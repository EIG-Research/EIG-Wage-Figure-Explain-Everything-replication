# 02b_build_generation_panel -- classify generations, compute weighted median real wage by year x age x generation x sex
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

rm(list = ls())
options(scipen = 999)
set.seed(42)

# Sourced by run_all.R inside new.env(parent = globalenv()).
#
# Reads the year-partitioned real-wage panel written by 02a,
# classifies each observation's birth year into one of five
# generations, and computes the EARNWT-weighted median real weekly
# wage and real hourly wage by year x age x generation x sex. Output
# is a single parquet plus an .rds sidecar.
#
# Generation cutoffs (Pew Research Center boundaries via Dimock 2019):
#   Silent:       BIRTHYR <= 1945
#   Boomers:      BIRTHYR %in% 1946:1964
#   Gen X:        BIRTHYR %in% 1965:1980
#   Millennials:  BIRTHYR %in% 1981:1996
#   Gen Z:        BIRTHYR >= 1997
# Pre-1928 births are folded into "Silent" so the panel covers the full
# historical range with exactly five generations.
#
# Weighted-median construction uses the shared weighted_quantile() helper
# (Stata `_pctile` / EPI no-interpolation lower-median convention; see
# code/_utils/weighted_stats.R), so the generation panel agrees with the
# percentile figure (A), the age-bin figure (B), and the EPI spot-check
# gate (10) by construction rather than relying on a separate estimator.
#
# No custom functions are defined; all transformations are inline.

source(here::here("code", "_utils", "00_packages.R"))

###################################
###   Configuration             ###
###################################

panel_in_dir_chr  <- here::here("data", "intermediate", "cps_real_wages")
# Writes to output/tables/ alongside the figure CSV sidecars produced
# by figure_a / figure_b / figure_c.
panel_out_dir_chr <- here::here("output", "tables")
out_parquet_chr   <- fs::path(panel_out_dir_chr, "generation_panel.parquet")
out_rds_chr       <- fs::path(panel_out_dir_chr, "generation_panel.rds")

# Generation cutoffs (Pew via Dimock 2019, "Defining generations: Where
# Millennials end and Generation Z begins," Pew Research Center).
silent_boomer_cutoff_int   <- 1945L
boomer_genx_cutoff_int     <- 1964L
genx_millennial_cutoff_int <- 1980L
millennial_genz_cutoff_int <- 1996L

# Canonical generation order for downstream figure consistency.
# The panel itself stores generation as character; the figure scripts
# can apply this factor order when plotting.
generation_levels_chr <- c("Silent", "Boomers", "Gen X", "Millennials", "Gen Z")

fs::dir_create(panel_out_dir_chr, recurse = TRUE)

###################################
###   1) Locate input panel     ###
###################################

if (!fs::dir_exists(panel_in_dir_chr)) {
  stop(
    "02b_build_generation_panel.R -- real-wage panel not found at ",
    panel_in_dir_chr, ". Run 02a_build_real_wages.R first."
  )
}

year_partition_paths_chr <- fs::dir_ls(
  panel_in_dir_chr, regexp = "year=\\d{4}", type = "directory"
)

if (length(year_partition_paths_chr) == 0L) {
  stop(
    "02b_build_generation_panel.R -- no year partitions under ",
    panel_in_dir_chr, ". Run 02a_build_real_wages.R first."
  )
}

message(
  "02b_build_generation_panel.R -- reading ",
  length(year_partition_paths_chr), " year partitions from ",
  panel_in_dir_chr
)

###################################
###   2) Load real-wage panel   ###
###################################
# Reads all year partitions and collects to an in-memory tibble
# (~8M person-year rows x 6 columns x 8 bytes ~= 0.4 GB).
#
# Explicit parquet-only file list: the partition dirs also contain
# part-0.rds sidecars (EIG dual-format checkpoint convention) which
# arrow::open_dataset() cannot parse if passed the bare directory.
# YEAR is stored as a column inside each parquet, so hive-partitioning
# auto-detection is not needed.
parquet_paths_chr <- fs::dir_ls(
  panel_in_dir_chr,
  regexp = "part-0\\.parquet$",
  recurse = TRUE,
  type   = "file"
)

if (length(parquet_paths_chr) == 0L) {
  stop(
    "02b_build_generation_panel.R -- no part-0.parquet files found ",
    "under ", panel_in_dir_chr, ". Run 02a_build_real_wages.R first."
  )
}

real_wage_ds <- arrow::open_dataset(parquet_paths_chr, format = "parquet")

real_wage_df <- real_wage_ds |>
  dplyr::select(
    YEAR, MONTH, EARNWT, AGE, SEX, BIRTHYR,
    real_weekly_wage_num, real_hourly_wage_num
  ) |>
  dplyr::collect()

required_cols_chr <- c(
  "YEAR", "MONTH", "EARNWT", "AGE", "SEX", "BIRTHYR",
  "real_weekly_wage_num", "real_hourly_wage_num"
)
missing_cols_chr <- setdiff(required_cols_chr, names(real_wage_df))

if (length(missing_cols_chr) > 0L) {
  stop(
    "02b_build_generation_panel.R -- real-wage panel missing column(s): ",
    paste(missing_cols_chr, collapse = ", ")
  )
}

message(
  "02b_build_generation_panel.R -- loaded ",
  format(nrow(real_wage_df), big.mark = ","),
  " person-year records spanning ",
  min(real_wage_df$YEAR, na.rm = TRUE), "-",
  max(real_wage_df$YEAR, na.rm = TRUE)
)

###################################
###   3) Classify generations   ###
###################################

real_wage_df <- real_wage_df |>
  dplyr::mutate(
    generation_chr = dplyr::case_when(
      BIRTHYR <= silent_boomer_cutoff_int                   ~ "Silent",
      BIRTHYR >  silent_boomer_cutoff_int &
        BIRTHYR <= boomer_genx_cutoff_int                   ~ "Boomers",
      BIRTHYR >  boomer_genx_cutoff_int &
        BIRTHYR <= genx_millennial_cutoff_int               ~ "Gen X",
      BIRTHYR >  genx_millennial_cutoff_int &
        BIRTHYR <= millennial_genz_cutoff_int               ~ "Millennials",
      BIRTHYR >  millennial_genz_cutoff_int                 ~ "Gen Z",
      TRUE                                                  ~ NA_character_
    )
  )

n_missing_birthyr_int <- sum(is.na(real_wage_df$BIRTHYR))
n_missing_gen_int     <- sum(is.na(real_wage_df$generation_chr))

if (n_missing_gen_int > 0L) {
  message(
    "02b_build_generation_panel.R -- WARNING: ",
    format(n_missing_gen_int, big.mark = ","),
    " rows have NA generation (missing BIRTHYR in ",
    format(n_missing_birthyr_int, big.mark = ","),
    " rows). These are excluded from the generation panel."
  )
}

# Distribution of generation codes (pre-drop)
gen_counts_df <- real_wage_df |>
  dplyr::count(generation_chr, name = "n_rows_int") |>
  dplyr::arrange(generation_chr)

message(
  "02b_build_generation_panel.R -- generation distribution (row counts, pre-drop):"
)
for (i in seq_len(nrow(gen_counts_df))) {
  message(
    "  ",
    ifelse(is.na(gen_counts_df$generation_chr[i]),
           "<NA>",
           gen_counts_df$generation_chr[i]),
    ": ", format(gen_counts_df$n_rows_int[i], big.mark = ",")
  )
}

###################################
###   4) Weighted median cells  ###
###################################
# Keep only rows with valid generation, valid real wage, and positive
# weight. Group by year x age x generation x sex and compute the
# EARNWT-weighted median via weighted_quantile(). Each cell pools up to
# 12 survey months of one year, so earnwt_cell_num divides the summed
# weight by the number of distinct months (weighted_population()) to
# report an average monthly population rather than a ~12x inflated count.

valid_bool <- !is.na(real_wage_df$generation_chr) &
  !is.na(real_wage_df$real_weekly_wage_num) &
  !is.na(real_wage_df$EARNWT) &
  real_wage_df$EARNWT > 0

# Note: real_hourly_wage_num is NA for rows with missing/zero hours in
# the salaried branch of 02a. Those rows are still kept by valid_bool
# because they have a valid weekly wage; weighted_quantile() drops NA
# values internally, so they fall out of the hourly median cell-by-cell.
gen_panel_df <- real_wage_df[valid_bool, , drop = FALSE] |>
  dplyr::group_by(YEAR, AGE, generation_chr, SEX) |>
  dplyr::summarise(
    n_cell_int                  = dplyr::n(),
    earnwt_cell_num             = weighted_population(EARNWT, YEAR, MONTH),
    real_weekly_wage_median_num = weighted_quantile(
      real_weekly_wage_num, EARNWT, 0.50
    ),
    real_hourly_wage_median_num = weighted_quantile(
      real_hourly_wage_num, EARNWT, 0.50
    ),
    .groups = "drop"
  ) |>
  dplyr::rename(
    year_int = YEAR,
    age_int  = AGE,
    sex_int  = SEX
  ) |>
  dplyr::mutate(
    year_int = as.integer(year_int),
    age_int  = as.integer(age_int),
    sex_int  = as.integer(sex_int)
  ) |>
  dplyr::arrange(year_int, age_int, generation_chr, sex_int)

# Defensive guard: if no valid rows survived the mask, the coverage check
# below would trivially pass on an empty panel. Stop here with a named
# error instead of silently writing an empty output.
if (nrow(gen_panel_df) == 0L) {
  stop(
    "02b_build_generation_panel.R -- generation panel is empty after ",
    "applying the validity mask. Check that 02a produced rows with ",
    "non-NA BIRTHYR, non-NA real_weekly_wage_num, and positive EARNWT."
  )
}

message(
  "02b_build_generation_panel.R -- generation panel: ",
  format(nrow(gen_panel_df), big.mark = ","), " cells spanning ",
  min(gen_panel_df$year_int), "-", max(gen_panel_df$year_int),
  " x ages ", min(gen_panel_df$age_int), "-", max(gen_panel_df$age_int)
)

###################################
###   5) Write outputs          ###
###################################

arrow::write_parquet(
  x           = gen_panel_df,
  sink        = out_parquet_chr,
  compression = "snappy"
)
saveRDS(gen_panel_df, file = out_rds_chr, compress = "xz")

message(
  "02b_build_generation_panel.R -- wrote generation panel: ",
  out_parquet_chr
)

###################################
###   6) Coverage verification  ###
###################################
# Coverage verification: every observed generation has at least one
# non-NA weighted median in at least one year. Failure indicates a
# silent loss of cells in the aggregation step.

observed_gens_chr <- sort(unique(
  real_wage_df$generation_chr[valid_bool]
))

panel_gens_with_median_chr <- sort(unique(
  gen_panel_df$generation_chr[!is.na(gen_panel_df$real_weekly_wage_median_num)]
))

missing_from_panel_chr <- setdiff(observed_gens_chr, panel_gens_with_median_chr)

if (length(missing_from_panel_chr) > 0L) {
  stop(
    "02b_build_generation_panel.R -- coverage verification FAIL: ",
    "generation(s) present in the valid input data but absent from ",
    "the output panel with a non-NA median: ",
    paste(missing_from_panel_chr, collapse = ", ")
  )
}

unobserved_gens_chr <- setdiff(generation_levels_chr, observed_gens_chr)

if (length(unobserved_gens_chr) > 0L) {
  message(
    "02b_build_generation_panel.R -- note: generation(s) not observed ",
    "in the input data: ",
    paste(unobserved_gens_chr, collapse = ", "),
    " (expected for Gen Z in early-year panels)."
  )
}

message(
  "02b_build_generation_panel.R -- coverage check PASS: ",
  length(panel_gens_with_median_chr), " of ",
  length(generation_levels_chr), " generations have non-NA medians (",
  paste(panel_gens_with_median_chr, collapse = ", "), ")."
)

###################################
###   7) Millennial spot-check  ###
###################################
# Millennial spot-check: for year=2020, age=30, sex=1, gen=Millennials,
# recompute the weighted median inline from the raw real-wage rows and
# assert the output-panel cell matches within a small numeric tolerance.
# Catches accidental groupby/aggregation regressions.

spotcheck_year_int <- 2020L
spotcheck_age_int  <- 30L
spotcheck_sex_int  <- 1L
spotcheck_gen_chr  <- "Millennials"

spotcheck_year_present_bool <- spotcheck_year_int %in%
  unique(real_wage_df$YEAR)

if (!spotcheck_year_present_bool) {
  message(
    "02b_build_generation_panel.R -- spot-check year ",
    spotcheck_year_int,
    " not present in panel; skipping Millennial spot-check."
  )
} else {
  spotcheck_bool <- valid_bool &
    real_wage_df$YEAR == spotcheck_year_int &
    real_wage_df$AGE == spotcheck_age_int &
    real_wage_df$SEX == spotcheck_sex_int &
    real_wage_df$generation_chr == spotcheck_gen_chr

  spotcheck_sub_df <- real_wage_df[spotcheck_bool, , drop = FALSE]

  if (nrow(spotcheck_sub_df) == 0L) {
    message(
      "02b_build_generation_panel.R -- spot-check cell year=",
      spotcheck_year_int, ", age=", spotcheck_age_int, ", sex=",
      spotcheck_sex_int, ", gen=", spotcheck_gen_chr,
      " has zero observations; skipping."
    )
  } else {
    spotcheck_hand_num <- weighted_quantile(
      spotcheck_sub_df$real_weekly_wage_num,
      spotcheck_sub_df$EARNWT,
      0.50
    )

    spotcheck_panel_num <- gen_panel_df |>
      dplyr::filter(
        year_int       == spotcheck_year_int,
        age_int        == spotcheck_age_int,
        sex_int        == spotcheck_sex_int,
        generation_chr == spotcheck_gen_chr
      ) |>
      dplyr::pull(real_weekly_wage_median_num)

    if (length(spotcheck_panel_num) != 1L) {
      stop(
        "02b_build_generation_panel.R -- spot-check FAIL: expected ",
        "exactly one matching cell in the generation panel; found ",
        length(spotcheck_panel_num), "."
      )
    }

    spotcheck_abs_diff_num <- abs(spotcheck_panel_num - spotcheck_hand_num)
    spotcheck_tol_num      <- 1e-6

    if (is.na(spotcheck_abs_diff_num) ||
        spotcheck_abs_diff_num > spotcheck_tol_num) {
      stop(
        "02b_build_generation_panel.R -- spot-check FAIL: Millennial age ",
        spotcheck_age_int, " sex ", spotcheck_sex_int, " in ",
        spotcheck_year_int, ": panel value = ", spotcheck_panel_num,
        "; hand-computed = ", spotcheck_hand_num,
        "; abs diff = ", spotcheck_abs_diff_num,
        " exceeds tolerance ", spotcheck_tol_num, "."
      )
    }

    message(
      "02b_build_generation_panel.R -- spot-check PASS: Millennial age ",
      spotcheck_age_int, " sex ", spotcheck_sex_int, " in ",
      spotcheck_year_int, " = $",
      format(round(spotcheck_panel_num, 2), big.mark = ","),
      " (n = ", format(nrow(spotcheck_sub_df), big.mark = ","),
      " obs; abs diff = ",
      format(spotcheck_abs_diff_num, scientific = TRUE), ")."
    )
  }
}

message("02b_build_generation_panel.R -- done.")
