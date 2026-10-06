# download_unemployment -- pull UNRATE from FRED (full panel) and identify contiguous spells of months with unemployment below 5 percent
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

rm(list = ls())
options(scipen = 999)
set.seed(42)

# Sourced by run_all.R inside new.env(parent = globalenv()).
#
# Pulls the official BLS civilian unemployment rate (UNRATE, seasonally
# adjusted, monthly) from FRED for the full available panel and writes
# two artifacts under data/fred/unemployment/:
#
#   unrate_monthly.parquet        full monthly UNRATE series with a
#                                 below-5-percent flag, one row per month
#   unrate_below_5_spells.parquet one row per contiguous run of months
#                                 with the rate below 5 percent
#
# Series choice: UNRATE (seasonally adjusted), not UNRATENSA. SA matches
# the headline rate most commonly cited and is appropriate for
# business-cycle spell identification.
#
# Threshold: strict less-than (unrate_num < 5). A month at exactly 5.0
# percent is NOT in a low-unemployment spell.
#
# Spell boundaries: contiguous month-to-month runs of the flag. A missing
# month would split a spell; the continuity check below halts before that
# can arise.
#
# FRED API key: fredr reads FRED_API_KEY from the environment. Missing
# key triggers a named error before any pull.
#
# No custom functions are defined; the pull, shaping, and spell
# identification are all inline.

source(here::here("code", "_utils", "00_packages.R"))

###################################
###   Configuration             ###
###################################

out_dir_chr <- here::here("data", "fred", "unemployment")
fs::dir_create(out_dir_chr, recurse = TRUE)

# FRED series ID
#   UNRATE  Civilian Unemployment Rate (BLS, monthly, seasonally
#           adjusted). Native scale is percent; no rescaling applied.
fred_series_chr <- c(unrate = "UNRATE")

# Pull from 1948-01-01, the start of the full FRED history for UNRATE.
series_start_date <- as.Date("1948-01-01")

# Spell threshold, on UNRATE's native percent scale. Strict less-than.
threshold_num <- 5

###################################
###   1) FRED API key guard     ###
###################################

fred_key_chr <- Sys.getenv("FRED_API_KEY")

if (!nzchar(fred_key_chr)) {
  stop(
    "download_unemployment.R -- FRED_API_KEY environment variable is not set. ",
    "Obtain a free key from https://fred.stlouisfed.org/docs/api/api_key.html ",
    "and set it in your .Renviron or via Sys.setenv(FRED_API_KEY = '...') ",
    "before sourcing this script."
  )
}

fredr::fredr_set_key(fred_key_chr)

message(
  "download_unemployment.R -- FRED key registered; pulling UNRATE ",
  "(Civilian Unemployment Rate, SA, monthly) from ",
  format(series_start_date), "."
)

###################################
###   2) Pull UNRATE (monthly)  ###
###################################

unrate_raw_df <- tryCatch(
  fredr::fredr(
    series_id         = fred_series_chr[["unrate"]],
    observation_start = series_start_date
  ),
  error = function(e) {
    stop(
      "download_unemployment.R -- failed to pull UNRATE from FRED: ",
      conditionMessage(e)
    )
  }
)

message(
  "download_unemployment.R -- UNRATE pulled: ",
  nrow(unrate_raw_df), " monthly observations (",
  format(min(unrate_raw_df$date)), " to ",
  format(max(unrate_raw_df$date)), ")"
)

###################################
###   3) Shape monthly frame    ###
###################################
# Native FRED percent scale retained; FRED dates are first-of-month.
# Rows with NA in unrate_num are dropped before the continuity check.

unrate_monthly_df <- unrate_raw_df |>
  dplyr::transmute(
    date      = date,
    year_int  = as.integer(lubridate::year(date)),
    month_int = as.integer(lubridate::month(date)),
    unrate_num = value
  ) |>
  dplyr::filter(!is.na(unrate_num)) |>
  dplyr::arrange(year_int, month_int)

###################################
###   4) Continuity check       ###
###################################
# Scan for gaps between the first and last observed month. A gap (e.g. a
# month FRED served with a missing value, dropped above) is logged as a
# warning rather than halting: spell identification below is gap-aware,
# so a gap breaks a spell instead of bridging it. Build the expected
# (year, month) grid with expand_grid, bound it to the observed date
# window so a partial final year is not falsely flagged, and anti-join
# against the months actually present.

expected_grid_df <- tidyr::expand_grid(
  year_int  = min(unrate_monthly_df$year_int):max(unrate_monthly_df$year_int),
  month_int = 1L:12L
) |>
  dplyr::mutate(
    grid_date = lubridate::make_date(year_int, month_int, 1L)
  ) |>
  dplyr::filter(
    grid_date >= min(unrate_monthly_df$date),
    grid_date <= max(unrate_monthly_df$date)
  ) |>
  dplyr::select(year_int, month_int)

have_grid_df <- unrate_monthly_df |>
  dplyr::select(year_int, month_int) |>
  dplyr::distinct()

missing_grid_df <- dplyr::anti_join(
  expected_grid_df, have_grid_df, by = c("year_int", "month_int")
)

n_missing_months_int <- nrow(missing_grid_df)

if (n_missing_months_int > 0L) {
  missing_chr <- paste(
    sprintf("%04d-%02d", missing_grid_df$year_int, missing_grid_df$month_int),
    collapse = ", "
  )
  message(
    "download_unemployment.R -- WARNING: UNRATE monthly series has ",
    n_missing_months_int, " missing (year, month) pair(s): ", missing_chr,
    ". Spells are computed gap-aware (each gap breaks a spell rather than ",
    "bridging it); confirm the gap is an expected data-collection ",
    "suspension before relying on spells adjacent to it."
  )
} else {
  message(
    "download_unemployment.R -- continuity scan PASS: ",
    nrow(unrate_monthly_df), " contiguous months, ",
    format(min(unrate_monthly_df$date)), " to ",
    format(max(unrate_monthly_df$date)), "."
  )
}

###################################
###   5) Spell identification   ###
###################################
# Flag months below the threshold, then identify contiguous below-5%
# runs. A plain rle() on the flag vector would silently bridge a dropped
# month (treating the months either side of a gap as adjacent); instead
# a new run starts whenever the flag changes OR the prior observed month
# is not exactly one calendar month earlier, so a gap breaks a spell.
# Spell aggregates are computed per run. Raw precision is kept on the
# min/max/mean columns (no rounding).

unrate_monthly_df <- unrate_monthly_df |>
  dplyr::arrange(date) |>
  dplyr::mutate(below_5_flag_bool = unrate_num < threshold_num)

# Monotonic calendar-month index for gap detection.
unrate_spell_work_df <- unrate_monthly_df |>
  dplyr::mutate(month_seq_int = year_int * 12L + (month_int - 1L))

# A new run starts at row 1, when the flag changes, or when the prior
# observed month is not exactly one calendar month earlier (a gap).
n_row_int <- nrow(unrate_spell_work_df)
run_break_bool <- c(
  TRUE,
  (unrate_spell_work_df$below_5_flag_bool[-1L] !=
     unrate_spell_work_df$below_5_flag_bool[-n_row_int]) |
    ((unrate_spell_work_df$month_seq_int[-1L] -
        unrate_spell_work_df$month_seq_int[-n_row_int]) != 1L)
)
unrate_spell_work_df$run_idx_int <- cumsum(run_break_bool)

low_unemp_spells_df <- unrate_spell_work_df |>
  dplyr::filter(below_5_flag_bool) |>
  dplyr::group_by(run_idx_int) |>
  dplyr::summarise(
    start_date        = min(date),
    end_date          = max(date),
    length_months_int = dplyr::n(),
    min_unrate_num    = min(unrate_num),
    max_unrate_num    = max(unrate_num),
    mean_unrate_num   = mean(unrate_num),
    .groups = "drop"
  ) |>
  dplyr::arrange(start_date) |>
  dplyr::mutate(
    spell_id_int      = dplyr::row_number(),
    start_year_int    = as.integer(lubridate::year(start_date)),
    start_month_int   = as.integer(lubridate::month(start_date)),
    end_year_int      = as.integer(lubridate::year(end_date)),
    end_month_int     = as.integer(lubridate::month(end_date)),
    length_months_int = as.integer(length_months_int)
  ) |>
  dplyr::select(
    spell_id_int,
    start_date, end_date,
    start_year_int, start_month_int, end_year_int, end_month_int,
    length_months_int,
    min_unrate_num, max_unrate_num, mean_unrate_num
  )

###################################
###   6) Spell logging          ###
###################################

for (spell_row_int in seq_len(nrow(low_unemp_spells_df))) {
  message(
    "download_unemployment.R -- spell ",
    low_unemp_spells_df$spell_id_int[spell_row_int], ": ",
    format(low_unemp_spells_df$start_date[spell_row_int], "%Y-%m"), " to ",
    format(low_unemp_spells_df$end_date[spell_row_int], "%Y-%m"), " (",
    low_unemp_spells_df$length_months_int[spell_row_int], " months, min=",
    sprintf("%.1f", low_unemp_spells_df$min_unrate_num[spell_row_int]), ", max=",
    sprintf("%.1f", low_unemp_spells_df$max_unrate_num[spell_row_int]), ", mean=",
    sprintf("%.1f", low_unemp_spells_df$mean_unrate_num[spell_row_int]), ")"
  )
}

message(
  "download_unemployment.R -- ", nrow(low_unemp_spells_df),
  " below-5% spell(s) identified covering ",
  sum(low_unemp_spells_df$length_months_int), " month(s) of ",
  nrow(unrate_monthly_df), " total."
)

###################################
###   7) Write parquet + rds    ###
###################################

unrate_monthly_out_path_chr <- fs::path(out_dir_chr, "unrate_monthly.parquet")
spells_out_path_chr         <- fs::path(out_dir_chr, "unrate_below_5_spells.parquet")

arrow::write_parquet(unrate_monthly_df,   sink = unrate_monthly_out_path_chr, compression = "snappy")
arrow::write_parquet(low_unemp_spells_df, sink = spells_out_path_chr,         compression = "snappy")

saveRDS(unrate_monthly_df,
        file = fs::path(out_dir_chr, "unrate_monthly.rds"),         compress = "xz")
saveRDS(low_unemp_spells_df,
        file = fs::path(out_dir_chr, "unrate_below_5_spells.rds"),  compress = "xz")

###################################
###   8) Manifest               ###
###################################

unemployment_manifest_df <- tibble::tibble(
  series_id_chr                  = unname(fred_series_chr[["unrate"]]),
  source_chr                     = "FRED",
  frequency_chr                  = "monthly",
  threshold_num                  = threshold_num,
  comparison_chr                 = "strict_less_than",
  n_obs_int                      = nrow(unrate_monthly_df),
  n_spells_int                   = nrow(low_unemp_spells_df),
  n_missing_months_int           = n_missing_months_int,
  coverage_min_chr               = format(min(unrate_monthly_df$date)),
  coverage_max_chr               = format(max(unrate_monthly_df$date)),
  # Project-relative, so the tracked manifest carries no machine path.
  out_parquet_monthly_path_chr   = as.character(fs::path_rel(unrate_monthly_out_path_chr, start = here::here())),
  out_parquet_spells_path_chr    = as.character(fs::path_rel(spells_out_path_chr, start = here::here())),
  # ISO-8601 with explicit Z suffix for locale-independent parsing.
  pulled_at_utc_chr              = format(
    Sys.time(), format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"
  )
)

manifest_path_chr <- fs::path(out_dir_chr, "_manifest.csv")
readr::write_csv(unemployment_manifest_df, manifest_path_chr)

message(
  "download_unemployment.R -- wrote monthly series (",
  nrow(unrate_monthly_df), " obs) and ", nrow(low_unemp_spells_df),
  " spell(s) (parquet + rds) and manifest to ", out_dir_chr
)

message("download_unemployment.R -- done.")
