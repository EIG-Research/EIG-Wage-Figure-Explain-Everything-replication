# figure_f_era_bars -- "lines over era bars" figures 6a (percentiles), 6b (wage ratios), 6c (education thirds)
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

rm(list = ls())
options(scipen = 999)
set.seed(42)

# Sourced by run_all.R inside new.env(parent = globalenv()).
#
# DRAW LAYER. Reads only the CSVs written by figure_f_era_bars_tables.R
# and never touches microdata. Each figure is ONE ggplot2/patchwork image
# with two rows on a shared date axis:
#
#   top     12-month rolling-average indexed lines (decision 08; Dec 1982
#           rolling average = 100), direct end-of-line
#           labels, era names on a rail above the data, dashed era rules,
#           dashed 100 reference line, March 2020 to December 2021 drawn
#           dashed (the figure_a_percentiles.R COVID convention)
#   bottom  within-era cumulative change bars,
#           positioned on the DATE axis:
#           each era's group is centered on the era's midpoint, every group
#           has the same width (0.95 x the shortest era), and the same
#           dashed era rules run through both rows
#
# Outputs:
#   output/figures/figure_f_era_bars_percentiles.png   (Figure 6a)
#   output/figures/figure_f_era_bars_ratios.png        (Figure 6b)
#   output/figures/figure_f_era_bars_education.png     (Figure 6c)
#
# Each PNG is rendered at its placed slide width (10.52 in, 300 dpi), so a
# font's point size is its on-slide size. The script stops rather than
# ships if any text is below the 12 pt floor, a label collides with a
# label, bar, or rule, an era name does not fit between its rules, the
# bars get less than 20 percent of their panel, or the era rules fail to
# line up between the two rows in the rendered image.
#
# Palette: 2022 primary EIG tokens via load_palette.R; fonts via
# eig_fonts.R. No custom functions are defined; the three figures are
# driven by a spec list and a for loop.

source(here::here("code", "_utils", "00_packages.R"))
source(here::here("code", "_utils", "load_palette.R"))
source(here::here("code", "_utils", "eig_fonts.R"))

###################################
###   Configuration             ###
###################################

tbl_in_dir_chr  <- here::here("output", "tables")
fig_out_dir_chr <- here::here("output", "figures")

# Rendered at the placed width, so pt on the device = pt on the slide.
placed_width_in_num <- 10.52
render_width_in_num <- 10.52
render_dpi_int      <- 300L

# Panel heights (in): line panel over bar panel, about 72 / 28.
line_panel_h_in_num <- 3.35
bar_panel_h_in_num  <- 1.30

# Font sizes (pt at render size). Legibility floor: 12 pt on the slide.
font_floor_pt_num   <- 12
title_pt_num        <- 20
subtitle_pt_num     <- 13
axis_pt_num         <- 12
rail_pt_num         <- 12
line_label_pt_num   <- 13
bar_label_pt_num    <- 12
caption_pt_num      <- 12
all_font_pt_num <- c(title_pt_num, subtitle_pt_num, axis_pt_num, rail_pt_num,
                     line_label_pt_num, bar_label_pt_num, caption_pt_num)

# Colors. Rules and rail follow the era-marking spec; grid follows
# eig-figure-style.md section 3; the 100 reference line follows
# figure_a_percentiles.R.
rule_color_chr   <- "#7A7A7A"
rail_color_chr   <- "#6B6B6B"
grid_color_chr   <- "#D9D9D9"
zero_color_chr   <- "#9AA0A6"
ref_color_chr    <- "#525252"
tick_color_chr   <- "#6B6B6B"
caption_color_chr <- "#333333"

# COVID dashed segment (figure_a_percentiles.R): March 2020 to December
# 2021 dashed, with February 2020 and January 2022 as bridge months.
covid_lead_dt <- as.Date("2020-02-01")
covid_lag_dt  <- as.Date("2022-01-01")

# Short rail names for the five eras (the long names in the era tables
# do not fit between the rules at 12 pt; era 2 keeps only "IT boom"). Era 1 carries the asterisk
# of figure_a_percentiles.R: the series begins after the stagnation did.
era_rail_labels_chr <- c(
  stagnation1     = "First long wage stagnation*",
  itboom          = "IT boom",   # "Late-1990s" alone (0.94 in) exceeds the era width at 12 pt
  stagnation2     = "Second long wage stagnation",
  recovery        = "Nascent recovery",
  covid_aftermath = "COVID-19 aftermath"
)

source_line_chr <- paste0(
  "Source: Author's analysis of IPUMS-CPS Outgoing Rotation Group microdata, ",
  "weighted by CPS earnings weights; inflation adjustment uses the U.S. Bureau ",
  "of Economic Analysis Personal Consumption Expenditures price index, via FRED."
)
note_common_chr <- paste0(
  "Lines are equally weighted, backward-looking 12-month rolling averages of monthly weighted statistics for wage and salary workers age 16 ",
  "and older; months with no data drop out of the window. Dashed lines: March 2020 to December 2021 (COVID-19 shifts in CPS ",
  "sample composition). No October 2025 CPS sample (federal shutdown). ",
  "*The era is measured from the December 1982 index base; any earlier stagnation is not shown."
)

pal_chr <- eig_palette_2022_primary

fig_specs_list <- list(
  list(
    fig_id_chr    = "6a",
    index_csv_chr = "figure_f_percentiles_indexed_roll12.csv",
    era_csv_chr   = "figure_f_percentiles_era_growth.csv",
    png_chr       = "figure_f_era_bars_percentiles.png",
    title_chr     = "Figure 6a. Wages grew at every percentile, but the top pulled away",
    subtitle_stem_chr = "Real hourly wage percentiles, 12-month rolling average, December 1982 = 100",
    subtitle_span_bool = TRUE,
    bar_note_chr  = "Bars: cumulative growth within each era (%), from the era's first month to its last. ",
    extra_note_chr = "",
    series_chr    = c("p10", "p25", "p50", "p75", "p90"),
    labels_chr    = c(p10 = "10th", p25 = "25th", p50 = "Median", p75 = "75th", p90 = "90th"),
    colors_chr    = c(p10 = pal_chr[["eig_teal_900"]], p25 = pal_chr[["eig_cyan_700"]],
                      p50 = pal_chr[["eig_blue_800"]], p75 = pal_chr[["eig_green_700"]],
                      p90 = pal_chr[["eig_gold_600"]]),
    y_limits_num  = c(88, 200),   # 196 in the AWP build; raised so P90 (peak ~182) clears the two-line era rail
    y_breaks_num  = c(100, 120, 140, 160, 180)
  ),
  list(
    fig_id_chr    = "6b",
    index_csv_chr = "figure_f_ratios_indexed_roll12.csv",
    era_csv_chr   = "figure_f_ratios_era_growth.csv",
    png_chr       = "figure_f_era_bars_ratios.png",
    title_chr     = "Figure 6b. The bottom closed on the middle while the top pulled away from both",
    subtitle_stem_chr = "Wage ratios, 12-month rolling average, December 1982 = 100",
    subtitle_span_bool = TRUE,
    bar_note_chr  = "Bars: cumulative change in each ratio within each era (%), from the era's first month to its last; 50/10 and 90/50 changes compound to the 90/10 change. ",
    extra_note_chr = "",
    series_chr    = c("r50_10", "r90_50", "r90_10"),
    labels_chr    = c(r50_10 = "50/10", r90_50 = "90/50", r90_10 = "90/10"),
    colors_chr    = c(r50_10 = pal_chr[["eig_green_700"]], r90_50 = pal_chr[["eig_gold_600"]],
                      r90_10 = pal_chr[["eig_blue_800"]]),
    y_limits_num  = c(88, 146),
    y_breaks_num  = c(90, 100, 110, 120, 130)
  ),
  list(
    fig_id_chr    = "6c",
    index_csv_chr = "figure_f_education_indexed_roll12.csv",
    era_csv_chr   = "figure_f_education_era_growth.csv",
    png_chr       = "figure_f_era_bars_education.png",
    title_chr     = "Figure 6c. The most-educated third pulled away until 2014, then the rest grew faster",
    subtitle_stem_chr = "Real median wage by education third, adults 25 to 64 ranked by schooling each year; 12-month rolling average, December 1982 = 100",
    subtitle_span_bool = FALSE,   # AWP 6c subtitle carries no year span
    bar_note_chr  = "Bars: cumulative growth within each era (%), from the era's first month to its last. ",
    extra_note_chr = "Thirds rank civilians 25 to 64 by four education groups each year, splitting a group across two thirds where a cut falls inside it; the wage medians are not limited to ages 25 to 64. ",
    series_chr    = c("bottom", "middle", "top"),
    labels_chr    = c(bottom = "Least\neducated", middle = "Middle", top = "Most\neducated"),
    colors_chr    = c(bottom = pal_chr[["eig_teal_900"]], middle = pal_chr[["eig_cyan_700"]],
                      top = pal_chr[["eig_gold_600"]]),
    y_limits_num  = c(90, 190),
    y_breaks_num  = c(100, 130, 160)
  )
)

fs::dir_create(fig_out_dir_chr, recurse = TRUE)

###################################
###   0) Legibility floor       ###
###################################

placed_scale_num <- placed_width_in_num / render_width_in_num
if (any(all_font_pt_num * placed_scale_num < font_floor_pt_num)) {
  stop(
    "figure_f_era_bars.R -- a font renders below the ", font_floor_pt_num,
    " pt floor at the placed width: ",
    paste(round(all_font_pt_num * placed_scale_num, 1), collapse = ", ")
  )
}
if (!eig_fonts_registered_bool) {
  warning("figure_f_era_bars.R -- EIG brand fonts unavailable; text metrics use the 'sans' fallback.")
}

# ggplot2 text size is in mm.
mm_per_pt_num <- 1 / ggplot2::.pt

verification_list <- list()

for (fig_spec in fig_specs_list) {

  fig_id_chr <- fig_spec$fig_id_chr
  message("figure_f_era_bars.R -- building Figure ", fig_id_chr, " ...")

  ###################################
  ###   1) Read tables            ###
  ###################################

  index_path_chr <- fs::path(tbl_in_dir_chr, fig_spec$index_csv_chr)
  era_path_chr   <- fs::path(tbl_in_dir_chr, fig_spec$era_csv_chr)
  if (!all(fs::file_exists(c(index_path_chr, era_path_chr)))) {
    stop("figure_f_era_bars.R -- missing input table(s) for Figure ", fig_id_chr,
         ". Run figure_f_era_bars_tables.R first.")
  }

  index_df <- readr::read_csv(index_path_chr, show_col_types = FALSE) |>
    dplyr::mutate(date_dt = as.Date(date_dt))
  era_df <- readr::read_csv(era_path_chr, show_col_types = FALSE) |>
    dplyr::mutate(dplyr::across(dplyr::ends_with("_dt"), as.Date))

  fig_series_chr <- fig_spec$series_chr
  n_series_int <- length(fig_series_chr)

  if (!all(fig_series_chr %in% names(index_df)) || !all(fig_series_chr %in% era_df$series_chr)) {
    stop("figure_f_era_bars.R -- Figure ", fig_id_chr, " tables lack an expected series.")
  }

  first_dt <- min(index_df$date_dt)
  last_dt  <- max(index_df$date_dt)
  domain_days_num <- as.numeric(last_dt - first_dt)

  eras_df <- era_df |>
    dplyr::distinct(era_i_int, era_slug_chr, era_start_dt, era_end_dt) |>
    dplyr::arrange(era_i_int)
  if (eras_df$era_start_dt[1] < first_dt || utils::tail(eras_df$era_end_dt, 1L) != last_dt) {
    stop("figure_f_era_bars.R -- Figure ", fig_id_chr, " eras do not span the plotted domain.")
  }

  # Dashed era rules: at the first month of eras 2-5.
  rule_dates_dt <- eras_df$era_start_dt[-1]
  # Era x extent for the rail and bar groups: [start, next era's start),
  # with the last era ending at the last data month.
  eras_df$era_right_dt <- c(eras_df$era_start_dt[-1], last_dt)

  year_first_int <- as.integer(format(first_dt, "%Y"))
  year_last_int  <- as.integer(format(last_dt, "%Y"))
  subtitle_chr <- if (isTRUE(fig_spec$subtitle_span_bool)) {
    paste0(fig_spec$subtitle_stem_chr, ", ", year_first_int, " to ", year_last_int)
  } else {
    fig_spec$subtitle_stem_chr
  }
  # Title, subtitle, and caption wrapped by MEASURED width (greedy, word by
  # word, in each block's own font) so no line runs past the image edge;
  # character-count wrapping misjudges proportional text. Each block is a
  # list of paragraphs that start on new lines.
  text_limit_pt_num <- (render_width_in_num - 0.25) * 72
  text_blocks_list <- list(
    title = list(paras_chr = fig_spec$title_chr, family_chr = eig_font_title_chr,
                 size_num = title_pt_num, weight_chr = "bold"),
    subtitle = list(paras_chr = subtitle_chr, family_chr = eig_font_body_chr,
                    size_num = subtitle_pt_num, weight_chr = "normal"),
    caption = list(paras_chr = c(paste0("Note: ", fig_spec$bar_note_chr, fig_spec$extra_note_chr,
                                        note_common_chr), source_line_chr),
                   family_chr = eig_font_body_chr, size_num = caption_pt_num, weight_chr = "normal")
  )
  wrapped_chr <- character(0)
  for (block_chr in names(text_blocks_list)) {
    block_ls <- text_blocks_list[[block_chr]]
    lines_chr <- character(0)
    for (para_chr in block_ls$paras_chr) {
      current_chr <- ""
      for (word_chr in strsplit(para_chr, " ")[[1]]) {
        candidate_chr <- if (current_chr == "") word_chr else paste(current_chr, word_chr)
        if (systemfonts::string_width(candidate_chr, family = block_ls$family_chr,
                                      size = block_ls$size_num, res = 72,
                                      weight = block_ls$weight_chr) <= text_limit_pt_num) {
          current_chr <- candidate_chr
        } else {
          lines_chr <- c(lines_chr, current_chr)
          current_chr <- word_chr
        }
      }
      lines_chr <- c(lines_chr, current_chr)
    }
    wrapped_chr[[block_chr]] <- paste(lines_chr, collapse = "\n")
  }
  title_wrapped_chr <- wrapped_chr[["title"]]
  subtitle_chr      <- wrapped_chr[["subtitle"]]
  caption_chr       <- wrapped_chr[["caption"]]

  long_df <- index_df |>
    dplyr::select(date_dt, dplyr::all_of(fig_series_chr)) |>
    tidyr::pivot_longer(dplyr::all_of(fig_series_chr), names_to = "series_chr", values_to = "index_num") |>
    dplyr::mutate(series_fct = factor(series_chr, levels = fig_series_chr))

  if (min(long_df$index_num) < fig_spec$y_limits_num[1] ||
      max(long_df$index_num) > fig_spec$y_limits_num[2]) {
    stop("figure_f_era_bars.R -- Figure ", fig_id_chr, " data leave the y range ",
         paste(fig_spec$y_limits_num, collapse = "-"), ".")
  }

  ###################################
  ###   2) Measure the layout     ###
  ###################################
  # Build a skeleton of the final layout (same margins, axis text, title,
  # subtitle, caption) and measure its fixed widths and heights on a ragg
  # device, so the panel sizes in inches are known before any label is
  # placed. The panels' own content does not change these measurements.

  line_label_lines_int <- lengths(regmatches(fig_spec$labels_chr, gregexpr("\n", fig_spec$labels_chr))) + 1L
  line_label_w_pt_num <- vapply(
    strsplit(fig_spec$labels_chr, "\n"),
    \(parts) max(systemfonts::string_width(parts, family = eig_font_body_chr,
                                           size = line_label_pt_num, res = 72)),
    numeric(1L)
  )
  label_gap_in_num <- 0.08
  right_margin_pt_num <- (label_gap_in_num * 72) + max(line_label_w_pt_num) + 6

  # Y tick labels in BOTH panels are drawn as text in a fixed left margin
  # (axis.text.y blank), so the shared left edge never depends on which bar
  # ticks are finally chosen. The margin fits the widest label among the
  # line breaks and every bar tick set the coarsening step can pick.
  tick_gap_in_num <- 0.06
  bar_vals_num <- era_df$cumulative_pct_num[era_df$series_chr %in% fig_series_chr]
  bar_tick_candidates_num <- unlist(lapply(1:4, \(n) pretty(c(min(0, bar_vals_num), max(0, bar_vals_num)), n = n)))
  tick_label_w_pt_num <- max(systemfonts::string_width(
    c(format(fig_spec$y_breaks_num), paste0(bar_tick_candidates_num, "%")),
    family = eig_font_body_chr, size = axis_pt_num, res = 72
  ))
  left_margin_pt_num <- tick_label_w_pt_num + tick_gap_in_num * 72 + 2

  base_theme <- ggplot2::theme_minimal(base_size = axis_pt_num, base_family = eig_font_body_chr) +
    ggplot2::theme(
      panel.grid.major.x = ggplot2::element_blank(),
      panel.grid.minor   = ggplot2::element_blank(),
      panel.grid.major.y = ggplot2::element_line(color = grid_color_chr, linewidth = 0.3),
      panel.border       = ggplot2::element_blank(),
      axis.title         = ggplot2::element_blank(),
      axis.text          = ggplot2::element_text(color = tick_color_chr, size = axis_pt_num),
      axis.text.y        = ggplot2::element_blank(),
      legend.position    = "none",
      plot.margin        = ggplot2::margin(2, right_margin_pt_num, 2, left_margin_pt_num, unit = "pt")
    )

  annotation_theme <- ggplot2::theme(
    # patchwork aligns title, subtitle, and caption to the subplots' inner
    # plot-margin edge; the negative left margin pulls them back flush left
    # past the fixed tick-label margin.
    plot.title = ggplot2::element_text(family = eig_font_title_chr, face = "bold",
                                       size = title_pt_num, hjust = 0,
                                       margin = ggplot2::margin(0, 0, 4, -left_margin_pt_num)),
    plot.subtitle = ggplot2::element_text(family = eig_font_body_chr, size = subtitle_pt_num,
                                          hjust = 0, margin = ggplot2::margin(0, 0, 8, -left_margin_pt_num)),
    plot.caption = ggplot2::element_text(family = eig_font_body_chr, size = caption_pt_num,
                                         color = caption_color_chr, hjust = 0, lineheight = 1.1,
                                         margin = ggplot2::margin(8, 0, 0, -left_margin_pt_num)),
    plot.title.position   = "plot",
    plot.caption.position = "plot",
    plot.margin = ggplot2::margin(10, 6, 8, 6, unit = "pt")
  )

  skel_line <- ggplot2::ggplot(long_df, ggplot2::aes(date_dt, index_num)) +
    ggplot2::geom_blank() +
    ggplot2::scale_x_date(limits = c(first_dt, last_dt), expand = c(0, 0),
                          breaks = seq(as.Date("1985-01-01"), last_dt, by = "5 years"),
                          date_labels = "%Y") +
    ggplot2::scale_y_continuous(limits = fig_spec$y_limits_num, breaks = fig_spec$y_breaks_num,
                                expand = c(0, 0)) +
    base_theme
  skel_bar <- ggplot2::ggplot(tibble::tibble(x = c(first_dt, last_dt), y = c(0, 1)),
                              ggplot2::aes(x, y)) +
    ggplot2::geom_blank() +
    ggplot2::scale_x_date(limits = c(first_dt, last_dt), expand = c(0, 0)) +
    base_theme +
    ggplot2::theme(axis.text.x = ggplot2::element_blank())
  skel_fig <- patchwork::wrap_plots(skel_line, skel_bar, ncol = 1) +
    patchwork::plot_layout(heights = c(line_panel_h_in_num, bar_panel_h_in_num)) +
    patchwork::plot_annotation(title = title_wrapped_chr, subtitle = subtitle_chr,
                               caption = caption_chr, theme = annotation_theme)

  # The ragg device must be open BEFORE the grob is built: ggplot2 fixes
  # title/axis text sizes from the current device's font metrics.
  measure_png_chr <- fs::file_temp(ext = "png")
  ragg::agg_png(measure_png_chr, width = render_width_in_num, height = 8,
                units = "in", res = render_dpi_int)
  skel_grob <- patchwork::patchworkGrob(skel_fig)
  h_type_chr <- grid::unitType(skel_grob$heights)
  w_type_chr <- grid::unitType(skel_grob$widths)
  fixed_h_in_num <- sum(grid::convertHeight(skel_grob$heights[h_type_chr != "null"], "in", valueOnly = TRUE))
  fixed_w_in_num <- sum(grid::convertWidth(skel_grob$widths[w_type_chr != "null"], "in", valueOnly = TRUE))
  grDevices::dev.off()
  fs::file_delete(measure_png_chr)

  if (sum(h_type_chr == "null") != 2L || sum(w_type_chr == "null") != 1L) {
    stop("figure_f_era_bars.R -- unexpected patchwork layout for Figure ", fig_id_chr, ".")
  }

  fig_height_in_num <- fixed_h_in_num + line_panel_h_in_num + bar_panel_h_in_num
  panel_w_in_num    <- render_width_in_num - fixed_w_in_num
  in_per_day_num    <- panel_w_in_num / domain_days_num

  ###################################
  ###   3) Line panel labels      ###
  ###################################
  # End-of-line labels, pushed apart only as far as needed (two passes:
  # upward from the lowest, then back down from the top limit), with a
  # dotted connector when a label moved.

  y_range_num      <- diff(fig_spec$y_limits_num)
  units_per_in_num <- y_range_num / line_panel_h_in_num
  line_h_units_num <- (line_label_pt_num * 1.15 / 72) * units_per_in_num

  end_df <- long_df |>
    dplyr::filter(date_dt == last_dt) |>
    dplyr::mutate(
      label_chr   = unname(fig_spec$labels_chr[series_chr]),
      n_lines_int = unname(line_label_lines_int[series_chr]),
      half_h_num  = n_lines_int * line_h_units_num / 2
    ) |>
    dplyr::arrange(index_num)

  end_df$label_y_num <- end_df$index_num
  gap_units_num <- 0.15 * line_h_units_num
  # Shift the cluster by its mean displacement once, so labels spread
  # around the line ends rather than only upward.
  for (pass_int in 1:2) {
    for (i in seq_len(nrow(end_df))[-1]) {
      min_y_num <- end_df$label_y_num[i - 1] + end_df$half_h_num[i - 1] +
        end_df$half_h_num[i] + gap_units_num
      end_df$label_y_num[i] <- max(end_df$label_y_num[i], min_y_num)
    }
    top_cap_num <- fig_spec$y_limits_num[2] - end_df$half_h_num[nrow(end_df)]
    if (end_df$label_y_num[nrow(end_df)] > top_cap_num) {
      end_df$label_y_num[nrow(end_df)] <- top_cap_num
    }
    for (i in rev(seq_len(nrow(end_df) - 1L))) {
      max_y_num <- end_df$label_y_num[i + 1] - end_df$half_h_num[i + 1] -
        end_df$half_h_num[i] - gap_units_num
      end_df$label_y_num[i] <- min(end_df$label_y_num[i], max_y_num)
    }
    if (pass_int == 1L) {
      end_df$label_y_num <- end_df$label_y_num -
        mean(end_df$label_y_num - end_df$index_num)
    }
  }

  label_sep_ok_bool <- all(diff(end_df$label_y_num) >=
    (utils::head(end_df$half_h_num, -1) + utils::tail(end_df$half_h_num, -1)) - 1e-9)
  if (!label_sep_ok_bool ||
      min(end_df$label_y_num - end_df$half_h_num) < fig_spec$y_limits_num[1]) {
    stop("figure_f_era_bars.R -- Figure ", fig_id_chr, " end labels cannot be separated.")
  }

  label_x_dt <- last_dt + round(label_gap_in_num / in_per_day_num)
  end_df$label_x_dt <- label_x_dt
  connector_df <- end_df |>
    dplyr::filter(abs(label_y_num - index_num) > 0.1 * line_h_units_num) |>
    dplyr::mutate(
      x_dt    = last_dt,
      xend_dt = last_dt + round(0.8 * label_gap_in_num / in_per_day_num)
    )

  ###################################
  ###   4) Era rail               ###
  ###################################
  # Era names centered on each era's span and top-aligned just under the
  # panel top, so one- and two-line names share a top edge; wrapped to
  # two lines when one line would not fit between the rules. The rail must
  # clear the data.

  rail_top_pad_in_num <- 0.05
  rail_line_h_in_num  <- 1.1 * rail_pt_num / 72
  rail_df <- eras_df |>
    dplyr::mutate(
      x_dt        = era_start_dt + (era_right_dt - era_start_dt) / 2,
      width_in    = as.numeric(era_right_dt - era_start_dt) * in_per_day_num,
      label_chr   = unname(era_rail_labels_chr[era_slug_chr]),
      n_lines_int = 1L,
      rail_y_num  = fig_spec$y_limits_num[2] - rail_top_pad_in_num * units_per_in_num
    )

  rail_pad_in_num <- 0.08
  for (e in seq_len(nrow(rail_df))) {
    one_w_in_num <- systemfonts::string_width(rail_df$label_chr[e], family = eig_font_body_chr,
                                              size = rail_pt_num, res = 72) / 72
    if (one_w_in_num > rail_df$width_in[e] - 2 * rail_pad_in_num) {
      words_chr <- strsplit(rail_df$label_chr[e], " ")[[1]]
      if (length(words_chr) < 2L) {
        stop("figure_f_era_bars.R -- era name '", rail_df$label_chr[e], "' does not fit and cannot wrap.")
      }
      split_w_in_num <- vapply(seq_len(length(words_chr) - 1L), \(k) max(
        systemfonts::string_width(
          c(paste(words_chr[1:k], collapse = " "),
            paste(words_chr[(k + 1):length(words_chr)], collapse = " ")),
          family = eig_font_body_chr, size = rail_pt_num, res = 72) / 72
      ), numeric(1L))
      best_k_int <- which.min(split_w_in_num)
      rail_df$label_chr[e] <- paste0(
        paste(words_chr[1:best_k_int], collapse = " "), "\n",
        paste(words_chr[(best_k_int + 1):length(words_chr)], collapse = " ")
      )
      rail_df$n_lines_int[e] <- 2L
      if (split_w_in_num[best_k_int] > rail_df$width_in[e] - 2 * rail_pad_in_num) {
        stop("figure_f_era_bars.R -- era name '", era_rail_labels_chr[rail_df$era_slug_chr[e]],
             "' does not fit between its rules even on two lines (needs ",
             round(split_w_in_num[best_k_int], 2), " in; era is ", round(rail_df$width_in[e], 2), " in).")
      }
    }
    # Rail clearance: the data under this era stay below the rail text
    # (with 0.03 in to spare).
    rail_bottom_num <- rail_df$rail_y_num[e] -
      (rail_df$n_lines_int[e] * rail_line_h_in_num + 0.03) * units_per_in_num
    era_max_num <- max(long_df$index_num[
      long_df$date_dt >= rail_df$era_start_dt[e] & long_df$date_dt <= rail_df$era_right_dt[e]
    ])
    if (era_max_num >= rail_bottom_num) {
      stop("figure_f_era_bars.R -- Figure ", fig_id_chr, " data reach the era rail in era ", e,
           " (data max ", round(era_max_num, 1), ", rail bottom ", round(rail_bottom_num, 1), ").")
    }
  }

  ###################################
  ###   5) Bar geometry           ###
  ###################################
  # Groups on the date axis: centered on each era's midpoint, one equal
  # width for every era; slot = group / n; bar = 0.9 x slot. The width is
  # the largest that keeps the widest value label on an outer bar at least
  # 0.03 in inside the shortest era's rules, capped at 0.95 x that era:
  #   g = (E - w - 2 x 0.03) / (1 - 0.9 / n)   (all in inches)
  # When horizontal labels would be wider than their slot (they would
  # stack into a staircase), every label in the figure is turned 90
  # degrees so it sits directly over (or under) its own bar; its
  # horizontal extent is then the text height.

  text_h_in_num <- 0.78 * bar_label_pt_num / 72   # digit cap-height box
  bar_labels_pre_chr <- sprintf("%.0f", round(era_df$cumulative_pct_num[era_df$series_chr %in% fig_series_chr]))
  bar_labels_pre_chr[bar_labels_pre_chr == "-0"] <- "0"
  widest_label_in_num <- max(systemfonts::string_width(
    bar_labels_pre_chr, family = eig_font_body_chr, size = bar_label_pt_num, res = 72, weight = "bold"
  )) / 72
  shortest_era_in_num <- min(as.numeric(eras_df$era_right_dt - eras_df$era_start_dt)) * in_per_day_num
  group_w_in_num <- min(
    0.95 * shortest_era_in_num,
    (shortest_era_in_num - widest_label_in_num - 2 * 0.03) / (1 - 0.9 / n_series_int)
  )
  # Rotate only if two same-sign labels on ADJACENT bars of one era would
  # collide horizontally at this width.
  pre_df <- era_df |>
    dplyr::filter(series_chr %in% fig_series_chr) |>
    dplyr::mutate(
      rank_int  = match(series_chr, fig_series_chr),
      label_chr = sprintf("%.0f", round(cumulative_pct_num)),
      sign_int  = dplyr::if_else(cumulative_pct_num >= 0, 1L, -1L)
    ) |>
    dplyr::arrange(era_i_int, rank_int)
  pre_df$label_chr[pre_df$label_chr == "-0"] <- "0"
  pre_df$w_in_num <- systemfonts::string_width(
    pre_df$label_chr, family = eig_font_body_chr, size = bar_label_pt_num, res = 72, weight = "bold"
  ) / 72
  adjacent_clash_bool <- FALSE
  for (r in seq_len(nrow(pre_df))[-1]) {
    if (pre_df$era_i_int[r] == pre_df$era_i_int[r - 1] &&
        pre_df$sign_int[r] == pre_df$sign_int[r - 1] &&
        (pre_df$w_in_num[r] + pre_df$w_in_num[r - 1]) / 2 + 0.03 > group_w_in_num / n_series_int) {
      adjacent_clash_bool <- TRUE
    }
  }
  rotate_labels_bool <- adjacent_clash_bool
  if (rotate_labels_bool) {
    group_w_in_num <- min(
      0.95 * shortest_era_in_num,
      (shortest_era_in_num - text_h_in_num - 2 * 0.03) / (1 - 0.9 / n_series_int)
    )
  }
  if (group_w_in_num <= 0) {
    stop("figure_f_era_bars.R -- Figure ", fig_id_chr, " bar labels are too wide for the shortest era.")
  }
  group_w_days_num <- group_w_in_num / in_per_day_num
  slot_w_days_num  <- group_w_days_num / n_series_int

  bar_df <- era_df |>
    dplyr::filter(series_chr %in% fig_series_chr) |>
    dplyr::left_join(eras_df |> dplyr::select(era_i_int, era_right_dt), by = "era_i_int") |>
    dplyr::mutate(
      rank_int     = match(series_chr, fig_series_chr),
      center_num   = as.numeric(era_start_dt) + (as.numeric(era_right_dt) - as.numeric(era_start_dt)) / 2,
      xc_num       = center_num + (rank_int - (n_series_int + 1) / 2) * slot_w_days_num,
      xmin_num     = xc_num - 0.45 * slot_w_days_num,
      xmax_num     = xc_num + 0.45 * slot_w_days_num,
      value_num    = cumulative_pct_num,   # owner choice 2026-09-29: cumulative (annualized stored in the tables)
      rounded_num  = round(value_num),
      label_chr    = sprintf("%.0f", rounded_num),
      sign_int     = dplyr::if_else(value_num >= 0, 1L, -1L),
      series_fct   = factor(series_chr, levels = fig_series_chr)
    ) |>
    dplyr::arrange(era_i_int, rank_int)

  # Never print "-0".
  bar_df$label_chr[bar_df$rounded_num == 0] <- "0"

  # Groups sit between their era's rules.
  group_bounds_df <- bar_df |>
    dplyr::group_by(era_i_int) |>
    dplyr::summarise(
      gmin_num = min(xmin_num), gmax_num = max(xmax_num),
      lo_num = as.numeric(dplyr::first(era_start_dt)), hi_num = as.numeric(dplyr::first(era_right_dt)),
      .groups = "drop"
    )
  if (any(group_bounds_df$gmin_num < group_bounds_df$lo_num | group_bounds_df$gmax_num > group_bounds_df$hi_num)) {
    stop("figure_f_era_bars.R -- Figure ", fig_id_chr, " bar group spills across an era rule.")
  }

  ###################################
  ###   6) Bar value labels       ###
  ###################################
  # Placed in inches from the zero line. Within each era group and sign,
  # labels go from the smallest |value| to the largest; a label that would
  # overlap an already-placed label horizontally (0.03 in gap) is lifted
  # past it (its height plus 0.03 in), and a label also clears any other
  # bar it overlaps horizontally. If the previous (smaller) label was
  # lifted, the next stays at least a quarter step beyond it so the label
  # order matches the value order. The panel's y limits then grow until
  # every label fits. box_w / box_h are each label's horizontal / vertical
  # extent (swapped when labels are rotated).

  bar_df$label_w_in_num <- systemfonts::string_width(
    bar_df$label_chr, family = eig_font_body_chr, size = bar_label_pt_num, res = 72,
    weight = "bold"
  ) / 72
  bar_df$box_w_in_num <- if (rotate_labels_bool) text_h_in_num else bar_df$label_w_in_num
  bar_df$box_h_in_num <- if (rotate_labels_bool) bar_df$label_w_in_num else text_h_in_num
  step_in_num   <- 0.95 * bar_label_pt_num / 72
  pad_in_num    <- 0.03
  hgap_in_num   <- 0.03

  data_lo_num <- min(0, bar_df$value_num)
  data_hi_num <- max(0, bar_df$value_num)
  y_lo_num <- data_lo_num
  y_hi_num <- data_hi_num + 1e-6
  bar_df$label_edge_in_num <- NA_real_   # inner edge (bottom for gains, top for losses)

  for (iter_int in 1:100) {
    s_in_per_unit_num <- bar_panel_h_in_num / (y_hi_num - y_lo_num)

    for (era_i in unique(bar_df$era_i_int)) {
      for (sgn in c(1L, -1L)) {
        idx_int <- which(bar_df$era_i_int == era_i & bar_df$sign_int == sgn)
        if (length(idx_int) == 0L) next
        idx_int <- idx_int[order(abs(bar_df$value_num[idx_int]), bar_df$rank_int[idx_int])]
        placed_int <- integer(0)
        prev_lifted_bool <- FALSE
        for (i in idx_int) {
          natural_in_num <- abs(bar_df$value_num[i]) * s_in_per_unit_num + pad_in_num
          edge_in_num <- natural_in_num
          xi_in_num <- bar_df$xc_num[i] * in_per_day_num
          # Other bars of the same sign in this group that the label overlaps.
          grp_int <- which(bar_df$era_i_int == era_i & bar_df$sign_int == sgn & seq_len(nrow(bar_df)) != i)
          for (j in grp_int) {
            bar_half_in_num <- 0.45 * slot_w_days_num * in_per_day_num
            if (abs(xi_in_num - bar_df$xc_num[j] * in_per_day_num) <
                bar_df$box_w_in_num[i] / 2 + bar_half_in_num) {
              edge_in_num <- max(edge_in_num,
                                 abs(bar_df$value_num[j]) * s_in_per_unit_num + pad_in_num)
            }
          }
          for (j in placed_int) {
            if (abs(xi_in_num - bar_df$xc_num[j] * in_per_day_num) <
                (bar_df$box_w_in_num[i] + bar_df$box_w_in_num[j]) / 2 + hgap_in_num) {
              edge_in_num <- max(edge_in_num, bar_df$label_edge_in_num[j] + bar_df$box_h_in_num[j] + 0.03)
            }
          }
          if (prev_lifted_bool && length(placed_int) > 0L) {
            edge_in_num <- max(edge_in_num,
                               bar_df$label_edge_in_num[utils::tail(placed_int, 1L)] + 0.25 * step_in_num)
          }
          bar_df$label_edge_in_num[i] <- edge_in_num
          prev_lifted_bool <- edge_in_num > natural_in_num + 1e-9
          placed_int <- c(placed_int, i)
        }
      }
    }

    outer_in_num <- bar_df$label_edge_in_num + bar_df$box_h_in_num + 0.02
    need_hi_num <- max(data_hi_num, max(c(0, outer_in_num[bar_df$sign_int == 1L])) / s_in_per_unit_num)
    need_lo_num <- min(data_lo_num, -max(c(0, outer_in_num[bar_df$sign_int == -1L])) / s_in_per_unit_num)
    if (abs(need_hi_num - y_hi_num) < 1e-6 && abs(need_lo_num - y_lo_num) < 1e-6) break
    y_hi_num <- need_hi_num
    y_lo_num <- need_lo_num
  }
  if (iter_int == 100L) {
    stop("figure_f_era_bars.R -- Figure ", fig_id_chr, " bar headroom did not converge.")
  }

  s_in_per_unit_num <- bar_panel_h_in_num / (y_hi_num - y_lo_num)
  bar_share_num <- (data_hi_num - data_lo_num) * s_in_per_unit_num / bar_panel_h_in_num
  if (bar_share_num < 0.20) {
    stop("figure_f_era_bars.R -- Figure ", fig_id_chr, " labels leave the bars only ",
         round(100 * bar_share_num), " percent of the panel height.")
  }

  bar_df <- bar_df |>
    dplyr::mutate(
      label_y_num = sign_int * label_edge_in_num / s_in_per_unit_num,
      label_vjust_num = if (rotate_labels_bool) 0.5 else dplyr::if_else(sign_int == 1L, 0, 1),
      label_hjust_num = if (rotate_labels_bool) dplyr::if_else(sign_int == 1L, 0, 1) else 0.5,
      label_angle_num = if (rotate_labels_bool) 90 else 0,
      # Label boxes in inches for the collision audit.
      box_x0_in = xc_num * in_per_day_num - box_w_in_num / 2,
      box_x1_in = xc_num * in_per_day_num + box_w_in_num / 2,
      box_y0_in = dplyr::if_else(sign_int == 1L, label_edge_in_num, -label_edge_in_num - box_h_in_num),
      box_y1_in = dplyr::if_else(sign_int == 1L, label_edge_in_num + box_h_in_num, -label_edge_in_num)
    )

  # Collision audit: label vs label, label vs bar, label vs rule.
  collision_chr <- character(0)
  for (i in seq_len(nrow(bar_df))) {
    for (j in seq_len(nrow(bar_df))) {
      if (j > i &&
          bar_df$box_x0_in[i] < bar_df$box_x1_in[j] && bar_df$box_x0_in[j] < bar_df$box_x1_in[i] &&
          bar_df$box_y0_in[i] < bar_df$box_y1_in[j] && bar_df$box_y0_in[j] < bar_df$box_y1_in[i]) {
        collision_chr <- c(collision_chr, paste0("label ", i, " x label ", j))
      }
      bar_y0_in <- min(0, bar_df$value_num[j]) * s_in_per_unit_num
      bar_y1_in <- max(0, bar_df$value_num[j]) * s_in_per_unit_num
      if (bar_df$box_x0_in[i] < bar_df$xmax_num[j] * in_per_day_num &&
          bar_df$xmin_num[j] * in_per_day_num < bar_df$box_x1_in[i] &&
          bar_df$box_y0_in[i] < bar_y1_in && bar_y0_in < bar_df$box_y1_in[i]) {
        collision_chr <- c(collision_chr, paste0("label ", i, " x bar ", j))
      }
    }
    rule_in_num <- as.numeric(rule_dates_dt) * in_per_day_num
    if (any(rule_in_num > bar_df$box_x0_in[i] & rule_in_num < bar_df$box_x1_in[i])) {
      collision_chr <- c(collision_chr, paste0("label ", i, " x era rule"))
    }
  }
  if (length(collision_chr) > 0L) {
    stop("figure_f_era_bars.R -- Figure ", fig_id_chr, " label collisions: ",
         paste(collision_chr, collapse = "; "))
  }
  n_lifted_int <- sum(bar_df$label_edge_in_num >
                        abs(bar_df$value_num) * s_in_per_unit_num + pad_in_num + 1e-9)

  # Bar y ticks: pretty() over the data range, kept near the data, always
  # including 0.
  # Coarsen until adjacent tick labels are at least 1.6 text heights apart.
  tick_n_int <- 4L
  ticks_num <- pretty(c(data_lo_num, data_hi_num), n = tick_n_int)
  while (diff(ticks_num)[1] * s_in_per_unit_num < 1.6 * axis_pt_num / 72 && tick_n_int > 1L) {
    tick_n_int <- tick_n_int - 1L
    ticks_num <- pretty(c(data_lo_num, data_hi_num), n = tick_n_int)
  }
  tick_step_num <- diff(ticks_num)[1]
  ticks_num <- ticks_num[ticks_num >= data_lo_num - 0.5 * tick_step_num &
                         ticks_num <= data_hi_num + 0.5 * tick_step_num &
                         ticks_num >= y_lo_num & ticks_num <= y_hi_num]
  ticks_num <- sort(unique(c(0, ticks_num)))

  ###################################
  ###   7) Draw                   ###
  ###################################

  pre_df   <- long_df |> dplyr::filter(date_dt <= covid_lead_dt)
  covid_df <- long_df |> dplyr::filter(date_dt >= covid_lead_dt, date_dt <= covid_lag_dt)
  post_df  <- long_df |> dplyr::filter(date_dt >= covid_lag_dt)

  # Y tick labels drawn as text just left of each panel (fixed margin).
  tick_x_off_days_num <- tick_gap_in_num / in_per_day_num
  line_ticks_df <- tibble::tibble(y_num = fig_spec$y_breaks_num, label_chr = format(fig_spec$y_breaks_num),
                                  x_num = as.numeric(first_dt) - tick_x_off_days_num)
  bar_ticks_df  <- tibble::tibble(y_num = ticks_num, label_chr = paste0(ticks_num, "%"),
                                  x_num = as.numeric(first_dt) - tick_x_off_days_num)

  line_plot <- ggplot2::ggplot(long_df, ggplot2::aes(x = date_dt, y = index_num, color = series_fct)) +
    ggplot2::geom_hline(yintercept = 100, linetype = "dashed", linewidth = 0.3, color = ref_color_chr) +
    ggplot2::geom_vline(xintercept = rule_dates_dt, linetype = "dashed", linewidth = 0.3,
                        color = rule_color_chr) +
    ggplot2::geom_line(data = pre_df,   linewidth = 0.7) +
    ggplot2::geom_line(data = covid_df, linewidth = 0.7, linetype = "dashed") +
    ggplot2::geom_line(data = post_df,  linewidth = 0.7) +
    ggplot2::geom_segment(
      data = connector_df,
      ggplot2::aes(x = x_dt, xend = xend_dt, y = index_num, yend = label_y_num, color = series_fct),
      linetype = "dotted", linewidth = 0.35, inherit.aes = FALSE
    ) +
    ggplot2::geom_text(
      data = end_df,
      ggplot2::aes(x = label_x_dt, y = label_y_num, label = label_chr, color = series_fct),
      hjust = 0, vjust = 0.5, lineheight = 0.95, size = line_label_pt_num * mm_per_pt_num,
      family = eig_font_body_chr, inherit.aes = FALSE
    ) +
    ggplot2::geom_text(
      data = rail_df,
      ggplot2::aes(x = x_dt, y = rail_y_num, label = label_chr),
      color = rail_color_chr, size = rail_pt_num * mm_per_pt_num, lineheight = 0.95, vjust = 1,
      family = eig_font_body_chr, inherit.aes = FALSE
    ) +
    ggplot2::geom_text(
      data = line_ticks_df,
      ggplot2::aes(x = as.Date(x_num), y = y_num, label = label_chr),
      hjust = 1, vjust = 0.5, color = tick_color_chr, size = axis_pt_num * mm_per_pt_num,
      family = eig_font_body_chr, inherit.aes = FALSE
    ) +
    ggplot2::scale_color_manual(values = fig_spec$colors_chr, drop = FALSE) +
    # oob_keep: the end labels sit right of the last month, outside the
    # limits, and must not be censored.
    ggplot2::scale_x_date(limits = c(first_dt, last_dt), expand = c(0, 0),
                          breaks = seq(as.Date("1985-01-01"), last_dt, by = "5 years"),
                          date_labels = "%Y", oob = scales::oob_keep) +
    ggplot2::scale_y_continuous(limits = fig_spec$y_limits_num, breaks = fig_spec$y_breaks_num,
                                labels = scales::label_number(accuracy = 1), expand = c(0, 0)) +
    ggplot2::coord_cartesian(clip = "off") +
    base_theme

  bar_plot <- ggplot2::ggplot(bar_df) +
    ggplot2::geom_hline(yintercept = 0, linewidth = 0.35, color = zero_color_chr) +
    ggplot2::geom_vline(xintercept = as.numeric(rule_dates_dt), linetype = "dashed",
                        linewidth = 0.3, color = rule_color_chr) +
    ggplot2::geom_rect(
      ggplot2::aes(xmin = xmin_num, xmax = xmax_num, ymin = pmin(0, value_num),
                   ymax = pmax(0, value_num), fill = series_fct),
      color = NA
    ) +
    ggplot2::geom_text(
      ggplot2::aes(x = xc_num, y = label_y_num, label = label_chr, color = series_fct,
                   vjust = label_vjust_num, hjust = label_hjust_num, angle = label_angle_num),
      size = bar_label_pt_num * mm_per_pt_num, fontface = "bold", family = eig_font_body_chr
    ) +
    ggplot2::geom_text(
      data = bar_ticks_df,
      ggplot2::aes(x = x_num, y = y_num, label = label_chr),
      hjust = 1, vjust = 0.5, color = tick_color_chr, size = axis_pt_num * mm_per_pt_num,
      family = eig_font_body_chr, inherit.aes = FALSE
    ) +
    ggplot2::scale_fill_manual(values = fig_spec$colors_chr, drop = FALSE) +
    ggplot2::scale_color_manual(values = fig_spec$colors_chr, drop = FALSE) +
    ggplot2::scale_x_continuous(limits = as.numeric(c(first_dt, last_dt)), expand = c(0, 0),
                                oob = scales::oob_keep) +
    ggplot2::scale_y_continuous(limits = c(y_lo_num, y_hi_num), breaks = ticks_num,
                                labels = paste0(ticks_num, "%"), expand = c(0, 0)) +
    ggplot2::coord_cartesian(clip = "off") +
    base_theme +
    ggplot2::theme(axis.text.x = ggplot2::element_blank())

  fig_plot <- patchwork::wrap_plots(line_plot, bar_plot, ncol = 1) +
    patchwork::plot_layout(heights = c(line_panel_h_in_num, bar_panel_h_in_num)) +
    patchwork::plot_annotation(title = title_wrapped_chr, subtitle = subtitle_chr,
                               caption = caption_chr, theme = annotation_theme)

  png_path_chr <- fs::path(fig_out_dir_chr, fig_spec$png_chr)
  ggplot2::ggsave(
    filename = png_path_chr,
    plot     = fig_plot,
    width    = render_width_in_num,
    height   = fig_height_in_num,
    units    = "in",
    dpi      = render_dpi_int,
    device   = eig_png_device,
    bg       = "white"
  )

  ###################################
  ###   7b) Bars-only export      ###
  ###################################
  # Bar panel alone, no title, subtitle, caption, or line panel, saved at
  # exactly 1000 px wide. The device is the same 10.52 in canvas as the full
  # figure; dpi is set to 1000 / 10.52 so the pixel width lands on 1000 and
  # every font keeps its size relative to the bars.
  
  bars_only_width_px_int <- 1000L
  bars_only_dpi_num      <- bars_only_width_px_int / render_width_in_num
  
  # Left and right padding are matched to the Datawrapper export so the
  # bar panel and the line chart share the same plot-area edges and dashed
  # era rules when both images are placed at the same width. Shares are of
  # total image width, measured from the placed screenshot (left 5.9%,
  # right 5.5%). Top and bottom get 8 pt so the outermost y tick labels
  # are not clipped.
  dw_left_share_num  <- 0.059
  dw_right_share_num <- 0.055
  bars_only_left_pt_num   <- dw_left_share_num  * render_width_in_num * 72
  bars_only_right_pt_num  <- dw_right_share_num * render_width_in_num * 72
  bars_only_margin_pt_num <- 8
  
  # Bar and bar-label colors. Figure 6b uses the Datawrapper line colors so
  # the bars match the line chart above them; other figures keep their
  # own palette.
  bars_only_colors_chr <- fig_spec$colors_chr
  if (fig_id_chr == "6b") {
    bars_only_colors_chr <- c(r50_10 = "#b3d6dd", r90_50 = "#f0b799", r90_10 = "#044140")
  }
  
  bars_only_plot <- bar_plot +
    ggplot2::scale_fill_manual(values = bars_only_colors_chr, drop = FALSE) +
    ggplot2::scale_color_manual(values = bars_only_colors_chr, drop = FALSE) +
    ggplot2::theme(
      plot.margin = ggplot2::margin(
        bars_only_margin_pt_num, bars_only_right_pt_num, bars_only_margin_pt_num,
        bars_only_left_pt_num, unit = "pt"
      )
    )
  
  bars_only_height_in_num <- bar_panel_h_in_num + 2 * bars_only_margin_pt_num / 72
  bars_only_png_chr <- fs::path(
    fig_out_dir_chr, sub("\\.png$", "_bars_only.png", fig_spec$png_chr)
  )
  
  ggplot2::ggsave(
    filename = bars_only_png_chr,
    plot     = bars_only_plot,
    width    = render_width_in_num,
    height   = bars_only_height_in_num,
    units    = "in",
    dpi      = bars_only_dpi_num,
    device   = eig_png_device,
    bg       = "white"
  )
  
  bars_only_dim_int <- dim(png::readPNG(bars_only_png_chr))
  if (bars_only_dim_int[2] != bars_only_width_px_int) {
    stop("figure_f_era_bars.R -- Figure ", fig_id_chr, " bars-only PNG is ", bars_only_dim_int[2],
         " px wide, expected ", bars_only_width_px_int, ".")
  }
  message("figure_f_era_bars.R -- Figure ", fig_id_chr, " bars-only written: ", bars_only_png_chr,
          " (", bars_only_dim_int[2], " x ", bars_only_dim_int[1], " px)")
  
  ###################################
  ###   8) Verify the render      ###
  ###################################
  # Find the dashed era rules in the rendered pixels: columns where the
  # rule gray is lit on a meaningful share of rows, separately in the
  # line-panel band and the bar-panel band. Each of the four rules must
  # sit on the same column (within 1 px) in both bands.

  img_arr <- png::readPNG(png_path_chr)
  img_h_int <- dim(img_arr)[1]
  img_w_int <- dim(img_arr)[2]
  rule_rgb_num <- grDevices::col2rgb(rule_color_chr)[, 1] / 255
  is_rule_mat <- abs(img_arr[, , 1] - rule_rgb_num[1]) < 0.06 &
    abs(img_arr[, , 2] - rule_rgb_num[2]) < 0.06 &
    abs(img_arr[, , 3] - rule_rgb_num[3]) < 0.06

  # Panel bands in pixel rows, from the measured layout.
  top_fixed_in_num <- NA_real_
  heights_in_num <- NULL
  ragg::agg_png(fs::file_temp(ext = "png"), width = render_width_in_num,
                height = fig_height_in_num, units = "in", res = render_dpi_int)
  fig_grob <- patchwork::patchworkGrob(fig_plot)
  h_type_chr <- grid::unitType(fig_grob$heights)
  heights_in_num <- grid::convertHeight(fig_grob$heights, "in", valueOnly = TRUE)
  heights_in_num[h_type_chr == "null"] <- c(line_panel_h_in_num, bar_panel_h_in_num)
  widths_in_num <- grid::convertWidth(fig_grob$widths, "in", valueOnly = TRUE)
  w_type_chr <- grid::unitType(fig_grob$widths)
  widths_in_num[w_type_chr == "null"] <- panel_w_in_num
  grDevices::dev.off()

  final_fixed_w_in_num <- sum(widths_in_num[w_type_chr != "null"])
  if (abs(final_fixed_w_in_num - fixed_w_in_num) > 0.005) {
    stop("figure_f_era_bars.R -- Figure ", fig_id_chr, " final layout width differs from the ",
         "measured skeleton by ", round(final_fixed_w_in_num - fixed_w_in_num, 3), " in.")
  }

  null_rows_int <- which(h_type_chr == "null")
  line_top_in_num <- sum(heights_in_num[seq_len(null_rows_int[1] - 1L)])
  bar_top_in_num  <- sum(heights_in_num[seq_len(null_rows_int[2] - 1L)])
  panel_left_in_num <- sum(widths_in_num[seq_len(which(w_type_chr == "null") - 1L)])

  line_rows_int <- round((line_top_in_num + 0.05) * render_dpi_int):round((line_top_in_num + line_panel_h_in_num - 0.05) * render_dpi_int)
  bar_rows_int  <- round((bar_top_in_num + 0.05) * render_dpi_int):round((bar_top_in_num + bar_panel_h_in_num - 0.05) * render_dpi_int)
  line_cols_int <- which(colMeans(is_rule_mat[line_rows_int, , drop = FALSE]) > 0.25)
  bar_cols_int  <- which(colMeans(is_rule_mat[bar_rows_int, , drop = FALSE]) > 0.25)

  expected_px_num <- (panel_left_in_num + as.numeric(rule_dates_dt - first_dt) * in_per_day_num) *
    render_dpi_int
  line_found_num <- vapply(expected_px_num, \(px) {
    near_int <- line_cols_int[abs(line_cols_int - px) <= 4]
    if (length(near_int) == 0L) NA_real_ else mean(near_int)
  }, numeric(1L))
  bar_found_num <- vapply(expected_px_num, \(px) {
    near_int <- bar_cols_int[abs(bar_cols_int - px) <= 4]
    if (length(near_int) == 0L) NA_real_ else mean(near_int)
  }, numeric(1L))

  if (anyNA(line_found_num) || anyNA(bar_found_num) ||
      max(abs(line_found_num - bar_found_num)) > 1) {
    stop(
      "figure_f_era_bars.R -- Figure ", fig_id_chr, " era rules do not line up between panels ",
      "(line px: ", paste(round(line_found_num, 1), collapse = ", "),
      "; bar px: ", paste(round(bar_found_num, 1), collapse = ", "), ")."
    )
  }

  verification_list[[fig_id_chr]] <- tibble::tibble(
    figure_chr        = fig_id_chr,
    png_chr           = fig_spec$png_chr,
    width_px_int      = img_w_int,
    height_px_int     = img_h_int,
    height_in_num     = round(fig_height_in_num, 2),
    min_font_pt_num   = min(all_font_pt_num * placed_scale_num),
    rule_offset_px_num = max(abs(line_found_num - bar_found_num)),
    bar_share_num     = round(bar_share_num, 2),
    labels_lifted_int = n_lifted_int,
    end_labels_moved_int = nrow(connector_df),
    rail_wrapped_chr  = paste(rail_df$era_slug_chr[rail_df$n_lines_int == 2L], collapse = ", "),
    bar_labels_rotated_bool = rotate_labels_bool
  )

  message(
    "figure_f_era_bars.R -- Figure ", fig_id_chr, " written: ", png_path_chr,
    " (", img_w_int, " x ", img_h_int, " px; rules aligned within ",
    round(max(abs(line_found_num - bar_found_num)), 1), " px; bars use ",
    round(100 * bar_share_num), "% of their panel; ", n_lifted_int, " bar label(s) lifted)"
  )
}

verification_df <- dplyr::bind_rows(verification_list)
print(verification_df)

message("figure_f_era_bars.R -- done. ", nrow(verification_df), " figures written to ", fig_out_dir_chr)
