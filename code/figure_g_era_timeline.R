# figure_g_era_timeline -- one-image timeline of the five wage eras: duration, median real wage growth, unemployment
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

rm(list = ls())
options(scipen = 999)
set.seed(42)

# Sourced by run_all.R inside new.env(parent = globalenv()).
#
# DRAW LAYER. Reads the era-growth table written by
# figure_f_era_bars_tables.R and the UNRATE series written by
# _utils/download_unemployment.R; never touches microdata. One
# ggplot2/patchwork image, two rows on a shared date axis:
#
#   top     variable-width bars: each bar spans its era on the date axis
#           (width = duration) and rises to the era's annualized growth in
#           the median real hourly wage (height), so bar area approximates
#           the era's cumulative growth. Era names and lengths sit on a
#           rail above the bars; each bar carries its value.
#   bottom  the monthly civilian unemployment rate (thin gray line) under a
#           thick segment at each era's average, with the average printed
#           beside it and a dashed 5 percent reference line.
#
# Color does one job: eras whose average unemployment rate is below
# 5 percent are EIG forest green in both rows, the others neutral gray
# (tufte-principles.md: one hue plus gray). Every value is also printed,
# so color is never the only cue (eig-figure-style.md section 6).
#
# Outputs:
#   output/figures/figure_g_era_timeline.png   (rendered at 10.52 in, 300 dpi,
#                                               the Figure 6 slide width)
#   output/tables/figure_g_era_timeline.csv    (one row per era: the numbers drawn)
#
# The script stops rather than ships if a font is below the 12 pt floor,
# an era name cannot fit between its era's edges, a label would collide
# with the monthly unemployment line or the era rail, or the title's claim
# (growth came in the shorter, low-unemployment eras) stops holding.
#
# Palette: 2022 primary EIG tokens via load_palette.R; fonts via
# eig_fonts.R. No custom functions are defined.

source(here::here("code", "_utils", "00_packages.R"))
source(here::here("code", "_utils", "load_palette.R"))
source(here::here("code", "_utils", "eig_fonts.R"))

###################################
###   Configuration             ###
###################################

tbl_dir_chr     <- here::here("output", "tables")
fig_out_dir_chr <- here::here("output", "figures")
era_csv_path_chr    <- fs::path(tbl_dir_chr, "figure_f_percentiles_era_growth.csv")
unrate_path_chr     <- here::here("data", "fred", "unemployment", "unrate_monthly.parquet")
png_path_chr        <- fs::path(fig_out_dir_chr, "figure_g_era_timeline.png")
table_out_path_chr  <- fs::path(tbl_dir_chr, "figure_g_era_timeline.csv")

# Rendered at the placed slide width (same as Figure 6), so pt on the
# device = pt on the slide.
render_width_in_num <- 10.52
render_dpi_int      <- 300L
top_panel_h_in_num    <- 2.55
bottom_panel_h_in_num <- 2.20   # taller since the axis starts at zero

# Font sizes (pt). Legibility floor: 12 pt on the slide.
font_floor_pt_num  <- 12
title_pt_num       <- 20
subtitle_pt_num    <- 13
panel_title_pt_num <- 12
axis_pt_num        <- 12
rail_pt_num        <- 12
value_pt_num       <- 12
caption_pt_num     <- 12
all_font_pt_num <- c(title_pt_num, subtitle_pt_num, panel_title_pt_num, axis_pt_num,
                     rail_pt_num, value_pt_num, caption_pt_num)
line_h_factor_num <- 1.2   # line height as a multiple of font size

# Unemployment threshold that splits the two colors, on UNRATE's percent
# scale. Strict less-than on the era AVERAGE: an era averaging exactly
# 5.0 would be gray.
threshold_num <- 5

# Colors: the low-unemployment highlight is the EIG single-series default
# (Forest Green, eig-figure-style.md section 1); everything else is gray,
# layered by weight (tufte-analytical-design.md section 3). Neutral grays
# follow the Figure 6 chrome.
pal_chr <- eig_palette_2022_primary
low_color_chr     <- pal_chr[["eig_green_700"]]
high_color_chr    <- "#9A9A9A"
monthly_color_chr <- "#C4C4C4"
rule_color_chr    <- "#B5B5B5"
ref_color_chr     <- "#525252"
grid_color_chr    <- "#E3E3E3"
baseline_color_chr <- "#9AA0A6"
ink_color_chr     <- "#262626"
rail_color_chr    <- "#404040"
muted_color_chr   <- "#6B6B6B"
caption_color_chr <- "#333333"

# Rail names: the Figure 6 short names (figure_f_era_bars.R), so the two
# figures name the eras identically. Era 1 carries the asterisk.
era_rail_labels_chr <- c(
  stagnation1     = "First long wage stagnation*",
  itboom          = "IT boom",
  stagnation2     = "Second long wage stagnation",
  recovery        = "Nascent recovery",
  covid_aftermath = "COVID-19 aftermath"
)

# Growth labels: one decimal. The CPS median is not precise to the
# hundredth of a percentage point per year.
growth_digits_int <- 1L
unrate_digits_int <- 1L

title_chr    <- "Figure 7. Real wages grew in short bursts, when unemployment was low"
source_line_chr <- paste0(
  "Sources: Author's analysis of IPUMS-CPS Outgoing Rotation Group microdata, weighted by CPS ",
  "earnings weights, deflated by the U.S. Bureau of Economic Analysis Personal Consumption ",
  "Expenditures price index; U.S. Bureau of Labor Statistics civilian unemployment rate ",
  "(UNRATE, seasonally adjusted). Both series via FRED."
)

fs::dir_create(fig_out_dir_chr, recurse = TRUE)
mm_per_pt_num <- 1 / ggplot2::.pt

###################################
###   0) Preconditions          ###
###################################

if (any(all_font_pt_num < font_floor_pt_num)) {
  stop("figure_g_era_timeline.R -- a font is below the ", font_floor_pt_num, " pt floor.")
}
if (!eig_fonts_registered_bool) {
  warning("figure_g_era_timeline.R -- EIG brand fonts unavailable; text metrics use the 'sans' fallback.")
}
for (p_chr in c(era_csv_path_chr, unrate_path_chr)) {
  if (!fs::file_exists(p_chr)) {
    stop("figure_g_era_timeline.R -- missing input ", p_chr,
         ". Run figure_f_era_bars_tables.R and _utils/download_unemployment.R first.")
  }
}

###################################
###   1) Read and join          ###
###################################

era_df <- readr::read_csv(era_csv_path_chr, show_col_types = FALSE) |>
  dplyr::filter(series_chr %in% c("p50")) |>
  dplyr::mutate(dplyr::across(dplyr::ends_with("_dt"), as.Date)) |>
  dplyr::arrange(era_i_int) |>
  dplyr::transmute(
    era_i_int, era_slug_chr, era_start_dt, era_end_dt,
    # months_int in the era table counts month-to-month steps (base to
    # end); the era's duration counts both its first and last month.
    duration_months_int = as.integer(months_int) + 1L,
    growth_ann_pct_num  = round(annualized_pct_num,1),
    growth_cum_pct_num  = cumulative_pct_num
  )

# era_10_df <- readr::read_csv(era_csv_path_chr, show_col_types = FALSE) |>
#   dplyr::filter(series_chr %in% c("p10")) |>
#   dplyr::mutate(dplyr::across(dplyr::ends_with("_dt"), as.Date)) |>
#   dplyr::arrange(era_i_int) |>
#   dplyr::transmute(
#     era_i_int, era_slug_chr, era_start_dt, era_end_dt,
#     # months_int in the era table counts month-to-month steps (base to
#     # end); the era's duration counts both its first and last month.
#     duration_months_int = as.integer(months_int) + 1L,
#     growth_ann_pct_num  = round(annualized_pct_num,1),
#     growth_cum_pct_num  = cumulative_pct_num
#   )
# 
# era_90_df <- readr::read_csv(era_csv_path_chr, show_col_types = FALSE) |>
#   dplyr::filter(series_chr %in% c("p90")) |>
#   dplyr::mutate(dplyr::across(dplyr::ends_with("_dt"), as.Date)) |>
#   dplyr::arrange(era_i_int) |>
#   dplyr::transmute(
#     era_i_int, era_slug_chr, era_start_dt, era_end_dt,
#     # months_int in the era table counts month-to-month steps (base to
#     # end); the era's duration counts both its first and last month.
#     duration_months_int = as.integer(months_int) + 1L,
#     growth_ann_pct_num  = round(annualized_pct_num,1),
#     growth_cum_pct_num  = cumulative_pct_num
#   )

if (nrow(era_df) != 5L || !all(names(era_rail_labels_chr) %in% era_df$era_slug_chr)) {
  stop("figure_g_era_timeline.R -- expected the five named eras in ", era_csv_path_chr, ".")
}

first_dt <- min(era_df$era_start_dt)
last_dt  <- max(era_df$era_end_dt)

unrate_df <- arrow::read_parquet(unrate_path_chr) |>
  dplyr::transmute(date_dt = as.Date(date), unrate_num) |>
  dplyr::filter(date_dt >= first_dt, date_dt <= last_dt) |>
  dplyr::arrange(date_dt)

if (max(unrate_df$date_dt) < last_dt) {
  stop("figure_g_era_timeline.R -- UNRATE ends ", format(max(unrate_df$date_dt)),
       ", before the last wage month ", format(last_dt), ". Rerun _utils/download_unemployment.R.")
}

# Era averages over the observed months in each era. October 2025 has no
# UNRATE observation (shutdown), so it drops out of era 5's average; its
# duration still counts the calendar month.
unrate_df$era_i_int <- findInterval(as.numeric(unrate_df$date_dt), as.numeric(era_df$era_start_dt))
era_unrate_df <- unrate_df |>
  dplyr::group_by(era_i_int) |>
  dplyr::summarise(
    unrate_mean_num   = mean(unrate_num),
    unrate_obs_int    = dplyr::n(),
    months_at_or_below_5_int = sum(unrate_num <= threshold_num),
    .groups = "drop"
  )
era_df <- era_df |>
  dplyr::left_join(era_unrate_df, by = "era_i_int") |>
  dplyr::mutate(
    low_unemp_bool = unrate_mean_num < threshold_num,
    regime_chr     = dplyr::if_else(low_unemp_bool, "low", "high"),
    rail_name_chr  = unname(era_rail_labels_chr[era_slug_chr]),
    ongoing_bool   = era_i_int == max(era_i_int),
    # x extent: from the era's first month to the next era's first month
    # (the last era runs one month past its last data month).
    xmin_dt = era_start_dt,
    xmax_dt = dplyr::lead(era_start_dt, default = seq(last_dt, by = "1 month", length.out = 2L)[2]),
    xmid_dt = xmin_dt + (xmax_dt - xmin_dt) / 2
  )

if (anyNA(era_df$unrate_mean_num)) {
  stop("figure_g_era_timeline.R -- an era has no UNRATE observations.")
}

###################################
###   2) Headline claim guard   ###
###################################
# The title says growth came in short bursts when unemployment was low.
# Both halves must hold in the data: every low-unemployment era grew
# faster than every other era, and the low-unemployment eras together
# span fewer months than the others.

low_df  <- era_df[era_df$low_unemp_bool, ]
high_df <- era_df[!era_df$low_unemp_bool, ]
if (nrow(low_df) == 0L || nrow(high_df) == 0L ||
    min(low_df$growth_ann_pct_num) <= max(high_df$growth_ann_pct_num) ||
    sum(low_df$duration_months_int) >= sum(high_df$duration_months_int)) {
  stop("figure_g_era_timeline.R -- the title claim no longer holds; revisit the title.")
}

###################################
###   3) Wrap title and caption ###
###################################
# Wrapped by MEASURED width, word by word, in each block's own font
# (the figure_f_era_bars.R method).

subtitle_chr <- paste0(
  "Five eras of the median real hourly wage, ", format(first_dt, "%B %Y"), " to ",
  format(last_dt, "%B %Y")
)
note_chr <- paste0(
  "Note: Bar width is era length; bar height is the annualized change in the median real hourly ",
  "wage (12-month rolling average) from the era's first month to its last, so bar area approximates ",
  "cumulative growth. Green marks eras whose average unemployment rate was below 5 percent. Wage ",
  "and salary workers age 16 and older. No October 2025 data (federal shutdown). *The series ",
  "begins in December 1982; any earlier stagnation is not shown."
)

text_limit_pt_num <- (render_width_in_num - 0.3) * 72
text_blocks_list <- list(
  title    = list(paras_chr = title_chr, family_chr = eig_font_title_chr,
                  size_num = title_pt_num, weight_chr = "bold"),
  subtitle = list(paras_chr = subtitle_chr, family_chr = eig_font_body_chr,
                  size_num = subtitle_pt_num, weight_chr = "normal"),
  caption  = list(paras_chr = c(note_chr, source_line_chr), family_chr = eig_font_body_chr,
                  size_num = caption_pt_num, weight_chr = "normal")
)
wrapped_chr <- character(0)
wrapped_lines_int <- integer(0)
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
  wrapped_chr[[block_chr]]       <- paste(lines_chr, collapse = "\n")
  wrapped_lines_int[[block_chr]] <- length(lines_chr)
}

###################################
###   4) Measure the layout     ###
###################################
# Horizontal scale: the panel spans the render width less the plot
# margins and the bottom panel's y tick labels (patchwork aligns the top
# panel to the same edges). The checks below pad by 0.08 in to absorb
# small differences from ggplot's own spacing.

plot_margin_pt_num <- 8
unrate_breaks_num  <- c(0, 5, 10, 15)
tick_w_pt_num <- max(systemfonts::string_width(paste0(unrate_breaks_num, "%"),
                                                family = eig_font_body_chr, size = axis_pt_num, res = 72))
panel_w_in_num <- render_width_in_num - (2 * plot_margin_pt_num + tick_w_pt_num + 6) / 72
in_per_day_num <- panel_w_in_num / as.numeric(era_df$xmax_dt[5] - first_dt)
pad_in_num     <- 0.08
line_in_num    <- rail_pt_num * line_h_factor_num / 72

era_df$width_in_num <- as.numeric(era_df$xmax_dt - era_df$xmin_dt) * in_per_day_num

# Rail text: the era name (bold), then its duration (regular, muted),
# each wrapped word by word to fit between the era's edges.
era_df$rail_name_wrapped_chr <- NA_character_
era_df$rail_name_lines_int   <- NA_integer_
era_df$duration_wrapped_chr  <- NA_character_
era_df$rail_lines_int        <- NA_integer_
era_df$duration_label_chr <- paste0(
  era_df$duration_months_int, " months", dplyr::if_else(era_df$ongoing_bool, " to date", "")  # no-break space keeps "to date" together
)
for (e in seq_len(nrow(era_df))) {
  limit_pt_num <- (era_df$width_in_num[e] - 2 * pad_in_num) * 72
  rail_parts_list <- list(
    name     = list(text_chr = era_df$rail_name_chr[e],      weight_chr = "bold"),
    duration = list(text_chr = era_df$duration_label_chr[e], weight_chr = "normal")
  )
  rail_wrapped_list <- list()
  for (part_chr in names(rail_parts_list)) {
    part_ls <- rail_parts_list[[part_chr]]
    lines_chr <- character(0)
    current_chr <- ""
    for (word_chr in strsplit(part_ls$text_chr, " ")[[1]]) {
      candidate_chr <- if (current_chr == "") word_chr else paste(current_chr, word_chr)
      if (systemfonts::string_width(candidate_chr, family = eig_font_body_chr, size = rail_pt_num,
                                    res = 72, weight = part_ls$weight_chr) <= limit_pt_num) {
        current_chr <- candidate_chr
      } else {
        lines_chr <- c(lines_chr, current_chr)
        current_chr <- word_chr
      }
    }
    lines_chr <- c(lines_chr, current_chr)
    # A single word wider than the era leaves an empty line or an
    # overlong one; either means the rail cannot fit.
    if (any(lines_chr == "") ||
        max(systemfonts::string_width(lines_chr, family = eig_font_body_chr, size = rail_pt_num,
                                      res = 72, weight = part_ls$weight_chr)) > limit_pt_num) {
      stop("figure_g_era_timeline.R -- '", part_ls$text_chr, "' does not fit its ",
           round(era_df$width_in_num[e], 2), " in era.")
    }
    rail_wrapped_list[[part_chr]] <- lines_chr
  }
  era_df$rail_name_wrapped_chr[e] <- paste(rail_wrapped_list$name, collapse = "\n")
  era_df$rail_name_lines_int[e]   <- length(rail_wrapped_list$name)
  era_df$duration_wrapped_chr[e]  <- paste(rail_wrapped_list$duration, collapse = "\n")
  era_df$rail_lines_int[e]        <- length(rail_wrapped_list$name) + length(rail_wrapped_list$duration)
}

# Top panel y range, solved in closed form so the tallest bar's value
# label clears the deepest rail: the space above the tallest bar must
# hold its label, the rail, and two gaps.
growth_max_num <- max(era_df$growth_ann_pct_num)
rail_h_in_num  <- max(era_df$rail_lines_int) * line_in_num
value_h_in_num <- value_pt_num * line_h_factor_num / 72
gap_in_num     <- 0.06
above_in_num   <- gap_in_num + value_h_in_num + 2 * gap_in_num + rail_h_in_num
if (above_in_num >= top_panel_h_in_num * 0.8) {
  stop("figure_g_era_timeline.R -- the rail leaves the bars under 20 percent of the top panel.")
}
top_y_hi_num  <- growth_max_num / (1 - above_in_num / top_panel_h_in_num)
top_units_per_in_num <- top_y_hi_num / top_panel_h_in_num

era_df$growth_label_chr <- paste0(formatC(era_df$growth_ann_pct_num, format = "f",
                                          digits = growth_digits_int), "%")
era_df$growth_label_y_num <- era_df$growth_ann_pct_num + gap_in_num * top_units_per_in_num
if (any(era_df$growth_ann_pct_num < 0)) {
  stop("figure_g_era_timeline.R -- an era has negative median growth; the label and baseline logic assume >= 0.")
}

growth_label_w_in_num <- systemfonts::string_width(era_df$growth_label_chr, family = eig_font_body_chr,
                                                   size = value_pt_num, res = 72, weight = "bold") / 72
if (any(growth_label_w_in_num > era_df$width_in_num - 2 * pad_in_num)) {
  stop("figure_g_era_timeline.R -- a growth label is wider than its bar.")
}

# Bottom panel: y range from zero (a true baseline, matching the
# Datawrapper version) to the data maximum, padded. The era averages sit in
# one row along the top of the panel, centered on their eras, so they
# read as a row of values aligned with the rail (and do not move as new
# months arrive). The build stops if the monthly line would run into a
# label or the row would leave the panel.
bottom_y_lo_num <- 0
bottom_y_hi_num <- ceiling(max(unrate_df$unrate_num)) + 0.8
bottom_units_per_in_num <- (bottom_y_hi_num - bottom_y_lo_num) / bottom_panel_h_in_num

era_df$unrate_label_chr <- paste0(formatC(era_df$unrate_mean_num, format = "f",
                                          digits = unrate_digits_int), "%")
unrate_label_w_in_num <- systemfonts::string_width(era_df$unrate_label_chr, family = eig_font_body_chr,
                                                   size = value_pt_num, res = 72, weight = "bold") / 72
label_half_h_units_num <- (value_h_in_num / 2) * bottom_units_per_in_num
clear_units_num  <- 0.04 * bottom_units_per_in_num
era_df$unrate_label_y_num <- bottom_y_hi_num - label_half_h_units_num - clear_units_num
for (e in seq_len(nrow(era_df))) {
  half_w_days_num <- (unrate_label_w_in_num[e] / 2 + pad_in_num) / in_per_day_num
  in_extent_bool <- abs(as.numeric(unrate_df$date_dt - era_df$xmid_dt[e])) <= half_w_days_num
  lo_num <- era_df$unrate_label_y_num[e] - label_half_h_units_num - clear_units_num
  if (any(unrate_df$unrate_num[in_extent_bool] >= lo_num) ||
      unrate_label_w_in_num[e] > era_df$width_in_num[e] - 2 * pad_in_num) {
    stop("figure_g_era_timeline.R -- the era ", e, " unemployment label collides with the monthly line or overflows its era.")
  }
}

###################################
###   5) Build the figure       ###
###################################

regime_colors_chr <- c(low = low_color_chr, high = high_color_chr)
rule_dates_dt <- era_df$xmin_dt[-1]
# 2 px surface gap between adjacent bars at 300 dpi (1 px each side).
bar_gap_days_num <- (1 / render_dpi_int) / in_per_day_num
era_df$bar_xmin_num <- as.numeric(era_df$xmin_dt) + bar_gap_days_num
era_df$bar_xmax_num <- as.numeric(era_df$xmax_dt) - bar_gap_days_num

rail_df <- dplyr::bind_rows(
  era_df |> dplyr::transmute(xmid_dt, label_chr = rail_name_wrapped_chr,
                             y_num = top_y_hi_num, color_chr = rail_color_chr, face_chr = "bold"),
  era_df |> dplyr::transmute(xmid_dt, label_chr = duration_wrapped_chr,
                             y_num = top_y_hi_num - rail_name_lines_int * line_in_num * top_units_per_in_num,
                             color_chr = muted_color_chr, face_chr = "plain")
)

panel_title_theme <- ggplot2::element_text(family = eig_font_body_chr, size = panel_title_pt_num,
                                           color = muted_color_chr, hjust = 0,
                                           margin = ggplot2::margin(0, 0, 4, 0))
base_theme <- ggplot2::theme_minimal(base_size = axis_pt_num, base_family = eig_font_body_chr) +
  ggplot2::theme(
    panel.grid         = ggplot2::element_blank(),
    panel.border       = ggplot2::element_blank(),
    axis.title         = ggplot2::element_blank(),
    axis.text          = ggplot2::element_text(color = muted_color_chr, size = axis_pt_num),
    legend.position    = "none",
    plot.title         = panel_title_theme,
    plot.title.position = "panel",
    plot.margin        = ggplot2::margin(2, plot_margin_pt_num, 2, plot_margin_pt_num, unit = "pt")
  )

top_plot <- ggplot2::ggplot(era_df) +
  ggplot2::geom_vline(xintercept = rule_dates_dt, linetype = "dashed", linewidth = 0.3,
                      color = rule_color_chr) +
  ggplot2::geom_rect(
    ggplot2::aes(xmin = as.Date(bar_xmin_num), xmax = as.Date(bar_xmax_num),
                 ymin = 0, ymax = growth_ann_pct_num, fill = regime_chr),
    color = NA
  ) +
  ggplot2::geom_hline(yintercept = 0, linewidth = 0.35, color = baseline_color_chr) +
  ggplot2::geom_text(
    ggplot2::aes(x = xmid_dt, y = growth_label_y_num, label = growth_label_chr),
    vjust = 0, color = ink_color_chr, fontface = "bold", size = value_pt_num * mm_per_pt_num,
    family = eig_font_body_chr
  ) +
  ggplot2::geom_text(
    data = rail_df,
    ggplot2::aes(x = xmid_dt, y = y_num, label = label_chr, color = color_chr, fontface = face_chr),
    vjust = 1, lineheight = line_h_factor_num, size = rail_pt_num * mm_per_pt_num,
    family = eig_font_body_chr
  ) +
  ggplot2::scale_fill_manual(values = regime_colors_chr) +
  ggplot2::scale_color_identity() +
  ggplot2::scale_x_date(limits = c(first_dt, era_df$xmax_dt[5]), expand = c(0, 0)) +
  ggplot2::scale_y_continuous(limits = c(0, top_y_hi_num), expand = c(0, 0)) +
  ggplot2::labs(title = "Median real hourly wage growth, % per year") +
  ggplot2::coord_cartesian(clip = "off") +
  base_theme +
  ggplot2::theme(axis.text = ggplot2::element_blank())

bottom_plot <- ggplot2::ggplot() +
  ggplot2::geom_hline(yintercept = unrate_breaks_num[!unrate_breaks_num %in% c(0, threshold_num)],
                      linewidth = 0.3, color = grid_color_chr) +
  ggplot2::geom_hline(yintercept = 0, linewidth = 0.35, color = baseline_color_chr) +
  ggplot2::geom_vline(xintercept = rule_dates_dt, linetype = "dashed", linewidth = 0.3,
                      color = rule_color_chr) +
  ggplot2::geom_hline(yintercept = threshold_num, linetype = "dashed", linewidth = 0.4,
                      color = ref_color_chr) +
  ggplot2::geom_line(data = unrate_df, ggplot2::aes(x = date_dt, y = unrate_num),
                     color = monthly_color_chr, linewidth = 0.45) +
  ggplot2::geom_segment(
    data = era_df,
    ggplot2::aes(x = as.Date(bar_xmin_num), xend = as.Date(bar_xmax_num),
                 y = unrate_mean_num, yend = unrate_mean_num, color = regime_chr),
    linewidth = 1.6, lineend = "butt"
  ) +
  ggplot2::geom_text(
    data = era_df,
    ggplot2::aes(x = xmid_dt, y = unrate_label_y_num, label = unrate_label_chr),
    vjust = 0.5, color = ink_color_chr, fontface = "bold", size = value_pt_num * mm_per_pt_num,
    family = eig_font_body_chr
  ) +
  ggplot2::scale_color_manual(values = regime_colors_chr) +
  ggplot2::scale_x_date(limits = c(first_dt, era_df$xmax_dt[5]), expand = c(0, 0),
                        breaks = seq(as.Date("1985-01-01"), last_dt, by = "5 years"),
                        date_labels = "%Y") +
  ggplot2::scale_y_continuous(limits = c(bottom_y_lo_num, bottom_y_hi_num), breaks = unrate_breaks_num,
                              labels = paste0(unrate_breaks_num, "%"), expand = c(0, 0)) +
  ggplot2::labs(title = "Unemployment rate: monthly (thin line) and era average (thick line, value along the top); dashed line at 5%") +
  ggplot2::coord_cartesian(clip = "off") +
  base_theme +
  ggplot2::theme(axis.ticks.x = ggplot2::element_line(color = muted_color_chr, linewidth = 0.3),
                 axis.ticks.length.x = grid::unit(3, "pt"))

annotation_theme <- ggplot2::theme(
  plot.title    = ggplot2::element_text(family = eig_font_title_chr, face = "bold", size = title_pt_num,
                                        hjust = 0, margin = ggplot2::margin(0, 0, 4, 0)),
  plot.subtitle = ggplot2::element_text(family = eig_font_body_chr, size = subtitle_pt_num,
                                        hjust = 0, margin = ggplot2::margin(0, 0, 10, 0)),
  plot.caption  = ggplot2::element_text(family = eig_font_body_chr, size = caption_pt_num,
                                        color = caption_color_chr, hjust = 0, lineheight = 1.1,
                                        margin = ggplot2::margin(10, 0, 0, 0)),
  plot.title.position   = "plot",
  plot.caption.position = "plot",
  plot.margin = ggplot2::margin(10, 6, 8, 6, unit = "pt")
)

fig_plot <- patchwork::wrap_plots(top_plot, bottom_plot, ncol = 1) +
  patchwork::plot_layout(heights = c(top_panel_h_in_num, bottom_panel_h_in_num)) +
  patchwork::plot_annotation(title = wrapped_chr[["title"]], subtitle = wrapped_chr[["subtitle"]],
                             caption = wrapped_chr[["caption"]], theme = annotation_theme)

# Height: panels plus every measured text block, the two panel titles,
# the x axis, and the margins.
fig_height_in_num <- top_panel_h_in_num + bottom_panel_h_in_num +
  wrapped_lines_int[["title"]]    * title_pt_num    * line_h_factor_num / 72 +
  wrapped_lines_int[["subtitle"]] * subtitle_pt_num * line_h_factor_num / 72 +
  wrapped_lines_int[["caption"]]  * caption_pt_num  * 1.1 * line_h_factor_num / 72 +
  2 * (panel_title_pt_num * line_h_factor_num + 4) / 72 +
  (axis_pt_num * line_h_factor_num + 6) / 72 +
  (10 + 8 + 4 + 10 + 10 + 8) / 72

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
###   6) Table and verification ###
###################################

era_out_df <- era_df |>
  dplyr::transmute(
    era_i_int, era_slug_chr, era_name_chr = rail_name_chr, era_start_dt, era_end_dt,
    duration_months_int, growth_ann_pct_num, growth_cum_pct_num,
    unrate_mean_num, unrate_obs_int, months_at_or_below_5_int, low_unemp_bool
  )
readr::write_csv(era_out_df, table_out_path_chr)

if (!fs::file_exists(png_path_chr) || fs::file_size(png_path_chr) == 0 ||
    !fs::file_exists(table_out_path_chr)) {
  stop("figure_g_era_timeline.R -- an output was not written.")
}

message(
  "figure_g_era_timeline.R -- wrote ", png_path_chr, " (", round(render_width_in_num, 2), " x ",
  round(fig_height_in_num, 2), " in) and ", table_out_path_chr, ". Eras: ",
  paste0(era_df$era_i_int, " ", era_df$duration_months_int, " mo, ", era_df$growth_label_chr,
         "/yr, UR ", era_df$unrate_label_chr, collapse = "; ")
)
