# 20c_build-binding-minimum-panel -- construct state-month and substate-month binding minimum wage panels for the 1979-onward CPS ORG window
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - what share of US wage and salary workers are constrained by their applicable (federal, state, county, or city) minimum wage, 1979 through present?

rm(list = ls())
options(scipen = 999)
# set.seed retained for project-wide consistency; no randomness is used
# in this script.
set.seed(42)

# Sourced by run_all.R inside new.env(parent = globalenv()).
#
# This script consumes the artifacts produced by 20a (VZ release) and
# 20b (forward state, sub-state, and tipped extensions) and produces two
# canonical monthly panels:
#
#   1. state_binding_panel_monthly.{rds,parquet}
#      keyed on (statefips, year, month). Carries federal MW, state MW,
#      tipped subminimum, and the binding floors derived as max() across
#      jurisdictions. One row per (state, month) covering 1979-01 to today.
#
#   2. substate_binding_panel_monthly.{rds,parquet}
#      keyed on (statefips, locality, year, month). Carries the locality
#      MW (and tipped subminimum where present in the YAML). One row per
#      (locality, month) for months when the locality had a separate
#      ordinance in effect. 20d will join this to CPS observations whose
#      COUNTY or INDIVIDCC identifies a covered locality.
#
# Conventions:
#   - Canonical month rate: max_mw (the rate effective at the end of the
#     month after any mid-month change). Min and mean are preserved for
#     sensitivity analysis. This matches VZ's monthly schema and the
#     Cengiz, Dube, Lindner & Zipperer (2019) convention.
#   - Date range: 1979-01-01 through Sys.Date(). VZ covers 1974-05-01
#     through 2022-12-31; the 20b extension covers 2023-01-01 through
#     today. The 1974-05 to 1978-12 portion of VZ is dropped at this
#     stage to align with the CPS ORG analysis window.
#   - Federal MW post-2022: carried forward at the VZ 2022-12 value
#     ($7.25), since federal MW has not changed since 2009-07-24 and no
#     2023-2026 federal change has been enacted.
#   - Tipped panel is already daily from 20b; aggregated to monthly here
#     by min/mean/max within (state, year, month).
#   - Place-of-residence vs. place-of-work measurement error documented
#     in 20b applies here too. 20d uses CPS state and county of residence
#     as the merge keys.
#
# Inputs:
#   - data/raw/minimum_wage/vz_release/v1.4.0/mw_state_stata/mw_state_monthly.dta
#   - data/raw/minimum_wage/vz_release/v1.4.0/mw_substate_stata/mw_substate_monthly.dta
#   - data/intermediate/minimum_wage/state_panel_extended.parquet
#   - data/intermediate/minimum_wage/substate_panel_extended.parquet
#   - data/intermediate/minimum_wage/state_tipped_panel.parquet
#
# Outputs:
#   - data/intermediate/minimum_wage/state_binding_panel_monthly.{rds,parquet}
#   - data/intermediate/minimum_wage/substate_binding_panel_monthly.{rds,parquet}
#
# No custom functions are defined; all logic is inline.

source(here::here("code", "_utils", "00_packages.R"))

###################################
###   Configuration             ###
###################################

panel_start_dt <- as.Date("1979-01-01")
panel_end_dt   <- Sys.Date()

vz_release_tag_chr <- "v1.4.0"

# Federal MW under the 2009 FLSA amendment is $7.25/hr; this floor has
# not been adjusted since 2009-07-24. Extracted as a named constant
# rather than hard-coded inline.
federal_floor_2009_num <- 7.25

# Locality slug overrides (kept identical to the Python synthesizer's
# LOCALITY_SLUG_OVERRIDES dict in code/_utils/synthesize_extension_yaml.py
# and the same tibble in 20b). Each entry collapses two free-text forms
# of the same ordinance into a single stable join slug. Add a row here
# whenever a new alias is introduced in either VZ or the YAML extension.
locality_slug_overrides_df <- tibble::tribble(
  ~state_fips_int, ~locality_chr,                                ~locality_id_chr_override,
  36L,             "Long Island & Westchester",                  "ny_li_westchester",
  36L,             "Nassau, Suffolk, and Westchester Counties",  "ny_li_westchester"
)

raw_mw_dir_chr        <- here::here("data", "raw", "minimum_wage")
vz_release_dir_chr    <- fs::path(raw_mw_dir_chr, "vz_release", vz_release_tag_chr)
intermediate_dir_chr  <- here::here("data", "intermediate", "minimum_wage")

vz_state_monthly_dta_chr    <- fs::path(vz_release_dir_chr, "mw_state_stata",    "mw_state_monthly.dta")
vz_substate_monthly_dta_chr <- fs::path(vz_release_dir_chr, "mw_substate_stata", "mw_substate_monthly.dta")

state_extended_parquet_chr    <- fs::path(intermediate_dir_chr, "state_panel_extended.parquet")
substate_extended_parquet_chr <- fs::path(intermediate_dir_chr, "substate_panel_extended.parquet")
state_tipped_parquet_chr      <- fs::path(intermediate_dir_chr, "state_tipped_panel.parquet")

required_inputs_chr <- c(
  vz_state_monthly_dta_chr,
  vz_substate_monthly_dta_chr,
  state_extended_parquet_chr,
  substate_extended_parquet_chr,
  state_tipped_parquet_chr
)

missing_inputs_chr <- required_inputs_chr[!fs::file_exists(required_inputs_chr)]

if (length(missing_inputs_chr) > 0L) {
  stop(
    "20c_build-binding-minimum-panel.R -- the following inputs are missing: ",
    paste(missing_inputs_chr, collapse = "; "),
    ". Run 20a and 20b first."
  )
}

fs::dir_create(intermediate_dir_chr, recurse = TRUE)

message("20c_build-binding-minimum-panel.R -- preflight passed.")

###################################
###   1) VZ state monthly       ###
###################################

vz_state_monthly_raw_df <- haven::read_dta(vz_state_monthly_dta_chr) |>
  haven::zap_labels()

# Coerce monthly_date to Date if haven returned it as numeric (Stata
# %tm format = months since 1960-01-01). %tm always represents the
# first day of the month.
if (is.numeric(vz_state_monthly_raw_df$monthly_date)) {
  vz_state_monthly_raw_df$monthly_date <- as.Date(paste0(
    1960L + as.integer(vz_state_monthly_raw_df$monthly_date) %/% 12L, "-",
    sprintf("%02d", (as.integer(vz_state_monthly_raw_df$monthly_date) %% 12L) + 1L),
    "-01"
  ))
}

vz_state_monthly_df <- vz_state_monthly_raw_df |>
  dplyr::filter(monthly_date >= panel_start_dt, monthly_date <= as.Date("2022-12-31")) |>
  dplyr::transmute(
    statefips_int     = as.integer(statefips),
    statename_chr     = as.character(statename),
    stateabb_chr      = as.character(stateabb),
    year_int          = as.integer(format(monthly_date, "%Y")),
    month_int         = as.integer(format(monthly_date, "%m")),
    year_month_dt     = as.Date(monthly_date),
    fed_mw_min_num    = as.numeric(min_fed_mw),
    fed_mw_mean_num   = as.numeric(mean_fed_mw),
    fed_mw_max_num    = as.numeric(max_fed_mw),
    state_mw_min_num  = as.numeric(min_mw),
    state_mw_mean_num = as.numeric(mean_mw),
    state_mw_max_num  = as.numeric(max_mw),
    source_chr        = "VZ_v1.4.0"
  )

message(
  "20c_build-binding-minimum-panel.R -- VZ state monthly: ",
  nrow(vz_state_monthly_df), " rows, ",
  format(min(vz_state_monthly_df$year_month_dt), "%Y-%m"), " to ",
  format(max(vz_state_monthly_df$year_month_dt), "%Y-%m")
)

###################################
###   2) Extension to monthly   ###
###################################
# state_panel_extended_df is daily 2023-01-01 through Sys.Date(). Aggregate
# to monthly by computing min/mean/max of rate_min_num within each
# (jurisdiction, year, month). Federal MW is constant $7.25 across this
# window, so fed columns are populated as 7.25 below.

state_extended_daily_df <- arrow::read_parquet(state_extended_parquet_chr)

state_extended_monthly_df <- state_extended_daily_df |>
  dplyr::mutate(
    year_int  = as.integer(format(date_dt, "%Y")),
    month_int = as.integer(format(date_dt, "%m"))
  ) |>
  dplyr::group_by(jurisdiction_chr, state_abbr_chr, state_fips_int, year_int, month_int) |>
  dplyr::summarise(
    state_mw_min_num  = min(rate_min_num, na.rm = TRUE),
    state_mw_mean_num = mean(rate_min_num, na.rm = TRUE),
    state_mw_max_num  = max(rate_min_num, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::transmute(
    statefips_int     = as.integer(state_fips_int),
    statename_chr     = as.character(jurisdiction_chr),
    stateabb_chr      = as.character(state_abbr_chr),
    year_int,
    month_int,
    year_month_dt     = as.Date(sprintf("%04d-%02d-01", year_int, month_int)),
    fed_mw_min_num    = federal_floor_2009_num,
    fed_mw_mean_num   = federal_floor_2009_num,
    fed_mw_max_num    = federal_floor_2009_num,
    state_mw_min_num,
    state_mw_mean_num,
    state_mw_max_num,
    source_chr        = "extension"
  )

message(
  "20c_build-binding-minimum-panel.R -- extension state monthly: ",
  nrow(state_extended_monthly_df), " rows, ",
  format(min(state_extended_monthly_df$year_month_dt), "%Y-%m"), " to ",
  format(max(state_extended_monthly_df$year_month_dt), "%Y-%m")
)

###################################
###   3) Stack VZ + extension   ###
###################################

state_combined_df <- dplyr::bind_rows(
  vz_state_monthly_df,
  state_extended_monthly_df
) |>
  dplyr::arrange(statefips_int, year_month_dt)

if (nrow(state_combined_df) == 0L) {
  stop(
    "20c_build-binding-minimum-panel.R -- combined state monthly panel ",
    "is empty after stacking. Investigate VZ + extension reads."
  )
}

# Verify continuity: the stack should produce one row per (statefips, year-month)
# with no overlap between VZ end (2022-12) and extension start (2023-01).
n_state_dupes_int <- state_combined_df |>
  dplyr::count(statefips_int, year_month_dt) |>
  dplyr::filter(n > 1L) |>
  nrow()

if (n_state_dupes_int > 0L) {
  stop(
    "20c_build-binding-minimum-panel.R -- ", n_state_dupes_int,
    " duplicate (state, year-month) rows after stacking VZ and extension. ",
    "VZ should end 2022-12 and extension should start 2023-01."
  )
}

# 3b) VZ <-> extension boundary validation -------------------------------
# Every state must have a non-NA rate at 2022-12 (VZ side) AND a non-NA
# rate at 2023-01 (extension side). A gap (missing row on either side)
# is an ingest bug, a state miscoded in the YAML extension, or a stale
# DOL_WHD HTML snapshot.
#
# Note (2026-05-05): we deliberately do NOT require the two rates to
# match in level. Many states have legitimate Jan 1, 2023 indexed
# step-ups (AK, CA, CO, ME, MN, MI, MT, NV, OR, WA, etc.) or
# scheduled-increase laws (FL, IL, MD, NJ, RI, VA, etc.); a level
# difference at the boundary is the rule, not the exception. The
# previous strict-equality check fired on 29 states' real rate
# changes, all false positives. The replacement check tests only
# coverage; level differences are summarized as informational logs.
#
# Comparison uses the BINDING rate -- pmax(state_mw_max_num,
# fed_mw_max_num) -- not the raw state statutory rate. VZ's max_mw
# column reports the EFFECTIVE state floor (federal preemption
# folded in), while the YAML extension carries the de jure STATUTORY
# state rate. For federally-preempted states like GA and WY (statutory
# $5.15, effective $7.25), the raw-state comparison spuriously shows
# a $7.25 -> $5.15 drop. Comparing post-pmax binding rates is
# semantically the right quantity and silences that false positive.
boundary_check_df <- vz_state_monthly_df |>
  dplyr::filter(year_int == 2022L, month_int == 12L) |>
  dplyr::transmute(
    statefips_int,
    vz_rate_num = pmax(state_mw_max_num, fed_mw_max_num, na.rm = TRUE)
  ) |>
  dplyr::full_join(
    state_extended_monthly_df |>
      dplyr::filter(year_int == 2023L, month_int == 1L) |>
      dplyr::transmute(
        statefips_int,
        ext_rate_num = pmax(state_mw_max_num, fed_mw_max_num, na.rm = TRUE)
      ),
    by = "statefips_int"
  ) |>
  dplyr::mutate(diff_num = ext_rate_num - vz_rate_num)

# Hard fail on missing coverage on either side.
gap_states_df <- boundary_check_df |>
  dplyr::filter(is.na(vz_rate_num) | is.na(ext_rate_num))

if (nrow(gap_states_df) > 0L) {
  stop(
    "20c_build-binding-minimum-panel.R -- VZ/extension boundary GAP ",
    "detected for ", nrow(gap_states_df), " state(s) -- one side is NA. ",
    "Every state must have non-NA rates at both 2022-12 (VZ) and 2023-01 ",
    "(extension). Failing state_fips: ",
    paste(gap_states_df$statefips_int, collapse = ", ")
  )
}

# Informational summary of rate changes at the boundary. Decreases
# beyond rounding noise are unusual (almost no MW law cuts a rate
# year-over-year) and surface here as a soft warning rather than a
# fatal error; review them but they do not block the pipeline.
n_changed_int   <- sum(abs(boundary_check_df$diff_num) > 0.005, na.rm = TRUE)
n_unchanged_int <- nrow(boundary_check_df) - n_changed_int
max_increase_num <- max(boundary_check_df$diff_num, na.rm = TRUE)
suspicious_decreases_df <- boundary_check_df |>
  dplyr::filter(diff_num < -0.01)

message(
  "20c_build-binding-minimum-panel.R -- VZ<->extension boundary coverage ",
  "OK for ", nrow(boundary_check_df), " jurisdictions; ",
  n_changed_int, " state(s) had a 2023-01 step-up vs 2022-12 ",
  "(max increase $", format(round(max_increase_num, 2), nsmall = 2), "), ",
  n_unchanged_int, " unchanged."
)

if (nrow(suspicious_decreases_df) > 0L) {
  message(
    "20c_build-binding-minimum-panel.R -- WARNING: ",
    nrow(suspicious_decreases_df), " state(s) show a 2023-01 rate BELOW ",
    "the 2022-12 rate by more than $0.01; minimum-wage cuts are unusual ",
    "and may indicate a parse error. Review state_fips: ",
    paste(suspicious_decreases_df$statefips_int, collapse = ", ")
  )
}

###################################
###   4) State tipped monthly   ###
###################################
# state_tipped_panel from 20b is daily 1974-05-01 to today. Aggregate to
# monthly by min/mean/max within (jurisdiction, year, month). Filter to
# panel start of 1979-01 to align with the state_combined_df range.

state_tipped_daily_df <- arrow::read_parquet(state_tipped_parquet_chr)

state_tipped_monthly_df <- state_tipped_daily_df |>
  dplyr::filter(date_dt >= panel_start_dt) |>
  dplyr::mutate(
    year_int  = as.integer(format(date_dt, "%Y")),
    month_int = as.integer(format(date_dt, "%m"))
  ) |>
  dplyr::group_by(state_fips_int, year_int, month_int) |>
  dplyr::summarise(
    state_tipped_min_num  = min(rate_tipped_num, na.rm = TRUE),
    state_tipped_mean_num = mean(rate_tipped_num, na.rm = TRUE),
    state_tipped_max_num  = max(rate_tipped_num, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::transmute(
    statefips_int = as.integer(state_fips_int),
    year_int,
    month_int,
    state_tipped_min_num,
    state_tipped_mean_num,
    state_tipped_max_num
  )

message(
  "20c_build-binding-minimum-panel.R -- state tipped monthly: ",
  nrow(state_tipped_monthly_df), " rows."
)

###################################
###   5) Compute binding floors ###
###################################
# Merge tipped into the combined state-month panel and compute:
#   binding_general_floor_num: max(fed_mw_max, state_mw_max) — the floor
#     for general workers in (state, month).
#   binding_tipped_floor_num: max of fed_tipped (effectively state_tipped
#     since state_tipped already incorporates federal default) — the
#     floor for tipped occupations in (state, month).
# All floors use the max-of-month convention (rate at end of month).

state_binding_panel_monthly_df <- state_combined_df |>
  dplyr::left_join(
    state_tipped_monthly_df,
    by = c("statefips_int", "year_int", "month_int")
  ) |>
  dplyr::mutate(
    binding_general_floor_num = pmax(fed_mw_max_num, state_mw_max_num, na.rm = TRUE),
    binding_tipped_floor_num  = state_tipped_max_num
  ) |>
  dplyr::select(
    statefips_int,
    statename_chr,
    stateabb_chr,
    year_int,
    month_int,
    year_month_dt,
    fed_mw_min_num,
    fed_mw_mean_num,
    fed_mw_max_num,
    state_mw_min_num,
    state_mw_mean_num,
    state_mw_max_num,
    state_tipped_min_num,
    state_tipped_mean_num,
    state_tipped_max_num,
    binding_general_floor_num,
    binding_tipped_floor_num,
    source_chr
  )

message(
  "20c_build-binding-minimum-panel.R -- state binding panel: ",
  nrow(state_binding_panel_monthly_df), " rows, ",
  length(unique(state_binding_panel_monthly_df$statefips_int)),
  " jurisdictions, ",
  format(min(state_binding_panel_monthly_df$year_month_dt), "%Y-%m"), " to ",
  format(max(state_binding_panel_monthly_df$year_month_dt), "%Y-%m")
)

###################################
###   6) VZ substate monthly    ###
###################################

vz_substate_monthly_raw_df <- haven::read_dta(vz_substate_monthly_dta_chr) |>
  haven::zap_labels()

# Coerce monthly_date to Date if haven returned it as numeric (Stata %tm).
if (is.numeric(vz_substate_monthly_raw_df$monthly_date)) {
  vz_substate_monthly_raw_df$monthly_date <- as.Date(paste0(
    1960L + as.integer(vz_substate_monthly_raw_df$monthly_date) %/% 12L, "-",
    sprintf("%02d", (as.integer(vz_substate_monthly_raw_df$monthly_date) %% 12L) + 1L),
    "-01"
  ))
}

vz_substate_monthly_df <- vz_substate_monthly_raw_df |>
  dplyr::filter(monthly_date >= panel_start_dt, monthly_date <= as.Date("2022-12-31")) |>
  dplyr::transmute(
    statefips_int        = as.integer(statefips),
    statename_chr        = as.character(statename),
    stateabb_chr         = as.character(stateabb),
    locality_chr         = as.character(locality),
    year_int             = as.integer(format(monthly_date, "%Y")),
    month_int            = as.integer(format(monthly_date, "%m")),
    year_month_dt        = as.Date(monthly_date),
    locality_mw_min_num  = as.numeric(min_mw),
    locality_mw_mean_num = as.numeric(mean_mw),
    locality_mw_max_num  = as.numeric(max_mw),
    locality_tipped_min_num  = NA_real_,
    locality_tipped_mean_num = NA_real_,
    locality_tipped_max_num  = NA_real_,
    abovestate_flag      = as.logical(abovestate),
    source_chr           = "VZ_v1.4.0"
  )

# Attach locality_id_chr (the stable slug join key) inline. Slug rule
# matches code/_utils/synthesize_extension_yaml.py:slugify_locality and
# the equivalent block in 20b: override table first, then deterministic
# state_abbr_lower + snake_case-of-locality (apostrophes stripped, '&'
# expanded to 'and', non-alphanumerics collapsed).
vz_substate_monthly_df <- vz_substate_monthly_df |>
  dplyr::left_join(
    locality_slug_overrides_df,
    by = c("statefips_int" = "state_fips_int", "locality_chr")
  ) |>
  dplyr::mutate(
    locality_id_chr = dplyr::coalesce(
      locality_id_chr_override,
      paste0(
        tolower(stateabb_chr), "_",
        locality_chr |>
          stringr::str_replace_all("’", "") |>
          stringr::str_replace_all("'", "") |>
          stringr::str_replace_all("&", "and") |>
          tolower() |>
          stringr::str_replace_all("[^a-z0-9]+", "_") |>
          stringr::str_replace_all("^_|_$", "")
      )
    )
  ) |>
  dplyr::select(-locality_id_chr_override)

message(
  "20c_build-binding-minimum-panel.R -- VZ substate monthly: ",
  nrow(vz_substate_monthly_df), " rows, ",
  length(unique(vz_substate_monthly_df$locality_id_chr)), " localities (by slug), ",
  format(min(vz_substate_monthly_df$year_month_dt), "%Y-%m"), " to ",
  format(max(vz_substate_monthly_df$year_month_dt), "%Y-%m")
)

###################################
###   7) Substate extension     ###
###################################

substate_extended_daily_df <- arrow::read_parquet(substate_extended_parquet_chr)

if (nrow(substate_extended_daily_df) > 0L) {

  substate_extended_monthly_df <- substate_extended_daily_df |>
    dplyr::mutate(
      year_int  = as.integer(format(date_dt, "%Y")),
      month_int = as.integer(format(date_dt, "%m"))
    ) |>
    dplyr::group_by(
      jurisdiction_state_chr,
      state_abbr_chr,
      state_fips_int,
      locality_chr,
      locality_id_chr,
      year_int,
      month_int
    ) |>
    dplyr::summarise(
      locality_mw_min_num      = min(rate_min_num, na.rm = TRUE),
      locality_mw_mean_num     = mean(rate_min_num, na.rm = TRUE),
      locality_mw_max_num      = max(rate_min_num, na.rm = TRUE),
      locality_tipped_min_num  = min(rate_tipped_num, na.rm = TRUE),
      locality_tipped_mean_num = mean(rate_tipped_num, na.rm = TRUE),
      locality_tipped_max_num  = max(rate_tipped_num, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::transmute(
      statefips_int  = as.integer(state_fips_int),
      statename_chr  = as.character(jurisdiction_state_chr),
      stateabb_chr   = as.character(state_abbr_chr),
      locality_chr,
      locality_id_chr,
      year_int,
      month_int,
      year_month_dt  = as.Date(sprintf("%04d-%02d-01", year_int, month_int)),
      locality_mw_min_num,
      locality_mw_mean_num,
      locality_mw_max_num,
      # Replace the Inf/-Inf produced by min/max on all-NA tipped groups
      # (where the YAML did not carry a rate_tipped) with explicit NA.
      locality_tipped_min_num  = dplyr::if_else(
        is.finite(locality_tipped_min_num), locality_tipped_min_num, NA_real_
      ),
      locality_tipped_mean_num = dplyr::if_else(
        is.nan(locality_tipped_mean_num), NA_real_, locality_tipped_mean_num
      ),
      locality_tipped_max_num  = dplyr::if_else(
        is.finite(locality_tipped_max_num), locality_tipped_max_num, NA_real_
      ),
      abovestate_flag = NA,
      source_chr      = "extension"
    )

  message(
    "20c_build-binding-minimum-panel.R -- substate extension monthly: ",
    nrow(substate_extended_monthly_df), " rows, ",
    length(unique(substate_extended_monthly_df$locality_id_chr)), " localities (by slug)."
  )

} else {

  substate_extended_monthly_df <- tibble::tibble(
    statefips_int            = integer(0L),
    statename_chr            = character(0L),
    stateabb_chr             = character(0L),
    locality_chr             = character(0L),
    locality_id_chr          = character(0L),
    year_int                 = integer(0L),
    month_int                = integer(0L),
    year_month_dt            = as.Date(character(0L)),
    locality_mw_min_num      = numeric(0L),
    locality_mw_mean_num     = numeric(0L),
    locality_mw_max_num      = numeric(0L),
    locality_tipped_min_num  = numeric(0L),
    locality_tipped_mean_num = numeric(0L),
    locality_tipped_max_num  = numeric(0L),
    abovestate_flag          = logical(0L),
    source_chr               = character(0L)
  )
}

###################################
###   8) Stack substate         ###
###################################
# Note: the abovestate_flag column is logical in the extension and
# numeric (originally) in VZ; both have been coerced to logical for
# consistency. VZ's 0/1 maps to FALSE/TRUE.

substate_binding_panel_monthly_df <- dplyr::bind_rows(
  vz_substate_monthly_df,
  substate_extended_monthly_df
) |>
  dplyr::arrange(statefips_int, locality_id_chr, year_month_dt)

# Duplicate detection now keyed on locality_id_chr (the stable slug),
# not the free-text locality_chr. The slug also
# collapses VZ-form and extension-form aliases (e.g., NY tri-county) to
# a single key.
n_substate_dupes_int <- substate_binding_panel_monthly_df |>
  dplyr::count(statefips_int, locality_id_chr, year_month_dt) |>
  dplyr::filter(n > 1L) |>
  nrow()

if (n_substate_dupes_int > 0L) {
  stop(
    "20c_build-binding-minimum-panel.R -- ", n_substate_dupes_int,
    " duplicate (state, locality_id, year-month) rows after stacking VZ ",
    "and extension. Investigate slug harmonization in 20b's ",
    "locality_slug_overrides_df and the synthesizer's ",
    "LOCALITY_SLUG_OVERRIDES dict."
  )
}

# Defensive: every panel row must have a non-NA locality_id_chr,
# otherwise the 20d join cannot be computed. Fail loudly.
if (any(is.na(substate_binding_panel_monthly_df$locality_id_chr))) {
  n_na_slug_int <- sum(is.na(substate_binding_panel_monthly_df$locality_id_chr))
  stop(
    "20c_build-binding-minimum-panel.R -- ", n_na_slug_int,
    " substate panel row(s) have NA locality_id_chr. The slug ",
    "derivation block should produce a non-NA value for every ",
    "(statefips, locality_chr) input."
  )
}

message(
  "20c_build-binding-minimum-panel.R -- substate binding panel: ",
  nrow(substate_binding_panel_monthly_df), " rows, ",
  substate_binding_panel_monthly_df |>
    dplyr::distinct(statefips_int, locality_id_chr) |>
    nrow(),
  " distinct (state, locality_id) pairs."
)

###################################
###   9) Write outputs          ###
###################################

saveRDS(
  state_binding_panel_monthly_df,
  fs::path(intermediate_dir_chr, "state_binding_panel_monthly.rds")
)
arrow::write_parquet(
  state_binding_panel_monthly_df,
  fs::path(intermediate_dir_chr, "state_binding_panel_monthly.parquet")
)

saveRDS(
  substate_binding_panel_monthly_df,
  fs::path(intermediate_dir_chr, "substate_binding_panel_monthly.rds")
)
arrow::write_parquet(
  substate_binding_panel_monthly_df,
  fs::path(intermediate_dir_chr, "substate_binding_panel_monthly.parquet")
)

message(
  "20c_build-binding-minimum-panel.R -- wrote state_binding_panel_monthly ",
  "and substate_binding_panel_monthly .{rds,parquet} to ",
  intermediate_dir_chr
)

###################################
###   Success log               ###
###################################

message(
  "20c_build-binding-minimum-panel.R -- done. State panel covers ",
  format(min(state_binding_panel_monthly_df$year_month_dt), "%Y-%m"), " to ",
  format(max(state_binding_panel_monthly_df$year_month_dt), "%Y-%m"),
  "; substate panel covers ",
  format(min(substate_binding_panel_monthly_df$year_month_dt), "%Y-%m"), " to ",
  format(max(substate_binding_panel_monthly_df$year_month_dt), "%Y-%m"),
  ". Ready for 20d CPS ORG merge."
)
