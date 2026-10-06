# 12_covid_composition_diagnostic -- measure the COVID-19 workforce-composition effect on real wage percentiles by reweighting to fixed pre-COVID composition
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

rm(list = ls())
options(scipen = 999)
set.seed(42)

# Sourced by run_all.R inside new.env(parent = globalenv()).
#
# Evidence base for Decision 10 (docs/decisions/decision_10_covid_
# composition_anchor.md): the COVID-19 aftermath chart is indexed to January
# 2022 because that is when the composition effect measured here had
# largely cleared.
#
# Method (reweighting, in the spirit of DiNardo, Fortin, and Lemieux 1996):
#   1) For each survey month, rake EARNWT so the weighted shares of four
#      worker characteristics match their pooled reference-year (2019)
#      shares: occupation major group (22 groups, OCC2010), education
#      (4 bins), age (6 bins), and sex. Raking matches the four marginals,
#      not their joint distribution.
#   2) Recompute the five weighted percentiles with the raked weights
#      ("composition-fixed") alongside the actual percentiles, using the
#      shared weighted_quantile() (Stata `_pctile` / EPI convention).
#   3) Composition gap = 100 * log(actual / composition-fixed), in log
#      points. It drifts upward before COVID because the workforce was
#      already shifting toward higher-paid occupations and more education,
#      so the COVID effect is the EXCESS over a linear trend fitted to the
#      pre-COVID months (fit window below).
#   4) Excess is smoothed with the Decision 08 12-month flat trailing
#      window, matching the charts: an indexed chart's anchor is a 12-month
#      rolling average, so the question is how much composition effect that
#      rolling base carries.
#   5) The noise band is the largest absolute rolling excess inside the fit
#      window (after its first 12 months, so every window is full).
#
# Limits: observables only. Composition shifts WITHIN a cell (e.g., the
# lowest-paid workers in an occupation losing their jobs) are not captured,
# so this is a lower bound on the true composition effect. Wage heaping at
# round dollar values makes the monthly gap step-shaped; the 12-month mean
# is the series to read.
#
# Outputs:
#   output/tables/diagnostics/covid_composition_gap_monthly.csv
#   output/figures/diagnostics/covid_composition_gap.png
#
# No custom functions are defined; all transformations are inline.

source(here::here("code", "_utils", "00_packages.R"))
source(here::here("code", "_utils", "load_palette.R"))
source(here::here("code", "_utils", "eig_fonts.R"))

###################################
###   Configuration             ###
###################################

panel_in_dir_chr <- here::here("data", "intermediate", "cps_real_wages")
tbl_out_dir_chr  <- here::here("output", "tables", "diagnostics")
fig_out_dir_chr  <- here::here("output", "figures", "diagnostics")
out_csv_chr      <- fs::path(tbl_out_dir_chr, "covid_composition_gap_monthly.csv")
out_png_chr      <- fs::path(fig_out_dir_chr, "covid_composition_gap.png")

fs::dir_create(tbl_out_dir_chr, recurse = TRUE)
fs::dir_create(fig_out_dir_chr, recurse = TRUE)

first_year_int     <- 2016L  # start of the pre-COVID trend-fit window
reference_year_int <- 2019L  # composition held fixed at pooled 2019 shares
fit_end_year_int   <- 2019L  # trend fit window: first_year_int..fit_end_year_int
rolling_window_int <- 12L    # Decision 08 smoother
raking_iter_int    <- 25L

# Chosen anchor for the COVID-19 aftermath chart (Decision 10) and the
# rolling-base month it replaced, reported side by side in the log.
anchor_idx_int   <- as.integer(2022L * 12L + 1L - 1L)  # January 2022
prior_anchor_idx_int <- as.integer(2021L * 12L + 1L - 1L)  # January 2021

percentile_keys_chr  <- c("p10", "p25", "p50", "p75", "p90")
percentile_probs_num <- c(0.10, 0.25, 0.50, 0.75, 0.90)

# OCC2010 major groups: upper bounds of the 2010 Census occupation code
# ranges, verified against the cps_00586 DDI labels (management 10-430
# through transportation and material moving 9000-9750). 9800+ is
# military / NIU and is excluded.
occ_breaks_num <- c(-Inf, 499, 999, 1299, 1599, 1999, 2099, 2199, 2599, 2999,
                    3599, 3699, 3999, 4199, 4299, 4699, 4999, 5999, 6199,
                    6999, 7699, 8999, 9799)

###################################
###   1) Load the wage panel    ###
###################################

parquet_paths_chr <- fs::dir_ls(
  panel_in_dir_chr, regexp = "part-0\\.parquet$", recurse = TRUE, type = "file"
)
year_of_path_int <- as.integer(sub(".*year=(\\d{4}).*", "\\1", parquet_paths_chr))
parquet_paths_chr <- parquet_paths_chr[year_of_path_int >= first_year_int]

if (length(parquet_paths_chr) == 0L) {
  stop(
    "12_covid_composition_diagnostic.R -- no panel partitions from ",
    first_year_int, " under ", panel_in_dir_chr, ". Run 02a_build_real_wages.R first."
  )
}

panel_df <- dplyr::bind_rows(lapply(parquet_paths_chr, \(p) {
  arrow::read_parquet(
    p,
    col_select = c("YEAR", "MONTH", "EARNWT", "AGE", "SEX", "EDUC", "OCC2010",
                   "real_hourly_wage_num")
  )
})) |>
  dplyr::mutate(dplyr::across(c(YEAR, MONTH, AGE, SEX, EDUC, OCC2010), as.integer)) |>
  dplyr::filter(!is.na(real_hourly_wage_num), !is.na(EARNWT), EARNWT > 0)

n_loaded_int <- nrow(panel_df)

# Education bins match figure_f_era_bars_tables.R: floor(EDUC / 10) of
# 0-6 less than HS, 7 HS, 8-10 some college, 11+ bachelor's or higher;
# EDUC 000/001 (NIU) and 999 (missing) are not valid bins.
panel_df <- panel_df |>
  dplyr::mutate(
    occ_grp_int  = as.integer(cut(OCC2010, c(occ_breaks_num, Inf))),
    educ_bin_int = dplyr::case_when(
      is.na(EDUC) | EDUC < 2L | EDUC >= 999L ~ NA_integer_,
      EDUC %/% 10L <= 6L                     ~ 1L,
      EDUC %/% 10L == 7L                     ~ 2L,
      EDUC %/% 10L <= 10L                    ~ 3L,
      TRUE                                   ~ 4L
    ),
    age_bin_int   = as.integer(cut(AGE, c(15, 24, 34, 44, 54, 64, Inf))),
    sex_int       = SEX,
    month_idx_int = YEAR * 12L + MONTH - 1L
  ) |>
  dplyr::filter(
    !is.na(OCC2010), OCC2010 < 9800L, !is.na(occ_grp_int),
    !is.na(educ_bin_int), !is.na(age_bin_int), sex_int %in% c(1L, 2L)
  )

message(
  "12_covid_composition_diagnostic.R -- ", format(nrow(panel_df), big.mark = ","),
  " of ", format(n_loaded_int, big.mark = ","), " wage records from ",
  first_year_int, " have a valid occupation group, education bin, age bin, and sex"
)

###################################
###   2) Reference shares       ###
###################################

dims_chr <- c("occ_grp_int", "educ_bin_int", "age_bin_int", "sex_int")

reference_df <- panel_df |> dplyr::filter(YEAR == reference_year_int)
target_shares_ls <- lapply(dims_chr, \(d) {
  s <- tapply(reference_df$EARNWT, reference_df[[d]], sum)
  s / sum(s)
})
names(target_shares_ls) <- dims_chr

###################################
###   3) Rake and recompute     ###
###################################

month_idx_vec_int <- sort(unique(panel_df$month_idx_int))
gap_rows_ls <- vector("list", length(month_idx_vec_int))

for (k in seq_along(month_idx_vec_int)) {
  month_df <- panel_df[panel_df$month_idx_int == month_idx_vec_int[k], ]
  w_num <- month_df$EARNWT

  for (it in seq_len(raking_iter_int)) {
    for (d in dims_chr) {
      cur_num <- tapply(w_num, month_df[[d]], sum)
      cur_num <- cur_num / sum(cur_num)
      adj_num <- target_shares_ls[[d]][names(cur_num)] / cur_num
      # A category present this month but absent in the reference year
      # keeps its weight rather than being zeroed.
      adj_num[is.na(adj_num)] <- 1
      w_num <- w_num * adj_num[as.character(month_df[[d]])]
    }
  }

  gap_rows_ls[[k]] <- tibble::tibble(
    month_idx_int = month_idx_vec_int[k],
    percentile_chr = percentile_keys_chr,
    actual_num = weighted_quantile(month_df$real_hourly_wage_num, month_df$EARNWT, percentile_probs_num),
    fixed_num  = weighted_quantile(month_df$real_hourly_wage_num, w_num,          percentile_probs_num)
  )
}

gap_df <- dplyr::bind_rows(gap_rows_ls) |>
  dplyr::mutate(
    year_int  = as.integer(month_idx_int %/% 12L),
    month_int = as.integer(month_idx_int %% 12L + 1L),
    date_dt   = as.Date(sprintf("%04d-%02d-01", year_int, month_int)),
    gap_lp_num = 100 * log(actual_num / fixed_num)
  )

###################################
###   4) Detrend and smooth     ###
###################################

gap_df <- gap_df |>
  dplyr::group_by(percentile_chr) |>
  dplyr::arrange(month_idx_int, .by_group = TRUE) |>
  dplyr::mutate(
    in_fit_bool = year_int <= fit_end_year_int,
    trend_lp_num = stats::predict(
      stats::lm(gap_lp_num ~ month_idx_int, subset = in_fit_bool),
      newdata = data.frame(month_idx_int = month_idx_int)
    ),
    excess_lp_num = gap_lp_num - trend_lp_num,
    # Calendar-based [t-11, t] window; missing months (October 2025) drop out.
    excess_roll12_lp_num = vapply(
      month_idx_int,
      \(m) mean(excess_lp_num[month_idx_int >= m - (rolling_window_int - 1L) & month_idx_int <= m]),
      numeric(1)
    ),
    band_lp_num = max(abs(excess_roll12_lp_num[
      in_fit_bool & month_idx_int >= min(month_idx_int) + (rolling_window_int - 1L)
    ])),
    trend_slope_lp_per_yr_num = 12 * unname(stats::coef(
      stats::lm(gap_lp_num ~ month_idx_int, subset = in_fit_bool)
    )[2])
  ) |>
  dplyr::ungroup()

###################################
###   5) Summarize the anchor   ###
###################################

peak_df <- gap_df |>
  dplyr::filter(year_int >= 2020L) |>
  dplyr::group_by(percentile_chr) |>
  dplyr::slice_max(excess_roll12_lp_num, n = 1L, with_ties = FALSE) |>
  dplyr::ungroup() |>
  dplyr::select(percentile_chr, peak_date_dt = date_dt, peak_num = excess_roll12_lp_num)

anchor_summary_df <- gap_df |>
  dplyr::filter(month_idx_int %in% c(prior_anchor_idx_int, anchor_idx_int)) |>
  dplyr::select(percentile_chr, month_idx_int, excess_roll12_lp_num, band_lp_num) |>
  tidyr::pivot_wider(
    names_from = month_idx_int, values_from = excess_roll12_lp_num,
    names_prefix = "excess_"
  ) |>
  dplyr::left_join(peak_df, by = "percentile_chr")
names(anchor_summary_df) <- sub(paste0("excess_", prior_anchor_idx_int), "excess_jan2021", names(anchor_summary_df))
names(anchor_summary_df) <- sub(paste0("excess_", anchor_idx_int), "excess_jan2022", names(anchor_summary_df))

message(
  "12_covid_composition_diagnostic.R -- 12-month rolling excess composition gap ",
  "(log points; peak / Jan 2021 / Jan 2022; pre-COVID band): ",
  paste0(
    anchor_summary_df$percentile_chr, " ",
    sprintf("%.1f", anchor_summary_df$peak_num), " / ",
    sprintf("%.1f", anchor_summary_df$excess_jan2021), " / ",
    sprintf("%.1f", anchor_summary_df$excess_jan2022), " (+/-",
    sprintf("%.1f", anchor_summary_df$band_lp_num), ")",
    collapse = "; "
  )
)

# Decision 10 guard: the January 2022 anchor is justified only while the
# rolling base there has shed at least half of each percentile's peak
# composition effect. Warn (not stop) so a data update that breaks the
# rationale is flagged without halting the pipeline.
anchor_share_left_num <- anchor_summary_df$excess_jan2022 / anchor_summary_df$peak_num
if (any(anchor_share_left_num > 0.5)) {
  warning(
    "12_covid_composition_diagnostic.R -- the January 2022 anchor retains more than half ",
    "of the peak composition effect for: ",
    paste(anchor_summary_df$percentile_chr[anchor_share_left_num > 0.5], collapse = ", "),
    ". Revisit Decision 10."
  )
} else {
  message(
    "12_covid_composition_diagnostic.R -- Decision 10 guard PASS: January 2022 retains at most ",
    sprintf("%.0f", 100 * max(anchor_share_left_num)), "% of any percentile's peak effect"
  )
}

###################################
###   6) Write the table        ###
###################################

readr::write_csv(
  gap_df |>
    dplyr::select(
      year_int, month_int, date_dt, month_idx_int, percentile_chr,
      actual_num, fixed_num, gap_lp_num, trend_lp_num, excess_lp_num,
      excess_roll12_lp_num, band_lp_num, trend_slope_lp_per_yr_num
    ) |>
    dplyr::arrange(percentile_chr, month_idx_int),
  out_csv_chr
)

###################################
###   7) Plot                   ###
###################################

percentile_labels_chr <- c(p10 = "10th", p25 = "25th", p50 = "Median", p75 = "75th", p90 = "90th")
percentile_colors_chr <- c(
  "10th"   = unname(eig_palette_2022_primary["eig_purple_800"]),
  "25th"   = unname(eig_palette_2022_primary["eig_blue_200"]),
  "Median" = unname(eig_palette_2022_primary["eig_blue_800"]),
  "75th"   = unname(eig_palette_2022_primary["eig_tan_500"]),
  "90th"   = unname(eig_palette_2022_primary["eig_gold_600"])
)

plot_df <- gap_df |>
  dplyr::filter(year_int >= reference_year_int) |>
  dplyr::mutate(percentile_fct = factor(percentile_labels_chr[percentile_chr], levels = percentile_labels_chr))

anchor_dt <- as.Date(sprintf("%04d-%02d-01", anchor_idx_int %/% 12L, anchor_idx_int %% 12L + 1L))

fig_plot <- ggplot2::ggplot(plot_df, ggplot2::aes(x = date_dt, y = excess_roll12_lp_num, color = percentile_fct)) +
  ggplot2::geom_hline(yintercept = 0, linetype = "dashed", linewidth = 0.3, color = "#525252") +
  ggplot2::geom_vline(xintercept = anchor_dt, linewidth = 0.3, color = "#525252") +
  ggplot2::annotate(
    "text", x = anchor_dt, y = Inf, label = " January 2022 anchor", hjust = 0, vjust = 1.5,
    size = 3.2, color = "#525252", family = eig_font_body_chr
  ) +
  ggplot2::geom_line(linewidth = 0.7) +
  ggplot2::scale_color_manual(values = percentile_colors_chr, name = "Percentile") +
  ggplot2::scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
  ggplot2::labs(
    title    = "Figure D1. The COVID-19 composition effect had largely cleared by January 2022",
    subtitle = "Excess of actual over composition-fixed wage percentiles, 12-month rolling average, log points",
    x = NULL, y = "Log points above pre-COVID trend",
    caption = stringr::str_wrap(paste0(
      "Note: Composition-fixed percentiles rake each month's earnings weights to pooled ",
      reference_year_int, " shares of occupation major group, education, age, and sex. The ",
      "gap is measured relative to its linear ", first_year_int, "-", fit_end_year_int,
      " trend. Observable characteristics only, so this is a lower bound. Source: Author's ",
      "analysis of IPUMS-CPS Outgoing Rotation Group microdata; BEA PCE price index via FRED, ",
      format(Sys.Date(), "%Y"), "."
    ), width = 120)
  ) +
  ggplot2::theme_minimal(base_size = 11, base_family = eig_font_body_chr) +
  ggplot2::theme(
    panel.grid.major.x = ggplot2::element_blank(),
    panel.grid.minor   = ggplot2::element_blank(),
    axis.line          = ggplot2::element_line(linewidth = 0.3),
    legend.position    = "right",
    plot.title         = ggplot2::element_text(face = "bold", family = eig_font_title_chr),
    plot.caption       = ggplot2::element_text(hjust = 0)
  )

ggplot2::ggsave(
  filename = out_png_chr, plot = fig_plot,
  width = 10.0, height = 5.6, units = "in", dpi = 300L, device = eig_png_device
)

###################################
###   8) Verify outputs         ###
###################################

for (path_chr in c(out_csv_chr, out_png_chr)) {
  if (!fs::file_exists(path_chr) || fs::file_size(path_chr) == 0) {
    stop("12_covid_composition_diagnostic.R -- output not written: ", path_chr)
  }
}

message("12_covid_composition_diagnostic.R -- done. Wrote ", out_csv_chr, " and ", out_png_chr)
