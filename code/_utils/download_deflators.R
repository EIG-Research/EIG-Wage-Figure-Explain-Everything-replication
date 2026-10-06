# download_deflators -- pull PCEPI, C-CPI-U, CPI-U SA, CPI-U NSA monthly from FRED and CPI-U-RS annual from a vendored BLS XLSX; rebase the monthly series so December 2025 = 1 and the annual series so the 2025 annual value = 1
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

rm(list = ls())
options(scipen = 999)
set.seed(42)

# Sourced by run_all.R inside new.env(parent = globalenv()).
#
# Pulls five inflation series and writes parquet deflator files under
# data/fred/deflators/. The four FRED monthly series are
# written at (year, month) granularity rebased so December 2025 = 1;
# CPI-U-RS is annual-only (BLS publishes no monthly variant) and
# rebased so the 2025 annual value = 1.
#
#   pcepi_dec2025_base.parquet        (production primary, monthly)
#   cpiurs_2025annual_base.parquet    (shadow; annual)
#   ccpiu_dec2025_base.parquet        (shadow; monthly)
#   cpiu_sa_dec2025_base.parquet      (shadow; monthly)
#   cpiu_nsa_dec2025_base.parquet     (shadow; monthly)
#
# PCEPI is the production primary deflator
# (docs/decisions/decision_01_pce_deflator.md). The other four
# series are retained as shadows for sensitivity comparisons.
#
# Source mix:
#   PCEPI, C-CPI-U, CPI-U SA, CPI-U NSA  -- pulled from FRED via fredr.
#   R-CPI-U-RS                           -- read from vendored BLS XLSX
#       at data/allitems.xlsx. FRED retired CPIURSEXP and BLS blocks
#       scripted HTTP fetches with 403; the file is small (~14 KB) and
#       updates roughly once a year, so it is vendored.
#
# FRED API key: fredr reads FRED_API_KEY from the environment. Missing
# key triggers a named error before any pull.
#
# No custom functions are defined; all five series pulls are inline.

source(here::here("code", "_utils", "00_packages.R"))

###################################
###   Configuration             ###
###################################

out_dir_chr <- here::here("data", "fred", "deflators")
fs::dir_create(out_dir_chr, recurse = TRUE)

# FRED series IDs
#   PCEPI       Personal Consumption Expenditures: Chain-type Price Index
#               (BEA, monthly). 2017 = 100 in FRED; we rebase to 2025 = 1.
#   SUUR0000SA0 Chained Consumer Price Index for All Urban Consumers, All
#               items, not seasonally adjusted (BLS C-CPI-U, monthly).
#   CPIAUCSL    Consumer Price Index for All Urban Consumers, All Items in
#               U.S. City Average, seasonally adjusted (BLS CPI-U SA, monthly).
#   CPIAUCNS    Consumer Price Index for All Urban Consumers, All Items in
#               U.S. City Average, not seasonally adjusted (BLS CPI-U NSA, monthly).
fred_series_chr <- c(
  pcepi    = "PCEPI",
  ccpiu    = "SUUR0000SA0",
  cpiu_sa  = "CPIAUCSL",
  cpiu_nsa = "CPIAUCNS"
)

# R-CPI-U-RS (Consumer Price Index Research Retroactive Series using
# Current Methods) source file. Canonical filename is "allitems.xlsx".
# Provenance for data/allitems.xlsx:
#   Source URL   : https://www.bls.gov/cpi/research-series/allitems.xlsx
#   Landing page : https://www.bls.gov/cpi/research-series/home.htm
#   Downloaded by: Ben Glasner
#   Downloaded on: 2026-04-22
# To refresh: replace data/allitems.xlsx with the latest file from the
# URL above, rerun this script, and update
# bls_cpiurs_downloaded_on_chr below.
bls_cpiurs_url_chr           <- "https://www.bls.gov/cpi/research-series/allitems.xlsx"
bls_cpiurs_downloaded_on_chr <- "2026-04-22"
cpiurs_raw_path_chr          <- here::here("data", "allitems.xlsx")

# Pull from 1979 forward so the 1982-start panel is fully covered with
# three years of lead for lag-window diagnostics.
series_start_date <- as.Date("1979-01-01")

# Rebase target: monthly series must equal 1 at December 2025. Annual
# CPI-U-RS rebases to the 2025 annual value (no monthly analog).
rebase_target_year_int  <- 2025L
rebase_target_month_int <- 12L

# Required minimum coverage for the downstream pipeline: all months from
# January 1982 through December of the rebase target year must be present
# in the primary monthly series (PCEPI).
required_start_year_int <- 1982L

###################################
###   1) FRED API key guard     ###
###################################

fred_key_chr <- Sys.getenv("FRED_API_KEY")

if (!nzchar(fred_key_chr)) {
  stop(
    "download_deflators.R -- FRED_API_KEY environment variable is not set. ",
    "Obtain a free key from https://fred.stlouisfed.org/docs/api/api_key.html ",
    "and set it in your .Renviron or via Sys.setenv(FRED_API_KEY = '...') ",
    "before sourcing this script."
  )
}

fredr::fredr_set_key(fred_key_chr)

message(
  "download_deflators.R -- FRED key registered; pulling four FRED series ",
  "(PCEPI, C-CPI-U, CPI-U SA, CPI-U NSA) plus CPI-U-RS from vendored ",
  "BLS XLSX at ", cpiurs_raw_path_chr, "."
)

###################################
###   2) Pull PCEPI (monthly)   ###
###################################

pcepi_raw_df <- tryCatch(
  fredr::fredr(
    series_id         = fred_series_chr[["pcepi"]],
    observation_start = series_start_date
  ),
  error = function(e) {
    stop(
      "download_deflators.R -- failed to pull PCEPI from FRED: ",
      conditionMessage(e)
    )
  }
)

message(
  "download_deflators.R -- PCEPI pulled: ",
  nrow(pcepi_raw_df), " monthly observations (",
  format(min(pcepi_raw_df$date)), " to ",
  format(max(pcepi_raw_df$date)), ")"
)

###################################
###   3) Read CPI-U-RS (BLS XLSX) ##
###################################
# FRED retired the CPIURSEXP series. BLS still publishes R-CPI-U-RS as an
# annual XLSX but returns 403 Forbidden on scripted requests, so the file is
# vendored in the repo at data/allitems.xlsx. See the provenance comment
# block above for download source and refresh instructions.
#
# The BLS file is already annual; no monthly-to-annual aggregation is needed.
# Step 3 locates the "YEAR" header row programmatically (there are a few
# title and note rows above the header), re-reads with the correct skip,
# identifies the annual-average column, and emits a tidy two-column data
# frame mirroring what the other annualized series produce in step 7.

if (!fs::file_exists(cpiurs_raw_path_chr)) {
  stop(
    "download_deflators.R -- vendored BLS CPI-U-RS file not found at ",
    cpiurs_raw_path_chr,
    ". Download the latest R-CPI-U-RS 'all items' XLSX from ",
    bls_cpiurs_url_chr,
    " (landing page: https://www.bls.gov/cpi/research-series/home.htm) ",
    "and save it to data/allitems.xlsx, then rerun this script."
  )
}

# Probe read: no column names, everything as text, to locate the header row.
cpiurs_probe_df <- readxl::read_excel(
  path      = cpiurs_raw_path_chr,
  col_names = FALSE,
  col_types = "text"
)

cpiurs_header_candidate_int <- which(
  toupper(trimws(as.character(cpiurs_probe_df[[1]]))) == "YEAR"
)

if (length(cpiurs_header_candidate_int) != 1L) {
  stop(
    "download_deflators.R -- could not locate a unique 'YEAR' header row in ",
    "the BLS CPI-U-RS XLSX (found ", length(cpiurs_header_candidate_int),
    " candidates). The BLS file format may have changed; inspect ",
    cpiurs_raw_path_chr, " and update the parse step."
  )
}

cpiurs_header_row_int <- cpiurs_header_candidate_int[[1]]

# Re-read with the identified header row as column names.
cpiurs_raw_df <- readxl::read_excel(
  path      = cpiurs_raw_path_chr,
  skip      = cpiurs_header_row_int - 1L,
  col_types = "text"
)

# Match the annual-average column case-insensitively. BLS has historically
# labeled it "AVG"; current versions may use "Annual Avg" or similar.
cpiurs_annual_col_candidates_chr <- names(cpiurs_raw_df)[
  grepl("AVG|ANNUAL", toupper(names(cpiurs_raw_df)))
]

if (length(cpiurs_annual_col_candidates_chr) < 1L) {
  stop(
    "download_deflators.R -- could not locate an annual-average column in ",
    "the BLS CPI-U-RS XLSX. Columns found: ",
    paste(names(cpiurs_raw_df), collapse = ", "),
    ". The BLS file format may have changed; update the parse step."
  )
}

cpiurs_annual_col_chr <- cpiurs_annual_col_candidates_chr[[1]]
cpiurs_year_col_chr   <- names(cpiurs_raw_df)[[1]]

cpiurs_annual_df <- cpiurs_raw_df |>
  dplyr::transmute(
    year_int         = suppressWarnings(
      as.integer(trimws(.data[[cpiurs_year_col_chr]]))
    ),
    index_annual_num = suppressWarnings(
      as.numeric(trimws(.data[[cpiurs_annual_col_chr]]))
    )
  ) |>
  dplyr::filter(
    !is.na(year_int),
    year_int >= 1970L,
    year_int <= 2100L,
    !is.na(index_annual_num)
  ) |>
  dplyr::arrange(year_int)

if (nrow(cpiurs_annual_df) == 0L) {
  stop(
    "download_deflators.R -- parsed BLS CPI-U-RS XLSX produced zero annual ",
    "observations. Inspect ", cpiurs_raw_path_chr, " manually."
  )
}

message(
  "download_deflators.R -- CPI-U-RS read from vendored BLS XLSX (downloaded ",
  bls_cpiurs_downloaded_on_chr, "): ",
  nrow(cpiurs_annual_df), " annual observations (",
  min(cpiurs_annual_df$year_int), "-",
  max(cpiurs_annual_df$year_int), "); annual column: '",
  cpiurs_annual_col_chr, "'"
)

###################################
###   4) Pull C-CPI-U (monthly) ###
###################################

ccpiu_raw_df <- tryCatch(
  fredr::fredr(
    series_id         = fred_series_chr[["ccpiu"]],
    observation_start = series_start_date
  ),
  error = function(e) {
    stop(
      "download_deflators.R -- failed to pull C-CPI-U (SUUR0000SA0) from FRED: ",
      conditionMessage(e)
    )
  }
)

message(
  "download_deflators.R -- C-CPI-U pulled: ",
  nrow(ccpiu_raw_df), " monthly observations (",
  format(min(ccpiu_raw_df$date)), " to ",
  format(max(ccpiu_raw_df$date)), ")"
)

###################################
###   5) Pull CPI-U SA (monthly)###
###################################

cpiu_sa_raw_df <- tryCatch(
  fredr::fredr(
    series_id         = fred_series_chr[["cpiu_sa"]],
    observation_start = series_start_date
  ),
  error = function(e) {
    stop(
      "download_deflators.R -- failed to pull CPI-U SA (CPIAUCSL) from FRED: ",
      conditionMessage(e)
    )
  }
)

message(
  "download_deflators.R -- CPI-U SA pulled: ",
  nrow(cpiu_sa_raw_df), " monthly observations (",
  format(min(cpiu_sa_raw_df$date)), " to ",
  format(max(cpiu_sa_raw_df$date)), ")"
)

###################################
###   6) Pull CPI-U NSA (monthly)###
###################################

cpiu_nsa_raw_df <- tryCatch(
  fredr::fredr(
    series_id         = fred_series_chr[["cpiu_nsa"]],
    observation_start = series_start_date
  ),
  error = function(e) {
    stop(
      "download_deflators.R -- failed to pull CPI-U NSA (CPIAUCNS) from FRED: ",
      conditionMessage(e)
    )
  }
)

message(
  "download_deflators.R -- CPI-U NSA pulled: ",
  nrow(cpiu_nsa_raw_df), " monthly observations (",
  format(min(cpiu_nsa_raw_df$date)), " to ",
  format(max(cpiu_nsa_raw_df$date)), ")"
)

###################################
###   7) Monthly frames         ###
###################################
# Build monthly-granular data frames for the four FRED series. Every
# published month is retained so 02a can link the CPS panel at
# (YEAR, MONTH). CPI-U-RS stays annual (no monthly variant published)
# and is carried in `cpiurs_annual_df` from step 3.

pcepi_monthly_df <- pcepi_raw_df |>
  dplyr::transmute(
    date             = date,
    year_int         = as.integer(lubridate::year(date)),
    month_int        = as.integer(lubridate::month(date)),
    index_monthly_num = value
  ) |>
  dplyr::filter(!is.na(index_monthly_num)) |>
  dplyr::arrange(year_int, month_int)

ccpiu_monthly_df <- ccpiu_raw_df |>
  dplyr::transmute(
    date             = date,
    year_int         = as.integer(lubridate::year(date)),
    month_int        = as.integer(lubridate::month(date)),
    index_monthly_num = value
  ) |>
  dplyr::filter(!is.na(index_monthly_num)) |>
  dplyr::arrange(year_int, month_int)

cpiu_sa_monthly_df <- cpiu_sa_raw_df |>
  dplyr::transmute(
    date             = date,
    year_int         = as.integer(lubridate::year(date)),
    month_int        = as.integer(lubridate::month(date)),
    index_monthly_num = value
  ) |>
  dplyr::filter(!is.na(index_monthly_num)) |>
  dplyr::arrange(year_int, month_int)

cpiu_nsa_monthly_df <- cpiu_nsa_raw_df |>
  dplyr::transmute(
    date             = date,
    year_int         = as.integer(lubridate::year(date)),
    month_int        = as.integer(lubridate::month(date)),
    index_monthly_num = value
  ) |>
  dplyr::filter(!is.na(index_monthly_num)) |>
  dplyr::arrange(year_int, month_int)

message(
  "download_deflators.R -- monthly series built; month coverage: ",
  "PCEPI ",
  format(min(pcepi_monthly_df$date)), " to ", format(max(pcepi_monthly_df$date)),
  " (", nrow(pcepi_monthly_df), " obs); C-CPI-U ",
  format(min(ccpiu_monthly_df$date)), " to ", format(max(ccpiu_monthly_df$date)),
  " (", nrow(ccpiu_monthly_df), " obs); CPI-U SA ",
  format(min(cpiu_sa_monthly_df$date)), " to ",
  format(max(cpiu_sa_monthly_df$date)),
  " (", nrow(cpiu_sa_monthly_df), " obs); CPI-U NSA ",
  format(min(cpiu_nsa_monthly_df$date)), " to ",
  format(max(cpiu_nsa_monthly_df$date)),
  " (", nrow(cpiu_nsa_monthly_df), " obs). CPI-U-RS (annual): ",
  min(cpiurs_annual_df$year_int), " to ", max(cpiurs_annual_df$year_int),
  " (", nrow(cpiurs_annual_df), " obs)."
)

###################################
###   8) Rebase to Dec 2025 = 1 ###
###################################
# Monthly series: divide every monthly value by the December 2025 value.
# PCEPI (primary) must have December 2025; halt if missing. Shadow
# monthly series allow fallback to the most recent available month with
# a visible log line.
# CPI-U-RS remains rebased to the 2025 annual value (no monthly granularity).

# PCEPI: primary. Must have December 2025.
pcepi_rebase_val_num <- pcepi_monthly_df$index_monthly_num[
  pcepi_monthly_df$year_int == rebase_target_year_int &
    pcepi_monthly_df$month_int == rebase_target_month_int
]
pcepi_rebase_year_used_int  <- rebase_target_year_int
pcepi_rebase_month_used_int <- rebase_target_month_int

if (length(pcepi_rebase_val_num) != 1L) {
  stop(
    "download_deflators.R -- PCEPI ",
    sprintf("%04d-%02d", rebase_target_year_int, rebase_target_month_int),
    " monthly value is missing. The primary deflator requires this ",
    "month for the December-2025 rebase; rerun after FRED publishes ",
    "it, or adjust rebase_target_year_int / rebase_target_month_int."
  )
}

pcepi_monthly_df$pcepi_dec2025_base <-
  pcepi_monthly_df$index_monthly_num / pcepi_rebase_val_num

# Helper-free monthly rebase for each shadow series, with latest-month
# fallback when the December target month is not yet published.

# C-CPI-U: shadow.
ccpiu_target_mask_bool <- ccpiu_monthly_df$year_int == rebase_target_year_int &
  ccpiu_monthly_df$month_int == rebase_target_month_int
ccpiu_rebase_val_num <- ccpiu_monthly_df$index_monthly_num[
  ccpiu_target_mask_bool
]
ccpiu_rebase_year_used_int  <- rebase_target_year_int
ccpiu_rebase_month_used_int <- rebase_target_month_int

if (length(ccpiu_rebase_val_num) != 1L) {
  # Fall back to the most recent available month.
  ccpiu_latest_idx <- which.max(ccpiu_monthly_df$date)
  ccpiu_rebase_val_num        <- ccpiu_monthly_df$index_monthly_num[ccpiu_latest_idx]
  ccpiu_rebase_year_used_int  <- ccpiu_monthly_df$year_int[ccpiu_latest_idx]
  ccpiu_rebase_month_used_int <- ccpiu_monthly_df$month_int[ccpiu_latest_idx]
  message(
    "download_deflators.R -- C-CPI-U ",
    sprintf("%04d-%02d", rebase_target_year_int, rebase_target_month_int),
    " not yet published; falling back to ",
    sprintf("%04d-%02d",
            ccpiu_rebase_year_used_int, ccpiu_rebase_month_used_int),
    " for rebase base."
  )
}

ccpiu_monthly_df$ccpiu_dec2025_base <-
  ccpiu_monthly_df$index_monthly_num / ccpiu_rebase_val_num

# CPI-U SA: shadow.
cpiu_sa_target_mask_bool <- cpiu_sa_monthly_df$year_int == rebase_target_year_int &
  cpiu_sa_monthly_df$month_int == rebase_target_month_int
cpiu_sa_rebase_val_num <- cpiu_sa_monthly_df$index_monthly_num[
  cpiu_sa_target_mask_bool
]
cpiu_sa_rebase_year_used_int  <- rebase_target_year_int
cpiu_sa_rebase_month_used_int <- rebase_target_month_int

if (length(cpiu_sa_rebase_val_num) != 1L) {
  cpiu_sa_latest_idx <- which.max(cpiu_sa_monthly_df$date)
  cpiu_sa_rebase_val_num        <- cpiu_sa_monthly_df$index_monthly_num[cpiu_sa_latest_idx]
  cpiu_sa_rebase_year_used_int  <- cpiu_sa_monthly_df$year_int[cpiu_sa_latest_idx]
  cpiu_sa_rebase_month_used_int <- cpiu_sa_monthly_df$month_int[cpiu_sa_latest_idx]
  message(
    "download_deflators.R -- CPI-U SA ",
    sprintf("%04d-%02d", rebase_target_year_int, rebase_target_month_int),
    " not yet published; falling back to ",
    sprintf("%04d-%02d",
            cpiu_sa_rebase_year_used_int, cpiu_sa_rebase_month_used_int),
    " for rebase base."
  )
}

cpiu_sa_monthly_df$cpiu_sa_dec2025_base <-
  cpiu_sa_monthly_df$index_monthly_num / cpiu_sa_rebase_val_num

# CPI-U NSA: shadow.
cpiu_nsa_target_mask_bool <- cpiu_nsa_monthly_df$year_int == rebase_target_year_int &
  cpiu_nsa_monthly_df$month_int == rebase_target_month_int
cpiu_nsa_rebase_val_num <- cpiu_nsa_monthly_df$index_monthly_num[
  cpiu_nsa_target_mask_bool
]
cpiu_nsa_rebase_year_used_int  <- rebase_target_year_int
cpiu_nsa_rebase_month_used_int <- rebase_target_month_int

if (length(cpiu_nsa_rebase_val_num) != 1L) {
  cpiu_nsa_latest_idx <- which.max(cpiu_nsa_monthly_df$date)
  cpiu_nsa_rebase_val_num        <- cpiu_nsa_monthly_df$index_monthly_num[cpiu_nsa_latest_idx]
  cpiu_nsa_rebase_year_used_int  <- cpiu_nsa_monthly_df$year_int[cpiu_nsa_latest_idx]
  cpiu_nsa_rebase_month_used_int <- cpiu_nsa_monthly_df$month_int[cpiu_nsa_latest_idx]
  message(
    "download_deflators.R -- CPI-U NSA ",
    sprintf("%04d-%02d", rebase_target_year_int, rebase_target_month_int),
    " not yet published; falling back to ",
    sprintf("%04d-%02d",
            cpiu_nsa_rebase_year_used_int, cpiu_nsa_rebase_month_used_int),
    " for rebase base."
  )
}

cpiu_nsa_monthly_df$cpiu_nsa_dec2025_base <-
  cpiu_nsa_monthly_df$index_monthly_num / cpiu_nsa_rebase_val_num

# CPI-U-RS: annual shadow. BLS does not publish it monthly; rebase to
# the 2025 annual value with latest-year fallback.
cpiurs_rebase_val_num <- cpiurs_annual_df$index_annual_num[
  cpiurs_annual_df$year_int == rebase_target_year_int
]
cpiurs_rebase_year_used_int <- rebase_target_year_int

if (length(cpiurs_rebase_val_num) != 1L) {
  cpiurs_rebase_year_used_int <- max(cpiurs_annual_df$year_int)
  cpiurs_rebase_val_num <- cpiurs_annual_df$index_annual_num[
    cpiurs_annual_df$year_int == cpiurs_rebase_year_used_int
  ]
  message(
    "download_deflators.R -- CPI-U-RS ", rebase_target_year_int,
    " not yet published; falling back to ", cpiurs_rebase_year_used_int,
    " for annual rebase base."
  )
}

cpiurs_annual_df$cpiurs_2025annual_base <-
  cpiurs_annual_df$index_annual_num / cpiurs_rebase_val_num

###################################
###   9) Coverage verification  ###
###################################
# PCEPI verification:
#   - Dec 2025 rebased value equals 1 to FP tolerance.
#   - Every (year, month) from Jan 1982 through Dec 2025 is present in
#     the monthly series. This is the coverage guaranteed to be
#     required by 02a's (YEAR, MONTH) join across the CPS ORG panel.
#   - No NA rebased values anywhere.

pcepi_dec2025_check_num <- pcepi_monthly_df$pcepi_dec2025_base[
  pcepi_monthly_df$year_int == rebase_target_year_int &
    pcepi_monthly_df$month_int == rebase_target_month_int
]

if (abs(pcepi_dec2025_check_num - 1) > 1e-9) {
  stop(
    "download_deflators.R -- PCEPI Dec ", rebase_target_year_int,
    " rebased value is ", format(pcepi_dec2025_check_num, digits = 15),
    "; expected 1 within 1e-9 floating-point tolerance."
  )
}

# Build the (year, month) grid that must be covered.
required_grid_df <- tidyr::expand_grid(
  year_int  = required_start_year_int:rebase_target_year_int,
  month_int = 1L:12L
)
pcepi_have_grid_df <- pcepi_monthly_df |>
  dplyr::select(year_int, month_int) |>
  dplyr::distinct()

pcepi_missing_grid_df <- dplyr::anti_join(
  required_grid_df, pcepi_have_grid_df, by = c("year_int", "month_int")
)

if (nrow(pcepi_missing_grid_df) > 0L) {
  missing_chr <- paste(
    sprintf("%04d-%02d",
            pcepi_missing_grid_df$year_int,
            pcepi_missing_grid_df$month_int),
    collapse = ", "
  )
  stop(
    "download_deflators.R -- PCEPI monthly series is missing required ",
    "(year, month) pair(s): ", missing_chr
  )
}

if (any(is.na(pcepi_monthly_df$pcepi_dec2025_base))) {
  stop("download_deflators.R -- PCEPI rebased series contains NA values.")
}
if (any(is.na(ccpiu_monthly_df$ccpiu_dec2025_base))) {
  stop("download_deflators.R -- C-CPI-U rebased series contains NA values.")
}
if (any(is.na(cpiu_sa_monthly_df$cpiu_sa_dec2025_base))) {
  stop("download_deflators.R -- CPI-U SA rebased series contains NA values.")
}
if (any(is.na(cpiu_nsa_monthly_df$cpiu_nsa_dec2025_base))) {
  stop("download_deflators.R -- CPI-U NSA rebased series contains NA values.")
}
if (any(is.na(cpiurs_annual_df$cpiurs_2025annual_base))) {
  stop("download_deflators.R -- CPI-U-RS rebased annual series contains NA values.")
}

message(
  "download_deflators.R -- verification PASS: PCEPI Dec ",
  rebase_target_year_int, "=",
  format(pcepi_dec2025_check_num, digits = 15),
  "; monthly coverage Jan ", required_start_year_int,
  " through Dec ", rebase_target_year_int,
  " complete (", nrow(required_grid_df), " months); no NA rows."
)

###################################
###  10) Write parquet + rds    ###
###################################

pcepi_out_path_chr    <- fs::path(out_dir_chr, "pcepi_dec2025_base.parquet")
cpiurs_out_path_chr   <- fs::path(out_dir_chr, "cpiurs_2025annual_base.parquet")
ccpiu_out_path_chr    <- fs::path(out_dir_chr, "ccpiu_dec2025_base.parquet")
cpiu_sa_out_path_chr  <- fs::path(out_dir_chr, "cpiu_sa_dec2025_base.parquet")
cpiu_nsa_out_path_chr <- fs::path(out_dir_chr, "cpiu_nsa_dec2025_base.parquet")

arrow::write_parquet(pcepi_monthly_df,    sink = pcepi_out_path_chr,    compression = "snappy")
arrow::write_parquet(cpiurs_annual_df,    sink = cpiurs_out_path_chr,   compression = "snappy")
arrow::write_parquet(ccpiu_monthly_df,    sink = ccpiu_out_path_chr,    compression = "snappy")
arrow::write_parquet(cpiu_sa_monthly_df,  sink = cpiu_sa_out_path_chr,  compression = "snappy")
arrow::write_parquet(cpiu_nsa_monthly_df, sink = cpiu_nsa_out_path_chr, compression = "snappy")

saveRDS(pcepi_monthly_df,
        file = fs::path(out_dir_chr, "pcepi_dec2025_base.rds"),    compress = "xz")
saveRDS(cpiurs_annual_df,
        file = fs::path(out_dir_chr, "cpiurs_2025annual_base.rds"), compress = "xz")
saveRDS(ccpiu_monthly_df,
        file = fs::path(out_dir_chr, "ccpiu_dec2025_base.rds"),    compress = "xz")
saveRDS(cpiu_sa_monthly_df,
        file = fs::path(out_dir_chr, "cpiu_sa_dec2025_base.rds"),  compress = "xz")
saveRDS(cpiu_nsa_monthly_df,
        file = fs::path(out_dir_chr, "cpiu_nsa_dec2025_base.rds"), compress = "xz")

# Delete stale 2025-annual-base artifacts from prior pipeline runs so
# readers cannot pick up the old schema.
stale_annual_paths_chr <- c(
  fs::path(out_dir_chr, "pcepi_2025_base.parquet"),
  fs::path(out_dir_chr, "pcepi_2025_base.rds"),
  fs::path(out_dir_chr, "ccpiu_2025_base.parquet"),
  fs::path(out_dir_chr, "ccpiu_2025_base.rds"),
  fs::path(out_dir_chr, "cpiu_sa_2025_base.parquet"),
  fs::path(out_dir_chr, "cpiu_sa_2025_base.rds"),
  fs::path(out_dir_chr, "cpiu_nsa_2025_base.parquet"),
  fs::path(out_dir_chr, "cpiu_nsa_2025_base.rds"),
  fs::path(out_dir_chr, "cpiurs_2025_base.parquet"),
  fs::path(out_dir_chr, "cpiurs_2025_base.rds")
)
stale_present_chr <- stale_annual_paths_chr[
  fs::file_exists(stale_annual_paths_chr)
]
if (length(stale_present_chr) > 0L) {
  fs::file_delete(stale_present_chr)
  message(
    "download_deflators.R -- removed ", length(stale_present_chr),
    " stale 2025-annual-base artifact(s) from ", out_dir_chr
  )
}

###################################
###  11) Manifest               ###
###################################

deflator_manifest_df <- tibble::tibble(
  deflator_key_chr       = c("pcepi", "cpiurs", "ccpiu", "cpiu_sa", "cpiu_nsa"),
  source_chr             = c(
    unname(fred_series_chr[["pcepi"]]),
    bls_cpiurs_url_chr,
    unname(fred_series_chr[["ccpiu"]]),
    unname(fred_series_chr[["cpiu_sa"]]),
    unname(fred_series_chr[["cpiu_nsa"]])
  ),
  role_chr               = c("primary", "shadow", "shadow", "shadow", "shadow"),
  frequency_chr          = c("monthly", "annual", "monthly", "monthly", "monthly"),
  base_period_chr        = c(
    "dec2025", "2025annual", "dec2025", "dec2025", "dec2025"
  ),
  rebase_year_int        = as.integer(c(
    pcepi_rebase_year_used_int,
    cpiurs_rebase_year_used_int,
    ccpiu_rebase_year_used_int,
    cpiu_sa_rebase_year_used_int,
    cpiu_nsa_rebase_year_used_int
  )),
  rebase_month_int       = as.integer(c(
    pcepi_rebase_month_used_int,
    NA_integer_,
    ccpiu_rebase_month_used_int,
    cpiu_sa_rebase_month_used_int,
    cpiu_nsa_rebase_month_used_int
  )),
  rebase_value_raw_num   = c(
    pcepi_rebase_val_num,
    cpiurs_rebase_val_num,
    ccpiu_rebase_val_num,
    cpiu_sa_rebase_val_num,
    cpiu_nsa_rebase_val_num
  ),
  coverage_min_chr       = c(
    format(min(pcepi_monthly_df$date)),
    paste0(min(cpiurs_annual_df$year_int), "-annual"),
    format(min(ccpiu_monthly_df$date)),
    format(min(cpiu_sa_monthly_df$date)),
    format(min(cpiu_nsa_monthly_df$date))
  ),
  coverage_max_chr       = c(
    format(max(pcepi_monthly_df$date)),
    paste0(max(cpiurs_annual_df$year_int), "-annual"),
    format(max(ccpiu_monthly_df$date)),
    format(max(cpiu_sa_monthly_df$date)),
    format(max(cpiu_nsa_monthly_df$date))
  ),
  # Project-relative, so the tracked manifest carries no machine path.
  out_parquet_path_chr   = as.character(fs::path_rel(c(
    pcepi_out_path_chr,
    cpiurs_out_path_chr,
    ccpiu_out_path_chr,
    cpiu_sa_out_path_chr,
    cpiu_nsa_out_path_chr
  ), start = here::here())),
  # ISO-8601 with explicit Z suffix for locale-independent parsing in 02a.
  pulled_at_utc_chr      = format(
    Sys.time(), format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"
  )
)

manifest_path_chr <- fs::path(out_dir_chr, "_manifest.csv")
readr::write_csv(deflator_manifest_df, manifest_path_chr)

message(
  "download_deflators.R -- wrote ", nrow(deflator_manifest_df),
  " deflator series (parquet + rds) and manifest to ", out_dir_chr
)

message("download_deflators.R -- done.")
