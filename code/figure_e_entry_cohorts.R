# figure_e_entry_cohorts -- weighted real hourly wage trajectory by 5-year labor-market-entry cohort
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

rm(list = ls())
options(scipen = 999)
set.seed(42)

# Sourced by run_all.R inside new.env(parent = globalenv()).
#
# Reads the year-partitioned real-wage panel written by 02a and builds a
# SYNTHETIC COHORT (pseudo-panel). CPS ORG is repeated cross-sections,
# not a longitudinal panel, so individual workers cannot be followed
# over time. Instead each person-year is assigned to a labor-market-
# entry cohort by the year that person turned `entry_age_int` (a proxy
# for entry: entry_year = BIRTHYR + entry_age_int), binned into 5-year
# groups anchored at 1982. The EARNWT-weighted median real hourly wage
# is then tracked by (entry cohort x age) across successive survey
# years. The unequal observation windows across cohorts are intended:
# the 1982 entrants are observed nearly age 22 to 63; the most recent
# entrants only to their late twenties.
#
# Outputs:
#   output/figures/figure_e_entry_cohorts_level.png    -- real $ by age
#   output/figures/figure_e_entry_cohorts_indexed.png  -- indexed, entry age = 100
#   output/tables/figure_e_entry_cohorts_level.csv      -- wide age x cohort, real $
#   output/tables/figure_e_entry_cohorts_indexed.csv    -- wide age x cohort, index
#   output/figures/figure_e_entry_cohort_growth_bars.png -- bar chart,
#       annualized prime-age real wage growth by entry cohort
#   output/tables/figure_e_entry_cohort_growth.csv      -- one row per cohort:
#       observed prime-age span and annualized real wage growth
#
# Weighted median uses the shared weighted_quantile() helper (Stata
# `_pctile` / EPI no-interpolation convention; see
# code/_utils/weighted_stats.R), matching figure_b and figure_c. Cohort
# colors are a sequential ramp interpolated from 2022 primary EIG palette
# tokens
# (oldest cohort darkest, newest cohort lightest) via load_palette.R and
# grDevices::colorRampPalette, so the figure remains token-derived per
# the EIG figure-style rules.
#
# Caveat carried in the caption: cohort medians are conditional on being
# an employed wage-and-salary worker at each age, so cohort composition
# shifts with age (labor-force entry/exit, mortality, immigration). The
# entry-age proxy assumes a common entry age and does not model schooling
# or delayed entry.
#
# No custom functions are defined; all transformations are inline.

source(here::here("code", "_utils", "00_packages.R"))
source(here::here("code", "_utils", "load_palette.R"))
source(here::here("code", "_utils", "eig_fonts.R"))

# ggrepel places the direct end-of-line cohort labels without overlap.
# Not in the shared manifest; only the figure scripts that direct-label
# need it, so it is guarded here rather than loaded in 00_packages.R.
if (!requireNamespace("ggrepel", quietly = TRUE)) {
  stop(
    "figure_e_entry_cohorts.R -- the `ggrepel` package is required for the ",
    "direct end-of-line cohort labels but is not installed. Install with ",
    "install.packages('ggrepel')."
  )
}

###################################
###   Configuration             ###
###################################

panel_in_dir_chr    <- here::here("data", "intermediate", "cps_real_wages")
fig_out_dir_chr     <- here::here("output", "figures")
tbl_out_dir_chr     <- here::here("output", "tables")

fig_level_png_chr   <- fs::path(fig_out_dir_chr,
  "figure_e_entry_cohorts_level.png")
fig_index_png_chr   <- fs::path(fig_out_dir_chr,
  "figure_e_entry_cohorts_indexed.png")
fig_level_csv_chr   <- fs::path(tbl_out_dir_chr,
  "figure_e_entry_cohorts_level.csv")
fig_index_csv_chr   <- fs::path(tbl_out_dir_chr,
  "figure_e_entry_cohorts_indexed.csv")
fig_growth_csv_chr  <- fs::path(tbl_out_dir_chr,
  "figure_e_entry_cohort_growth.csv")
fig_cal_png_chr     <- fs::path(fig_out_dir_chr,
  "figure_e_entry_cohorts_calendar.png")
fig_cal_csv_chr     <- fs::path(tbl_out_dir_chr,
  "figure_e_entry_cohorts_calendar.csv")
fig_bars_png_chr    <- fs::path(fig_out_dir_chr,
  "figure_e_entry_cohort_growth_bars.png")

# Entry proxied by the year the worker turned `entry_age_int`. 22 ~= a
# four-year-college completion age; disclosed in the caption.
entry_age_int          <- 22L

# 5-year entry-cohort bins anchored at 1982 (the first CPS-ORG year).
# Cohorts entering before 1982 are excluded -- their age-22 wage is not
# observable in this panel, so an entry-anchored trajectory cannot start
# at the entry age.
cohort_anchor_year_int <- 1982L
cohort_bin_width_int   <- 5L

# Prime-age observation window. Cohorts are still identified by entry
# (birth year + entry_age_int = 22), but their wage trajectories are
# shown only over the conventional prime working ages 25-54. This drops
# the 22-24 labor-market-transition years and, more importantly, the
# 55-plus near-retirement years where labor-force exit and selection
# distort the median wage. The entry-age proxy (22) is used for cohort
# labeling only; it is no longer the start of the plotted window.
age_min_int            <- 25L
age_max_int            <- 54L

# Minimum weighted-cell observation count. (cohort x age) cells thinner
# than this are set to NA before plotting and growth calculation, so a
# single noisy cell cannot drive a trajectory endpoint.
min_cell_n_int         <- 30L

# A cohort needs at least this many non-NA (post-guard) age cells before
# an annualized growth rate is reported. Below this the observed career
# is too short to fit a slope; the cohort still appears in the figure as
# a short line.
min_cohort_ages_int    <- 3L

# Index base value (entry age = 100) for the indexed trajectory.
index_base_num         <- 100

# Wage-stagnation periods (literature-standard windows), inclusive on
# both ends. Band 1 is the long real-wage stagnation from the early
# 1980s through the mid-1990s; band 2 is the 2000s / Great Recession
# plateau. These define both the shaded regions in the calendar-time
# figure and the per-cohort stagnation-exposure share. Edit the four
# years to re-scope; downstream membership is rebuilt from them.
band1_start_int        <- 1982L
band1_end_int          <- 1995L
band2_start_int        <- 2002L
band2_end_int          <- 2014L

# Flattened set of stagnation calendar years, rebuilt from the band
# bounds above. Used for the exposure-share denominator/numerator.
stagnation_years_int   <- c(
  seq(band1_start_int, band1_end_int),
  seq(band2_start_int, band2_end_int)
)

# Matched early-prime-age window for the cohort-comparable growth
# measure. Holding the age range fixed across cohorts isolates the
# calendar (stagnation-exposure) effect from the lifecycle wage-age
# concavity and from the differing observation-window lengths. Age 34 is
# the deepest common early-prime age most cohorts reach within the
# panel; cohorts that have not yet reached it report NA for the matched
# measure.
matched_start_age_int  <- 25L
matched_end_age_int    <- 34L

fs::dir_create(fig_out_dir_chr, recurse = TRUE)
fs::dir_create(tbl_out_dir_chr, recurse = TRUE)

###################################
###   1) Load real-wage panel   ###
###################################

if (!fs::dir_exists(panel_in_dir_chr)) {
  stop(
    "figure_e_entry_cohorts.R -- real-wage panel not found at ",
    panel_in_dir_chr, ". Run 02a_build_real_wages.R first."
  )
}

# Explicit parquet-only file list -- the partition dirs also contain
# part-0.rds sidecars (EIG dual-format convention) which arrow cannot
# parse. YEAR lives inside each parquet as a column.
parquet_paths_chr <- fs::dir_ls(
  panel_in_dir_chr,
  regexp  = "part-0\\.parquet$",
  recurse = TRUE,
  type    = "file"
)

if (length(parquet_paths_chr) == 0L) {
  stop(
    "figure_e_entry_cohorts.R -- no part-0.parquet files found under ",
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
    "figure_e_entry_cohorts.R -- real-wage panel missing column(s): ",
    paste(missing_cols_chr, collapse = ", ")
  )
}

message(
  "figure_e_entry_cohorts.R -- loaded ",
  format(nrow(real_wage_df), big.mark = ","),
  " person-year records spanning ",
  min(real_wage_df$YEAR, na.rm = TRUE), "-",
  max(real_wage_df$YEAR, na.rm = TRUE)
)

###################################
###   2) Assign entry cohorts   ###
###################################
# entry_year = BIRTHYR + entry_age_int. Bins are left-closed, 5 years
# wide, anchored at cohort_anchor_year_int. A 1982-anchored width-5
# scheme yields 1982-1986, 1987-1991, ..., so the named entry years
# 1982, 2001, and 2016 fall in the 1982-1986, 1997-2001, and 2012-2016
# bins respectively. Entry years before the anchor are set to NA cohort
# and dropped (age-22 wage unobservable in this panel).

real_wage_df <- real_wage_df |>
  dplyr::mutate(
    entry_year_int    = BIRTHYR + entry_age_int,
    cohort_start_int  = dplyr::if_else(
      !is.na(entry_year_int) & entry_year_int >= cohort_anchor_year_int,
      cohort_anchor_year_int +
        ((entry_year_int - cohort_anchor_year_int) %/% cohort_bin_width_int) *
          cohort_bin_width_int,
      NA_integer_
    ),
    cohort_end_int    = cohort_start_int + cohort_bin_width_int - 1L,
    cohort_label_chr  = dplyr::if_else(
      !is.na(cohort_start_int),
      paste0(cohort_start_int, "-", cohort_end_int),
      NA_character_
    )
  )

n_missing_cohort_int <- sum(is.na(real_wage_df$cohort_label_chr))

if (n_missing_cohort_int > 0L) {
  message(
    "figure_e_entry_cohorts.R -- ",
    format(n_missing_cohort_int, big.mark = ","),
    " person-year records have no entry cohort (missing BIRTHYR or entry ",
    "year before ", cohort_anchor_year_int, "); excluded by the validity mask."
  )
}

###################################
###   3) Apply validity mask    ###
###################################
# Keep rows with a valid cohort, a valid age inside the career window,
# a valid real hourly wage, and a positive weight. Explicit boolean
# mask per EIG coding standard (no filter() chain).

valid_bool <- !is.na(real_wage_df$cohort_label_chr) &
  !is.na(real_wage_df$AGE) &
  real_wage_df$AGE >= age_min_int &
  real_wage_df$AGE <= age_max_int &
  !is.na(real_wage_df$real_hourly_wage_num) &
  !is.na(real_wage_df$EARNWT) &
  real_wage_df$EARNWT > 0

n_valid_int <- sum(valid_bool)

if (n_valid_int == 0L) {
  stop(
    "figure_e_entry_cohorts.R -- no valid person-year observations after ",
    "applying the validity mask. Check 02a output, BIRTHYR coverage, and ",
    "the [", age_min_int, ", ", age_max_int, "] age window."
  )
}

message(
  "figure_e_entry_cohorts.R -- validity mask retains ",
  format(n_valid_int, big.mark = ","), " of ",
  format(nrow(real_wage_df), big.mark = ","),
  " person-year records (ages ", age_min_int, "-", age_max_int, ")"
)

###################################
###   4) Weighted median cells  ###
###################################
# Group by (cohort x age) and compute the EARNWT-weighted median real
# hourly wage. A single (cohort, age) cell pools the up-to-5 birth years
# in the cohort bin, each observed at that age in its own survey year.

cohort_age_df <- real_wage_df[valid_bool, , drop = FALSE] |>
  dplyr::group_by(cohort_start_int, cohort_end_int, cohort_label_chr, AGE) |>
  dplyr::summarise(
    n_cell_int                  = dplyr::n(),
    earnwt_cell_num             = weighted_population(EARNWT, YEAR, MONTH),
    real_hourly_wage_median_num = weighted_quantile(
      real_hourly_wage_num, EARNWT, 0.50
    ),
    .groups = "drop"
  ) |>
  dplyr::rename(age_int = AGE) |>
  dplyr::mutate(age_int = as.integer(age_int)) |>
  dplyr::arrange(cohort_start_int, age_int)

if (nrow(cohort_age_df) == 0L) {
  stop(
    "figure_e_entry_cohorts.R -- grouped panel has zero rows after ",
    "summarise; the validity mask removed every cell. Investigate 02a output."
  )
}

# Small-cell guard: blank out medians from thin cells so they neither
# render nor enter the growth fit. The weight and count are retained for
# the CSV audit trail.
thin_cell_bool <- cohort_age_df$n_cell_int < min_cell_n_int
n_thin_int     <- sum(thin_cell_bool)

if (n_thin_int > 0L) {
  message(
    "figure_e_entry_cohorts.R -- ", n_thin_int, " of ",
    nrow(cohort_age_df), " (cohort x age) cells fall below the ",
    min_cell_n_int, "-observation minimum and are set to NA before ",
    "plotting and growth calculation."
  )
  cohort_age_df$real_hourly_wage_median_num[thin_cell_bool] <- NA_real_
}

# Canonical cohort order (oldest entry cohort first) for factor levels,
# color assignment, and CSV column order.
cohort_levels_chr <- cohort_age_df |>
  dplyr::distinct(cohort_start_int, cohort_label_chr) |>
  dplyr::arrange(cohort_start_int) |>
  dplyr::pull(cohort_label_chr)

cohort_age_df <- cohort_age_df |>
  dplyr::mutate(
    cohort_fct = factor(cohort_label_chr, levels = cohort_levels_chr)
  )

message(
  "figure_e_entry_cohorts.R -- ", length(cohort_levels_chr),
  " entry cohorts (", cohort_levels_chr[1], " to ",
  cohort_levels_chr[length(cohort_levels_chr)], "); ",
  nrow(cohort_age_df), " (cohort x age) cells; ages ",
  min(cohort_age_df$age_int), "-", max(cohort_age_df$age_int)
)

###################################
###   4b) Calendar-year panel   ###
###################################
# Second aggregation grouping the same masked microdata by
# (cohort x calendar YEAR) instead of (cohort x age). This is what the
# stagnation-exposure story needs: holding calendar fixed across cohorts
# shows that older cohorts' wage lines pass through the stagnation bands
# during their prime wage-building years, while younger cohorts only
# appear after the bands. Within one (cohort, YEAR) cell the 5 birth
# years of the cohort sit at 5 adjacent ages; the weighted median across
# them is the cohort's wage that calendar year. Same small-cell guard as
# the age panel.

cohort_year_df <- real_wage_df[valid_bool, , drop = FALSE] |>
  dplyr::group_by(cohort_start_int, cohort_end_int, cohort_label_chr, YEAR) |>
  dplyr::summarise(
    n_cell_int                  = dplyr::n(),
    earnwt_cell_num             = weighted_population(EARNWT, YEAR, MONTH),
    real_hourly_wage_median_num = weighted_quantile(
      real_hourly_wage_num, EARNWT, 0.50
    ),
    .groups = "drop"
  ) |>
  dplyr::rename(year_int = YEAR) |>
  dplyr::mutate(year_int = as.integer(year_int))

thin_year_cell_bool <- cohort_year_df$n_cell_int < min_cell_n_int
if (sum(thin_year_cell_bool) > 0L) {
  cohort_year_df$real_hourly_wage_median_num[thin_year_cell_bool] <- NA_real_
}

cohort_year_df <- cohort_year_df |>
  dplyr::mutate(
    cohort_fct = factor(cohort_label_chr, levels = cohort_levels_chr)
  ) |>
  dplyr::arrange(cohort_start_int, year_int)

message(
  "figure_e_entry_cohorts.R -- calendar-year panel: ",
  nrow(cohort_year_df), " (cohort x year) cells spanning ",
  min(cohort_year_df$year_int), "-", max(cohort_year_df$year_int)
)

###################################
###   5) Validate wage range    ###
###################################
# The hourly EPI trim bounds ($0.50 to $200 in 1989 PCE dollars) map to
# roughly $1.10 to $442 per hour in December 2025 PCE dollars. Cohort-age
# cell medians should sit comfortably inside that range; values outside
# signal a deflator or trim misconfiguration upstream. The $250 ceiling
# mirrors the figure_b / figure_c sanity check.

wage_min_num <- min(cohort_age_df$real_hourly_wage_median_num, na.rm = TRUE)
wage_max_num <- max(cohort_age_df$real_hourly_wage_median_num, na.rm = TRUE)

if (is.na(wage_min_num) || wage_min_num <= 0) {
  stop(
    "figure_e_entry_cohorts.R -- computed cell-median minimum is not ",
    "positive (", wage_min_num, "); abort before rendering."
  )
}

if (is.na(wage_max_num) || wage_max_num > 250) {
  stop(
    "figure_e_entry_cohorts.R -- computed cell-median maximum exceeds ",
    "$250/hr (", wage_max_num, "); likely an outlier-trim or deflator ",
    "misconfiguration. Abort before rendering."
  )
}

message(
  "figure_e_entry_cohorts.R -- cell-median range: $",
  format(round(wage_min_num, 2), big.mark = ","), " to $",
  format(round(wage_max_num, 2), big.mark = ",")
)

###################################
###   6) Index to entry age     ###
###################################
# Per cohort, rebase the trajectory to index_base_num at the cohort's
# earliest non-NA age (the prime-age start, age 25, for cohorts whose
# age-25 cell survived the small-cell guard). The base age is recorded
# so the CSV and growth table disclose where each index series is
# anchored.

base_df <- cohort_age_df |>
  dplyr::filter(!is.na(real_hourly_wage_median_num)) |>
  dplyr::group_by(cohort_label_chr) |>
  dplyr::summarise(
    base_age_int  = min(age_int),
    .groups       = "drop"
  )

base_df <- base_df |>
  dplyr::inner_join(
    cohort_age_df |>
      dplyr::select(cohort_label_chr, age_int, real_hourly_wage_median_num),
    by = c("cohort_label_chr", "base_age_int" = "age_int")
  ) |>
  dplyr::rename(base_wage_num = real_hourly_wage_median_num)

cohort_age_df <- cohort_age_df |>
  dplyr::left_join(
    base_df |> dplyr::select(cohort_label_chr, base_age_int, base_wage_num),
    by = "cohort_label_chr"
  ) |>
  dplyr::mutate(
    indexed_num = dplyr::if_else(
      !is.na(real_hourly_wage_median_num) & !is.na(base_wage_num),
      real_hourly_wage_median_num / base_wage_num * index_base_num,
      NA_real_
    )
  )

###################################
###   7) Coverage verification  ###
###################################
# Every cohort observed in the valid input should retain at least one
# non-NA median after the small-cell guard. A cohort that vanishes
# entirely (every cell thin) is logged so the operator knows a line is
# absent from the figure.

observed_cohorts_chr <- sort(unique(real_wage_df$cohort_label_chr[valid_bool]))

panel_cohorts_with_median_chr <- sort(unique(
  cohort_age_df$cohort_label_chr[!is.na(cohort_age_df$real_hourly_wage_median_num)]
))

missing_from_panel_chr <- setdiff(
  observed_cohorts_chr, panel_cohorts_with_median_chr
)

if (length(missing_from_panel_chr) > 0L) {
  message(
    "figure_e_entry_cohorts.R -- note: cohort(s) present in valid input ",
    "but with no cell surviving the ", min_cell_n_int,
    "-observation guard (absent from the figure): ",
    paste(missing_from_panel_chr, collapse = ", ")
  )
}

###################################
###   8) Annualized growth      ###
###################################
# Per cohort, summarize the observed career and its annualized real wage
# growth. Two annual-growth measures:
#   annual_growth_ols_pct -- exp(slope) - 1, where slope is the weighted
#     OLS slope of log(median wage) on age across all non-NA cells. Uses
#     the full trajectory, so it is robust to a single noisy endpoint.
#     This is the headline "average annual growth over the observed
#     career."
#   cagr_pct -- endpoint compound annual growth rate between the first
#     and last observed non-NA age. Reported alongside for transparency.
# Both are computed only for cohorts with >= min_cohort_ages_int non-NA
# age cells.

growth_input_df <- cohort_age_df |>
  dplyr::filter(!is.na(real_hourly_wage_median_num)) |>
  dplyr::arrange(cohort_start_int, age_int)

growth_rows_ls  <- vector("list", length(cohort_levels_chr))
growth_idx_int  <- 1L

for (cohort_chr in cohort_levels_chr) {

  sub_df <- growth_input_df[growth_input_df$cohort_label_chr == cohort_chr, ,
                            drop = FALSE]

  n_ages_int <- nrow(sub_df)

  if (n_ages_int < min_cohort_ages_int) {
    message(
      "figure_e_entry_cohorts.R -- cohort ", cohort_chr, " has only ",
      n_ages_int, " non-NA age cell(s) (< ", min_cohort_ages_int,
      "); annualized growth not reported."
    )
    next
  }

  first_age_int   <- sub_df$age_int[1]
  last_age_int    <- sub_df$age_int[n_ages_int]
  first_wage_num  <- sub_df$real_hourly_wage_median_num[1]
  last_wage_num   <- sub_df$real_hourly_wage_median_num[n_ages_int]
  span_years_int  <- last_age_int - first_age_int

  cum_growth_pct_num <- (last_wage_num / first_wage_num - 1) * 100

  cagr_pct_num <- if (span_years_int > 0L) {
    ((last_wage_num / first_wage_num) ^ (1 / span_years_int) - 1) * 100
  } else {
    NA_real_
  }

  # Weighted OLS of log(wage) on age. weights = cell weight so wide cells
  # anchor the slope. exp(slope) - 1 converts the per-year log change to
  # a per-year percent change.
  ols_fit       <- stats::lm(
    log(real_hourly_wage_median_num) ~ age_int,
    data    = sub_df,
    weights = earnwt_cell_num
  )
  ols_slope_num <- unname(stats::coef(ols_fit)["age_int"])
  ols_pct_num   <- (exp(ols_slope_num) - 1) * 100

  growth_rows_ls[[growth_idx_int]] <- tibble::tibble(
    cohort_label_chr        = cohort_chr,
    entry_start_year_int    = sub_df$cohort_start_int[1],
    entry_end_year_int      = sub_df$cohort_end_int[1],
    first_age_int           = as.integer(first_age_int),
    last_age_int            = as.integer(last_age_int),
    n_ages_observed_int     = as.integer(n_ages_int),
    first_wage_real_num     = first_wage_num,
    last_wage_real_num      = last_wage_num,
    cumulative_growth_pct   = cum_growth_pct_num,
    annual_growth_ols_pct   = ols_pct_num,
    cagr_pct                = cagr_pct_num,
    total_n_int             = as.integer(sum(sub_df$n_cell_int))
  )
  growth_idx_int <- growth_idx_int + 1L
}

growth_df <- dplyr::bind_rows(
  growth_rows_ls[!vapply(growth_rows_ls, is.null, logical(1L))]
)

if (nrow(growth_df) == 0L) {
  stop(
    "figure_e_entry_cohorts.R -- no cohort reached the ",
    min_cohort_ages_int, "-age minimum for a growth fit. Inspect the ",
    "small-cell guard and the age window."
  )
}

growth_df <- growth_df |>
  dplyr::mutate(
    cohort_fct = factor(cohort_label_chr, levels = cohort_levels_chr)
  ) |>
  dplyr::arrange(cohort_fct)

message(
  "figure_e_entry_cohorts.R -- annualized growth computed for ",
  nrow(growth_df), " of ", length(cohort_levels_chr), " cohorts; ",
  "OLS annual real-wage growth ranges ",
  sprintf("%+.2f", min(growth_df$annual_growth_ols_pct)), "% to ",
  sprintf("%+.2f", max(growth_df$annual_growth_ols_pct)), "% per year."
)

###################################
###   8b) Matched-window growth ###
###################################
# Real wage growth over a common early-career age window
# (matched_start_age_int -> matched_end_age_int), holding the age range
# fixed across cohorts so only the calendar period differs. The older
# cohorts traverse this window during the stagnation bands and the
# younger cohorts traverse it during recovery periods, so a lower
# matched-window growth for older cohorts is attributable to calendar
# stagnation, not to lifecycle concavity or window length. Cohorts that
# have not yet reached matched_end_age_int (or whose endpoint cell was
# suppressed by the small-cell guard) report NA.

matched_endpoint_df <- cohort_age_df |>
  dplyr::filter(
    age_int %in% c(matched_start_age_int, matched_end_age_int),
    !is.na(real_hourly_wage_median_num)
  ) |>
  dplyr::mutate(
    endpoint_chr = dplyr::if_else(
      age_int == matched_start_age_int, "matched_start_wage", "matched_end_wage"
    )
  ) |>
  dplyr::select(cohort_label_chr, endpoint_chr, real_hourly_wage_median_num) |>
  tidyr::pivot_wider(
    names_from  = endpoint_chr,
    values_from = real_hourly_wage_median_num
  )

# Defensive: guarantee both endpoint columns exist even if no cohort
# reached the matched end age (e.g., an early-build panel).
for (col_chr in c("matched_start_wage", "matched_end_wage")) {
  if (!col_chr %in% names(matched_endpoint_df)) {
    matched_endpoint_df[[col_chr]] <- NA_real_
  }
}

matched_span_int <- matched_end_age_int - matched_start_age_int

matched_df <- matched_endpoint_df |>
  dplyr::mutate(
    matched_growth_pct = dplyr::if_else(
      !is.na(matched_start_wage) & !is.na(matched_end_wage),
      (matched_end_wage / matched_start_wage - 1) * 100,
      NA_real_
    ),
    matched_annual_pct = dplyr::if_else(
      !is.na(matched_start_wage) & !is.na(matched_end_wage),
      ((matched_end_wage / matched_start_wage) ^ (1 / matched_span_int) - 1) *
        100,
      NA_real_
    )
  ) |>
  dplyr::select(cohort_label_chr, matched_growth_pct, matched_annual_pct)

###################################
###   8c) Stagnation exposure   ###
###################################
# Per cohort, the share of observed working years (calendar years with a
# non-suppressed cell in the calendar-year panel) that fell inside a
# stagnation band. This is the single-number quantification of
# over-exposure: oldest cohorts spent most of their observed career in
# the bands; cohorts entering after 2014 have zero exposure.

exposure_df <- cohort_year_df |>
  dplyr::filter(!is.na(real_hourly_wage_median_num)) |>
  dplyr::group_by(cohort_label_chr) |>
  dplyr::summarise(
    n_obs_years_int        = dplyr::n_distinct(year_int),
    n_stagnation_years_int = sum(year_int %in% stagnation_years_int),
    .groups                = "drop"
  ) |>
  dplyr::mutate(
    stagnation_exposure_share = n_stagnation_years_int / n_obs_years_int
  )

growth_df <- growth_df |>
  dplyr::left_join(matched_df,   by = "cohort_label_chr") |>
  dplyr::left_join(exposure_df,  by = "cohort_label_chr")

message(
  "figure_e_entry_cohorts.R -- stagnation-exposure share ranges ",
  sprintf("%.0f", 100 * min(growth_df$stagnation_exposure_share, na.rm = TRUE)),
  "% to ",
  sprintf("%.0f", 100 * max(growth_df$stagnation_exposure_share, na.rm = TRUE)),
  "% of observed working years; matched ages ", matched_start_age_int, "-",
  matched_end_age_int, " growth reported for ",
  sum(!is.na(growth_df$matched_growth_pct)), " of ", nrow(growth_df),
  " cohorts."
)

###################################
###   9) Cohort color ramp      ###
###################################
# SINGLE-HUE sequential ramp (EIG greens darkening into teal), oldest
# entry cohort darkest to newest lightest. A single-hue sequence encodes
# cohort recency as lightness (Tufte: avoid multi-hue "rainbow" ramps for
# ordered data) and stays on-brand: the anchors are 2022 primary tokens
# Forest Green (eig_green_700) and Dark Teal (eig_teal_900) with a sage
# midpoint (eig_green_500). Cohort identity is carried by the direct
# end-of-line labels below, not by hue, so adjacent-cohort similarity in
# a single-hue ramp is not a legibility problem.

ramp_anchor_tokens_chr <- c("eig_teal_900", "eig_green_700", "eig_green_500")
missing_ramp_tokens_chr <- setdiff(
  ramp_anchor_tokens_chr, names(eig_palette_2022_primary)
)
if (length(missing_ramp_tokens_chr) > 0L) {
  stop(
    "figure_e_entry_cohorts.R -- missing palette token(s) for the cohort ",
    "color ramp: ", paste(missing_ramp_tokens_chr, collapse = ", ")
  )
}

# Index 1 (oldest cohort) = darkest (eig_teal_900); last (newest) =
# lightest (eig_green_500), so the most stagnation-exposed cohorts read
# darkest.
cohort_colors_chr <- grDevices::colorRampPalette(
  unname(eig_palette_2022_primary[ramp_anchor_tokens_chr])
)(length(cohort_levels_chr))
names(cohort_colors_chr) <- cohort_levels_chr

# Highlight color for the single most-exposed (oldest) cohort in the bar
# chart: EIG Gold, the brand's callout color.
eig_gold_chr        <- unname(eig_palette_2022_primary["eig_gold_600"])
eig_forest_green_chr <- unname(eig_palette_2022_primary["eig_green_700"])

###################################
###   10) Shared caption        ###
###################################

# Captions are wrapped with stringr::str_wrap() so a long line can never
# run off the device edge (ggplot does not wrap plot.caption). Kept to a
# concise Source + Note per EIG figure-style section 4; the full
# methodology lives in the script header and the figures-summary digest.
fig_caption_chr <- paste0(
  "Source: IPUMS-CPS ORG, 1982 to latest; BEA PCEPI via FRED.\n",
  stringr::str_wrap(
    paste0(
      "Note: Synthetic cohort (pseudo-panel). Workers are grouped by ",
      "labor-market entry (birth year + ", entry_age_int, ") into ",
      cohort_bin_width_int, "-year cohorts; lines show the EARNWT-weighted ",
      "median real hourly wage by age over prime age ", age_min_int, "-",
      age_max_int, ". Cohorts are observed over unequal age windows by ",
      "design. Cells below ", min_cell_n_int,
      " observations are suppressed; medians are conditional on employment.",
      " Census-imputed (allocated) earnings records retained; October 2025 not collected (shutdown)."
    ),
    width = 110
  )
)

# Calendar-time figure caption. Adds the stagnation-band definition and
# the over-exposure framing; otherwise shares the synthetic-cohort and
# selection caveats above.
fig_caption_cal_chr <- paste0(
  "Source: IPUMS-CPS ORG, 1982 to latest; BEA PCEPI via FRED.\n",
  stringr::str_wrap(
    paste0(
      "Note: Synthetic cohort (pseudo-panel). Lines show the EARNWT-weighted ",
      "median real hourly wage by calendar year for each 5-year entry cohort ",
      "(birth year + ", entry_age_int, "), prime age ", age_min_int, "-",
      age_max_int, ". Shaded bands are the real-wage stagnation periods ",
      band1_start_int, "-", band1_end_int, " and ", band2_start_int, "-",
      band2_end_int, "; a cohort appears inside a band only if it was in the ",
      "labor market then. Cells below ", min_cell_n_int,
      " observations are suppressed; medians are conditional on employment.",
      " October 2025 not collected (shutdown)."
    ),
    width = 110
  )
)

# Bar-chart caption. Bar height is the annualized real wage growth over
# each cohort's observed prime-age span (the weighted OLS slope of log
# real hourly wage on age, converted to a per-year percent).
fig_caption_bars_chr <- paste0(
  "Source: IPUMS-CPS ORG, 1982 to latest; BEA PCEPI via FRED.\n",
  stringr::str_wrap(
    paste0(
      "Note: Synthetic cohort (pseudo-panel). Bar height is the annualized ",
      "growth of the EARNWT-weighted median real hourly wage over each ",
      "cohort's observed prime-age span (", age_min_int, "-", age_max_int,
      "), the cell-weighted OLS slope of log real wage on age as a per-year ",
      "percent. Cohorts are identified by entry year (birth year + ",
      entry_age_int, "). Observation spans differ by cohort, so younger ",
      "cohorts cover only early prime age (steeper growth) and the bars are ",
      "not over identical windows. Cohorts with fewer than ",
      min_cohort_ages_int, " observed prime ages are omitted."
    ),
    width = 110
  )
)

###################################
###   11) Render level figure   ###
###################################

plot_df <- cohort_age_df[!is.na(cohort_age_df$real_hourly_wage_median_num), ,
                         drop = FALSE]

x_breaks_int <- seq(
  floor(min(plot_df$age_int) / 5L) * 5L,
  ceiling(max(plot_df$age_int) / 5L) * 5L,
  by = 5L
)

# Direct end-of-line labels (Tufte: label the data, not a legend). One
# label per cohort at its terminal (maximum-age) point.
level_ends_df <- plot_df |>
  dplyr::group_by(cohort_fct) |>
  dplyr::slice_max(age_int, n = 1L, with_ties = FALSE) |>
  dplyr::ungroup()

fig_e_level_plot <- ggplot2::ggplot(
  plot_df,
  ggplot2::aes(
    x     = age_int,
    y     = real_hourly_wage_median_num,
    color = cohort_fct
  )
) +
  ggplot2::geom_line(linewidth = 0.9, na.rm = TRUE) +
  ggrepel::geom_text_repel(
    data    = level_ends_df,
    ggplot2::aes(label = cohort_fct),
    hjust          = 0,
    nudge_x        = 1.0,
    direction      = "y",
    segment.color  = NA,
    size           = 2.9,
    show.legend    = FALSE,
    na.rm          = TRUE,
    max.overlaps   = Inf
  ) +
  ggplot2::scale_color_manual(values = cohort_colors_chr, guide = "none") +
  ggplot2::scale_y_continuous(
    labels = scales::label_dollar(accuracy = 1L)
  ) +
  ggplot2::scale_x_continuous(
    breaks = x_breaks_int,
    expand = ggplot2::expansion(mult = c(0.02, 0.16))
  ) +
  ggplot2::labs(
    title    = "Figure 5a. Real hourly wage trajectory by labor-market-entry cohort",
    subtitle = stringr::str_wrap(
      paste0(
        "Weighted median real hourly wage over prime age ", age_min_int, "-",
        age_max_int, ", in December 2025 PCE dollars, for 5-year entry cohorts"
      ),
      width = 90
    ),
    x        = "Age (years)",
    y        = "Real hourly wage (Dec 2025 $)",
    caption  = fig_caption_chr
  ) +
  ggplot2::theme_minimal(base_size = 11, base_family = eig_font_body_chr) +
  ggplot2::theme(
    panel.grid.major.x = ggplot2::element_blank(),
    panel.grid.minor   = ggplot2::element_blank(),
    panel.border       = ggplot2::element_blank(),
    axis.line          = ggplot2::element_line(linewidth = 0.3),
    legend.position    = "none",
    plot.title         = ggplot2::element_text(face = "bold",
                                               family = eig_font_title_chr),
    plot.caption       = ggplot2::element_text(hjust = 0)
  )

###################################
###   12) Render indexed figure ###
###################################

index_plot_df <- cohort_age_df[!is.na(cohort_age_df$indexed_num), ,
                               drop = FALSE]

index_ends_df <- index_plot_df |>
  dplyr::group_by(cohort_fct) |>
  dplyr::slice_max(age_int, n = 1L, with_ties = FALSE) |>
  dplyr::ungroup()

fig_e_index_plot <- ggplot2::ggplot(
  index_plot_df,
  ggplot2::aes(
    x     = age_int,
    y     = indexed_num,
    color = cohort_fct
  )
) +
  ggplot2::geom_hline(
    yintercept = index_base_num,
    linewidth  = 0.3,
    color      = "grey60"
  ) +
  ggplot2::geom_line(linewidth = 0.9, na.rm = TRUE) +
  ggrepel::geom_text_repel(
    data    = index_ends_df,
    ggplot2::aes(label = cohort_fct),
    hjust          = 0,
    nudge_x        = 1.0,
    direction      = "y",
    segment.color  = NA,
    size           = 2.9,
    show.legend    = FALSE,
    na.rm          = TRUE,
    max.overlaps   = Inf
  ) +
  ggplot2::scale_color_manual(values = cohort_colors_chr, guide = "none") +
  ggplot2::scale_x_continuous(
    breaks = x_breaks_int,
    expand = ggplot2::expansion(mult = c(0.02, 0.16))
  ) +
  ggplot2::labs(
    title    = "Figure 5b. Real hourly wage growth by labor-market-entry cohort",
    subtitle = stringr::str_wrap(
      paste0(
        "Weighted median real hourly wage over prime age ", age_min_int,
        "-", age_max_int, ", indexed to ", index_base_num, " at age ",
        age_min_int
      ),
      width = 90
    ),
    x        = "Age (years)",
    y        = paste0("Index (age ", age_min_int, " = ", index_base_num, ")"),
    caption  = fig_caption_chr
  ) +
  ggplot2::theme_minimal(base_size = 11, base_family = eig_font_body_chr) +
  ggplot2::theme(
    panel.grid.major.x = ggplot2::element_blank(),
    panel.grid.minor   = ggplot2::element_blank(),
    panel.border       = ggplot2::element_blank(),
    axis.line          = ggplot2::element_line(linewidth = 0.3),
    legend.position    = "none",
    plot.title         = ggplot2::element_text(face = "bold",
                                               family = eig_font_title_chr),
    plot.caption       = ggplot2::element_text(hjust = 0)
  )

###################################
###   12b) Render calendar figure#
###################################
# Calendar-time view: x = survey year, one line per cohort, with the two
# stagnation bands shaded. This is the figure that makes the
# over-exposure story visible -- older cohorts' lines traverse the bands
# during their prime wage-building years while younger cohorts only
# appear after them.

cal_plot_df <- cohort_year_df[!is.na(cohort_year_df$real_hourly_wage_median_num), ,
                              drop = FALSE]

cal_x_breaks_int <- seq(
  floor(min(cal_plot_df$year_int) / 5L) * 5L,
  ceiling(max(cal_plot_df$year_int) / 5L) * 5L,
  by = 5L
)

# Direct end-of-line labels at each cohort's terminal (latest) year.
cal_ends_df <- cal_plot_df |>
  dplyr::group_by(cohort_fct) |>
  dplyr::slice_max(year_int, n = 1L, with_ties = FALSE) |>
  dplyr::ungroup()

# Band rectangles span the full plot height. xmin/xmax are nudged by
# half a year so the integer year endpoints sit inside the shaded span.
band_rect_df <- tibble::tibble(
  xmin_num = c(band1_start_int - 0.5, band2_start_int - 0.5),
  xmax_num = c(band1_end_int   + 0.5, band2_end_int   + 0.5)
)

fig_e_cal_plot <- ggplot2::ggplot() +
  ggplot2::geom_rect(
    data = band_rect_df,
    ggplot2::aes(
      xmin = xmin_num, xmax = xmax_num,
      ymin = -Inf,     ymax = Inf
    ),
    fill  = "grey70",
    alpha = 0.25
  ) +
  ggplot2::geom_line(
    data = cal_plot_df,
    ggplot2::aes(
      x     = year_int,
      y     = real_hourly_wage_median_num,
      color = cohort_fct
    ),
    linewidth = 0.9,
    na.rm     = TRUE
  ) +
  ggrepel::geom_text_repel(
    data    = cal_ends_df,
    ggplot2::aes(
      x     = year_int,
      y     = real_hourly_wage_median_num,
      label = cohort_fct,
      color = cohort_fct
    ),
    hjust          = 0,
    nudge_x        = 0.6,
    direction      = "y",
    segment.color  = NA,
    size           = 2.9,
    show.legend    = FALSE,
    na.rm          = TRUE,
    max.overlaps   = Inf
  ) +
  ggplot2::scale_color_manual(values = cohort_colors_chr, guide = "none") +
  ggplot2::scale_y_continuous(
    labels = scales::label_dollar(accuracy = 1L)
  ) +
  ggplot2::scale_x_continuous(
    breaks = cal_x_breaks_int,
    expand = ggplot2::expansion(mult = c(0.02, 0.12))
  ) +
  ggplot2::labs(
    title    = "Figure 5c. Cohort exposure to real-wage stagnation, by calendar year",
    subtitle = stringr::str_wrap(
      paste0(
        "Weighted median real hourly wage by year, in December 2025 PCE ",
        "dollars; shaded bands are the ", band1_start_int, "-", band1_end_int,
        " and ", band2_start_int, "-", band2_end_int, " stagnation periods"
      ),
      width = 90
    ),
    x        = "Year",
    y        = "Real hourly wage (Dec 2025 $)",
    caption  = fig_caption_cal_chr
  ) +
  ggplot2::theme_minimal(base_size = 11, base_family = eig_font_body_chr) +
  ggplot2::theme(
    panel.grid.major.x = ggplot2::element_blank(),
    panel.grid.minor   = ggplot2::element_blank(),
    panel.border       = ggplot2::element_blank(),
    axis.line          = ggplot2::element_line(linewidth = 0.3),
    legend.position    = "none",
    plot.title         = ggplot2::element_text(face = "bold",
                                               family = eig_font_title_chr),
    plot.caption       = ggplot2::element_text(hjust = 0)
  )

###################################
###   12c) Render growth bars    #
###################################
# Simple bar chart: one bar per entry cohort, height = the cohort's
# annualized real wage growth over its observed prime-age span
# (annual_growth_ols_pct from the growth table). The x-axis runs oldest
# to newest entry cohort. Bars use the same cohort color ramp as the
# trajectory figures so a reader can cross-reference; the x-axis already
# labels each cohort, so the color legend is dropped. Value labels sit
# just outside each bar.

# Single-series bar chart: EIG rule is one color (Forest Green) for a
# single series, Gold for a highlighted/callout bar. The oldest cohort
# (cohort_levels_chr[1]) is the most stagnation-exposed and carries the
# narrative, so it is highlighted in Gold; all others are Forest Green.
# Fill is set as an identity color, so no redundant color legend.
oldest_cohort_chr <- cohort_levels_chr[1]

bars_df <- growth_df |>
  dplyr::arrange(cohort_fct) |>
  dplyr::mutate(
    bar_label_chr = paste0(sprintf("%+.1f", annual_growth_ols_pct), "%"),
    bar_fill_chr  = dplyr::if_else(
      cohort_label_chr == oldest_cohort_chr,
      eig_gold_chr,
      eig_forest_green_chr
    )
  )

fig_e_bars_plot <- ggplot2::ggplot(
  bars_df,
  ggplot2::aes(
    x    = cohort_fct,
    y    = annual_growth_ols_pct,
    fill = bar_fill_chr
  )
) +
  ggplot2::geom_col(width = 0.72) +
  ggplot2::geom_text(
    ggplot2::aes(label = bar_label_chr),
    vjust  = -0.45,
    size   = 3.1,
    color  = "grey20",
    family = eig_font_body_chr
  ) +
  ggplot2::scale_fill_identity() +
  ggplot2::scale_y_continuous(
    labels = scales::label_number(accuracy = 0.1, suffix = "%"),
    expand = ggplot2::expansion(mult = c(0, 0.12))
  ) +
  ggplot2::labs(
    title    = "Figure 5d. Average annual real wage growth by labor-market-entry cohort",
    subtitle = stringr::str_wrap(
      paste0(
        "Annualized growth of the weighted median real hourly wage over ",
        "prime age ", age_min_int, "-", age_max_int,
        "; oldest, most stagnation-exposed cohort highlighted in gold"
      ),
      width = 78
    ),
    x        = "Labor-market-entry cohort",
    y        = "Average annual real wage growth (%/yr)",
    caption  = fig_caption_bars_chr
  ) +
  ggplot2::theme_minimal(base_size = 11, base_family = eig_font_body_chr) +
  ggplot2::theme(
    panel.grid.major.x = ggplot2::element_blank(),
    panel.grid.minor   = ggplot2::element_blank(),
    panel.border       = ggplot2::element_blank(),
    axis.line.x        = ggplot2::element_line(linewidth = 0.3),
    axis.text.x        = ggplot2::element_text(angle = 30, hjust = 1),
    plot.title         = ggplot2::element_text(face = "bold",
                                               family = eig_font_title_chr),
    plot.caption       = ggplot2::element_text(hjust = 0)
  )

###################################
###   13) Write PNGs            ###
###################################

ggplot2::ggsave(
  filename = fig_level_png_chr,
  plot     = fig_e_level_plot,
  width    = 9.5,
  height   = 5.8,
  units    = "in",
  dpi      = 300L,
  device   = eig_png_device
)

ggplot2::ggsave(
  filename = fig_index_png_chr,
  plot     = fig_e_index_plot,
  width    = 9.5,
  height   = 5.8,
  units    = "in",
  dpi      = 300L,
  device   = eig_png_device
)

ggplot2::ggsave(
  filename = fig_cal_png_chr,
  plot     = fig_e_cal_plot,
  width    = 9.5,
  height   = 5.8,
  units    = "in",
  dpi      = 300L,
  device   = eig_png_device
)

ggplot2::ggsave(
  filename = fig_bars_png_chr,
  plot     = fig_e_bars_plot,
  width    = 8.5,
  height   = 5.4,
  units    = "in",
  dpi      = 300L,
  device   = eig_png_device
)

###################################
###   14) Write wide CSVs       ###
###################################
# Wide by cohort, one row per age (Datawrapper convention). Snake-case
# cohort column names ("1982-1986" -> "entry_1982_1986") so downstream
# consumers parse them as valid identifiers. Column order oldest cohort
# first, matching cohort_levels_chr.

cohort_column_names_chr <- setNames(
  paste0("entry_", gsub("-", "_", cohort_levels_chr)),
  cohort_levels_chr
)
cohort_column_order_chr <- unname(cohort_column_names_chr[cohort_levels_chr])

level_wide_df <- cohort_age_df |>
  dplyr::mutate(
    cohort_col_chr = unname(cohort_column_names_chr[cohort_label_chr])
  ) |>
  dplyr::select(age_int, cohort_col_chr, real_hourly_wage_median_num) |>
  tidyr::pivot_wider(
    names_from  = cohort_col_chr,
    values_from = real_hourly_wage_median_num
  )

index_wide_df <- cohort_age_df |>
  dplyr::mutate(
    cohort_col_chr = unname(cohort_column_names_chr[cohort_label_chr])
  ) |>
  dplyr::select(age_int, cohort_col_chr, indexed_num) |>
  tidyr::pivot_wider(
    names_from  = cohort_col_chr,
    values_from = indexed_num
  )

# Guarantee every cohort column exists and is ordered even if a cohort
# pivoted to no rows (defensive against an all-thin cohort).
for (col_chr in setdiff(cohort_column_order_chr, names(level_wide_df))) {
  level_wide_df[[col_chr]] <- NA_real_
}
for (col_chr in setdiff(cohort_column_order_chr, names(index_wide_df))) {
  index_wide_df[[col_chr]] <- NA_real_
}

level_wide_df <- level_wide_df |>
  dplyr::select(age_int, dplyr::all_of(cohort_column_order_chr)) |>
  dplyr::arrange(age_int)

index_wide_df <- index_wide_df |>
  dplyr::select(age_int, dplyr::all_of(cohort_column_order_chr)) |>
  dplyr::arrange(age_int)

readr::write_csv(level_wide_df, fig_level_csv_chr)
readr::write_csv(index_wide_df, fig_index_csv_chr)

# Calendar-time wide CSV: one row per year, one column per cohort
# (Datawrapper convention), so the shaded-band figure is reproducible
# downstream. Year grid spans the panel's observed year range with NA
# where a cohort has no surviving cell that year.
cal_wide_df <- cohort_year_df |>
  dplyr::mutate(
    cohort_col_chr = unname(cohort_column_names_chr[cohort_label_chr])
  ) |>
  dplyr::select(year_int, cohort_col_chr, real_hourly_wage_median_num) |>
  tidyr::pivot_wider(
    names_from  = cohort_col_chr,
    values_from = real_hourly_wage_median_num
  )

for (col_chr in setdiff(cohort_column_order_chr, names(cal_wide_df))) {
  cal_wide_df[[col_chr]] <- NA_real_
}

cal_wide_df <- cal_wide_df |>
  dplyr::select(year_int, dplyr::all_of(cohort_column_order_chr)) |>
  dplyr::arrange(year_int)

readr::write_csv(cal_wide_df, fig_cal_csv_chr)

###################################
###   15) Write growth CSV      ###
###################################
# One row per cohort. Columns progress from the observed-career summary
# through the full-window growth, the matched early-career window (ages
# matched_start_age_int -> matched_end_age_int, comparable across
# cohorts), and the stagnation-exposure share.

growth_out_df <- growth_df |>
  dplyr::select(
    cohort_label_chr,
    entry_start_year_int,
    entry_end_year_int,
    first_age_int,
    last_age_int,
    n_ages_observed_int,
    first_wage_real_num,
    last_wage_real_num,
    cumulative_growth_pct,
    annual_growth_ols_pct,
    cagr_pct,
    matched_growth_pct,
    matched_annual_pct,
    n_obs_years_int,
    n_stagnation_years_int,
    stagnation_exposure_share,
    total_n_int
  )

readr::write_csv(growth_out_df, fig_growth_csv_chr)

message(
  "figure_e_entry_cohorts.R -- wrote PNGs (", fig_level_png_chr, ", ",
  fig_index_png_chr, ", ", fig_cal_png_chr, ", ", fig_bars_png_chr,
  ") and CSVs (", fig_level_csv_chr, ", ", fig_index_csv_chr, ", ",
  fig_cal_csv_chr, ", ", fig_growth_csv_chr, ")"
)

###################################
###   16) Verify outputs exist  ###
###################################

for (path_chr in c(fig_level_png_chr, fig_index_png_chr, fig_cal_png_chr,
                   fig_bars_png_chr,
                   fig_level_csv_chr, fig_index_csv_chr, fig_cal_csv_chr,
                   fig_growth_csv_chr)) {
  if (!fs::file_exists(path_chr)) {
    stop("figure_e_entry_cohorts.R -- output not written: ", path_chr)
  }
}

message("figure_e_entry_cohorts.R -- done.")
