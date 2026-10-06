# figure_a_percentiles -- weighted real hourly wage percentiles (10/25/50/75/90) by month, level + indexed
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

rm(list = ls())
options(scipen = 999)
set.seed(42)

# Sourced by run_all.R inside new.env(parent = globalenv()).
#
# This script reads the year-partitioned real-wage panel written by 02a,
# computes weighted percentiles (10th, 25th, 50th, 75th, 90th) of the
# real hourly wage per (YEAR, MONTH) using EARNWT, and produces FIVE PNG
# figures (one level, four indexed) and matching CSV sidecars:
#
#   Level:                output/figures/figure_a_percentiles_level.png
#                         output/tables/figure_a_percentiles_level_monthly.csv
#                         output/tables/figure_a_percentiles_level_roll12.csv
#   Indexed (full panel): output/figures/figure_a_percentiles_indexed.png
#                         output/tables/figure_a_percentiles_indexed_monthly.csv
#                         output/tables/figure_a_percentiles_indexed_roll12.csv
#                         (both carry COVID sidecar columns
#                         p10_covid-p90_covid and covid_flag_int covering
#                         March 2020 to December 2021; see step 9)
#   Indexed (2001-2014):  output/figures/figure_a_percentiles_indexed_2001_2014.png
#                         output/tables/figure_a_percentiles_indexed_2001_2014_monthly.csv
#                         output/tables/figure_a_percentiles_indexed_2001_2014_roll12.csv
#   Indexed (2015-2020):  output/figures/figure_a_percentiles_indexed_2015_2020.png
#                         output/tables/figure_a_percentiles_indexed_2015_2020_monthly.csv
#                         output/tables/figure_a_percentiles_indexed_2015_2020_roll12.csv
#   Indexed (2021-now):   output/figures/figure_a_percentiles_indexed_2021_present.png
#                         output/tables/figure_a_percentiles_indexed_2021_present_monthly.csv
#                         output/tables/figure_a_percentiles_indexed_2021_present_roll12.csv
#   Indexed (named eras): output/figures/figure_a_percentiles_indexed_<slug>.png
#                         output/tables/figure_a_percentiles_indexed_<slug>_monthly.csv
#                         output/tables/figure_a_percentiles_indexed_<slug>_roll12.csv
#                         for the named eras (see step 8e): stagnation1,
#                         itboom, stagnation2, recovery, recovery_end2021,
#                         covid_aftermath, covid_aftermath_idx2021,
#                         covid_aftermath_idx2025m03, uncertainty.
#                         Each era is indexed to its own start month unless
#                         its spec names a separate anchor month.
#
# Each indexed version rebases by the 12-month rolling average at
# the anchor month, so the rolling average line sits at 100 at the anchor.
#
# Anchors:
#   * Full-panel indexed:  December 1982 (first month after the NBER-dated
#                          end of the 1981-82 recession, trough November
#                          1982), applied uniformly to every percentile.
#   * 2001-2014 subset:    February 2001 (month immediately preceding the
#                          NBER-dated March 2001 dot-com recession start).
#   * 2015-2020 subset:    January 2015.
#   * 2021-present subset: January 2021.
#
# Each figure shows monthly cell values as low-alpha points and a
# matching-color 12-month rolling average line per percentile.
# The rolling window is calendar-based [t-11, t]; missing months
# contribute NA and are dropped via na.rm = TRUE. Partial windows at
# series start are allowed.
#
# Weighted-quantile construction is inline: for each (YEAR, MONTH)
# cell, sort by real_hourly_wage_num ascending, cumulate EARNWT, and
# for each probability p select the smallest value whose cumulative
# weight is at least p * total weight (the Stata `_pctile` / EPI
# no-interpolation convention).
#
# Palette: 2022 primary EIG palette tokens loaded via load_palette.R.
# No custom functions are defined; all transformations are inline.

source(here::here("code", "_utils", "00_packages.R"))
source(here::here("code", "_utils", "load_palette.R"))
source(here::here("code", "_utils", "eig_fonts.R"))

###################################
###   Configuration             ###
###################################

panel_in_dir_chr    <- here::here("data", "intermediate", "cps_real_wages")
fig_out_dir_chr     <- here::here("output", "figures")
tbl_out_dir_chr     <- here::here("output", "tables")

fig_level_png_chr   <- fs::path(fig_out_dir_chr, "figure_a_percentiles_level.png")
fig_index_png_chr   <- fs::path(fig_out_dir_chr, "figure_a_percentiles_indexed.png")
fig_index_2001_png_chr <- fs::path(fig_out_dir_chr,
  "figure_a_percentiles_indexed_2001_2014.png")
fig_index_2015_png_chr <- fs::path(fig_out_dir_chr,
  "figure_a_percentiles_indexed_2015_2020.png")
fig_index_2021_png_chr <- fs::path(fig_out_dir_chr,
  "figure_a_percentiles_indexed_2021_present.png")

# One CSV per outcome type, wide by percentile (Datawrapper convention:
# one column per plotted series). Monthly and 12-month rolling average.
fig_level_monthly_csv_chr    <- fs::path(tbl_out_dir_chr,
  "figure_a_percentiles_level_monthly.csv")
fig_level_rolling_csv_chr    <- fs::path(tbl_out_dir_chr,
  "figure_a_percentiles_level_roll12.csv")
fig_index_monthly_csv_chr    <- fs::path(tbl_out_dir_chr,
  "figure_a_percentiles_indexed_monthly.csv")
fig_index_rolling_csv_chr    <- fs::path(tbl_out_dir_chr,
  "figure_a_percentiles_indexed_roll12.csv")
fig_index_2001_monthly_csv_chr <- fs::path(tbl_out_dir_chr,
  "figure_a_percentiles_indexed_2001_2014_monthly.csv")
fig_index_2001_rolling_csv_chr <- fs::path(tbl_out_dir_chr,
  "figure_a_percentiles_indexed_2001_2014_roll12.csv")
fig_index_2015_monthly_csv_chr <- fs::path(tbl_out_dir_chr,
  "figure_a_percentiles_indexed_2015_2020_monthly.csv")
fig_index_2015_rolling_csv_chr <- fs::path(tbl_out_dir_chr,
  "figure_a_percentiles_indexed_2015_2020_roll12.csv")
fig_index_2021_monthly_csv_chr <- fs::path(tbl_out_dir_chr,
  "figure_a_percentiles_indexed_2021_present_monthly.csv")
fig_index_2021_rolling_csv_chr <- fs::path(tbl_out_dir_chr,
  "figure_a_percentiles_indexed_2021_present_roll12.csv")

# 2022 primary palette tokens (one per percentile, low-to-high)
percentile_colors_chr <- c(
  "p10" = unname(eig_palette_2022_primary["eig_teal_900"]),
  "p25" = unname(eig_palette_2022_primary["eig_cyan_700"]),
  "p50" = unname(eig_palette_2022_primary["eig_blue_800"]),
  "p75" = unname(eig_palette_2022_primary["eig_green_700"]),
  "p90" = unname(eig_palette_2022_primary["eig_gold_600"])
)

percentile_labels_chr <- c(
  "p10" = "10th percentile",
  "p25" = "25th percentile",
  "p50" = "50th percentile (median)",
  "p75" = "75th percentile",
  "p90" = "90th percentile"
)

percentile_levels_chr <- names(percentile_labels_chr)

# Smoothing window. Per decision 08, the display series is a plain 12-month
# backward-facing rolling average: equal weight on every observed month in the
# calendar window [t-11, t], no recency weighting and no tuning parameter. See
# docs/decisions/decision_08_smoothing_12mo_flat.md. Supersedes the 12-month
# geometric EWMA of decision 07.
rolling_window_int <- 12L

# Indexed-figure anchors. All figures use fixed calendar months; subset
# rolling averages come from the full-panel rolling average column so the
# window at each anchor draws on prior-data months.
#
# Full-panel anchor: December 1982, the first month after the NBER-dated
# end of the 1981-82 recession (trough November 1982), applied uniformly
# to every percentile.
anchor_main_year_int  <- 1982L
anchor_main_month_int <- 12L

subset_2001_start_year_int  <- 2001L
subset_2001_start_month_int <- 2L
subset_2001_end_year_int    <- 2014L
subset_2001_end_month_int   <- 12L

subset_2015_start_year_int  <- 2015L
subset_2015_start_month_int <- 1L
subset_2015_end_year_int    <- 2020L
subset_2015_end_month_int   <- 12L

subset_2021_start_year_int  <- 2021L
subset_2021_start_month_int <- 1L
# 2021-present end month is determined dynamically as the latest month
# with non-NA percentile data in the panel.

# COVID window, used by the full-panel indexed figure and its CSV
# sidecars (steps 8a and 9).
#
# March 2020 through December 2021 is drawn as a separate dashed series:
# COVID-driven shifts in CPS sample composition confound the wage
# percentiles across that span. The solid series is blank across the
# window; the dashed series additionally carries one bridge month on each
# side -- February 2020 and January 2022 -- so it meets the solid line at
# both ends instead of leaving a one-month gap. Every month is therefore
# plotted by exactly one series except at the two bridge months.
covid_start_idx_int <- as.integer(2020L * 12L +  3L - 1L)  # Mar 2020
covid_end_idx_int   <- as.integer(2021L * 12L + 12L - 1L)  # Dec 2021
covid_lead_idx_int  <- covid_start_idx_int - 1L            # Feb 2020 bridge
covid_lag_idx_int   <- covid_end_idx_int   + 1L            # Jan 2022 bridge

# The 2015-2020 figure (step 8c) ends in December 2020 and keeps its own
# original calendar-year-2020 dashed treatment; it does not use the
# constants above.
boundary_2015_idx_int <- as.integer(2019L * 12L + 12L - 1L)  # Dec 2019

fs::dir_create(fig_out_dir_chr, recurse = TRUE)
fs::dir_create(tbl_out_dir_chr, recurse = TRUE)

###################################
###   1) Load real-wage panel   ###
###################################

if (!fs::dir_exists(panel_in_dir_chr)) {
  stop(
    "figure_a_percentiles.R -- real-wage panel not found at ",
    panel_in_dir_chr, ". Run 02a_build_real_wages.R first."
  )
}

# Explicit parquet-only file list -- the partition dirs also contain
# part-0.rds sidecars (EIG dual-format convention) which arrow cannot
# parse. YEAR and MONTH live inside each parquet as columns.
parquet_paths_chr <- fs::dir_ls(
  panel_in_dir_chr,
  regexp = "part-0\\.parquet$",
  recurse = TRUE,
  type   = "file"
)

if (length(parquet_paths_chr) == 0L) {
  stop(
    "figure_a_percentiles.R -- no part-0.parquet files found under ",
    panel_in_dir_chr, ". Run 02a_build_real_wages.R first."
  )
}

real_wage_ds <- arrow::open_dataset(parquet_paths_chr, format = "parquet")

real_wage_df <- real_wage_ds |>
  dplyr::select(YEAR, MONTH, EARNWT, real_hourly_wage_num) |>
  dplyr::collect()

required_cols_chr <- c("YEAR", "MONTH", "EARNWT", "real_hourly_wage_num")
missing_cols_chr  <- setdiff(required_cols_chr, names(real_wage_df))

if (length(missing_cols_chr) > 0L) {
  stop(
    "figure_a_percentiles.R -- real-wage panel missing column(s): ",
    paste(missing_cols_chr, collapse = ", ")
  )
}

message(
  "figure_a_percentiles.R -- loaded ",
  format(nrow(real_wage_df), big.mark = ","),
  " person-month records spanning ",
  min(real_wage_df$YEAR, na.rm = TRUE), "-",
  max(real_wage_df$YEAR, na.rm = TRUE)
)

###################################
###   2) Monthly percentiles    ###
###################################
# Within each (YEAR, MONTH): EARNWT-weighted percentiles via the shared
# weighted_quantile() helper (Stata `_pctile` / EPI no-interpolation
# convention). See code/_utils/weighted_stats.R.

valid_bool <- !is.na(real_wage_df$real_hourly_wage_num) &
  !is.na(real_wage_df$EARNWT) &
  real_wage_df$EARNWT > 0

percentile_wide_df <- real_wage_df[valid_bool, , drop = FALSE] |>
  dplyr::group_by(YEAR, MONTH) |>
  dplyr::summarise(
    n_cell_int = dplyr::n(),
    p10        = weighted_quantile(real_hourly_wage_num, EARNWT, 0.10),
    p25        = weighted_quantile(real_hourly_wage_num, EARNWT, 0.25),
    p50        = weighted_quantile(real_hourly_wage_num, EARNWT, 0.50),
    p75        = weighted_quantile(real_hourly_wage_num, EARNWT, 0.75),
    p90        = weighted_quantile(real_hourly_wage_num, EARNWT, 0.90),
    .groups    = "drop"
  ) |>
  dplyr::rename(
    year_int  = YEAR,
    month_int = MONTH
  ) |>
  dplyr::mutate(
    year_int  = as.integer(year_int),
    month_int = as.integer(month_int)
  )

message(
  "figure_a_percentiles.R -- computed percentiles for ",
  format(nrow(percentile_wide_df), big.mark = ","),
  " (year, month) cells spanning ",
  min(percentile_wide_df$year_int), "-",
  max(percentile_wide_df$year_int)
)

###################################
###   3) Calendar-complete grid ###
###################################
# Long-format reshape and left-join onto a full (month, percentile)
# calendar grid so missing months are explicit NA rows.
# month_idx_int = year * 12 + month - 1 (linear ordering).

percentile_wide_df <- percentile_wide_df |>
  dplyr::mutate(
    month_idx_int = as.integer(year_int * 12L + month_int - 1L)
  )

min_month_idx_int <- min(percentile_wide_df$month_idx_int)
max_month_idx_int <- max(percentile_wide_df$month_idx_int)

calendar_df <- tidyr::expand_grid(
  month_idx_int  = seq(min_month_idx_int, max_month_idx_int),
  percentile_chr = percentile_levels_chr
) |>
  dplyr::mutate(
    year_int  = as.integer(month_idx_int %/% 12L),
    month_int = as.integer(month_idx_int %%  12L + 1L)
  )

percentile_long_df <- percentile_wide_df |>
  tidyr::pivot_longer(
    cols      = dplyr::all_of(percentile_levels_chr),
    names_to  = "percentile_chr",
    values_to = "real_hourly_wage_num"
  ) |>
  dplyr::select(
    month_idx_int, year_int, month_int, percentile_chr,
    n_cell_int, real_hourly_wage_num
  )

percentile_panel_df <- calendar_df |>
  dplyr::left_join(
    percentile_long_df |>
      dplyr::select(month_idx_int, percentile_chr, n_cell_int, real_hourly_wage_num),
    by = c("month_idx_int", "percentile_chr")
  )

###################################
###   4) 12-month rolling average ###
###################################
# Backward-looking [t-11, t] calendar window per percentile, equally
# weighted. The window is adaptive to missing months: a month with no
# survey data (e.g. October 2025, lost to the federal government
# shutdown) drops out of both the numerator and the denominator, so the
# average is taken over the months actually observed rather than
# reaching back a thirteenth month. Partial windows at series start are
# allowed, and all-NA windows produce NA_real_.

percentile_panel_df <- percentile_panel_df |>
  dplyr::arrange(percentile_chr, month_idx_int) |>
  dplyr::group_by(percentile_chr) |>
  dplyr::mutate(
    real_hourly_wage_roll12_num = zoo::rollapplyr(
      data    = real_hourly_wage_num,
      width   = rolling_window_int,
      FUN     = function(x) {
        # Flat mean over observed months (decision 08). The all-NA guard is
        # required: mean(x, na.rm = TRUE) on an all-NA window returns NaN,
        # not NA_real_.
        if (all(is.na(x))) NA_real_ else mean(x, na.rm = TRUE)
      },
      fill    = NA_real_,
      partial = TRUE
    )
  ) |>
  dplyr::ungroup()

###################################
###   5) Validate level range   ###
###################################
# Outlier-trim bounds in Dec 2025 dollars: ~[$1.10, $442]/hr (Decision
# #5 uniform $200 1989-PCE). Monthly percentiles should fall comfortably
# inside this range; anything beyond $250/hr indicates a deflator or
# trim misconfiguration.

wage_min_num <- min(percentile_panel_df$real_hourly_wage_num, na.rm = TRUE)
wage_max_num <- max(percentile_panel_df$real_hourly_wage_num, na.rm = TRUE)

if (is.na(wage_min_num) || wage_min_num <= 0) {
  stop(
    "figure_a_percentiles.R -- computed percentile minimum is not ",
    "positive (", wage_min_num, "); abort before rendering."
  )
}

if (is.na(wage_max_num) || wage_max_num > 250) {
  stop(
    "figure_a_percentiles.R -- computed percentile maximum exceeds ",
    "$250/hr (", wage_max_num, "); likely an outlier-trim or deflator ",
    "misconfiguration. Abort before rendering."
  )
}

message(
  "figure_a_percentiles.R -- monthly percentile range: $",
  format(round(wage_min_num, 2), big.mark = ","), "/hr to $",
  format(round(wage_max_num, 2), big.mark = ","), "/hr"
)

###################################
###   6) Build indexed series   ###
###################################
# Anchor on the 12-month rolling average at a fixed calendar month --
# December 1982, the first month after the NBER-dated end of the 1981-82
# recession (trough November 1982) -- applied uniformly to every
# percentile. Scaling commutes with the rolling average, so the indexed
# rolling average line sits at 100 at the anchor month. The indexed raw
# point at the anchor is generally not 100: the trailing window
# [July 1982, December 1982] averages six cells, so the December cell
# need not equal its own rolling average.

# 6a) Per-percentile rolling average anchor at December 1982.

anchor_main_idx_int <- as.integer(
  anchor_main_year_int * 12L + anchor_main_month_int - 1L
)

anchor_main_df <- percentile_panel_df |>
  dplyr::filter(month_idx_int == anchor_main_idx_int) |>
  dplyr::transmute(
    percentile_chr,
    anchor_main_roll12_num = real_hourly_wage_roll12_num
  )

missing_anchor_main_chr <- setdiff(
  percentile_levels_chr,
  anchor_main_df$percentile_chr[!is.na(anchor_main_df$anchor_main_roll12_num)]
)

if (length(missing_anchor_main_chr) > 0L) {
  message(
    "figure_a_percentiles.R -- main-figure anchor (December 1982) missing ",
    "or NA for percentile(s): ",
    paste(missing_anchor_main_chr, collapse = ", "),
    ". Indexed values for those percentiles will be NA."
  )
}

# 6b) Apply the anchor to both the raw (point) and rolling (line) series.

percentile_panel_df <- percentile_panel_df |>
  dplyr::left_join(
    anchor_main_df |>
      dplyr::select(percentile_chr, anchor_main_roll12_num),
    by = "percentile_chr"
  ) |>
  dplyr::mutate(
    index_num = dplyr::if_else(
      !is.na(anchor_main_roll12_num) & anchor_main_roll12_num > 0,
      100 * real_hourly_wage_num       / anchor_main_roll12_num,
      NA_real_
    ),
    index_roll12_num = dplyr::if_else(
      !is.na(anchor_main_roll12_num) & anchor_main_roll12_num > 0,
      100 * real_hourly_wage_roll12_num / anchor_main_roll12_num,
      NA_real_
    )
  ) |>
  dplyr::mutate(
    date_dt         = as.Date(sprintf("%04d-%02d-01", year_int, month_int)),
    percentile_fct  = factor(
      percentile_chr,
      levels = percentile_levels_chr,
      labels = percentile_labels_chr
    )
  ) |>
  dplyr::arrange(percentile_chr, month_idx_int)

# Human-readable anchor label for the figure caption (fixed December 1982).
anchor_main_label_chr <- format(
  as.Date(sprintf(
    "%04d-%02d-01", anchor_main_year_int, anchor_main_month_int
  )),
  "%B %Y"
)

message(
  "figure_a_percentiles.R -- main indexed anchor month (fixed): ",
  anchor_main_label_chr
)

###################################
###   7) Plot -- level version  ###
###################################

fig_a_level_plot <- ggplot2::ggplot(
  percentile_panel_df,
  ggplot2::aes(
    x     = date_dt,
    color = percentile_fct
  )
) +
  ggplot2::geom_point(
    ggplot2::aes(y = real_hourly_wage_num),
    alpha = 0.3,
    size  = 0.9,
    na.rm = TRUE
  ) +
  ggplot2::geom_line(
    ggplot2::aes(y = real_hourly_wage_roll12_num),
    alpha     = 1.0,
    linewidth = 0.7,
    na.rm     = TRUE
  ) +
  ggplot2::scale_color_manual(
    values = stats::setNames(
      percentile_colors_chr,
      percentile_labels_chr[names(percentile_colors_chr)]
    ),
    name = "Percentile"
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::label_dollar(accuracy = 1L)
  ) +
  ggplot2::scale_x_date(
    date_breaks = "4 years",
    date_labels = "%Y"
  ) +
  ggplot2::labs(
    title    = "Figure 1a. Real hourly wage percentiles",
    subtitle = "Monthly weighted percentiles (points) and 12-month rolling average (line), in December 2025 PCE dollars",
    x        = NULL,
    y        = "Real hourly wage (Dec 2025 $)",
    caption  = stringr::str_wrap(paste0(
      "Source: IPUMS-CPS ORG, 1982 to latest; BEA PCEPI via FRED. ",
      "Sample: civilian wage-and-salary workers with EARNWT > 0 and a ",
      "non-missing hourly wage; workers age 16 and older. Census-imputed ",
      "(allocated) earnings records are retained, matching EPI's public ",
      "extract. Salaried workers who do not report usable weekly hours ",
      "are excluded from the hourly series. October 2025 data not collected ",
      "due to federal government shutdown. The line is an equally weighted, ",
      "backward-looking 12-month rolling average; months with no data drop ",
      "out of the window rather than shifting it."
    ), width = 120)
  ) +
  ggplot2::theme_minimal(base_size = 11, base_family = eig_font_body_chr) +
  ggplot2::theme(
    panel.grid.major.x = ggplot2::element_blank(),
    panel.grid.minor   = ggplot2::element_blank(),
    panel.border       = ggplot2::element_blank(),
    axis.line          = ggplot2::element_line(linewidth = 0.3),
    legend.position    = "right",
    plot.title         = ggplot2::element_text(face = "bold",
                                               family = eig_font_title_chr),
    plot.caption       = ggplot2::element_text(hjust = 0)
  )

ggplot2::ggsave(
  filename = fig_level_png_chr,
  plot     = fig_a_level_plot,
  width    = 10.0,
  height   = 5.6,
  units    = "in",
  dpi      = 300L,
  device   = eig_png_device
)

###################################
###   8) Plot -- indexed version#
###################################
# The rolling average line is split into three segments so March 2020
# through December 2021 draws dashed: COVID-driven shifts in CPS sample
# composition confound the percentiles across that span. February 2020
# and January 2022 each appear in two frames so the dashed segment meets
# the solid line at both ends without a gap. This matches the
# solid/dashed column split in the CSV sidecars (step 9).

panel_main_pre_df   <- percentile_panel_df |>
  dplyr::filter(month_idx_int <= covid_lead_idx_int)
panel_main_covid_df <- percentile_panel_df |>
  dplyr::filter(
    month_idx_int >= covid_lead_idx_int,
    month_idx_int <= covid_lag_idx_int
  )
panel_main_post_df  <- percentile_panel_df |>
  dplyr::filter(month_idx_int >= covid_lag_idx_int)

fig_a_index_plot <- ggplot2::ggplot(
  percentile_panel_df,
  ggplot2::aes(
    x     = date_dt,
    color = percentile_fct
  )
) +
  ggplot2::geom_hline(
    yintercept = 100,
    linetype   = "dashed",
    linewidth  = 0.3,
    color      = "#525252"
  ) +
  ggplot2::geom_point(
    ggplot2::aes(y = index_num),
    alpha = 0.3,
    size  = 0.9,
    na.rm = TRUE
  ) +
  ggplot2::geom_line(
    data = panel_main_pre_df,
    ggplot2::aes(y = index_roll12_num),
    alpha     = 1.0,
    linewidth = 0.7,
    na.rm     = TRUE
  ) +
  ggplot2::geom_line(
    data = panel_main_covid_df,
    ggplot2::aes(y = index_roll12_num),
    linetype  = "dashed",
    alpha     = 1.0,
    linewidth = 0.7,
    na.rm     = TRUE
  ) +
  ggplot2::geom_line(
    data = panel_main_post_df,
    ggplot2::aes(y = index_roll12_num),
    alpha     = 1.0,
    linewidth = 0.7,
    na.rm     = TRUE
  ) +
  ggplot2::scale_color_manual(
    values = stats::setNames(
      percentile_colors_chr,
      percentile_labels_chr[names(percentile_colors_chr)]
    ),
    name = "Percentile"
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::label_number(accuracy = 1L)
  ) +
  ggplot2::scale_x_date(
    date_breaks = "4 years",
    date_labels = "%Y"
  ) +
  ggplot2::labs(
    title    = paste0(
      "Figure 1b. Real hourly wage percentiles, indexed so the 12-month ",
      "rolling average equals 100 in ", anchor_main_label_chr
    ),
    subtitle = paste0(
      "Monthly weighted percentiles (points) and 12-month rolling average ",
      "(line, dashed March 2020 to December 2021), per-percentile growth ",
      "since the anchor month"
    ),
    x        = NULL,
    y        = paste0("Index (", anchor_main_label_chr, " 12-month rolling average = 100)"),
    caption  = stringr::str_wrap(paste0(
      "Source: IPUMS-CPS ORG, 1982 to latest; BEA PCEPI via FRED. ",
      "Sample: civilian wage-and-salary workers with EARNWT > 0 and a ",
      "non-missing hourly wage. Each percentile series is rescaled by ",
      "its 12-month rolling average evaluated at ", anchor_main_label_chr,
      " (the first month after the NBER-dated end of the 1981-82 ",
      "recession, trough November 1982), applied uniformly ",
      "to every percentile, so the rolling average line sits at 100 at the ",
      "anchor. Sample restricted to workers age 16 and older. Census-",
      "imputed (allocated) earnings records are retained, matching EPI's ",
      "public extract. Salaried workers who do not report usable weekly ",
      "hours are excluded from the hourly series. March 2020 through ",
      "December 2021 is drawn as a dashed segment: COVID-driven shifts ",
      "in CPS sample composition confound the wage percentiles across ",
      "that span. October ",
      "2025 data not collected due to federal government shutdown."
    ), width = 120)
  ) +
  ggplot2::theme_minimal(base_size = 11, base_family = eig_font_body_chr) +
  ggplot2::theme(
    panel.grid.major.x = ggplot2::element_blank(),
    panel.grid.minor   = ggplot2::element_blank(),
    panel.border       = ggplot2::element_blank(),
    axis.line          = ggplot2::element_line(linewidth = 0.3),
    legend.position    = "right",
    plot.title         = ggplot2::element_text(face = "bold",
                                               family = eig_font_title_chr),
    plot.caption       = ggplot2::element_text(hjust = 0)
  )

ggplot2::ggsave(
  filename = fig_index_png_chr,
  plot     = fig_a_index_plot,
  width    = 10.0,
  height   = 5.6,
  units    = "in",
  dpi      = 300L,
  device   = eig_png_device
)

###################################
###   8b) Indexed -- 2001-2014  ###
###################################
# Subset: Feb 2001 through Dec 2014; anchor: Feb 2001 (month immediately
# preceding the NBER-dated March 2001 dot-com recession start). The
# rolling average draws from the full-panel column so the window at Feb
# 2001 is [Sep 2000, Feb 2001].

subset_2001_start_idx_int <- as.integer(
  subset_2001_start_year_int * 12L + subset_2001_start_month_int - 1L
)
subset_2001_end_idx_int   <- as.integer(
  subset_2001_end_year_int   * 12L + subset_2001_end_month_int   - 1L
)

# 1) Capture the per-percentile rolling average anchor at February 2001.
anchor_2001_df <- percentile_panel_df |>
  dplyr::filter(month_idx_int == subset_2001_start_idx_int) |>
  dplyr::transmute(
    percentile_chr,
    anchor_2001_roll12_num = real_hourly_wage_roll12_num
  )

missing_anchor_2001_chr <- setdiff(
  percentile_levels_chr,
  anchor_2001_df$percentile_chr[!is.na(anchor_2001_df$anchor_2001_roll12_num)]
)

if (length(missing_anchor_2001_chr) > 0L) {
  message(
    "figure_a_percentiles.R -- 2001-2014 anchor (Feb 2001) missing or ",
    "NA for percentile(s): ",
    paste(missing_anchor_2001_chr, collapse = ", "),
    ". Indexed values for those percentiles will be NA."
  )
}

# 2) Slice the panel to the subset window and apply the anchor.
panel_2001_df <- percentile_panel_df |>
  dplyr::filter(
    month_idx_int >= subset_2001_start_idx_int,
    month_idx_int <= subset_2001_end_idx_int
  ) |>
  dplyr::left_join(anchor_2001_df, by = "percentile_chr") |>
  dplyr::mutate(
    index_subset_num = dplyr::if_else(
      !is.na(anchor_2001_roll12_num) & anchor_2001_roll12_num > 0,
      100 * real_hourly_wage_num       / anchor_2001_roll12_num,
      NA_real_
    ),
    index_subset_roll12_num = dplyr::if_else(
      !is.na(anchor_2001_roll12_num) & anchor_2001_roll12_num > 0,
      100 * real_hourly_wage_roll12_num / anchor_2001_roll12_num,
      NA_real_
    )
  )

# 3) Plot.
fig_a_index_2001_plot <- ggplot2::ggplot(
  panel_2001_df,
  ggplot2::aes(
    x     = date_dt,
    color = percentile_fct
  )
) +
  ggplot2::geom_hline(
    yintercept = 100,
    linetype   = "dashed",
    linewidth  = 0.3,
    color      = "#525252"
  ) +
  ggplot2::geom_point(
    ggplot2::aes(y = index_subset_num),
    alpha = 0.3,
    size  = 0.9,
    na.rm = TRUE
  ) +
  ggplot2::geom_line(
    ggplot2::aes(y = index_subset_roll12_num),
    alpha     = 1.0,
    linewidth = 0.7,
    na.rm     = TRUE
  ) +
  ggplot2::scale_color_manual(
    values = stats::setNames(
      percentile_colors_chr,
      percentile_labels_chr[names(percentile_colors_chr)]
    ),
    name = "Percentile"
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::label_number(accuracy = 1L)
  ) +
  ggplot2::scale_x_date(
    date_breaks = "2 years",
    date_labels = "%Y"
  ) +
  ggplot2::labs(
    title    = paste0(
      "Figure 1b-i. Real hourly wage percentiles, February 2001 to ",
      "December 2014"
    ),
    subtitle = paste0(
      "Monthly weighted percentiles (points) and 12-month rolling average ",
      "(line), indexed so the rolling average equals 100 in February 2001"
    ),
    x        = NULL,
    y        = "Index (Feb 2001 12-month rolling average = 100)",
    caption  = stringr::str_wrap(paste0(
      "Source: IPUMS-CPS ORG; BEA PCEPI via FRED. Sample: civilian ",
      "wage-and-salary workers with EARNWT > 0 and a non-missing ",
      "hourly wage. Each percentile series is rescaled by its 12-month ",
      "rolling average evaluated at February 2001, the month ",
      "immediately preceding the NBER-dated March 2001 dot-com ",
      "recession start. The window at February 2001 uses prior-data ",
      "months (September 2000 to February 2001)."
    ), width = 120)
  ) +
  ggplot2::theme_minimal(base_size = 11, base_family = eig_font_body_chr) +
  ggplot2::theme(
    panel.grid.major.x = ggplot2::element_blank(),
    panel.grid.minor   = ggplot2::element_blank(),
    panel.border       = ggplot2::element_blank(),
    axis.line          = ggplot2::element_line(linewidth = 0.3),
    legend.position    = "right",
    plot.title         = ggplot2::element_text(face = "bold",
                                               family = eig_font_title_chr),
    plot.caption       = ggplot2::element_text(hjust = 0)
  )

ggplot2::ggsave(
  filename = fig_index_2001_png_chr,
  plot     = fig_a_index_2001_plot,
  width    = 10.0,
  height   = 5.6,
  units    = "in",
  dpi      = 300L,
  device   = eig_png_device
)

###################################
###   8c) Indexed -- 2015-2020  ###
###################################
# Subset: Jan 2015 through Dec 2020; anchor: Jan 2015. Calendar-year
# 2020 months are flagged (covid_2020_flag_int) and drawn as a dashed
# line segment because COVID-driven changes in CPS composition confound
# the 2020 wage percentiles relative to the 2015-2019 baseline.

subset_2015_start_idx_int <- as.integer(
  subset_2015_start_year_int * 12L + subset_2015_start_month_int - 1L
)
subset_2015_end_idx_int   <- as.integer(
  subset_2015_end_year_int   * 12L + subset_2015_end_month_int   - 1L
)

# 1) Capture the per-percentile rolling average anchor at January 2015.
anchor_2015_df <- percentile_panel_df |>
  dplyr::filter(month_idx_int == subset_2015_start_idx_int) |>
  dplyr::transmute(
    percentile_chr,
    anchor_2015_roll12_num = real_hourly_wage_roll12_num
  )

missing_anchor_2015_chr <- setdiff(
  percentile_levels_chr,
  anchor_2015_df$percentile_chr[!is.na(anchor_2015_df$anchor_2015_roll12_num)]
)

if (length(missing_anchor_2015_chr) > 0L) {
  message(
    "figure_a_percentiles.R -- 2015-2020 anchor (Jan 2015) missing or ",
    "NA for percentile(s): ",
    paste(missing_anchor_2015_chr, collapse = ", "),
    ". Indexed values for those percentiles will be NA."
  )
}

# 2) Slice the panel to the subset window and apply the anchor. The
#    covid_2020_flag_int marks calendar-year 2020 months (1L) versus
#    2015-2019 months (0L) for the dashed-segment treatment and the CSV.
panel_2015_df <- percentile_panel_df |>
  dplyr::filter(
    month_idx_int >= subset_2015_start_idx_int,
    month_idx_int <= subset_2015_end_idx_int
  ) |>
  dplyr::left_join(anchor_2015_df, by = "percentile_chr") |>
  dplyr::mutate(
    index_subset_num = dplyr::if_else(
      !is.na(anchor_2015_roll12_num) & anchor_2015_roll12_num > 0,
      100 * real_hourly_wage_num       / anchor_2015_roll12_num,
      NA_real_
    ),
    index_subset_roll12_num = dplyr::if_else(
      !is.na(anchor_2015_roll12_num) & anchor_2015_roll12_num > 0,
      100 * real_hourly_wage_roll12_num / anchor_2015_roll12_num,
      NA_real_
    ),
    covid_2020_flag_int = dplyr::if_else(year_int == 2020L, 1L, 0L)
  )

# Split the rolling average line into a solid 2015-2019 segment and a
# dashed 2020 segment. December 2019 (the last pre-2020 month) is
# included in both frames so the two segments join without a visible gap.
# boundary_2015_idx_int is defined in the Configuration block.

panel_2015_pre_df   <- panel_2015_df |>
  dplyr::filter(month_idx_int <= boundary_2015_idx_int)
panel_2015_covid_df <- panel_2015_df |>
  dplyr::filter(month_idx_int >= boundary_2015_idx_int)

# 3) Plot.
fig_a_index_2015_plot <- ggplot2::ggplot(
  panel_2015_df,
  ggplot2::aes(
    x     = date_dt,
    color = percentile_fct
  )
) +
  ggplot2::geom_hline(
    yintercept = 100,
    linetype   = "dashed",
    linewidth  = 0.3,
    color      = "#525252"
  ) +
  ggplot2::geom_point(
    ggplot2::aes(y = index_subset_num),
    alpha = 0.3,
    size  = 0.9,
    na.rm = TRUE
  ) +
  ggplot2::geom_line(
    data = panel_2015_pre_df,
    ggplot2::aes(y = index_subset_roll12_num),
    alpha     = 1.0,
    linewidth = 0.7,
    na.rm     = TRUE
  ) +
  ggplot2::geom_line(
    data = panel_2015_covid_df,
    ggplot2::aes(y = index_subset_roll12_num),
    linetype  = "dashed",
    alpha     = 1.0,
    linewidth = 0.7,
    na.rm     = TRUE
  ) +
  ggplot2::scale_color_manual(
    values = stats::setNames(
      percentile_colors_chr,
      percentile_labels_chr[names(percentile_colors_chr)]
    ),
    name = "Percentile"
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::label_number(accuracy = 1L)
  ) +
  ggplot2::scale_x_date(
    date_breaks = "1 year",
    date_labels = "%Y"
  ) +
  ggplot2::labs(
    title    = paste0(
      "Figure 1b-ii. Real hourly wage percentiles, January 2015 to ",
      "December 2020"
    ),
    subtitle = paste0(
      "Monthly weighted percentiles (points) and 12-month rolling average ",
      "(line, dashed in 2020), indexed so the rolling average equals 100 ",
      "in January 2015"
    ),
    x        = NULL,
    y        = "Index (Jan 2015 12-month rolling average = 100)",
    caption  = stringr::str_wrap(paste0(
      "Source: IPUMS-CPS ORG; BEA PCEPI via FRED. Sample: civilian ",
      "wage-and-salary workers with EARNWT > 0 and a non-missing ",
      "hourly wage. Each percentile series is rescaled by its 12-month ",
      "rolling average evaluated at January 2015. The window at ",
      "January 2015 uses prior-data months (August 2014 to January ",
      "2015). Calendar-year 2020 months are drawn as a dashed segment: ",
      "COVID-driven shifts in CPS sample composition confound the 2020 ",
      "wage percentiles relative to the 2015-2019 baseline."
    ), width = 120)
  ) +
  ggplot2::theme_minimal(base_size = 11, base_family = eig_font_body_chr) +
  ggplot2::theme(
    panel.grid.major.x = ggplot2::element_blank(),
    panel.grid.minor   = ggplot2::element_blank(),
    panel.border       = ggplot2::element_blank(),
    axis.line          = ggplot2::element_line(linewidth = 0.3),
    legend.position    = "right",
    plot.title         = ggplot2::element_text(face = "bold",
                                               family = eig_font_title_chr),
    plot.caption       = ggplot2::element_text(hjust = 0)
  )

ggplot2::ggsave(
  filename = fig_index_2015_png_chr,
  plot     = fig_a_index_2015_plot,
  width    = 10.0,
  height   = 5.6,
  units    = "in",
  dpi      = 300L,
  device   = eig_png_device
)

###################################
###   8d) Indexed -- 2021-now   ###
###################################
# Subset: Jan 2021 through the most recent non-NA month; anchor: Jan 2021.

subset_2021_start_idx_int <- as.integer(
  subset_2021_start_year_int * 12L + subset_2021_start_month_int - 1L
)

# Latest non-NA cell (real data collected, not a calendar slot).
subset_2021_end_idx_int <- max(
  percentile_panel_df$month_idx_int[
    !is.na(percentile_panel_df$real_hourly_wage_num)
  ]
)

subset_2021_end_year_int  <- as.integer(subset_2021_end_idx_int %/% 12L)
subset_2021_end_month_int <- as.integer(subset_2021_end_idx_int %%  12L + 1L)
subset_2021_end_label_chr <- format(
  as.Date(sprintf(
    "%04d-%02d-01",
    subset_2021_end_year_int,
    subset_2021_end_month_int
  )),
  "%B %Y"
)

message(
  "figure_a_percentiles.R -- 2021-present subset end month: ",
  subset_2021_end_label_chr
)

# 1) Capture the per-percentile rolling average anchor at January 2021.
anchor_2021_df <- percentile_panel_df |>
  dplyr::filter(month_idx_int == subset_2021_start_idx_int) |>
  dplyr::transmute(
    percentile_chr,
    anchor_2021_roll12_num = real_hourly_wage_roll12_num
  )

missing_anchor_2021_chr <- setdiff(
  percentile_levels_chr,
  anchor_2021_df$percentile_chr[!is.na(anchor_2021_df$anchor_2021_roll12_num)]
)

if (length(missing_anchor_2021_chr) > 0L) {
  message(
    "figure_a_percentiles.R -- 2021-present anchor (Jan 2021) missing ",
    "or NA for percentile(s): ",
    paste(missing_anchor_2021_chr, collapse = ", "),
    ". Indexed values for those percentiles will be NA."
  )
}

# 2) Slice the panel to the subset window and apply the anchor.
panel_2021_df <- percentile_panel_df |>
  dplyr::filter(
    month_idx_int >= subset_2021_start_idx_int,
    month_idx_int <= subset_2021_end_idx_int
  ) |>
  dplyr::left_join(anchor_2021_df, by = "percentile_chr") |>
  dplyr::mutate(
    index_subset_num = dplyr::if_else(
      !is.na(anchor_2021_roll12_num) & anchor_2021_roll12_num > 0,
      100 * real_hourly_wage_num       / anchor_2021_roll12_num,
      NA_real_
    ),
    index_subset_roll12_num = dplyr::if_else(
      !is.na(anchor_2021_roll12_num) & anchor_2021_roll12_num > 0,
      100 * real_hourly_wage_roll12_num / anchor_2021_roll12_num,
      NA_real_
    )
  )

# 3) Plot.
fig_a_index_2021_plot <- ggplot2::ggplot(
  panel_2021_df,
  ggplot2::aes(
    x     = date_dt,
    color = percentile_fct
  )
) +
  ggplot2::geom_hline(
    yintercept = 100,
    linetype   = "dashed",
    linewidth  = 0.3,
    color      = "#525252"
  ) +
  ggplot2::geom_point(
    ggplot2::aes(y = index_subset_num),
    alpha = 0.3,
    size  = 0.9,
    na.rm = TRUE
  ) +
  ggplot2::geom_line(
    ggplot2::aes(y = index_subset_roll12_num),
    alpha     = 1.0,
    linewidth = 0.7,
    na.rm     = TRUE
  ) +
  ggplot2::scale_color_manual(
    values = stats::setNames(
      percentile_colors_chr,
      percentile_labels_chr[names(percentile_colors_chr)]
    ),
    name = "Percentile"
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::label_number(accuracy = 1L)
  ) +
  ggplot2::scale_x_date(
    date_breaks = "1 year",
    date_labels = "%Y"
  ) +
  ggplot2::labs(
    title    = paste0(
      "Figure 1b-iii. Real hourly wage percentiles, January 2021 to ",
      subset_2021_end_label_chr
    ),
    subtitle = paste0(
      "Monthly weighted percentiles (points) and 12-month rolling average ",
      "(line), indexed so the rolling average equals 100 in January 2021"
    ),
    x        = NULL,
    y        = "Index (Jan 2021 12-month rolling average = 100)",
    caption  = stringr::str_wrap(paste0(
      "Source: IPUMS-CPS ORG; BEA PCEPI via FRED. Sample: civilian ",
      "wage-and-salary workers with EARNWT > 0 and a non-missing ",
      "hourly wage. Each percentile series is rescaled by its 12-month ",
      "rolling average evaluated at January 2021. The window at ",
      "January 2021 uses prior-data months (August 2020 to January ",
      "2021). October 2025 data not collected due to federal ",
      "government shutdown."
    ), width = 120)
  ) +
  ggplot2::theme_minimal(base_size = 11, base_family = eig_font_body_chr) +
  ggplot2::theme(
    panel.grid.major.x = ggplot2::element_blank(),
    panel.grid.minor   = ggplot2::element_blank(),
    panel.border       = ggplot2::element_blank(),
    axis.line          = ggplot2::element_line(linewidth = 0.3),
    legend.position    = "right",
    plot.title         = ggplot2::element_text(face = "bold",
                                               family = eig_font_title_chr),
    plot.caption       = ggplot2::element_text(hjust = 0)
  )

ggplot2::ggsave(
  filename = fig_index_2021_png_chr,
  plot     = fig_a_index_2021_plot,
  width    = 10.0,
  height   = 5.6,
  units    = "in",
  dpi      = 300L,
  device   = eig_png_device
)

###################################
###   8e) Indexed -- named eras ###
###################################
# Additional indexed subsets, one per named U.S. wage-history era.
# Each is rebased by default to its own START month: the per-percentile
# 12-month rolling average at the anchor month is set to 100, and both the
# raw (point) and rolling (line) series are rescaled by that anchor.
# A spec may set anchor_year_int / anchor_month_int to rebase on a month
# other than the start. That is used by covid_aftermath_idx2025m03, which
# keeps the January 2021 window but rebases on March 2025, so the chart
# reads as change relative to March 2025 and pre-anchor months sit off 100.
# The anchor window is calendar-based [anchor-11, anchor] and draws on
# prior-data months exactly like the 2001/2015/2021 subsets above.
#
# Eras (start -> end; "latest" = most recent non-NA data month):
#   stagnation1      First Long Wage Stagnation*      1982m12 -> 1996m08
#   itboom           Late-1990s IT boom               1996m09 -> 2001m02
#   stagnation2      Second Long Wage Stagnation      2001m03 -> 2014m10
#   recovery         Nascent Recovery Slams into COVID 2014m11 -> 2020m02
#   covid_aftermath  COVID Aftermath                  2020m03 -> latest
#   uncertainty      Age of economic uncertainty      2024m01 -> latest
#
# stagnation2 keeps its March 2001 window but is anchored 2003m01, and
# covid_aftermath keeps its March 2020 window but is anchored 2022m01.
#
# Two variants share the COVID Aftermath window but differ in anchor:
#   covid_aftermath_idx2021     2021m01 -> latest, anchored 2021m01
#   covid_aftermath_idx2025m03  2021m01 -> latest, anchored 2025m03
#
# * First Long Wage Stagnation begins December 1982, the start of the
#   available IPUMS-CPS ORG monthly data (the first month after the
#   NBER-dated end of the 1981-82 recession, trough November 1982); any
#   earlier stagnation is not observed in this data.
#
# Each era writes one PNG and two wide CSV sidecars (monthly raw and
# 12-month rolling), schema: year_int, month_int, date_dt, p10..p90.
# This section is self-contained: it renders, writes, and verifies its
# own outputs and does not depend on sections 9 or 10.

# Latest non-NA data month (real data collected, not a calendar slot);
# used for the two eras whose end is "now".
era_latest_idx_int <- max(
  percentile_panel_df$month_idx_int[
    !is.na(percentile_panel_df$real_hourly_wage_num)
  ]
)

# Era specification list. end_year/end_month NA => dynamic latest month.
# caption_extra_chr appends era-specific notes to the shared caption.
era_specs_list <- list(
  list(
    slug_chr        = "stagnation1",
    title_chr       = "First Long Wage Stagnation*",
    start_year_int  = 1982L, start_month_int = 12L,
    end_year_int    = 1996L, end_month_int   = 8L,
    caption_extra_chr = paste0(
      " * This era begins December 1982, the start of the available ",
      "IPUMS-CPS ORG monthly data (the first month after the NBER-dated ",
      "end of the 1981-82 recession, trough November 1982); any earlier ",
      "wage stagnation is not observed in this data."
    )
  ),
  list(
    slug_chr        = "itboom",
    title_chr       = "Late-1990s IT boom",
    start_year_int  = 1996L, start_month_int = 9L,
    end_year_int    = 2001L, end_month_int   = 2L,
    caption_extra_chr = ""
  ),
  # Full March 2001 window, rebased to January 2003 = 100, so the chart
  # reads as change relative to January 2003; the 2001-2002 months sit
  # off 100 on the same scale.
  list(
    slug_chr         = "stagnation2",
    title_chr        = "Second Long Wage Stagnation",
    start_year_int   = 2001L, start_month_int  = 3L,
    end_year_int     = 2014L, end_month_int    = 10L,
    anchor_year_int  = 2003L, anchor_month_int = 1L,
    caption_extra_chr = ""
  ),
  list(
    slug_chr        = "recovery",
    title_chr       = "Nascent Recovery Slams into COVID",
    start_year_int  = 2014L, start_month_int = 11L,
    end_year_int    = 2020L, end_month_int   = 2L,
    caption_extra_chr = ""
  ),
  # Same era and anchor (November 2014) as "recovery", extended through
  # January 2021 so the run into and one year past the COVID onset is
  # visible; the 2020 caveat applies because 2020 is now in range.
  list(
    slug_chr        = "recovery_end2021",
    title_chr       = "Nascent Recovery Slams into COVID",
    start_year_int  = 2014L, start_month_int = 11L,
    end_year_int    = 2021L, end_month_int   = 1L,
    caption_extra_chr = paste0(
      " Calendar-year 2020 percentiles are confounded by COVID-driven ",
      "shifts in CPS sample composition and should be read with caution ",
      "relative to the surrounding months."
    )
  ),
  # Starts March 2020 (the first COVID month, matching the dashed span and
  # Figure 6 era 5) but is rebased to January 2022 = 100, when the
  # composition effect measured by 12_covid_composition_diagnostic.R had
  # largely cleared from the 12-month rolling base (Decision 10).
  list(
    slug_chr         = "covid_aftermath",
    title_chr        = "COVID Aftermath",
    start_year_int   = 2020L, start_month_int  = 3L,
    end_year_int     = NA_integer_, end_month_int = NA_integer_,
    anchor_year_int  = 2022L, anchor_month_int = 1L,
    caption_extra_chr = paste0(
      " March 2020 to December 2021 percentiles are confounded by ",
      "COVID-driven shifts in CPS sample composition; the index is set to ",
      "January 2022, when that composition effect had largely cleared."
    )
  ),
  # COVID Aftermath rebased to January 2021 = 100 (range starts January
  # 2021, so the confounded 2020 months are outside the window and no
  # 2020 caveat is needed).
  list(
    slug_chr        = "covid_aftermath_idx2021",
    title_chr       = "COVID Aftermath",
    start_year_int  = 2021L, start_month_int = 1L,
    end_year_int    = NA_integer_, end_month_int = NA_integer_,
    caption_extra_chr = ""
  ),
  # Same window as covid_aftermath_idx2021 (January 2021 to latest) but
  # rebased to March 2025 = 100, so the chart reads as change relative to
  # March 2025 rather than cumulative change since January 2021. Months
  # before March 2025 therefore sit below or above 100 on the same scale.
  list(
    slug_chr         = "covid_aftermath_idx2025m03",
    title_chr        = "COVID Aftermath",
    start_year_int   = 2021L, start_month_int  = 1L,
    end_year_int     = NA_integer_, end_month_int = NA_integer_,
    anchor_year_int  = 2025L, anchor_month_int = 3L,
    caption_extra_chr = ""
  ),
  list(
    slug_chr        = "uncertainty",
    title_chr       = "Age of economic uncertainty",
    start_year_int  = 2024L, start_month_int = 1L,
    end_year_int    = NA_integer_, end_month_int = NA_integer_,
    caption_extra_chr = ""
  )
)

for (era_spec in era_specs_list) {

  era_start_idx_int <- as.integer(
    era_spec$start_year_int * 12L + era_spec$start_month_int - 1L
  )

  # Dynamic end for "now" eras; otherwise the fixed calendar end month.
  era_end_idx_int <- if (is.na(era_spec$end_year_int)) {
    era_latest_idx_int
  } else {
    as.integer(era_spec$end_year_int * 12L + era_spec$end_month_int - 1L)
  }

  era_end_year_int  <- as.integer(era_end_idx_int %/% 12L)
  era_end_month_int <- as.integer(era_end_idx_int %%  12L + 1L)

  era_start_label_chr <- format(
    as.Date(sprintf(
      "%04d-%02d-01", era_spec$start_year_int, era_spec$start_month_int
    )),
    "%B %Y"
  )
  era_end_label_chr <- format(
    as.Date(sprintf("%04d-%02d-01", era_end_year_int, era_end_month_int)),
    "%B %Y"
  )
  # Anchor month: the era start unless the spec names a different one.
  era_anchor_idx_int <- if (is.null(era_spec$anchor_year_int)) {
    era_start_idx_int
  } else {
    as.integer(
      era_spec$anchor_year_int * 12L + era_spec$anchor_month_int - 1L
    )
  }

  era_anchor_label_chr <- format(
    as.Date(sprintf(
      "%04d-%02d-01",
      as.integer(era_anchor_idx_int %/% 12L),
      as.integer(era_anchor_idx_int %%  12L + 1L)
    )),
    "%B %Y"
  )

  # An anchor outside the plotted window would rebase on a month the reader
  # cannot see; that is never intended, so fail loudly rather than render it.
  if (
    era_anchor_idx_int < era_start_idx_int ||
    era_anchor_idx_int > era_end_idx_int
  ) {
    stop(
      "figure_a_percentiles.R -- ", era_spec$slug_chr, " anchor (",
      era_anchor_label_chr, ") falls outside its window (",
      era_start_label_chr, " to ", era_end_label_chr, ")."
    )
  }

  # Anchor window start (anchor month minus eleven) for the caption: the
  # rolling window is the calendar-based 12 months [anchor-11, anchor].
  era_window_start_idx_int <- era_anchor_idx_int - 11L
  era_window_start_label_chr <- format(
    as.Date(sprintf(
      "%04d-%02d-01",
      as.integer(era_window_start_idx_int %/% 12L),
      as.integer(era_window_start_idx_int %%  12L + 1L)
    )),
    "%B %Y"
  )

  # 1) Per-percentile rolling average anchor at the era anchor month.
  anchor_era_df <- percentile_panel_df |>
    dplyr::filter(month_idx_int == era_anchor_idx_int) |>
    dplyr::transmute(
      percentile_chr,
      anchor_era_roll12_num = real_hourly_wage_roll12_num
    )

  missing_anchor_era_chr <- setdiff(
    percentile_levels_chr,
    anchor_era_df$percentile_chr[!is.na(anchor_era_df$anchor_era_roll12_num)]
  )

  if (length(missing_anchor_era_chr) > 0L) {
    message(
      "figure_a_percentiles.R -- ", era_spec$slug_chr, " anchor (",
      era_anchor_label_chr, ") missing or NA for percentile(s): ",
      paste(missing_anchor_era_chr, collapse = ", "),
      ". Indexed values for those percentiles will be NA."
    )
  }

  # 2) Slice the panel to the era window and apply the anchor.
  panel_era_df <- percentile_panel_df |>
    dplyr::filter(
      month_idx_int >= era_start_idx_int,
      month_idx_int <= era_end_idx_int
    ) |>
    dplyr::left_join(anchor_era_df, by = "percentile_chr") |>
    dplyr::mutate(
      index_subset_num = dplyr::if_else(
        !is.na(anchor_era_roll12_num) & anchor_era_roll12_num > 0,
        100 * real_hourly_wage_num       / anchor_era_roll12_num,
        NA_real_
      ),
      index_subset_roll12_num = dplyr::if_else(
        !is.na(anchor_era_roll12_num) & anchor_era_roll12_num > 0,
        100 * real_hourly_wage_roll12_num / anchor_era_roll12_num,
        NA_real_
      )
    )

  # 3) x-axis breaks scaled to the era span.
  era_span_months_int <- era_end_idx_int - era_start_idx_int + 1L
  if (era_span_months_int <= 24L) {
    era_date_breaks_chr <- "3 months"
    era_date_labels_chr <- "%b %Y"
  } else if (era_span_months_int <= 84L) {
    era_date_breaks_chr <- "1 year"
    era_date_labels_chr <- "%Y"
  } else {
    era_date_breaks_chr <- "2 years"
    era_date_labels_chr <- "%Y"
  }

  # 4) Plot.
  fig_a_index_era_plot <- ggplot2::ggplot(
    panel_era_df,
    ggplot2::aes(
      x     = date_dt,
      color = percentile_fct
    )
  ) +
    ggplot2::geom_hline(
      yintercept = 100,
      linetype   = "dashed",
      linewidth  = 0.3,
      color      = "#525252"
    ) +
    ggplot2::geom_point(
      ggplot2::aes(y = index_subset_num),
      alpha = 0.3,
      size  = 0.9,
      na.rm = TRUE
    ) +
    ggplot2::geom_line(
      ggplot2::aes(y = index_subset_roll12_num),
      alpha     = 1.0,
      linewidth = 0.7,
      na.rm     = TRUE
    ) +
    ggplot2::scale_color_manual(
      values = stats::setNames(
        percentile_colors_chr,
        percentile_labels_chr[names(percentile_colors_chr)]
      ),
      name = "Percentile"
    ) +
    ggplot2::scale_y_continuous(
      labels = scales::label_number(accuracy = 1L)
    ) +
    ggplot2::scale_x_date(
      date_breaks = era_date_breaks_chr,
      date_labels = era_date_labels_chr
    ) +
    ggplot2::labs(
      title    = paste0(
        era_spec$title_chr, ", ", era_start_label_chr, " to ",
        era_end_label_chr
      ),
      # Wrapped: at full length the subtitle runs past the right edge of
      # the 10 in canvas for the longer anchor-month names.
      subtitle = stringr::str_wrap(paste0(
        "Monthly weighted percentiles (points) and 12-month rolling average ",
        "(line), indexed so the rolling average equals 100 in ",
        era_anchor_label_chr
      ), width = 100),
      x        = NULL,
      y        = paste0("Index (", era_anchor_label_chr, " 12-month rolling average = 100)"),
      caption  = stringr::str_wrap(paste0(
        "Source: IPUMS-CPS ORG; BEA PCEPI via FRED. Sample: civilian ",
        "wage-and-salary workers with EARNWT > 0 and a non-missing ",
        "hourly wage. Each percentile series is rescaled by its 12-month ",
        "rolling average evaluated at ", era_anchor_label_chr,
        ". The window at ", era_anchor_label_chr, " uses prior-data months (",
        era_window_start_label_chr, " to ", era_anchor_label_chr, ").",
        era_spec$caption_extra_chr
      ), width = 120)
    ) +
    ggplot2::theme_minimal(base_size = 11, base_family = eig_font_body_chr) +
    ggplot2::theme(
      panel.grid.major.x = ggplot2::element_blank(),
      panel.grid.minor   = ggplot2::element_blank(),
      panel.border       = ggplot2::element_blank(),
      axis.line          = ggplot2::element_line(linewidth = 0.3),
      legend.position    = "right",
      plot.title         = ggplot2::element_text(face = "bold",
                                                 family = eig_font_title_chr),
      plot.caption       = ggplot2::element_text(hjust = 0)
    )

  fig_index_era_png_chr <- fs::path(
    fig_out_dir_chr,
    paste0("figure_a_percentiles_indexed_", era_spec$slug_chr, ".png")
  )

  ggplot2::ggsave(
    filename = fig_index_era_png_chr,
    plot     = fig_a_index_era_plot,
    width    = 10.0,
    height   = 5.6,
    units    = "in",
    dpi      = 300L,
    device   = eig_png_device
  )

  # 5) Wide CSV sidecars (monthly raw and 12-month rolling).
  index_era_monthly_wide_df <- panel_era_df |>
    dplyr::select(
      year_int, month_int, date_dt, percentile_chr, index_subset_num
    ) |>
    tidyr::pivot_wider(
      names_from  = percentile_chr,
      values_from = index_subset_num
    ) |>
    dplyr::select(
      year_int, month_int, date_dt,
      dplyr::all_of(percentile_levels_chr)
    ) |>
    dplyr::arrange(year_int, month_int)

  index_era_rolling_wide_df <- panel_era_df |>
    dplyr::select(
      year_int, month_int, date_dt, percentile_chr, index_subset_roll12_num
    ) |>
    tidyr::pivot_wider(
      names_from  = percentile_chr,
      values_from = index_subset_roll12_num
    ) |>
    dplyr::select(
      year_int, month_int, date_dt,
      dplyr::all_of(percentile_levels_chr)
    ) |>
    dplyr::arrange(year_int, month_int)

  fig_index_era_monthly_csv_chr <- fs::path(
    tbl_out_dir_chr,
    paste0("figure_a_percentiles_indexed_", era_spec$slug_chr, "_monthly.csv")
  )
  fig_index_era_rolling_csv_chr <- fs::path(
    tbl_out_dir_chr,
    paste0("figure_a_percentiles_indexed_", era_spec$slug_chr, "_roll12.csv")
  )

  readr::write_csv(index_era_monthly_wide_df, fig_index_era_monthly_csv_chr)
  readr::write_csv(index_era_rolling_wide_df, fig_index_era_rolling_csv_chr)

  # 6) Verify this era's three outputs exist before moving on.
  for (path_chr in c(
    fig_index_era_png_chr,
    fig_index_era_monthly_csv_chr,
    fig_index_era_rolling_csv_chr
  )) {
    if (!fs::file_exists(path_chr)) {
      stop("figure_a_percentiles.R -- era output not written: ", path_chr)
    }
  }

  message(
    "figure_a_percentiles.R -- wrote ", era_spec$slug_chr, " (",
    era_start_label_chr, " to ", era_end_label_chr,
    ", indexed to ", era_anchor_label_chr, ") PNG + 2 CSVs"
  )
}

###################################
###   9) Write wide CSV sidecars#
###################################
# Datawrapper-style wide tables: one column per plotted series.
# Ten CSVs total (two per figure: monthly raw and 12-month rolling).
# Schema: year_int, month_int, date_dt, p10, p25, p50, p75, p90.
# The 2015-2020 pair additionally carries p10_2020-p90_2020 (the dashed
# 2020 series, blank outside the December 2019 to December 2020 range)
# and covid_2020_flag_int; the base p10-p90 columns there are blank
# across 2020 so the solid and dashed series never overlap except at the
# December 2019 bridge month.
#
# The full-panel indexed pair carries the same kind of split over a wider
# window: p10-p90 hold the solid line and are blank (NA) from March 2020
# through December 2021, p10_covid-p90_covid hold February 2020 through
# January 2022, and covid_flag_int marks the blanked span. Every month is
# plotted by exactly one column except the February 2020 and January 2022
# bridge months, so plotting both sets renders the COVID span as a
# separate (dashed) line joining the solid line at each end without a gap.
# Long-format tables are not written; rebuild from wide via
# tidyr::pivot_longer if needed.

level_monthly_wide_df <- percentile_panel_df |>
  dplyr::select(
    year_int, month_int, date_dt, percentile_chr, real_hourly_wage_num
  ) |>
  tidyr::pivot_wider(
    names_from  = percentile_chr,
    values_from = real_hourly_wage_num
  ) |>
  dplyr::select(
    year_int, month_int, date_dt,
    dplyr::all_of(percentile_levels_chr)
  ) |>
  dplyr::arrange(year_int, month_int)

level_rolling_wide_df <- percentile_panel_df |>
  dplyr::select(
    year_int, month_int, date_dt, percentile_chr,
    real_hourly_wage_roll12_num
  ) |>
  tidyr::pivot_wider(
    names_from  = percentile_chr,
    values_from = real_hourly_wage_roll12_num
  ) |>
  dplyr::select(
    year_int, month_int, date_dt,
    dplyr::all_of(percentile_levels_chr)
  ) |>
  dplyr::arrange(year_int, month_int)

index_monthly_wide_df <- percentile_panel_df |>
  dplyr::select(
    year_int, month_int, date_dt, month_idx_int, percentile_chr, index_num
  ) |>
  tidyr::pivot_wider(
    names_from  = percentile_chr,
    values_from = index_num
  ) |>
  dplyr::arrange(year_int, month_int) |>
  dplyr::mutate(
    covid_flag_int   = dplyr::if_else(
      month_idx_int >= covid_start_idx_int &
      month_idx_int <= covid_end_idx_int, 1L, 0L
    ),
    covid_window_lgl = month_idx_int >= covid_lead_idx_int &
                       month_idx_int <= covid_lag_idx_int,
    p10_covid = dplyr::if_else(covid_window_lgl, p10, NA_real_),
    p25_covid = dplyr::if_else(covid_window_lgl, p25, NA_real_),
    p50_covid = dplyr::if_else(covid_window_lgl, p50, NA_real_),
    p75_covid = dplyr::if_else(covid_window_lgl, p75, NA_real_),
    p90_covid = dplyr::if_else(covid_window_lgl, p90, NA_real_)
  ) |>
  dplyr::mutate(
    dplyr::across(
      dplyr::all_of(percentile_levels_chr),
      \(x) dplyr::if_else(covid_flag_int == 1L, NA_real_, x)
    )
  ) |>
  dplyr::select(
    year_int, month_int, date_dt,
    dplyr::all_of(percentile_levels_chr),
    p10_covid, p25_covid, p50_covid, p75_covid, p90_covid,
    covid_flag_int
  )

index_rolling_wide_df <- percentile_panel_df |>
  dplyr::select(
    year_int, month_int, date_dt, month_idx_int, percentile_chr,
    index_roll12_num
  ) |>
  tidyr::pivot_wider(
    names_from  = percentile_chr,
    values_from = index_roll12_num
  ) |>
  dplyr::arrange(year_int, month_int) |>
  dplyr::mutate(
    covid_flag_int   = dplyr::if_else(
      month_idx_int >= covid_start_idx_int &
      month_idx_int <= covid_end_idx_int, 1L, 0L
    ),
    covid_window_lgl = month_idx_int >= covid_lead_idx_int &
                       month_idx_int <= covid_lag_idx_int,
    p10_covid = dplyr::if_else(covid_window_lgl, p10, NA_real_),
    p25_covid = dplyr::if_else(covid_window_lgl, p25, NA_real_),
    p50_covid = dplyr::if_else(covid_window_lgl, p50, NA_real_),
    p75_covid = dplyr::if_else(covid_window_lgl, p75, NA_real_),
    p90_covid = dplyr::if_else(covid_window_lgl, p90, NA_real_)
  ) |>
  dplyr::mutate(
    dplyr::across(
      dplyr::all_of(percentile_levels_chr),
      \(x) dplyr::if_else(covid_flag_int == 1L, NA_real_, x)
    )
  ) |>
  dplyr::select(
    year_int, month_int, date_dt,
    dplyr::all_of(percentile_levels_chr),
    p10_covid, p25_covid, p50_covid, p75_covid, p90_covid,
    covid_flag_int
  )

readr::write_csv(level_monthly_wide_df, fig_level_monthly_csv_chr)
readr::write_csv(level_rolling_wide_df, fig_level_rolling_csv_chr)
readr::write_csv(index_monthly_wide_df, fig_index_monthly_csv_chr)
readr::write_csv(index_rolling_wide_df, fig_index_rolling_csv_chr)

# Subset CSVs: same schema, sourced from the per-subset panel data
# frames built in steps 8b/8c/8d.

index_2001_monthly_wide_df <- panel_2001_df |>
  dplyr::select(
    year_int, month_int, date_dt, percentile_chr, index_subset_num
  ) |>
  tidyr::pivot_wider(
    names_from  = percentile_chr,
    values_from = index_subset_num
  ) |>
  dplyr::select(
    year_int, month_int, date_dt,
    dplyr::all_of(percentile_levels_chr)
  ) |>
  dplyr::arrange(year_int, month_int)

index_2001_rolling_wide_df <- panel_2001_df |>
  dplyr::select(
    year_int, month_int, date_dt, percentile_chr, index_subset_roll12_num
  ) |>
  tidyr::pivot_wider(
    names_from  = percentile_chr,
    values_from = index_subset_roll12_num
  ) |>
  dplyr::select(
    year_int, month_int, date_dt,
    dplyr::all_of(percentile_levels_chr)
  ) |>
  dplyr::arrange(year_int, month_int)

# 2015-2020 CSVs carry the dashed-2020 split so Datawrapper can render
# the 2020 months as a separate (dashed) series set: the p10-p90 columns
# hold the solid 2015-2019 line and are blank (NA) across 2020, while the
# p10_2020-p90_2020 columns hold 2020 plus the December 2019 bridge month
# (so the dashed line joins the solid line without a one-month gap). Each
# percentile is therefore plotted by exactly one column except at the
# December 2019 bridge, which appears in both.

index_2015_monthly_wide_df <- panel_2015_df |>
  dplyr::select(
    year_int, month_int, date_dt, month_idx_int, covid_2020_flag_int,
    percentile_chr, index_subset_num
  ) |>
  tidyr::pivot_wider(
    names_from  = percentile_chr,
    values_from = index_subset_num
  ) |>
  dplyr::arrange(year_int, month_int) |>
  dplyr::mutate(
    p10_2020 = dplyr::if_else(month_idx_int >= boundary_2015_idx_int, p10, NA_real_),
    p25_2020 = dplyr::if_else(month_idx_int >= boundary_2015_idx_int, p25, NA_real_),
    p50_2020 = dplyr::if_else(month_idx_int >= boundary_2015_idx_int, p50, NA_real_),
    p75_2020 = dplyr::if_else(month_idx_int >= boundary_2015_idx_int, p75, NA_real_),
    p90_2020 = dplyr::if_else(month_idx_int >= boundary_2015_idx_int, p90, NA_real_)
  ) |>
  dplyr::mutate(
    p10 = dplyr::if_else(month_idx_int <= boundary_2015_idx_int, p10, NA_real_),
    p25 = dplyr::if_else(month_idx_int <= boundary_2015_idx_int, p25, NA_real_),
    p50 = dplyr::if_else(month_idx_int <= boundary_2015_idx_int, p50, NA_real_),
    p75 = dplyr::if_else(month_idx_int <= boundary_2015_idx_int, p75, NA_real_),
    p90 = dplyr::if_else(month_idx_int <= boundary_2015_idx_int, p90, NA_real_)
  ) |>
  dplyr::select(
    year_int, month_int, date_dt,
    dplyr::all_of(percentile_levels_chr),
    p10_2020, p25_2020, p50_2020, p75_2020, p90_2020,
    covid_2020_flag_int
  )

index_2015_rolling_wide_df <- panel_2015_df |>
  dplyr::select(
    year_int, month_int, date_dt, month_idx_int, covid_2020_flag_int,
    percentile_chr, index_subset_roll12_num
  ) |>
  tidyr::pivot_wider(
    names_from  = percentile_chr,
    values_from = index_subset_roll12_num
  ) |>
  dplyr::arrange(year_int, month_int) |>
  dplyr::mutate(
    p10_2020 = dplyr::if_else(month_idx_int >= boundary_2015_idx_int, p10, NA_real_),
    p25_2020 = dplyr::if_else(month_idx_int >= boundary_2015_idx_int, p25, NA_real_),
    p50_2020 = dplyr::if_else(month_idx_int >= boundary_2015_idx_int, p50, NA_real_),
    p75_2020 = dplyr::if_else(month_idx_int >= boundary_2015_idx_int, p75, NA_real_),
    p90_2020 = dplyr::if_else(month_idx_int >= boundary_2015_idx_int, p90, NA_real_)
  ) |>
  dplyr::mutate(
    p10 = dplyr::if_else(month_idx_int <= boundary_2015_idx_int, p10, NA_real_),
    p25 = dplyr::if_else(month_idx_int <= boundary_2015_idx_int, p25, NA_real_),
    p50 = dplyr::if_else(month_idx_int <= boundary_2015_idx_int, p50, NA_real_),
    p75 = dplyr::if_else(month_idx_int <= boundary_2015_idx_int, p75, NA_real_),
    p90 = dplyr::if_else(month_idx_int <= boundary_2015_idx_int, p90, NA_real_)
  ) |>
  dplyr::select(
    year_int, month_int, date_dt,
    dplyr::all_of(percentile_levels_chr),
    p10_2020, p25_2020, p50_2020, p75_2020, p90_2020,
    covid_2020_flag_int
  )

index_2021_monthly_wide_df <- panel_2021_df |>
  dplyr::select(
    year_int, month_int, date_dt, percentile_chr, index_subset_num
  ) |>
  tidyr::pivot_wider(
    names_from  = percentile_chr,
    values_from = index_subset_num
  ) |>
  dplyr::select(
    year_int, month_int, date_dt,
    dplyr::all_of(percentile_levels_chr)
  ) |>
  dplyr::arrange(year_int, month_int)

index_2021_rolling_wide_df <- panel_2021_df |>
  dplyr::select(
    year_int, month_int, date_dt, percentile_chr, index_subset_roll12_num
  ) |>
  tidyr::pivot_wider(
    names_from  = percentile_chr,
    values_from = index_subset_roll12_num
  ) |>
  dplyr::select(
    year_int, month_int, date_dt,
    dplyr::all_of(percentile_levels_chr)
  ) |>
  dplyr::arrange(year_int, month_int)

readr::write_csv(index_2001_monthly_wide_df, fig_index_2001_monthly_csv_chr)
readr::write_csv(index_2001_rolling_wide_df, fig_index_2001_rolling_csv_chr)
readr::write_csv(index_2015_monthly_wide_df, fig_index_2015_monthly_csv_chr)
readr::write_csv(index_2015_rolling_wide_df, fig_index_2015_rolling_csv_chr)
readr::write_csv(index_2021_monthly_wide_df, fig_index_2021_monthly_csv_chr)
readr::write_csv(index_2021_rolling_wide_df, fig_index_2021_rolling_csv_chr)

message(
  "figure_a_percentiles.R -- wrote level PNG (", fig_level_png_chr,
  ") and wide CSVs (", fig_level_monthly_csv_chr, ", ",
  fig_level_rolling_csv_chr, ")"
)
message(
  "figure_a_percentiles.R -- wrote indexed PNG (", fig_index_png_chr,
  ") and wide CSVs (", fig_index_monthly_csv_chr, ", ",
  fig_index_rolling_csv_chr, ")"
)
message(
  "figure_a_percentiles.R -- wrote 2001-2014 indexed PNG (",
  fig_index_2001_png_chr, ") and wide CSVs (",
  fig_index_2001_monthly_csv_chr, ", ",
  fig_index_2001_rolling_csv_chr, ")"
)
message(
  "figure_a_percentiles.R -- wrote 2015-2020 indexed PNG (",
  fig_index_2015_png_chr, ") and wide CSVs (",
  fig_index_2015_monthly_csv_chr, ", ",
  fig_index_2015_rolling_csv_chr, ")"
)
message(
  "figure_a_percentiles.R -- wrote 2021-present indexed PNG (",
  fig_index_2021_png_chr, ") and wide CSVs (",
  fig_index_2021_monthly_csv_chr, ", ",
  fig_index_2021_rolling_csv_chr, ")"
)

###################################
###   10) Verify outputs exist  ###
###################################

for (path_chr in c(
  fig_level_png_chr,
  fig_index_png_chr,
  fig_index_2001_png_chr,
  fig_index_2015_png_chr,
  fig_index_2021_png_chr,
  fig_level_monthly_csv_chr, fig_level_rolling_csv_chr,
  fig_index_monthly_csv_chr, fig_index_rolling_csv_chr,
  fig_index_2001_monthly_csv_chr, fig_index_2001_rolling_csv_chr,
  fig_index_2015_monthly_csv_chr, fig_index_2015_rolling_csv_chr,
  fig_index_2021_monthly_csv_chr, fig_index_2021_rolling_csv_chr
)) {
  if (!fs::file_exists(path_chr)) {
    stop("figure_a_percentiles.R -- output not written: ", path_chr)
  }
}

message("figure_a_percentiles.R -- done.")
