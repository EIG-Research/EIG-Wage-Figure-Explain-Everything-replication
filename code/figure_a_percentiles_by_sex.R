# figure_a_percentiles_by_sex -- weighted real hourly wage percentiles (10/25/50/75/90) by month, indexed, split by sex
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

rm(list = ls())
options(scipen = 999)
set.seed(42)

# Sourced by run_all.R inside new.env(parent = globalenv()).
#
# Companion to code/figure_a_percentiles.R: identical weighted-percentile
# construction and the same December 1982 indexed anchor (the first month
# after the NBER-dated end of the 1981-82 recession, trough November
# 1982), but the percentile cells are computed
# separately by SEX (IPUMS-CPS convention: 1 = male, 2 = female) so the
# indexed real-wage growth comparison can be read by sex. Scope is the
# full-panel indexed figure only -- the level figure and the three
# date-range subset variants (2001-2014, 2015-2020, 2021-present) in
# figure_a_percentiles.R are not duplicated here.
#
# Outputs:
#   output/figures/figure_a_percentiles_indexed_by_sex.png
#     -- "Figure 1b-iv" (extends the 1b-i/ii/iii date-range subset
#        numbering in figure_a_percentiles.R with a by-sex breakdown of
#        the full-panel index). One figure, faceted by sex (Male /
#        Female), colored by percentile, points (monthly) + line
#        (12-month rolling average).
#   output/tables/figure_a_percentiles_indexed_by_sex_monthly.xlsx
#     -- two-sheet workbook (Male, Female); each sheet is the monthly
#        indexed series in the same wide schema as
#        figure_a_percentiles_indexed_monthly.csv:
#        year_int, month_int, date_dt, p10, p25, p50, p75, p90,
#        p10_covid-p90_covid, covid_flag_int (see step 8).
#   output/tables/figure_a_percentiles_indexed_by_sex_roll12.xlsx
#     -- same two-sheet layout, 12-month rolling average values.
#
# March 2020 through December 2021 is drawn as a separate dashed series
# and carried in its own sidecar columns, matching the pooled figure in
# figure_a_percentiles.R.
#
# Each sex's index is anchored to its OWN 12-month rolling average at
# December 1982 (not to the pooled anchor in figure_a_percentiles.R),
# so "100" means "that sex's own December 1982 level" in each panel.
#
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

fig_index_sex_png_chr <- fs::path(fig_out_dir_chr, "figure_a_percentiles_indexed_by_sex.png")

xlsx_monthly_chr <- fs::path(tbl_out_dir_chr,
  "figure_a_percentiles_indexed_by_sex_monthly.xlsx")
xlsx_rolling_chr <- fs::path(tbl_out_dir_chr,
  "figure_a_percentiles_indexed_by_sex_roll12.xlsx")

# 2022 primary palette tokens (one per percentile, low-to-high) -- same
# tokens as figure_a_percentiles.R so the two figures read consistently.
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

# IPUMS-CPS SEX coding: 1 = male, 2 = female. No other codes are valid
# for adult ORG respondents. male_sex_int/female_sex_int are derived
# from sex_labels_chr (not re-hardcoded) so every downstream filter by
# sex stays tied to this single mapping.
sex_labels_chr   <- c("1" = "Male", "2" = "Female")
sex_levels_int   <- as.integer(names(sex_labels_chr))
male_sex_int     <- as.integer(names(sex_labels_chr)[sex_labels_chr == "Male"])
female_sex_int   <- as.integer(names(sex_labels_chr)[sex_labels_chr == "Female"])

# Smoothing window. Per decision 08, the display series is a plain 12-month
# backward-facing rolling average: equal weight on every observed month in the
# calendar window [t-11, t]. See
# docs/decisions/decision_08_smoothing_12mo_flat.md. Supersedes the 12-month
# geometric EWMA of decision 07.
rolling_window_int <- 12L

# Indexed-figure anchor: December 1982, the first month after the
# NBER-dated end of the 1981-82 recession (trough November 1982),
# applied uniformly to every percentile within each sex (mirrors
# figure_a_percentiles.R's main indexed figure).
anchor_main_year_int  <- 1982L
anchor_main_month_int <- 12L

# COVID window, matching the pooled figure in figure_a_percentiles.R.
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

fs::dir_create(fig_out_dir_chr, recurse = TRUE)
fs::dir_create(tbl_out_dir_chr, recurse = TRUE)

###################################
###   1) Load real-wage panel   ###
###################################

if (!fs::dir_exists(panel_in_dir_chr)) {
  stop(
    "figure_a_percentiles_by_sex.R -- real-wage panel not found at ",
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
    "figure_a_percentiles_by_sex.R -- no part-0.parquet files found under ",
    panel_in_dir_chr, ". Run 02a_build_real_wages.R first."
  )
}

real_wage_ds <- arrow::open_dataset(parquet_paths_chr, format = "parquet")

real_wage_df <- real_wage_ds |>
  dplyr::select(YEAR, MONTH, SEX, EARNWT, real_hourly_wage_num) |>
  dplyr::collect()

required_cols_chr <- c("YEAR", "MONTH", "SEX", "EARNWT", "real_hourly_wage_num")
missing_cols_chr  <- setdiff(required_cols_chr, names(real_wage_df))

if (length(missing_cols_chr) > 0L) {
  stop(
    "figure_a_percentiles_by_sex.R -- real-wage panel missing column(s): ",
    paste(missing_cols_chr, collapse = ", ")
  )
}

off_code_sex_bool <- !real_wage_df$SEX %in% sex_levels_int | is.na(real_wage_df$SEX)
off_code_sex_int  <- sort(unique(real_wage_df$SEX[off_code_sex_bool]), na.last = TRUE)

if (any(off_code_sex_bool)) {
  message(
    "figure_a_percentiles_by_sex.R -- dropping ",
    format(sum(off_code_sex_bool), big.mark = ","),
    " record(s) with SEX code(s) outside {1, 2}: ",
    paste(off_code_sex_int, collapse = ", ")
  )
}

message(
  "figure_a_percentiles_by_sex.R -- loaded ",
  format(nrow(real_wage_df), big.mark = ","),
  " person-month records spanning ",
  min(real_wage_df$YEAR, na.rm = TRUE), "-",
  max(real_wage_df$YEAR, na.rm = TRUE)
)

###################################
###   2) Monthly percentiles    ###
###################################
# Within each (YEAR, MONTH, SEX): EARNWT-weighted percentiles via the
# shared weighted_quantile() helper (Stata `_pctile` / EPI
# no-interpolation convention). See code/_utils/weighted_stats.R.

valid_bool <- !is.na(real_wage_df$real_hourly_wage_num) &
  !is.na(real_wage_df$EARNWT) &
  real_wage_df$EARNWT > 0 &
  real_wage_df$SEX %in% sex_levels_int

percentile_wide_df <- real_wage_df[valid_bool, , drop = FALSE] |>
  dplyr::group_by(YEAR, MONTH, SEX) |>
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
    month_int = MONTH,
    sex_int   = SEX
  ) |>
  dplyr::mutate(
    year_int  = as.integer(year_int),
    month_int = as.integer(month_int),
    sex_int   = as.integer(sex_int)
  )

message(
  "figure_a_percentiles_by_sex.R -- computed percentiles for ",
  format(nrow(percentile_wide_df), big.mark = ","),
  " (year, month, sex) cells spanning ",
  min(percentile_wide_df$year_int), "-",
  max(percentile_wide_df$year_int)
)

###################################
###   3) Calendar-complete grid ###
###################################
# Long-format reshape and left-join onto a full (month, percentile, sex)
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
  percentile_chr = percentile_levels_chr,
  sex_int        = sex_levels_int
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
    month_idx_int, year_int, month_int, sex_int, percentile_chr,
    n_cell_int, real_hourly_wage_num
  )

percentile_panel_df <- calendar_df |>
  dplyr::left_join(
    percentile_long_df |>
      dplyr::select(month_idx_int, sex_int, percentile_chr, n_cell_int, real_hourly_wage_num),
    by = c("month_idx_int", "sex_int", "percentile_chr")
  )

###################################
###   4) 12-month rolling average ###
###################################
# Backward-looking [t-11, t] calendar window per (percentile, sex),
# equally weighted and adaptive to missing months: an unobserved month
# drops out of both the numerator and the denominator. Partial windows
# at series start are allowed, and all-NA windows produce NA_real_.

percentile_panel_df <- percentile_panel_df |>
  dplyr::arrange(sex_int, percentile_chr, month_idx_int) |>
  dplyr::group_by(sex_int, percentile_chr) |>
  dplyr::mutate(
    real_hourly_wage_roll12_num = zoo::rollapplyr(
      data    = real_hourly_wage_num,
      width   = rolling_window_int,
      FUN     = function(x) {
        # Flat mean over observed months (decision 08). The all-NA guard is
        # required: mean(x, na.rm = TRUE) on an all-NA window returns NaN.
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
# #5 uniform $200 1989-PCE). Sex-specific monthly percentiles should
# fall comfortably inside this range; anything beyond $250/hr indicates
# a deflator, trim, or SEX-join misconfiguration.

wage_min_num <- min(percentile_panel_df$real_hourly_wage_num, na.rm = TRUE)
wage_max_num <- max(percentile_panel_df$real_hourly_wage_num, na.rm = TRUE)

if (is.na(wage_min_num) || wage_min_num <= 0) {
  stop(
    "figure_a_percentiles_by_sex.R -- computed percentile minimum is not ",
    "positive (", wage_min_num, "); abort before rendering."
  )
}

if (is.na(wage_max_num) || wage_max_num > 250) {
  stop(
    "figure_a_percentiles_by_sex.R -- computed percentile maximum exceeds ",
    "$250/hr (", wage_max_num, "); likely an outlier-trim or deflator ",
    "misconfiguration. Abort before rendering."
  )
}

message(
  "figure_a_percentiles_by_sex.R -- monthly percentile range: $",
  format(round(wage_min_num, 2), big.mark = ","), "/hr to $",
  format(round(wage_max_num, 2), big.mark = ","), "/hr"
)

###################################
###   6) Build indexed series   ###
###################################
# Anchor on the 12-month rolling average at a fixed calendar month --
# December 1982, the first month after the NBER-dated end of the 1981-82
# recession (trough November 1982) -- applied uniformly to every
# percentile WITHIN each sex. Each sex therefore has its own anchor value
# per percentile, so "100" in the Male panel means "Male December 1982
# rolling average" and likewise for Female; the two panels are not on a
# shared dollar scale.

anchor_main_idx_int <- as.integer(
  anchor_main_year_int * 12L + anchor_main_month_int - 1L
)

anchor_main_df <- percentile_panel_df |>
  dplyr::filter(month_idx_int == anchor_main_idx_int) |>
  dplyr::transmute(
    sex_int, percentile_chr,
    anchor_main_roll12_num = real_hourly_wage_roll12_num
  )

# Full expected (percentile, sex) combination set, so a completely
# absent anchor month (zero rows in anchor_main_df, e.g. a truncated
# panel that does not reach back to December 1982) is caught the same
# way as a present-but-NA anchor -- mirrors the setdiff() guard in
# figure_a_percentiles.R, generalized to two grouping keys.
expected_anchor_pairs_df <- tidyr::expand_grid(
  sex_int        = sex_levels_int,
  percentile_chr = percentile_levels_chr
)

present_anchor_pairs_df <- anchor_main_df |>
  dplyr::filter(!is.na(anchor_main_roll12_num)) |>
  dplyr::select(sex_int, percentile_chr)

missing_anchor_main_df <- expected_anchor_pairs_df |>
  dplyr::anti_join(present_anchor_pairs_df, by = c("sex_int", "percentile_chr"))

if (nrow(missing_anchor_main_df) > 0L) {
  message(
    "figure_a_percentiles_by_sex.R -- main-figure anchor (December 1982) ",
    "missing or NA for (sex, percentile) pair(s): ",
    paste(
      paste0(sex_labels_chr[as.character(missing_anchor_main_df$sex_int)],
             "/", missing_anchor_main_df$percentile_chr),
      collapse = ", "
    ),
    ". Indexed values for those pairs will be NA."
  )
}

percentile_panel_df <- percentile_panel_df |>
  dplyr::left_join(
    anchor_main_df |>
      dplyr::select(sex_int, percentile_chr, anchor_main_roll12_num),
    by = c("sex_int", "percentile_chr")
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
    ),
    sex_fct         = factor(
      sex_int,
      levels = sex_levels_int,
      labels = unname(sex_labels_chr)
    )
  ) |>
  dplyr::arrange(sex_int, percentile_chr, month_idx_int)

anchor_main_label_chr <- format(
  as.Date(sprintf(
    "%04d-%02d-01", anchor_main_year_int, anchor_main_month_int
  )),
  "%B %Y"
)

message(
  "figure_a_percentiles_by_sex.R -- indexed anchor month (fixed, per sex): ",
  anchor_main_label_chr
)

###################################
###   7) Plot -- indexed by sex ###
###################################
# The rolling average line is split into three segments so March 2020
# through December 2021 draws dashed. February 2020 and January 2022 each
# appear in two frames so the dashed segment meets the solid line at both
# ends without a gap. Each frame retains sex_fct, so facet_wrap splits
# every segment across both panels. This matches the solid/dashed column
# split in the XLSX sheets (step 8).

panel_sex_pre_df   <- percentile_panel_df |>
  dplyr::filter(month_idx_int <= covid_lead_idx_int)
panel_sex_covid_df <- percentile_panel_df |>
  dplyr::filter(
    month_idx_int >= covid_lead_idx_int,
    month_idx_int <= covid_lag_idx_int
  )
panel_sex_post_df  <- percentile_panel_df |>
  dplyr::filter(month_idx_int >= covid_lag_idx_int)

fig_a_index_sex_plot <- ggplot2::ggplot(
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
    data = panel_sex_pre_df,
    ggplot2::aes(y = index_roll12_num),
    alpha     = 1.0,
    linewidth = 0.7,
    na.rm     = TRUE
  ) +
  ggplot2::geom_line(
    data = panel_sex_covid_df,
    ggplot2::aes(y = index_roll12_num),
    linetype  = "dashed",
    alpha     = 1.0,
    linewidth = 0.7,
    na.rm     = TRUE
  ) +
  ggplot2::geom_line(
    data = panel_sex_post_df,
    ggplot2::aes(y = index_roll12_num),
    alpha     = 1.0,
    linewidth = 0.7,
    na.rm     = TRUE
  ) +
  ggplot2::facet_wrap(~sex_fct, ncol = 2L) +
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
      "Figure 1b-iv. Real hourly wage percentiles by sex, indexed so the ",
      "12-month rolling average equals 100 in ", anchor_main_label_chr
    ),
    subtitle = paste0(
      "Monthly weighted percentiles (points) and 12-month rolling average ",
      "(line, dashed March 2020 to December 2021), per-percentile growth ",
      "since the anchor month, computed separately by sex"
    ),
    x        = NULL,
    y        = paste0("Index (", anchor_main_label_chr, " 12-month rolling average = 100, by sex)"),
    caption  = stringr::str_wrap(paste0(
      "Source: IPUMS-CPS ORG, 1982 to latest; BEA PCEPI via FRED. ",
      "Sample: civilian wage-and-salary workers with EARNWT > 0 and a ",
      "non-missing hourly wage. Percentiles are computed separately by ",
      "sex (IPUMS SEX: 1 = male, 2 = female); each sex-percentile series ",
      "is rescaled by its OWN 12-month rolling average evaluated at ",
      anchor_main_label_chr, " (the first month after the NBER-dated end ",
      "of the 1981-82 recession, trough November 1982), so the two panels ",
      "are not on a shared dollar scale. ",
      "Sample restricted to workers age 16 and older. Census-imputed ",
      "(allocated) earnings records are retained, matching EPI's public ",
      "extract. Salaried workers who do not report usable weekly hours ",
      "are excluded from the hourly series. March 2020 through December ",
      "2021 is drawn as a dashed segment: COVID-driven shifts in CPS ",
      "sample composition confound the wage percentiles across that ",
      "span. October 2025 data not ",
      "collected due to federal government shutdown."
    ), width = 120)
  ) +
  ggplot2::theme_minimal(base_size = 11, base_family = eig_font_body_chr) +
  ggplot2::theme(
    panel.grid.major.x = ggplot2::element_blank(),
    panel.grid.minor   = ggplot2::element_blank(),
    panel.border       = ggplot2::element_blank(),
    axis.line          = ggplot2::element_line(linewidth = 0.3),
    legend.position    = "right",
    strip.text         = ggplot2::element_text(face = "bold",
                                               family = eig_font_title_chr),
    plot.title         = ggplot2::element_text(face = "bold",
                                               family = eig_font_title_chr),
    plot.caption       = ggplot2::element_text(hjust = 0)
  )

ggplot2::ggsave(
  filename = fig_index_sex_png_chr,
  plot     = fig_a_index_sex_plot,
  width    = 12.0,
  height   = 5.6,
  units    = "in",
  dpi      = 300L,
  device   = eig_png_device
)

###################################
###   8) Write by-sex XLSX      ###
###################################
# Two workbooks (monthly, 12-month rolling), each with one sheet per
# sex. Sheet schema matches figure_a_percentiles.R's pooled indexed
# tables, COVID split included: year_int, month_int, date_dt, p10-p90,
# p10_covid-p90_covid, covid_flag_int.
#
# p10-p90 hold the solid line and are blank across March 2020 to December
# 2021; p10_covid-p90_covid hold February 2020 through January 2022; and
# covid_flag_int marks the blanked span. Every month is covered by exactly
# one set except the two bridge months.
#
# The COVID split is applied once per measure on a sex-stacked frame, then
# each sex is sliced out, so the window logic is not repeated four times.

index_monthly_wide_df <- percentile_panel_df |>
  dplyr::select(
    sex_int, year_int, month_int, date_dt, month_idx_int, percentile_chr,
    index_num
  ) |>
  tidyr::pivot_wider(
    names_from  = percentile_chr,
    values_from = index_num
  ) |>
  dplyr::arrange(sex_int, year_int, month_int) |>
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
    sex_int, year_int, month_int, date_dt,
    dplyr::all_of(percentile_levels_chr),
    p10_covid, p25_covid, p50_covid, p75_covid, p90_covid,
    covid_flag_int
  )

index_rolling_wide_df <- percentile_panel_df |>
  dplyr::select(
    sex_int, year_int, month_int, date_dt, month_idx_int, percentile_chr,
    index_roll12_num
  ) |>
  tidyr::pivot_wider(
    names_from  = percentile_chr,
    values_from = index_roll12_num
  ) |>
  dplyr::arrange(sex_int, year_int, month_int) |>
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
    sex_int, year_int, month_int, date_dt,
    dplyr::all_of(percentile_levels_chr),
    p10_covid, p25_covid, p50_covid, p75_covid, p90_covid,
    covid_flag_int
  )

index_monthly_male_wide_df <- index_monthly_wide_df |>
  dplyr::filter(sex_int == male_sex_int)   |> dplyr::select(-sex_int)
index_monthly_female_wide_df <- index_monthly_wide_df |>
  dplyr::filter(sex_int == female_sex_int) |> dplyr::select(-sex_int)
index_rolling_male_wide_df <- index_rolling_wide_df |>
  dplyr::filter(sex_int == male_sex_int)   |> dplyr::select(-sex_int)
index_rolling_female_wide_df <- index_rolling_wide_df |>
  dplyr::filter(sex_int == female_sex_int) |> dplyr::select(-sex_int)

monthly_sheets_ls <- list(
  Male   = index_monthly_male_wide_df,
  Female = index_monthly_female_wide_df
)

rolling_sheets_ls <- list(
  Male   = index_rolling_male_wide_df,
  Female = index_rolling_female_wide_df
)

writexl::write_xlsx(monthly_sheets_ls, path = xlsx_monthly_chr)
writexl::write_xlsx(rolling_sheets_ls, path = xlsx_rolling_chr)

message(
  "figure_a_percentiles_by_sex.R -- wrote indexed-by-sex PNG (",
  fig_index_sex_png_chr, ") and XLSX workbooks (",
  xlsx_monthly_chr, ", ", xlsx_rolling_chr, ")"
)

###################################
###   9) Verify outputs exist   ###
###################################

for (path_chr in c(
  fig_index_sex_png_chr,
  xlsx_monthly_chr,
  xlsx_rolling_chr
)) {
  if (!fs::file_exists(path_chr)) {
    stop("figure_a_percentiles_by_sex.R -- output not written: ", path_chr)
  }
}

message("figure_a_percentiles_by_sex.R -- done.")
