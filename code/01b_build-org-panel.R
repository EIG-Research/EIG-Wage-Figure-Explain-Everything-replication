# 01b_build-org-panel -- EPI SWA wage-analysis sample gate, RF hours imputation, sex-separate Pareto topcode, EPI rotation-group bridge
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

rm(list = ls())
options(scipen = 999)
set.seed(42)

# Sourced by run_all.R inside new.env(parent = globalenv()).
#
# Reads the year-partitioned raw CPS ORG extract written by
# 01a_load-ipums-cps.R, applies the EPI State of Working America
# wage-analysis sample gate (wage-and-salary workers, excluding the
# self-employed, with a valid weekly or hourly wage source), applies
# IPUMS sentinels to the wage and hours variables, imputes "hours vary"
# records via a per-year random forest, identifies topcoded weekly
# wages per the regime for each year, fits a sex-separate Pareto
# distribution by OLS on log-log binned data over the top 20 percent,
# replaces topcoded values with the fitted mean above topcode, runs
# the EPI rotation-group bridge for 2023m4 through 2024m12, and
# writes a year-partitioned ORG panel parquet with two EPI flag columns:
#   - pareto_topcode_imputed_flag : TRUE iff a Pareto imputation replaced
#                                   the topcoded wage; FALSE if left at
#                                   topcode.
#   - hours_imputed_flag          : TRUE iff a model-imputed hours value
#                                   replaced a "hours vary" (997) sentinel
#                                   in the primary usual-hours variable.
#
# Departure pointers (see docs/decisions/ for full rationale):
#   - Departure #2 (no `1.5 * topcode` Pareto fallback):
#     docs/decisions/decision_02_no_pareto_fallback.md.
#   - Departure #3 (retain BLS-allocated records, toggle
#     apply_allocation_flag_drop_bool below):
#     docs/decisions/decision_03_retain_allocated_records.md.
#   - Departure #4 (random-forest hours imputation):
#     docs/decisions/decision_04_random_forest_hours_imputation.md.
#   - Departure #6 (EPI rotation-group bridge for 2023m4-2024m12):
#     docs/decisions/decision_06_epi_rotation_group_bridge.md.
#
# ASEC-sample records:
#   The 00a extract includes the March ASEC samples (cpsYYYY_03s), and
#   IPUMS delivers each ASEC respondent as a separate record
#   (ASECFLAG == 1) alongside the basic-monthly March record of the same
#   person (ASECFLAG == 2). From 1990 on the ASEC copy carries a positive
#   EARNWT, so without a filter every March holds each earner twice (and
#   2001-2004 also holds the ASEC oversample). Step 0 drops ASECFLAG == 1
#   records before any other processing; counts are written to
#   asec_records_dropped.csv. See
#   docs/decisions/decision_11_drop_asec_sample_records.md.
#
# Allocation flags:
#   IPUMS-CPS harmonizes the BLS raw allocation flags into the Q-prefix
#   convention. With `data_quality_flags = TRUE` set on EARNWEEK and
#   HOURWAGE in 00a, IPUMS returns QEARNWEE (covers EARNWEEK and
#   EARNWEEK2) and QHOURWAG (covers HOURWAGE and HOURWAGE2). Code 0 =
#   unaltered; nonzero = edited or allocated. Step 1c computes the
#   SWA drop mask for diagnostic logging and applies it only when
#   apply_allocation_flag_drop_bool is TRUE. Jan 1994 - Aug 1995 is
#   retained without drop because the BLS allocation flags are absent
#   for that window.
#
#   Hours allocation flags (QUHRSWORKORG, QUHRSWORK1) are pulled by 00a
#   for diagnostic use; 01b does not drop on them. Hours-vary (code 997)
#   records are RF-imputed.
#
# Usual-hours handling:
#   Primary usual-hours variable is coalesce(UHRSWORK1, UHRSWORKORG).
#   UHRSWORK1 is preferred because it is defined on a wider sample.
#   Special codes on these variables (IPUMS CPS):
#     - UHRSWORK1          : 997 = "Hours vary", 999 = NIU.
#                            (99 is a legitimate topcoded value: 99+ hours.)
#                            NOTE: despite the IPUMS "main job (1994+)" label,
#                            IPUMS populates this column from 1982 in this ORG
#                            extract -- before 1994 it carries the earner-study
#                            usual hours for ALL ORG earners (the data EPI reads
#                            from `ernush`), so salaried workers have usable
#                            hours back to 1982. Verified ~99.9% coverage for
#                            salaried earners 1983-1993 (temp/hours_coverage_probe.py).
#     - UHRSWORKORG        : 997 = "Hours vary", 998 = "Don't know",
#                            999 = NIU. Hourly-paid only and begins in 1989;
#                            it is NOT a salaried-hours source in any year.
#   Values >= 997 in either variable become NA before use in denominators.
#   Each row with missing primary hours is classified by reason (vary =
#   997, dont_know = UHRSWORKORG 998, niu = 999, other_missing); rows whose
#   reason is in hours_impute_reasons_chr (default: vary + dont_know) are
#   RF-imputed. NIU is excluded by default -- for salaried workers
#   UHRSWORKORG is NIU by construction (defined only for hourly-paid ORG
#   earners), so a salaried NIU on hours is a structural universe artifact,
#   not random non-response. The unimputed residual is logged to
#   hours_missingness_diagnostics.csv.
#
# Wage sentinels (IPUMS-encoded cent-level magic numbers, applied to the
# canonical wage columns before the sample gate):
#     - HOURWAGE / HOURWAGE2   : >= 999.99 -> NA
#     - EARNWEEK (pre-2023)    : >= 9999.99 -> NA
#     - EARNWEEK2 (2023+)      : >= 999999.99 -> NA
#
# Pareto fit notes:
#   - OLS on a log-log binned empirical tail with an 80th-percentile
#     threshold, sex-separate fit. Mathematically equivalent to current
#     EPI `epiextracts/code/ado/topcode_impute.ado`; the EIG implementation
#     differs only in bin layout (log-spaced bins between p80 and the
#     topcode vs. EPI's fixed $50-wide bins) and dependent variable form
#     (log empirical survival vs. log cumulative count). Not a departure.
#   - The fit INCLUDES topcoded rows (binned at the topcode mass), and
#     the survival estimate at each bin is EARNWT-weighted, mirroring EPI.
#   - No `1.5 * topcode` fallback (Departure #2).
#   - If OLS cannot be fit for a sex-year cell, topcoded values are
#     left at the topcode and pareto_topcode_imputed_flag is FALSE.
#
# No custom functions are defined. All transformations are inline.

source(here::here("code", "_utils", "00_packages.R"))

###################################
###   Configuration             ###
###################################

raw_dataset_dir_chr   <- here::here("data", "raw", "cps_org")
out_panel_dir_chr     <- here::here("data", "intermediate", "cps_org_panel")
pareto_diag_path_chr  <- here::here("data", "intermediate",
                                    "pareto_diagnostics.csv")
topcode_diag_path_chr <- here::here("data", "intermediate",
                                    "topcode_detection_diagnostics.csv")
#   ^ Per-year topcode detection diagnostic. Columns: year,
#     n_nonmissing, n_at_max, mass_share, detected_topcode_value,
#     expected_legacy_topcode_value, detected_matches_legacy.
hours_rf_diag_path_chr <- here::here("data", "intermediate",
                                     "hours_rf_diagnostics.csv")
#   ^ Per-year RF fit diagnostics. Columns: year, n_train_int,
#     n_imputed_int, oob_r_squared_num, oob_mse_num, num_trees_int,
#     mtry_int, fit_status_chr.
hours_rf_importance_path_chr <- here::here("data", "intermediate",
                                           "hours_rf_feature_importance.csv")
#   ^ Per-(year, feature) impurity-based importance from the ranger
#     fit. Columns: year, feature_chr, importance_num.
hours_missing_diag_path_chr <- here::here("data", "intermediate",
                                          "hours_missingness_diagnostics.csv")
#   ^ Per-(year, pay type, reason, imputed) missing-hours classification.
#     Columns: year, paidhour_int, reason_chr, imputed_bool, n_int. Lets a
#     reviewer see how many salaried rows fall out of the hourly series and
#     why (vary / dont_know / niu / other_missing).
asec_drop_diag_path_chr <- here::here("data", "intermediate",
                                      "asec_records_dropped.csv")
#   ^ Per-(year, month) count of ASEC-sample records dropped in step 0.
#     Columns: year_int, month_int, n_asec_records_int,
#     n_asec_earnwt_pos_int. Same layout as the AWP repo's diagnostic.

# Allocation-flag drop switch. TRUE applies the SWA drop in step 1c;
# FALSE (production default) retains all records. The drop mask is
# computed regardless of this flag for diagnostic logging.
# See docs/decisions/decision_03_retain_allocated_records.md.
apply_allocation_flag_drop_bool <- FALSE

# Topcode regime handling.
#
# Two-regime resolution strategy:
#   - Legacy years (1982-2022): use the documented EARNWEEK topcode
#     value from `legacy_topcode_lookup_df` directly ($999 for
#     1982-88, $1923 for 1989-97, $2884.60 for 1998-2022). Mirrors
#     EPI `epiextracts/code/variables/generate_weekpay.do`, which
#     hard-codes the topcode by date band. Empirical detection on
#     `nominal_weekly_wage_num` does not work for these years because
#     hourly workers' HOURWAGE * hours products produce outlier maxima
#     far above the EARNWEEK topcode mass.
#   - Post-legacy years (>= 2023): empirical mass-point detection at
#     the max of `nominal_weekly_wage_num`. BLS's dynamic top-3 %
#     weighted-average topcode in the *2 era produces a real mass at
#     the max.
#
# `topcoded_bool` is restricted to NON-HOURLY workers whose EARNWEEK
# is at the resolved topcode within $0.01. Hourly workers at the
# HOURWAGE topcode are NOT Pareto-adjusted, matching EPI
# (`generate_weekpay.do` applies the Pareto only to `weekpay_noadj`).
#
# Pareto scope is bounded by pareto_max_year_int. For 2023-2024, the
# fit uses the legacy $2,884.60 as the analytical threshold; the
# rotation-group bridge then overwrites the BLS-topcoded subset for
# 2023m4-2024m12. Years beyond 2024 skip the fit entirely.
# See docs/decisions/decision_06_epi_rotation_group_bridge.md.

# Topcode detection parameters.
pareto_max_year_int        <- 2024L
#   ^ EPI extends the legacy $2,884.60 topcode through December 2024 in
#     `epiextracts/code/variables/generate_weekpay.do`
#     (`if tm(1998m1) <= $date & $date <= tm(2024m12)`).
topcode_min_mass_share_num <- 0.001
#   ^ Floor share of non-missing weekly-wage rows for treating the max
#     value as a topcode mass point.
topcode_min_mass_count_int <- 10L
#   ^ Absolute minimum count of observations at the detected topcode.
topcode_tolerance_num      <- 0.01
#   ^ BLS reports CPS earnings to the cent; rows within $0.01 of the
#     topcode are treated as "at the topcode."

# Legacy topcode lookup table. Source: EPI
# `epiextracts/code/variables/generate_weekpay.do` (the date-range table
# that sets `local topcodeval`). Used as the analytical Pareto threshold
# in the per-year loop and as the expected value in the topcode-detection
# diagnostic CSV.
legacy_topcode_lookup_df <- tibble::tibble(
  year_int                      = c(1982:1988, 1989:1997, 1998:2024),
  expected_legacy_topcode_num   = c(
    rep(999.00,   length(1982:1988)),
    rep(1923.00,  length(1989:1997)),
    rep(2884.60,  length(1998:2024))
  )
)

# Pareto fit parameters. Inline constants (no custom functions per
# user-preferences rule).
pareto_upper_share_num <- 0.20
#   ^ Top 20 percent of the observed distribution (80th percentile and
#     above), per EPI methodology
#     (microdata.epi.org/methodology/wagevariables).
pareto_n_bins_int      <- 50L
#   ^ 50 log-spaced bins between the 80th percentile and the topcode.
pareto_min_fit_obs_int <- 30L
#   ^ Minimum per sex-year cell to attempt a Pareto fit. Cells below
#     this count emit fit_status = "insufficient_cell_observations".

# Random-forest hours imputation parameters. Hyperparameters are LOCKED
# at sensible defaults to keep per-year fits deterministic and
# reproducible. Do not retune per year.
# See docs/decisions/decision_04_random_forest_hours_imputation.md.
hours_min_training_rows_int <- 500L
#   ^ Below this floor the imputation is skipped and hours-vary rows
#     retain NA hours.
hours_rf_num_trees_int        <- 500L
#   ^ ranger default ensemble size.
hours_rf_min_node_size_int    <- 5L
#   ^ ranger default for regression.
hours_rf_seed_int             <- 42L
#   ^ Project seed (matches set.seed(42) at top of every script).
hours_rf_num_threads_int      <- 1L
#   ^ Single-thread for full determinism under set.seed; ranger with
#     num.threads > 1 is non-deterministic even with a fixed seed.
hours_lower_bound_num         <- 1
#   ^ Clamp predicted hours to at least 1 per week.
hours_upper_bound_num         <- 99
#   ^ Upper clamp at 99 matches the UHRSWORK1 top-code and EPI's
#     `replace hoursu1i = 99 if hoursu1i > 99` in generate_hoursu1i.do.

# Hours-missingness imputation scope. "Hours vary" (997) records have
# always been RF-imputed. This vector controls which missing-hours reasons
# are imputed. Recognized reasons:
#   "vary"      -- usual hours vary (UHRSWORKORG or UHRSWORK1 == 997)
#   "dont_know" -- ORG usual hours "Don't know" (UHRSWORKORG == 998)
#   "niu"       -- not in universe (UHRSWORKORG or UHRSWORK1 == 999)
# Default is c("vary", "dont_know"): the don't-know extension brings
# salaried workers who would otherwise drop out of the hourly series back
# in via a model-imputed hours value. "niu" is INTENTIONALLY excluded: for
# salaried (PAIDHOUR == 1) workers UHRSWORKORG is not-in-universe by
# construction (it is defined only for hourly-paid ORG earners; see
# https://cps.ipums.org/cps-action/variables/UHRSWORKORG), so a salaried
# NIU on hours is a structural universe artifact, not random non-response,
# and the RF -- trained only on workers who DO report hours -- would
# fabricate a value. To revert to the prior production behavior, set this
# to c("vary"). Changing this vector changes the reported hourly series and
# REQUIRES a validation rerun plus the 10_epi_spot_checks gate before
# publication. See docs/decisions/decision_07_hours_missingness_scope.md.
hours_impute_reasons_chr <- c("vary", "dont_know")

###################################
###   1) Locate year partitions ###
###################################

year_partition_paths_chr <- fs::dir_ls(
  raw_dataset_dir_chr, regexp = "year=\\d{4}", type = "directory"
)

if (length(year_partition_paths_chr) == 0L) {
  stop(
    "01b_build-org-panel.R -- no year partitions under ",
    raw_dataset_dir_chr, ". Run 01a_load-ipums-cps.R first."
  )
}

years_available_int <- sort(as.integer(
  stringr::str_extract(basename(year_partition_paths_chr), "\\d{4}")
))

message(
  "01b_build-org-panel.R -- years available: ",
  min(years_available_int), "-", max(years_available_int),
  " (", length(years_available_int), " partitions)"
)

fs::dir_create(out_panel_dir_chr, recurse = TRUE)

###################################
###   2) Diagnostic accumulators###
###################################
# Pareto diagnostics: one row per (year, sex) cell.
diagnostics_list <- vector("list", length(years_available_int) * 2L)
diag_idx_int     <- 1L

# Topcode detection diagnostics: one row per year.
topcode_diagnostics_list <- vector("list", length(years_available_int))
topcode_diag_idx_int     <- 1L

# RF hours-imputation diagnostics: one row per year (fit characteristics).
hours_rf_diagnostics_list <- vector("list", length(years_available_int))
hours_rf_diag_idx_int     <- 1L

# Per-year feature-importance accumulator: one row per (year, feature).
# NULL slots are filtered out at write time.
hours_rf_importance_list <- vector("list", length(years_available_int))
hours_rf_importance_idx_int <- 1L

# Per-year missing-hours diagnostic accumulator: one tibble per year
# (grouped by pay type, reason, imputed status). NULL slots dropped at
# write time.
hours_missing_diag_list <- vector("list", length(years_available_int))
hours_missing_diag_idx_int <- 1L

# ASEC-record drop counts: one tibble per year (one row per month).
asec_drop_list <- vector("list", length(years_available_int))
asec_drop_idx_int <- 1L

###################################
###   3) Per-year processing    ###
###################################

for (yr in years_available_int) {

  message("01b_build-org-panel.R -- processing year ", yr, " ...")

  in_parquet_chr <- fs::path(
    raw_dataset_dir_chr, paste0("year=", yr), "part-0.parquet"
  )

  if (!fs::file_exists(in_parquet_chr)) {
    stop("01b_build-org-panel.R -- missing partition: ", in_parquet_chr)
  }

  raw_yr_df <- arrow::read_parquet(in_parquet_chr)

  # 0) Drop ASEC-sample records (ASECFLAG == 1) before sentinels, the
  #    sample gate, the RF hours fit, Pareto, and the bridge. Keyed on
  #    ASECFLAG rather than on sample names: monthly sample IDs end in
  #    both "b" and "s", so the suffix is not a reliable marker. ASECFLAG
  #    is NA in non-March months and 2 for basic-monthly March records.
  #    See docs/decisions/decision_11_drop_asec_sample_records.md.
  if (!"ASECFLAG" %in% names(raw_yr_df)) {
    stop(
      "01b_build-org-panel.R -- ASECFLAG absent from year ", yr,
      " partition; it is required to drop ASEC-sample records. Re-run ",
      "01a against an extract that includes ASECFLAG."
    )
  }
  asec_bool <- !is.na(raw_yr_df$ASECFLAG) &
    as.integer(raw_yr_df$ASECFLAG) == 1L
  asec_drop_list[[asec_drop_idx_int]] <- tibble::tibble(
    month_int    = as.integer(raw_yr_df$MONTH),
    asec_bool    = asec_bool,
    earnwt_pos_bool = asec_bool & !is.na(raw_yr_df$EARNWT) &
      raw_yr_df$EARNWT > 0
  ) |>
    dplyr::group_by(month_int) |>
    dplyr::summarise(
      n_asec_records_int    = sum(asec_bool),
      n_asec_earnwt_pos_int = sum(earnwt_pos_bool),
      .groups               = "drop"
    ) |>
    dplyr::mutate(year_int = as.integer(yr), .before = 1L)
  if (any(asec_bool)) {
    message(
      "  ASEC-sample records dropped: ",
      format(sum(asec_drop_list[[asec_drop_idx_int]]$n_asec_records_int),
             big.mark = ","),
      " (", format(sum(asec_drop_list[[asec_drop_idx_int]]$n_asec_earnwt_pos_int),
                   big.mark = ","),
      " with EARNWT > 0)"
    )
  }
  asec_drop_idx_int <- asec_drop_idx_int + 1L

  raw_yr_df <- raw_yr_df[!asec_bool, , drop = FALSE]

  # Era flag: TRUE for years that use the *2 successor variables.
  # Determines which EARNWEEK sentinel applies for the current year.
  # 01a constructed EARNWEEK_CANON_NUM and HOURWAGE_CANON_NUM using
  # the same seam.
  use_star2_yr_bool <- yr >= 2023L

  # 1a) Apply IPUMS wage sentinels to the canonical wage columns.
  #     Sentinels are converted to NA before any downstream use
  #     (sample gate, weekly-wage computation, topcode detection).
  #     See header for full sentinel list.
  #     Note: 999.99 is the IPUMS not-in-universe / missing sentinel for the
  #     hourly rate, NOT the topcode. The legitimate hourly-rate topcode is
  #     $99.99 (usual hours < 29) for 2003 through 2023m3; like EPI, topcoded
  #     hourly rates are retained (not Pareto-adjusted), so this threshold
  #     must NOT be lowered to 99.99.
  #     See https://cps.ipums.org/cps/hourly_earnings_topcodes.shtml.
  hourwage_sentinel_mask_bool <- !is.na(raw_yr_df$HOURWAGE_CANON_NUM) &
    raw_yr_df$HOURWAGE_CANON_NUM >= 999.99
  raw_yr_df$HOURWAGE_CANON_NUM[hourwage_sentinel_mask_bool] <- NA_real_

  earnweek_sentinel_threshold_num <- if (use_star2_yr_bool) {
    999999.99
  } else {
    9999.99
  }
  earnweek_sentinel_mask_bool <- !is.na(raw_yr_df$EARNWEEK_CANON_NUM) &
    raw_yr_df$EARNWEEK_CANON_NUM >= earnweek_sentinel_threshold_num
  raw_yr_df$EARNWEEK_CANON_NUM[earnweek_sentinel_mask_bool] <- NA_real_

  n_hourwage_sentinel_int <- sum(hourwage_sentinel_mask_bool)
  n_earnweek_sentinel_int <- sum(earnweek_sentinel_mask_bool)
  if (n_hourwage_sentinel_int > 0L || n_earnweek_sentinel_int > 0L) {
    message(
      "  wage sentinels applied: HOURWAGE=",
      format(n_hourwage_sentinel_int, big.mark = ","),
      "; EARNWEEK=", format(n_earnweek_sentinel_int, big.mark = ","),
      " (era=", if (use_star2_yr_bool) "*2" else "legacy", ")"
    )
  }

  # 1b) EPI SWA wage-analysis sample gate: wage-and-salary workers
  #     with at least one valid wage source, excluding the self-employed.
  #       - PAIDHOUR: 0 = NIU, 1 = No (salaried), 2 = Yes (hourly).
  #       - CLASSWKR 10-14 = self-employed.
  #     Matches the EPI SWA wage-analysis sample, not the
  #     `epiextracts` extract sample (which gates on minsamp in {4, 8},
  #     orgwgt > 0, age >= 16; MIS and weight filters are enforced
  #     upstream in 01a, and the age >= 16 check below is a defensive
  #     belt-and-suspenders against a stray non-NIU PAIDHOUR for a
  #     younger record).
  is_wage_salary_bool    <- raw_yr_df$PAIDHOUR %in% c(1L, 2L)
  is_age_16_plus_bool    <- !is.na(raw_yr_df$AGE) & raw_yr_df$AGE >= 16L
  is_not_self_emp_bool   <- !(!is.na(raw_yr_df$CLASSWKR) &
                              raw_yr_df$CLASSWKR %in% 10:14)
  has_valid_weekly_bool  <- !is.na(raw_yr_df$EARNWEEK_CANON_NUM) &
    raw_yr_df$EARNWEEK_CANON_NUM > 0
  has_valid_hourly_bool  <- !is.na(raw_yr_df$HOURWAGE_CANON_NUM) &
    raw_yr_df$HOURWAGE_CANON_NUM > 0
  sample_gate_bool       <- is_wage_salary_bool &
    is_age_16_plus_bool &
    is_not_self_emp_bool &
    (has_valid_weekly_bool | has_valid_hourly_bool)

  panel_df <- raw_yr_df[sample_gate_bool, , drop = FALSE]

  n_post_gate_int <- nrow(panel_df)
  message(
    "  sample gate: ",
    format(n_post_gate_int, big.mark = ","), " rows kept (of ",
    format(nrow(raw_yr_df), big.mark = ","), ")"
  )

  # 1c) BLS-allocation drop mask on the primary wage source.
  #     QEARNWEE and QHOURWAG are IPUMS-harmonized Q-flags covering
  #     EARNWEEK / EARNWEEK2 and HOURWAGE / HOURWAGE2 respectively
  #     (no era routing). Code 0 = unaltered; nonzero = allocated.
  #     EPI's SWA drop rule excludes hourly-paid records with nonzero
  #     QHOURWAG and non-hourly records with nonzero QEARNWEE.
  #     Jan 1994 - Aug 1995 is retained without drop because the BLS
  #     allocation flags are absent for that window.
  #     Production toggle: apply_allocation_flag_drop_bool above.
  q_earnweek_col_chr <- "QEARNWEE"
  q_hourwage_col_chr <- "QHOURWAG"

  missing_qflag_cols_chr <- setdiff(
    c(q_earnweek_col_chr, q_hourwage_col_chr), names(panel_df)
  )

  if (length(missing_qflag_cols_chr) > 0L) {
    stop(
      "01b_build-org-panel.R -- expected Q-flag column(s) absent from ",
      "year ", yr, " partition: ",
      paste(missing_qflag_cols_chr, collapse = ", "),
      ". Re-run 01a_load-ipums-cps.R against a fresh IPUMS extract built ",
      "with data_quality_flags = TRUE. If the partition predates the ",
      "Q-flag switch, delete data/intermediate/cps_org_panel/year=", yr,
      "/ and re-run the pipeline from 00a."
    )
  }

  q_weekly_num_vec <- as.numeric(panel_df[[q_earnweek_col_chr]])
  q_hourly_num_vec <- as.numeric(panel_df[[q_hourwage_col_chr]])

  hourly_paid_bool    <- panel_df$PAIDHOUR == 2L
  nonhourly_paid_bool <- panel_df$PAIDHOUR == 1L

  in_1994_1995_gap_bool <- if (yr == 1994L) {
    rep(TRUE, nrow(panel_df))
  } else if (yr == 1995L) {
    !is.na(panel_df$MONTH) & panel_df$MONTH <= 8L
  } else {
    rep(FALSE, nrow(panel_df))
  }

  alloc_drop_bool <-
    !in_1994_1995_gap_bool &
    (
      (hourly_paid_bool &
       !is.na(q_hourly_num_vec) & q_hourly_num_vec != 0) |
      (nonhourly_paid_bool &
       !is.na(q_weekly_num_vec) & q_weekly_num_vec != 0)
    )

  # Diagnostic counts are computed regardless of whether the drop is
  # applied, so the run log reports how many rows the EPI canonical rule
  # WOULD remove for this year.
  n_alloc_drop_candidate_int <- sum(alloc_drop_bool)
  n_gap_kept_int             <- sum(in_1994_1995_gap_bool)

  if (apply_allocation_flag_drop_bool) {
    panel_df <- panel_df[!alloc_drop_bool, , drop = FALSE]
    message(
      "  allocation-flag drop APPLIED (apply_allocation_flag_drop_bool = TRUE): ",
      format(n_alloc_drop_candidate_int, big.mark = ","),
      " rows dropped (EPI canonical, nonzero Q-flag on primary wage source); ",
      format(n_gap_kept_int, big.mark = ","),
      " rows retained in Jan 1994 - Aug 1995 allocation-data gap (per EPI)"
    )
  } else {
    message(
      "  allocation-flag drop SKIPPED (apply_allocation_flag_drop_bool = FALSE, ",
      "CEPR/Schmitt 2003 convention): ",
      format(n_alloc_drop_candidate_int, big.mark = ","),
      " rows would have been dropped under the EPI canonical rule and are ",
      "RETAINED in the panel; ",
      format(n_gap_kept_int, big.mark = ","),
      " rows in the Jan 1994 - Aug 1995 allocation-data gap are also retained ",
      "(per EPI)"
    )
  }

  # 2) Primary usual-hours variable and missing-hours classification.
  #    - Capture the RAW (pre-sentinel) hours codes on UHRSWORKORG and
  #      UHRSWORK1 so the missing-hours reason can be classified after the
  #      NA sentinels are applied (the sentinel erases the code otherwise).
  #    - Apply NA sentinels:
  #        UHRSWORK1   : >= 997 -> NA  (997 hours vary, 999 NIU)
  #        UHRSWORKORG : >= 997 -> NA  (997 hours vary, 998 Don't know,
  #                                     999 NIU)
  #    - Construct primary hours as coalesce(UHRSWORK1, UHRSWORKORG);
  #      UHRSWORK1 is preferred (defined on a wider sample),
  #      UHRSWORKORG is the ORG-only (hourly-paid) fallback.
  #    - Classify each missing-hours row by reason and flag for RF
  #      imputation those whose reason is in hours_impute_reasons_chr.
  uhrsworkorg_raw_int <- as.integer(panel_df$UHRSWORKORG)
  uhrswork1_raw_int   <- as.integer(panel_df$UHRSWORK1)

  uhrsworkorg_num_vec <- as.numeric(panel_df$UHRSWORKORG)
  uhrsworkorg_num_vec[!is.na(uhrsworkorg_num_vec) &
                      uhrsworkorg_num_vec >= 997] <- NA_real_

  uhrswork1_num_vec <- as.numeric(panel_df$UHRSWORK1)
  uhrswork1_num_vec[!is.na(uhrswork1_num_vec) &
                    uhrswork1_num_vec >= 997] <- NA_real_

  hours_primary_num_vec <- dplyr::coalesce(
    uhrswork1_num_vec, uhrsworkorg_num_vec
  )

  hourly_paid_bool <- panel_df$PAIDHOUR == 2L

  # Classify the reason primary hours are missing, by priority:
  #   vary (997) > dont_know (UHRSWORKORG 998) > niu (999) > other_missing.
  # Reason is NA for rows whose primary hours are present.
  missing_hours_bool <- is.na(hours_primary_num_vec)
  reason_vary_bool <-
    (!is.na(uhrsworkorg_raw_int) & uhrsworkorg_raw_int == 997L) |
    (!is.na(uhrswork1_raw_int)   & uhrswork1_raw_int   == 997L)
  reason_dontknow_bool <-
    !is.na(uhrsworkorg_raw_int) & uhrsworkorg_raw_int == 998L
  reason_niu_bool <-
    (!is.na(uhrsworkorg_raw_int) & uhrsworkorg_raw_int == 999L) |
    (!is.na(uhrswork1_raw_int)   & uhrswork1_raw_int   == 999L)

  hours_missing_reason_chr <- rep(NA_character_, nrow(panel_df))
  hours_missing_reason_chr[missing_hours_bool & reason_vary_bool] <- "vary"
  hours_missing_reason_chr[missing_hours_bool &
                           is.na(hours_missing_reason_chr) &
                           reason_dontknow_bool] <- "dont_know"
  hours_missing_reason_chr[missing_hours_bool &
                           is.na(hours_missing_reason_chr) &
                           reason_niu_bool] <- "niu"
  hours_missing_reason_chr[missing_hours_bool &
                           is.na(hours_missing_reason_chr)] <- "other_missing"

  # Rows to RF-impute: missing primary hours whose reason is in the
  # configured scope (default vary + dont_know; niu and other_missing are
  # excluded). Named alloc_hours_bool for downstream compatibility with the
  # RF fit/predict block below.
  alloc_hours_bool <- missing_hours_bool &
    !is.na(hours_missing_reason_chr) &
    hours_missing_reason_chr %in% hours_impute_reasons_chr

  # 3) Initialize derived columns and flags
  panel_df$hours_imputed_flag          <- FALSE
  panel_df$pareto_topcode_imputed_flag <- FALSE
  # uhrsworkorg_used_num retains its name for downstream compatibility but
  # now holds the primary hours (UHRSWORK1 preferred, UHRSWORKORG fallback).
  panel_df$uhrsworkorg_used_num        <- hours_primary_num_vec
  panel_df$hours_primary_source_num    <- hours_primary_num_vec

  # 4) Random-forest impute "hours vary" rows.
  #    Per-year ranger fit on non-hours-vary, non-allocated, positive-
  #    hours training observations weighted by EARNWT. Hyperparameters
  #    are locked at the defaults from the configuration block above.
  #    Categorical features are recoded to factors with an explicit
  #    "NIU" level so ranger handles missingness via an explicit
  #    level (CITIZEN NIU pre-1994, UNION NIU pre-1983, etc.).
  #    See docs/decisions/decision_04_random_forest_hours_imputation.md.

  # Preflight: verify all RF feature columns are present in the panel.
  # CITIZEN, IND1990, and UNION are required by the RF specification; if the
  # IPUMS extract pre-dates the required RF feature set, fail fast with
  # an actionable error rather than producing a misleading stack trace
  # inside ranger.
  rf_feature_cols_chr <- c(
    "AGE", "SEX", "EDUC", "RACE", "HISPAN", "MARST",
    "STATEFIP", "CLASSWKR", "OCC2010",
    "CITIZEN", "IND1990", "UNION"
  )
  missing_rf_cols_chr <- setdiff(rf_feature_cols_chr, names(panel_df))
  if (length(missing_rf_cols_chr) > 0L) {
    stop(
      "01b_build-org-panel.R -- year ", yr,
      ": expected RF hours-imputation feature column(s) absent from ",
      "partition: ", paste(missing_rf_cols_chr, collapse = ", "),
      ". The IPUMS extract requires CITIZEN, IND1990, and UNION. ",
      "Re-run 00a with run_00a = TRUE (this triggers a fresh IPUMS ",
      "extract submission because the requested variable list has ",
      "changed), then re-run 01a and 01b. If the partition is stale, ",
      "delete data/raw/cps_org/year=", yr,
      "/ and re-run the pipeline from 00a."
    )
  }

  # Construct the feature data frame for the full panel. Each
  # categorical feature is recoded to a factor with NA -> "NIU" so
  # ranger handles missingness via an explicit level rather than
  # surrogate splits.
  hours_rf_features_df <- tibble::tibble(
    AGE_num    = as.numeric(panel_df$AGE),
    SEX_fct    = factor(dplyr::if_else(is.na(panel_df$SEX),      "NIU",
                                       as.character(panel_df$SEX))),
    EDUC_fct   = factor(dplyr::if_else(is.na(panel_df$EDUC),     "NIU",
                                       as.character(panel_df$EDUC))),
    RACE_fct   = factor(dplyr::if_else(is.na(panel_df$RACE),     "NIU",
                                       as.character(panel_df$RACE))),
    HISPAN_fct = factor(dplyr::if_else(is.na(panel_df$HISPAN),   "NIU",
                                       as.character(panel_df$HISPAN))),
    MARST_fct  = factor(dplyr::if_else(is.na(panel_df$MARST),    "NIU",
                                       as.character(panel_df$MARST))),
    STATEFIP_fct = factor(dplyr::if_else(is.na(panel_df$STATEFIP), "NIU",
                                         as.character(panel_df$STATEFIP))),
    CLASSWKR_fct = factor(dplyr::if_else(is.na(panel_df$CLASSWKR), "NIU",
                                         as.character(panel_df$CLASSWKR))),
    OCC2010_fct  = factor(dplyr::if_else(is.na(panel_df$OCC2010),  "NIU",
                                         as.character(panel_df$OCC2010))),
    CITIZEN_fct  = factor(dplyr::if_else(is.na(panel_df$CITIZEN),  "NIU",
                                         as.character(panel_df$CITIZEN))),
    IND1990_fct  = factor(dplyr::if_else(is.na(panel_df$IND1990),  "NIU",
                                         as.character(panel_df$IND1990))),
    UNION_fct    = factor(dplyr::if_else(is.na(panel_df$UNION),    "NIU",
                                         as.character(panel_df$UNION)))
  )

  fit_train_bool <- !alloc_hours_bool &
    !is.na(hours_primary_num_vec) & hours_primary_num_vec > 0 &
    !is.na(panel_df$EARNWT) & panel_df$EARNWT > 0

  rf_attempted_bool <- sum(fit_train_bool) >= hours_min_training_rows_int &&
    any(alloc_hours_bool)

  if (rf_attempted_bool) {

    rf_train_df              <- hours_rf_features_df[fit_train_bool, , drop = FALSE]
    rf_train_df$target_num   <- hours_primary_num_vec[fit_train_bool]
    rf_train_weights_num     <- panel_df$EARNWT[fit_train_bool]

    rf_fit <- ranger::ranger(
      formula                   = target_num ~ .,
      data                      = rf_train_df,
      case.weights              = rf_train_weights_num,
      num.trees                 = hours_rf_num_trees_int,
      min.node.size             = hours_rf_min_node_size_int,
      splitrule                 = "variance",
      respect.unordered.factors = "order",
      importance                = "impurity",
      seed                      = hours_rf_seed_int,
      num.threads               = hours_rf_num_threads_int
    )

    # Predict for hours-vary rows. ranger returns predictions in the
    # same order as the input data frame; align with alloc_hours_bool.
    rf_predict_df          <- hours_rf_features_df[alloc_hours_bool, , drop = FALSE]
    predicted_hours_num    <- stats::predict(
      rf_fit, data = rf_predict_df, num.threads = hours_rf_num_threads_int
    )$predictions
    predicted_hours_num    <- round(predicted_hours_num)
    predicted_hours_num    <- pmin(
      pmax(predicted_hours_num, hours_lower_bound_num),
      hours_upper_bound_num
    )

    panel_df$uhrsworkorg_used_num[alloc_hours_bool] <- predicted_hours_num
    panel_df$hours_imputed_flag[alloc_hours_bool]   <- TRUE

    # Accumulate per-year diagnostics.
    hours_rf_diagnostics_list[[hours_rf_diag_idx_int]] <- tibble::tibble(
      year                   = yr,
      n_train_int            = as.integer(sum(fit_train_bool)),
      n_imputed_int          = as.integer(sum(alloc_hours_bool)),
      oob_r_squared_num      = as.numeric(rf_fit$r.squared),
      oob_mse_num            = as.numeric(rf_fit$prediction.error),
      num_trees_int          = as.integer(hours_rf_num_trees_int),
      mtry_int               = as.integer(rf_fit$mtry),
      fit_status_chr         = "rf_fit_success"
    )
    hours_rf_diag_idx_int <- hours_rf_diag_idx_int + 1L

    # Accumulate per-(year, feature) importance.
    importance_num_vec <- rf_fit$variable.importance
    hours_rf_importance_list[[hours_rf_importance_idx_int]] <- tibble::tibble(
      year           = yr,
      feature_chr    = names(importance_num_vec),
      importance_num = as.numeric(importance_num_vec)
    )
    hours_rf_importance_idx_int <- hours_rf_importance_idx_int + 1L

    message(
      "  RF hours imputation: fit on ",
      format(sum(fit_train_bool), big.mark = ","),
      " rows; imputed ", format(sum(alloc_hours_bool), big.mark = ","),
      " rows; OOB R^2=", format(round(rf_fit$r.squared, 4L), nsmall = 4L),
      "; mtry=", rf_fit$mtry
    )
  } else {
    # Capture skip reason for the diagnostic CSV (training thin or no
    # hours-vary rows).
    skip_reason_chr <- if (sum(fit_train_bool) < hours_min_training_rows_int) {
      "insufficient_training_rows"
    } else {
      "no_hours_vary_rows"
    }
    hours_rf_diagnostics_list[[hours_rf_diag_idx_int]] <- tibble::tibble(
      year                   = yr,
      n_train_int            = as.integer(sum(fit_train_bool)),
      n_imputed_int          = 0L,
      oob_r_squared_num      = NA_real_,
      oob_mse_num            = NA_real_,
      num_trees_int          = NA_integer_,
      mtry_int               = NA_integer_,
      fit_status_chr         = skip_reason_chr
    )
    hours_rf_diag_idx_int <- hours_rf_diag_idx_int + 1L

    message(
      "  RF hours imputation skipped (",
      skip_reason_chr,
      "; training rows: ",
      format(sum(fit_train_bool), big.mark = ","),
      "; hours-vary rows: ", sum(alloc_hours_bool), ")"
    )
  }

  # Free the feature frame: ~150k rows x 12 columns at year scope is
  # ~30MB and not used after the predict step.
  rm(hours_rf_features_df)

  # Per-year missing-hours diagnostic: among rows with missing primary
  # hours, count by pay type, reason, and whether the RF actually imputed
  # the value (hours_imputed_flag is TRUE only when a fit succeeded).
  # Salaried (paidhour_int == 1) rows with reason "niu"/"other_missing",
  # and any unimputed row, are the records that fall out of the hourly
  # series. See docs/decisions/decision_07_hours_missingness_scope.md.
  if (any(missing_hours_bool)) {
    miss_idx_int <- which(missing_hours_bool)
    hours_missing_diag_list[[hours_missing_diag_idx_int]] <- tibble::tibble(
      year         = yr,
      paidhour_int = as.integer(panel_df$PAIDHOUR[miss_idx_int]),
      reason_chr   = hours_missing_reason_chr[miss_idx_int],
      imputed_bool = panel_df$hours_imputed_flag[miss_idx_int]
    ) |>
      dplyr::group_by(year, paidhour_int, reason_chr, imputed_bool) |>
      dplyr::summarise(n_int = dplyr::n(), .groups = "drop")
    hours_missing_diag_idx_int <- hours_missing_diag_idx_int + 1L
  }

  # 5) Construct nominal weekly wage per EPI hourly-vs-weekly routing.
  #    - Hourly-paid: weekly wage = HOURWAGE_CANON_NUM * hours_used
  #    - Non-hourly : weekly wage = EARNWEEK_CANON_NUM
  #    The canonical wage columns were constructed in 01a step 8b and
  #    carry the legacy series for YEAR < 2023 and the *2 series for
  #    YEAR >= 2023.
  panel_df$nominal_weekly_wage_num <- NA_real_
  panel_df$nominal_weekly_wage_num[hourly_paid_bool] <-
    panel_df$HOURWAGE_CANON_NUM[hourly_paid_bool] *
    panel_df$uhrsworkorg_used_num[hourly_paid_bool]
  panel_df$nominal_weekly_wage_num[!hourly_paid_bool] <-
    panel_df$EARNWEEK_CANON_NUM[!hourly_paid_bool]

  # Preserve the pre-imputation weekly wage so the post-Pareto
  # rotation-group bridge can reference raw values from MISH == 4
  # records when computing bridge values for MISH == 8 records in
  # 2023m4-2024m3. The Pareto block overwrites nominal_weekly_wage_num
  # for topcoded rows in-place.
  panel_df$nominal_weekly_wage_raw_num <- panel_df$nominal_weekly_wage_num

  # 6) Topcode determination for this year.
  #    Legacy years (1982-2022) use the documented EARNWEEK topcode
  #    value directly, mirroring EPI
  #    `epiextracts/code/variables/generate_weekpay.do`. Post-legacy
  #    years (>= 2023) use empirical mass-point detection at the max of
  #    `nominal_weekly_wage_num`. The `topcoded_bool` mask is restricted
  #    to non-hourly workers; hourly workers at the HOURWAGE topcode are
  #    NOT Pareto-adjusted, matching EPI `generate_weekpay.do` and
  #    `generate_wage.do`.

  nonmissing_wage_bool <- !is.na(panel_df$nominal_weekly_wage_num)
  n_nonmissing_int <- sum(nonmissing_wage_bool)

  # Look up the documented legacy topcode value for this year. Returns
  # numeric(0) for years outside the lookup (>= 2023).
  legacy_lookup_match_num <- legacy_topcode_lookup_df$expected_legacy_topcode_num[
    legacy_topcode_lookup_df$year_int == yr
  ]
  documented_topcode_num <- if (length(legacy_lookup_match_num) == 1L) {
    legacy_lookup_match_num
  } else {
    NA_real_
  }

  weekly_tc_num      <- NA_real_
  n_at_topcode_int   <- 0L
  mass_share_num     <- 0
  has_topcode_bool   <- FALSE
  topcode_source_chr <- NA_character_

  if (!is.na(documented_topcode_num)) {
    # Legacy years (1982-2022): use the documented value directly.
    # Mass at-or-above the documented value is computed on the
    # non-hourly subset (EARNWEEK is what BLS actually topcodes).
    # Comparison is `EARNWEEK >= documented_topcode_num -
    # topcode_tolerance_num`, mirroring EPI's
    # `replace varlist = topcodeval if varlist >= topcodeval` in
    # `topcode_impute.ado`. Catches the documented value, the +1c
    # BLS-stored value ($2884.61 when documented is $2884.60), and
    # rare slightly-above-topcode artifacts ($2885.00 in some years).
    weekly_tc_num <- documented_topcode_num
    topcode_source_chr <- "documented_legacy_lookup"

    nonhourly_nonmissing_bool <- !hourly_paid_bool &
      !is.na(panel_df$EARNWEEK_CANON_NUM)
    n_nonhourly_nonmissing_int <- sum(nonhourly_nonmissing_bool)

    nonhourly_at_tc_bool <- nonhourly_nonmissing_bool &
      panel_df$EARNWEEK_CANON_NUM >=
        (documented_topcode_num - topcode_tolerance_num)
    n_at_topcode_int <- sum(nonhourly_at_tc_bool)
    mass_share_num   <- if (n_nonhourly_nonmissing_int > 0L) {
      n_at_topcode_int / n_nonhourly_nonmissing_int
    } else {
      0
    }
    has_topcode_bool <- n_at_topcode_int >= topcode_min_mass_count_int
  } else if (n_nonmissing_int > 0L) {
    # Post-legacy years (>= 2023): empirical mass-point detection at
    # the max of nominal_weekly_wage_num. Same mass thresholds as
    # before. weekly_tc_num is the empirical max if both thresholds
    # pass; otherwise no topcode is treated as present.
    candidate_tc_num <- max(
      panel_df$nominal_weekly_wage_num[nonmissing_wage_bool],
      na.rm = TRUE
    )
    at_max_bool <- nonmissing_wage_bool &
      abs(panel_df$nominal_weekly_wage_num - candidate_tc_num) <
        topcode_tolerance_num
    n_at_topcode_int <- sum(at_max_bool)
    mass_share_num   <- n_at_topcode_int / n_nonmissing_int
    has_topcode_bool <-
      n_at_topcode_int >= topcode_min_mass_count_int &&
      mass_share_num   >= topcode_min_mass_share_num
    if (has_topcode_bool) {
      weekly_tc_num <- candidate_tc_num
    }
    topcode_source_chr <- "empirical_mass_point"
  }

  # Identify the topcoded observations to be Pareto-imputed. Restrict
  # to non-hourly workers whose EARNWEEK is at or above the resolved
  # topcode (within $0.01 downward for floating-point safety).
  # `>=` semantics match EPI's
  # `replace varlist = topcodeval if varlist >= topcodeval` and
  # capture the IPUMS-stored value ($2884.61 where documented is
  # $2884.60) plus rare $2885.00 whole-dollar-rounding artifacts.
  topcoded_bool <- if (has_topcode_bool) {
    !hourly_paid_bool &
      !is.na(panel_df$EARNWEEK_CANON_NUM) &
      panel_df$EARNWEEK_CANON_NUM >=
        (weekly_tc_num - topcode_tolerance_num)
  } else {
    rep(FALSE, nrow(panel_df))
  }

  n_topcoded_int <- sum(topcoded_bool)

  if (has_topcode_bool) {
    message(
      "  topcode resolved ($",
      format(round(weekly_tc_num, 2), big.mark = ","),
      "; source=", topcode_source_chr,
      "): non-hourly mass at-or-above count ",
      format(n_at_topcode_int, big.mark = ","),
      " (", format(round(mass_share_num * 100, 3), nsmall = 3L),
      "% of non-hourly non-missing)"
    )
  } else {
    message(
      "  no topcode resolved (source=",
      if (is.na(topcode_source_chr)) "unknown" else topcode_source_chr,
      "; mass at-or-above candidate value: ",
      format(n_at_topcode_int, big.mark = ","), " rows, ",
      format(round(mass_share_num * 100, 3), nsmall = 3L), "%)"
    )
  }

  # Diagnostic CSV row. For legacy years the audit signal is
  # `n_at_topcode_int`; if it drops below `topcode_min_mass_count_int`
  # the warning at the end of the script flags the year for manual
  # review.
  expected_legacy_topcode_num <- documented_topcode_num

  detected_matches_legacy_bool <- if (is.na(expected_legacy_topcode_num)) {
    NA
  } else if (!has_topcode_bool) {
    FALSE
  } else {
    TRUE
  }

  topcode_diagnostics_list[[topcode_diag_idx_int]] <- tibble::tibble(
    year                            = yr,
    topcode_source_chr              = topcode_source_chr,
    n_nonmissing_int                = as.integer(n_nonmissing_int),
    n_at_topcode_int                = as.integer(n_at_topcode_int),
    mass_share_num                  = mass_share_num,
    has_topcode_bool                = has_topcode_bool,
    resolved_topcode_value_num      = if (has_topcode_bool) weekly_tc_num else NA_real_,
    expected_legacy_topcode_num     = expected_legacy_topcode_num,
    detected_matches_legacy_bool    = detected_matches_legacy_bool
  )
  topcode_diag_idx_int <- topcode_diag_idx_int + 1L

  # 7) Sex-separate Pareto fit (OLS on log-log binned top 20 percent).
  #    Mirrors current EPI
  #    `epiextracts/code/ado/topcode_impute.ado`:
  #      (a) The fit INCLUDES topcoded rows (binned at the topcode
  #          mass).
  #      (b) Survival estimate is EARNWT-weighted (equivalent to EPI's
  #          `[pw=orgwgt]`).
  #    Years after pareto_max_year_int skip the fit; topcoded rows (if
  #    detected) remain at the topcode value with
  #    pareto_topcode_imputed_flag = FALSE.
  for (sex_val_int in c(1L, 2L)) {

    sex_cell_bool <- panel_df$SEX == sex_val_int &
      !is.na(panel_df$nominal_weekly_wage_num) &
      panel_df$nominal_weekly_wage_num > 0 &
      !is.na(panel_df$EARNWT) &
      panel_df$EARNWT > 0

    n_in_cell_int <- sum(sex_cell_bool)

    # Count topcoded rows that will be left at topcode if fit fails
    sex_topcoded_bool <- panel_df$SEX == sex_val_int & topcoded_bool
    n_sex_topcoded_int <- sum(sex_topcoded_bool)

    # Years beyond pareto_max_year_int skip the Pareto fit. Topcoded
    # rows remain at the topcode value with
    # pareto_topcode_imputed_flag = FALSE. The post-Pareto bridge
    # block (after the year loop) handles 2023m4-2024m12 against
    # `nominal_weekly_wage_raw_num`.
    if (yr > pareto_max_year_int) {
      diagnostics_list[[diag_idx_int]] <- tibble::tibble(
        year                  = yr,
        sex                   = sex_val_int,
        n_in_cell_int         = as.integer(n_in_cell_int),
        n_above_threshold_int = 0L,
        fitted_alpha_num      = NA_real_,
        n_imputed_int         = 0L,
        n_left_at_topcode_int = as.integer(n_sex_topcoded_int),
        fit_status            = "skipped_post_pareto_max_year"
      )
      diag_idx_int <- diag_idx_int + 1L
      next
    }

    # No detectable topcode this year -> nothing to impute. Skipping
    # here also avoids dereferencing weekly_tc_num (NA when
    # has_topcode_bool is FALSE) in the Pareto fit below, which would
    # propagate NA into the `if()` guards.
    if (!has_topcode_bool) {
      diagnostics_list[[diag_idx_int]] <- tibble::tibble(
        year                  = yr,
        sex                   = sex_val_int,
        n_in_cell_int         = as.integer(n_in_cell_int),
        n_above_threshold_int = 0L,
        fitted_alpha_num      = NA_real_,
        n_imputed_int         = 0L,
        n_left_at_topcode_int = 0L,
        fit_status            = "no_topcode_detected"
      )
      diag_idx_int <- diag_idx_int + 1L
      next
    }

    if (n_in_cell_int < pareto_min_fit_obs_int) {
      diagnostics_list[[diag_idx_int]] <- tibble::tibble(
        year                  = yr,
        sex                   = sex_val_int,
        n_in_cell_int         = as.integer(n_in_cell_int),
        n_above_threshold_int = 0L,
        fitted_alpha_num      = NA_real_,
        n_imputed_int         = 0L,
        n_left_at_topcode_int = as.integer(n_sex_topcoded_int),
        fit_status            = "insufficient_cell_observations"
      )
      diag_idx_int <- diag_idx_int + 1L
      next
    }

    # EARNWT-weighted 80th-percentile threshold across the full sex-year
    # cell (including topcoded rows at the topcode value; matches EPI's
    # `_pctile ... [aw=orgwgt]` step in `topcode_impute.ado`).
    # stats::quantile() does not accept weights, so the threshold is
    # computed manually via the cumulative-weight rule equivalent to
    # Stata's _pctile convention: smallest sorted value whose
    # cumulative weight is at least p * total weight.
    sorted_idx_int     <- order(panel_df$nominal_weekly_wage_num[sex_cell_bool])
    sorted_wages_num   <- panel_df$nominal_weekly_wage_num[sex_cell_bool][sorted_idx_int]
    sorted_weights_num <- panel_df$EARNWT[sex_cell_bool][sorted_idx_int]
    cum_weight_num     <- cumsum(sorted_weights_num)
    total_weight_num   <- cum_weight_num[length(cum_weight_num)]
    threshold_80_num   <- sorted_wages_num[
      which(cum_weight_num >= (1 - pareto_upper_share_num) * total_weight_num)[1L]
    ]

    above_thresh_cell_bool <- sex_cell_bool &
      panel_df$nominal_weekly_wage_num >= threshold_80_num

    n_above_thresh_int <- sum(above_thresh_cell_bool)

    if (n_above_thresh_int < pareto_min_fit_obs_int ||
        threshold_80_num >= weekly_tc_num) {
      diagnostics_list[[diag_idx_int]] <- tibble::tibble(
        year                  = yr,
        sex                   = sex_val_int,
        n_in_cell_int         = as.integer(n_in_cell_int),
        n_above_threshold_int = as.integer(n_above_thresh_int),
        fitted_alpha_num      = NA_real_,
        n_imputed_int         = 0L,
        n_left_at_topcode_int = as.integer(n_sex_topcoded_int),
        fit_status            = "insufficient_above_threshold"
      )
      diag_idx_int <- diag_idx_int + 1L
      next
    }

    # Log-spaced bins between p80 and the topcode
    bin_edges_num  <- exp(seq(
      from       = log(threshold_80_num),
      to         = log(weekly_tc_num),
      length.out = pareto_n_bins_int + 1L
    ))
    bin_lowers_num <- bin_edges_num[-length(bin_edges_num)]

    # EARNWT-weighted empirical survival at each bin lower across the
    # FULL sex-year cell (topcoded rows included; their mass shows up
    # in the rightmost bin). Survival is computed as
    #   S(b) = sum(EARNWT * 1{wage >= b}) / sum(EARNWT)
    # which mirrors EPI's `[pw=orgwgt]` cumulative-count construction
    # up to a normalization constant (the slope estimate is invariant
    # to that constant).
    cell_wages_num    <- panel_df$nominal_weekly_wage_num[sex_cell_bool]
    cell_weights_num  <- panel_df$EARNWT[sex_cell_bool]
    cell_total_wt_num <- sum(cell_weights_num)

    surv_estimate_num <- vapply(
      bin_lowers_num,
      function(b) {
        sum(cell_weights_num * (cell_wages_num >= b)) / cell_total_wt_num
      },
      numeric(1L)
    )

    valid_bins_bool <- surv_estimate_num > 0

    if (sum(valid_bins_bool) < 5L) {
      diagnostics_list[[diag_idx_int]] <- tibble::tibble(
        year                  = yr,
        sex                   = sex_val_int,
        n_in_cell_int         = as.integer(n_in_cell_int),
        n_above_threshold_int = as.integer(n_above_thresh_int),
        fitted_alpha_num      = NA_real_,
        n_imputed_int         = 0L,
        n_left_at_topcode_int = as.integer(n_sex_topcoded_int),
        fit_status            = "too_few_valid_bins"
      )
      diag_idx_int <- diag_idx_int + 1L
      next
    }

    log_x_num <- log(bin_lowers_num[valid_bins_bool])
    log_s_num <- log(surv_estimate_num[valid_bins_bool])

    # OLS: log S = const + slope * log x. Pareto tail: alpha = -slope.
    # OLS itself is unweighted because each bin is one observation
    # (EARNWT weighting is baked into the survival estimate at each
    # bin). Matches EPI `reg logrunning logbin` in
    # `topcode_impute.ado`.
    fit_ols   <- stats::lm(log_s_num ~ log_x_num)
    slope_num <- unname(stats::coef(fit_ols)[2L])
    alpha_num <- -slope_num

    if (!is.finite(alpha_num) || alpha_num <= 1) {
      # Pareto conditional-mean formula requires alpha > 1. When it
      # does not hold, leave topcoded values at the topcode. No
      # `1.5 * topcode` fallback. See
      # docs/decisions/decision_02_no_pareto_fallback.md.
      diagnostics_list[[diag_idx_int]] <- tibble::tibble(
        year                  = yr,
        sex                   = sex_val_int,
        n_in_cell_int         = as.integer(n_in_cell_int),
        n_above_threshold_int = as.integer(n_above_thresh_int),
        fitted_alpha_num      = alpha_num,
        n_imputed_int         = 0L,
        n_left_at_topcode_int = as.integer(n_sex_topcoded_int),
        fit_status            = "alpha_not_gt_1"
      )
      diag_idx_int <- diag_idx_int + 1L
      next
    }

    # 8) Mean-above-topcode and imputation
    mean_above_tc_num <- alpha_num * weekly_tc_num / (alpha_num - 1)

    panel_df$nominal_weekly_wage_num[sex_topcoded_bool]      <- mean_above_tc_num
    panel_df$pareto_topcode_imputed_flag[sex_topcoded_bool]  <- TRUE

    diagnostics_list[[diag_idx_int]] <- tibble::tibble(
      year                  = yr,
      sex                   = sex_val_int,
      n_in_cell_int         = as.integer(n_in_cell_int),
      n_above_threshold_int = as.integer(n_above_thresh_int),
      fitted_alpha_num      = alpha_num,
      n_imputed_int         = as.integer(n_sex_topcoded_int),
      n_left_at_topcode_int = 0L,
      fit_status            = "ols_fit_success"
    )
    diag_idx_int <- diag_idx_int + 1L

    message(
      "  sex=", sex_val_int, " Pareto fit: alpha=", round(alpha_num, 4),
      "; imputed mean=$", format(round(mean_above_tc_num, 2), big.mark = ","),
      "; imputed rows=", n_sex_topcoded_int
    )
  }

  # 8b) EPI rotation-group bridge for 2023m4 - 2024m12.
  #     Mirrors EPI `tc_fix.do`. The step-7 Pareto loop has already
  #     imputed records with `nominal_weekly_wage_raw_num >= $2,884.60`
  #     to the per-sex conditional mean; this block overwrites the
  #     subset that BLS actually topcoded under the EARNWEEK2 regime:
  #       - 2023m4 - 2024m3 (rotation-group transition window):
  #           * MISH == 4 topcoded -> restore raw (= dynamic BLS topcode)
  #           * MISH == 8 topcoded -> assign the EARNWT-weighted mean
  #             of nominal_weekly_wage_raw_num where raw >= $2,884.60
  #             AND MISH == 4 in the same month
  #             (EPI: `sum weekpay_noadj [w=orgwgt] if weekpay_noadj
  #             >= 2884.6 & minsamp == 4`).
  #       - 2024m4 - 2024m12 (rotation transition complete):
  #           * All BLS-topcoded records restore raw (no MISH split).
  #     Records between $2,884.60 and the dynamic topcode are left at
  #     the step-7 Pareto-imputed conditional mean.
  #     See docs/decisions/decision_06_epi_rotation_group_bridge.md.
  if (yr %in% c(2023L, 2024L)) {
    bridge_legacy_tc_num <- 2884.60
    bridge_tol_num       <- topcode_tolerance_num

    if (yr == 2023L) {
      bridge_months_int      <- 4:12
      raw_restore_months_int <- integer(0)
    } else {  # yr == 2024L
      bridge_months_int      <- 1:3
      raw_restore_months_int <- 4:12
    }

    # Rotation-group bridge months (2023m4-12 and 2024m1-3).
    # Identifies two distinct topcoded populations per month:
    #   * MISH == 4 records at the dynamic month-max
    #   * MISH == 8 records at the legacy $2,884.60 value
    for (mo in bridge_months_int) {
      month_nonhourly_bool <- panel_df$MONTH == mo & !hourly_paid_bool &
        !is.na(panel_df$nominal_weekly_wage_raw_num) &
        panel_df$nominal_weekly_wage_raw_num > 0
      if (sum(month_nonhourly_bool) < 30L) next

      # MISH == 4 dynamic topcode: max raw weekly wage within MISH==4
      # cell for the month.
      mish4_month_bool <- month_nonhourly_bool & panel_df$MISH == 4L
      n_mish4_month_int <- sum(mish4_month_bool)
      if (n_mish4_month_int == 0L) next
      dynamic_tc_num <- max(
        panel_df$nominal_weekly_wage_raw_num[mish4_month_bool]
      )

      # MISH == 4 topcoded: at the dynamic month-max. Restore raw.
      mish4_topcoded_bool <- mish4_month_bool &
        abs(panel_df$nominal_weekly_wage_raw_num - dynamic_tc_num) <
          bridge_tol_num
      n_mish4_tc_int <- sum(mish4_topcoded_bool)
      if (n_mish4_tc_int > 0L) {
        panel_df$nominal_weekly_wage_num[mish4_topcoded_bool] <-
          panel_df$nominal_weekly_wage_raw_num[mish4_topcoded_bool]
        panel_df$pareto_topcode_imputed_flag[mish4_topcoded_bool] <- FALSE
      }

      # MISH == 8 topcoded: at or above the legacy $2,884.60. The
      # `>= bridge_legacy_tc_num - bridge_tol_num` threshold matches
      # EPI's `weekpay_noadj >= 2884.6` in `tc_fix.do` and catches
      # the IPUMS-stored $2,884.61 and rare $2,885.00 clusters.
      mish8_topcoded_bool <- month_nonhourly_bool & panel_df$MISH == 8L &
        panel_df$nominal_weekly_wage_raw_num >=
          (bridge_legacy_tc_num - bridge_tol_num)
      n_mish8_tc_int <- sum(mish8_topcoded_bool)

      # Donors for the MISH == 8 bridge value: same-month MISH == 4
      # records with raw weekly wage >= $2,884.60. Weighted mean.
      donor_bool <- mish4_month_bool &
        panel_df$nominal_weekly_wage_raw_num >= bridge_legacy_tc_num &
        !is.na(panel_df$EARNWT) &
        panel_df$EARNWT > 0
      n_donor_int <- sum(donor_bool)

      if (n_mish8_tc_int > 0L && n_donor_int >= 5L) {
        bridge_value_num <- sum(
          panel_df$nominal_weekly_wage_raw_num[donor_bool] *
            panel_df$EARNWT[donor_bool]
        ) / sum(panel_df$EARNWT[donor_bool])
        panel_df$nominal_weekly_wage_num[mish8_topcoded_bool] <-
          bridge_value_num
        panel_df$pareto_topcode_imputed_flag[mish8_topcoded_bool] <- TRUE
      } else {
        bridge_value_num <- NA_real_
      }

      message(
        "  bridge ", yr, "m", sprintf("%02d", mo),
        ": MISH==4 dynamic_tc=$",
        format(round(dynamic_tc_num, 2), big.mark = ","),
        " restored n=", n_mish4_tc_int,
        "; MISH==8 legacy_tc=$",
        format(round(bridge_legacy_tc_num, 2), big.mark = ","),
        " bridge=$",
        if (is.na(bridge_value_num)) "NA" else
          format(round(bridge_value_num, 2), big.mark = ","),
        " (n=", n_mish8_tc_int, ", donors=", n_donor_int, ")"
      )
    }

    # Raw-restore months (2024m4-12): all BLS-topcoded records get raw.
    for (mo in raw_restore_months_int) {
      month_nonhourly_bool <- panel_df$MONTH == mo & !hourly_paid_bool &
        !is.na(panel_df$nominal_weekly_wage_raw_num) &
        panel_df$nominal_weekly_wage_raw_num > 0
      if (sum(month_nonhourly_bool) < 30L) next

      dynamic_tc_num <- max(
        panel_df$nominal_weekly_wage_raw_num[month_nonhourly_bool]
      )

      bls_topcoded_month_bool <- month_nonhourly_bool &
        abs(panel_df$nominal_weekly_wage_raw_num - dynamic_tc_num) <
          bridge_tol_num
      n_bls_tc_int <- sum(bls_topcoded_month_bool)
      if (n_bls_tc_int == 0L) next

      panel_df$nominal_weekly_wage_num[bls_topcoded_month_bool] <-
        panel_df$nominal_weekly_wage_raw_num[bls_topcoded_month_bool]
      panel_df$pareto_topcode_imputed_flag[bls_topcoded_month_bool] <- FALSE

      message(
        "  raw-restore ", yr, "m", sprintf("%02d", mo),
        ": dynamic_tc=$",
        format(round(dynamic_tc_num, 2), big.mark = ","),
        "; topcoded n=", n_bls_tc_int, " restored to raw"
      )
    }
  }

  # 9) Write partition
  out_partition_dir_chr <- fs::path(out_panel_dir_chr, paste0("year=", yr))
  fs::dir_create(out_partition_dir_chr, recurse = TRUE)

  out_parquet_chr <- fs::path(out_partition_dir_chr, "part-0.parquet")
  out_rds_chr     <- fs::path(out_partition_dir_chr, "part-0.rds")

  arrow::write_parquet(
    x           = panel_df,
    sink        = out_parquet_chr,
    compression = "snappy"
  )
  saveRDS(panel_df, file = out_rds_chr, compress = "xz")

  message(
    "  wrote partition: ", out_parquet_chr, " (",
    format(nrow(panel_df), big.mark = ","), " rows)"
  )
}

###################################
###   4) Write diagnostics CSVs ###
###################################

# 4a) Pareto fit diagnostics (one row per (year, sex) cell)
diagnostics_df <- dplyr::bind_rows(
  diagnostics_list[!vapply(diagnostics_list, is.null, logical(1L))]
)

readr::write_csv(diagnostics_df, pareto_diag_path_chr)

message(
  "01b_build-org-panel.R -- Pareto diagnostics written: ",
  pareto_diag_path_chr, " (", nrow(diagnostics_df), " rows)"
)

# 4b) Topcode detection diagnostics (one row per year)
topcode_diagnostics_df <- dplyr::bind_rows(
  topcode_diagnostics_list[!vapply(topcode_diagnostics_list, is.null,
                                   logical(1L))]
)

readr::write_csv(topcode_diagnostics_df, topcode_diag_path_chr)

# Surface any legacy year (1982-2022) where the documented topcode
# value is in use but the EARNWEEK non-hourly mass count at that value
# is below the absolute threshold (topcode_min_mass_count_int). This
# would indicate either an IPUMS revision shifting the topcode value
# or an unusually small sample, and warrants manual review before the
# next production rerun. Years outside the legacy table (>= 2023) are
# excluded because `detected_matches_legacy_bool` is NA there.
mismatch_bool <- !is.na(topcode_diagnostics_df$detected_matches_legacy_bool) &
  !topcode_diagnostics_df$detected_matches_legacy_bool
if (any(mismatch_bool)) {
  message(
    "01b_build-org-panel.R -- WARNING: ",
    sum(mismatch_bool),
    " legacy year(s) where the documented EARNWEEK topcode value has ",
    "fewer than ", topcode_min_mass_count_int,
    " non-hourly observations at the documented value. Pareto adjustment ",
    "is skipped for those years and topcoded observations remain at the ",
    "topcode. Inspect ", topcode_diag_path_chr,
    " and confirm whether the IPUMS extract reflects a known BLS or ",
    "IPUMS revision before relying on this run."
  )
}

message(
  "01b_build-org-panel.R -- topcode detection diagnostics written: ",
  topcode_diag_path_chr, " (", nrow(topcode_diagnostics_df), " rows)"
)

# 4c) RF hours-imputation diagnostics (one row per year; one row per
# (year, feature) for importance).
hours_rf_diagnostics_df <- dplyr::bind_rows(
  hours_rf_diagnostics_list[!vapply(hours_rf_diagnostics_list, is.null,
                                    logical(1L))]
)
readr::write_csv(hours_rf_diagnostics_df, hours_rf_diag_path_chr)

hours_rf_importance_df <- dplyr::bind_rows(
  hours_rf_importance_list[!vapply(hours_rf_importance_list, is.null,
                                   logical(1L))]
)
readr::write_csv(hours_rf_importance_df, hours_rf_importance_path_chr)

# Surface any year where the RF imputation reported a non-success
# fit_status_chr. "insufficient_training_rows" and "no_hours_vary_rows"
# are expected for pre-1994 years; flag anything else.
n_unexpected_skip_int <- sum(
  !hours_rf_diagnostics_df$fit_status_chr %in%
    c("rf_fit_success", "insufficient_training_rows", "no_hours_vary_rows")
)
if (n_unexpected_skip_int > 0L) {
  message(
    "01b_build-org-panel.R -- WARNING: ",
    n_unexpected_skip_int,
    " year(s) where the RF hours imputation reported an unexpected ",
    "fit_status_chr. Inspect ", hours_rf_diag_path_chr,
    " before relying on this run."
  )
}

message(
  "01b_build-org-panel.R -- RF hours-imputation diagnostics written: ",
  hours_rf_diag_path_chr, " (", nrow(hours_rf_diagnostics_df), " rows); ",
  "feature importance: ", hours_rf_importance_path_chr,
  " (", nrow(hours_rf_importance_df), " rows)"
)

# 4d) Hours-missingness diagnostics (one row per year x pay type x reason
# x imputed status). Lets a reviewer quantify how many salaried records
# fall out of the hourly series and why, and how many the don't-know
# extension recovered.
hours_missing_diag_df <- dplyr::bind_rows(
  hours_missing_diag_list[!vapply(hours_missing_diag_list, is.null,
                                  logical(1L))]
)
readr::write_csv(hours_missing_diag_df, hours_missing_diag_path_chr)

# Surface the count of salaried rows that still have no usable hours after
# imputation (reason niu / other_missing, or imputation skipped). These are
# retained in the weekly series but drop out of the hourly series.
n_salaried_unresolved_int <- sum(
  hours_missing_diag_df$n_int[
    hours_missing_diag_df$paidhour_int == 1L &
      !hours_missing_diag_df$imputed_bool
  ]
)
message(
  "01b_build-org-panel.R -- hours-missingness diagnostics written: ",
  hours_missing_diag_path_chr, " (", nrow(hours_missing_diag_df),
  " rows); salaried rows with unresolved hours (excluded from hourly ",
  "series): ", format(n_salaried_unresolved_int, big.mark = ","), "."
)

# 4e) ASEC-sample records dropped in step 0 (one row per year x month).
asec_drop_df <- dplyr::bind_rows(
  asec_drop_list[!vapply(asec_drop_list, is.null, logical(1L))]
)
readr::write_csv(asec_drop_df, asec_drop_diag_path_chr)

message(
  "01b_build-org-panel.R -- dropped ",
  format(sum(asec_drop_df$n_asec_records_int), big.mark = ","),
  " ASEC-sample records (",
  format(sum(asec_drop_df$n_asec_earnwt_pos_int), big.mark = ","),
  " with EARNWT > 0) across ", sum(asec_drop_df$n_asec_records_int > 0L),
  " months; months: ",
  paste(sort(unique(asec_drop_df$month_int[asec_drop_df$n_asec_records_int > 0L])),
        collapse = ", "),
  ". Written: ", asec_drop_diag_path_chr
)

message("01b_build-org-panel.R -- done.")
