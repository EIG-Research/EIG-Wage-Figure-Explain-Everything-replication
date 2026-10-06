# 20d_merge-cps-binding -- merge state binding minimum panel to CPS-ORG real wages and construct the at-or-below-binding indicator
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
# This script consumes the year-partitioned cps_real_wages panel from 02a
# and the state_binding_panel_monthly from 20c, then constructs:
#
#   - data/intermediate/cps_binding_indicator/year=YYYY/part-0.{rds,parquet}
#     One row per CPS-ORG hourly-paid worker observation (PAIDHOUR == 2)
#     for 1979 onward, carrying every cps_real_wages column plus:
#       - state_general_floor_num: state binding general floor for the
#         worker's state-month, max(federal, state) per 20c
#       - state_tipped_floor_num: state tipped floor (federal default
#         $2.13 outside the YAML override window pending task 18)
#       - locality_chr: VZ locality_chr matched via concordance, or NA
#         if no city/county concordance match
#       - locality_general_floor_num: locality MW floor for the worker's
#         (locality, year, month), or NA if no locality match
#       - locality_tipped_floor_num: locality cash-tipped subminimum,
#         or NA if no locality match or VZ does not track tipped for it
#       - effective_general_floor_num: max(state_general_floor_num,
#         locality_general_floor_num); the canonical binding floor for
#         general workers
#       - effective_tipped_floor_num: max(state_tipped_floor_num,
#         locality_tipped_floor_num); analogous for tipped
#       - is_tipped_occupation_flag: TRUE for OCC2010 codes in the
#         tipped-occupation list defined below
#       - applicable_floor_num: effective_tipped_floor_num if tipped
#         occupation else effective_general_floor_num
#       - at_or_below_general_flag: nominal_hourly_wage_num <= effective_general_floor_num
#       - at_or_below_tipped_flag: nominal_hourly_wage_num <= effective_tipped_floor_num
#       - at_or_below_applicable_flag: at_or_below_tipped_flag if tipped
#         else at_or_below_general_flag (the canonical binding indicator)
#
# Sub-state binding floors (county- and city-level localities from VZ's
# substate_binding_panel_monthly) are merged via two hand-curated
# concordance files at data/raw/minimum_wage/concordance/:
#   - county_to_locality.csv:    (state_fips, county_fips) -> locality_chr
#   - individcc_to_locality.csv: (state_fips, metfips, county_fips,
#                                 individcc, era) -> locality_chr
# City-level matches take priority over county-level; both are coded
# era-aware to handle the 2015 IPUMS-CPS METFIPS code change for
# several MSAs (LA, Minneapolis, etc.). Localities not represented in
# the concordance fall back to state-level binding only — currently a
# documented gap for smaller California Bay Area cities like Belmont,
# Cupertino, Daly City, Half Moon Bay that VZ tracks but IPUMS does
# not separately identify.
#
# Required cps_real_wages columns (added 2026-05-04 to 00a's IPUMS
# variable list and 02a's keep_cols_chr; the user must re-run 00a, 01a,
# 01b, 02a after that change before 20d can succeed):
#   STATEFIP, COUNTY, METFIPS, INDIVIDCC, OCC2010
#
# Tipped-occupation classification: a baseline list of OCC2010 codes
# corresponding to tipped occupations per BLS Wage and Hour Division
# guidance. The user may adjust this list; documented below at the
# tipped_occ_codes_int definition.
#
# No custom functions are defined; all logic is inline.

source(here::here("code", "_utils", "00_packages.R"))

###################################
###   Configuration             ###
###################################

panel_in_dir_chr   <- here::here("data", "intermediate", "cps_real_wages")
binding_dir_chr    <- here::here("data", "intermediate", "minimum_wage")
concordance_dir_chr <- here::here("data", "raw", "minimum_wage", "concordance")
panel_out_dir_chr  <- here::here("data", "intermediate", "cps_binding_indicator")

state_binding_parquet_chr <- fs::path(
  binding_dir_chr, "state_binding_panel_monthly.parquet"
)
substate_binding_parquet_chr <- fs::path(
  binding_dir_chr, "substate_binding_panel_monthly.parquet"
)
county_concordance_csv_chr <- fs::path(concordance_dir_chr, "county_to_locality.csv")
individcc_concordance_csv_chr <- fs::path(concordance_dir_chr, "individcc_to_locality.csv")

# CPS analytic window. CPS-ORG hourly wage data is conventionally
# available from 1979 forward; the existing project pipeline starts at
# 1982 per 00a's extract_start_year_int. The binding panel covers 1979+,
# so the effective merge range is the intersection — driven by which
# year partitions exist on disk.
panel_start_year_int <- 1979L

# Tipped-occupation OCC2010 codes. Baseline derived from FLSA's
# definition of "tipped employee" (workers customarily and regularly
# receiving more than $30 per month in tips, per 29 USC 203(t); see also
# DOL WHD Fact Sheet #15). Concentrated in food service, personal
# care, and certain hospitality and transportation roles. The
# integer codes drive the merge; comments cite canonical IPUMS-CPS
# OCC2010 labels. Adjust this list to broaden or narrow the
# tipped-occupation universe; the source-of-truth for code definitions
# is the IPUMS-CPS OCC2010 codebook
# (https://cps.ipums.org/cps/codes/occ_20112019_codes.shtml).
#
# Membership change 2026-05-05 after an internal code review
# (CRITICAL): comments were corrected to canonical labels and the list
# was rebalanced. Added 4020 (Cooks), 4530 (Baggage porters/bellhops/
# concierges), 5300 (Hotel, motel, and resort desk clerks). Removed
# 4710 (First-line supervisors of non-retail sales workers) and 4720
# (Cashiers) — neither is tipped under FLSA.
tipped_occ_codes_int <- c(
  4020L,  # Cooks
  4040L,  # Bartenders
  4060L,  # Counter attendants, cafeteria, food concession, and coffee shop
  4110L,  # Waiters and waitresses
  4120L,  # Food servers, nonrestaurant
  4130L,  # Dining room and cafeteria attendants and bartender helpers
  4140L,  # Dishwashers
  4150L,  # Hosts and hostesses, restaurant, lounge, and coffee shop
  4160L,  # Food preparation and serving related workers, all other
  4500L,  # Barbers
  4510L,  # Hairdressers, hairstylists, and cosmetologists
  4520L,  # Miscellaneous personal appearance workers
  4530L,  # Baggage porters, bellhops, and concierges
  5300L,  # Hotel, motel, and resort desk clerks
  9140L   # Taxi drivers and chauffeurs
)

# Assertion: the list must be unique and sorted. Replaces the prior
# unique() + duplicate-guard comment pattern.
stopifnot(
  !anyDuplicated(tipped_occ_codes_int),
  identical(tipped_occ_codes_int, sort(tipped_occ_codes_int))
)

###################################
###   1) Preflight              ###
###################################

if (!fs::file_exists(state_binding_parquet_chr)) {
  stop(
    "20d_merge-cps-binding.R -- state binding panel not found at ",
    state_binding_parquet_chr, ". Run 20c first."
  )
}

if (!fs::file_exists(substate_binding_parquet_chr)) {
  stop(
    "20d_merge-cps-binding.R -- substate binding panel not found at ",
    substate_binding_parquet_chr, ". Run 20c first."
  )
}

year_partition_paths_chr <- fs::dir_ls(
  panel_in_dir_chr, type = "directory", regexp = "year=\\d{4}$"
)

if (length(year_partition_paths_chr) == 0L) {
  stop(
    "20d_merge-cps-binding.R -- no cps_real_wages year partitions found in ",
    panel_in_dir_chr, ". Run 02a first."
  )
}

panel_years_int <- sort(as.integer(stringr::str_extract(
  basename(year_partition_paths_chr), "\\d{4}"
)))

panel_years_int <- panel_years_int[panel_years_int >= panel_start_year_int]

if (length(panel_years_int) == 0L) {
  stop(
    "20d_merge-cps-binding.R -- no cps_real_wages year partitions at or ",
    "after ", panel_start_year_int, "."
  )
}

message(
  "20d_merge-cps-binding.R -- merging ", length(panel_years_int),
  " year partitions covering ", min(panel_years_int), " - ",
  max(panel_years_int), "."
)

fs::dir_create(panel_out_dir_chr, recurse = TRUE)

###################################
###   2) Load state binding     ###
###################################
# Read the state binding panel once. The panel is small (~29,000 rows);
# loading once avoids re-reading per year partition.

state_binding_df <- arrow::read_parquet(state_binding_parquet_chr) |>
  dplyr::transmute(
    STATEFIP        = as.integer(statefips_int),
    YEAR            = as.integer(year_int),
    MONTH           = as.integer(month_int),
    statename_chr   = as.character(statename_chr),
    stateabb_chr    = as.character(stateabb_chr),
    state_general_floor_num = as.numeric(binding_general_floor_num),
    state_tipped_floor_num  = as.numeric(binding_tipped_floor_num)
  )

message(
  "20d_merge-cps-binding.R -- loaded state binding panel: ",
  nrow(state_binding_df), " rows."
)

###################################
###   2b) Load substate binding ###
###################################
# Substate panel is keyed on (STATEFIP, locality_id_chr, YEAR, MONTH).
# locality_id_chr is the stable slug written by 20c via the slug
# overrides table + deterministic snake_case rule (kept identical to
# the Python synthesizer's slugify_locality function). The slug
# absorbs all free-text drift between VZ and the YAML extension,
# including the New York tri-county pair (VZ "Long Island &
# Westchester" / YAML "Nassau, Suffolk, and Westchester Counties"
# both -> ny_li_westchester) and the apostrophe variants of
# "Prince George's County" (curly U+2019 in YAML, straight in VZ;
# both -> md_prince_georges_county). locality_chr survives as a
# display label but is no longer load-bearing for the join.

substate_binding_df <- arrow::read_parquet(substate_binding_parquet_chr) |>
  dplyr::transmute(
    STATEFIP        = as.integer(statefips_int),
    # locality_id_chr is the stable join key written by 20c (slug
    # registry collapses VZ-form and extension-form aliases — most
    # importantly the New York tri-county pair — onto a single key).
    # locality_chr is retained for display only.
    locality_id_chr = as.character(locality_id_chr),
    locality_chr    = as.character(locality_chr),
    YEAR            = as.integer(year_int),
    MONTH           = as.integer(month_int),
    locality_general_floor_num = as.numeric(locality_mw_max_num),
    locality_tipped_floor_num  = as.numeric(locality_tipped_max_num)
  )

# Deduplicate to one row per (STATEFIP, locality_id_chr, YEAR, MONTH).
# Slug-aware grouping replaces the prior (STATEFIP, locality_chr, YEAR,
# MONTH) collapse so VZ and extension panels with different display
# strings (e.g., "Long Island & Westchester" vs "Nassau, Suffolk, and
# Westchester Counties") fold to one row.
substate_binding_df <- substate_binding_df |>
  dplyr::group_by(STATEFIP, locality_id_chr, YEAR, MONTH) |>
  dplyr::summarise(
    locality_chr               = dplyr::first(sort(locality_chr)),
    locality_general_floor_num = max(locality_general_floor_num, na.rm = TRUE),
    locality_tipped_floor_num  = max(locality_tipped_floor_num, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    locality_general_floor_num = dplyr::if_else(
      is.finite(locality_general_floor_num),
      locality_general_floor_num, NA_real_
    ),
    locality_tipped_floor_num = dplyr::if_else(
      is.finite(locality_tipped_floor_num),
      locality_tipped_floor_num, NA_real_
    )
  )

message(
  "20d_merge-cps-binding.R -- loaded substate binding panel: ",
  nrow(substate_binding_df), " rows; ",
  length(unique(substate_binding_df$locality_id_chr)), " distinct localities (by slug)."
)

###################################
###   2c) Load concordances     ###
###################################
# Two concordances map CPS geography to VZ locality_chr names.
# city-level (individcc) takes priority over county-level when both
# match for a given CPS observation, since city is more specific.

if (fs::file_exists(county_concordance_csv_chr)) {
  # readr::read_csv with explicit col_types is used in place of
  # utils::read.csv to (a) enforce strict RFC-4180 quoting (apostrophe is
  # NOT a quote character), and (b) fail loudly via stop_for_problems()
  # if any row has the wrong number of fields. utils::read.csv silently
  # spilled a stray comma in row 11's notes_chr into the next row when
  # the field was unquoted, misaligning 6 county entries (Bernalillo NM,
  # Santa Fe NM, King WA, Long Island & Westchester NY x 3) -- see
  # internal code review, 2026-05-14.
  county_concordance_df <- readr::read_csv(
    county_concordance_csv_chr,
    col_types = readr::cols(
      state_fips_int  = readr::col_integer(),
      county_fips_int = readr::col_integer(),
      locality_id_chr = readr::col_character(),
      locality_chr    = readr::col_character(),
      source_chr      = readr::col_character(),
      notes_chr       = readr::col_character()
    ),
    show_col_types = FALSE
  )
  readr::stop_for_problems(county_concordance_df)
  county_concordance_df <- county_concordance_df |>
    dplyr::transmute(
      STATEFIP                = as.integer(state_fips_int),
      county_fips_3_int       = as.integer(county_fips_int),
      locality_county_id_chr  = as.character(locality_id_chr)
    )
} else {
  county_concordance_df <- tibble::tibble(
    STATEFIP                = integer(0L),
    county_fips_3_int       = integer(0L),
    locality_county_id_chr  = character(0L)
  )
  message(
    "20d_merge-cps-binding.R -- county concordance not present at ",
    county_concordance_csv_chr, "; sub-state county-level binding will not be merged."
  )
}

# Era boundaries are stored as YYYYMM integers (e.g., 201507 inclusive
# end of pre-Aug-2015 regime, 201508 start of post-Aug-2015 regime).
# IPUMS-CPS recodes METFIPS for several MSAs starting Aug 2015 per
# https://cps.ipums.org/cps/codes/individcc_aug2015_onward_codes.shtml;
# CPS observations from Jan-Jul 2015 still carry pre-2015 INDIVIDCC
# values and must match the pre-era concordance entry. Whole-year
# boundaries (the prior schema) misrouted the Jan-Jul 2015 cohort
#.
if (fs::file_exists(individcc_concordance_csv_chr)) {
  # Same readr::read_csv + stop_for_problems pattern as the county
  # concordance read above. Strict typing surfaces any future malformed
  # row instead of letting it silently misalign columns.
  individcc_concordance_df <- readr::read_csv(
    individcc_concordance_csv_chr,
    col_types = readr::cols(
      state_fips_int          = readr::col_integer(),
      metfips_int             = readr::col_integer(),
      county_fips_5digit_int  = readr::col_integer(),
      individcc_int           = readr::col_integer(),
      era_start_yearmonth_int = readr::col_integer(),
      era_end_yearmonth_int   = readr::col_integer(),
      locality_id_chr         = readr::col_character(),
      locality_chr            = readr::col_character(),
      source_chr              = readr::col_character(),
      notes_chr               = readr::col_character()
    ),
    show_col_types = FALSE
  )
  readr::stop_for_problems(individcc_concordance_df)
  individcc_concordance_df <- individcc_concordance_df |>
    dplyr::transmute(
      STATEFIP                  = as.integer(state_fips_int),
      METFIPS                   = as.integer(metfips_int),
      county_5digit_int         = as.integer(county_fips_5digit_int),
      INDIVIDCC                 = as.integer(individcc_int),
      era_start_yearmonth_int   = as.integer(era_start_yearmonth_int),
      era_end_yearmonth_int     = as.integer(era_end_yearmonth_int),
      locality_city_id_chr      = as.character(locality_id_chr)
    )
} else {
  individcc_concordance_df <- tibble::tibble(
    STATEFIP                = integer(0L),
    METFIPS                 = integer(0L),
    county_5digit_int       = integer(0L),
    INDIVIDCC               = integer(0L),
    era_start_yearmonth_int = integer(0L),
    era_end_yearmonth_int   = integer(0L),
    locality_city_id_chr    = character(0L)
  )
  message(
    "20d_merge-cps-binding.R -- individcc concordance not present at ",
    individcc_concordance_csv_chr, "; sub-state city-level binding will not be merged."
  )
}

message(
  "20d_merge-cps-binding.R -- concordances loaded: ",
  nrow(county_concordance_df), " county-level entries, ",
  nrow(individcc_concordance_df), " city-level entries (across both era regimes)."
)

###################################
###   3) Iterate year partitions ###
###################################
# Process one year at a time to bound peak memory: each cps_real_wages
# year partition is roughly 100k-200k rows, well within memory, but the
# full 1982-2026 panel summed is ~6-8M rows.

run_summary_df <- tibble::tibble(
  year_int               = integer(0L),
  n_input_rows_int       = integer(0L),
  n_hourly_paid_int      = integer(0L),
  n_after_state_join_int = integer(0L),
  n_unmatched_state_int  = integer(0L),
  n_at_or_below_int      = integer(0L)
)

for (yr in panel_years_int) {

  in_partition_path_chr <- fs::path(
    panel_in_dir_chr, paste0("year=", yr), "part-0.parquet"
  )

  if (!fs::file_exists(in_partition_path_chr)) {
    message(
      "20d_merge-cps-binding.R -- year ", yr, ": expected partition ",
      in_partition_path_chr, " missing; skipping."
    )
    next
  }

  panel_df <- arrow::read_parquet(in_partition_path_chr)

  required_cps_cols_chr <- c(
    "YEAR", "MONTH", "EARNWT", "PAIDHOUR",
    "nominal_hourly_wage_num",
    "STATEFIP", "COUNTY", "METFIPS", "INDIVIDCC", "OCC2010"
  )

  missing_cps_cols_chr <- setdiff(required_cps_cols_chr, names(panel_df))

  if (length(missing_cps_cols_chr) > 0L) {
    stop(
      "20d_merge-cps-binding.R -- year ", yr, " partition is missing ",
      "required columns: ", paste(missing_cps_cols_chr, collapse = ", "),
      ". Update 00a's variables_list and 02a's keep_cols_chr to include ",
      "STATEFIP, COUNTY, METFIPS, INDIVIDCC, OCC2010 and re-run ",
      "00a -> 01a -> 01b -> 02a."
    )
  }

  n_input_rows_int <- nrow(panel_df)

  # 3.1) Restrict to hourly-paid workers --------------------------------------
  # Per the design decision, the binding-MW analysis sample is
  # CPS-ORG hourly-paid workers (PAIDHOUR == 2). PAIDHOUR codes:
  # 0 = NIU (not in universe, e.g., self-employed or out of labor
  # force), 1 = paid by the hour but on salary base, 2 = paid by the
  # hour. The hourly-wage variable in CPS-ORG is most reliably
  # measured for PAIDHOUR == 2; non-hourly workers' hourly wages are
  # derived from earnings/hours and carry more measurement noise.
  # Tipped workers paid on a salary-equivalent basis (a small
  # fraction; most tipped workers receive hourly wages) are excluded
  # by this restriction, which slightly under-states the tipped-
  # subgroup binding share.
  #
  # Also require non-NA hourly wage to ensure the binding indicator
  # is computable. PAIDHOUR has not-in-universe codes that surface as
  # NA in early-year edge cases; guarding !is.na(PAIDHOUR) prevents
  # NA propagation through `&`, which otherwise silently produces
  # NA-row tibbles.
  hourly_paid_bool <- !is.na(panel_df$PAIDHOUR) &
    panel_df$PAIDHOUR == 2L &
    !is.na(panel_df$nominal_hourly_wage_num)

  panel_hourly_df <- panel_df[hourly_paid_bool, , drop = FALSE]

  # 3.1b) Drop STATEFIP == 99 (household not in any state) -----------
  # CPS codes STATEFIP == 99 for households whose state cannot be
  # identified (suppressed for confidentiality in some early years).
  # These rows have no defensible state binding floor; pmax(NA, ...)
  # silently classified them as not-bound under the prior code,
  # under-stating the binding share by their EARNWT-weighted share
  #. Drop them with a diagnostic.
  no_state_bool <- panel_hourly_df$STATEFIP == 99L
  if (any(no_state_bool, na.rm = TRUE)) {
    n_no_state_int  <- sum(no_state_bool, na.rm = TRUE)
    earnwt_no_state_num <- sum(
      panel_hourly_df$EARNWT[no_state_bool], na.rm = TRUE
    )
    earnwt_total_num <- sum(panel_hourly_df$EARNWT, na.rm = TRUE)
    message(
      "20d_merge-cps-binding.R -- year ", yr, ": dropping ",
      format(n_no_state_int, big.mark = ","),
      " row(s) with STATEFIP == 99 (household not in any state); ",
      "EARNWT-weighted share = ",
      format(round(100 * earnwt_no_state_num / max(earnwt_total_num, 1), 4L),
             nsmall = 4L), "%."
    )
    panel_hourly_df <- panel_hourly_df[!no_state_bool, , drop = FALSE]
  }
  n_hourly_paid_int <- nrow(panel_hourly_df)

  # 3.2) Merge state binding floor --------------------------------------------

  panel_with_floor_df <- panel_hourly_df |>
    dplyr::mutate(
      STATEFIP = as.integer(STATEFIP),
      YEAR     = as.integer(YEAR),
      MONTH    = as.integer(MONTH)
    ) |>
    dplyr::left_join(
      state_binding_df,
      by = c("STATEFIP", "YEAR", "MONTH")
    )

  n_after_state_join_int <- nrow(panel_with_floor_df)
  n_unmatched_state_int  <- sum(is.na(panel_with_floor_df$state_general_floor_num))

  if (n_unmatched_state_int > 0L) {
    message(
      "20d_merge-cps-binding.R -- year ", yr, ": ", n_unmatched_state_int,
      " row(s) failed to match the state binding panel. Investigate ",
      "STATEFIP values that do not appear in the binding panel ",
      "(territories like Puerto Rico are not in VZ; STATEFIP = 99 ",
      "indicates household not in any state)."
    )
  }

  # 3.3) Attach locality_id_chr via concordances ------------------------------
  # Compute the 3-digit county code from the IPUMS 5-digit COUNTY value
  # (state_fips * 1000 + county_fips_3) and a yearmonth_int (YYYYMM)
  # from CPS YEAR + MONTH for the era-window check. Then iterate the
  # city-level concordance for an era-aware match (city takes priority);
  # fall back to county-level concordance if no city match is found.
  # Localities not in either concordance keep locality_id_chr = NA and
  # the binding floor falls back to state-level only (documented
  # limitation: smaller California Bay Area cities, Iowa counties only
  # in extension YAML, etc.).
  panel_geo_df <- panel_with_floor_df |>
    dplyr::mutate(
      COUNTY              = as.integer(COUNTY),
      METFIPS             = as.integer(METFIPS),
      INDIVIDCC           = as.integer(INDIVIDCC),
      county_fips_3_int   = dplyr::if_else(
        !is.na(COUNTY) & COUNTY > 0L, as.integer(COUNTY %% 1000L), NA_integer_
      ),
      yearmonth_int       = YEAR * 100L + MONTH
    )

  # City-level match: scan the individcc concordance one row at a time
  # and assign locality_city_id_chr to panel rows that match all of
  # STATEFIP, METFIPS, INDIVIDCC, era window (yearmonth_int between
  # era_start_yearmonth_int and era_end_yearmonth_int), and (where
  # required) the 5-digit COUNTY. Inline loop avoids a complex
  # multi-key join with NA-tolerant county filtering and a non-equi
  # era window. The full scan runs in O(n_panel x nrow(individcc_
  # concordance_df)), which completes in well under a second per year
  # partition for the current concordance size; runtime hint is
  # computed at runtime rather than commented as a fixed count
  #.
  panel_geo_df$locality_city_id_chr <- NA_character_

  if (nrow(individcc_concordance_df) > 0L) {
    for (cc_idx_int in seq_len(nrow(individcc_concordance_df))) {
      cc_row_ls <- individcc_concordance_df[cc_idx_int, ]

      candidate_match_bool <-
        panel_geo_df$STATEFIP        == cc_row_ls$STATEFIP   &
        panel_geo_df$METFIPS         == cc_row_ls$METFIPS    &
        panel_geo_df$INDIVIDCC       == cc_row_ls$INDIVIDCC  &
        panel_geo_df$yearmonth_int  >= cc_row_ls$era_start_yearmonth_int &
        panel_geo_df$yearmonth_int  <= cc_row_ls$era_end_yearmonth_int   &
        is.na(panel_geo_df$locality_city_id_chr)

      if (!is.na(cc_row_ls$county_5digit_int)) {
        candidate_match_bool <- candidate_match_bool &
          panel_geo_df$COUNTY == cc_row_ls$county_5digit_int
      }

      candidate_match_bool[is.na(candidate_match_bool)] <- FALSE

      if (any(candidate_match_bool)) {
        panel_geo_df$locality_city_id_chr[candidate_match_bool] <-
          cc_row_ls$locality_city_id_chr
      }
    }
  }

  # County-level match: simple two-key join. Coalesce city slug over
  # county slug (city is more specific).
  panel_geo_df <- panel_geo_df |>
    dplyr::left_join(
      county_concordance_df,
      by = c("STATEFIP", "county_fips_3_int")
    ) |>
    dplyr::mutate(
      locality_id_chr = dplyr::coalesce(locality_city_id_chr, locality_county_id_chr)
    )

  # 3.4) Merge substate binding floor -----------------------------------------
  # Joined on locality_id_chr (the stable slug from 20c) plus
  # (STATEFIP, YEAR, MONTH). Replaces the prior locality_chr free-text
  # join, which silently failed for the New York tri-county pair
  # because VZ used "Long Island & Westchester" while the YAML
  # extension used "Nassau, Suffolk, and Westchester Counties"
  #.

  panel_with_substate_df <- panel_geo_df |>
    dplyr::left_join(
      substate_binding_df,
      by = c("STATEFIP", "locality_id_chr", "YEAR", "MONTH")
    )

  n_with_locality_int <- sum(!is.na(panel_with_substate_df$locality_id_chr))
  n_with_locality_floor_int <- sum(
    !is.na(panel_with_substate_df$locality_general_floor_num)
  )

  # 3.5) Compute effective floors and indicators ------------------------------
  # effective_general_floor = max(state_general, locality_general)
  # effective_tipped_floor  = max(state_tipped,  locality_tipped)
  # applicable_floor        = effective_tipped if tipped occupation, else effective_general
  # When locality floor is NA (worker not in a covered locality), the
  # effective floor reduces to the state-level floor.
  #
  # Bias note: pmax(state, locality) does
  # NOT weight for partial county coverage. Several concordance
  # entries (LA County, Cook County, King County) cover ordinances
  # that legally apply only to UNINCORPORATED county workers. Because
  # CPS only resolves to the 3-digit county, these workers cannot be
  # separated from incorporated-city residents in the same county;
  # the rule over-attributes binding events to the incorporated-city
  # subset and slightly over-states the binding share for those
  # counties. Direction of bias: upward. A coverage-weighted floor
  # would require Census place-level population data and a
  # county-place crosswalk; deferred per remediation 2026-05-05.

  panel_indicator_df <- panel_with_substate_df |>
    dplyr::mutate(
      effective_general_floor_num = pmax(
        state_general_floor_num,
        dplyr::coalesce(locality_general_floor_num, -Inf),
        na.rm = TRUE
      ),
      effective_tipped_floor_num = pmax(
        state_tipped_floor_num,
        dplyr::coalesce(locality_tipped_floor_num, -Inf),
        na.rm = TRUE
      ),
      is_tipped_occupation_flag = as.integer(OCC2010) %in% tipped_occ_codes_int,
      applicable_floor_num      = dplyr::if_else(
        is_tipped_occupation_flag,
        effective_tipped_floor_num,
        effective_general_floor_num
      ),
      at_or_below_general_flag    = !is.na(effective_general_floor_num) &
        nominal_hourly_wage_num <= effective_general_floor_num,
      at_or_below_tipped_flag     = !is.na(effective_tipped_floor_num) &
        nominal_hourly_wage_num <= effective_tipped_floor_num,
      at_or_below_applicable_flag = !is.na(applicable_floor_num) &
        nominal_hourly_wage_num <= applicable_floor_num
    )

  # Replace -Inf produced by pmax(-Inf, NA, na.rm=TRUE) with NA. This
  # happens when a state has no state binding floor and no locality.
  panel_indicator_df <- panel_indicator_df |>
    dplyr::mutate(
      effective_general_floor_num = dplyr::if_else(
        is.finite(effective_general_floor_num),
        effective_general_floor_num, NA_real_
      ),
      effective_tipped_floor_num = dplyr::if_else(
        is.finite(effective_tipped_floor_num),
        effective_tipped_floor_num, NA_real_
      )
    )

  n_at_or_below_int <- sum(
    panel_indicator_df$at_or_below_applicable_flag, na.rm = TRUE
  )

  # 3.4) Write output partition -----------------------------------------------

  out_partition_dir_chr <- fs::path(panel_out_dir_chr, paste0("year=", yr))
  fs::dir_create(out_partition_dir_chr, recurse = TRUE)

  arrow::write_parquet(
    x           = panel_indicator_df,
    sink        = fs::path(out_partition_dir_chr, "part-0.parquet"),
    compression = "snappy"
  )
  saveRDS(
    panel_indicator_df,
    file     = fs::path(out_partition_dir_chr, "part-0.rds"),
    compress = "xz"
  )

  # Per-year summary ----------------------------------------------------------

  run_summary_df <- dplyr::bind_rows(
    run_summary_df,
    tibble::tibble(
      year_int                  = as.integer(yr),
      n_input_rows_int          = as.integer(n_input_rows_int),
      n_hourly_paid_int         = as.integer(n_hourly_paid_int),
      n_after_state_join_int    = as.integer(n_after_state_join_int),
      n_unmatched_state_int     = as.integer(n_unmatched_state_int),
      n_with_locality_int       = as.integer(n_with_locality_int),
      n_with_locality_floor_int = as.integer(n_with_locality_floor_int),
      n_at_or_below_int         = as.integer(n_at_or_below_int)
    )
  )

  message(
    "20d_merge-cps-binding.R -- year ", yr, ": ",
    format(n_input_rows_int, big.mark = ","), " input -> ",
    format(n_hourly_paid_int, big.mark = ","), " hourly-paid -> ",
    format(n_at_or_below_int, big.mark = ","),
    " at or below binding (",
    format(round(100 * n_at_or_below_int / max(n_hourly_paid_int, 1L), 2L), nsmall = 2L),
    "%)."
  )
}

###################################
###   4) Diagnostics summary    ###
###################################

run_summary_path_chr <- fs::path(panel_out_dir_chr, "_run_summary.csv")
utils::write.csv(run_summary_df, run_summary_path_chr, row.names = FALSE)

total_hourly_paid_int <- sum(run_summary_df$n_hourly_paid_int)
total_at_or_below_int <- sum(run_summary_df$n_at_or_below_int)

message(
  "20d_merge-cps-binding.R -- summary: ",
  format(total_hourly_paid_int, big.mark = ","),
  " hourly-paid worker observations across ",
  nrow(run_summary_df), " year partitions; ",
  format(total_at_or_below_int, big.mark = ","), " (",
  format(round(100 * total_at_or_below_int / max(total_hourly_paid_int, 1L), 2L), nsmall = 2L),
  "%) at or below the applicable binding floor."
)

message(
  "20d_merge-cps-binding.R -- done. Output partitions in ",
  panel_out_dir_chr, ". Sub-state binding (county/city ordinances) ",
  "is now merged via county_to_locality.csv and individcc_to_locality.csv ",
  "concordances. Localities not represented in those concordances ",
  "(smaller California Bay Area cities, Iowa counties only in extension) ",
  "fall back to state-level binding."
)
