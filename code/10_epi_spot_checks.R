# 10_epi_spot_checks -- numerical verification against EPI State of Working America reference values
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

rm(list = ls())
options(scipen = 999)
set.seed(42)

# Sourced by run_all.R inside new.env(parent = globalenv()) when the
# verification gate is exercised. Invoke end-to-end via `run_10 <- TRUE`
# in run_all.R, or directly with:
#   source(here::here("code", "10_epi_spot_checks.R"),
#          local = new.env(parent = globalenv()))
#
# Computes three numerical spot-checks against the EPI State of Working
# America Data Library and writes a comparison markdown to a local-only
# verification directory (`verif_out_dir_chr` below):
#   1) 1990 weighted median real hourly wage.
#   2) 2010 weighted median real hourly wage.
#   3) 2023 weighted 90th percentile real hourly wage.
#
# EPI's SWA Data Library publishes hourly percentiles only; the
# reference CSV (`epi_reference_values.csv`) records EPI row
# identifiers and the PCEPI ratio used to convert EPI's 2025-annual
# base to this pipeline's December 2025 PCE base.
#
# If the reference CSV is absent, the script writes the new-repo
# values and flags delta columns as "reference pending".
#
# Weighted quantile construction uses the shared weighted_quantile()
# helper (code/_utils/weighted_stats.R) -- the same function called by
# figure_a_percentiles.R and every other reporting path: sort within
# year by real_hourly_wage_num, cumulate EARNWT, and pick the smallest
# value whose cumulative weight is at least p * total weight (Stata
# `_pctile` / EPI no-interpolation convention).
#
# The verification directory is gitignored. To make the spot-check
# table public-facing, copy the rendered markdown into the README or
# a tracked output table after the script runs.
#
# No custom functions are defined; all transformations are inline.

source(here::here("code", "_utils", "00_packages.R"))

###################################
###   Configuration             ###
###################################

panel_in_dir_chr     <- here::here("data", "intermediate", "cps_real_wages")
verif_out_dir_chr    <- here::here("output", "verification")
verif_out_md_chr     <- fs::path(verif_out_dir_chr, "2026-04-21_spotcheck.md")
epi_ref_csv_chr      <- fs::path(verif_out_dir_chr, "epi_reference_values.csv")

spot_year_1_int      <- 1990L
spot_year_2_int      <- 2010L
spot_year_3_int      <- 2023L
spot_prob_median_num <- 0.50
spot_prob_p90_num    <- 0.90

# Deviation tolerances. A cell passes the spot-check if EITHER the
# absolute delta (dollars per hour) is within
# tol_abs_dollars_per_hour_num OR the relative delta (percent) is
# within tol_rel_pct_num; both are reported in the markdown for
# diagnostic value. Deltas exceeding both tolerances trigger a named
# failure in section 6. Tolerances are sized to absorb the three
# documented departures (#1 deflator, #2 no-fallback Pareto, #3
# retained allocated records); see docs/decisions/ for rationale.
tol_abs_dollars_per_hour_num <- 3.0
tol_rel_pct_num              <- 10.0

fs::dir_create(verif_out_dir_chr, recurse = TRUE)

###################################
###   1) Load real-wage panel   ###
###################################

if (!fs::dir_exists(panel_in_dir_chr)) {
  stop(
    "10_epi_spot_checks.R -- real-wage panel not found at ",
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
    "10_epi_spot_checks.R -- no part-0.parquet files found under ",
    panel_in_dir_chr, ". Run 02a_build_real_wages.R first."
  )
}

real_wage_ds <- arrow::open_dataset(parquet_paths_chr, format = "parquet")

real_wage_df <- real_wage_ds |>
  dplyr::select(YEAR, EARNWT, real_hourly_wage_num) |>
  dplyr::collect()

required_cols_chr <- c("YEAR", "EARNWT", "real_hourly_wage_num")
missing_cols_chr  <- setdiff(required_cols_chr, names(real_wage_df))

if (length(missing_cols_chr) > 0L) {
  stop(
    "10_epi_spot_checks.R -- real-wage panel missing column(s): ",
    paste(missing_cols_chr, collapse = ", ")
  )
}

message(
  "10_epi_spot_checks.R -- loaded ",
  format(nrow(real_wage_df), big.mark = ","),
  " person-year records spanning ",
  min(real_wage_df$YEAR, na.rm = TRUE), "-",
  max(real_wage_df$YEAR, na.rm = TRUE)
)

###################################
###   2) Apply validity mask    ###
###################################

valid_bool <- !is.na(real_wage_df$real_hourly_wage_num) &
  !is.na(real_wage_df$EARNWT) &
  real_wage_df$EARNWT > 0

if (sum(valid_bool) == 0L) {
  stop(
    "10_epi_spot_checks.R -- no valid person-year observations after ",
    "applying the validity mask. Check 02a output."
  )
}

valid_df <- real_wage_df[valid_bool, , drop = FALSE]

###################################
###   3) Compute spot-check     ###
###                 values       ###
###################################
# Weighted quantile per year. Cell 1: 1990 p50. Cell 2: 2010 p50.
# Cell 3: 2023 p90. Each cell subsets valid_df to that year and calls
# weighted_quantile(real_hourly_wage_num, EARNWT, p), which sorts by
# wage, cumulates EARNWT, and returns the smallest wage whose cumulative
# weight reaches p * total weight.

spot_cells_ls <- list(
  list(
    id_chr       = "1990_p50",
    year_int     = spot_year_1_int,
    prob_num     = spot_prob_median_num,
    description_chr = "1990 weighted median real hourly wage"
  ),
  list(
    id_chr       = "2010_p50",
    year_int     = spot_year_2_int,
    prob_num     = spot_prob_median_num,
    description_chr = "2010 weighted median real hourly wage"
  ),
  list(
    id_chr       = "2023_p90",
    year_int     = spot_year_3_int,
    prob_num     = spot_prob_p90_num,
    description_chr = "2023 weighted 90th percentile real hourly wage"
  )
)

spot_rows_df <- dplyr::tibble(
  id_chr          = character(0L),
  year_int        = integer(0L),
  prob_num        = numeric(0L),
  description_chr = character(0L),
  n_cell_int      = integer(0L),
  new_value_num   = numeric(0L)
)

for (cell_ls in spot_cells_ls) {
  year_subset_bool <- valid_df$YEAR == cell_ls$year_int

  if (sum(year_subset_bool) == 0L) {
    message(
      "10_epi_spot_checks.R -- year ", cell_ls$year_int,
      " has zero valid rows; recording NA."
    )
    spot_rows_df <- dplyr::bind_rows(
      spot_rows_df,
      dplyr::tibble(
        id_chr          = cell_ls$id_chr,
        year_int        = cell_ls$year_int,
        prob_num        = cell_ls$prob_num,
        description_chr = cell_ls$description_chr,
        n_cell_int      = 0L,
        new_value_num   = NA_real_
      )
    )
    next
  }

  cell_df <- valid_df[year_subset_bool, , drop = FALSE]
  new_value_num <- weighted_quantile(
    cell_df$real_hourly_wage_num, cell_df$EARNWT, cell_ls$prob_num
  )

  message(
    "10_epi_spot_checks.R -- ", cell_ls$id_chr, ": ",
    format(nrow(cell_df), big.mark = ","), " valid rows; value = $",
    format(round(new_value_num, 2), big.mark = ",")
  )

  spot_rows_df <- dplyr::bind_rows(
    spot_rows_df,
    dplyr::tibble(
      id_chr          = cell_ls$id_chr,
      year_int        = cell_ls$year_int,
      prob_num        = cell_ls$prob_num,
      description_chr = cell_ls$description_chr,
      n_cell_int      = as.integer(nrow(cell_df)),
      new_value_num   = new_value_num
    )
  )
}

###################################
###   4) Merge EPI reference    ###
###################################

if (fs::file_exists(epi_ref_csv_chr)) {
  # Schema:
  #   id_chr                     cell identifier (e.g., 1990_p50)
  #   metric_chr                 "hourly" (EPI SWA publishes hourly only)
  #   base_period_chr            "dec2025" for all current rows
  #   epi_nominal_num            EPI's published nominal value (info only)
  #   epi_value_2025annual_num   EPI's 2025-annual real value (info only)
  #   dec2025_rescale_ratio_num  mean(PCEPI monthly in 2025) / PCEPI(Dec 2025)
  #   epi_value_num              Dec-2025-base comparison target
  #                              (= epi_value_2025annual_num *
  #                                 dec2025_rescale_ratio_num)
  #   source_chr                 provenance note
  epi_ref_df <- readr::read_csv(
    epi_ref_csv_chr,
    col_types = readr::cols(
      id_chr                    = readr::col_character(),
      metric_chr                = readr::col_character(),
      base_period_chr           = readr::col_character(),
      epi_nominal_num           = readr::col_double(),
      epi_value_2025annual_num  = readr::col_double(),
      dec2025_rescale_ratio_num = readr::col_double(),
      epi_value_num             = readr::col_double(),
      source_chr                = readr::col_character()
    )
  )

  required_ref_cols_chr <- c("id_chr", "epi_value_num", "source_chr")
  missing_ref_cols_chr  <- setdiff(required_ref_cols_chr, names(epi_ref_df))

  if (length(missing_ref_cols_chr) > 0L) {
    stop(
      "10_epi_spot_checks.R -- EPI reference CSV missing column(s): ",
      paste(missing_ref_cols_chr, collapse = ", ")
    )
  }

  # Soft check on base period; rows with base_period_chr != "dec2025"
  # are from a prior convention and the comparison target has not been
  # rescaled. Warn but do not halt.
  if ("base_period_chr" %in% names(epi_ref_df)) {
    non_dec2025_rows_chr <- epi_ref_df$id_chr[
      !is.na(epi_ref_df$base_period_chr) &
        epi_ref_df$base_period_chr != "dec2025"
    ]
    if (length(non_dec2025_rows_chr) > 0L) {
      message(
        "10_epi_spot_checks.R -- WARNING: reference row(s) with ",
        "base_period_chr != 'dec2025': ",
        paste(non_dec2025_rows_chr, collapse = ", "),
        ". Populate dec2025_rescale_ratio_num and epi_value_num before ",
        "trusting the tolerance check."
      )
    }
  }

  # Dual-tolerance gate: pass when EITHER absolute delta ($/hr) or
  # relative delta (%) is within tolerance. within_tol_bool is the
  # pass flag for the section-6 failure gate.
  spot_rows_df <- spot_rows_df |>
    dplyr::left_join(epi_ref_df, by = "id_chr") |>
    dplyr::mutate(
      delta_num          = new_value_num - epi_value_num,
      delta_pct_num      = dplyr::if_else(
        !is.na(epi_value_num) & epi_value_num != 0,
        100 * (new_value_num - epi_value_num) / epi_value_num,
        NA_real_
      ),
      within_tol_abs_bool = !is.na(delta_num) &
        abs(delta_num) <= tol_abs_dollars_per_hour_num,
      within_tol_rel_bool = !is.na(delta_pct_num) &
        abs(delta_pct_num) <= tol_rel_pct_num,
      within_tol_bool     = (!is.na(within_tol_abs_bool) &
                               within_tol_abs_bool) |
                             (!is.na(within_tol_rel_bool) &
                                within_tol_rel_bool)
    )

  message(
    "10_epi_spot_checks.R -- merged ",
    sum(!is.na(spot_rows_df$epi_value_num)), " of ",
    nrow(spot_rows_df), " reference values"
  )
} else {
  spot_rows_df <- spot_rows_df |>
    dplyr::mutate(
      epi_nominal_num         = NA_real_,
      epi_value_2025annual_num = NA_real_,
      dec2025_rescale_ratio_num = NA_real_,
      epi_value_num           = NA_real_,
      source_chr              = NA_character_,
      delta_num               = NA_real_,
      delta_pct_num           = NA_real_,
      within_tol_abs_bool     = NA,
      within_tol_rel_bool     = NA,
      within_tol_bool         = NA
    )

  message(
    "10_epi_spot_checks.R -- EPI reference CSV not found at ",
    epi_ref_csv_chr, "; delta and tolerance columns will be flagged ",
    "as 'reference pending'."
  )
}

###################################
###   5) Write spot-check MD    ###
###################################

md_lines_chr <- c(
  "# W10 EPI Spot-Check Verification",
  "",
  paste0("- **Computed:** ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  paste0(
    "- **Panel source:** `",
    fs::path_rel(panel_in_dir_chr, here::here()), "`"
  ),
  paste0(
    "- **Metric:** real hourly wage (EPI SWA publishes hourly only; ",
    "see script header for provenance)."
  ),
  paste0(
    "- **EPI reference source:** `",
    fs::path_rel(epi_ref_csv_chr, here::here()),
    ifelse(fs::file_exists(epi_ref_csv_chr), "` (present)", "` (MISSING)")
  ),
  paste0(
    "- **Tolerance (dual gate; cell passes if EITHER is satisfied):**",
    " |delta| <= $",
    format(tol_abs_dollars_per_hour_num, nsmall = 2L),
    "/hr in December 2025 PCE dollars OR |delta %| <= ",
    format(tol_rel_pct_num, nsmall = 1L), " percent."
  ),
  "",
  "## Spot-check values",
  "",
  paste(
    "| Cell | Year | Probability | N valid rows | New repo ($/hr) |",
    "EPI ref ($/hr) | Delta ($/hr) | Delta (%) |",
    "|delta| <= abs tol | |delta %| <= rel tol | Pass | Reference source |"
  ),
  paste(
    "|------|------|-------------|--------------|-----------------|",
    "----------------|--------------|-----------|",
    "------------------|-----------------------|------|------------------|"
  )
)

for (i in seq_len(nrow(spot_rows_df))) {
  new_value_chr <- ifelse(
    is.na(spot_rows_df$new_value_num[i]),
    "NA",
    format(round(spot_rows_df$new_value_num[i], 2), big.mark = ",", nsmall = 2L)
  )
  epi_value_chr <- ifelse(
    is.na(spot_rows_df$epi_value_num[i]),
    "pending",
    format(round(spot_rows_df$epi_value_num[i], 2), big.mark = ",", nsmall = 2L)
  )
  delta_chr <- ifelse(
    is.na(spot_rows_df$delta_num[i]),
    "--",
    format(round(spot_rows_df$delta_num[i], 2), nsmall = 2L)
  )
  delta_pct_chr <- ifelse(
    is.na(spot_rows_df$delta_pct_num[i]),
    "--",
    paste0(format(round(spot_rows_df$delta_pct_num[i], 2), nsmall = 2L), "%")
  )
  within_abs_chr <- ifelse(
    is.na(spot_rows_df$within_tol_abs_bool[i]),
    "--",
    ifelse(isTRUE(spot_rows_df$within_tol_abs_bool[i]), "yes", "NO")
  )
  within_rel_chr <- ifelse(
    is.na(spot_rows_df$within_tol_rel_bool[i]),
    "--",
    ifelse(isTRUE(spot_rows_df$within_tol_rel_bool[i]), "yes", "NO")
  )
  within_chr <- ifelse(
    is.na(spot_rows_df$within_tol_bool[i]),
    "--",
    ifelse(isTRUE(spot_rows_df$within_tol_bool[i]), "PASS", "FAIL")
  )
  source_chr <- ifelse(
    is.na(spot_rows_df$source_chr[i]),
    "--",
    spot_rows_df$source_chr[i]
  )

  md_lines_chr <- c(
    md_lines_chr,
    paste0(
      "| `", spot_rows_df$id_chr[i], "` | ",
      spot_rows_df$year_int[i], " | ",
      format(spot_rows_df$prob_num[i], nsmall = 2L), " | ",
      format(spot_rows_df$n_cell_int[i], big.mark = ","), " | ",
      new_value_chr, " | ",
      epi_value_chr, " | ",
      delta_chr, " | ",
      delta_pct_chr, " | ",
      within_abs_chr, " | ",
      within_rel_chr, " | ",
      within_chr, " | ",
      source_chr, " |"
    )
  )
}

md_lines_chr <- c(
  md_lines_chr,
  "",
  "## Interpretation",
  "",
  paste0(
    "The new-repo values are computed from `",
    fs::path_rel(panel_in_dir_chr, here::here()),
    "` using the Stata `_pctile` / EPI lower-quantile convention ",
    "(sort + cumulative EARNWT + which-first). This matches the ",
    "construction in `code/figure_a_percentiles.R` exactly."
  ),
  "",
  paste0(
    "The dual-tolerance gate (|delta| <= $",
    format(tol_abs_dollars_per_hour_num, nsmall = 2L),
    "/hr OR |delta %| <= ",
    format(tol_rel_pct_num, nsmall = 1L),
    " percent) is designed to accommodate: (1) the PCE vs. CPI-U-RS ",
    "deflator swap (Departure #1), which moves earlier-year reals ",
    "systematically downward by roughly the cumulative CPI-PCE gap ",
    "from the year of observation through 2025, (2) the dropped 1.5x ",
    "topcode fallback (Departure #2), which raises imputed values for ",
    "sex-year cells where the Pareto fit fails (cells where the CEPR ",
    "convention would substitute 1.5 * topcode), and (3) the retained ",
    "BLS-allocated earnings records (Departure #3), which can move the ",
    "lower percentiles in years with substantial allocation. The Pareto ",
    "estimator itself (OLS on a log-log binned empirical tail) is NOT a ",
    "departure: it matches current EPI `epiextracts` (`topcode_impute.ado`) ",
    "in expectation. Deltas inside the looser of the two tolerances are the ",
    "expected signature of the three departures and do not trigger a failure."
  ),
  ""
)

if (any(!is.na(spot_rows_df$within_tol_bool) &
        !spot_rows_df$within_tol_bool)) {
  md_lines_chr <- c(
    md_lines_chr,
    "## Failures",
    "",
    paste0(
      "One or more cells exceed BOTH the $",
      format(tol_abs_dollars_per_hour_num, nsmall = 2L),
      "/hr absolute tolerance AND the ",
      format(tol_rel_pct_num, nsmall = 1L),
      " percent relative tolerance. Investigate in order of expected ",
      "impact on the upper tail: Pareto bin count, upper-share ",
      "threshold, dynamic topcode convention (see `docs/decisions/` ",
      "for the methodological choices that most likely drive the ",
      "deviation)."
    ),
    ""
  )
}

writeLines(md_lines_chr, con = verif_out_md_chr)

message(
  "10_epi_spot_checks.R -- wrote ", verif_out_md_chr
)

###################################
###   6) Named stop on failure  ###
###################################
# If the EPI reference is present AND any cell is beyond tolerance,
# halt with a named error so the orchestrator records the failure
# rather than silently proceeding.

if (fs::file_exists(epi_ref_csv_chr)) {
  failing_cells_chr <- spot_rows_df$id_chr[
    !is.na(spot_rows_df$within_tol_bool) & !spot_rows_df$within_tol_bool
  ]
  if (length(failing_cells_chr) > 0L) {
    stop(
      "10_epi_spot_checks.R -- spot-check failure for cell(s): ",
      paste(failing_cells_chr, collapse = ", "),
      ". See ", verif_out_md_chr, " for details."
    )
  }
}

message("10_epi_spot_checks.R -- done.")
