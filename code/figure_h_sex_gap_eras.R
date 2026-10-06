# figure_h_sex_gap_eras -- men's vs women's real wage levels, growth, and pay gap by percentile, stagnation eras vs the nascent recovery onward
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

rm(list = ls())
options(scipen = 999)
set.seed(42)

# Standalone script (not yet sourced by run_all.R). Reads the real-wage
# panel written by 02a_build_real_wages.R and the era table written by
# figure_f_era_bars_tables.R, so run those first.
#
# Two periods, both taken from the named eras (figure_a_percentiles.R
# step 8e, era partition in figure_f_era_bars_tables.R):
#   stagnations  start of stagnation1 (Dec 1982) -> end of stagnation2 (Oct 2014)
#   recovery_on  start of recovery   (Nov 2014) -> latest data month
#
# For each period and sex, the script builds two paired tables:
#   Table 1  levels and growth -- 10th/25th/50th/75th/90th percentile hourly
#            wage at the period's first and last month, cumulative growth,
#            annualized growth, and the women-minus-men growth gap
#   Table 2  pay gap -- men-minus-women dollar gap and women's pay as a
#            percent of men's at the first and last month
#
# Construction, step by step (mirrors figure_a_percentiles_by_sex.R):
#   1. Load the person-month real-wage records for the years the endpoint
#      windows touch. real_hourly_wage_num is in December 2025 PCE dollars.
#   2. Monthly EARNWT-weighted percentiles within (month, sex), via the
#      shared weighted_quantile() (Stata _pctile / EPI no-interpolation).
#   3. Endpoint level = plain 12-month backward rolling average of the
#      monthly percentiles over the calendar window [t-11, t] (decision 08);
#      months with no CPS sample (October 2025) drop out of the window.
#   4. Growth = last / first - 1; annualized over (months between) / 12.
#   5. Gap = men - women (dollars); ratio = women / men.
#   6. Cross-check: growth must match the by-sex indexed workbook
#      (figure_a_percentiles_indexed_by_sex_roll12.xlsx) at the same months.
#
# Outputs:
#   output/tables/figure_h_sex_gap_levels.csv   (Table 1, both periods)
#   output/tables/figure_h_sex_gap_ratios.csv   (Table 2, both periods)
#   output/figures/figure_h_sex_gap_eras.png    (Figure 8, provisional number)
#
# Education-third extension (steps 8-10; also needs Figure 6c's third
# fractions from figure_f_era_bars_tables.R). Same periods and encoding,
# as a grid of periods (columns) x education thirds (rows):
#   within        percentiles within each (sex, third)          -> Figure 8b
#   overall_rank  each third's SHARE of the workers at each sex's
#                 OVERALL percentile ranks (+/- 2.5 rank points),
#                 as the percentage-point change per decade      -> Figure 8c
#   output/tables/figure_h_sex_gap_educ_within_levels.csv
#   output/tables/figure_h_sex_gap_educ_overall_rank_levels.csv
#   output/figures/figure_h_sex_gap_educ_within.png
#   output/figures/figure_h_sex_gap_educ_overall_rank.png
# Step 8 checks that the pooled-sex third medians reproduce Figure 6c's
# rolling levels at every endpoint month.
#
# Figure design (eig-figure-style.md + tufte-principles.md): two small
# multiples on one shared y scale, one per period. Each shows annualized
# real wage growth across the percentiles for women (Forest Green, circles)
# and men (Gold, squares); a light gray rule joins the pair at each
# percentile, so its length is the growth gap. Annualized rates put a
# 32-year and a 12-year period on the same scale. Direct labels, no legend,
# horizontal light gridlines only, no plot border, y axis from zero.
#
# No custom functions are defined.

source(here::here("code", "_utils", "00_packages.R"))
source(here::here("code", "_utils", "load_palette.R"))
source(here::here("code", "_utils", "eig_fonts.R"))

###################################
###   Configuration             ###
###################################

panel_in_dir_chr <- here::here("data", "intermediate", "cps_real_wages")
tbl_dir_chr      <- here::here("output", "tables")
fig_out_dir_chr  <- here::here("output", "figures")

era_csv_chr      <- fs::path(tbl_dir_chr, "figure_f_percentiles_era_growth.csv")
index_xlsx_chr   <- fs::path(tbl_dir_chr, "figure_a_percentiles_indexed_by_sex_roll12.xlsx")
levels_csv_chr   <- fs::path(tbl_dir_chr, "figure_h_sex_gap_levels.csv")
ratios_csv_chr   <- fs::path(tbl_dir_chr, "figure_h_sex_gap_ratios.csv")
fig_png_chr      <- fs::path(fig_out_dir_chr, "figure_h_sex_gap_eras.png")

# Education-third extension (steps 8-10).
frac_csv_chr         <- fs::path(tbl_dir_chr, "figure_f_education_third_fractions.csv")
educ_index_csv_chr   <- fs::path(tbl_dir_chr, "figure_f_education_indexed_roll12.csv")
educ_levels_csv_chr  <- c(within       = fs::path(tbl_dir_chr, "figure_h_sex_gap_educ_within_levels.csv"),
                          overall_rank = fs::path(tbl_dir_chr, "figure_h_sex_gap_educ_overall_rank_levels.csv"))
educ_fig_png_chr     <- c(within       = fs::path(fig_out_dir_chr, "figure_h_sex_gap_educ_within.png"),
                          overall_rank = fs::path(fig_out_dir_chr, "figure_h_sex_gap_educ_overall_rank.png"))

third_keys_chr   <- c("bottom", "middle", "top")
third_labels_chr <- c(bottom = "Least\neducated\nthird", middle = "Middle\nthird", top = "Most\neducated\nthird")

# Overall-rank version: a worker counts toward percentile p when their
# EARNWT-weighted rank in their sex's whole monthly wage distribution is
# within this many rank points of p (0.025 => ranks 7.5-12.5 for p10).
rank_band_half_num <- 0.025

# Monthly cells thinner than this are reported (and named in the figure
# note) as thin; the 12-month average still uses them.
thin_cell_n_int <- 30L

percentile_probs_num <- c(p10 = 0.10, p25 = 0.25, p50 = 0.50, p75 = 0.75, p90 = 0.90)
percentile_keys_chr  <- names(percentile_probs_num)

# IPUMS-CPS SEX: 1 = male, 2 = female (figure_a_percentiles_by_sex.R).
sex_labels_chr <- c("1" = "Men", "2" = "Women")

# Decision 08: flat 12-month backward rolling window.
rolling_window_int <- 12L

# Growth in this script must reproduce the indexed workbook to within
# this many percentage points (rounding only).
check_tol_pts_num <- 0.05

# Figure size and type (print sizes per eig-figure-style.md section 2).
fig_width_in_num  <- 6.5
fig_height_in_num <- 4.3
fig_dpi_int       <- 300L
title_pt_num      <- 11
subtitle_pt_num   <- 9
strip_pt_num      <- 9
axis_title_pt_num <- 9
axis_pt_num       <- 8
label_pt_num      <- 8
caption_pt_num    <- 7

women_color_chr   <- unname(eig_palette_2022_primary["eig_green_700"])   # sequence 1
men_color_chr     <- unname(eig_palette_2022_primary["eig_gold_600"])    # sequence 2
gap_rule_color_chr <- "#BDBDBD"
grid_color_chr    <- "#D9D9D9"
text_color_chr    <- "#333333"
tick_color_chr    <- "#6B6B6B"

source_line_chr <- paste0(
  "Source: Author's analysis of IPUMS-CPS Outgoing Rotation Group microdata, ",
  "weighted by CPS earnings weights; inflation adjustment uses the U.S. Bureau ",
  "of Economic Analysis Personal Consumption Expenditures price index, via FRED."
)

fs::dir_create(c(tbl_dir_chr, fig_out_dir_chr), recurse = TRUE)

###################################
###   0) Period boundaries      ###
###################################
# Taken from the era table, not re-typed, so a change to the era
# partition flows through here.

if (!fs::file_exists(era_csv_chr)) {
  stop("figure_h_sex_gap_eras.R -- missing ", era_csv_chr, ". Run figure_f_era_bars_tables.R first.")
}

eras_df <- readr::read_csv(era_csv_chr, show_col_types = FALSE) |>
  dplyr::distinct(era_slug_chr, era_start_dt, era_end_dt) |>
  dplyr::mutate(
    start_idx_int = as.integer(lubridate::year(era_start_dt) * 12L + lubridate::month(era_start_dt) - 1L),
    end_idx_int   = as.integer(lubridate::year(era_end_dt)   * 12L + lubridate::month(era_end_dt)   - 1L)
  )

required_eras_chr <- c("stagnation1", "stagnation2", "recovery", "covid_aftermath")
if (!all(required_eras_chr %in% eras_df$era_slug_chr)) {
  stop("figure_h_sex_gap_eras.R -- era table lacks one of: ", paste(required_eras_chr, collapse = ", "))
}
periods_df <- tibble::tibble(
  period_chr    = c("stagnations", "recovery_on"),
  start_idx_int = c(eras_df$start_idx_int[eras_df$era_slug_chr == "stagnation1"],
                    eras_df$start_idx_int[eras_df$era_slug_chr == "recovery"]),
  end_idx_int   = c(eras_df$end_idx_int[eras_df$era_slug_chr == "stagnation2"],
                    eras_df$end_idx_int[eras_df$era_slug_chr == "covid_aftermath"])
) |>
  dplyr::mutate(
    years_num      = (end_idx_int - start_idx_int) / 12,
    start_date_dt  = as.Date(sprintf("%d-%02d-01", start_idx_int %/% 12L, start_idx_int %% 12L + 1L)),
    end_date_dt    = as.Date(sprintf("%d-%02d-01", end_idx_int %/% 12L, end_idx_int %% 12L + 1L)),
    period_label_chr = paste0(format(start_date_dt, "%b %Y"), " to ", format(end_date_dt, "%b %Y"))
  )

periods_df$era_note_chr <- c("First and second long wage stagnations",
                             "Nascent recovery through COVID-19 aftermath")

print(periods_df)

# Era-by-era view (step 11): the five contiguous eras of the era table,
# plus the overlapping "uncertainty" window of figure_a_percentiles.R
# step 8e (January 2024 -> latest; not in the era table). Each era runs
# from its first month to its last, as in Figure 6 (figure_f_era_bars),
# so consecutive eras do not chain exactly (one month falls between them).
uncertainty_start_idx_int <- 2024L * 12L + 1L - 1L
era_periods_df <- eras_df |>
  dplyr::select(era_slug_chr, start_idx_int, end_idx_int) |>
  dplyr::bind_rows(tibble::tibble(
    era_slug_chr  = "uncertainty",
    start_idx_int = uncertainty_start_idx_int,
    end_idx_int   = eras_df$end_idx_int[eras_df$era_slug_chr == "covid_aftermath"]
  )) |>
  dplyr::mutate(
    era_label_chr = dplyr::recode(era_slug_chr,
      stagnation1 = "First long wage stagnation", itboom = "Late-1990s IT boom",
      stagnation2 = "Second long wage stagnation", recovery = "Nascent recovery",
      covid_aftermath = "COVID-19 aftermath", uncertainty = "Age of economic uncertainty (overlaps)"),
    years_num     = (end_idx_int - start_idx_int) / 12,
    period_label_chr = paste0(
      format(as.Date(sprintf("%d-%02d-01", start_idx_int %/% 12L, start_idx_int %% 12L + 1L)), "%b %Y"), " to ",
      format(as.Date(sprintf("%d-%02d-01", end_idx_int %/% 12L, end_idx_int %% 12L + 1L)), "%b %Y"))
  )

###################################
###   1) Load real-wage records ###
###################################
# Only the calendar years that the endpoint windows touch (the two
# contrast periods and every era).

endpoint_idx_int <- sort(unique(c(periods_df$start_idx_int, periods_df$end_idx_int,
                                  era_periods_df$start_idx_int, era_periods_df$end_idx_int)))
window_idx_int   <- sort(unique(unlist(lapply(endpoint_idx_int, \(e) seq(e - rolling_window_int + 1L, e)))))
window_years_int <- sort(unique(window_idx_int %/% 12L))

parquet_paths_chr <- fs::dir_ls(panel_in_dir_chr, regexp = "part-0[.]parquet$", recurse = TRUE, type = "file")
parquet_paths_chr <- parquet_paths_chr[
  stringr::str_extract(parquet_paths_chr, "(?<=year=)\\d{4}") %in% as.character(window_years_int)
]
if (length(parquet_paths_chr) == 0L) {
  stop("figure_h_sex_gap_eras.R -- no real-wage partitions for years ",
       paste(window_years_int, collapse = ", "), ". Run 02a_build_real_wages.R first.")
}

real_wage_df <- arrow::open_dataset(parquet_paths_chr, format = "parquet") |>
  dplyr::select(YEAR, MONTH, SEX, EARNWT, EDUC, pareto_topcode_imputed_flag, real_hourly_wage_num) |>
  dplyr::collect() |>
  dplyr::filter(
    !is.na(real_hourly_wage_num), !is.na(EARNWT), EARNWT > 0,
    SEX %in% as.integer(names(sex_labels_chr))
  ) |>
  dplyr::mutate(month_idx_int = as.integer(YEAR * 12L + MONTH - 1L)) |>
  dplyr::filter(month_idx_int %in% window_idx_int)

message("figure_h_sex_gap_eras.R -- loaded ", format(nrow(real_wage_df), big.mark = ","),
        " person-month records for years ", paste(window_years_int, collapse = ", "))

###################################
###   2) Monthly percentiles    ###
###################################

monthly_df <- real_wage_df |>
  dplyr::group_by(month_idx_int, SEX) |>
  dplyr::summarise(
    n_obs_int = dplyr::n(),
    p10 = weighted_quantile(real_hourly_wage_num, EARNWT, percentile_probs_num[["p10"]]),
    p25 = weighted_quantile(real_hourly_wage_num, EARNWT, percentile_probs_num[["p25"]]),
    p50 = weighted_quantile(real_hourly_wage_num, EARNWT, percentile_probs_num[["p50"]]),
    p75 = weighted_quantile(real_hourly_wage_num, EARNWT, percentile_probs_num[["p75"]]),
    p90 = weighted_quantile(real_hourly_wage_num, EARNWT, percentile_probs_num[["p90"]]),
    .groups = "drop"
  ) |>
  dplyr::mutate(sex_chr = unname(sex_labels_chr[as.character(SEX)])) |>
  tidyr::pivot_longer(dplyr::all_of(percentile_keys_chr), names_to = "percentile_chr", values_to = "wage_num")

###################################
###   3) Endpoint 12-mo levels  ###
###################################
# One row per (endpoint month, sex, percentile): the mean of the monthly
# percentiles over the observed months in [t-11, t].

endpoint_df <- tidyr::expand_grid(end_idx_int = endpoint_idx_int, win_idx_int = 0:(rolling_window_int - 1L)) |>
  dplyr::mutate(month_idx_int = end_idx_int - win_idx_int) |>
  dplyr::inner_join(monthly_df, by = "month_idx_int", relationship = "many-to-many") |>
  dplyr::group_by(end_idx_int, sex_chr, percentile_chr) |>
  dplyr::summarise(
    level_num     = mean(wage_num),
    months_int    = dplyr::n(),
    n_obs_int     = sum(n_obs_int),
    .groups = "drop"
  )

if (any(endpoint_df$months_int < rolling_window_int - 1L)) {
  stop("figure_h_sex_gap_eras.R -- an endpoint window has fewer than ",
       rolling_window_int - 1L, " observed months.")
}

###################################
###   4) Table 1: levels/growth ###
###################################

levels_long_df <- periods_df |>
  dplyr::select(period_chr, period_label_chr, start_idx_int, end_idx_int, years_num) |>
  dplyr::left_join(
    endpoint_df |> dplyr::rename(start_idx_int = end_idx_int, start_level_num = level_num,
                                 start_months_int = months_int, start_n_obs_int = n_obs_int),
    by = "start_idx_int", relationship = "one-to-many"
  ) |>
  dplyr::left_join(
    endpoint_df |> dplyr::rename(end_level_num = level_num,
                                 end_months_int = months_int, end_n_obs_int = n_obs_int),
    by = c("end_idx_int", "sex_chr", "percentile_chr")
  ) |>
  dplyr::mutate(
    growth_pct_num     = 100 * (end_level_num / start_level_num - 1),
    annualized_pct_num = 100 * ((end_level_num / start_level_num)^(1 / years_num) - 1)
  )

levels_df <- levels_long_df |>
  dplyr::select(period_chr, period_label_chr, years_num, percentile_chr, sex_chr,
                start_level_num, end_level_num, growth_pct_num, annualized_pct_num) |>
  tidyr::pivot_wider(names_from = sex_chr,
                     values_from = c(start_level_num, end_level_num, growth_pct_num, annualized_pct_num)) |>
  dplyr::mutate(growth_gap_pts_num = growth_pct_num_Women - growth_pct_num_Men) |>
  dplyr::arrange(factor(period_chr, periods_df$period_chr), factor(percentile_chr, percentile_keys_chr))

###################################
###   5) Table 2: pay gap       ###
###################################

ratios_df <- levels_df |>
  dplyr::transmute(
    period_chr, period_label_chr, percentile_chr,
    start_gap_usd_num   = start_level_num_Men - start_level_num_Women,
    end_gap_usd_num     = end_level_num_Men   - end_level_num_Women,
    start_ratio_pct_num = 100 * start_level_num_Women / start_level_num_Men,
    end_ratio_pct_num   = 100 * end_level_num_Women   / end_level_num_Men
  )

readr::write_csv(levels_df, levels_csv_chr)
readr::write_csv(ratios_df, ratios_csv_chr)

# Console view of the paired tables, rounded as in the write-up.
for (p in periods_df$period_chr) {
  message("\n== ", periods_df$period_label_chr[periods_df$period_chr == p], " ==")
  print(levels_df |>
    dplyr::filter(period_chr == p) |>
    dplyr::transmute(
      pct       = percentile_chr,
      men_start = round(start_level_num_Men, 2),   men_end   = round(end_level_num_Men, 2),
      men_g     = round(growth_pct_num_Men, 1),
      wom_start = round(start_level_num_Women, 2), wom_end   = round(end_level_num_Women, 2),
      wom_g     = round(growth_pct_num_Women, 1),
      gap_pts   = round(growth_gap_pts_num, 1)
    ), n = Inf)
  print(ratios_df |>
    dplyr::filter(period_chr == p) |>
    dplyr::transmute(
      pct = percentile_chr,
      gap_start = round(start_gap_usd_num, 2), gap_end = round(end_gap_usd_num, 2),
      ratio_start = round(start_ratio_pct_num, 1), ratio_end = round(end_ratio_pct_num, 1)
    ), n = Inf)
}

###################################
###   6) Cross-check vs index   ###
###################################
# Same construction as figure_a_percentiles_by_sex.R, so growth between
# the two months must match that script's indexed workbook.

if (fs::file_exists(index_xlsx_chr) && requireNamespace("readxl", quietly = TRUE)) {
  index_df <- dplyr::bind_rows(
    readxl::read_excel(index_xlsx_chr, sheet = "Male")   |> dplyr::mutate(sex_chr = "Men"),
    readxl::read_excel(index_xlsx_chr, sheet = "Female") |> dplyr::mutate(sex_chr = "Women")
  ) |>
    dplyr::mutate(month_idx_int = as.integer(year_int * 12L + month_int - 1L))
  # Values inside the COVID window live in the *_covid sidecar columns.
  for (k in percentile_keys_chr) {
    index_df[[k]] <- dplyr::coalesce(index_df[[k]], index_df[[paste0(k, "_covid")]])
  }
  index_long_df <- index_df |>
    dplyr::select(month_idx_int, sex_chr, dplyr::all_of(percentile_keys_chr)) |>
    tidyr::pivot_longer(dplyr::all_of(percentile_keys_chr), names_to = "percentile_chr", values_to = "index_num")

  check_df <- levels_long_df |>
    dplyr::left_join(index_long_df |> dplyr::rename(start_idx_int = month_idx_int, start_index_num = index_num),
                     by = c("start_idx_int", "sex_chr", "percentile_chr")) |>
    dplyr::left_join(index_long_df |> dplyr::rename(end_idx_int = month_idx_int, end_index_num = index_num),
                     by = c("end_idx_int", "sex_chr", "percentile_chr")) |>
    dplyr::mutate(diff_pts_num = growth_pct_num - 100 * (end_index_num / start_index_num - 1))

  if (anyNA(check_df$diff_pts_num) || any(abs(check_df$diff_pts_num) > check_tol_pts_num)) {
    stop("figure_h_sex_gap_eras.R -- growth disagrees with ", fs::path_file(index_xlsx_chr),
         " by up to ", round(max(abs(check_df$diff_pts_num), na.rm = TRUE), 3),
         " pts; rerun figure_a_percentiles_by_sex.R or check the panel.")
  }
  message("figure_h_sex_gap_eras.R -- growth matches the by-sex index workbook (max diff ",
          signif(max(abs(check_df$diff_pts_num)), 2), " pts).")
} else {
  warning("figure_h_sex_gap_eras.R -- by-sex index workbook or readxl unavailable; cross-check skipped.")
}

###################################
###   7) Figure                 ###
###################################

pct_position_num <- c(p10 = 10, p25 = 25, p50 = 50, p75 = 75, p90 = 90)
pct_tick_chr     <- c("10th", "25th", "50th\n(median)", "75th", "90th")

facet_levels_chr <- paste0(periods_df$period_label_chr, "\n", periods_df$era_note_chr)

plot_df <- levels_long_df |>
  dplyr::left_join(periods_df |> dplyr::select(period_chr, era_note_chr), by = "period_chr") |>
  dplyr::mutate(
    facet_chr = factor(paste0(period_label_chr, "\n", era_note_chr), levels = facet_levels_chr),
    x_num     = unname(pct_position_num[percentile_chr]),
    sex_chr   = factor(sex_chr, levels = c("Women", "Men"))
  )

gap_rule_df <- plot_df |>
  dplyr::select(facet_chr, x_num, sex_chr, annualized_pct_num) |>
  tidyr::pivot_wider(names_from = sex_chr, values_from = annualized_pct_num)

# Direct labels in the first panel only (the second shares the encoding),
# placed where the pair is far apart: Women above its median point, Men
# below its 90th-percentile point (below Men's median there is no room).
label_df <- plot_df |>
  dplyr::filter(
    facet_chr == facet_levels_chr[1],
    (sex_chr == "Women" & percentile_chr == "p50") | (sex_chr == "Men" & percentile_chr == "p90")
  ) |>
  dplyr::mutate(
    label_y_num = annualized_pct_num + dplyr::if_else(sex_chr == "Women", 0.15, -0.12),
    vjust_num   = dplyr::if_else(sex_chr == "Women", 0, 1)
  )

y_max_num <- max(plot_df$annualized_pct_num)
y_top_num <- ceiling(y_max_num * 2) / 2

subtitle_chr <- paste0(
  "Average annual real hourly wage growth (%) at each percentile of men's and of women's wage distribution. ",
  "The gray rule at each percentile is the gap between them."
)
note_chr <- paste0(
  "Note: Wage and salary workers age 16 and older. Endpoints are equally weighted 12-month rolling averages of monthly ",
  "EARNWT-weighted percentiles in December 2025 dollars; each sex is ranked within its own distribution. ",
  "No October 2025 CPS sample (federal shutdown). Changes in who is working, including women's rising education, ",
  "shape these rates; no sampling error is shown."
)

fig_plot <- ggplot2::ggplot(plot_df, ggplot2::aes(x = x_num, y = annualized_pct_num)) +
  ggplot2::geom_hline(yintercept = 0, color = tick_color_chr, linewidth = 0.3) +
  ggplot2::geom_segment(
    data = gap_rule_df,
    ggplot2::aes(x = x_num, xend = x_num, y = Men, yend = Women),
    inherit.aes = FALSE, color = gap_rule_color_chr, linewidth = 1.6, lineend = "butt"
  ) +
  ggplot2::geom_line(ggplot2::aes(color = sex_chr, group = sex_chr), linewidth = 0.6) +
  ggplot2::geom_point(ggplot2::aes(color = sex_chr, shape = sex_chr), size = 1.9, fill = "white", stroke = 0.9) +
  ggplot2::geom_text(
    data = label_df,
    ggplot2::aes(y = label_y_num, label = sex_chr, color = sex_chr, vjust = vjust_num),
    family = eig_font_body_chr, fontface = "bold", size = label_pt_num / ggplot2::.pt
  ) +
  ggplot2::facet_wrap(ggplot2::vars(facet_chr), nrow = 1) +
  ggplot2::scale_color_manual(values = c(Women = women_color_chr, Men = men_color_chr), guide = "none") +
  ggplot2::scale_shape_manual(values = c(Women = 21, Men = 22), guide = "none") +
  ggplot2::scale_x_continuous(
    breaks = unname(pct_position_num), labels = pct_tick_chr,
    limits = c(4, 96), expand = ggplot2::expansion(0)
  ) +
  ggplot2::scale_y_continuous(
    limits = c(0, y_top_num), breaks = seq(0, y_top_num, by = 0.5),
    labels = \(v) dplyr::if_else(v == 0, "0%", paste0(formatC(v, format = "f", digits = 1), "%")),
    expand = ggplot2::expansion(mult = c(0, 0.02))
  ) +
  ggplot2::labs(
    title    = "Figure 8. Real wage growth by sex and percentile, 1982 to 2014 and 2014 to 2026",
    subtitle = stringr::str_wrap(subtitle_chr, 92),
    x        = "Percentile of each sex's hourly wage distribution",
    y        = NULL,
    caption  = paste0(stringr::str_wrap(note_chr, 118), "\n", stringr::str_wrap(source_line_chr, 118))
  )

# One theme for Figure 8 and the education-third versions (steps 8-10).
fig_theme <- ggplot2::theme_minimal(base_family = eig_font_body_chr) +
  ggplot2::theme(
    plot.title         = ggplot2::element_text(family = eig_font_title_chr, face = "bold", size = title_pt_num,
                                               color = text_color_chr, margin = ggplot2::margin(b = 3)),
    plot.subtitle      = ggplot2::element_text(size = subtitle_pt_num, color = text_color_chr,
                                               margin = ggplot2::margin(b = 8)),
    plot.title.position = "plot",
    plot.caption       = ggplot2::element_text(size = caption_pt_num, color = text_color_chr, hjust = 0,
                                               face = "italic", lineheight = 1.1, margin = ggplot2::margin(t = 8)),
    plot.caption.position = "plot",
    strip.text         = ggplot2::element_text(size = strip_pt_num, color = text_color_chr, hjust = 0,
                                               lineheight = 1.1, margin = ggplot2::margin(b = 4)),
    strip.background   = ggplot2::element_blank(),
    axis.title.x       = ggplot2::element_text(size = axis_title_pt_num, color = text_color_chr,
                                               margin = ggplot2::margin(t = 5)),
    axis.text          = ggplot2::element_text(size = axis_pt_num, color = tick_color_chr),
    panel.grid.major.x = ggplot2::element_blank(),
    panel.grid.minor   = ggplot2::element_blank(),
    panel.grid.major.y = ggplot2::element_line(color = grid_color_chr, linewidth = 0.25),
    panel.spacing.x    = grid::unit(0.3, "in"),
    plot.background    = ggplot2::element_rect(fill = "white", color = NA),
    panel.border       = ggplot2::element_blank(),
    plot.margin        = ggplot2::margin(8, 10, 6, 8)
  )

ggplot2::ggsave(fig_png_chr, fig_plot + fig_theme, width = fig_width_in_num, height = fig_height_in_num,
                dpi = fig_dpi_int, device = eig_png_device, bg = "white")

message("figure_h_sex_gap_eras.R -- wrote ", levels_csv_chr, ", ", ratios_csv_chr, ", and ", fig_png_chr)

###################################
###   8) Education thirds       ###
###################################
# Thirds are the ones Figure 6c uses (figure_f_era_bars_tables.R step 4):
# each year, civilians 25-64 are ranked by four education bins and each
# bin is split fractionally across the thirds, so a wage record carries
# weight EARNWT x (its year-bin fraction) in each third. The wage sample
# itself is not limited to ages 25-64, matching Figure 6c. Records with
# NIU/missing EDUC get zero weight in every third.
#
# Two views of the same thirds:
#   within        percentiles of the wage distribution WITHIN each
#                 (month, sex, third) cell
#   overall_rank  each worker's EARNWT-weighted rank in their sex's WHOLE
#                 monthly distribution; at percentile p, each third's
#                 share of the workers ranked within +/- rank_band_half_num
#                 of p (weight EARNWT x fraction; the three shares sum to
#                 1). Plotted as the percentage-point change per decade.

if (!all(fs::file_exists(c(frac_csv_chr, educ_index_csv_chr)))) {
  stop("figure_h_sex_gap_eras.R -- missing education-third tables. Run figure_f_era_bars_tables.R first.")
}

fractions_df <- readr::read_csv(frac_csv_chr, show_col_types = FALSE) |>
  dplyr::transmute(
    year_int = as.integer(year_int), educ_bin_int = as.integer(educ_bin_int),
    frac_bottom_num, frac_middle_num, frac_top_num
  )
if (!all(window_years_int %in% fractions_df$year_int)) {
  stop("figure_h_sex_gap_eras.R -- third fractions missing for year(s) ",
       paste(setdiff(window_years_int, fractions_df$year_int), collapse = ", "))
}

# How far the thirds' membership moves, for the Figure 8b note: the top
# third's share of the some-college bin (3) at the first and at the
# stagnation-end year, and the middle third's share of the bachelor's+
# bin (4) at the last year.
stag_end_year_int <- periods_df$end_idx_int[periods_df$period_chr == "stagnations"] %/% 12L
third_shift_num <- c(
  top_somecoll_start = fractions_df$frac_top_num[fractions_df$year_int == window_years_int[1] & fractions_df$educ_bin_int == 3L],
  top_somecoll_mid   = fractions_df$frac_top_num[fractions_df$year_int == stag_end_year_int & fractions_df$educ_bin_int == 3L],
  mid_ba_end         = fractions_df$frac_middle_num[fractions_df$year_int == max(window_years_int) & fractions_df$educ_bin_int == 4L]
)
if (length(third_shift_num) != 3L || anyNA(third_shift_num)) {
  stop("figure_h_sex_gap_eras.R -- could not read the third-shift fractions for the note.")
}

# Same EDUC crosswalk as figure_f_era_bars_tables.R step 3.
educ_df <- real_wage_df |>
  dplyr::mutate(
    year_int         = as.integer(YEAR),
    sex_chr          = unname(sex_labels_chr[as.character(SEX)]),
    educ_general_int = as.integer(EDUC %/% 10L),
    educ_bin_int     = dplyr::case_when(
      is.na(EDUC) | EDUC %in% c(0L, 1L) | EDUC >= 999L ~ NA_integer_,
      educ_general_int <= 6L                          ~ 1L,
      educ_general_int == 7L                          ~ 2L,
      educ_general_int %in% 8:10                      ~ 3L,
      educ_general_int %in% 11:12                     ~ 4L,
      TRUE                                            ~ NA_integer_
    )
  ) |>
  dplyr::left_join(fractions_df, by = c("year_int", "educ_bin_int")) |>
  dplyr::mutate(dplyr::across(c(frac_bottom_num, frac_middle_num, frac_top_num), \(f) dplyr::coalesce(f, 0)))

if (nrow(educ_df) != nrow(real_wage_df)) {
  stop("figure_h_sex_gap_eras.R -- the fraction join changed the wage row count.")
}

# Overall within-sex rank, computed on ALL wage records (with or without
# an education bin), before splitting into thirds. Tied wages share the
# midpoint of their combined weight.
educ_df <- educ_df |>
  dplyr::arrange(month_idx_int, sex_chr, real_hourly_wage_num) |>
  dplyr::group_by(month_idx_int, sex_chr) |>
  dplyr::mutate(cum_w_num = cumsum(EARNWT), total_w_num = sum(EARNWT)) |>
  dplyr::group_by(month_idx_int, sex_chr, real_hourly_wage_num) |>
  dplyr::mutate(rank_num = (max(cum_w_num) - sum(EARNWT) / 2) / total_w_num) |>
  dplyr::ungroup()

# One row per (record, third) with positive weight in that third.
educ_long_df <- educ_df |>
  dplyr::select(month_idx_int, sex_chr, EARNWT, real_hourly_wage_num, rank_num, pareto_topcode_imputed_flag,
                frac_bottom_num, frac_middle_num, frac_top_num) |>
  tidyr::pivot_longer(c(frac_bottom_num, frac_middle_num, frac_top_num),
                      names_to = "third_chr", names_pattern = "frac_(.*)_num", values_to = "frac_num") |>
  dplyr::filter(frac_num > 0) |>
  dplyr::mutate(w_num = EARNWT * frac_num)

# Monthly cells, both views.
within_monthly_df <- educ_long_df |>
  dplyr::group_by(month_idx_int, sex_chr, third_chr) |>
  dplyr::reframe(
    percentile_chr = percentile_keys_chr,
    value_num      = weighted_quantile(real_hourly_wage_num, w_num, unname(percentile_probs_num)),
    n_obs_int      = dplyr::n()
  )

# Share of the band's (binned) workers in each third. Every third gets a
# row, so a third with no workers in the band shows a share of 0.
rank_monthly_df <- dplyr::bind_rows(lapply(percentile_keys_chr, \(k) {
  educ_long_df |>
    dplyr::filter(abs(rank_num - percentile_probs_num[[k]]) <= rank_band_half_num) |>
    dplyr::mutate(third_chr = factor(third_chr, levels = third_keys_chr)) |>
    dplyr::group_by(month_idx_int, sex_chr, third_chr, .drop = FALSE) |>
    dplyr::summarise(w_third_num = sum(w_num), n_obs_int = dplyr::n(), .groups = "drop") |>
    dplyr::group_by(month_idx_int, sex_chr) |>
    dplyr::mutate(value_num = w_third_num / sum(w_third_num), n_obs_int = sum(n_obs_int)) |>
    dplyr::ungroup() |>
    dplyr::mutate(third_chr = as.character(third_chr), percentile_chr = k) |>
    dplyr::select(-w_third_num)
}))

share_sum_gap_num <- rank_monthly_df |>
  dplyr::group_by(month_idx_int, sex_chr, percentile_chr) |>
  dplyr::summarise(s = sum(value_num), .groups = "drop") |>
  dplyr::pull(s) |>
  (\(s) max(abs(s - 1)))()
if (share_sum_gap_num > 1e-9) {
  stop("figure_h_sex_gap_eras.R -- third shares at a rank band do not sum to 1 (gap ", signif(share_sum_gap_num, 3), ").")
}

educ_monthly_df <- dplyr::bind_rows(within = within_monthly_df, overall_rank = rank_monthly_df, .id = "view_chr")

# Cross-check: the pooled-sex third medians at the endpoint months must
# reproduce Figure 6c's rolling levels (same thirds, same weights).
pooled_endpoint_df <- educ_long_df |>
  dplyr::group_by(month_idx_int, third_chr) |>
  dplyr::summarise(median_num = weighted_quantile(real_hourly_wage_num, w_num, 0.5), .groups = "drop") |>
  dplyr::inner_join(
    tidyr::expand_grid(end_idx_int = endpoint_idx_int, win_idx_int = 0:(rolling_window_int - 1L)) |>
      dplyr::mutate(month_idx_int = end_idx_int - win_idx_int),
    by = "month_idx_int", relationship = "many-to-many"
  ) |>
  dplyr::group_by(end_idx_int, third_chr) |>
  dplyr::summarise(level_num = mean(median_num), .groups = "drop")

educ_ref_df <- readr::read_csv(educ_index_csv_chr, show_col_types = FALSE) |>
  dplyr::filter(month_idx_int %in% endpoint_idx_int) |>
  dplyr::select(end_idx_int = month_idx_int, bottom = bottom_level_num, middle = middle_level_num, top = top_level_num) |>
  tidyr::pivot_longer(dplyr::all_of(third_keys_chr), names_to = "third_chr", values_to = "ref_level_num")

educ_check_df <- dplyr::inner_join(pooled_endpoint_df, educ_ref_df, by = c("end_idx_int", "third_chr"))
educ_check_rel_num <- max(abs(educ_check_df$level_num / educ_check_df$ref_level_num - 1))
if (nrow(educ_check_df) != length(endpoint_idx_int) * length(third_keys_chr) || educ_check_rel_num > 1e-9) {
  stop("figure_h_sex_gap_eras.R -- pooled third medians do not reproduce ",
       fs::path_file(educ_index_csv_chr), " (max relative diff ", signif(educ_check_rel_num, 3), ").")
}
message("figure_h_sex_gap_eras.R -- pooled third medians match Figure 6c's rolling levels (max relative diff ",
        signif(educ_check_rel_num, 2), ").")

###################################
###   9) Education tables       ###
###################################

educ_endpoint_df <- tidyr::expand_grid(end_idx_int = endpoint_idx_int, win_idx_int = 0:(rolling_window_int - 1L)) |>
  dplyr::mutate(month_idx_int = end_idx_int - win_idx_int) |>
  dplyr::inner_join(educ_monthly_df, by = "month_idx_int", relationship = "many-to-many") |>
  dplyr::group_by(view_chr, end_idx_int, sex_chr, third_chr, percentile_chr) |>
  dplyr::summarise(
    level_num      = mean(value_num),
    months_int     = dplyr::n(),
    min_n_obs_int  = min(n_obs_int),
    .groups = "drop"
  )

if (any(educ_endpoint_df$months_int < rolling_window_int - 1L)) {
  stop("figure_h_sex_gap_eras.R -- an education endpoint window has fewer than ",
       rolling_window_int - 1L, " observed months.")
}

thin_cells_df <- educ_endpoint_df |> dplyr::filter(min_n_obs_int < thin_cell_n_int)
if (nrow(thin_cells_df) > 0L) {
  message("figure_h_sex_gap_eras.R -- ", nrow(thin_cells_df), " endpoint window(s) include a monthly cell under ",
          thin_cell_n_int, " records:")
  print(thin_cells_df, n = Inf)
}

educ_levels_long_df <- periods_df |>
  dplyr::select(period_chr, period_label_chr, start_idx_int, end_idx_int, years_num) |>
  dplyr::left_join(
    educ_endpoint_df |> dplyr::rename(start_idx_int = end_idx_int, start_level_num = level_num,
                                      start_min_n_obs_int = min_n_obs_int) |> dplyr::select(-months_int),
    by = "start_idx_int", relationship = "one-to-many"
  ) |>
  dplyr::left_join(
    educ_endpoint_df |> dplyr::rename(end_level_num = level_num, end_min_n_obs_int = min_n_obs_int) |>
      dplyr::select(-months_int),
    by = c("view_chr", "end_idx_int", "sex_chr", "third_chr", "percentile_chr")
  ) |>
  dplyr::mutate(
    # within: levels are wages, so growth is a ratio.
    growth_pct_num     = 100 * (end_level_num / start_level_num - 1),
    annualized_pct_num = 100 * ((end_level_num / start_level_num)^(1 / years_num) - 1),
    # overall_rank: levels are shares, so change is a difference.
    share_change_pts_num        = 100 * (end_level_num - start_level_num),
    share_change_decade_pts_num = share_change_pts_num / years_num * 10,
    plot_y_num = dplyr::if_else(view_chr == "within", annualized_pct_num, share_change_decade_pts_num)
  )

# The three thirds' share changes at a rank must offset exactly.
share_offset_gap_num <- educ_levels_long_df |>
  dplyr::filter(view_chr == "overall_rank") |>
  dplyr::group_by(period_chr, sex_chr, percentile_chr) |>
  dplyr::summarise(s = sum(share_change_pts_num), .groups = "drop") |>
  dplyr::pull(s) |>
  (\(s) max(abs(s)))()
if (share_offset_gap_num > 1e-9) {
  stop("figure_h_sex_gap_eras.R -- third share changes do not sum to zero (gap ", signif(share_offset_gap_num, 3), ").")
}

# Share table (overall_rank): each third's share of the workers at each
# overall within-sex percentile, first and last month, and the change.
share_table_df <- educ_levels_long_df |>
  dplyr::filter(view_chr == "overall_rank") |>
  dplyr::select(period_chr, period_label_chr, years_num, third_chr, percentile_chr, sex_chr,
                start_level_num, end_level_num, share_change_pts_num, share_change_decade_pts_num,
                start_min_n_obs_int, end_min_n_obs_int) |>
  dplyr::mutate(start_share_pct_num = 100 * start_level_num, end_share_pct_num = 100 * end_level_num) |>
  dplyr::select(-start_level_num, -end_level_num) |>
  tidyr::pivot_wider(names_from = sex_chr,
                     values_from = c(start_share_pct_num, end_share_pct_num, share_change_pts_num,
                                     share_change_decade_pts_num, start_min_n_obs_int, end_min_n_obs_int)) |>
  dplyr::mutate(change_gap_pts_num = share_change_pts_num_Women - share_change_pts_num_Men) |>
  dplyr::arrange(factor(period_chr, periods_df$period_chr), factor(third_chr, third_keys_chr),
                 factor(percentile_chr, percentile_keys_chr))
readr::write_csv(share_table_df, educ_levels_csv_chr[["overall_rank"]])

message("\n== overall_rank (third's share of workers at each overall within-sex percentile, %) ==")
print(share_table_df |>
  dplyr::transmute(
    period = period_chr, third = third_chr, pct = percentile_chr,
    men_start = round(start_share_pct_num_Men, 1), men_end = round(end_share_pct_num_Men, 1),
    wom_start = round(start_share_pct_num_Women, 1), wom_end = round(end_share_pct_num_Women, 1),
    men_chg = round(share_change_pts_num_Men, 1), wom_chg = round(share_change_pts_num_Women, 1)
  ), n = Inf)

# Topcode exposure. 01b replaces each sex-year's topcoded weekly wages
# with one Pareto-fitted mean above the topcode (none after the last
# Pareto year, when they stay at the topcode). That value is a mass point,
# not an observed wage, and the fitted mean rises as alpha falls. When a
# group's imputed share reaches 1 - p, its percentile p IS that value.
# A cell is flagged when the endpoint window's imputed share is at least
# topcode_flag_frac_num x (1 - p), i.e. at or near the mass point.
topcode_flag_frac_num <- 0.8

topcode_monthly_df <- dplyr::bind_rows(
  real_wage_df |>
    dplyr::mutate(sex_chr = unname(sex_labels_chr[as.character(SEX)]), group_chr = "all", w_num = EARNWT),
  educ_long_df |> dplyr::rename(group_chr = third_chr)
) |>
  dplyr::group_by(month_idx_int, sex_chr, group_chr) |>
  dplyr::summarise(imputed_share_num = sum(w_num * (pareto_topcode_imputed_flag %in% TRUE)) / sum(w_num),
                   .groups = "drop")

topcode_endpoint_df <- tidyr::expand_grid(end_idx_int = endpoint_idx_int, win_idx_int = 0:(rolling_window_int - 1L)) |>
  dplyr::mutate(month_idx_int = end_idx_int - win_idx_int) |>
  dplyr::inner_join(topcode_monthly_df, by = "month_idx_int", relationship = "many-to-many") |>
  dplyr::group_by(end_idx_int, sex_chr, group_chr) |>
  dplyr::summarise(imputed_share_num = mean(imputed_share_num), .groups = "drop")

# One row per (endpoint, sex, group, percentile) that sits at or near the
# imputed mass point.
topcode_flags_df <- tidyr::expand_grid(topcode_endpoint_df, percentile_chr = percentile_keys_chr) |>
  dplyr::filter(imputed_share_num >= topcode_flag_frac_num * (1 - percentile_probs_num[percentile_chr])) |>
  dplyr::select(end_idx_int, sex_chr, group_chr, percentile_chr, imputed_share_num)

message("figure_h_sex_gap_eras.R -- ", nrow(topcode_flags_df), " endpoint cell(s) at or near the Pareto topcode mass point:")
print(topcode_flags_df, n = Inf)

# For a (period, group, percentile), which endpoints are flagged, e.g.
# "Men end" -- joined into the tables below.
topcode_period_note_df <- dplyr::bind_rows(
  periods_df |> dplyr::transmute(key_chr = period_chr, start_idx_int, end_idx_int),
  era_periods_df |> dplyr::transmute(key_chr = era_slug_chr, start_idx_int, end_idx_int)
) |>
  tidyr::pivot_longer(c(start_idx_int, end_idx_int), names_to = "side_chr", values_to = "end_idx_int") |>
  dplyr::mutate(side_chr = dplyr::if_else(side_chr == "start_idx_int", "start", "end")) |>
  dplyr::inner_join(topcode_flags_df, by = "end_idx_int", relationship = "many-to-many") |>
  dplyr::group_by(key_chr, group_chr, percentile_chr) |>
  dplyr::summarise(topcode_flag_chr = paste(sprintf("%s %s (%.0f%% imputed)", sex_chr, side_chr, 100 * imputed_share_num),
                                            collapse = "; "), .groups = "drop")

# Wage table (within): levels, growth, gaps, and ratio, one row per
# (period, third, percentile).
for (v in "within") {
  educ_table_df <- educ_levels_long_df |>
    dplyr::filter(view_chr == v) |>
    dplyr::select(period_chr, period_label_chr, years_num, third_chr, percentile_chr, sex_chr,
                  start_level_num, end_level_num, growth_pct_num, annualized_pct_num,
                  start_min_n_obs_int, end_min_n_obs_int) |>
    tidyr::pivot_wider(names_from = sex_chr,
                       values_from = c(start_level_num, end_level_num, growth_pct_num, annualized_pct_num,
                                       start_min_n_obs_int, end_min_n_obs_int)) |>
    dplyr::mutate(
      growth_gap_pts_num  = growth_pct_num_Women - growth_pct_num_Men,
      start_gap_usd_num   = start_level_num_Men - start_level_num_Women,
      end_gap_usd_num     = end_level_num_Men   - end_level_num_Women,
      start_ratio_pct_num = 100 * start_level_num_Women / start_level_num_Men,
      end_ratio_pct_num   = 100 * end_level_num_Women   / end_level_num_Men
    ) |>
    dplyr::left_join(topcode_period_note_df, by = c(period_chr = "key_chr", third_chr = "group_chr", "percentile_chr")) |>
    dplyr::arrange(factor(period_chr, periods_df$period_chr), factor(third_chr, third_keys_chr),
                   factor(percentile_chr, percentile_keys_chr))
  readr::write_csv(educ_table_df, educ_levels_csv_chr[[v]])

  message("\n== ", v, " ==")
  print(educ_table_df |>
    dplyr::transmute(
      period = period_chr, third = third_chr, pct = percentile_chr,
      men_g = round(growth_pct_num_Men, 1), wom_g = round(growth_pct_num_Women, 1),
      gap_pts = round(growth_gap_pts_num, 1),
      ratio_start = round(start_ratio_pct_num, 1), ratio_end = round(end_ratio_pct_num, 1)
    ), n = Inf)
}

###################################
###   10) Education figures     ###
###################################
# Same encoding as Figure 8, laid out as a grid: columns are the two
# periods, rows the three education thirds, one shared y scale.

educ_fig_specs_list <- list(
  within = list(
    title_chr    = "Figure 8b. Real wage growth by sex and percentile within education thirds, 1982 to 2014 and 2014 to 2026",
    subtitle_chr = paste0(
      "Average annual real hourly wage growth (%) at each percentile of the wage distribution of men and of women ",
      "within each education third. The gray rule at each percentile is the gap between them."
    ),
    x_title_chr  = "Percentile of the hourly wage distribution within each sex and education third",
    label_third_chr = "bottom",
    y_label_fun  = \(b) dplyr::if_else(b == 0, "0%", paste0(formatC(b, format = "f", digits = 1), "%"))
  ),
  overall_rank = list(
    title_chr    = "Figure 8c. Change in which education thirds hold each rung of men's and women's wage distributions, 1982 to 2014 and 2014 to 2026",
    subtitle_chr = paste0(
      "Change per decade (percentage points) in each education third's share of the workers ranked near each percentile ",
      "(within 2.5 points) of their sex's whole wage distribution. At each percentile the three thirds' changes sum to zero. ",
      "The gray rule is the gap between men and women."
    ),
    x_title_chr  = "Percentile rank in each sex's whole hourly wage distribution",
    label_third_chr = "top",
    y_label_fun  = \(b) dplyr::case_when(b == 0 ~ "0", b > 0 ~ paste0("+", formatC(b, format = "fg")),
                                         TRUE ~ formatC(b, format = "fg"))
  )
)

educ_note_common_chr <- paste0(
  "Note: Wage and salary workers age 16 and older. Education thirds rank civilians 25 to 64 by four education groups each ",
  "year, splitting a group across two thirds where a cut falls inside it (as in Figure 6c). Endpoints are equally weighted ",
  "12-month rolling averages of monthly EARNWT-weighted statistics in December 2025 dollars. No October 2025 CPS sample ",
  "(federal shutdown). No sampling error is shown."
)

for (v in names(educ_fig_specs_list)) {
  spec <- educ_fig_specs_list[[v]]

  # Column headers: the era note wraps to fit beside the row strips.
  grid_facet_levels_chr <- paste0(periods_df$period_label_chr, "\n", stringr::str_wrap(periods_df$era_note_chr, 28))

  educ_plot_df <- educ_levels_long_df |>
    dplyr::filter(view_chr == v) |>
    dplyr::left_join(periods_df |> dplyr::select(period_chr, era_note_chr), by = "period_chr") |>
    dplyr::mutate(
      facet_chr = factor(paste0(period_label_chr, "\n", stringr::str_wrap(era_note_chr, 28)),
                         levels = grid_facet_levels_chr),
      third_f   = factor(unname(third_labels_chr[third_chr]), levels = unname(third_labels_chr)),
      x_num     = unname(pct_position_num[percentile_chr]),
      sex_chr   = factor(sex_chr, levels = c("Women", "Men"))
    )

  educ_gap_df <- educ_plot_df |>
    dplyr::select(facet_chr, third_f, x_num, sex_chr, plot_y_num) |>
    tidyr::pivot_wider(names_from = sex_chr, values_from = plot_y_num)

  if (v == "within") {
    y_lo_num <- min(0, floor(min(educ_plot_df$plot_y_num) * 2) / 2)
    y_hi_num <- ceiling(max(educ_plot_df$plot_y_num) * 2) / 2
    y_step_num <- if (y_hi_num - y_lo_num > 3) 1 else 0.5
    # Breaks anchored on zero so the 0% line is always a gridline.
    y_breaks_num <- seq(ceiling(y_lo_num / y_step_num) * y_step_num, y_hi_num, by = y_step_num)
  } else {
    # Share changes run both ways; pretty() breaks include zero.
    y_breaks_num <- pretty(range(c(0, educ_plot_df$plot_y_num)), n = 4)
    y_lo_num <- min(y_breaks_num)
    y_hi_num <- max(y_breaks_num)
  }
  label_off_num <- 0.05 * (y_hi_num - y_lo_num)

  # Direct labels in the left column (row set by the spec), between markers so they
  # sit clear of the points: Women above its line midway from the 25th to
  # the 50th, Men below its line midway from the 50th to the 75th.
  first_panel_df <- educ_plot_df |>
    dplyr::filter(facet_chr == grid_facet_levels_chr[1], third_chr == spec$label_third_chr)
  educ_label_df <- tibble::tibble(
    sex_chr = factor(c("Women", "Men"), levels = c("Women", "Men")),
    x_lo_chr = c("p25", "p50"), x_hi_chr = c("p50", "p75")
  ) |>
    dplyr::mutate(
      facet_chr = factor(grid_facet_levels_chr[1], levels = grid_facet_levels_chr),
      third_f   = factor(third_labels_chr[[spec$label_third_chr]], levels = unname(third_labels_chr)),
      x_num     = (pct_position_num[x_lo_chr] + pct_position_num[x_hi_chr]) / 2,
      line_y_num = purrr::pmap_dbl(list(sex_chr, x_lo_chr, x_hi_chr), \(s, lo, hi) mean(
        first_panel_df$plot_y_num[first_panel_df$sex_chr == s & first_panel_df$percentile_chr %in% c(lo, hi)]
      )),
      label_y_num = line_y_num + dplyr::if_else(sex_chr == "Women", label_off_num, -label_off_num),
      vjust_num   = dplyr::if_else(sex_chr == "Women", 0, 1),
      plot_y_num = label_y_num
    )

  thin_n_int <- sum(educ_endpoint_df$view_chr == v & educ_endpoint_df$min_n_obs_int < thin_cell_n_int)

  # Wage points whose start or end sits at or near the Pareto topcode mass
  # point get a dagger (within view only; shares are rank-based).
  dagger_df <- educ_plot_df[0, ]
  if (v == "within") {
    dagger_df <- educ_plot_df |>
      dplyr::filter(purrr::pmap_lgl(list(start_idx_int, end_idx_int, as.character(sex_chr), third_chr, percentile_chr),
        \(s, e, sx, th, pc) any(topcode_flags_df$end_idx_int %in% c(s, e) & topcode_flags_df$sex_chr == sx &
                                topcode_flags_df$group_chr == th & topcode_flags_df$percentile_chr == pc)))
  }
  note_v_chr <- paste0(
    educ_note_common_chr,
    if (v == "within") paste0(
      " Thirds shift as education rises: the top third held ",
      round(100 * third_shift_num[["top_somecoll_start"]]), " percent of the some-college group in ",
      window_years_int[1], " and ", round(100 * third_shift_num[["top_somecoll_mid"]]), " percent in ",
      stag_end_year_int, "; by ", max(window_years_int), " the middle third held ",
      round(100 * third_shift_num[["mid_ba_end"]]), " percent of bachelor's degree holders. Those shifts are part of ",
      "each third's growth.",
      if (nrow(dagger_df) > 0L) paste0(
        " † At or near the Census top-code: at least ", round(100 * topcode_flag_frac_num), " percent of the ",
        "workers above this percentile carry a single imputed top-coded wage, so the value tracks the imputation, not reported pay."
      ) else ""
    ) else paste0(
      " Ranks are within each sex's whole monthly distribution; tied wages share a rank. Shares are of workers with a ",
      "reported education level within 2.5 rank points of each percentile. The thirds are re-ranked each year, so as ",
      "education rises each third's typical schooling rises too; a third's share at a rank can move for that reason as ",
      "well as because of who earns what",
      if (thin_n_int > 0L) paste0(" (", thin_n_int, " endpoint windows include a month with under ",
                                  thin_cell_n_int, " records in a band)") else "",
      "."
    )
  )

  educ_plot <- ggplot2::ggplot(educ_plot_df, ggplot2::aes(x = x_num, y = plot_y_num)) +
    ggplot2::geom_hline(yintercept = 0, color = tick_color_chr, linewidth = 0.3) +
    ggplot2::geom_segment(
      data = educ_gap_df,
      ggplot2::aes(x = x_num, xend = x_num, y = Men, yend = Women),
      inherit.aes = FALSE, color = gap_rule_color_chr, linewidth = 1.6, lineend = "butt"
    ) +
    ggplot2::geom_line(ggplot2::aes(color = sex_chr, group = sex_chr), linewidth = 0.6) +
    ggplot2::geom_point(ggplot2::aes(color = sex_chr, shape = sex_chr), size = 1.7, fill = "white", stroke = 0.85) +
    ggplot2::geom_text(
      data = dagger_df, ggplot2::aes(label = "†", color = sex_chr),
      nudge_x = 3.2, vjust = 0.2, family = eig_font_body_chr, fontface = "bold", size = label_pt_num / ggplot2::.pt
    ) +
    ggplot2::geom_text(
      data = educ_label_df,
      ggplot2::aes(y = label_y_num, label = sex_chr, color = sex_chr, vjust = vjust_num),
      family = eig_font_body_chr, fontface = "bold", size = label_pt_num / ggplot2::.pt
    ) +
    ggplot2::facet_grid(rows = ggplot2::vars(third_f), cols = ggplot2::vars(facet_chr)) +
    ggplot2::scale_color_manual(values = c(Women = women_color_chr, Men = men_color_chr), guide = "none") +
    ggplot2::scale_shape_manual(values = c(Women = 21, Men = 22), guide = "none") +
    ggplot2::scale_x_continuous(
      breaks = unname(pct_position_num), labels = pct_tick_chr,
      limits = c(4, 96), expand = ggplot2::expansion(0)
    ) +
    ggplot2::scale_y_continuous(
      limits = c(y_lo_num, y_hi_num), breaks = y_breaks_num,
      labels = spec$y_label_fun,
      expand = ggplot2::expansion(mult = c(0.02, 0.02))
    ) +
    ggplot2::labs(
      title    = stringr::str_wrap(spec$title_chr, 80),
      subtitle = stringr::str_wrap(spec$subtitle_chr, 92),
      x        = spec$x_title_chr,
      y        = NULL,
      caption  = paste0(stringr::str_wrap(note_v_chr, 118), "\n", stringr::str_wrap(source_line_chr, 118))
    ) +
    fig_theme +
    ggplot2::theme(
      strip.text.y.right = ggplot2::element_text(size = strip_pt_num, color = text_color_chr, angle = 0,
                                                 hjust = 0, lineheight = 1.1, margin = ggplot2::margin(l = 6)),
      panel.spacing.y    = grid::unit(0.18, "in")
    )

  ggplot2::ggsave(educ_fig_png_chr[[v]], educ_plot, width = fig_width_in_num, height = 7.6,
                  dpi = fig_dpi_int, device = eig_png_device, bg = "white")
  message("figure_h_sex_gap_eras.R -- wrote ", educ_levels_csv_chr[[v]], " and ", educ_fig_png_chr[[v]])
}

###################################
###   11) Era-by-era tables     ###
###################################
# Men's and women's wages at the first and last month of each era, for
# the whole within-sex distribution (group "all") and within each
# education third (the Figure 8b construction): dollar and percent
# change, annualized change, the growth gap, and the pay gap. Reuses the
# endpoint levels of steps 3 and 9, which already cover every era month.

era_csv_chr <- fs::path(tbl_dir_chr, "figure_h_sex_gap_by_era.csv")

era_endpoint_df <- dplyr::bind_rows(
  endpoint_df |> dplyr::transmute(group_chr = "all", end_idx_int, sex_chr, percentile_chr, level_num),
  educ_endpoint_df |>
    dplyr::filter(view_chr == "within") |>
    dplyr::transmute(group_chr = third_chr, end_idx_int, sex_chr, percentile_chr, level_num)
)

era_long_df <- era_periods_df |>
  dplyr::left_join(era_endpoint_df |> dplyr::rename(start_idx_int = end_idx_int, start_level_num = level_num),
                   by = "start_idx_int", relationship = "one-to-many") |>
  dplyr::left_join(era_endpoint_df |> dplyr::rename(end_level_num = level_num),
                   by = c("end_idx_int", "group_chr", "sex_chr", "percentile_chr")) |>
  dplyr::mutate(
    change_usd_num     = end_level_num - start_level_num,
    growth_pct_num     = 100 * (end_level_num / start_level_num - 1),
    annualized_pct_num = 100 * ((end_level_num / start_level_num)^(1 / years_num) - 1)
  )

if (anyNA(era_long_df$growth_pct_num)) {
  stop("figure_h_sex_gap_eras.R -- an era endpoint level is missing.")
}

# Cross-check the whole-distribution era growth against the by-sex index
# workbook (step 6), when it was read.
if (exists("index_long_df")) {
  era_check_df <- era_long_df |>
    dplyr::filter(group_chr == "all") |>
    dplyr::left_join(index_long_df |> dplyr::rename(start_idx_int = month_idx_int, start_index_num = index_num),
                     by = c("start_idx_int", "sex_chr", "percentile_chr")) |>
    dplyr::left_join(index_long_df |> dplyr::rename(end_idx_int = month_idx_int, end_index_num = index_num),
                     by = c("end_idx_int", "sex_chr", "percentile_chr")) |>
    dplyr::mutate(diff_pts_num = growth_pct_num - 100 * (end_index_num / start_index_num - 1))
  if (anyNA(era_check_df$diff_pts_num) || any(abs(era_check_df$diff_pts_num) > check_tol_pts_num)) {
    stop("figure_h_sex_gap_eras.R -- era growth disagrees with the by-sex index workbook.")
  }
  message("figure_h_sex_gap_eras.R -- era growth matches the by-sex index workbook (max diff ",
          signif(max(abs(era_check_df$diff_pts_num)), 2), " pts).")
}

era_table_df <- era_long_df |>
  dplyr::select(era_slug_chr, era_label_chr, period_label_chr, years_num, group_chr, percentile_chr, sex_chr,
                start_level_num, end_level_num, change_usd_num, growth_pct_num, annualized_pct_num) |>
  tidyr::pivot_wider(names_from = sex_chr,
                     values_from = c(start_level_num, end_level_num, change_usd_num, growth_pct_num, annualized_pct_num)) |>
  dplyr::mutate(
    growth_gap_pts_num     = growth_pct_num_Women - growth_pct_num_Men,
    annualized_gap_pts_num = annualized_pct_num_Women - annualized_pct_num_Men,
    start_gap_usd_num      = start_level_num_Men - start_level_num_Women,
    end_gap_usd_num        = end_level_num_Men   - end_level_num_Women,
    start_ratio_pct_num    = 100 * start_level_num_Women / start_level_num_Men,
    end_ratio_pct_num      = 100 * end_level_num_Women   / end_level_num_Men
  ) |>
  dplyr::left_join(topcode_period_note_df, by = c(era_slug_chr = "key_chr", "group_chr", "percentile_chr")) |>
  dplyr::arrange(factor(era_slug_chr, era_periods_df$era_slug_chr),
                 factor(group_chr, c("all", third_keys_chr)), factor(percentile_chr, percentile_keys_chr))

readr::write_csv(era_table_df, era_csv_chr)

message("\n== By era (all = whole within-sex distribution; thirds as in Figure 8b) ==")
print(era_table_df |>
  dplyr::transmute(
    era = era_slug_chr, grp = group_chr, pct = percentile_chr,
    m0 = round(start_level_num_Men, 2), m1 = round(end_level_num_Men, 2), m_pct = round(growth_pct_num_Men, 1),
    w0 = round(start_level_num_Women, 2), w1 = round(end_level_num_Women, 2), w_pct = round(growth_pct_num_Women, 1),
    gap_pts = round(growth_gap_pts_num, 1), ratio0 = round(start_ratio_pct_num, 1), ratio1 = round(end_ratio_pct_num, 1)
  ), n = Inf, width = Inf)
message("figure_h_sex_gap_eras.R -- wrote ", era_csv_chr)
