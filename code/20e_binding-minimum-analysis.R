# 20e_binding-minimum-analysis -- weighted binding-share time series, subgroup tabulations, and BLS validation
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - what share of US wage and salary workers earn at or below the maximum of the federal, state, or local general minimum wage, 1979 through present?

rm(list = ls())
options(scipen = 999)
# set.seed retained for project-wide consistency; no randomness is used
# in this script.
set.seed(42)

# Sourced by run_all.R inside new.env(parent = globalenv()).
#
# This script reads the year-partitioned worker-level binding-indicator
# panel written by 20d, computes weighted shares of hourly-paid workers
# at or below several minimum-wage thresholds, and produces:
#
#   Figure:   output/figures/figure_d_binding_share_national.png
#             output/figures/figure_d_binding_share_monthly.png
#
#   Tables:   output/tables/figure_d_binding_share_yearly.csv
#             output/tables/figure_d_binding_share_monthly.csv
#             output/tables/figure_d_binding_share_by_state_yearly.csv
#             output/tables/figure_d_binding_share_by_demographic_yearly.csv
#
#   Validation: output/verification/2026-05-04_binding_validation.md
#               (compares our federal-binding share against BLS published
#               values from the Characteristics of Minimum Wage Workers
#               annual reports; reference CSV at
#               output/verification/bls_min_wage_workers_reference.csv)
#
# Two binding-share time series are reported in the headline figures
# and headline tables (figure_d_binding_share_national.png,
# figure_d_binding_share_monthly.png, figure_d_binding_share_yearly.csv,
# figure_d_binding_share_monthly.csv):
#   1. at_or_below_federal_share: hourly_wage <= federal MW. Computed
#      inline by comparing nominal_hourly_wage_num against the federal
#      MW (which is constant within each year given the FLSA schedule).
#      This is the BLS-comparable measure.
#   2. at_or_below_state_general_share: hourly_wage <= effective general
#      minimum, where the effective general minimum is the maximum of
#      the federal floor, the state floor, and any covered local floor
#      (Seattle, Chicago, NYC, San Francisco, Cook County, etc. via the
#      county_to_locality and individcc_to_locality concordances). Where
#      a local jurisdiction is not in the concordances, the value falls
#      back to max(federal, state); see the documented limitations in
#      the validation report. Column name retained for backward
#      compatibility -- the series now accounts for federal, state, and
#      tracked local minimums.
#
# A third tipped-aware series (at_or_below_applicable_share) was
# previously computed and reported. It has been dropped from the
# headline figures, the yearly and monthly summary tables, and the
# validation report because the tipped-subminimum construction is
# unreliable at this stage (incomplete coverage of partial-tip-credit
# states, and the legal question of which minimum applies to tipped
# workers is more nuanced than the panel currently captures). The
# at_or_below_applicable_flag is still present in the 20d worker-level
# panel and the column is still emitted in the by_state and by_demographic
# auxiliary tables so any downstream consumer that wants it can read it.
#
# All shares are weighted by EARNWT.
#
# No custom functions are defined; all transformations are inline.

source(here::here("code", "_utils", "00_packages.R"))
source(here::here("code", "_utils", "load_palette.R"))

###################################
###   Configuration             ###
###################################

panel_in_dir_chr   <- here::here("data", "intermediate", "cps_binding_indicator")
fig_out_dir_chr    <- here::here("output", "figures")
tbl_out_dir_chr    <- here::here("output", "tables")
verif_dir_chr      <- here::here("output", "verification")

fig_yearly_png_chr <- fs::path(fig_out_dir_chr, "figure_d_binding_share_national.png")
fig_monthly_png_chr <- fs::path(fig_out_dir_chr, "figure_d_binding_share_monthly.png")

tbl_yearly_csv_chr        <- fs::path(tbl_out_dir_chr, "figure_d_binding_share_yearly.csv")
tbl_monthly_csv_chr       <- fs::path(tbl_out_dir_chr, "figure_d_binding_share_monthly.csv")
tbl_by_state_csv_chr      <- fs::path(tbl_out_dir_chr, "figure_d_binding_share_by_state_yearly.csv")
tbl_by_demographic_csv_chr <- fs::path(tbl_out_dir_chr, "figure_d_binding_share_by_demographic_yearly.csv")

bls_reference_csv_chr     <- fs::path(verif_dir_chr,   "bls_min_wage_workers_reference.csv")
binding_validation_md_chr <- fs::path(verif_dir_chr,
  paste0(format(Sys.Date(), "%Y-%m-%d"), "_binding_validation.md")
)

# 2022 primary palette tokens (one per series). Two series now -- the
# tipped-aware "applicable" series has been dropped from headline
# outputs (see top-level docstring).
share_colors_chr <- c(
  "federal"     = unname(eig_palette_2022_primary["eig_blue_800"]),
  "state"       = unname(eig_palette_2022_primary["eig_teal_900"])
)

share_labels_chr <- c(
  "federal"     = "At or below federal minimum",
  "state"       = "At or below the maximum of federal, state, or local minimum"
)

share_levels_chr <- names(share_labels_chr)

# 12-month trailing rolling-mean window for the monthly figure, in calendar
# months (decision 08). Section 5 rolls over a calendar-complete grid, so a
# month with no data shortens the window rather than stretching it to 13
# calendar months. See docs/decisions/decision_12_figure_d_calendar_rolling_window.md.
rolling_window_int <- 12L

# Plot dimensions and DPI consistent with figure_a/b/c.
plot_width_in_num  <- 9
plot_height_in_num <- 5.5
plot_dpi_int       <- 300L

fs::dir_create(fig_out_dir_chr, recurse = TRUE)
fs::dir_create(tbl_out_dir_chr, recurse = TRUE)
fs::dir_create(verif_dir_chr,   recurse = TRUE)

###################################
###   1) Preflight              ###
###################################

panel_partitions_chr <- fs::dir_ls(
  panel_in_dir_chr, type = "directory", regexp = "year=\\d{4}$"
)

if (length(panel_partitions_chr) == 0L) {
  stop(
    "20e_binding-minimum-analysis.R -- no cps_binding_indicator year ",
    "partitions found in ", panel_in_dir_chr, ". Run 20d first."
  )
}

panel_years_int <- sort(as.integer(stringr::str_extract(
  basename(panel_partitions_chr), "\\d{4}"
)))

message(
  "20e_binding-minimum-analysis.R -- found ", length(panel_years_int),
  " year partitions covering ", min(panel_years_int), " - ",
  max(panel_years_int), "."
)

###################################
###   2) Load full panel        ###
###################################
# The binding-indicator panel is roughly 4.6 million rows total. Load
# all years into one tibble; the columns we need are a small subset of
# what 20d wrote.

partition_paths_chr <- vapply(
  panel_years_int,
  function(yr) fs::path(panel_in_dir_chr, paste0("year=", yr), "part-0.parquet"),
  character(1L)
)

# Column subset for the analysis. fed_mw_max_num is NOT in the 20d
# output; it is added below via a join to state_binding_panel_monthly.
needed_cols_chr <- c(
  "YEAR", "MONTH", "EARNWT", "AGE", "SEX", "PAIDHOUR",
  "STATEFIP", "OCC2010", "nominal_hourly_wage_num",
  "state_general_floor_num", "state_tipped_floor_num",
  "applicable_floor_num", "is_tipped_occupation_flag",
  "at_or_below_general_flag", "at_or_below_tipped_flag",
  "at_or_below_applicable_flag"
)

# Read each partition into a list, then bind once. Pre-allocating the
# list and binding in a single dplyr::bind_rows call avoids O(n^2)
# memory growth that an in-loop bind would trigger.
partition_dfs_ls <- vector("list", length(partition_paths_chr))
for (idx_int in seq_along(partition_paths_chr)) {
  partition_dfs_ls[[idx_int]] <- arrow::read_parquet(
    partition_paths_chr[[idx_int]],
    col_select = dplyr::all_of(needed_cols_chr)
  )
}
panel_df <- dplyr::bind_rows(partition_dfs_ls)
rm(partition_dfs_ls)

message(
  "20e_binding-minimum-analysis.R -- loaded full panel: ",
  format(nrow(panel_df), big.mark = ","), " rows; ",
  "weighted earnings sum = ",
  format(round(sum(panel_df$EARNWT, na.rm = TRUE)), big.mark = ",")
)

###################################
###   3) Attach federal MW      ###
###################################
# Read the state binding panel for fed_mw_max_num. Federal MW is
# identical across all states for any given (year, month), so we take
# the unique values per (year, month) and join.

state_binding_path_chr <- here::here(
  "data", "intermediate", "minimum_wage", "state_binding_panel_monthly.parquet"
)

if (!fs::file_exists(state_binding_path_chr)) {
  stop(
    "20e_binding-minimum-analysis.R -- state binding panel not found at ",
    state_binding_path_chr, ". Run 20c first."
  )
}

federal_floor_df <- arrow::read_parquet(state_binding_path_chr) |>
  dplyr::select(
    YEAR     = year_int,
    MONTH    = month_int,
    fed_mw_max_num
  ) |>
  dplyr::distinct()

panel_df <- panel_df |>
  dplyr::mutate(
    YEAR  = as.integer(YEAR),
    MONTH = as.integer(MONTH)
  ) |>
  dplyr::left_join(federal_floor_df, by = c("YEAR", "MONTH"))

panel_df <- panel_df |>
  dplyr::mutate(
    at_or_below_federal_flag = !is.na(fed_mw_max_num) &
      !is.na(nominal_hourly_wage_num) &
      nominal_hourly_wage_num <= fed_mw_max_num
  )

message(
  "20e_binding-minimum-analysis.R -- attached federal MW; computed ",
  "at_or_below_federal_flag for ", format(nrow(panel_df), big.mark = ","),
  " observations."
)

###################################
###   4) Yearly weighted shares ###
###################################
# For each year, compute the weighted share of hourly-paid worker
# observations at or below each of the three thresholds. Weights
# are EARNWT. Numerator: weighted count of TRUE flags. Denominator:
# weighted count of valid observations (non-NA flag).

valid_obs_bool <- !is.na(panel_df$nominal_hourly_wage_num) &
  !is.na(panel_df$EARNWT) & panel_df$EARNWT > 0

panel_valid_df <- panel_df[valid_obs_bool, , drop = FALSE]

# earnwt_pop_num is the average monthly population (summed EARNWT divided
# by the number of distinct survey months in the year via
# weighted_population()); the at_or_below_* shares are ratios of weighted
# sums and so are scale-invariant -- the month divisor cancels.
yearly_share_df <- panel_valid_df |>
  dplyr::group_by(YEAR) |>
  dplyr::summarise(
    n_obs_int                       = dplyr::n(),
    earnwt_pop_num                  = weighted_population(EARNWT, YEAR, MONTH),
    at_or_below_federal_share       = sum(EARNWT * at_or_below_federal_flag) / sum(EARNWT),
    at_or_below_state_general_share = sum(EARNWT * at_or_below_general_flag, na.rm = TRUE) /
      sum(EARNWT[!is.na(at_or_below_general_flag)]),
    .groups = "drop"
  ) |>
  dplyr::arrange(YEAR)

utils::write.csv(yearly_share_df, tbl_yearly_csv_chr, row.names = FALSE)

message(
  "20e_binding-minimum-analysis.R -- yearly share table: ",
  nrow(yearly_share_df), " years; ",
  "federal-binding range ", format(round(100 * min(yearly_share_df$at_or_below_federal_share), 2L), nsmall = 2L),
  "% to ", format(round(100 * max(yearly_share_df$at_or_below_federal_share), 2L), nsmall = 2L),
  "%; state-binding range ",
  format(round(100 * min(yearly_share_df$at_or_below_state_general_share), 2L), nsmall = 2L),
  "% to ",
  format(round(100 * max(yearly_share_df$at_or_below_state_general_share), 2L), nsmall = 2L),
  "%."
)

###################################
###   5) Monthly weighted shares ##
###################################

# Monthly weighted shares, one row per observed (year, month). A month with
# no CPS sample (October 2025, lost to the federal government shutdown) has
# no row here; the calendar grid below adds it back as an explicit NA row.
monthly_obs_df <- panel_valid_df |>
  dplyr::group_by(YEAR, MONTH) |>
  dplyr::summarise(
    n_obs_int                       = dplyr::n(),
    at_or_below_federal_share       = sum(EARNWT * at_or_below_federal_flag) / sum(EARNWT),
    at_or_below_state_general_share = sum(EARNWT * at_or_below_general_flag, na.rm = TRUE) /
      sum(EARNWT[!is.na(at_or_below_general_flag)]),
    .groups = "drop"
  ) |>
  dplyr::mutate(month_idx_int = as.integer(YEAR * 12L + MONTH - 1L))

# Both shares must be present in every observed month, so the one
# observed-month count (window_n_int) below describes both rolling series.
if (anyNA(monthly_obs_df$at_or_below_federal_share) ||
    anyNA(monthly_obs_df$at_or_below_state_general_share)) {
  stop(
    "20e_binding-minimum-analysis.R -- an observed month has an NA ",
    "monthly share; window_n_int would not describe both series."
  )
}

# Calendar-complete grid (month_idx_int = year * 12 + month - 1), first to
# last observed month, mirroring figure_a_percentiles.R step 3. Months with
# no data are explicit NA rows and are kept in the written CSV.
monthly_share_df <- tibble::tibble(
  month_idx_int = seq(min(monthly_obs_df$month_idx_int),
                      max(monthly_obs_df$month_idx_int))
) |>
  dplyr::mutate(
    YEAR  = as.integer(month_idx_int %/% 12L),
    MONTH = as.integer(month_idx_int %%  12L + 1L)
  ) |>
  dplyr::left_join(monthly_obs_df, by = c("month_idx_int", "YEAR", "MONTH")) |>
  dplyr::arrange(month_idx_int) |>
  dplyr::mutate(
    year_month_dt = as.Date(sprintf("%04d-%02d-01", YEAR, MONTH))
  )

missing_months_chr <- format(
  monthly_share_df$year_month_dt[is.na(monthly_share_df$n_obs_int)], "%Y-%m"
)
message(
  "20e_binding-minimum-analysis.R -- monthly calendar grid: ",
  nrow(monthly_share_df), " months; months with no data: ",
  if (length(missing_months_chr) == 0L) "none" else
    paste(missing_months_chr, collapse = ", ")
)

# 12-month trailing rolling mean per series over the calendar grid
# (decision 08; decision 12). A month with no data drops out of both the
# numerator and the denominator, so a window never reaches back a
# thirteenth month. Partial windows at series start are allowed.
# window_n_int counts the observed months in each window.
monthly_share_df <- monthly_share_df |>
  dplyr::mutate(
    federal_rolling_share = zoo::rollapplyr(
      data    = at_or_below_federal_share,
      width   = rolling_window_int,
      FUN     = function(x) {
        # The all-NA guard is required: mean(x, na.rm = TRUE) on an all-NA
        # window returns NaN, not NA_real_.
        if (all(is.na(x))) NA_real_ else mean(x, na.rm = TRUE)
      },
      fill    = NA_real_,
      partial = TRUE
    ),
    state_rolling_share = zoo::rollapplyr(
      data    = at_or_below_state_general_share,
      width   = rolling_window_int,
      FUN     = function(x) {
        if (all(is.na(x))) NA_real_ else mean(x, na.rm = TRUE)
      },
      fill    = NA_real_,
      partial = TRUE
    ),
    window_n_int = as.integer(zoo::rollapplyr(
      data    = !is.na(n_obs_int),
      width   = rolling_window_int,
      FUN     = sum,
      fill    = NA_integer_,
      partial = TRUE
    ))
  )

# Checks (the build stops on any failure).
#   (1) No rolling value is NA in a window with at least one observed month.
#   (2) Every rolling value, and every window_n_int, equals the plain mean
#       (count) over that row's calendar window [t-11, t], recomputed here
#       from month_idx_int rather than from row positions.
n_roll_na_int <- sum(
  monthly_share_df$window_n_int > 0L &
    (is.na(monthly_share_df$federal_rolling_share) |
       is.na(monthly_share_df$state_rolling_share))
)
if (n_roll_na_int > 0L) {
  stop(
    "20e_binding-minimum-analysis.R -- ", n_roll_na_int, " rolling value(s) ",
    "are NA in windows that contain observed months."
  )
}

audit_diff_num <- vapply(
  seq_len(nrow(monthly_share_df)),
  function(row_int) {
    in_window_bool <-
      monthly_share_df$month_idx_int >= monthly_share_df$month_idx_int[row_int] -
        (rolling_window_int - 1L) &
      monthly_share_df$month_idx_int <= monthly_share_df$month_idx_int[row_int]
    max(
      abs(mean(monthly_share_df$at_or_below_federal_share[in_window_bool], na.rm = TRUE) -
            monthly_share_df$federal_rolling_share[row_int]),
      abs(mean(monthly_share_df$at_or_below_state_general_share[in_window_bool], na.rm = TRUE) -
            monthly_share_df$state_rolling_share[row_int]),
      abs(sum(!is.na(monthly_share_df$n_obs_int[in_window_bool])) -
            monthly_share_df$window_n_int[row_int])
    )
  },
  numeric(1L)
)
if (any(is.na(audit_diff_num)) || max(audit_diff_num) > 1e-12) {
  stop(
    "20e_binding-minimum-analysis.R -- rolling mean does not equal the ",
    "calendar-window mean in ",
    sum(is.na(audit_diff_num) | audit_diff_num > 1e-12), " month(s)."
  )
}

short_window_bool <- monthly_share_df$window_n_int <
  pmin(rolling_window_int, seq_len(nrow(monthly_share_df)))
message(
  "20e_binding-minimum-analysis.R -- rolling-window checks passed for ",
  nrow(monthly_share_df), " months; windows with fewer than 12 observed ",
  "months (after the start-up year): ",
  if (!any(short_window_bool)) "none" else paste0(
    format(min(monthly_share_df$year_month_dt[short_window_bool]), "%Y-%m"), " to ",
    format(max(monthly_share_df$year_month_dt[short_window_bool]), "%Y-%m"),
    " (window_n_int ",
    paste(sort(unique(monthly_share_df$window_n_int[short_window_bool])), collapse = ", "),
    ")"
  )
)

utils::write.csv(
  dplyr::select(monthly_share_df, -month_idx_int),
  tbl_monthly_csv_chr, row.names = FALSE
)

message(
  "20e_binding-minimum-analysis.R -- monthly share table: ",
  nrow(monthly_share_df), " calendar months (",
  sum(!is.na(monthly_share_df$n_obs_int)), " with data)."
)

###################################
###   6) By-state yearly         ##
###################################

by_state_share_df <- panel_valid_df |>
  dplyr::group_by(STATEFIP, YEAR) |>
  dplyr::summarise(
    n_obs_int                    = dplyr::n(),
    earnwt_pop_num               = weighted_population(EARNWT, YEAR, MONTH),
    at_or_below_federal_share    = sum(EARNWT * at_or_below_federal_flag) / sum(EARNWT),
    at_or_below_state_share      = sum(EARNWT * at_or_below_general_flag, na.rm = TRUE) /
      sum(EARNWT[!is.na(at_or_below_general_flag)]),
    at_or_below_applicable_share = sum(EARNWT * at_or_below_applicable_flag, na.rm = TRUE) /
      sum(EARNWT[!is.na(at_or_below_applicable_flag)]),
    .groups = "drop"
  ) |>
  dplyr::arrange(STATEFIP, YEAR)

utils::write.csv(by_state_share_df, tbl_by_state_csv_chr, row.names = FALSE)

message(
  "20e_binding-minimum-analysis.R -- by-state yearly: ",
  nrow(by_state_share_df), " (state, year) cells across ",
  length(unique(by_state_share_df$STATEFIP)), " states."
)

###################################
###   7) By-demographic yearly   ##
###################################
# Six demographic splits: sex (1=male, 2=female), and three age bins
# (16-24, 25-54, 55+). Cross of sex x age bin produces six cells per
# year; we report each split independently rather than the cross to
# keep the table compact.

demographic_share_df <- panel_valid_df |>
  dplyr::mutate(
    # NA-AGE rows must be assigned an explicit NA bin; without this
    # branch case_when's `<` comparison returns NA, falls through to
    # the TRUE clause, and silently classifies missing-age workers as
    # 55+.
    age_bin_chr = dplyr::case_when(
      is.na(AGE)   ~ NA_character_,
      AGE <  25L   ~ "age_16_24",
      AGE <  55L   ~ "age_25_54",
      TRUE         ~ "age_55_plus"
    ),
    sex_chr = dplyr::case_when(
      SEX == 1L ~ "male",
      SEX == 2L ~ "female",
      TRUE      ~ "other_or_missing"
    )
  )

# Three by-group tables stacked into a long format with a group_var/group_value pair.
share_by_sex_df <- demographic_share_df |>
  dplyr::group_by(YEAR, sex_chr) |>
  dplyr::summarise(
    n_obs_int                    = dplyr::n(),
    at_or_below_state_share      = sum(EARNWT * at_or_below_general_flag, na.rm = TRUE) /
      sum(EARNWT[!is.na(at_or_below_general_flag)]),
    at_or_below_applicable_share = sum(EARNWT * at_or_below_applicable_flag, na.rm = TRUE) /
      sum(EARNWT[!is.na(at_or_below_applicable_flag)]),
    .groups = "drop"
  ) |>
  dplyr::transmute(
    YEAR,
    group_var_chr   = "sex",
    group_value_chr = sex_chr,
    n_obs_int,
    at_or_below_state_share,
    at_or_below_applicable_share
  )

share_by_age_df <- demographic_share_df |>
  dplyr::group_by(YEAR, age_bin_chr) |>
  dplyr::summarise(
    n_obs_int                    = dplyr::n(),
    at_or_below_state_share      = sum(EARNWT * at_or_below_general_flag, na.rm = TRUE) /
      sum(EARNWT[!is.na(at_or_below_general_flag)]),
    at_or_below_applicable_share = sum(EARNWT * at_or_below_applicable_flag, na.rm = TRUE) /
      sum(EARNWT[!is.na(at_or_below_applicable_flag)]),
    .groups = "drop"
  ) |>
  dplyr::transmute(
    YEAR,
    group_var_chr   = "age_bin",
    group_value_chr = age_bin_chr,
    n_obs_int,
    at_or_below_state_share,
    at_or_below_applicable_share
  )

share_by_tipped_df <- demographic_share_df |>
  dplyr::group_by(YEAR, is_tipped_occupation_flag) |>
  dplyr::summarise(
    n_obs_int                    = dplyr::n(),
    at_or_below_state_share      = sum(EARNWT * at_or_below_general_flag, na.rm = TRUE) /
      sum(EARNWT[!is.na(at_or_below_general_flag)]),
    at_or_below_applicable_share = sum(EARNWT * at_or_below_applicable_flag, na.rm = TRUE) /
      sum(EARNWT[!is.na(at_or_below_applicable_flag)]),
    .groups = "drop"
  ) |>
  dplyr::transmute(
    YEAR,
    group_var_chr   = "tipped_occupation",
    group_value_chr = ifelse(is_tipped_occupation_flag, "tipped", "non_tipped"),
    n_obs_int,
    at_or_below_state_share,
    at_or_below_applicable_share
  )

demographic_table_df <- dplyr::bind_rows(
  share_by_sex_df,
  share_by_age_df,
  share_by_tipped_df
) |>
  dplyr::arrange(group_var_chr, group_value_chr, YEAR)

utils::write.csv(demographic_table_df, tbl_by_demographic_csv_chr, row.names = FALSE)

message(
  "20e_binding-minimum-analysis.R -- by-demographic yearly table: ",
  nrow(demographic_table_df), " rows across 3 group_var splits ",
  "(sex, age_bin, tipped_occupation)."
)

###################################
###   8) National yearly figure  ##
###################################
# Three lines per the share_levels_chr vector. Long format for ggplot.

yearly_long_df <- yearly_share_df |>
  tidyr::pivot_longer(
    cols      = c(at_or_below_federal_share, at_or_below_state_general_share),
    names_to  = "series_chr",
    values_to = "share_num"
  ) |>
  dplyr::mutate(
    series_chr = dplyr::case_when(
      series_chr == "at_or_below_federal_share"       ~ "federal",
      series_chr == "at_or_below_state_general_share" ~ "state",
      TRUE                                            ~ series_chr
    ),
    series_chr = factor(series_chr, levels = share_levels_chr)
  )

yearly_plot <- ggplot2::ggplot(
  yearly_long_df,
  ggplot2::aes(
    x = YEAR, y = 100 * share_num,
    color = series_chr, linetype = series_chr
  )
) +
  ggplot2::geom_line(linewidth = 1.0) +
  ggplot2::geom_point(size = 1.6, alpha = 0.7) +
  ggplot2::scale_color_manual(
    values = share_colors_chr, labels = share_labels_chr,
    breaks = share_levels_chr, name = NULL
  ) +
  ggplot2::scale_linetype_manual(
    values = c("federal" = "solid", "state" = "solid"),
    labels = share_labels_chr, breaks = share_levels_chr, name = NULL
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::label_percent(scale = 1, accuracy = 0.1),
    limits = c(0, NA),
    expand = ggplot2::expansion(mult = c(0, 0.05))
  ) +
  ggplot2::scale_x_continuous(
    breaks = seq(1980, max(yearly_share_df$YEAR), by = 5L)
  ) +
  ggplot2::labs(
    title    = "Figure D. Share of hourly-paid CPS workers at or below the applicable minimum wage",
    subtitle = paste0("Annual share, ", min(yearly_share_df$YEAR), " through ",
                      max(yearly_share_df$YEAR),
                      "; weighted by EARNWT"),
    x        = NULL,
    y        = NULL,
    caption  = paste0(
      "Source: IPUMS-CPS Outgoing Rotation Group; Vaghul-Zipperer ",
      "historical minimum wages v1.4.0 extended through ",
      max(yearly_share_df$YEAR), " using DOL WHD and EPI Minimum Wage Tracker. ",
      "Local jurisdiction minimums (Seattle, Chicago, NYC, San Francisco, ",
      "Cook County, etc.) included via county_to_locality and ",
      "individcc_to_locality concordances; localities not in those ",
      "concordances fall back to state-level binding."
    )
  ) +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(
    panel.grid.major.x = ggplot2::element_blank(),
    panel.grid.minor   = ggplot2::element_blank(),
    panel.grid.major.y = ggplot2::element_line(color = "grey85", linewidth = 0.3),
    legend.position    = "top",
    legend.justification = "left",
    plot.title.position  = "plot",
    plot.caption.position = "plot",
    plot.caption       = ggplot2::element_text(hjust = 0, size = 8, color = "grey40"),
    axis.text          = ggplot2::element_text(color = "grey20")
  )

ggplot2::ggsave(
  filename = fig_yearly_png_chr,
  plot     = yearly_plot,
  width    = plot_width_in_num,
  height   = plot_height_in_num,
  dpi      = plot_dpi_int,
  bg       = "white"
)

message(
  "20e_binding-minimum-analysis.R -- wrote yearly figure: ", fig_yearly_png_chr
)

###################################
###   9) Monthly figure          ##
###################################

monthly_long_df <- monthly_share_df |>
  tidyr::pivot_longer(
    cols      = c(federal_rolling_share, state_rolling_share),
    names_to  = "series_chr",
    values_to = "share_num"
  ) |>
  dplyr::mutate(
    series_chr = dplyr::case_when(
      series_chr == "federal_rolling_share" ~ "federal",
      series_chr == "state_rolling_share"   ~ "state",
      TRUE                                  ~ series_chr
    ),
    series_chr = factor(series_chr, levels = share_levels_chr)
  )

monthly_plot <- ggplot2::ggplot(
  monthly_long_df,
  ggplot2::aes(
    x = year_month_dt, y = 100 * share_num,
    color = series_chr, linetype = series_chr
  )
) +
  ggplot2::geom_line(linewidth = 0.8) +
  ggplot2::scale_color_manual(
    values = share_colors_chr, labels = share_labels_chr,
    breaks = share_levels_chr, name = NULL
  ) +
  ggplot2::scale_linetype_manual(
    values = c("federal" = "solid", "state" = "solid"),
    labels = share_labels_chr, breaks = share_levels_chr, name = NULL
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::label_percent(scale = 1, accuracy = 0.1),
    limits = c(0, NA),
    expand = ggplot2::expansion(mult = c(0, 0.05))
  ) +
  ggplot2::scale_x_date(date_breaks = "5 years", date_labels = "%Y") +
  ggplot2::labs(
    title    = "Figure D (monthly). Share of hourly-paid CPS workers at or below the applicable minimum wage",
    subtitle = paste0("Twelve-month trailing rolling mean of monthly weighted shares, ",
                      format(min(monthly_share_df$year_month_dt), "%Y-%m"),
                      " through ",
                      format(max(monthly_share_df$year_month_dt), "%Y-%m")),
    x        = NULL, y = NULL,
    caption  = paste0(
      "Source: IPUMS-CPS Outgoing Rotation Group; Vaghul-Zipperer ",
      "historical minimum wages v1.4.0 extended through ",
      max(yearly_share_df$YEAR), " using DOL WHD and EPI Minimum Wage Tracker. ",
      "Local jurisdiction minimums (Seattle, Chicago, NYC, San Francisco, ",
      "Cook County, etc.) included via county_to_locality and ",
      "individcc_to_locality concordances; localities not in those ",
      "concordances fall back to state-level binding."
    )
  ) +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(
    panel.grid.major.x = ggplot2::element_blank(),
    panel.grid.minor   = ggplot2::element_blank(),
    panel.grid.major.y = ggplot2::element_line(color = "grey85", linewidth = 0.3),
    legend.position    = "top",
    legend.justification = "left",
    plot.title.position  = "plot",
    plot.caption.position = "plot",
    plot.caption       = ggplot2::element_text(hjust = 0, size = 8, color = "grey40"),
    axis.text          = ggplot2::element_text(color = "grey20")
  )

ggplot2::ggsave(
  filename = fig_monthly_png_chr,
  plot     = monthly_plot,
  width    = plot_width_in_num,
  height   = plot_height_in_num,
  dpi      = plot_dpi_int,
  bg       = "white"
)

message(
  "20e_binding-minimum-analysis.R -- wrote monthly figure: ", fig_monthly_png_chr
)

###################################
###   10) BLS validation         ##
###################################
# Compare our at_or_below_federal_share to BLS published values from the
# Characteristics of Minimum Wage Workers annual reports. The reference
# CSV is at output/verification/bls_min_wage_workers_reference.csv
# and is hand-curated; if missing, this section emits a template and
# skips the comparison.

if (!fs::file_exists(bls_reference_csv_chr)) {

  bls_template_df <- tibble::tibble(
    YEAR              = integer(0L),
    bls_share_num     = numeric(0L),
    bls_at_count_int  = integer(0L),
    bls_below_count_int = integer(0L),
    bls_total_hourly_int = integer(0L),
    source_url_chr    = character(0L),
    source_notes_chr  = character(0L)
  )
  utils::write.csv(bls_template_df, bls_reference_csv_chr, row.names = FALSE)

  message(
    "20e_binding-minimum-analysis.R -- BLS reference CSV not found; ",
    "wrote empty template at ", bls_reference_csv_chr,
    ". Populate with values from the BLS Characteristics of Minimum ",
    "Wage Workers annual reports (https://www.bls.gov/opub/reports/",
    "minimum-wage/) and re-run for validation comparison."
  )

  validation_block_chr <- c(
    "## BLS validation",
    "",
    "BLS reference CSV is empty. Populate ",
    paste0("`", bls_reference_csv_chr, "`"),
    "with values from the BLS Characteristics of Minimum Wage Workers ",
    "annual reports and re-run 20e for the comparison."
  )

} else {

  bls_reference_df <- utils::read.csv(bls_reference_csv_chr, stringsAsFactors = FALSE)

  if (nrow(bls_reference_df) == 0L) {

    validation_block_chr <- c(
      "## BLS validation",
      "",
      paste0("BLS reference CSV at `", bls_reference_csv_chr, "` is empty. ",
             "Populate with values from the BLS Characteristics of Minimum ",
             "Wage Workers annual reports and re-run 20e for the comparison.")
    )

  } else {

    bls_reference_df <- bls_reference_df |>
      dplyr::mutate(
        YEAR          = as.integer(YEAR),
        bls_share_num = as.numeric(bls_share_num)
      ) |>
      dplyr::select(YEAR, bls_share_num)

    validation_df <- yearly_share_df |>
      dplyr::select(YEAR, our_federal_share = at_or_below_federal_share) |>
      dplyr::inner_join(bls_reference_df, by = "YEAR") |>
      dplyr::mutate(
        diff_pct_pt_num = 100 * (our_federal_share - bls_share_num),
        passed_bool     = abs(diff_pct_pt_num) <= 1.0
      )

    n_validated_int <- nrow(validation_df)
    n_passed_int    <- sum(validation_df$passed_bool, na.rm = TRUE)

    validation_block_chr <- c(
      "## BLS validation",
      "",
      paste0("Reference: BLS Characteristics of Minimum Wage Workers ",
             "annual reports (https://www.bls.gov/opub/reports/minimum-wage/)."),
      "",
      paste0("Validated years: ", n_validated_int, "; ",
             "within +/- 1.0 percentage point of BLS: ", n_passed_int, "."),
      "",
      "| YEAR | Our federal-binding share | BLS published share | Diff (pct pts) | Pass |",
      "|------|---------------------------|---------------------|----------------|------|"
    )

    for (idx_int in seq_len(nrow(validation_df))) {
      row_ls <- validation_df[idx_int, ]
      validation_block_chr <- c(
        validation_block_chr,
        paste0(
          "| ", row_ls$YEAR, " | ",
          format(round(100 * row_ls$our_federal_share, 2), nsmall = 2), "% | ",
          format(round(100 * row_ls$bls_share_num, 2), nsmall = 2), "% | ",
          format(round(row_ls$diff_pct_pt_num, 2), nsmall = 2), " | ",
          ifelse(row_ls$passed_bool, "PASS", "FAIL"),
          " |"
        )
      )
    }
  }
}

###################################
###   11) Validation report      ##
###################################

report_chr <- c(
  paste0("# Binding-minimum-wage validation report -- ",
         format(Sys.Date(), "%Y-%m-%d")),
  "",
  paste0("**Pipeline:** 20e_binding-minimum-analysis.R"),
  paste0("**Panel rows:** ", format(nrow(panel_valid_df), big.mark = ","),
         " hourly-paid worker observations across ",
         length(unique(panel_valid_df$YEAR)), " years."),
  paste0("**Panel coverage:** ", min(panel_valid_df$YEAR), " through ",
         max(panel_valid_df$YEAR), "."),
  "",
  "## Headline shares",
  "",
  paste0("| Metric | Min year | Max year | Most recent year (",
         max(yearly_share_df$YEAR), ") |"),
  "|---|---|---|---|",
  paste0(
    "| At or below federal MW | ",
    format(round(100 * min(yearly_share_df$at_or_below_federal_share), 2), nsmall = 2), "% (",
    yearly_share_df$YEAR[which.min(yearly_share_df$at_or_below_federal_share)], ") | ",
    format(round(100 * max(yearly_share_df$at_or_below_federal_share), 2), nsmall = 2), "% (",
    yearly_share_df$YEAR[which.max(yearly_share_df$at_or_below_federal_share)], ") | ",
    format(round(100 * yearly_share_df$at_or_below_federal_share[
      which.max(yearly_share_df$YEAR)
    ], 2), nsmall = 2), "% |"
  ),
  paste0(
    "| At or below max(federal, state, local) | ",
    format(round(100 * min(yearly_share_df$at_or_below_state_general_share), 2), nsmall = 2), "% (",
    yearly_share_df$YEAR[which.min(yearly_share_df$at_or_below_state_general_share)], ") | ",
    format(round(100 * max(yearly_share_df$at_or_below_state_general_share), 2), nsmall = 2), "% (",
    yearly_share_df$YEAR[which.max(yearly_share_df$at_or_below_state_general_share)], ") | ",
    format(round(100 * yearly_share_df$at_or_below_state_general_share[
      which.max(yearly_share_df$YEAR)
    ], 2), nsmall = 2), "% |"
  ),
  "",
  paste0(
    "*Note: the previously reported tipped-aware applicable-binding ",
    "share has been dropped from the headline figures and tables ",
    "because the tipped-subminimum construction is unreliable at this ",
    "stage. The column is retained in the by_state and by_demographic ",
    "auxiliary tables for downstream consumers who want to inspect it.*"
  ),
  "",
  validation_block_chr,
  "",
  "## Documented limitations",
  "",
  paste0(
    "- **Sub-state binding floor partially merged.** For VZ-tracked ",
    "localities matched via county_to_locality.csv (Cook County, LA ",
    "County, Howard/Montgomery/Prince George's MD, Bernalillo and ",
    "Santa Fe NM, King WA, Long Island & Westchester NY) and via ",
    "individcc_to_locality.csv (Chicago, San Francisco, Los Angeles, ",
    "San Diego, Seattle, Oakland, Berkeley, San Jose, NYC, etc., ",
    "across both 2004-2014 and 2015-onward IPUMS code regimes), the ",
    "locality MW is now merged and reflected in effective_general_floor_num. ",
    "Localities not represented in the concordances (smaller California ",
    "Bay Area cities like Belmont, Cupertino, Daly City; Iowa counties ",
    "in extension YAML; Maine and Missouri cities) fall back to ",
    "state-level binding. Additionally, the VZ 2022-12-31 anchor used ",
    "for the 2023-2024 gap window mildly under-states indexed-city MW ",
    "in those years; full precision requires extending rate_from chain ",
    "inference to sub-state localities (currently state-level only)."
  ),
  paste0(
    "- **Tip-credit-banning states fully covered.** Seven states ban the ",
    "tip credit (Alaska, California, Minnesota, Montana, Nevada, Oregon, ",
    "Washington); their cash tipped subminimum equals the full state ",
    "minimum wage. The 20b section 8 panel build now applies this rule ",
    "from 1991-04-01 onward (when the federal cash subminimum was ",
    "frozen at $2.13). Hawaii is intentionally excluded: it allows a ",
    "small tip credit (~$0.75 below state MW), and approximating it ",
    "as fully banned would slightly overstate the binding share for ",
    "Hawaii tipped workers."
  ),
  paste0(
    "- **Partial-tip-credit states still on federal default.** A small ",
    "set of states (DC, NY, NJ, MA, MD, RI, MI, IL, ME, OH, AR, CT) ",
    "have cash tipped subminimums that are intermediate between federal ",
    "$2.13 and full state MW, often tied to state-specific schedules ",
    "(e.g., 60-66 percent of state MW or fixed dollar amounts). For ",
    "these states the panel currently uses federal $2.13 default, ",
    "under-stating the binding share for tipped workers in those ",
    "states. Sourcing requires Allegretto-Cooper 2014 EPI BP #379 ",
    "Appendix Table A1 plus DOL WHD Wayback Machine snapshots; the ",
    "expected magnitude of the under-statement is on the order of ",
    "0.1 to 0.3 percentage points on the headline applicable share."
  ),
  paste0(
    "- **Place of residence vs place of work.** CPS reports state and ",
    "county of residence; minimum-wage law applies at place of work. ",
    "For commuters across jurisdictional boundaries the binding floor ",
    "may be wrong. The pipeline assumes place of residence is a workable ",
    "proxy."
  )
)

writeLines(report_chr, con = binding_validation_md_chr)

message(
  "20e_binding-minimum-analysis.R -- wrote validation report: ",
  binding_validation_md_chr
)

###################################
###   Success log               ###
###################################

message(
  "20e_binding-minimum-analysis.R -- done. ",
  "Yearly figure, monthly figure, and four CSV tables written to ",
  fig_out_dir_chr, " and ", tbl_out_dir_chr, ". Validation report at ",
  binding_validation_md_chr, "."
)
