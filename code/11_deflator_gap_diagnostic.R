# 11_deflator_gap_diagnostic -- recompute selected real-wage percentiles under PCE vs CPI-U-RS to quantify the deflator gap
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

rm(list = ls())
options(scipen = 999)
set.seed(42)

# Sourced by run_all.R inside new.env(parent = globalenv()).
#
# This script measures the ISOLATED deflator effect: it re-deflates the
# SAME nominal hourly wages with both the production PCE series and the
# shadow CPI-U-RS series, both rebased to a common reference year, holding
# the rest of the pipeline fixed, then compares weighted percentiles cell
# by cell. This is DISTINCT from the W10 spot-check (10_epi_spot_checks.R),
# which reconciles the full EIG figure against EPI's published (CPI-U-RS)
# values; that net reconciliation is about -2.25 percent at the 1990 P50
# and is what corresponds to Decision 01's "~2 points." The isolated
# deflator gap measured here is larger (about -8.6 percent at the 1990 P50,
# to 2019) because the full reconciliation partly offsets the deflator with
# EPI's topcode/allocation conventions and a later (2025) horizon.
#
# Reference year: the LATEST calendar year present in BOTH series. The
# vendored CPI-U-RS file is annual and currently ends well short of the PCE
# series (it does not extend to 2025), so the reference resolves to the
# last available CPI-U-RS year rather than to 2025. The reported gap is the
# cumulative PCE-vs-CPI-U-RS divergence from each cell's year through that
# reference year. Putting both series on one reference year removes any
# base-period artifact, so the gap reflects only the PCE-vs-CPI-U-RS
# difference. Levels therefore differ from the production Dec-2025 figures;
# the diagnostic value is the gap between the two columns, not their level.
#
# Cells mirror 10_epi_spot_checks.R: 1990 P50, 2010 P50, 2023 P90. Any cell
# whose year is outside the CPI-U-RS coverage is reported as NA for the
# CPI-U-RS comparison rather than computed.
#
# Weighted-percentile construction matches figure_a_percentiles.R: sort
# within year by the real wage, cumulate EARNWT, pick the smallest value
# whose cumulative weight is at least p * total weight.
#
# No custom functions are defined; all transformations are inline.

source(here::here("code", "_utils", "00_packages.R"))

###################################
###   Configuration             ###
###################################

panel_in_dir_chr      <- here::here("data", "intermediate", "cps_real_wages")
deflator_dir_chr      <- here::here("data", "fred", "deflators")
deflator_manifest_chr <- fs::path(deflator_dir_chr, "_manifest.csv")
out_dir_chr           <- here::here("data", "intermediate")
out_csv_chr           <- fs::path(out_dir_chr, "deflator_gap_diagnostic.csv")

# Cells to evaluate: (year, probability). Mirrors the EPI spot-check cells.
cells_ls <- list(
  list(id_chr = "1990_p50", year_int = 1990L, prob_num = 0.50),
  list(id_chr = "2010_p50", year_int = 2010L, prob_num = 0.50),
  list(id_chr = "2023_p90", year_int = 2023L, prob_num = 0.90)
)

# Verified 2026-06-04: the within-repo 1990-to-2019 PCE-vs-CPI-U-RS P50 gap
# is about 8.6 percent (the CPI-U-RS series ends in 2019). The band below
# brackets that with margin so the gate flags only gross deflator/series
# misconfiguration, not the expected divergence. Decision 01's "~2 points"
# is the separate W10 EIG-vs-EPI reconciliation (about -2.25 percent), not
# this isolated deflator gap; see decision_01's Verification note.
gap_1990_sanity_lower_pct_num <- 2.0
gap_1990_sanity_upper_pct_num <- 15.0

###################################
###   1) Load nominal panel     ###
###################################

if (!fs::dir_exists(panel_in_dir_chr)) {
  stop(
    "11_deflator_gap_diagnostic.R -- real-wage panel not found at ",
    panel_in_dir_chr, ". Run 02a_build_real_wages.R first."
  )
}

parquet_paths_chr <- fs::dir_ls(
  panel_in_dir_chr, regexp = "part-0\\.parquet$", recurse = TRUE, type = "file"
)

if (length(parquet_paths_chr) == 0L) {
  stop(
    "11_deflator_gap_diagnostic.R -- no part-0.parquet files under ",
    panel_in_dir_chr, ". Run 02a_build_real_wages.R first."
  )
}

panel_df <- arrow::open_dataset(parquet_paths_chr, format = "parquet") |>
  dplyr::select(YEAR, MONTH, EARNWT, nominal_hourly_wage_num) |>
  dplyr::collect()

required_cols_chr <- c("YEAR", "MONTH", "EARNWT", "nominal_hourly_wage_num")
missing_cols_chr  <- setdiff(required_cols_chr, names(panel_df))
if (length(missing_cols_chr) > 0L) {
  stop(
    "11_deflator_gap_diagnostic.R -- panel missing column(s): ",
    paste(missing_cols_chr, collapse = ", "),
    ". The nominal hourly wage is required to re-deflate."
  )
}

###################################
###   2) Resolve deflator paths ###
###################################

if (!fs::file_exists(deflator_manifest_chr)) {
  stop(
    "11_deflator_gap_diagnostic.R -- deflator manifest not found at ",
    deflator_manifest_chr, ". Run code/_utils/download_deflators.R first."
  )
}

manifest_df <- readr::read_csv(deflator_manifest_chr, show_col_types = FALSE)

# Recorded paths are resolved by file name inside deflator_dir_chr, so the
# project can live anywhere on disk.
pcepi_path_chr <- fs::path(deflator_dir_chr, fs::path_file(
  manifest_df$out_parquet_path_chr[manifest_df$deflator_key_chr == "pcepi"]
))
cpiurs_path_chr <- fs::path(deflator_dir_chr, fs::path_file(
  manifest_df$out_parquet_path_chr[manifest_df$deflator_key_chr == "cpiurs"]
))

if (length(pcepi_path_chr) != 1L || !fs::file_exists(pcepi_path_chr)) {
  stop("11_deflator_gap_diagnostic.R -- PCEPI parquet missing or ambiguous in manifest.")
}
if (length(cpiurs_path_chr) != 1L || !fs::file_exists(cpiurs_path_chr)) {
  stop("11_deflator_gap_diagnostic.R -- CPI-U-RS parquet missing or ambiguous in manifest.")
}

###################################
###   3) Common reference year  ###
###################################
# Resolve the reference year as the latest year present in BOTH series,
# then rebase each series to that year (PCE to the year's monthly mean,
# CPI-U-RS to the year's annual value). This is robust to the CPI-U-RS
# file ending short of 2025.

pcepi_df  <- arrow::read_parquet(pcepi_path_chr)
cpiurs_df <- arrow::read_parquet(cpiurs_path_chr)

pcepi_years_int  <- sort(unique(pcepi_df$year_int))
cpiurs_years_int <- sort(unique(cpiurs_df$year_int))
common_years_int <- intersect(pcepi_years_int, cpiurs_years_int)

if (length(common_years_int) == 0L) {
  stop("11_deflator_gap_diagnostic.R -- PCE and CPI-U-RS series share no common year.")
}

ref_year_int <- max(common_years_int)

message(
  "11_deflator_gap_diagnostic.R -- CPI-U-RS coverage ",
  min(cpiurs_years_int), "-", max(cpiurs_years_int),
  "; PCE coverage ", min(pcepi_years_int), "-", max(pcepi_years_int),
  "; common reference year used = ", ref_year_int,
  if (ref_year_int < 2025L) {
    " (NOTE: CPI-U-RS does not extend to 2025; gap is measured through this earlier year)."
  } else {
    "."
  }
)

# PCE: rebase to the reference-year monthly mean.
pcepi_ref_mean_num <- mean(
  pcepi_df$index_monthly_num[pcepi_df$year_int == ref_year_int], na.rm = TRUE
)
if (!is.finite(pcepi_ref_mean_num) || pcepi_ref_mean_num <= 0) {
  stop("11_deflator_gap_diagnostic.R -- PCEPI reference-year mean is missing or non-positive.")
}
pcepi_join_df <- pcepi_df |>
  dplyr::transmute(
    YEAR  = as.integer(year_int),
    MONTH = as.integer(month_int),
    pce_ref_base = index_monthly_num / pcepi_ref_mean_num
  )

# CPI-U-RS: rebase to the reference-year annual value.
cpiurs_ref_val_num <- cpiurs_df$index_annual_num[cpiurs_df$year_int == ref_year_int]
if (length(cpiurs_ref_val_num) != 1L ||
    !is.finite(cpiurs_ref_val_num) || cpiurs_ref_val_num <= 0) {
  stop("11_deflator_gap_diagnostic.R -- CPI-U-RS reference-year value is missing or non-positive.")
}
cpiurs_join_df <- cpiurs_df |>
  dplyr::transmute(
    YEAR = as.integer(year_int),
    cpiurs_ref_base = index_annual_num / cpiurs_ref_val_num
  )

###################################
###   4) Re-deflate both ways   ###
###################################

panel_df <- panel_df |>
  dplyr::left_join(pcepi_join_df,  by = c("YEAR", "MONTH")) |>
  dplyr::left_join(cpiurs_join_df, by = "YEAR") |>
  dplyr::mutate(
    real_pce_num    = nominal_hourly_wage_num / pce_ref_base,
    real_cpiurs_num = nominal_hourly_wage_num / cpiurs_ref_base
  )

###################################
###   5) Weighted percentiles   ###
###################################

results_df <- tibble::tibble(
  id_chr           = character(0),
  year_int         = integer(0),
  prob_num         = numeric(0),
  ref_year_int     = integer(0),
  n_cell_int       = integer(0),
  real_pce_num     = numeric(0),
  real_cpiurs_num  = numeric(0),
  gap_abs_num      = numeric(0),
  gap_pct_num      = numeric(0)
)

for (cell_ls in cells_ls) {
  cell_bool <- panel_df$YEAR == cell_ls$year_int &
    !is.na(panel_df$EARNWT) & panel_df$EARNWT > 0 &
    !is.na(panel_df$real_pce_num) & !is.na(panel_df$real_cpiurs_num)

  if (sum(cell_bool) == 0L) {
    message(
      "11_deflator_gap_diagnostic.R -- ", cell_ls$id_chr,
      ": zero valid rows under BOTH deflators (likely outside CPI-U-RS ",
      "coverage through ", max(cpiurs_years_int), "); recording NA."
    )
    results_df <- dplyr::bind_rows(results_df, tibble::tibble(
      id_chr = cell_ls$id_chr, year_int = cell_ls$year_int,
      prob_num = cell_ls$prob_num, ref_year_int = ref_year_int, n_cell_int = 0L,
      real_pce_num = NA_real_, real_cpiurs_num = NA_real_,
      gap_abs_num = NA_real_, gap_pct_num = NA_real_
    ))
    next
  }

  cell_df <- panel_df[cell_bool, , drop = FALSE]

  # PCE weighted percentile.
  ord_pce_int   <- order(cell_df$real_pce_num)
  w_pce_num     <- cell_df$real_pce_num[ord_pce_int]
  wt_pce_num    <- cell_df$EARNWT[ord_pce_int]
  cum_pce_num   <- cumsum(wt_pce_num)
  val_pce_num   <- w_pce_num[which(cum_pce_num >= cell_ls$prob_num * sum(wt_pce_num))[1]]

  # CPI-U-RS weighted percentile.
  ord_rs_int    <- order(cell_df$real_cpiurs_num)
  w_rs_num      <- cell_df$real_cpiurs_num[ord_rs_int]
  wt_rs_num     <- cell_df$EARNWT[ord_rs_int]
  cum_rs_num    <- cumsum(wt_rs_num)
  val_rs_num    <- w_rs_num[which(cum_rs_num >= cell_ls$prob_num * sum(wt_rs_num))[1]]

  gap_abs_num <- val_pce_num - val_rs_num
  gap_pct_num <- 100 * (val_pce_num - val_rs_num) / val_rs_num

  results_df <- dplyr::bind_rows(results_df, tibble::tibble(
    id_chr = cell_ls$id_chr, year_int = cell_ls$year_int,
    prob_num = cell_ls$prob_num, ref_year_int = ref_year_int,
    n_cell_int = as.integer(nrow(cell_df)),
    real_pce_num = val_pce_num, real_cpiurs_num = val_rs_num,
    gap_abs_num = gap_abs_num, gap_pct_num = gap_pct_num
  ))

  message(
    "11_deflator_gap_diagnostic.R -- ", cell_ls$id_chr, " (n=",
    format(nrow(cell_df), big.mark = ","), ", ref ", ref_year_int, "): PCE $",
    format(round(val_pce_num, 2), nsmall = 2L), "/hr vs CPI-U-RS $",
    format(round(val_rs_num, 2), nsmall = 2L), "/hr; gap ",
    format(round(gap_pct_num, 2), nsmall = 2L), "%"
  )
}

fs::dir_create(out_dir_chr, recurse = TRUE)
readr::write_csv(results_df, out_csv_chr)

###################################
###   6) Sanity gate on 1990    ###
###################################
# Confirm the recomputed 1990 P50 gap is in the plausible band the memo
# implies. A value outside [0.5, 6.0] percent means the memo's "~2 points"
# claim no longer matches the pipeline and Decision 01 needs revisiting.

gap_1990_pct_num <- results_df$gap_pct_num[results_df$id_chr == "1990_p50"]

if (length(gap_1990_pct_num) == 1L && !is.na(gap_1990_pct_num)) {
  if (abs(gap_1990_pct_num) < gap_1990_sanity_lower_pct_num ||
      abs(gap_1990_pct_num) > gap_1990_sanity_upper_pct_num) {
    message(
      "11_deflator_gap_diagnostic.R -- WARNING: recomputed 1990 P50 ",
      "PCE-vs-CPI-U-RS gap is ",
      format(round(gap_1990_pct_num, 2), nsmall = 2L),
      "% (through reference year ", ref_year_int,
      "), outside the [", gap_1990_sanity_lower_pct_num, ", ",
      gap_1990_sanity_upper_pct_num, "] percent band expected for the ",
      "1990-to-reference PCE-vs-CPI-U-RS divergence. Investigate the ",
      "deflator series (note CPI-U-RS coverage) before relying on this run."
    )
  } else {
    message(
      "11_deflator_gap_diagnostic.R -- 1990 P50 PCE-vs-CPI-U-RS gap = ",
      format(round(gap_1990_pct_num, 2), nsmall = 2L),
      "% (through reference year ", ref_year_int,
      "), consistent with the expected 1990-to-reference PCE-vs-CPI-U-RS ",
      "divergence."
    )
  }
}

message(
  "11_deflator_gap_diagnostic.R -- diagnostic written: ", out_csv_chr,
  " (", nrow(results_df), " cells)."
)
message("11_deflator_gap_diagnostic.R -- done.")
