# =============================================================================
#  ROBUSTNESS TEST -- smoothing-window sensitivity for the wage-percentile
#  figures. Compares three trailing smoothers of the monthly weighted
#  percentiles and diagnoses whether the month-to-month "bumpiness" is
#  seasonal or sampling noise:
#
#    (1) 6-month flat rolling mean      <- pre-decision-07 smoother
#    (2) 12-month flat rolling mean     <- CURRENT PRODUCTION SMOOTHER
#                                          (decision 08; deseasonalizing,
#                                          equally weighted, adaptive to
#                                          missing months)
#    (3) 12-month geometric EWMA        <- decision 07 smoother, now
#                                          superseded; retained here as the
#                                          rejected recency-weighted
#                                          alternative (weights ratio^k,
#                                          k = months back)
#
#  All three are kept deliberately: the three-way comparison is the shared
#  evidence base for decision 07 (which chose the EWMA) and decision 08
#  (which reversed to the flat 12-month mean). Do not prune the losing
#  branches -- they are what makes either decision auditable.
#
#  This is an EXPLORATORY ROBUSTNESS CHECK. It is NOT part of the production
#  pipeline (code/run_all.R) and writes nothing the figures depend on. It only
#  reads the raw monthly percentiles the pipeline already produced
#  (output/tables/figure_a_percentiles_level_monthly.csv) and writes diagnostics
#  and comparison figures under output/robustness/.
#
#  Author - Ben Glasner
#  research title - EIG Wage Figure Explain Everything
# =============================================================================

rm(list = ls())
options(scipen = 999)
set.seed(42)

source(here::here("code", "_utils", "00_packages.R"))
source(here::here("code", "_utils", "load_palette.R"))
source(here::here("code", "_utils", "eig_fonts.R"))

###################################
###   Configuration             ###
###################################

level_monthly_csv_chr <- here::here(
  "output", "tables", "figure_a_percentiles_level_monthly.csv"
)
out_dir_chr <- here::here("output", "robustness")
fs::dir_create(out_dir_chr, recurse = TRUE)

percentile_levels_chr <- c("p10", "p25", "p50", "p75", "p90")
percentile_labels_chr <- c(
  p10 = "10th", p25 = "25th", p50 = "Median", p75 = "75th", p90 = "90th"
)
percentile_colors_chr <- c(
  p10 = unname(eig_palette_2022_primary["eig_purple_800"]),
  p25 = unname(eig_palette_2022_primary["eig_blue_200"]),
  p50 = unname(eig_palette_2022_primary["eig_blue_800"]),
  p75 = unname(eig_palette_2022_primary["eig_tan_500"]),
  p90 = unname(eig_palette_2022_primary["eig_gold_600"])
)

# Geometric EWMA decay for the comparison branch only (decision 07's setting;
# no longer used in production). Weight on the month k periods back is
# ewma_ratio^k, so ratio < 1 up-weights recent months. Reported half-life below.
ewma_ratio_num <- 0.85
ewma_halflife_num <- log(0.5) / log(ewma_ratio_num)

if (!fs::file_exists(level_monthly_csv_chr)) {
  stop(
    "robustness_smoothing_window.R -- raw monthly percentiles not found at ",
    level_monthly_csv_chr, ". Run figure_a_percentiles.R first."
  )
}

###################################
###   1) Load raw monthly series #
###################################
# Calendar-complete monthly grid of weighted percentiles (Dec 2025 dollars);
# missing months (e.g. Oct 2025) are NA rows.

raw_wide_df <- readr::read_csv(level_monthly_csv_chr, show_col_types = FALSE) |>
  dplyr::arrange(year_int, month_int) |>
  dplyr::mutate(
    date_dt  = as.Date(date_dt),
    month_int = as.integer(month_int),
    t_index_int = dplyr::row_number()
  )

message(
  "robustness_smoothing_window.R -- loaded ", nrow(raw_wide_df),
  " monthly rows (", format(min(raw_wide_df$date_dt)), " to ",
  format(max(raw_wide_df$date_dt)), "); EWMA ratio ", ewma_ratio_num,
  " (half-life ", round(ewma_halflife_num, 2), " months)."
)

###################################
###   2) Seasonality diagnostics #
###################################
# For each percentile: STL decomposition (seasonal strength and peak-to-trough
# seasonal amplitude as a share of the mean), a month-dummy F-test on the
# STL-detrended series, and lag-12 autocorrelation of the first difference.
# Internal NA months are linearly interpolated only for these ts diagnostics.

diag_rows_list <- lapply(percentile_levels_chr, function(p_chr) {
  y_num      <- raw_wide_df[[p_chr]]
  y_fill_num <- zoo::na.approx(y_num, na.rm = FALSE)
  y_fill_num <- zoo::na.locf(y_fill_num, na.rm = FALSE)
  y_fill_num <- zoo::na.locf(y_fill_num, fromLast = TRUE, na.rm = FALSE)

  ts_y <- stats::ts(
    y_fill_num, frequency = 12L,
    start = c(raw_wide_df$year_int[1], raw_wide_df$month_int[1])
  )
  stl_fit  <- stats::stl(ts_y, s.window = "periodic")
  comp_mat <- stl_fit$time.series
  seas_num <- as.numeric(comp_mat[, "seasonal"])
  rem_num  <- as.numeric(comp_mat[, "remainder"])
  trend_num <- as.numeric(comp_mat[, "trend"])

  seasonal_strength_num <- max(
    0, 1 - stats::var(rem_num) / stats::var(seas_num + rem_num)
  )
  seasonal_amp_pct_num <- (max(seas_num) - min(seas_num)) /
    mean(y_fill_num) * 100

  detrended_num <- y_fill_num - trend_num
  month_fit    <- stats::lm(detrended_num ~ factor(raw_wide_df$month_int))
  f_stat       <- summary(month_fit)$fstatistic
  month_pval_num <- if (!is.null(f_stat)) {
    stats::pf(f_stat[1L], f_stat[2L], f_stat[3L], lower.tail = FALSE)
  } else {
    NA_real_
  }

  acf_obj <- stats::acf(diff(y_fill_num), plot = FALSE, lag.max = 12L)
  acf12_num <- as.numeric(acf_obj$acf[13L])

  data.frame(
    percentile         = percentile_labels_chr[[p_chr]],
    seasonal_strength  = round(seasonal_strength_num, 3),
    seasonal_amp_pct   = round(seasonal_amp_pct_num, 2),
    month_F_pvalue     = signif(month_pval_num, 3),
    acf_lag12_of_diff  = round(acf12_num, 3),
    stringsAsFactors   = FALSE
  )
})

seasonality_diag_df <- do.call(rbind, diag_rows_list)

message("robustness_smoothing_window.R -- seasonality diagnostics:")
print(seasonality_diag_df, row.names = FALSE)

# Verdict heuristic: seasonal strength is on a 0-1 scale; < ~0.1 is negligible.
# This diagnostic measures how much seasonality there is to remove; it is NOT
# the deciding test for the smoother. Production uses the flat 12-month mean
# (decision 08) on interpretability and equal-weighting grounds regardless of
# what this reports -- clean deseasonalization is a bonus, not the reason.
max_strength_num <- max(seasonality_diag_df$seasonal_strength)
seasonality_verdict_chr <- if (max_strength_num < 0.10) {
  "NEGLIGIBLE seasonality -- bumpiness is essentially sampling noise."
} else if (max_strength_num < 0.30) {
  "WEAK seasonality -- some annual structure, mostly sampling noise."
} else {
  "MATERIAL seasonality -- the flat 12-month mean's zero at the seasonal frequency is doing real work here."
}
message("robustness_smoothing_window.R -- verdict: ", seasonality_verdict_chr,
        " (max STL seasonal strength = ", round(max_strength_num, 3), ")")

readr::write_csv(
  seasonality_diag_df,
  fs::path(out_dir_chr, "seasonality_diagnostics.csv")
)

###################################
###   3) Three smoothers         #
###################################
# Trailing windows (align right), partial windows allowed at series start,
# NA months skipped. EWMA weights the most recent month by ratio^0 = 1 and the
# oldest in-window month by ratio^(n-1). Anonymous FUNs only (no named helpers),
# matching the production convention in figure_a_percentiles.R.

smoothed_long_df <- lapply(percentile_levels_chr, function(p_chr) {
  y_num <- raw_wide_df[[p_chr]]

  flat6_num <- zoo::rollapplyr(
    y_num, width = 6L,
    FUN = function(v) if (all(is.na(v))) NA_real_ else mean(v, na.rm = TRUE),
    fill = NA_real_, partial = TRUE
  )
  flat12_num <- zoo::rollapplyr(
    y_num, width = 12L,
    FUN = function(v) if (all(is.na(v))) NA_real_ else mean(v, na.rm = TRUE),
    fill = NA_real_, partial = TRUE
  )
  ewma12_num <- zoo::rollapplyr(
    y_num, width = 12L,
    FUN = function(v) {
      n_int  <- length(v)
      w_num  <- ewma_ratio_num^((n_int - 1L):0L)
      w_num[is.na(v)] <- 0
      if (sum(w_num) == 0) NA_real_ else sum(w_num * v, na.rm = TRUE) / sum(w_num)
    },
    fill = NA_real_, partial = TRUE
  )

  dplyr::bind_rows(
    data.frame(date_dt = raw_wide_df$date_dt, percentile_chr = p_chr,
               method_chr = "6-month flat (pre-2026-07-11)", value_num = flat6_num),
    data.frame(date_dt = raw_wide_df$date_dt, percentile_chr = p_chr,
               method_chr = "12-month flat (production)", value_num = flat12_num),
    data.frame(date_dt = raw_wide_df$date_dt, percentile_chr = p_chr,
               method_chr = "12-month EWMA (superseded)", value_num = ewma12_num)
  )
}) |>
  dplyr::bind_rows()

method_levels_chr <- c("6-month flat (pre-2026-07-11)", "12-month flat (production)",
                       "12-month EWMA (superseded)")

###################################
###   4) Index + comparison plot #
###################################
# Reproduce the two chart contexts and index each smoother to 100 at its own
# anchor month, so smoothness and lag are compared on equal footing.
#   Long window:  full panel, anchor December 1982.
#   Short window: January 2024 to latest, anchor January 2024.

# Helper values only (no functions): anchor dates.
anchor_long_dt  <- as.Date("1982-12-01")
anchor_short_dt <- as.Date("2024-01-01")
short_start_dt  <- as.Date("2024-01-01")

index_and_plot_df <- smoothed_long_df |>
  dplyr::mutate(
    percentile_fct = factor(
      percentile_chr, levels = percentile_levels_chr,
      labels = percentile_labels_chr[percentile_levels_chr]
    ),
    method_fct = factor(method_chr, levels = method_levels_chr)
  )

# Long-window indexed frame.
anchor_long_vals_df <- index_and_plot_df |>
  dplyr::filter(date_dt == anchor_long_dt) |>
  dplyr::select(percentile_chr, method_chr, anchor_num = value_num)

long_plot_df <- index_and_plot_df |>
  dplyr::left_join(anchor_long_vals_df, by = c("percentile_chr", "method_chr")) |>
  dplyr::mutate(index_num = dplyr::if_else(
    !is.na(anchor_num) & anchor_num > 0, 100 * value_num / anchor_num, NA_real_
  ))

# Short-window indexed frame (re-anchored to Jan 2024, filtered to the window).
anchor_short_vals_df <- index_and_plot_df |>
  dplyr::filter(date_dt == anchor_short_dt) |>
  dplyr::select(percentile_chr, method_chr, anchor_num = value_num)

short_plot_df <- index_and_plot_df |>
  dplyr::filter(date_dt >= short_start_dt) |>
  dplyr::left_join(anchor_short_vals_df, by = c("percentile_chr", "method_chr")) |>
  dplyr::mutate(index_num = dplyr::if_else(
    !is.na(anchor_num) & anchor_num > 0, 100 * value_num / anchor_num, NA_real_
  ))

# Shared plot scaffold, faceted by smoother.
smoothing_theme <- ggplot2::theme_minimal(
  base_size = 11, base_family = eig_font_body_chr
) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major.x = ggplot2::element_blank(),
    axis.line = ggplot2::element_line(linewidth = 0.3),
    legend.position = "right",
    plot.title = ggplot2::element_text(face = "bold",
                                       family = eig_font_title_chr),
    strip.text = ggplot2::element_text(face = "bold")
  )

long_plot <- ggplot2::ggplot(
  long_plot_df,
  ggplot2::aes(date_dt, index_num, color = percentile_fct)
) +
  ggplot2::geom_hline(yintercept = 100, linetype = "dashed",
                      linewidth = 0.3, color = "#777777") +
  ggplot2::geom_line(linewidth = 0.6, na.rm = TRUE) +
  ggplot2::facet_wrap(~ method_fct, ncol = 3L) +
  ggplot2::scale_color_manual(
    values = stats::setNames(percentile_colors_chr,
                             percentile_labels_chr[percentile_levels_chr]),
    name = "Percentile"
  ) +
  ggplot2::scale_x_date(date_breaks = "8 years", date_labels = "%Y") +
  ggplot2::labs(
    title = "Robustness: smoothing-window comparison, full panel (indexed to December 1982 = 100)",
    subtitle = paste0(
      "Monthly weighted real-wage percentiles under three trailing smoothers. ",
      "EWMA ratio ", ewma_ratio_num, " (half-life ",
      round(ewma_halflife_num, 1), " months)."
    ),
    x = NULL, y = "Index (Dec 1982 = 100)"
  ) +
  smoothing_theme

short_plot <- ggplot2::ggplot(
  short_plot_df,
  ggplot2::aes(date_dt, index_num, color = percentile_fct)
) +
  ggplot2::geom_hline(yintercept = 100, linetype = "dashed",
                      linewidth = 0.3, color = "#777777") +
  ggplot2::geom_line(linewidth = 0.7, na.rm = TRUE) +
  ggplot2::facet_wrap(~ method_fct, ncol = 3L) +
  ggplot2::scale_color_manual(
    values = stats::setNames(percentile_colors_chr,
                             percentile_labels_chr[percentile_levels_chr]),
    name = "Percentile"
  ) +
  ggplot2::scale_x_date(date_breaks = "6 months", date_labels = "%b %Y") +
  ggplot2::labs(
    title = "Robustness: smoothing-window comparison, January 2024 onward (indexed to January 2024 = 100)",
    subtitle = paste0(
      "Short-window view -- shows how each smoother handles recent dynamics. ",
      "EWMA ratio ", ewma_ratio_num, " (half-life ",
      round(ewma_halflife_num, 1), " months)."
    ),
    x = NULL, y = "Index (Jan 2024 = 100)"
  ) +
  smoothing_theme +
  ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))

long_png_chr  <- fs::path(out_dir_chr, "robustness_smoothing_fullpanel.png")
short_png_chr <- fs::path(out_dir_chr, "robustness_smoothing_uncertainty.png")

ggplot2::ggsave(long_png_chr, long_plot, width = 12.0, height = 5.0,
                units = "in", dpi = 200L, device = eig_png_device)
ggplot2::ggsave(short_png_chr, short_plot, width = 12.0, height = 5.0,
                units = "in", dpi = 200L, device = eig_png_device)

###################################
###   5) Verify + report         #
###################################

for (path_chr in c(
  fs::path(out_dir_chr, "seasonality_diagnostics.csv"),
  long_png_chr, short_png_chr
)) {
  if (!fs::file_exists(path_chr)) {
    stop("robustness_smoothing_window.R -- output not written: ", path_chr)
  }
}

message("robustness_smoothing_window.R -- wrote diagnostics CSV and 2 ",
        "comparison PNGs to ", out_dir_chr)
message("robustness_smoothing_window.R -- done.")
