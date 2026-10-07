# figure_f_era_bars_tables -- 12-month rolling-average wage series and within-era growth tables for the "lines over era bars" figures (6a percentiles, 6b ratios, 6c education thirds)
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

rm(list = ls())
options(scipen = 999)
set.seed(42)

# Sourced by run_all.R inside new.env(parent = globalenv()).
#
# TABLE LAYER. This script is the only stage of Figure 6 that reads
# microdata. code/figure_f_era_bars.R draws exclusively from the CSVs
# written here and never re-tabulates.
#
# Series (monthly; 12-month rolling average = 100 in December 1982):
#   6a  P10, P25, P50, P75, P90 of the real hourly wage
#   6b  wage ratios 50/10, 90/50, 90/10
#   6c  median real hourly wage by education third (least / middle / most)
#
# Estimator (decision 08, the repo standard for every display series):
# EARNWT-weighted quantiles per survey month (shared weighted_quantile(),
# Stata `_pctile` / EPI no-interpolation convention), then an equally
# weighted, backward-looking 12-month calendar rolling average [t-11, t].
# Months with no data (October 2025, federal shutdown) drop out of the
# window rather than shifting it; partial windows at series start are
# allowed, so the series begins January 1982. window_n_int records the
# number of observed months in each window. Ratios are formed from the
# smoothed percentiles (P50/P10, P90/P50, P90/P10), so 90/10 = 50/10 x
# 90/50 holds exactly in every month.
#
# Index anchor (figure_a_percentiles.R full-panel convention): each series
# is divided by its own 12-month rolling average in December 1982, so the
# rolling-average line sits at 100 there. The monthly sidecar applies the
# same anchor to the monthly cells.
#
# Eras: the five contiguous named wage eras of figure_a_percentiles.R step
# 8e (an editorial periodization, not estimated break dates and not NBER
# dates). Following the step-8e convention, each era is measured from the
# rolling average at its START month to the rolling average at its last
# month; the bars plot the cumulative change over that span (owner choice,
# 2026-09-29), and the annualized rate is stored alongside. Because
# adjacent eras are anchored one month apart, the era factors do not
# multiply exactly to the whole-period change; the gap is reported, not
# forced to zero.
#
# Education thirds: each calendar year, all civilian persons aged 25-64 in
# the CPS basic monthly survey (every labor-force status; WTFINL-weighted,
# pooled over the year's months; March ASEC oversample records and the
# 1984-1988 Armed Forces records, whose EDUC is NIU, excluded) are
# ranked by four education bins. Each bin's population interval on [0, 1]
# is split fractionally across [0, 1/3], [1/3, 2/3], [2/3, 1] rather than
# assigned whole, because the 1/3 cut falls inside the HS-diploma bin in
# every year. A wage record carries its own calendar year's fractions and
# the third's monthly median uses weight EARNWT x fraction. The WAGE sample
# is not restricted to ages 25-64: all wage-and-salary workers 16+.
#
# Outputs (output/tables/; _monthly = anchored monthly cells, _roll12 =
# the plotted 12-month rolling average, matching figure_a naming):
#   figure_f_percentiles_indexed_monthly.csv / _roll12.csv
#   figure_f_ratios_indexed_monthly.csv      / _roll12.csv
#   figure_f_education_indexed_monthly.csv   / _roll12.csv
#   figure_f_percentiles_era_growth.csv
#   figure_f_ratios_era_growth.csv
#   figure_f_education_era_growth.csv
#   figure_f_education_third_fractions.csv   (year x bin diagnostic)
#   figure_f_awp_reference_check.csv         (AWP definition vs. AWP build)
#   figure_f_awp_definition_comparison.csv   (repo standard vs. AWP definition)
#
# Step 11 also rebuilds the EIG American Worker Project (AWP) slim-deck
# definition (pooled 12-month quantile, windows need 11 of 12 months,
# chained era anchors, cumulative bars), checks it still reproduces the AWP
# reference values, and writes it next to the repo-standard numbers so the
# AWP repo can be migrated knowingly. The AWP definition is a comparison
# only; nothing plotted uses it (decision 09, reversed 2026-09-29).
#
# The build stops if any identity (ratio, fraction) or headline claim guard
# fails. No custom functions are defined; all transformations are inline.

source(here::here("code", "_utils", "00_packages.R"))

###################################
###   Configuration             ###
###################################

panel_in_dir_chr <- here::here("data", "intermediate", "cps_real_wages")
raw_in_dir_chr   <- here::here("data", "raw", "cps_org")
tbl_out_dir_chr  <- here::here("output", "tables")

pct_monthly_csv_chr   <- fs::path(tbl_out_dir_chr, "figure_f_percentiles_indexed_monthly.csv")
pct_roll_csv_chr      <- fs::path(tbl_out_dir_chr, "figure_f_percentiles_indexed_roll12.csv")
ratio_monthly_csv_chr <- fs::path(tbl_out_dir_chr, "figure_f_ratios_indexed_monthly.csv")
ratio_roll_csv_chr    <- fs::path(tbl_out_dir_chr, "figure_f_ratios_indexed_roll12.csv")
educ_monthly_csv_chr  <- fs::path(tbl_out_dir_chr, "figure_f_education_indexed_monthly.csv")
educ_roll_csv_chr     <- fs::path(tbl_out_dir_chr, "figure_f_education_indexed_roll12.csv")
pct_era_csv_chr       <- fs::path(tbl_out_dir_chr, "figure_f_percentiles_era_growth.csv")
ratio_era_csv_chr     <- fs::path(tbl_out_dir_chr, "figure_f_ratios_era_growth.csv")
educ_era_csv_chr      <- fs::path(tbl_out_dir_chr, "figure_f_education_era_growth.csv")
frac_csv_chr          <- fs::path(tbl_out_dir_chr, "figure_f_education_third_fractions.csv")
awp_ref_csv_chr       <- fs::path(tbl_out_dir_chr, "figure_f_awp_reference_check.csv")
awp_cmp_csv_chr       <- fs::path(tbl_out_dir_chr, "figure_f_awp_definition_comparison.csv")

# Decision 08 smoother: 12-month flat trailing window.
rolling_window_int <- 12L

# Index anchor: December 1982 (figure_a_percentiles.R full-panel anchor).
anchor_year_int  <- 1982L
anchor_month_int <- 12L

# AWP comparison definition only (step 11): pooled window resolved with at
# least 11 of 12 observed months.
awp_window_min_months_int <- 11L

percentile_keys_chr  <- c("p10", "p25", "p50", "p75", "p90")
percentile_probs_num <- c(0.10, 0.25, 0.50, 0.75, 0.90)
ratio_keys_chr       <- c("r50_10", "r90_50", "r90_10")
third_keys_chr       <- c("bottom", "middle", "top")

# COVID window flag carried in the monthly CSVs, matching the March 2020 to
# December 2021 dashed segment of figure_a_percentiles.R.
covid_start_idx_int <- as.integer(2020L * 12L +  3L - 1L)
covid_end_idx_int   <- as.integer(2021L * 12L + 12L - 1L)

# Named wage eras (figure_a_percentiles.R step 8e; contiguous subset).
# end NA => the latest resolved window. The "uncertainty" era of step 8e
# overlaps COVID-19 aftermath and is not part of this contiguous partition.
era_specs_df <- tibble::tribble(
  ~era_i_int, ~era_slug_chr,     ~era_label_chr,                     ~start_year_int, ~start_month_int, ~end_year_int, ~end_month_int,
  1L,         "stagnation1",     "First long wage stagnation",       1982L,           12L,              1996L,         8L,
  2L,         "itboom",          "Late-1990s IT boom",               1996L,            9L,              2001L,         2L,
  3L,         "stagnation2",     "Second long wage stagnation",      2001L,            3L,              2014L,        10L,
  4L,         "recovery",        "Nascent recovery meets COVID-19",  2014L,           11L,              2020L,         1L,
  5L,         "covid_aftermath", "COVID-19 aftermath",               2020L,            2L,              NA_integer_,   NA_integer_
)
# Era 4 runs through January 2020 and era 5 starts February 2020, the NBER
# peak month, matching the figure_a recovery and covid_aftermath charts
# (Decision 10 addendum, 2026-10-07). The boundaries are now the same as
# the AWP comparison's in step 11 (its era 5 first month is February 2020);
# the AWP vector below stays separate because the reference check reproduces
# fixed AWP slim-deck values and must not move with this table.
awp_era_start_month_idx_int <- c(
  1982L * 12L + 12L - 1L, 1996L * 12L + 9L - 1L, 2001L * 12L + 3L - 1L,
  2014L * 12L + 11L - 1L, 2020L * 12L + 2L - 1L
)

# Education bins from the IPUMS general code floor(EDUC / 10), pinned to
# the cps_00586 DDI: 002 and 010-060 less than HS; 070-073 HS (071 is
# "12th grade, no diploma" and lands here under the general-code rule);
# 080-100 some college / associate's; 110-125 bachelor's or higher.
# EDUC 000/001 (NIU) and 999 (missing) are not valid bins.
educ_bin_labels_chr <- c(
  "Less than HS",
  "HS diploma or GED",
  "Some college or Associate's degree",
  "Bachelor's degree or higher"
)
ranking_age_min_int <- 25L
ranking_age_max_int <- 64L

# Reference values from the EIG American Worker Project slim-deck build
# (July 2026 window). Compared, never tuned to.
reference_df <- tibble::tribble(
  ~figure_chr, ~series_chr, ~stat_chr,   ~era_i_int, ~reference_num,
  "6a", "p10",    "last_index", NA_integer_, 150.4,
  "6a", "p25",    "last_index", NA_integer_, 149.9,
  "6a", "p50",    "last_index", NA_integer_, 140.1,
  "6a", "p75",    "last_index", NA_integer_, 146.5,
  "6a", "p90",    "last_index", NA_integer_, 176.8,
  "6b", "r50_10", "last_index", NA_integer_,  93.1,
  "6b", "r90_50", "last_index", NA_integer_, 126.3,
  "6b", "r90_10", "last_index", NA_integer_, 117.6,
  "6c", "bottom", "last_index", NA_integer_, 137.2,
  "6c", "middle", "last_index", NA_integer_, 143.4,
  "6c", "top",    "last_index", NA_integer_, 162.8,
  "6a", "p10",    "base_level", NA_integer_,   9.79,
  "6a", "p50",    "base_level", NA_integer_,  18.48,
  "6a", "p90",    "base_level", NA_integer_,  37.89,
  "6c", "bottom", "base_level", NA_integer_,  14.58,
  "6c", "middle", "base_level", NA_integer_,  17.61,
  "6c", "top",    "base_level", NA_integer_,  23.82,
  "6a", "p10", "era_cum_pct", 1L, -4.25, "6a", "p10", "era_cum_pct", 2L, 13.63,
  "6a", "p10", "era_cum_pct", 3L,  5.33, "6a", "p10", "era_cum_pct", 4L, 11.16,
  "6a", "p10", "era_cum_pct", 5L, 18.07,
  "6a", "p25", "era_cum_pct", 1L,  2.38, "6a", "p25", "era_cum_pct", 2L,  9.91,
  "6a", "p25", "era_cum_pct", 3L,  3.78, "6a", "p25", "era_cum_pct", 4L, 15.29,
  "6a", "p25", "era_cum_pct", 5L, 11.32,
  "6a", "p50", "era_cum_pct", 1L,  1.89, "6a", "p50", "era_cum_pct", 2L, 11.30,
  "6a", "p50", "era_cum_pct", 3L,  5.49, "6a", "p50", "era_cum_pct", 4L,  8.54,
  "6a", "p50", "era_cum_pct", 5L,  7.88,
  "6a", "p75", "era_cum_pct", 1L,  3.10, "6a", "p75", "era_cum_pct", 2L, 11.89,
  "6a", "p75", "era_cum_pct", 3L,  7.33, "6a", "p75", "era_cum_pct", 4L, 10.36,
  "6a", "p75", "era_cum_pct", 5L,  7.21,
  "6a", "p90", "era_cum_pct", 1L, 11.64, "6a", "p90", "era_cum_pct", 2L, 11.36,
  "6a", "p90", "era_cum_pct", 3L, 14.42, "6a", "p90", "era_cum_pct", 4L, 11.54,
  "6a", "p90", "era_cum_pct", 5L, 11.46,
  "6b", "r50_10", "era_cum_pct", 1L,  6.41, "6b", "r50_10", "era_cum_pct", 2L, -2.05,
  "6b", "r50_10", "era_cum_pct", 3L,  0.15, "6b", "r50_10", "era_cum_pct", 4L, -2.36,
  "6b", "r50_10", "era_cum_pct", 5L, -8.63,
  "6b", "r90_50", "era_cum_pct", 1L,  9.57, "6b", "r90_50", "era_cum_pct", 2L,  0.05,
  "6b", "r90_50", "era_cum_pct", 3L,  8.47, "6b", "r90_50", "era_cum_pct", 4L,  2.77,
  "6b", "r90_50", "era_cum_pct", 5L,  3.32,
  "6b", "r90_10", "era_cum_pct", 1L, 16.59, "6b", "r90_10", "era_cum_pct", 2L, -2.00,
  "6b", "r90_10", "era_cum_pct", 3L,  8.63, "6b", "r90_10", "era_cum_pct", 4L,  0.35,
  "6b", "r90_10", "era_cum_pct", 5L, -5.60,
  "6c", "bottom", "era_cum_pct", 1L,  0.27, "6c", "bottom", "era_cum_pct", 2L,  7.80,
  "6c", "bottom", "era_cum_pct", 3L,  4.73, "6c", "bottom", "era_cum_pct", 4L, 12.72,
  "6c", "bottom", "era_cum_pct", 5L,  7.51,
  "6c", "middle", "era_cum_pct", 1L,  2.77, "6c", "middle", "era_cum_pct", 2L, 10.19,
  "6c", "middle", "era_cum_pct", 3L, -0.71, "6c", "middle", "era_cum_pct", 4L, 12.78,
  "6c", "middle", "era_cum_pct", 5L, 13.06,
  "6c", "top",    "era_cum_pct", 1L, 14.00, "6c", "top",    "era_cum_pct", 2L, 16.62,
  "6c", "top",    "era_cum_pct", 3L,  9.01, "6c", "top",    "era_cum_pct", 4L,  7.38,
  "6c", "top",    "era_cum_pct", 5L,  4.59
)

fs::dir_create(tbl_out_dir_chr, recurse = TRUE)

###################################
###   1) Load real-wage panel   ###
###################################

if (!fs::dir_exists(panel_in_dir_chr)) {
  stop(
    "figure_f_era_bars_tables.R -- real-wage panel not found at ",
    panel_in_dir_chr, ". Run 02a_build_real_wages.R first."
  )
}

# Explicit parquet-only file list: the partition dirs also hold part-0.rds
# sidecars that arrow cannot parse.
panel_paths_chr <- fs::dir_ls(
  panel_in_dir_chr, regexp = "part-0\\.parquet$", recurse = TRUE, type = "file"
)

real_wage_ds <- arrow::open_dataset(panel_paths_chr, format = "parquet")

missing_cols_chr <- setdiff(
  c("YEAR", "MONTH", "EARNWT", "SEX", "EDUC", "real_hourly_wage_num"),
  names(real_wage_ds)
)
if (length(missing_cols_chr) > 0L) {
  stop(
    "figure_f_era_bars_tables.R -- real-wage panel missing column(s): ",
    paste(missing_cols_chr, collapse = ", "),
    ". EDUC is carried by 02a_build_real_wages.R; rerun 02a."
  )
}

wage_df <- real_wage_ds |>
  dplyr::select(YEAR, MONTH, EARNWT, SEX, EDUC, real_hourly_wage_num) |>
  dplyr::collect()

n_loaded_int <- nrow(wage_df)

# Drop rows that cannot enter any weighted statistic.
wage_df <- wage_df |>
  dplyr::filter(
    !is.na(real_hourly_wage_num),
    !is.na(EARNWT),
    EARNWT > 0
  ) |>
  dplyr::mutate(
    year_int      = as.integer(YEAR),
    month_int     = as.integer(MONTH),
    month_idx_int = as.integer(year_int * 12L + month_int - 1L)
  ) |>
  dplyr::arrange(month_idx_int)

message(
  "figure_f_era_bars_tables.R -- loaded ", format(n_loaded_int, big.mark = ","),
  " person-month records; ", format(nrow(wage_df), big.mark = ","),
  " kept after dropping NA wages and missing/non-positive EARNWT"
)

###################################
###   2) Calendar-complete grid ###
###################################
# Every calendar month from the first to the last observed month gets a
# row; months with no data (October 2025) carry n_records_int = 0.

month_counts_df <- wage_df |>
  dplyr::count(month_idx_int, name = "n_records_int")

first_obs_idx_int <- min(month_counts_df$month_idx_int)
last_obs_idx_int  <- max(month_counts_df$month_idx_int)

grid_df <- tibble::tibble(
  month_idx_int = seq(first_obs_idx_int, last_obs_idx_int)
) |>
  dplyr::left_join(month_counts_df, by = "month_idx_int") |>
  dplyr::mutate(
    n_records_int = dplyr::coalesce(n_records_int, 0L),
    observed_bool = n_records_int > 0L,
    year_int      = as.integer(month_idx_int %/% 12L),
    month_int     = as.integer(month_idx_int %%  12L + 1L),
    date_dt       = as.Date(sprintf("%04d-%02d-01", year_int, month_int))
  )

missing_months_chr <- format(grid_df$date_dt[!grid_df$observed_bool], "%Y-%m")
message(
  "figure_f_era_bars_tables.R -- month grid ",
  format(min(grid_df$date_dt), "%Y-%m"), " to ", format(max(grid_df$date_dt), "%Y-%m"),
  " (", nrow(grid_df), " months); months with no data: ",
  if (length(missing_months_chr) == 0L) "none" else paste(missing_months_chr, collapse = ", ")
)

# Row ranges per month in the month-sorted wage_df, so a window is one
# contiguous row block.
month_first_row_int <- match(grid_df$month_idx_int, wage_df$month_idx_int)
month_last_row_int  <- nrow(wage_df) + 1L -
  match(grid_df$month_idx_int, rev(wage_df$month_idx_int))

###################################
###   3) Education bins         ###
###################################

wage_df <- wage_df |>
  dplyr::mutate(
    educ_general_int = as.integer(EDUC %/% 10L),
    educ_bin_int = dplyr::case_when(
      is.na(EDUC) | EDUC %in% c(0L, 1L) | EDUC >= 999L ~ NA_integer_,
      educ_general_int <= 6L                          ~ 1L,
      educ_general_int == 7L                          ~ 2L,
      educ_general_int %in% 8:10                      ~ 3L,
      educ_general_int %in% 11:12                     ~ 4L,
      TRUE                                            ~ NA_integer_
    )
  )

n_wage_no_bin_int <- sum(is.na(wage_df$educ_bin_int) | is.na(wage_df$SEX))
message(
  "figure_f_era_bars_tables.R -- wage records without a valid education bin ",
  "or sex (excluded from 6c only): ", format(n_wage_no_bin_int, big.mark = ",")
)

###################################
###   4) Ranking population     ###
###################################
# All civilian persons aged 25-64 in the basic monthly CPS (every
# labor-force status), WTFINL-weighted and pooled over each year's months.
# ASECFLAG == 1 marks March ASEC oversample records, which are not part of
# the basic monthly sample. Armed Forces members (EMPSTAT == 1) carry
# positive WTFINL only in 1984-1988 and have EDUC = NIU there (about 0.5
# percent of the weighted 25-64 population), so they cannot be ranked;
# they are excluded in every year, matching the civilian wage sample.

raw_paths_chr <- fs::dir_ls(
  raw_in_dir_chr, regexp = "part-0\\.parquet$", recurse = TRUE, type = "file"
)

ranking_base_ds <- arrow::open_dataset(raw_paths_chr, format = "parquet") |>
  dplyr::filter(
    AGE >= ranking_age_min_int,
    AGE <= ranking_age_max_int,
    !is.na(WTFINL),
    WTFINL > 0,
    is.na(ASECFLAG) | ASECFLAG != 1L
  )

armed_forces_df <- ranking_base_ds |>
  dplyr::filter(EMPSTAT == 1L) |>
  dplyr::group_by(YEAR) |>
  dplyr::summarise(n_rows_int = dplyr::n(), .groups = "drop") |>
  dplyr::collect() |>
  dplyr::arrange(YEAR)
message(
  "figure_f_era_bars_tables.R -- Armed Forces rows excluded from the ranking ",
  "population: ", format(sum(armed_forces_df$n_rows_int), big.mark = ","),
  if (nrow(armed_forces_df) > 0L) {
    paste0(" (years ", paste(armed_forces_df$YEAR, collapse = ", "), ")")
  } else ""
)

ranking_raw_df <- ranking_base_ds |>
  dplyr::filter(is.na(EMPSTAT) | EMPSTAT != 1L) |>
  dplyr::group_by(YEAR, EDUC) |>
  dplyr::summarise(
    wtfinl_sum_num = sum(WTFINL),
    n_rows_int     = dplyr::n(),
    .groups        = "drop"
  ) |>
  dplyr::collect()

ranking_invalid_df <- ranking_raw_df |>
  dplyr::filter(is.na(EDUC) | EDUC %in% c(0L, 1L) | EDUC >= 999L)
if (nrow(ranking_invalid_df) > 0L) {
  stop(
    "figure_f_era_bars_tables.R -- ", sum(ranking_invalid_df$n_rows_int),
    " ranking-population rows aged 25-64 carry NIU/missing EDUC; ",
    "the crosswalk would silently drop them."
  )
}

ranking_df <- ranking_raw_df |>
  dplyr::mutate(
    year_int         = as.integer(YEAR),
    educ_general_int = as.integer(EDUC %/% 10L),
    educ_bin_int = dplyr::case_when(
      educ_general_int <= 6L          ~ 1L,
      educ_general_int == 7L          ~ 2L,
      educ_general_int %in% 8:10      ~ 3L,
      educ_general_int %in% 11:12     ~ 4L,
      TRUE                            ~ NA_integer_
    )
  )

if (anyNA(ranking_df$educ_bin_int)) {
  stop(
    "figure_f_era_bars_tables.R -- EDUC code(s) outside the crosswalk: ",
    paste(sort(unique(ranking_df$EDUC[is.na(ranking_df$educ_bin_int)])), collapse = ", ")
  )
}

# Year x bin shares, cumulative intervals, and fractional thirds.
# frac_k = |[prior_cum, cum] intersect [lo_k, hi_k]| / share.
fraction_df <- ranking_df |>
  dplyr::group_by(year_int, educ_bin_int) |>
  dplyr::summarise(
    population_num = sum(wtfinl_sum_num),
    n_rows_int     = sum(n_rows_int),
    .groups        = "drop"
  ) |>
  dplyr::arrange(year_int, educ_bin_int) |>
  dplyr::group_by(year_int) |>
  dplyr::mutate(
    n_bins_int    = dplyr::n(),
    share_num     = population_num / sum(population_num),
    cum_num       = cumsum(share_num),
    prior_cum_num = cum_num - share_num
  ) |>
  dplyr::ungroup() |>
  dplyr::mutate(
    educ_bin_chr = educ_bin_labels_chr[educ_bin_int],
    frac_bottom_num = pmax(0, pmin(cum_num, 1 / 3) - pmax(prior_cum_num, 0))     / share_num,
    frac_middle_num = pmax(0, pmin(cum_num, 2 / 3) - pmax(prior_cum_num, 1 / 3)) / share_num,
    frac_top_num    = pmax(0, pmin(cum_num, 1)     - pmax(prior_cum_num, 2 / 3)) / share_num
  )

if (any(fraction_df$n_bins_int != 4L)) {
  stop("figure_f_era_bars_tables.R -- a ranking year is missing an education bin.")
}
frac_sum_gap_num <- max(abs(
  fraction_df$frac_bottom_num + fraction_df$frac_middle_num + fraction_df$frac_top_num - 1
))
if (frac_sum_gap_num > 1e-9) {
  stop(
    "figure_f_era_bars_tables.R -- third fractions do not sum to 1 within a bin ",
    "(max gap ", signif(frac_sum_gap_num, 3), ")."
  )
}

missing_rank_years_int <- setdiff(unique(wage_df$year_int), fraction_df$year_int)
if (length(missing_rank_years_int) > 0L) {
  stop(
    "figure_f_era_bars_tables.R -- no ranking population for wage year(s): ",
    paste(missing_rank_years_int, collapse = ", ")
  )
}

# Where the 1/3 and 2/3 cuts fall, for the log.
cut_bins_df <- fraction_df |>
  dplyr::group_by(year_int) |>
  dplyr::summarise(
    cut13_bin_int = educ_bin_int[prior_cum_num < 1 / 3 & cum_num > 1 / 3][1],
    cut23_bin_int = educ_bin_int[prior_cum_num < 2 / 3 & cum_num > 2 / 3][1],
    .groups       = "drop"
  )
message(
  "figure_f_era_bars_tables.R -- ranking population built for ",
  nrow(cut_bins_df), " years; the 1/3 cut falls in bin(s) ",
  paste(sort(unique(cut_bins_df$cut13_bin_int)), collapse = "/"),
  " and the 2/3 cut in bin(s) ",
  paste(sort(unique(cut_bins_df$cut23_bin_int)), collapse = "/")
)

# Attach each wage record's own-year fractions. Records without a bin get
# zero weight in every third.
wage_df <- wage_df |>
  dplyr::left_join(
    fraction_df |>
      dplyr::select(year_int, educ_bin_int, frac_bottom_num, frac_middle_num, frac_top_num),
    by = c("year_int", "educ_bin_int")
  ) |>
  dplyr::mutate(
    frac_bottom_num = dplyr::if_else(is.na(SEX), 0, dplyr::coalesce(frac_bottom_num, 0)),
    frac_middle_num = dplyr::if_else(is.na(SEX), 0, dplyr::coalesce(frac_middle_num, 0)),
    frac_top_num    = dplyr::if_else(is.na(SEX), 0, dplyr::coalesce(frac_top_num, 0))
  )

if (nrow(wage_df) != sum(month_counts_df$n_records_int)) {
  stop("figure_f_era_bars_tables.R -- the fraction join changed the wage row count.")
}

###################################
###   5) Monthly cells          ###
###################################
# Per observed survey month: EARNWT-weighted P10-P90 and the three
# education-third medians (weight EARNWT x third fraction). Months with no
# data stay NA on the calendar grid.

wage_x_num   <- wage_df$real_hourly_wage_num
wage_w_num   <- wage_df$EARNWT
frac_bot_num <- wage_df$frac_bottom_num
frac_mid_num <- wage_df$frac_middle_num
frac_top_num <- wage_df$frac_top_num

n_grid_int <- nrow(grid_df)
cell_keys_chr <- c(percentile_keys_chr, third_keys_chr)
monthly_mat_num <- matrix(
  NA_real_, nrow = n_grid_int, ncol = length(cell_keys_chr),
  dimnames = list(NULL, cell_keys_chr)
)

for (g in which(grid_df$observed_bool)) {
  rows_int <- month_first_row_int[g]:month_last_row_int[g]
  x_num <- wage_x_num[rows_int]
  w_num <- wage_w_num[rows_int]
  monthly_mat_num[g, percentile_keys_chr] <- weighted_quantile(x_num, w_num, percentile_probs_num)
  monthly_mat_num[g, "bottom"] <- weighted_quantile(x_num, w_num * frac_bot_num[rows_int], 0.5)
  monthly_mat_num[g, "middle"] <- weighted_quantile(x_num, w_num * frac_mid_num[rows_int], 0.5)
  monthly_mat_num[g, "top"]    <- weighted_quantile(x_num, w_num * frac_top_num[rows_int], 0.5)
}

monthly_df <- dplyr::bind_cols(
  grid_df |> dplyr::select(month_idx_int, year_int, month_int, date_dt, observed_bool),
  tibble::as_tibble(monthly_mat_num)
) |>
  dplyr::mutate(
    r50_10 = p50 / p10,
    r90_50 = p90 / p50,
    r90_10 = p90 / p10
  )

###################################
###   6) 12-month rolling average ###
###################################
# Decision 08: equally weighted, backward-looking [t-11, t] calendar window
# over the observed months; partial windows at series start allowed; an
# all-NA window is NA_real_. Ratios come from the smoothed percentiles.

roll_df <- monthly_df
for (k in cell_keys_chr) {
  roll_df[[k]] <- zoo::rollapplyr(
    data    = monthly_df[[k]],
    width   = rolling_window_int,
    FUN     = function(x) {
      # mean(x, na.rm = TRUE) on an all-NA window is NaN, not NA_real_.
      if (all(is.na(x))) NA_real_ else mean(x, na.rm = TRUE)
    },
    fill    = NA_real_,
    partial = TRUE
  )
}
roll_df <- roll_df |>
  dplyr::mutate(
    r50_10 = p50 / p10,
    r90_50 = p90 / p50,
    r90_10 = p90 / p10,
    window_n_int = as.integer(zoo::rollapplyr(
      as.integer(observed_bool), width = rolling_window_int, FUN = sum, partial = TRUE
    ))
  )

if (anyNA(roll_df[, cell_keys_chr])) {
  stop("figure_f_era_bars_tables.R -- a rolling-average month is NA.")
}

ratio_gap_num <- max(abs(roll_df$r90_10 - roll_df$r50_10 * roll_df$r90_50))
if (ratio_gap_num >= 1e-9) {
  stop(
    "figure_f_era_bars_tables.R -- ratio identity r90_10 = r50_10 x r90_50 fails ",
    "(max gap ", signif(ratio_gap_num, 3), ")."
  )
}

latest_idx_int <- max(roll_df$month_idx_int)
message(
  "figure_f_era_bars_tables.R -- 12-month rolling averages ",
  format(min(roll_df$date_dt), "%Y-%m"), " to ", format(max(roll_df$date_dt), "%Y-%m"),
  "; latest window_n = ", roll_df$window_n_int[nrow(roll_df)],
  "; partial windows at series start: ", sum(roll_df$window_n_int < rolling_window_int &
                                            roll_df$month_idx_int < min(roll_df$month_idx_int) + 11L)
)

###################################
###   7) Index to December 1982 ###
###################################

series_keys_chr <- c(percentile_keys_chr, ratio_keys_chr, third_keys_chr)

anchor_idx_int <- as.integer(anchor_year_int * 12L + anchor_month_int - 1L)
anchor_row_int <- which(roll_df$month_idx_int == anchor_idx_int)
if (length(anchor_row_int) != 1L || roll_df$window_n_int[anchor_row_int] != rolling_window_int) {
  stop("figure_f_era_bars_tables.R -- the December 1982 anchor window is missing or incomplete.")
}

anchor_values_num <- unlist(roll_df[anchor_row_int, series_keys_chr])
index_roll_df    <- roll_df
index_monthly_df <- monthly_df
for (k in series_keys_chr) {
  index_roll_df[[k]]    <- 100 * roll_df[[k]]    / anchor_values_num[[k]]
  index_monthly_df[[k]] <- 100 * monthly_df[[k]] / anchor_values_num[[k]]
}

###################################
###   8) Eras and era growth    ###
###################################

era_df <- era_specs_df |>
  dplyr::mutate(
    start_idx_int = as.integer(start_year_int * 12L + start_month_int - 1L),
    end_idx_int   = dplyr::if_else(
      is.na(end_year_int),
      latest_idx_int,
      as.integer(end_year_int * 12L + end_month_int - 1L)
    )
  ) |>
  dplyr::arrange(era_i_int)

if (era_df$start_idx_int[1] != anchor_idx_int) {
  stop("figure_f_era_bars_tables.R -- era 1 must start at the December 1982 index anchor.")
}
if (any(era_df$start_idx_int[-1] != era_df$end_idx_int[-nrow(era_df)] + 1L)) {
  stop("figure_f_era_bars_tables.R -- eras are not contiguous.")
}
if (utils::tail(era_df$end_idx_int, 1L) != latest_idx_int) {
  stop("figure_f_era_bars_tables.R -- the last era does not end at the latest month.")
}

# figure_a step-8e convention: each era is anchored at its own START month.
era_df <- era_df |>
  dplyr::mutate(
    base_idx_int = start_idx_int,
    months_int   = end_idx_int - base_idx_int,
    era_start_dt = as.Date(sprintf("%04d-%02d-01", start_idx_int %/% 12L, start_idx_int %% 12L + 1L)),
    era_end_dt   = as.Date(sprintf("%04d-%02d-01", end_idx_int %/% 12L, end_idx_int %% 12L + 1L))
  )

era_growth_df <- tidyr::expand_grid(
  era_df |>
    dplyr::select(
      era_i_int, era_slug_chr, era_label_chr, era_start_dt, era_end_dt,
      base_idx_int, end_idx_int, months_int
    ),
  series_chr = series_keys_chr
) |>
  dplyr::mutate(base_value_num = NA_real_, end_value_num = NA_real_)

for (r in seq_len(nrow(era_growth_df))) {
  key_chr <- era_growth_df$series_chr[r]
  era_growth_df$base_value_num[r] <- roll_df[[key_chr]][roll_df$month_idx_int == era_growth_df$base_idx_int[r]]
  era_growth_df$end_value_num[r]  <- roll_df[[key_chr]][roll_df$month_idx_int == era_growth_df$end_idx_int[r]]
}

era_growth_df <- era_growth_df |>
  dplyr::mutate(
    base_date_dt       = as.Date(sprintf("%04d-%02d-01", base_idx_int %/% 12L, base_idx_int %% 12L + 1L)),
    end_date_dt        = as.Date(sprintf("%04d-%02d-01", end_idx_int %/% 12L, end_idx_int %% 12L + 1L)),
    years_num          = months_int / 12,
    factor_num         = end_value_num / base_value_num,
    cumulative_pct_num = 100 * (factor_num - 1),
    annualized_pct_num = 100 * (factor_num ^ (12 / months_int) - 1)
  )

if (anyNA(era_growth_df$factor_num)) {
  stop("figure_f_era_bars_tables.R -- an era anchor has no rolling-average value.")
}

# Per-era ratio identity (same anchor months for all three ratios).
ratio_era_wide_df <- era_growth_df |>
  dplyr::filter(series_chr %in% ratio_keys_chr) |>
  dplyr::select(era_i_int, series_chr, factor_num) |>
  tidyr::pivot_wider(names_from = series_chr, values_from = factor_num)
ratio_era_gap_num <- max(abs(
  ratio_era_wide_df$r50_10 * ratio_era_wide_df$r90_50 - ratio_era_wide_df$r90_10
))
if (ratio_era_gap_num > 1e-9) {
  stop("figure_f_era_bars_tables.R -- per-era ratio identity fails (gap ", signif(ratio_era_gap_num, 3), ").")
}

# Chain gap (reported, not asserted): start-month anchoring leaves a
# one-month seam between adjacent eras.
chain_df <- era_growth_df |>
  dplyr::group_by(series_chr) |>
  dplyr::summarise(chain_num = prod(factor_num), .groups = "drop") |>
  dplyr::mutate(
    whole_num  = unlist(roll_df[nrow(roll_df), series_chr]) / anchor_values_num[series_chr],
    gap_pp_num = 100 * (chain_num - whole_num)
  )

message(
  "figure_f_era_bars_tables.R -- ratio identity max gap ", signif(ratio_gap_num, 3),
  " (monthly), ", signif(ratio_era_gap_num, 3), " (per era); era chain vs. whole-period ",
  "change differs by at most ", round(max(abs(chain_df$gap_pp_num)), 2),
  " index points (four one-month seams)"
)

era_lookup_int <- findInterval(index_roll_df$month_idx_int, era_df$start_idx_int)
era_lookup_int[era_lookup_int == 0L] <- NA_integer_
index_roll_df$era_slug_chr    <- era_df$era_slug_chr[era_lookup_int]
index_monthly_df$era_slug_chr <- index_roll_df$era_slug_chr
covid_flag_int <- as.integer(
  index_roll_df$month_idx_int >= covid_start_idx_int & index_roll_df$month_idx_int <= covid_end_idx_int
)
index_roll_df$covid_flag_int    <- covid_flag_int
index_monthly_df$covid_flag_int <- covid_flag_int
index_monthly_df$window_n_int   <- index_roll_df$window_n_int

###################################
###   9) Headline claim guards  ###
###################################
# The figure titles assert these; the build fails if the data stop
# supporting them.

last_index_num <- unlist(index_roll_df[nrow(index_roll_df), series_keys_chr])

# 6a: every percentile ends above 100; P90 highest; P50 lowest.
if (!all(last_index_num[percentile_keys_chr] > 100) ||
    names(which.max(last_index_num[percentile_keys_chr])) != "p90" ||
    names(which.min(last_index_num[percentile_keys_chr])) != "p50") {
  stop("figure_f_era_bars_tables.R -- 6a headline claim no longer holds: ",
       paste(names(last_index_num[percentile_keys_chr]), round(last_index_num[percentile_keys_chr], 1), collapse = ", "))
}

# 6b: the 50/10 index ends below 100 (the bottom closed on the middle) and
# the 90/50 and 90/10 indexes end above 100 (the top pulled away from both).
if (!(last_index_num[["r50_10"]] < 100 && last_index_num[["r90_50"]] > 100 && last_index_num[["r90_10"]] > 100)) {
  stop("figure_f_era_bars_tables.R -- 6b headline claim no longer holds (50/10 ",
       round(last_index_num[["r50_10"]], 1), ", 90/50 ", round(last_index_num[["r90_50"]], 1), ").")
}

# 6c: the most-educated third grew faster than both others in eras 1-3
# and slower than both in eras 4-5.
educ_era_wide_df <- era_growth_df |>
  dplyr::filter(series_chr %in% third_keys_chr) |>
  dplyr::select(era_i_int, series_chr, cumulative_pct_num) |>
  tidyr::pivot_wider(names_from = series_chr, values_from = cumulative_pct_num) |>
  dplyr::arrange(era_i_int)
top_leads_bool <- educ_era_wide_df$top > pmax(educ_era_wide_df$bottom, educ_era_wide_df$middle)
top_lags_bool  <- educ_era_wide_df$top < pmin(educ_era_wide_df$bottom, educ_era_wide_df$middle)
if (!all(top_leads_bool[1:3]) || !all(top_lags_bool[4:5])) {
  stop("figure_f_era_bars_tables.R -- 6c headline claim (top third leads eras 1-3, lags eras 4-5) no longer holds.")
}

message("figure_f_era_bars_tables.R -- all headline claim guards PASS")

###################################
###   10) Write tables          ###
###################################

key_cols_chr <- c("year_int", "month_int", "date_dt", "month_idx_int",
                  "window_n_int", "era_slug_chr", "covid_flag_int")

pct_roll_out_df <- index_roll_df |>
  dplyr::select(dplyr::all_of(c(key_cols_chr, percentile_keys_chr))) |>
  dplyr::bind_cols(
    roll_df |>
      dplyr::select(dplyr::all_of(percentile_keys_chr)) |>
      dplyr::rename_with(\(x) paste0(x, "_level_num"))
  )
ratio_roll_out_df <- index_roll_df |>
  dplyr::select(dplyr::all_of(c(key_cols_chr, ratio_keys_chr))) |>
  dplyr::bind_cols(
    roll_df |>
      dplyr::select(dplyr::all_of(ratio_keys_chr)) |>
      dplyr::rename_with(\(x) paste0(x, "_level_num"))
  )
educ_roll_out_df <- index_roll_df |>
  dplyr::select(dplyr::all_of(c(key_cols_chr, third_keys_chr))) |>
  dplyr::bind_cols(
    roll_df |>
      dplyr::select(dplyr::all_of(third_keys_chr)) |>
      dplyr::rename_with(\(x) paste0(x, "_level_num"))
  )

readr::write_csv(pct_roll_out_df,   pct_roll_csv_chr)
readr::write_csv(ratio_roll_out_df, ratio_roll_csv_chr)
readr::write_csv(educ_roll_out_df,  educ_roll_csv_chr)
readr::write_csv(
  index_monthly_df |> dplyr::select(dplyr::all_of(c(key_cols_chr, percentile_keys_chr))),
  pct_monthly_csv_chr
)
readr::write_csv(
  index_monthly_df |> dplyr::select(dplyr::all_of(c(key_cols_chr, ratio_keys_chr))),
  ratio_monthly_csv_chr
)
readr::write_csv(
  index_monthly_df |> dplyr::select(dplyr::all_of(c(key_cols_chr, third_keys_chr))),
  educ_monthly_csv_chr
)

era_out_cols_chr <- c(
  "era_i_int", "era_slug_chr", "era_label_chr", "era_start_dt", "era_end_dt",
  "series_chr", "base_date_dt", "base_value_num", "end_date_dt", "end_value_num",
  "months_int", "years_num", "cumulative_pct_num", "annualized_pct_num"
)
readr::write_csv(
  era_growth_df |> dplyr::filter(series_chr %in% percentile_keys_chr) |> dplyr::select(dplyr::all_of(era_out_cols_chr)),
  pct_era_csv_chr
)
readr::write_csv(
  era_growth_df |> dplyr::filter(series_chr %in% ratio_keys_chr) |> dplyr::select(dplyr::all_of(era_out_cols_chr)),
  ratio_era_csv_chr
)
readr::write_csv(
  era_growth_df |> dplyr::filter(series_chr %in% third_keys_chr) |> dplyr::select(dplyr::all_of(era_out_cols_chr)),
  educ_era_csv_chr
)
readr::write_csv(
  fraction_df |>
    dplyr::select(
      year_int, educ_bin_int, educ_bin_chr, n_rows_int, population_num,
      share_num, prior_cum_num, cum_num, frac_bottom_num, frac_middle_num, frac_top_num
    ),
  frac_csv_chr
)

###################################
###   11) AWP definition        ###
###################################
# Comparison only, for migrating the AWP repo. The AWP slim-deck build
# defines each point as ONE weighted quantile of the pooled trailing 12
# months (resolved only with >= 11 observed months and a leading-edge
# guard, so it starts December 1982), chains each era from the window
# before it starts, and plots cumulative change. (a) Confirm that this
# definition still reproduces the AWP reference values; (b) write it next
# to the repo-standard numbers.

awp_mat_num <- matrix(
  NA_real_, nrow = n_grid_int, ncol = length(cell_keys_chr),
  dimnames = list(NULL, cell_keys_chr)
)
for (g in seq_len(n_grid_int)) {
  start_g_int <- g - (rolling_window_int - 1L)
  if (start_g_int < 1L) next
  win_g_int <- start_g_int:g
  obs_g_int <- win_g_int[grid_df$observed_bool[win_g_int]]
  if (length(obs_g_int) < awp_window_min_months_int) next
  rows_int <- month_first_row_int[min(obs_g_int)]:month_last_row_int[max(obs_g_int)]
  x_num <- wage_x_num[rows_int]
  w_num <- wage_w_num[rows_int]
  awp_mat_num[g, percentile_keys_chr] <- weighted_quantile(x_num, w_num, percentile_probs_num)
  awp_mat_num[g, "bottom"] <- weighted_quantile(x_num, w_num * frac_bot_num[rows_int], 0.5)
  awp_mat_num[g, "middle"] <- weighted_quantile(x_num, w_num * frac_mid_num[rows_int], 0.5)
  awp_mat_num[g, "top"]    <- weighted_quantile(x_num, w_num * frac_top_num[rows_int], 0.5)
}
awp_df <- dplyr::bind_cols(
  grid_df |> dplyr::select(month_idx_int),
  tibble::as_tibble(awp_mat_num)
) |>
  dplyr::mutate(r50_10 = p50 / p10, r90_50 = p90 / p50, r90_10 = p90 / p10) |>
  dplyr::filter(!is.na(p50))

awp_base_num   <- unlist(awp_df[1L, series_keys_chr])
awp_latest_num <- unlist(awp_df[nrow(awp_df), series_keys_chr])

# AWP era boundaries (awp_era_start_month_idx_int, configuration): each era
# ends the month before the next starts; the last ends at the latest month.
awp_era_df <- tidyr::expand_grid(
  era_df |>
    dplyr::transmute(
      era_i_int, era_slug_chr,
      awp_start_idx_int = awp_era_start_month_idx_int[era_i_int],
      awp_base_idx_int  = dplyr::if_else(era_i_int == 1L, awp_start_idx_int, awp_start_idx_int - 1L),
      end_idx_int       = dplyr::lead(awp_start_idx_int - 1L, default = latest_idx_int)
    ),
  series_chr = series_keys_chr
) |>
  dplyr::mutate(awp_base_num = NA_real_, awp_end_num = NA_real_)
for (r in seq_len(nrow(awp_era_df))) {
  key_chr <- awp_era_df$series_chr[r]
  awp_era_df$awp_base_num[r] <- awp_df[[key_chr]][awp_df$month_idx_int == awp_era_df$awp_base_idx_int[r]]
  awp_era_df$awp_end_num[r]  <- awp_df[[key_chr]][awp_df$month_idx_int == awp_era_df$end_idx_int[r]]
}
awp_era_df <- awp_era_df |>
  dplyr::mutate(awp_cumulative_pct_num = 100 * (awp_end_num / awp_base_num - 1))

# (a) Reference check.
awp_ours_df <- dplyr::bind_rows(
  tibble::tibble(series_chr = series_keys_chr, stat_chr = "last_index", era_i_int = NA_integer_,
                 ours_num = unname(100 * awp_latest_num / awp_base_num)),
  tibble::tibble(series_chr = series_keys_chr, stat_chr = "base_level", era_i_int = NA_integer_,
                 ours_num = unname(awp_base_num)),
  awp_era_df |> dplyr::transmute(series_chr, stat_chr = "era_cum_pct", era_i_int, ours_num = awp_cumulative_pct_num)
)
awp_ref_check_df <- reference_df |>
  dplyr::left_join(awp_ours_df, by = c("series_chr", "stat_chr", "era_i_int")) |>
  dplyr::mutate(
    ours_rounded_num = dplyr::if_else(stat_chr == "last_index", round(ours_num, 1), round(ours_num, 2)),
    diff_num         = ours_rounded_num - reference_num,
    match_bool       = abs(diff_num) < 1e-9
  )
readr::write_csv(awp_ref_check_df, awp_ref_csv_chr)
message(
  "figure_f_era_bars_tables.R -- AWP definition reproduces ", sum(awp_ref_check_df$match_bool),
  " of ", nrow(awp_ref_check_df), " AWP reference values"
)

# (b) Side-by-side: repo standard (plotted) vs. AWP definition.
awp_cmp_df <- era_growth_df |>
  dplyr::select(era_i_int, era_slug_chr, series_chr,
                repo_cumulative_pct_num = cumulative_pct_num,
                repo_annualized_pct_num = annualized_pct_num) |>
  dplyr::left_join(
    awp_era_df |> dplyr::select(era_i_int, series_chr, awp_cumulative_pct_num),
    by = c("era_i_int", "series_chr")
  ) |>
  dplyr::left_join(
    tibble::tibble(
      series_chr            = series_keys_chr,
      repo_last_index_num   = unname(last_index_num),
      awp_last_index_num    = unname(100 * awp_latest_num / awp_base_num)
    ),
    by = "series_chr"
  ) |>
  dplyr::mutate(cumulative_diff_pp_num = repo_cumulative_pct_num - awp_cumulative_pct_num)
readr::write_csv(awp_cmp_df, awp_cmp_csv_chr)
message(
  "figure_f_era_bars_tables.R -- repo standard vs. AWP definition: cumulative era change ",
  "differs by at most ", round(max(abs(awp_cmp_df$cumulative_diff_pp_num)), 2), " pp"
)

###################################
###   12) Verify outputs        ###
###################################

out_paths_chr <- c(pct_monthly_csv_chr, pct_roll_csv_chr, ratio_monthly_csv_chr, ratio_roll_csv_chr,
                   educ_monthly_csv_chr, educ_roll_csv_chr, pct_era_csv_chr, ratio_era_csv_chr,
                   educ_era_csv_chr, frac_csv_chr, awp_ref_csv_chr, awp_cmp_csv_chr)
out_missing_chr <- out_paths_chr[!fs::file_exists(out_paths_chr) | fs::file_size(out_paths_chr) == 0]
if (length(out_missing_chr) > 0L) {
  stop("figure_f_era_bars_tables.R -- output(s) missing or empty: ", paste(out_missing_chr, collapse = ", "))
}

message("figure_f_era_bars_tables.R -- done. Wrote ", length(out_paths_chr), " tables to ", tbl_out_dir_chr)
