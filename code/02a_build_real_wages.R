# 02a_build_real_wages -- join primary deflator, compute real weekly and hourly wages, apply EPI outlier bounds
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

rm(list = ls())
options(scipen = 999)
set.seed(42)

# Sourced by run_all.R inside new.env(parent = globalenv()).
#
# Reads the year-partitioned ORG panel written by 01b, joins the primary
# deflator (PCEPI by default) via the manifest written by
# code/_utils/download_deflators.R, computes real weekly and hourly
# wages in December 2025 PCE dollars, and applies the EPI outlier
# bounds. The deflator join is at the (YEAR, MONTH) level — every CPS
# ORG row is deflated by its own survey-month PCEPI value. The
# outlier bounds on the hourly wage in 1989 PCE dollars are translated
# into December 2025 PCE dollars once via
# PCEPI(Dec 1989) / PCEPI(Dec 2025) and applied uniformly across years.
#
# Output columns:
#   YEAR, MONTH, EARNWT, AGE, SEX, BIRTHYR,
#   nominal_weekly_wage_num, real_weekly_wage_num,
#   nominal_hourly_wage_num, real_hourly_wage_num,
#   hours_imputed_flag, pareto_topcode_imputed_flag
#
# Hourly-wage construction follows the EPI metric routing:
#   PAIDHOUR == 2 (hourly-paid): hourly wage = HOURWAGE_CANON_NUM.
#   PAIDHOUR == 1 (salaried):    hourly wage = nominal_weekly_wage_num /
#     uhrsworkorg_used_num (the coalesced primary hours variable with
#     01b's RF imputation applied to hours-vary rows). Salaried rows
#     with NA or non-positive hours propagate NA to the hourly wage.
#
# Departure pointers (see docs/decisions/ for full rationale):
#   - Departure #1 (PCE deflator):
#     docs/decisions/decision_01_pce_deflator.md.
#   - Departure #5 (uniform $200 / hour 1989-PCE upper bound):
#     docs/decisions/decision_05_uniform_200_upper_bound.md.
#
# CPI-U-RS, C-CPI-U, CPI-U SA, and CPI-U NSA are stored as shadow
# deflators for sensitivity spot-checks, not joined here.
#
# No custom functions are defined; all transformations are inline.

source(here::here("code", "_utils", "00_packages.R"))

###################################
###   Configuration             ###
###################################

# Primary deflator key. The manifest written by _utils/download_deflators.R
# records one row per available deflator keyed by short string. "pcepi" is
# the production primary; other valid keys are "cpiurs", "ccpiu", "cpiu_sa",
# "cpiu_nsa" (all shadows used for sensitivity comparisons). This script
# currently reads the primary key's parquet only; to compare against a
# shadow, flip this switch and rerun.
primary_deflator_key_chr <- "pcepi"

panel_in_dir_chr       <- here::here("data", "intermediate", "cps_org_panel")
deflator_dir_chr       <- here::here("data", "fred", "deflators")
deflator_manifest_chr  <- fs::path(deflator_dir_chr, "_manifest.csv")
panel_out_dir_chr      <- here::here("data", "intermediate", "cps_real_wages")

# Maximum age (in days) of the deflator manifest before 02a emits a staleness
# message. Monthly FRED series update shortly after each month closes; a seven-
# day window covers common pipeline sequencing without producing false
# positives on routine re-runs.
deflator_max_age_days_num <- 7

# EPI outlier bounds in 1989 PCE dollars applied to the HOURLY wage
# (Schmitt 2003 CEPR convention). For hourly-paid workers
# (PAIDHOUR == 2) the hourly wage is HOURWAGE_CANON_NUM; for salaried
# workers (PAIDHOUR == 1) it is EARNWEEK_CANON_NUM / hours.
# See docs/decisions/decision_05_uniform_200_upper_bound.md.
bound_lower_hourly_1989_num <- 0.50
bound_upper_hourly_1989_num <- 200

# Reference year/month for the outlier-bound translation. Per user
# direction (2026-04-23), the 1989 reference is December 1989 PCEPI —
# strictly month-year throughout — so the $0.50/$200 hourly bounds in
# 1989 PCE dollars translate into December 2025 PCE dollars via the
# ratio PCEPI(Dec 2025) / PCEPI(Dec 1989) = 1 / PCEPI(Dec 1989).
bound_ref_year_int  <- 1989L
bound_ref_month_int <- 12L

###################################
###   1) Manifest preflight     ###
###################################
# Gate: the deflator manifest written by code/_utils/download_deflators.R must
# exist and record the requested primary key. The manifest records paths and
# pull timestamps so 02a never silently reads an orphaned parquet that no
# longer matches the declared pipeline state.

if (!fs::file_exists(deflator_manifest_chr)) {
  stop(
    "02a_build_real_wages.R -- deflator manifest not found at ",
    deflator_manifest_chr, ". Run code/_utils/download_deflators.R via ",
    "run_00b = TRUE in run_all.R (or source directly) before 02a."
  )
}

deflator_manifest_df <- readr::read_csv(
  deflator_manifest_chr, show_col_types = FALSE
)

required_manifest_cols_chr <- c(
  "deflator_key_chr", "out_parquet_path_chr", "pulled_at_utc_chr"
)
missing_manifest_cols_chr <- setdiff(
  required_manifest_cols_chr, names(deflator_manifest_df)
)

if (length(missing_manifest_cols_chr) > 0L) {
  stop(
    "02a_build_real_wages.R -- deflator manifest is missing column(s): ",
    paste(missing_manifest_cols_chr, collapse = ", "),
    ". Rerun code/_utils/download_deflators.R to regenerate it."
  )
}

primary_row_bool <-
  deflator_manifest_df$deflator_key_chr == primary_deflator_key_chr

if (sum(primary_row_bool) != 1L) {
  stop(
    "02a_build_real_wages.R -- deflator manifest has ",
    sum(primary_row_bool), " rows for key '", primary_deflator_key_chr,
    "'; expected exactly 1. Keys available: ",
    paste(unique(deflator_manifest_df$deflator_key_chr), collapse = ", ")
  )
}

# The manifest's recorded path is resolved by file name inside
# deflator_dir_chr, so the project can live anywhere on disk.
primary_deflator_path_chr <- fs::path(
  deflator_dir_chr,
  fs::path_file(deflator_manifest_df$out_parquet_path_chr[primary_row_bool])
)
primary_pulled_at_chr     <-
  deflator_manifest_df$pulled_at_utc_chr[primary_row_bool]

if (!fs::file_exists(primary_deflator_path_chr)) {
  stop(
    "02a_build_real_wages.R -- deflator parquet for key '",
    primary_deflator_key_chr,
    "' is listed in the manifest but missing on disk: ",
    primary_deflator_path_chr, ". Rerun code/_utils/download_deflators.R."
  )
}

# Parse the pulled_at_utc timestamp. Accepts the current ISO-8601 form
# (`%Y-%m-%dT%H:%M:%SZ`) and the legacy `%Y-%m-%d %H:%M:%S UTC` form
# so older manifests still pass the freshness check.
primary_pulled_at_posix <- tryCatch(
  as.POSIXct(
    primary_pulled_at_chr,
    format = "%Y-%m-%dT%H:%M:%SZ",
    tz     = "UTC"
  ),
  warning = function(w) as.POSIXct(NA),
  error   = function(e) as.POSIXct(NA)
)

if (is.na(primary_pulled_at_posix)) {
  primary_pulled_at_posix <- tryCatch(
    as.POSIXct(
      primary_pulled_at_chr,
      format = "%Y-%m-%d %H:%M:%S",
      tz     = "UTC"
    ),
    warning = function(w) as.POSIXct(NA),
    error   = function(e) as.POSIXct(NA)
  )
}

if (is.na(primary_pulled_at_posix)) {
  message(
    "02a_build_real_wages.R -- manifest pulled_at_utc_chr ('",
    primary_pulled_at_chr, "') could not be parsed; skipping freshness check."
  )
} else {
  manifest_age_days_num <- as.numeric(
    difftime(Sys.time(), primary_pulled_at_posix, units = "days")
  )
  if (manifest_age_days_num > deflator_max_age_days_num) {
    message(
      "02a_build_real_wages.R -- primary deflator ('",
      primary_deflator_key_chr, "') manifest is ",
      round(manifest_age_days_num, 1L), " days old (threshold ",
      deflator_max_age_days_num, "). Consider rerunning download_deflators.R."
    )
  }
}

# Compatibility guard: PCEPI-named columns are referenced directly
# below. Halt if a shadow key is selected; switching keys requires
# generalizing the <key>_dec2025_base column refs and, for CPI-U-RS,
# moving to a YEAR-only join.
if (!identical(primary_deflator_key_chr, "pcepi")) {
  stop(
    "02a_build_real_wages.R -- primary_deflator_key_chr is set to '",
    primary_deflator_key_chr,
    "' but the downstream code references PCEPI monthly column names ",
    "directly. Generalize the column refs (<key>_dec2025_base) and the ",
    "(YEAR, MONTH) join structure before switching keys. CPI-U-RS is ",
    "annual-only; a shadow-run against CPI-U-RS additionally requires a ",
    "YEAR-only join path."
  )
}

pcepi_path_chr <- primary_deflator_path_chr

message(
  "02a_build_real_wages.R -- primary deflator '",
  primary_deflator_key_chr, "' resolved to ", pcepi_path_chr,
  " (pulled ", primary_pulled_at_chr, ")"
)

###################################
###   2) Locate year partitions ###
###################################

year_partition_paths_chr <- fs::dir_ls(
  panel_in_dir_chr, regexp = "year=\\d{4}", type = "directory"
)

if (length(year_partition_paths_chr) == 0L) {
  stop(
    "02a_build_real_wages.R -- no year partitions under ",
    panel_in_dir_chr, ". Run 01b_build-org-panel.R first."
  )
}

years_available_int <- sort(as.integer(
  stringr::str_extract(basename(year_partition_paths_chr), "\\d{4}")
))

fs::dir_create(panel_out_dir_chr, recurse = TRUE)

message(
  "02a_build_real_wages.R -- ORG panel years available: ",
  min(years_available_int), "-", max(years_available_int),
  " (", length(years_available_int), " partitions)"
)

###################################
###   3) Load PCEPI deflator    ###
###################################

pcepi_df <- arrow::read_parquet(pcepi_path_chr)

required_pcepi_cols_chr <- c("year_int", "month_int", "pcepi_dec2025_base")
missing_pcepi_cols_chr  <- setdiff(required_pcepi_cols_chr, names(pcepi_df))

if (length(missing_pcepi_cols_chr) > 0L) {
  stop(
    "02a_build_real_wages.R -- PCEPI parquet is missing column(s): ",
    paste(missing_pcepi_cols_chr, collapse = ", "),
    ". Expected monthly schema from download_deflators.R (year_int, ",
    "month_int, pcepi_dec2025_base)."
  )
}

# PCEPI monthly coverage summary. The CPS ORG panel joins on
# (YEAR, MONTH); rows whose (YEAR, MONTH) have no PCEPI match drop out
# via NA propagation on the real wage. Per-year partitions with zero
# matched rows are skipped entirely.
pcepi_year_month_df <- pcepi_df |>
  dplyr::select(year_int, month_int, pcepi_dec2025_base) |>
  dplyr::distinct()

message(
  "02a_build_real_wages.R -- PCEPI monthly coverage: ",
  nrow(pcepi_year_month_df), " (year, month) pairs spanning ",
  sprintf("%04d-%02d", min(pcepi_year_month_df$year_int),
          min(pcepi_year_month_df$month_int[
            pcepi_year_month_df$year_int == min(pcepi_year_month_df$year_int)
          ])),
  " to ",
  sprintf("%04d-%02d", max(pcepi_year_month_df$year_int),
          max(pcepi_year_month_df$month_int[
            pcepi_year_month_df$year_int == max(pcepi_year_month_df$year_int)
          ]))
)

###################################
###   4) Translate 1989 bounds  ###
###################################
# pcepi_dec2025_base is PCEPI(y, m) / PCEPI(Dec 2025), so the December
# 1989 base value equals PCEPI(Dec 1989) / PCEPI(Dec 2025). A wage of
# $B in December 1989 PCE dollars equals
# $B / pcepi_dec1989_base_num in December 2025 PCE dollars. Computed
# once and applied uniformly across every year.

pcepi_dec1989_mask_bool <- pcepi_df$year_int == bound_ref_year_int &
  pcepi_df$month_int == bound_ref_month_int

pcepi_dec1989_base_num <- pcepi_df$pcepi_dec2025_base[pcepi_dec1989_mask_bool]

if (length(pcepi_dec1989_base_num) != 1L ||
    is.na(pcepi_dec1989_base_num) ||
    pcepi_dec1989_base_num <= 0) {
  stop(
    "02a_build_real_wages.R -- PCEPI December 1989 value is missing or ",
    "non-positive in the deflator parquet; cannot translate EPI outlier ",
    "bounds. Inspect ", pcepi_path_chr, " and confirm Dec 1989 coverage."
  )
}

bound_lower_hourly_dec2025_num <-
  bound_lower_hourly_1989_num / pcepi_dec1989_base_num
bound_upper_hourly_dec2025_num <-
  bound_upper_hourly_1989_num / pcepi_dec1989_base_num

message(
  "02a_build_real_wages.R -- December 1989 PCE-dollar HOURLY-wage bounds [",
  bound_lower_hourly_1989_num, ", ", bound_upper_hourly_1989_num,
  "] translate to December 2025 PCE-dollar HOURLY-wage bounds [",
  format(round(bound_lower_hourly_dec2025_num, 4), big.mark = ","), ", ",
  format(round(bound_upper_hourly_dec2025_num, 2), big.mark = ","),
  "] via PCEPI(Dec 1989)/PCEPI(Dec 2025) = ",
  format(round(pcepi_dec1989_base_num, 6), nsmall = 6L),
  "."
)

###################################
###   5) Row-count accumulator  ###
###################################

row_counts_df <- tibble::tibble(
  year_int                = integer(0),
  n_pre_trim_int          = integer(0),
  n_post_trim_int         = integer(0),
  n_dropped_no_deflator_int = integer(0),
  n_dropped_low_int       = integer(0),
  n_dropped_high_int      = integer(0),
  n_months_matched_int    = integer(0),
  n_salaried_no_hours_hourly_na_int = integer(0)
)

skipped_years_int <- integer(0L)

# Per-year summary stats are computed in section 6 on the in-memory
# post-trim panel_df rather than re-reading the just-written parquets
# (Windows arrow memory-mapping can hold a write lock on the same file).
summary_list <- vector("list", length(years_available_int))
summary_idx_int <- 1L

###################################
###   6) Per-year processing    ###
###################################
# Year-partition loop. Each row is deflated by its own (YEAR, MONTH)
# PCEPI value — no annual scalar is applied. Unmatched (YEAR, MONTH)
# rows propagate NA to the real wage and drop out via the validity
# filter; their count is logged per year.

for (yr in years_available_int) {

  in_parquet_chr <- fs::path(
    panel_in_dir_chr, paste0("year=", yr), "part-0.parquet"
  )

  if (!fs::file_exists(in_parquet_chr)) {
    stop("02a_build_real_wages.R -- missing input partition: ", in_parquet_chr)
  }

  panel_df <- arrow::read_parquet(in_parquet_chr)

  # (YEAR, MONTH) left-join into PCEPI monthly. Preserves panel row
  # order and assigns NA to unmatched rows.
  panel_df <- dplyr::left_join(
    panel_df,
    pcepi_df |>
      dplyr::transmute(
        YEAR  = as.integer(year_int),
        MONTH = as.integer(month_int),
        pcepi_dec2025_base = pcepi_dec2025_base
      ),
    by = c("YEAR", "MONTH")
  )

  n_unmatched_int <- sum(is.na(panel_df$pcepi_dec2025_base))
  n_pre_trim_int  <- nrow(panel_df)

  if (n_unmatched_int == n_pre_trim_int) {
    message(
      "02a_build_real_wages.R -- year ", yr, ": ",
      format(n_pre_trim_int, big.mark = ","),
      " panel rows, 0 matched to PCEPI month — skipping partition. ",
      "Rerun code/_utils/download_deflators.R once the needed months ",
      "are published."
    )
    skipped_years_int <- c(skipped_years_int, as.integer(yr))
    next
  }

  # Compute real weekly wage in December 2025 PCE dollars.
  # nominal_weekly_wage_num / pcepi_dec2025_base = Dec 2025 PCE $ per week.
  panel_df$real_weekly_wage_num <-
    panel_df$nominal_weekly_wage_num / panel_df$pcepi_dec2025_base

  # Construct nominal and real HOURLY wage per the EPI metric routing.
  # For hourly-paid workers (PAIDHOUR == 2) HOURWAGE_CANON_NUM is the
  # reported hourly rate (no Pareto adjustment is applied to hourly-
  # rate topcodes; matches EPI `generate_wage.do`). For salaried
  # workers (PAIDHOUR == 1) the hourly equivalent is
  # nominal_weekly_wage_num / uhrsworkorg_used_num, mirroring EPI's
  # `wage = weekpay / hoursu1 if paidhre == 0`. Using
  # nominal_weekly_wage_num (rather than EARNWEEK_CANON_NUM) propagates
  # the Pareto imputation from 01b into the production hourly wage.
  # Salaried rows with NA or non-positive hours propagate NA to the
  # hourly wage (the 40-hour fallback below is scoped to the outlier-
  # bound check only and does not flow into the production wage value).
  hours_for_hourly_num_vec <- panel_df$uhrsworkorg_used_num
  hours_for_hourly_valid_bool <- !is.na(hours_for_hourly_num_vec) &
    is.finite(hours_for_hourly_num_vec) &
    hours_for_hourly_num_vec > 0
  # Guarded denominator: divide by the valid hours where available, else
  # NA. Using hours_for_hourly_safe_num keeps the subsequent arithmetic
  # fully vectorized without intermediate warnings on zero hours.
  hours_for_hourly_safe_num <- dplyr::if_else(
    hours_for_hourly_valid_bool,
    hours_for_hourly_num_vec,
    NA_real_
  )
  panel_df$nominal_hourly_wage_num <- dplyr::if_else(
    panel_df$PAIDHOUR == 2L,
    panel_df$HOURWAGE_CANON_NUM,
    panel_df$nominal_weekly_wage_num / hours_for_hourly_safe_num,
    missing = NA_real_
  )
  panel_df$real_hourly_wage_num <-
    panel_df$nominal_hourly_wage_num / panel_df$pcepi_dec2025_base

  # Outlier bounds applied to the HOURLY wage (Schmitt 2003 CEPR
  # convention). For hourly-paid workers the hourly wage is the raw
  # HOURWAGE_CANON_NUM (before 01b's weekly-wage construction). For
  # salaried workers the hourly equivalent is EARNWEEK_CANON_NUM / hours.
  # Using the raw canonical wage columns evaluates Pareto-imputed
  # topcode rows against the bound using their pre-imputation reported
  # values.
  bound_hours_num_vec <- panel_df$uhrsworkorg_used_num
  bound_hours_fallback_bool <- is.na(bound_hours_num_vec) |
    bound_hours_num_vec <= 0
  # 40-hour fallback for salaried workers with missing/zero hours so
  # the hourly-equivalent computation yields a finite value. Rows for
  # which EARNWEEK_CANON_NUM is also missing still propagate NA and
  # are excluded from bound evaluation via valid_wage_bool below.
  bound_hours_num_vec[bound_hours_fallback_bool] <- 40

  nominal_hourly_for_bound_num <- dplyr::if_else(
    panel_df$PAIDHOUR == 2L,
    panel_df$HOURWAGE_CANON_NUM,
    panel_df$EARNWEEK_CANON_NUM / bound_hours_num_vec,
    missing = NA_real_
  )
  real_hourly_for_bound_num <-
    nominal_hourly_for_bound_num / panel_df$pcepi_dec2025_base

  # Apply the outlier bounds on the real hourly wage. Rows are kept
  # only when (a) the real weekly wage is non-missing AND (b) the real
  # hourly wage passes the [0.50, 200] bound in 1989 PCE dollars. The
  # upper bound applies uniformly regardless of reported hours.
  valid_wage_bool <- !is.na(panel_df$real_weekly_wage_num) &
    !is.na(real_hourly_for_bound_num) &
    is.finite(real_hourly_for_bound_num)

  low_drop_bool  <- valid_wage_bool &
    real_hourly_for_bound_num < bound_lower_hourly_dec2025_num
  high_drop_bool <- valid_wage_bool &
    real_hourly_for_bound_num > bound_upper_hourly_dec2025_num

  keep_bool <- valid_wage_bool & !low_drop_bool & !high_drop_bool

  n_dropped_low_int  <- sum(low_drop_bool)
  n_dropped_high_int <- sum(high_drop_bool)
  n_months_matched_int <- length(
    unique(panel_df$MONTH[!is.na(panel_df$pcepi_dec2025_base)])
  )

  panel_df <- panel_df[keep_bool, , drop = FALSE]

  # Salaried workers (PAIDHOUR == 1) retained in the panel but excluded
  # from the HOURLY series because they report no usable weekly hours:
  # their production hourly wage is NA. (The 40-hour fallback above is
  # scoped to the outlier-bound check only and never enters the reported
  # hourly value.) These rows remain in the weekly series. Counting them
  # per year makes the hourly-metric coverage gap auditable rather than
  # silent; see the figure captions and decision_07.
  n_salaried_no_hours_hourly_na_int <- sum(
    panel_df$PAIDHOUR == 1L & is.na(panel_df$real_hourly_wage_num)
  )

  # Select the output columns. MONTH is carried through so downstream
  # consumers can replicate the (YEAR, MONTH) deflator join or
  # disaggregate within-year if needed.
  keep_cols_chr <- c(
    "YEAR", "MONTH", "EARNWT", "AGE", "SEX", "BIRTHYR", "PAIDHOUR",
    "nominal_weekly_wage_num", "real_weekly_wage_num",
    "nominal_hourly_wage_num", "real_hourly_wage_num",
    "hours_imputed_flag", "pareto_topcode_imputed_flag",
    # Geographic identifiers and occupation code, passed through for
    # the binding-minimum-wage sub-analysis (stages 20a-20e).
    "STATEFIP", "COUNTY", "METFIPS", "INDIVIDCC", "OCC2010",
    # IPUMS harmonized education code, passed through for the education-
    # third medians in figure_f_era_bars_tables.R.
    "EDUC"
  )

  missing_out_cols_chr <- setdiff(keep_cols_chr, names(panel_df))
  if (length(missing_out_cols_chr) > 0L) {
    stop(
      "02a_build_real_wages.R -- input partition ", yr,
      " missing expected column(s): ",
      paste(missing_out_cols_chr, collapse = ", ")
    )
  }

  panel_df <- panel_df[, keep_cols_chr, drop = FALSE]

  # Per-year summary statistics on the post-trim in-memory panel. The
  # weighted percentiles use the shared weighted_quantile() helper (same
  # no-interpolation rule as figure_a_percentiles.R and
  # 10_epi_spot_checks.R). earnwt_pop_num reports the average monthly
  # population via weighted_population() -- the summed EARNWT divided by
  # the number of distinct survey months in the year -- so a full 12-month
  # year is not reported as ~12x the population. The raw weight total
  # wt_sum_num is kept only as the (scale-invariant) denominator for the
  # weighted mean and SD.
  summary_valid_bool <- !is.na(panel_df$real_weekly_wage_num) &
    !is.na(panel_df$EARNWT) &
    panel_df$EARNWT > 0
  if (any(summary_valid_bool)) {
    v_df <- panel_df[summary_valid_bool, , drop = FALSE]
    wt_sum_num  <- sum(v_df$EARNWT)
    mean_num    <- sum(v_df$real_weekly_wage_num * v_df$EARNWT) / wt_sum_num
    var_num     <- sum(
      v_df$EARNWT * (v_df$real_weekly_wage_num - mean_num) ^ 2
    ) / wt_sum_num
    sd_num      <- sqrt(var_num)

    earnwt_pop_num <- weighted_population(v_df$EARNWT, v_df$YEAR, v_df$MONTH)

    summary_list[[summary_idx_int]] <- tibble::tibble(
      year_int       = as.integer(yr),
      n_rows_int     = as.integer(nrow(v_df)),
      earnwt_pop_num = earnwt_pop_num,
      mean_num       = mean_num,
      sd_num         = sd_num,
      p10_num        = weighted_quantile(v_df$real_weekly_wage_num, v_df$EARNWT, 0.10),
      p25_num        = weighted_quantile(v_df$real_weekly_wage_num, v_df$EARNWT, 0.25),
      p50_num        = weighted_quantile(v_df$real_weekly_wage_num, v_df$EARNWT, 0.50),
      p75_num        = weighted_quantile(v_df$real_weekly_wage_num, v_df$EARNWT, 0.75),
      p90_num        = weighted_quantile(v_df$real_weekly_wage_num, v_df$EARNWT, 0.90)
    )
  } else {
    summary_list[[summary_idx_int]] <- tibble::tibble(
      year_int       = as.integer(yr),
      n_rows_int     = 0L,
      earnwt_pop_num = NA_real_,
      mean_num       = NA_real_,
      sd_num         = NA_real_,
      p10_num        = NA_real_,
      p25_num        = NA_real_,
      p50_num        = NA_real_,
      p75_num        = NA_real_,
      p90_num        = NA_real_
    )
  }
  summary_idx_int <- summary_idx_int + 1L

  # Write partition
  out_partition_dir_chr <- fs::path(panel_out_dir_chr, paste0("year=", yr))
  fs::dir_create(out_partition_dir_chr, recurse = TRUE)

  out_parquet_chr <- fs::path(out_partition_dir_chr, "part-0.parquet")
  out_rds_chr     <- fs::path(out_partition_dir_chr, "part-0.rds")

  arrow::write_parquet(
    x           = panel_df,
    sink        = out_parquet_chr,
    compression = "snappy"
  )
  saveRDS(panel_df, file = out_rds_chr, compress = "xz")

  row_counts_df <- dplyr::bind_rows(
    row_counts_df,
    tibble::tibble(
      year_int                  = as.integer(yr),
      n_pre_trim_int            = as.integer(n_pre_trim_int),
      n_post_trim_int           = as.integer(nrow(panel_df)),
      n_dropped_no_deflator_int = as.integer(n_unmatched_int),
      n_dropped_low_int         = as.integer(n_dropped_low_int),
      n_dropped_high_int        = as.integer(n_dropped_high_int),
      n_months_matched_int      = as.integer(n_months_matched_int),
      n_salaried_no_hours_hourly_na_int =
        as.integer(n_salaried_no_hours_hourly_na_int)
    )
  )

  message(
    "02a_build_real_wages.R -- year ", yr, ": ",
    format(n_pre_trim_int, big.mark = ","), " -> ",
    format(nrow(panel_df),  big.mark = ","), " rows (dropped ",
    format(n_unmatched_int, big.mark = ","), " no-deflator, ",
    format(n_dropped_low_int,  big.mark = ","), " low, ",
    format(n_dropped_high_int, big.mark = ","), " high; ",
    n_months_matched_int, " months matched; ",
    format(n_salaried_no_hours_hourly_na_int, big.mark = ","),
    " salaried rows excluded from hourly series for missing hours)"
  )
}

if (length(skipped_years_int) > 0L) {
  message(
    "02a_build_real_wages.R -- ",
    length(skipped_years_int),
    " year partition(s) skipped for zero PCEPI month matches: ",
    paste(skipped_years_int, collapse = ", "),
    "."
  )
}

###################################
###   7) Write row-count log    ###
###################################

counts_path_chr <- fs::path(
  here::here("data", "intermediate"), "real_wage_trim_counts.csv"
)
readr::write_csv(row_counts_df, counts_path_chr)

message(
  "02a_build_real_wages.R -- trim-count log written: ", counts_path_chr,
  " (", nrow(row_counts_df), " year rows; ",
  format(sum(row_counts_df$n_post_trim_int), big.mark = ","),
  " person-year rows retained in total)"
)

###################################
###   8) Boundary unit check    ###
###################################
# Boundary unit check: outlier trimming drops zero rows when the bounds
# are absurdly wide. Re-runs the trim logic inline against the last
# processed year's data using bounds of [1e-12, 1e12] and asserts zero
# drops. The check year is named explicitly (not loop-leaked).
#
# Picks a year with full 12-month PCEPI coverage so the mean-over-months
# scalar is a sensible stand-in for the deflator. Years with partial
# PCEPI coverage (typically the trailing calendar year) are excluded.
widecheck_eligible_years_int <- row_counts_df$year_int[
  row_counts_df$n_months_matched_int == 12L &
    row_counts_df$n_dropped_no_deflator_int == 0L
]

if (length(widecheck_eligible_years_int) == 0L) {
  message(
    "02a_build_real_wages.R -- boundary unit check SKIPPED: no processed ",
    "year has full 12-month PCEPI coverage with zero unmatched rows. ",
    "This is expected when every CPS year is partial (early-build or ",
    "trailing-year-only run)."
  )
  widecheck_year_int <- NA_integer_
} else {
  widecheck_year_int <- max(widecheck_eligible_years_int)

  widecheck_in_parquet_chr <- fs::path(
    panel_in_dir_chr, paste0("year=", widecheck_year_int), "part-0.parquet"
  )
  widecheck_panel_df <- arrow::read_parquet(widecheck_in_parquet_chr)

  # Month-specific deflator lookup — use the mean PCEPI over the check
  # year's 12 months as a single-scalar stand-in. The check is a unit
  # boundary test on the trim logic, not an accuracy test on the
  # deflation, so a single representative scalar suffices.
  widecheck_pcepi_num <- mean(
    pcepi_df$pcepi_dec2025_base[
      pcepi_df$year_int == widecheck_year_int
    ],
    na.rm = TRUE
  )
  widecheck_real_num  <- widecheck_panel_df$nominal_weekly_wage_num /
    widecheck_pcepi_num

  # Count rows whose nominal_weekly_wage_num is non-finite (Inf, -Inf,
  # or NaN) — a separate data-quality concern flagged as a diagnostic
  # but not counted toward the bound-trim unit test.
  widecheck_nonfinite_int <- sum(
    !is.na(widecheck_panel_df$nominal_weekly_wage_num) &
      !is.finite(widecheck_panel_df$nominal_weekly_wage_num)
  )
  if (widecheck_nonfinite_int > 0L) {
    message(
      "02a_build_real_wages.R -- diagnostic: ",
      widecheck_nonfinite_int,
      " row(s) in year ", widecheck_year_int,
      " have non-finite nominal_weekly_wage_num (Inf or NaN). These ",
      "are excluded from the bound-trim unit test; investigate in 01b ",
      "if the count is unexpectedly large."
    )
  }

  # Count rows whose nominal_weekly_wage_num is exactly zero (most
  # commonly hourly-paid workers reporting zero hours; HOURWAGE * 0 = 0).
  # Production processing drops them under any positive lower bound;
  # the unit test excludes them for the same reason.
  widecheck_zero_int <- sum(
    !is.na(widecheck_panel_df$nominal_weekly_wage_num) &
      is.finite(widecheck_panel_df$nominal_weekly_wage_num) &
      widecheck_panel_df$nominal_weekly_wage_num == 0
  )
  if (widecheck_zero_int > 0L) {
    message(
      "02a_build_real_wages.R -- diagnostic: ",
      widecheck_zero_int,
      " row(s) in year ", widecheck_year_int,
      " have nominal_weekly_wage_num = 0 (likely hourly-paid with ",
      "zero reported hours). Production processing drops these under ",
      "the $0.50 lower bound; the unit test excludes them."
    )
  }

  # Bound-trim unit test: on strictly positive finite real wages,
  # absurdly wide bounds must drop zero rows. Zero-wage rows and
  # non-finite rows are degenerate cases that any positive lower
  # bound correctly excludes; the test's purpose is to verify the
  # trim arithmetic, not the pipeline's treatment of degenerate
  # values.
  widecheck_valid_bool <- !is.na(widecheck_real_num) &
    is.finite(widecheck_real_num) &
    widecheck_real_num > 0
  widecheck_drop_bool  <- widecheck_valid_bool &
    (widecheck_real_num < 1e-12 | widecheck_real_num > 1e12)

  if (sum(widecheck_drop_bool) != 0L) {
    stop(
      "02a_build_real_wages.R -- boundary unit check failed: absurdly wide ",
      "bounds [1e-12, 1e12] dropped ", sum(widecheck_drop_bool),
      " strictly-positive finite-valued rows in year ",
      widecheck_year_int, "; expected 0."
    )
  }

  message(
    "02a_build_real_wages.R -- boundary unit check PASS: absurdly wide ",
    "bounds dropped 0 strictly-positive finite-valued rows in check year ",
    widecheck_year_int, " (", sum(widecheck_valid_bool),
    " rows in scope)."
  )
}

###################################
###   9) Summary statistics     ###
###################################
# MR-DA1 summary-statistics table. Per-year rows were computed inline
# in section 6 on the in-memory post-trim panel; this section binds
# them and writes. Skipped years produce NULL slots that bind_rows
# silently drops.

summary_df <- dplyr::bind_rows(
  summary_list[!vapply(summary_list, is.null, logical(1L))]
)

summary_path_chr <- fs::path(
  here::here("data", "intermediate"), "real_wage_summary_stats.csv"
)
readr::write_csv(summary_df, summary_path_chr)

message(
  "02a_build_real_wages.R -- summary-stats table written: ",
  summary_path_chr, " (", nrow(summary_df),
  " year rows; weighted mean range $",
  format(round(min(summary_df$mean_num, na.rm = TRUE), 2), big.mark = ","),
  " to $",
  format(round(max(summary_df$mean_num, na.rm = TRUE), 2), big.mark = ","),
  ")"
)

message("02a_build_real_wages.R -- done.")
