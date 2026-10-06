# figure_c_generation -- weighted real hourly wage median by age and generation
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

rm(list = ls())
options(scipen = 999)
set.seed(42)

# Sourced by run_all.R inside new.env(parent = globalenv()).
#
# Reads the year-partitioned real-wage panel written by 02a,
# classifies each person-year into one of five generations, and
# computes the EARNWT-weighted median real hourly wage per
# (age, generation) cell pooled across observation years.
# Outputs:
#   output/figures/figure_c_generation.png
#   output/tables/figure_c_generation.csv  (one row per generation,
#                                           columns p50 by age)
#
# Reads microdata rather than aggregating 02b's panel: a weighted mean
# of year x age x sex x generation cell medians only approximates the
# true age x generation weighted median.
#
# Generation cutoffs (Pew Research via Dimock 2019):
#   Silent:     BIRTHYR <= 1945
#   Boomers:    1946 <= BIRTHYR <= 1964
#   Gen X:      1965 <= BIRTHYR <= 1980
#   Millennials:1981 <= BIRTHYR <= 1996
#   Gen Z:      BIRTHYR >= 1997
#
# Weighted median uses the shared weighted_quantile() helper (Stata
# `_pctile` / EPI no-interpolation convention; see
# code/_utils/weighted_stats.R). Palette: 2022 primary EIG tokens via
# load_palette.R.
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
fig_png_chr         <- fs::path(fig_out_dir_chr, "figure_c_generation.png")
fig_csv_chr         <- fs::path(tbl_out_dir_chr, "figure_c_generation.csv")

# Generation cutoffs. Four cutoffs -> five generations.
silent_boomer_cutoff_int     <- 1945L
boomer_genx_cutoff_int       <- 1964L
genx_millennial_cutoff_int   <- 1980L
millennial_genz_cutoff_int   <- 1996L

# Generation display order (oldest to youngest).
generation_levels_chr <- c(
  "Silent",
  "Boomers",
  "Gen X",
  "Millennials",
  "Gen Z"
)

# 2022 primary palette tokens, one per generation.
generation_colors_chr <- c(
  "Silent"      = unname(eig_palette_2022_primary["eig_blue_800"]),
  "Boomers"     = unname(eig_palette_2022_primary["eig_cyan_700"]),
  "Gen X"       = unname(eig_palette_2022_primary["eig_green_700"]),
  "Millennials" = unname(eig_palette_2022_primary["eig_purple_800"]),
  "Gen Z"       = unname(eig_palette_2022_primary["eig_gold_600"])
)

fs::dir_create(fig_out_dir_chr, recurse = TRUE)
fs::dir_create(tbl_out_dir_chr, recurse = TRUE)

###################################
###   1) Load real-wage panel   ###
###################################

if (!fs::dir_exists(panel_in_dir_chr)) {
  stop(
    "figure_c_generation.R -- real-wage panel not found at ",
    panel_in_dir_chr, ". Run 02a_build_real_wages.R first."
  )
}

# Explicit parquet-only file list — the partition dirs also contain
# part-0.rds sidecars (EIG dual-format convention) which arrow cannot
# parse. YEAR lives inside each parquet as a column.
parquet_paths_chr <- fs::dir_ls(
  panel_in_dir_chr,
  regexp = "part-0\\.parquet$",
  recurse = TRUE,
  type   = "file"
)

if (length(parquet_paths_chr) == 0L) {
  stop(
    "figure_c_generation.R -- no part-0.parquet files found under ",
    panel_in_dir_chr, ". Run 02a_build_real_wages.R first."
  )
}

real_wage_ds <- arrow::open_dataset(parquet_paths_chr, format = "parquet")

real_wage_df <- real_wage_ds |>
  dplyr::select(YEAR, MONTH, AGE, BIRTHYR, EARNWT, real_hourly_wage_num) |>
  dplyr::collect()

required_cols_chr <- c("YEAR", "MONTH", "AGE", "BIRTHYR", "EARNWT", "real_hourly_wage_num")
missing_cols_chr  <- setdiff(required_cols_chr, names(real_wage_df))

if (length(missing_cols_chr) > 0L) {
  stop(
    "figure_c_generation.R -- real-wage panel missing column(s): ",
    paste(missing_cols_chr, collapse = ", ")
  )
}

message(
  "figure_c_generation.R -- loaded ",
  format(nrow(real_wage_df), big.mark = ","),
  " person-year records spanning ",
  min(real_wage_df$YEAR, na.rm = TRUE), "-",
  max(real_wage_df$YEAR, na.rm = TRUE)
)

###################################
###   2) Classify generations   ###
###################################
# Four cutoffs -> five generations. Missing BIRTHYR is set to
# NA_character_ and excluded by the validity mask.

real_wage_df <- real_wage_df |>
  dplyr::mutate(
    generation_chr = dplyr::case_when(
      BIRTHYR <= silent_boomer_cutoff_int                ~ "Silent",
      BIRTHYR >  silent_boomer_cutoff_int &
        BIRTHYR <= boomer_genx_cutoff_int                ~ "Boomers",
      BIRTHYR >  boomer_genx_cutoff_int &
        BIRTHYR <= genx_millennial_cutoff_int            ~ "Gen X",
      BIRTHYR >  genx_millennial_cutoff_int &
        BIRTHYR <= millennial_genz_cutoff_int            ~ "Millennials",
      BIRTHYR >  millennial_genz_cutoff_int              ~ "Gen Z",
      TRUE                                               ~ NA_character_
    )
  )

n_missing_gen_int <- sum(is.na(real_wage_df$generation_chr))

if (n_missing_gen_int > 0L) {
  message(
    "figure_c_generation.R -- ", format(n_missing_gen_int, big.mark = ","),
    " person-year records have no generation classification (missing ",
    "BIRTHYR); these rows will be excluded by the validity mask."
  )
}

###################################
###   3) Apply validity mask    ###
###################################
# Drop rows with missing generation, missing age, missing real wage,
# missing weight, or non-positive weight before aggregation. Explicit
# boolean mask per EIG coding standard (no filter() chain).

valid_bool <- !is.na(real_wage_df$generation_chr) &
  !is.na(real_wage_df$AGE) &
  !is.na(real_wage_df$real_hourly_wage_num) &
  !is.na(real_wage_df$EARNWT) &
  real_wage_df$EARNWT > 0

n_valid_int <- sum(valid_bool)

if (n_valid_int == 0L) {
  stop(
    "figure_c_generation.R -- no valid person-year observations after ",
    "applying the validity mask. Check 02a output and BIRTHYR coverage."
  )
}

message(
  "figure_c_generation.R -- validity mask retains ",
  format(n_valid_int, big.mark = ","), " of ",
  format(nrow(real_wage_df), big.mark = ","),
  " person-year records"
)

###################################
###   4) Weighted median by cell###
###################################
# Pool across all observation years. A single (AGE, generation_chr) cell
# contains every person-month observation where the respondent was that
# age and belongs to that generation. Because the cell pools many survey
# months across years, earnwt_cell_num divides the summed weight by the
# number of distinct (YEAR, MONTH) survey months (weighted_population())
# so it reports an average monthly population rather than a months-times
# inflated count.

gen_age_panel_df <- real_wage_df[valid_bool, , drop = FALSE] |>
  dplyr::group_by(AGE, generation_chr) |>
  dplyr::summarise(
    n_cell_int                  = dplyr::n(),
    earnwt_cell_num             = weighted_population(EARNWT, YEAR, MONTH),
    real_hourly_wage_median_num = weighted_quantile(
      real_hourly_wage_num, EARNWT, 0.50
    ),
    .groups = "drop"
  ) |>
  dplyr::rename(age_int = AGE) |>
  dplyr::mutate(
    age_int        = as.integer(age_int),
    generation_fct = factor(generation_chr, levels = generation_levels_chr)
  ) |>
  dplyr::arrange(generation_fct, age_int)

if (nrow(gen_age_panel_df) == 0L) {
  stop(
    "figure_c_generation.R -- grouped panel has zero rows after summarise; ",
    "the validity mask removed every cell. Investigate 02a output."
  )
}

message(
  "figure_c_generation.R -- computed weighted medians for ",
  nrow(gen_age_panel_df), " age x generation cells; ages ",
  min(gen_age_panel_df$age_int), "-", max(gen_age_panel_df$age_int),
  " across ", length(unique(gen_age_panel_df$generation_chr)), " generations"
)

###################################
###   5) Validate axis ranges   ###
###################################
# The outlier trim bounds are applied to the HOURLY wage (Schmitt 2003
# CEPR convention for the lower bound): $0.50 to $200 in 1989 dollars
# (Departure #5; the $200 upper supersedes EPI's $100), roughly $1.10
# to $442 per hour in December 2025 PCE dollars via
# PCEPI(Dec 1989)/PCEPI(Dec 2025). Generation-age cell medians should
# fall comfortably inside this range.

wage_min_num <- min(gen_age_panel_df$real_hourly_wage_median_num, na.rm = TRUE)
wage_max_num <- max(gen_age_panel_df$real_hourly_wage_median_num, na.rm = TRUE)

if (is.na(wage_min_num) || wage_min_num <= 0) {
  stop(
    "figure_c_generation.R -- computed cell-median minimum is not ",
    "positive (", wage_min_num, "); abort before rendering."
  )
}

# 250 is a generous sanity ceiling: it sits well below the applied
# $442/hr upper trim bound yet far above any plausible age x generation
# cell median in a normal run.
if (is.na(wage_max_num) || wage_max_num > 250) {
  stop(
    "figure_c_generation.R -- computed cell-median maximum exceeds ",
    "$250/hr (", wage_max_num, "); likely an outlier-trim or deflator ",
    "misconfiguration. Abort before rendering."
  )
}

message(
  "figure_c_generation.R -- cell-median range: $",
  format(round(wage_min_num, 2), big.mark = ","), " to $",
  format(round(wage_max_num, 2), big.mark = ",")
)

###################################
###   6) Coverage verification  ###
###################################
# Every generation observed in the valid input should have at least one
# non-NA median in the output panel. A generation absent from the panel
# but present in the input signals a silent aggregation failure.
# Generations absent from the input entirely (e.g., Gen Z in early-year
# sub-samples) log a note but do not fail.

observed_gens_chr <- sort(unique(real_wage_df$generation_chr[valid_bool]))

panel_gens_with_median_chr <- sort(unique(
  gen_age_panel_df$generation_chr[!is.na(gen_age_panel_df$real_hourly_wage_median_num)]
))

missing_from_panel_chr <- setdiff(observed_gens_chr, panel_gens_with_median_chr)

if (length(missing_from_panel_chr) > 0L) {
  stop(
    "figure_c_generation.R -- generation(s) present in valid input but ",
    "absent from the output panel: ",
    paste(missing_from_panel_chr, collapse = ", ")
  )
}

unobserved_gens_chr <- setdiff(generation_levels_chr, observed_gens_chr)

if (length(unobserved_gens_chr) > 0L) {
  message(
    "figure_c_generation.R -- generation(s) not observed in valid input ",
    "(will not appear in plot): ",
    paste(unobserved_gens_chr, collapse = ", ")
  )
}

###################################
###   7) Render ggplot          ###
###################################

fig_c_plot <- ggplot2::ggplot(
  gen_age_panel_df,
  ggplot2::aes(
    x     = age_int,
    y     = real_hourly_wage_median_num,
    color = generation_fct
  )
) +
  ggplot2::geom_line(linewidth = 0.9) +
  ggplot2::scale_color_manual(
    values = generation_colors_chr,
    name   = "Generation"
  ) +
  ggplot2::scale_y_continuous(
    labels = scales::label_dollar(accuracy = 1L)
  ) +
  ggplot2::scale_x_continuous(
    breaks = seq(
      floor(min(gen_age_panel_df$age_int) / 5L) * 5L,
      ceiling(max(gen_age_panel_df$age_int) / 5L) * 5L,
      by = 5L
    )
  ) +
  ggplot2::labs(
    title    = "Figure 3. Real hourly wage median by age and generation",
    subtitle = "Weighted median real hourly wages in December 2025 PCE dollars, by age and generation",
    x        = "Age (years)",
    y        = "Real hourly wage (Dec 2025 $)",
    caption  = stringr::str_wrap(
      paste0(
        "Source: IPUMS-CPS ORG, 1982 to latest; BEA PCEPI via FRED. ",
        "Sample: civilian wage-and-salary workers age 16 and older with ",
        "EARNWT > 0. ",
        "Generations: Silent (birth year 1945 and earlier), Boomers (1946 ",
        "to 1964), Gen X (1965 to 1980), Millennials (1981 to 1996), Gen Z ",
        "(1997 onward), per Pew Research Center. Census-imputed ",
        "(allocated) earnings records are retained, matching EPI's public ",
        "extract. October 2025 data not collected due to federal government ",
        "shutdown. Cell medians are point estimates."
      ),
      width = 130
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
###   8) Write PNG + CSV        ###
###################################

ggplot2::ggsave(
  filename = fig_png_chr,
  plot     = fig_c_plot,
  width    = 8.5,
  height   = 5.2,
  units    = "in",
  dpi      = 300L,
  device   = eig_png_device
)

# Wide CSV: one row per age_int, one column per generation (Datawrapper
# convention). Snake-case column names handle the "Gen X" space and are
# robust across downstream consumers. Order matches generation_levels_chr
# (oldest generation first, youngest last).
generation_column_names_chr <- c(
  "Silent"      = "silent",
  "Boomers"     = "boomers",
  "Gen X"       = "gen_x",
  "Millennials" = "millennials",
  "Gen Z"       = "gen_z"
)
generation_column_order_chr <-
  unname(generation_column_names_chr[generation_levels_chr])

gen_age_wide_df <- gen_age_panel_df |>
  dplyr::mutate(
    generation_col_chr =
      unname(generation_column_names_chr[generation_chr])
  ) |>
  dplyr::select(
    age_int, generation_col_chr, real_hourly_wage_median_num
  ) |>
  tidyr::pivot_wider(
    names_from  = generation_col_chr,
    values_from = real_hourly_wage_median_num
  )

# Guarantee every generation column exists even if a given column had
# no observations (defensive against future panels where a generation
# is entirely missing). Missing columns are added as all-NA.
missing_cols_chr <- setdiff(
  generation_column_order_chr, names(gen_age_wide_df)
)
for (col_chr in missing_cols_chr) {
  gen_age_wide_df[[col_chr]] <- NA_real_
}

gen_age_wide_df <- gen_age_wide_df |>
  dplyr::select(
    age_int,
    dplyr::all_of(generation_column_order_chr)
  ) |>
  dplyr::arrange(age_int)

readr::write_csv(gen_age_wide_df, fig_csv_chr)

message(
  "figure_c_generation.R -- wrote PNG (", fig_png_chr,
  ") and wide CSV (", fig_csv_chr, ")"
)

###################################
###   9) Verify outputs exist   ###
###################################

if (!fs::file_exists(fig_png_chr)) {
  stop("figure_c_generation.R -- PNG was not written: ", fig_png_chr)
}
if (!fs::file_exists(fig_csv_chr)) {
  stop("figure_c_generation.R -- CSV was not written: ", fig_csv_chr)
}

message("figure_c_generation.R -- done.")
