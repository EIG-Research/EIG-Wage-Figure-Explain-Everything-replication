# figure_b_age_bins -- weighted real hourly wage median by month and age bin
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

rm(list = ls())
options(scipen = 999)
set.seed(42)

# Sourced by run_all.R inside new.env(parent = globalenv()).
#
# Reads the year-partitioned real-wage panel written by 02a, classifies
# each person-year into one of six age bins, and computes an
# EARNWT-weighted median real hourly wage per (YEAR, MONTH, age bin)
# cell. Plots monthly cell medians as low-alpha points with a
# matching-color 12-month rolling average line per bin.
# Outputs:
#   output/figures/figure_b_age_bins.png
#   output/tables/figure_b_age_bins_monthly.csv     (raw cell medians)
#   output/tables/figure_b_age_bins_roll12.csv    (12-month rolling averages)
#
# Age bins (inclusive on both ends): <=18, 19-24, 25-34, 35-54, 55-64,
# 65+.
#
# Weighted median uses the shared weighted_quantile() helper (Stata
# `_pctile` / EPI no-interpolation convention; see
# code/_utils/weighted_stats.R). 12-month rolling average: calendar-based
# [t-11, t] window; missing months are dropped within the window via
# na.rm = TRUE, partial windows at series start are allowed.
#
# Palette: 2022 primary EIG palette tokens via load_palette.R,
# youngest-lightest to oldest-darkest.
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
fig_png_chr         <- fs::path(fig_out_dir_chr, "figure_b_age_bins.png")

# One CSV per outcome type, wide by age bin (Datawrapper convention).
fig_monthly_csv_chr <- fs::path(tbl_out_dir_chr,
  "figure_b_age_bins_monthly.csv")
fig_rolling_csv_chr <- fs::path(tbl_out_dir_chr,
  "figure_b_age_bins_roll12.csv")

# Map display labels (containing <=, -, +) to snake_case CSV column
# names for Datawrapper. Order mirrors age_bin_levels_chr.
age_bin_column_names_chr <- c(
  "<=18"  = "age_le18",
  "19-24" = "age_19_24",
  "25-34" = "age_25_34",
  "35-54" = "age_35_54",
  "55-64" = "age_55_64",
  "65+"   = "age_65_plus"
)

# Age-bin labels in display order, youngest to oldest.
age_bin_levels_chr <- c(
  "<=18",
  "19-24",
  "25-34",
  "35-54",
  "55-64",
  "65+"
)

# 2022 primary palette tokens, youngest-lightest to oldest-darkest.
age_bin_colors_chr <- c(
  "<=18"  = unname(eig_palette_2022_primary["eig_tan_300"]),
  "19-24" = unname(eig_palette_2022_primary["eig_tan_500"]),
  "25-34" = unname(eig_palette_2022_primary["eig_gold_600"]),
  "35-54" = unname(eig_palette_2022_primary["eig_green_700"]),
  "55-64" = unname(eig_palette_2022_primary["eig_cyan_700"]),
  "65+"   = unname(eig_palette_2022_primary["eig_purple_800"])
)

# Smoothing window. Per decision 08, the display series is a plain 12-month
# backward-facing rolling average: equal weight on every observed month in the
# calendar window [t-11, t]. See
# docs/decisions/decision_08_smoothing_12mo_flat.md. Supersedes the 12-month
# geometric EWMA of decision 07.
rolling_window_int <- 12L

fs::dir_create(fig_out_dir_chr, recurse = TRUE)
fs::dir_create(tbl_out_dir_chr, recurse = TRUE)

###################################
###   1) Load real-wage panel   ###
###################################

if (!fs::dir_exists(panel_in_dir_chr)) {
  stop(
    "figure_b_age_bins.R -- real-wage panel not found at ",
    panel_in_dir_chr, ". Run 02a_build_real_wages.R first."
  )
}

# Explicit parquet-only file list — the partition dirs also contain
# part-0.rds sidecars (EIG dual-format convention) which arrow cannot
# parse.
parquet_paths_chr <- fs::dir_ls(
  panel_in_dir_chr,
  regexp = "part-0\\.parquet$",
  recurse = TRUE,
  type   = "file"
)

if (length(parquet_paths_chr) == 0L) {
  stop(
    "figure_b_age_bins.R -- no part-0.parquet files found under ",
    panel_in_dir_chr, ". Run 02a_build_real_wages.R first."
  )
}

real_wage_ds <- arrow::open_dataset(parquet_paths_chr, format = "parquet")

real_wage_df <- real_wage_ds |>
  dplyr::select(YEAR, MONTH, AGE, EARNWT, real_hourly_wage_num) |>
  dplyr::collect()

required_cols_chr <- c("YEAR", "MONTH", "AGE", "EARNWT", "real_hourly_wage_num")
missing_cols_chr  <- setdiff(required_cols_chr, names(real_wage_df))

if (length(missing_cols_chr) > 0L) {
  stop(
    "figure_b_age_bins.R -- real-wage panel missing column(s): ",
    paste(missing_cols_chr, collapse = ", ")
  )
}

message(
  "figure_b_age_bins.R -- loaded ",
  format(nrow(real_wage_df), big.mark = ","),
  " person-month records spanning ",
  min(real_wage_df$YEAR, na.rm = TRUE), "-",
  max(real_wage_df$YEAR, na.rm = TRUE)
)

###################################
###   2) Classify age bins      ###
###################################
# Bin edges are inclusive on both sides within each stated range.

real_wage_df <- real_wage_df |>
  dplyr::mutate(
    age_bin_chr = dplyr::case_when(
      AGE <= 18L                    ~ "<=18",
      AGE >= 19L & AGE <= 24L       ~ "19-24",
      AGE >= 25L & AGE <= 34L       ~ "25-34",
      AGE >= 35L & AGE <= 54L       ~ "35-54",
      AGE >= 55L & AGE <= 64L       ~ "55-64",
      AGE >= 65L                    ~ "65+",
      TRUE                          ~ NA_character_
    )
  )

n_missing_age_bin_int <- sum(is.na(real_wage_df$age_bin_chr))

if (n_missing_age_bin_int > 0L) {
  message(
    "figure_b_age_bins.R -- ", format(n_missing_age_bin_int, big.mark = ","),
    " person-month records have no age-bin classification (missing AGE); ",
    "these rows are excluded by the validity mask."
  )
}

###################################
###   3) Apply validity mask    ###
###################################
# Drop rows with missing age bin, missing real hourly wage, missing
# weight, or non-positive weight before aggregation.

valid_bool <- !is.na(real_wage_df$age_bin_chr) &
  !is.na(real_wage_df$real_hourly_wage_num) &
  !is.na(real_wage_df$EARNWT) &
  real_wage_df$EARNWT > 0

n_valid_int <- sum(valid_bool)

if (n_valid_int == 0L) {
  stop(
    "figure_b_age_bins.R -- no valid person-month observations after ",
    "applying the validity mask. Check 02a output and AGE coverage."
  )
}

message(
  "figure_b_age_bins.R -- validity mask retains ",
  format(n_valid_int, big.mark = ","), " of ",
  format(nrow(real_wage_df), big.mark = ","),
  " person-month records"
)

###################################
###   4) Monthly weighted medians#
###################################
# Group by (YEAR, MONTH, age_bin_chr) and compute the weighted median
# real hourly wage via the shared weighted_quantile() helper. Each cell
# is a single survey month, so weighted_population()'s month divisor is 1
# and earnwt_cell_num is that month's population for the age bin.

age_bin_monthly_df <- real_wage_df[valid_bool, , drop = FALSE] |>
  dplyr::group_by(YEAR, MONTH, age_bin_chr) |>
  dplyr::summarise(
    n_cell_int                  = dplyr::n(),
    earnwt_cell_num             = weighted_population(EARNWT, YEAR, MONTH),
    real_hourly_wage_median_num = weighted_quantile(
      real_hourly_wage_num, EARNWT, 0.50
    ),
    .groups = "drop"
  ) |>
  dplyr::rename(
    year_int  = YEAR,
    month_int = MONTH
  ) |>
  dplyr::mutate(
    year_int    = as.integer(year_int),
    month_int   = as.integer(month_int)
  )

if (nrow(age_bin_monthly_df) == 0L) {
  stop(
    "figure_b_age_bins.R -- grouped panel has zero rows after summarise; ",
    "the validity mask removed every cell. Investigate 02a output."
  )
}

message(
  "figure_b_age_bins.R -- computed weighted medians for ",
  format(nrow(age_bin_monthly_df), big.mark = ","),
  " (year, month, age-bin) cells"
)

###################################
###   5) Calendar-complete grid ###
###################################
# Construct a full (year, month) x age_bin grid so months that are
# absent from the 02a panel (e.g., October 2025, not collected due to
# the federal government shutdown) are explicit NA rows. Missing-month
# rows contribute NA to the rolling average window and are dropped via
# na.rm = TRUE. The grid spans the panel's observed year-month range.

# month_idx_int is a 0-indexed monthly counter across all years --
# year * 12 + (month - 1). It orders months linearly for rolling and
# handles calendar arithmetic without date parsing. The transformation
# is reversible:
#   year_int  = month_idx_int %/% 12
#   month_int = month_idx_int %%  12 + 1
age_bin_monthly_df <- age_bin_monthly_df |>
  dplyr::mutate(
    month_idx_int = as.integer(year_int * 12L + month_int - 1L)
  )

min_month_idx_int <- min(age_bin_monthly_df$month_idx_int)
max_month_idx_int <- max(age_bin_monthly_df$month_idx_int)

calendar_df <- tidyr::expand_grid(
  month_idx_int = seq(min_month_idx_int, max_month_idx_int),
  age_bin_chr   = age_bin_levels_chr
) |>
  dplyr::mutate(
    year_int  = as.integer(month_idx_int %/% 12L),
    month_int = as.integer(month_idx_int %%  12L + 1L)
  )

age_bin_panel_df <- calendar_df |>
  dplyr::left_join(
    age_bin_monthly_df |>
      dplyr::select(
        month_idx_int, age_bin_chr, n_cell_int, earnwt_cell_num,
        real_hourly_wage_median_num
      ),
    by = c("month_idx_int", "age_bin_chr")
  )

###################################
###   6) 12-month rolling average ###
###################################
# Calendar-based, backward-looking [t-11, t] window, equally weighted.
# zoo::rollapplyr with align = "right" and partial = TRUE delivers
# exactly the requested behavior: partial windows at series start, and
# NA-within-window skipped via na.rm = TRUE in the inline FUN lambda, so
# the window adapts to the months actually observed. All-NA windows
# yield NA (the NaN that mean(x, na.rm=TRUE) produces on empty x is
# coerced back to NA_real_ inside the lambda).

age_bin_panel_df <- age_bin_panel_df |>
  dplyr::arrange(age_bin_chr, month_idx_int) |>
  dplyr::group_by(age_bin_chr) |>
  dplyr::mutate(
    real_hourly_wage_median_roll12_num = zoo::rollapplyr(
      data    = real_hourly_wage_median_num,
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
  dplyr::ungroup() |>
  dplyr::mutate(
    date_dt     = as.Date(sprintf("%04d-%02d-01", year_int, month_int)),
    age_bin_fct = factor(age_bin_chr, levels = age_bin_levels_chr)
  ) |>
  dplyr::arrange(age_bin_fct, month_idx_int)

###################################
###   7) Validate axis ranges   ###
###################################
# Sanity-check the computed medians against the applied hourly outlier
# trim bounds: $0.50 to $200 in 1989 dollars (Departure #5; the lower
# bound matches EPI, the $200 upper supersedes EPI's $100), which
# translate to roughly $1.10 to $442 per hour in December 2025 PCE
# dollars via PCEPI(Dec 1989)/PCEPI(Dec 2025). Monthly medians should
# fall comfortably inside this range.

wage_min_num <- min(age_bin_panel_df$real_hourly_wage_median_num, na.rm = TRUE)
wage_max_num <- max(age_bin_panel_df$real_hourly_wage_median_num, na.rm = TRUE)

if (is.na(wage_min_num) || wage_min_num <= 0) {
  stop(
    "figure_b_age_bins.R -- computed cell-median minimum is not ",
    "positive (", wage_min_num, "); abort before rendering."
  )
}

if (is.na(wage_max_num) || wage_max_num > 250) {
  stop(
    "figure_b_age_bins.R -- computed cell-median maximum exceeds ",
    "$250/hr (", wage_max_num, "); likely an outlier-trim or deflator ",
    "misconfiguration. Abort before rendering."
  )
}

message(
  "figure_b_age_bins.R -- monthly cell-median range: $",
  format(round(wage_min_num, 2), big.mark = ","), "/hr to $",
  format(round(wage_max_num, 2), big.mark = ","), "/hr"
)

###################################
###   8) Coverage verification  ###
###################################
# Every age bin observed in the valid input data should have at least
# one non-NA monthly median in the output panel.

observed_bins_chr <- sort(
  unique(real_wage_df$age_bin_chr[valid_bool])
)

panel_bins_with_median_chr <- sort(unique(
  age_bin_panel_df$age_bin_chr[!is.na(age_bin_panel_df$real_hourly_wage_median_num)]
))

missing_from_panel_chr <- setdiff(observed_bins_chr, panel_bins_with_median_chr)

if (length(missing_from_panel_chr) > 0L) {
  stop(
    "figure_b_age_bins.R -- age bin(s) present in valid input but ",
    "absent from the output panel: ",
    paste(missing_from_panel_chr, collapse = ", ")
  )
}

###################################
###   9) Render ggplot          ###
###################################

fig_b_plot <- ggplot2::ggplot(
  age_bin_panel_df,
  ggplot2::aes(
    x     = date_dt,
    color = age_bin_fct
  )
) +
  ggplot2::geom_point(
    ggplot2::aes(y = real_hourly_wage_median_num),
    alpha = 0.3,
    size  = 0.9,
    na.rm = TRUE
  ) +
  ggplot2::geom_line(
    ggplot2::aes(y = real_hourly_wage_median_roll12_num),
    alpha     = 1.0,
    linewidth = 0.7,
    na.rm     = TRUE
  ) +
  ggplot2::scale_color_manual(
    values = age_bin_colors_chr,
    name   = "Age bin"
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::label_dollar(accuracy = 1L)
  ) +
  ggplot2::scale_x_date(
    date_breaks = "4 years",
    date_labels = "%Y"
  ) +
  ggplot2::labs(
    title    = "Figure 2. Real hourly wage median by age bin",
    subtitle = "Monthly weighted medians (points) and 12-month rolling average (line), in December 2025 PCE dollars",
    x        = NULL,
    y        = "Real hourly wage (Dec 2025 $)",
    caption  = stringr::str_wrap(
      paste0(
        "Source: IPUMS-CPS ORG, 1982 to latest; BEA PCEPI via FRED. ",
        "Sample: civilian wage-and-salary workers age 16 and older with ",
        "EARNWT > 0. The youngest age bin is small and volatile; interpret ",
        "it with care. Census-imputed (allocated) earnings records are ",
        "retained, matching EPI's public extract. October 2025 data not ",
        "collected due to federal government ",
        "shutdown. The rolling average line uses a backward-looking 12-month ",
        "window; missing months contribute no data to the window."
      ),
      width = 145
    )
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

###################################
###   10) Write PNG + CSV       ###
###################################

ggplot2::ggsave(
  filename = fig_png_chr,
  plot     = fig_b_plot,
  width    = 10.0,
  height   = 5.4,
  units    = "in",
  dpi      = 300L,
  device   = eig_png_device
)

# Wide by age bin, one file per outcome variable type. Column order:
# year, month, date, then the six age-bin columns youngest to oldest.
# Snake-case column names from age_bin_column_names_chr so Datawrapper
# can parse them as valid identifiers.
age_bin_column_order_chr <- unname(age_bin_column_names_chr[age_bin_levels_chr])

monthly_wide_df <- age_bin_panel_df |>
  dplyr::mutate(
    age_bin_col_chr = unname(age_bin_column_names_chr[age_bin_chr])
  ) |>
  dplyr::select(
    year_int, month_int, date_dt, age_bin_col_chr,
    real_hourly_wage_median_num
  ) |>
  tidyr::pivot_wider(
    names_from  = age_bin_col_chr,
    values_from = real_hourly_wage_median_num
  ) |>
  dplyr::select(
    year_int, month_int, date_dt,
    dplyr::all_of(age_bin_column_order_chr)
  ) |>
  dplyr::arrange(year_int, month_int)

rolling_wide_df <- age_bin_panel_df |>
  dplyr::mutate(
    age_bin_col_chr = unname(age_bin_column_names_chr[age_bin_chr])
  ) |>
  dplyr::select(
    year_int, month_int, date_dt, age_bin_col_chr,
    real_hourly_wage_median_roll12_num
  ) |>
  tidyr::pivot_wider(
    names_from  = age_bin_col_chr,
    values_from = real_hourly_wage_median_roll12_num
  ) |>
  dplyr::select(
    year_int, month_int, date_dt,
    dplyr::all_of(age_bin_column_order_chr)
  ) |>
  dplyr::arrange(year_int, month_int)

readr::write_csv(monthly_wide_df, fig_monthly_csv_chr)
readr::write_csv(rolling_wide_df, fig_rolling_csv_chr)

message(
  "figure_b_age_bins.R -- wrote PNG (", fig_png_chr,
  ") and wide CSVs (", fig_monthly_csv_chr, ", ", fig_rolling_csv_chr, ")"
)

###################################
###   11) Verify outputs exist  ###
###################################

for (path_chr in c(fig_png_chr, fig_monthly_csv_chr, fig_rolling_csv_chr)) {
  if (!fs::file_exists(path_chr)) {
    stop("figure_b_age_bins.R -- output not written: ", path_chr)
  }
}

message("figure_b_age_bins.R -- done.")
