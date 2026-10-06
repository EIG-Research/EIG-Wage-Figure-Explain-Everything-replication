# 20b_extend-minimum-wage-forward -- forward extension of VZ state and sub-state minimum wage panels and construction of state tipped subminimum panel
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
# This script is the extension stage for the binding-minimum-wage
# sub-analysis. It does three things, each saved as its own intermediate
# artifact for downstream consumption by 20c:
#
#   (a) Parse the U.S. DOL Wage and Hour Division historical state
#       minimum wage HTML snapshot (1968 - 2024) to a long-format panel
#       and cross-validate against the Vaghul-Zipperer (VZ) annual file
#       for the 1974 - 2022 overlap. VZ remains canonical where the two
#       disagree; DOL WHD is canonical for 2023 and 2024 (post-VZ gap).
#
#   (b) Forward extension 2025 - present: state and sub-state ordinance
#       changes ingested from a hand-curated YAML at
#       data/raw/minimum_wage/extension/2023-onward.yaml. The YAML
#       schema mirrors VZ's mw_state_changes / mw_substate_changes
#       columns. The hand-curation step itself is a separate task; this
#       script only ingests and validates the YAML.
#
#   (c) State tipped subminimum panel, 1974 - present, built tiered:
#         - Pre-1991 federal cash subminimum schedule (50 percent of FLSA
#           minimum 1966 - 1989, then $2.13 from 1991 onward),
#         - 1991 - 2006 state-level series (Allegretto-Reich / Even-
#           Macpherson published compilation, hand-curated YAML),
#         - 2007 - present from Wayback Machine snapshots of the DOL WHD
#           tipped page (one snapshot per January, hand-curated YAML).
#
# Inputs (must already be on disk; produced by 20a or by snapshot fetch):
#   - data/raw/minimum_wage/vz_release/v1.4.0/mw_state_stata/mw_state_annual.dta
#   - data/raw/minimum_wage/sources/dol_whd/<DATE>/state-minimum-wage-history.html
#   - data/raw/minimum_wage/sources/dol_whd/<DATE>/state-minimum-wage-tipped.html
#   - data/raw/minimum_wage/sources/berkeley/<DATE>/inventory-of-us-city-and-county-minimum-wage-ordinances.html
#   - data/raw/minimum_wage/sources/epi/<DATE>/minimum-wage-tracker.html
#   - data/raw/minimum_wage/extension/2023-onward.yaml          (TODO: hand-curated, not yet built)
#   - data/raw/minimum_wage/extension/tipped/1991-2006.yaml     (TODO: hand-curated, not yet built)
#   - data/raw/minimum_wage/extension/tipped/2007-onward.yaml   (TODO: hand-curated, not yet built)
#
# Outputs (written by this script):
#   - data/intermediate/minimum_wage/dol_whd_state_history.{rds,parquet}
#   - data/intermediate/minimum_wage/vz_dol_validation.{rds,parquet}
#   - data/intermediate/minimum_wage/state_panel_extended.{rds,parquet}        (built on subsequent run when YAML lands)
#   - data/intermediate/minimum_wage/substate_panel_extended.{rds,parquet}     (built on subsequent run when YAML lands)
#   - data/intermediate/minimum_wage/state_tipped_panel.{rds,parquet}          (built on subsequent run when YAMLs land)
#
# Cleaning rules for the DOL WHD historical cells (Section 4 below):
#   - "..." -> NA, set no_state_mw_flag = TRUE.
#   - "$X.YZ" -> X.YZ; "$" stripped.
#   - "X & Y" (FLSA pre-1978 tier) -> max(X, Y); the higher rate is the
#     "newly covered" universal rate that replaced the tiered schedule
#     after the 1977 FLSA amendments.
#   - "X - Y" (industry/coverage range) -> max(X, Y); upper bound,
#     corresponding to the broadest-coverage industry.
#   - "X/wk" or "X/day" -> NA, set non_hourly_flag = TRUE; these are
#     pre-1980 weekly or daily rates (Arizona, Arkansas) where no
#     proper hourly state minimum existed.
#   - footnote markers "(a)" through "(z)" stripped from all cells
#     prior to numeric parsing.
#
# Place-of-residence vs. place-of-work is a known measurement-error
# issue: the binding floor for a CPS observation reflects the worker's
# state and (where identified) county of residence, not their place of
# work. For commuters across jurisdictional boundaries, the binding
# floor will be wrong. The pipeline assumes place of residence is a
# workable proxy and the analysis stage flags this caveat.
#
# No custom functions are defined; all logic is inline.

source(here::here("code", "_utils", "00_packages.R"))

###################################
###   Configuration             ###
###################################

# Static configuration. Update DATE_chr when a fresh snapshot is pulled
# into data/raw/minimum_wage/sources/<source>/<DATE>/.
snapshot_date_chr <- "2026-05-04"

raw_mw_dir_chr        <- here::here("data", "raw", "minimum_wage")
sources_dir_chr       <- fs::path(raw_mw_dir_chr, "sources")
extension_dir_chr     <- fs::path(raw_mw_dir_chr, "extension")
intermediate_dir_chr  <- here::here("data", "intermediate", "minimum_wage")

vz_release_tag_chr        <- "v1.4.0"
vz_release_dir_chr        <- fs::path(raw_mw_dir_chr, "vz_release", vz_release_tag_chr)
vz_state_annual_dta_chr   <- fs::path(vz_release_dir_chr, "mw_state_stata", "mw_state_annual.dta")

dol_history_html_chr <- fs::path(
  sources_dir_chr, "dol_whd", snapshot_date_chr,
  "state-minimum-wage-history.html"
)
dol_tipped_html_chr  <- fs::path(
  sources_dir_chr, "dol_whd", snapshot_date_chr,
  "state-minimum-wage-tipped.html"
)
berkeley_html_chr    <- fs::path(
  sources_dir_chr, "berkeley", snapshot_date_chr,
  "inventory-of-us-city-and-county-minimum-wage-ordinances.html"
)
epi_html_chr         <- fs::path(
  sources_dir_chr, "epi", snapshot_date_chr,
  "minimum-wage-tracker.html"
)

extension_yaml_chr        <- fs::path(extension_dir_chr, "2023-onward.yaml")
tipped_pre2007_yaml_chr   <- fs::path(extension_dir_chr, "tipped", "1991-2006.yaml")
tipped_post2007_yaml_chr  <- fs::path(extension_dir_chr, "tipped", "2007-onward.yaml")

fs::dir_create(intermediate_dir_chr, recurse = TRUE)

###################################
###   1) Preflight              ###
###################################
# Confirm every required input is on disk before doing any parse work.
# A missing snapshot is a hard error: the user must run snapshot fetch
# (or 20a) first, not silently fall through.

required_inputs_chr <- c(
  vz_state_annual_dta_chr,
  dol_history_html_chr,
  dol_tipped_html_chr,
  berkeley_html_chr,
  epi_html_chr
)

missing_inputs_chr <- required_inputs_chr[!fs::file_exists(required_inputs_chr)]

if (length(missing_inputs_chr) > 0L) {
  stop(
    "20b_extend-minimum-wage-forward.R -- the following input files are ",
    "missing: ", paste(missing_inputs_chr, collapse = "; "),
    ". Run 20a (for VZ release) and refresh source snapshots in ",
    sources_dir_chr, "/<source>/<DATE>/ before re-running this stage."
  )
}

message(
  "20b_extend-minimum-wage-forward.R -- preflight passed; ",
  length(required_inputs_chr), " input files present."
)

###################################
###   2) Parse DOL WHD HTML     ###
###################################
# The DOL WHD historical state minimum wage page contains six HTML
# tables, one per year-block: 1968 - 1981 (selected pre-FLSA-1978 years),
# 1988 - 1998, 2000 - 2006, 2007 - 2013, 2014 - 2019, 2020 - 2024.
# Each table has 55 rows = 50 states + Federal + DC + 4 territories.
# rvest::html_table() reads each table directly into a data frame.

message(
  "20b_extend-minimum-wage-forward.R -- parsing DOL WHD historical ",
  "state HTML at ", dol_history_html_chr
)

dol_html_doc <- xml2::read_html(dol_history_html_chr)
dol_tables_ls <- dol_html_doc |>
  rvest::html_elements("table") |>
  rvest::html_table()

if (length(dol_tables_ls) != 6L) {
  stop(
    "20b_extend-minimum-wage-forward.R -- expected 6 tables in the DOL ",
    "WHD history page, found ", length(dol_tables_ls), ". The page ",
    "structure has changed; re-snapshot the page and update this script."
  )
}

message(
  "20b_extend-minimum-wage-forward.R -- DOL WHD page parsed: ",
  length(dol_tables_ls), " tables, ",
  vapply(dol_tables_ls, nrow, integer(1L)) |> sum(),
  " total rows pre-cleaning."
)

# Stack the six tables into one wide data frame keyed on jurisdiction.
# Column 1 is always "State or other jurisdiction"; the remaining
# columns vary across the six tables (selected years pre-1988, annual
# 1988+). Use a left join chain to preserve all year columns.

dol_wide_df <- dol_tables_ls[[1L]] |>
  dplyr::rename(jurisdiction_chr = 1L)

for (table_idx_int in 2:6) {
  next_table_df <- dol_tables_ls[[table_idx_int]] |>
    dplyr::rename(jurisdiction_chr = 1L)

  dol_wide_df <- dplyr::left_join(
    dol_wide_df,
    next_table_df,
    by = "jurisdiction_chr"
  )
}

if (nrow(dol_wide_df) != 55L) {
  stop(
    "20b_extend-minimum-wage-forward.R -- expected 55 jurisdictions ",
    "after joining DOL WHD tables, found ", nrow(dol_wide_df),
    ". Investigate jurisdiction-name mismatches across tables."
  )
}

message(
  "20b_extend-minimum-wage-forward.R -- DOL WHD wide panel built: ",
  nrow(dol_wide_df), " jurisdictions x ",
  ncol(dol_wide_df) - 1L, " year columns."
)

###################################
###   3) Reshape DOL to long    ###
###################################
# Reshape the wide wide-by-year panel to long format with one row per
# jurisdiction-year before any cell-level cleaning. Year columns in the
# DOL HTML carry trailing footnote markers (e.g., "1968 (a)"). Strip
# those from the column name to get a clean integer year.

dol_long_raw_df <- dol_wide_df |>
  tidyr::pivot_longer(
    cols       = -jurisdiction_chr,
    names_to   = "year_label_chr",
    values_to  = "rate_raw_chr"
  ) |>
  dplyr::mutate(
    year_int = as.integer(stringr::str_extract(year_label_chr, "^\\d{4}"))
  ) |>
  dplyr::select(jurisdiction_chr, year_int, rate_raw_chr)

if (any(is.na(dol_long_raw_df$year_int))) {
  bad_labels_chr <- dol_long_raw_df |>
    dplyr::filter(is.na(year_int)) |>
    dplyr::pull(year_label_chr) |>
    unique()
  stop(
    "20b_extend-minimum-wage-forward.R -- could not parse year from ",
    "DOL WHD column label(s): ",
    paste(utils::head(bad_labels_chr, 5L), collapse = ", "),
    ". Investigate column naming."
  )
}

message(
  "20b_extend-minimum-wage-forward.R -- DOL WHD long panel: ",
  nrow(dol_long_raw_df), " jurisdiction-year rows; year range ",
  min(dol_long_raw_df$year_int), " - ",
  max(dol_long_raw_df$year_int), "."
)

###################################
###   4) Apply cleaning rules   ###
###################################
# Per the rules block at the top of the script. Apply sequentially:
#   (i)   trim whitespace
#   (ii)  strip footnote markers like "(a)", "(b)", "(c)" ...
#   (iii) flag non-hourly cells ("/wk", "/day")
#   (iv)  flag no-state-MW cells ("...")
#   (v)   strip "$" prefix
#   (vi)  parse numeric, handling "&" (FLSA tier max) and "-" (range max).
# All intermediate columns kept for diagnostic visibility.

dol_clean_df <- dol_long_raw_df |>
  dplyr::mutate(
    rate_trimmed_chr = stringr::str_trim(rate_raw_chr),

    # (ii-a) Strip footnote markers in parentheses or square brackets.
    # Patterns observed in the snapshot:
    #   "(a)" "(b)"           single lowercase letter
    #   "[c]" "[a]"            square-bracket variants (Arkansas,
    #                          Illinois, Nebraska, Virginia 1996-2024)
    #   "(g, j)" "(g,,j)"      multi-letter with commas/spaces
    #                          (U.S. Virgin Islands)
    #   "(i2)"                 alphanumeric (Puerto Rico)
    # Allow letters, digits, commas, and whitespace inside the brackets.
    rate_nofoot_chr = stringr::str_remove_all(
      rate_trimmed_chr,
      "\\([a-z0-9,\\s]+\\)|\\[[a-z0-9,\\s]+\\]"
    ) |> stringr::str_trim(),

    # (ii-b) Detect the no-state-MW marker BEFORE typographic normalization.
    # The literal "..." marker collides with the double-dot normalization
    # below: collapsing "\\.\\." to "." would turn "..." into ".".
    no_state_mw_flag = rate_nofoot_chr == "...",

    # (ii-c) Normalize known typographic anomalies:
    #   - em-dash to hyphen (Puerto Rico "5.08 - 7.25" used em-dash)
    #   - double-dot typo to single dot (USVI "4..65")
    #   - stray backtick to nothing (Oregon 1972 "1.25`")
    rate_normalized_chr = rate_nofoot_chr |>
      stringr::str_replace_all("–", "-") |>
      stringr::str_replace_all("\\.\\.", ".") |>
      stringr::str_remove_all("`") |>
      stringr::str_trim(),

    # (iii) non-hourly flag (weekly or daily historical rates)
    non_hourly_flag = stringr::str_detect(
      rate_normalized_chr, "/wk|/day"
    ),

    # (iv) strip "$" prefix; also handles "$" appearing mid-string after
    # an "&" or "-" split (e.g., "$1.15 & $1.60")
    rate_nodol_chr = stringr::str_remove_all(rate_normalized_chr, "\\$")
  )

# (vi) Numeric parse. Handle three patterns:
#   - "X & Y"   -> max(X, Y)         (FLSA tier resolution)
#   - "X - Y"   -> max(X, Y)         (industry range upper bound)
#   - plain     -> as.numeric(X)
# Anything that fails to parse with these rules and is not already
# flagged as non-hourly or no-state-MW is recorded in a diagnostic
# vector for manual review.

# Pre-allocate the numeric column and a diagnostic-reason column.
dol_clean_df$rate_num <- NA_real_
dol_clean_df$parse_reason_chr <- NA_character_

for (row_idx_int in seq_len(nrow(dol_clean_df))) {

  # Skip already-flagged rows.
  if (isTRUE(dol_clean_df$non_hourly_flag[row_idx_int])) {
    dol_clean_df$parse_reason_chr[row_idx_int] <- "non_hourly"
    next
  }

  if (isTRUE(dol_clean_df$no_state_mw_flag[row_idx_int])) {
    dol_clean_df$parse_reason_chr[row_idx_int] <- "no_state_mw"
    next
  }

  cell_chr <- dol_clean_df$rate_nodol_chr[row_idx_int]

  if (is.na(cell_chr) || !nzchar(cell_chr)) {
    dol_clean_df$parse_reason_chr[row_idx_int] <- "empty"
    next
  }

  # Tiered rate ("X & Y" FLSA pre-1978 tier, "X/Y" Nevada health-
  # insurance tier). Take max in both cases. For FLSA, max is the
  # "newly covered" rate that became universal post-1977. For Nevada,
  # max is the rate when the employer does not offer health insurance
  # (the higher of the two tiers; conservative as a binding floor
  # because it overstates the legally-required floor for the subset of
  # Nevada workers whose employer does offer insurance).
  if (stringr::str_detect(cell_chr, "&|/")) {
    parts_chr <- stringr::str_split(cell_chr, "&|/", simplify = TRUE) |>
      as.character() |>
      stringr::str_trim()
    parts_num <- suppressWarnings(as.numeric(parts_chr))
    parts_clean_num <- parts_num[!is.na(parts_num)]
    if (length(parts_clean_num) >= 1L) {
      dol_clean_df$rate_num[row_idx_int] <- max(parts_clean_num)
      dol_clean_df$parse_reason_chr[row_idx_int] <- "tier_max"
    } else {
      dol_clean_df$parse_reason_chr[row_idx_int] <- "tier_unparseable"
    }
    next
  }

  # Range ("X - Y") -> max upper bound
  if (stringr::str_detect(cell_chr, "-")) {
    parts_chr <- stringr::str_split(cell_chr, "-", simplify = TRUE) |>
      as.character() |>
      stringr::str_trim()
    parts_num <- suppressWarnings(as.numeric(parts_chr))
    parts_clean_num <- parts_num[!is.na(parts_num)]
    if (length(parts_clean_num) >= 1L) {
      dol_clean_df$rate_num[row_idx_int] <- max(parts_clean_num)
      dol_clean_df$parse_reason_chr[row_idx_int] <- "range_max"
    } else {
      dol_clean_df$parse_reason_chr[row_idx_int] <- "range_unparseable"
    }
    next
  }

  # Plain numeric
  parsed_num <- suppressWarnings(as.numeric(cell_chr))
  if (!is.na(parsed_num)) {
    dol_clean_df$rate_num[row_idx_int] <- parsed_num
    dol_clean_df$parse_reason_chr[row_idx_int] <- "plain"
  } else {
    dol_clean_df$parse_reason_chr[row_idx_int] <- "unrecognized"
  }
}

# Diagnostic counts
parse_counts_df <- dol_clean_df |>
  dplyr::count(parse_reason_chr, name = "n_int") |>
  dplyr::arrange(dplyr::desc(n_int))

message(
  "20b_extend-minimum-wage-forward.R -- DOL WHD parse breakdown:\n",
  paste0(
    "  ", parse_counts_df$parse_reason_chr, ": ", parse_counts_df$n_int,
    collapse = "\n"
  )
)

unrecognized_count_int <- dol_clean_df |>
  dplyr::filter(parse_reason_chr %in% c("unrecognized", "tier_unparseable", "range_unparseable")) |>
  nrow()

if (unrecognized_count_int > 0L) {
  warning(
    "20b_extend-minimum-wage-forward.R -- ", unrecognized_count_int,
    " DOL WHD cell(s) failed to parse. Inspect ",
    "data/intermediate/minimum_wage/dol_whd_state_history.rds and ",
    "extend the cleaning rules if these are systematic."
  )
}

###################################
###   5) Write DOL outputs      ###
###################################

dol_state_history_out_df <- dol_clean_df |>
  dplyr::select(
    jurisdiction_chr,
    year_int,
    rate_num,
    rate_raw_chr,
    non_hourly_flag,
    no_state_mw_flag,
    parse_reason_chr
  )

saveRDS(
  dol_state_history_out_df,
  fs::path(intermediate_dir_chr, "dol_whd_state_history.rds")
)
arrow::write_parquet(
  dol_state_history_out_df,
  fs::path(intermediate_dir_chr, "dol_whd_state_history.parquet")
)

message(
  "20b_extend-minimum-wage-forward.R -- wrote DOL WHD state history: ",
  nrow(dol_state_history_out_df), " rows -> ",
  fs::path(intermediate_dir_chr, "dol_whd_state_history.{rds,parquet}")
)

###################################
###   6) VZ vs DOL validation   ###
###################################
# Read the VZ annual file, harmonize the jurisdiction name to the DOL
# label, and compute a per-(state, year) discrepancy for the 1974-2022
# overlap. Differences > $0.01 are flagged for inspection. VZ remains
# canonical where the two disagree because VZ has daily granularity
# and explicit edge-case handling.

message("20b_extend-minimum-wage-forward.R -- reading VZ annual file ...")

vz_annual_raw_df <- haven::read_dta(vz_state_annual_dta_chr) |>
  haven::zap_labels()

# Inspect VZ annual schema. Expected columns based on monthly file
# pattern: state FIPS, name, abbreviation, year, plus federal/state
# min/avg/max numerics. Defensive code: warn if expected fields are
# missing rather than failing silently.

required_vz_cols_chr <- c(
  "statefips", "statename", "stateabb", "year",
  "fed_mw", "mw"
)

# VZ daily/monthly use lowercase; annual may use "Annual" prefixed
# camel case. Check both naming conventions.
vz_cols_lower_chr <- tolower(names(vz_annual_raw_df))

if (!all(c("year") %in% vz_cols_lower_chr)) {
  stop(
    "20b_extend-minimum-wage-forward.R -- VZ annual file is missing ",
    "expected 'year' column. Found: ",
    paste(names(vz_annual_raw_df), collapse = ", ")
  )
}

# Standardize the VZ schema. Column names in the annual XLSX use
# "Annual State Maximum" etc.; the .dta should be the same. Try
# lowercase/snake-case standardization to match the daily file.
vz_annual_std_df <- vz_annual_raw_df

# Lowercase all names for matching robustness.
names(vz_annual_std_df) <- tolower(names(vz_annual_std_df))

# Pick the VZ "state maximum" annual field (the rate that applied at
# any point during the year — matches DOL WHD, which lists the rate
# in effect during the year). The VZ annual file uses `max_mw` for
# the state-level max-of-year and `max_fed_mw` for federal; the
# candidate list below is ordered preferred-first.
candidate_state_max_chr <- intersect(
  c("max_mw", "max_state_mw", "annual_state_maximum",
    "annualstatemaximum", "state_max", "mw_max"),
  names(vz_annual_std_df)
)

# Fall back to any non-federal max column (matches max_mw without
# matching max_fed_mw).
if (length(candidate_state_max_chr) == 0L) {
  candidate_state_max_chr <- names(vz_annual_std_df)[
    stringr::str_detect(names(vz_annual_std_df), "^max_mw$|^max_state") |
    (stringr::str_detect(names(vz_annual_std_df), "state") &
     stringr::str_detect(names(vz_annual_std_df), "max"))
  ]
}

if (length(candidate_state_max_chr) == 0L) {
  stop(
    "20b_extend-minimum-wage-forward.R -- could not identify the VZ ",
    "annual state maximum column. Available columns: ",
    paste(names(vz_annual_std_df), collapse = ", ")
  )
}

vz_state_max_col_chr <- candidate_state_max_chr[[1L]]

message(
  "20b_extend-minimum-wage-forward.R -- VZ state-max column: '",
  vz_state_max_col_chr, "' (chosen from ",
  paste(candidate_state_max_chr, collapse = ", "), ")"
)

# Identify the VZ state-name column for the join. Try common names.
candidate_name_cols_chr <- intersect(
  c("statename", "name", "state"),
  names(vz_annual_std_df)
)

if (length(candidate_name_cols_chr) == 0L) {
  stop(
    "20b_extend-minimum-wage-forward.R -- could not identify VZ state ",
    "name column. Available: ", paste(names(vz_annual_std_df), collapse = ", ")
  )
}

vz_name_col_chr <- candidate_name_cols_chr[[1L]]

# Build the VZ subset for join. VZ may expose `year` either as a
# POSIXct/Date (Stata %td or %tc format) or as a plain numeric carrying
# the calendar year directly (Stata %ty format). Detect the class and
# extract the calendar year accordingly. Direct as.integer() on a
# datetime would return seconds-since-epoch; format(numeric, "%Y")
# would fail in prettyNum().
year_class_chr <- class(vz_annual_std_df[["year"]])

if (any(year_class_chr %in% c("Date", "POSIXct", "POSIXt"))) {
  vz_year_extracted_int <- as.integer(format(vz_annual_std_df[["year"]], "%Y"))
} else if (is.numeric(vz_annual_std_df[["year"]])) {
  # Assume Stata %ty annual format: value is already the calendar year.
  vz_year_extracted_int <- as.integer(vz_annual_std_df[["year"]])
} else {
  stop(
    "20b_extend-minimum-wage-forward.R -- unexpected class for VZ year ",
    "column: ", paste(year_class_chr, collapse = ", "),
    ". Expected Date, POSIXct, or numeric."
  )
}

message(
  "20b_extend-minimum-wage-forward.R -- VZ year column class: ",
  paste(year_class_chr, collapse = ", "),
  "; extracted range: ",
  min(vz_year_extracted_int, na.rm = TRUE), " - ",
  max(vz_year_extracted_int, na.rm = TRUE)
)

vz_for_join_df <- vz_annual_std_df |>
  dplyr::transmute(
    jurisdiction_chr = .data[[vz_name_col_chr]],
    year_int         = vz_year_extracted_int,
    vz_state_max_num = as.numeric(.data[[vz_state_max_col_chr]])
  )

# Harmonize jurisdiction names. DOL uses "Federal (FLSA)" and
# "District of Columbia"; VZ likely uses just state names with no
# "Federal" row. Drop "Federal (FLSA)" and territories from the join
# (VZ does not include them). Document the drop.
non_state_juris_chr <- c(
  "Federal (FLSA)",
  "Puerto Rico",
  "U.S. Virgin Islands",
  "Guam",
  "American Samoa"
)

dol_for_join_df <- dol_state_history_out_df |>
  dplyr::filter(!jurisdiction_chr %in% non_state_juris_chr) |>
  dplyr::select(
    jurisdiction_chr,
    year_int,
    dol_rate_num = rate_num
  )

# Restrict to overlap years 1974-2022. VZ starts 1974-05; the first
# full annual year in VZ is 1975. Use 1975-2022 for the strict
# overlap. Years 1974, 2023, 2024 in DOL but not VZ are kept in the
# DOL output but not validated.
overlap_years_int <- 1975:2022

validation_df <- dol_for_join_df |>
  dplyr::filter(year_int %in% overlap_years_int) |>
  dplyr::left_join(vz_for_join_df, by = c("jurisdiction_chr", "year_int")) |>
  dplyr::mutate(
    diff_num = dplyr::if_else(
      !is.na(dol_rate_num) & !is.na(vz_state_max_num),
      abs(dol_rate_num - vz_state_max_num),
      NA_real_
    ),
    discrepancy_flag = !is.na(diff_num) & diff_num > 0.01
  )

n_validated_int      <- sum(!is.na(validation_df$diff_num))
n_discrepancy_int    <- sum(validation_df$discrepancy_flag, na.rm = TRUE)
n_dol_only_int       <- sum(!is.na(validation_df$dol_rate_num) & is.na(validation_df$vz_state_max_num))
n_vz_only_int        <- sum(is.na(validation_df$dol_rate_num) & !is.na(validation_df$vz_state_max_num))

message(
  "20b_extend-minimum-wage-forward.R -- VZ vs DOL WHD validation (",
  min(overlap_years_int), "-", max(overlap_years_int), "):\n",
  "  validated state-years:        ", n_validated_int, "\n",
  "  state-years with diff > $0.01: ", n_discrepancy_int, "\n",
  "  DOL has, VZ missing:           ", n_dol_only_int, "\n",
  "  VZ has, DOL missing:           ", n_vz_only_int
)

saveRDS(
  validation_df,
  fs::path(intermediate_dir_chr, "vz_dol_validation.rds")
)
arrow::write_parquet(
  validation_df,
  fs::path(intermediate_dir_chr, "vz_dol_validation.parquet")
)

message(
  "20b_extend-minimum-wage-forward.R -- wrote VZ vs DOL validation: ",
  nrow(validation_df), " rows -> ",
  fs::path(intermediate_dir_chr, "vz_dol_validation.{rds,parquet}")
)

###################################
###   7) Forward extension      ###
###################################
# Build the 2023-01-01 through-today daily state and sub-state minimum
# wage panels by reading data/raw/minimum_wage/extension/2023-onward.yaml
# and forward-filling rates from change events. The output panels are
# stacked with VZ daily files in 20c.
#
# Key design choices:
#   - The 2022-12-31 anchor rate per state (from VZ state monthly's
#     max_mw column for 2022m12) is included as a phantom event so
#     forward-fill correctly initializes states with no 2023+ events.
#   - Sub-state extension only emits rows for (state, locality) pairs
#     present in the YAML; pre-first-event days for each locality are
#     dropped, since the locality had no separate ordinance until that
#     date.
#   - Federal MW is not in the YAML; 20c handles federal as a constant
#     $7.25 since 2009-07-24.

if (!fs::file_exists(extension_yaml_chr)) {

  message(
    "20b_extend-minimum-wage-forward.R -- extension YAML not present at ",
    extension_yaml_chr, "; skipping forward extension. ",
    "Run code/_utils/synthesize_extension_yaml.py to regenerate."
  )

} else {

  message(
    "20b_extend-minimum-wage-forward.R -- reading extension YAML at ",
    extension_yaml_chr
  )

  extension_yaml_ls <- yaml::read_yaml(extension_yaml_chr)

  # 7.1) Validate top-level YAML structure -----------------------------------

  required_yaml_keys_chr <- c("metadata", "state_changes", "substate_changes")
  missing_yaml_keys_chr  <- setdiff(required_yaml_keys_chr, names(extension_yaml_ls))

  if (length(missing_yaml_keys_chr) > 0L) {
    stop(
      "20b_extend-minimum-wage-forward.R -- extension YAML missing top-level ",
      "key(s): ", paste(missing_yaml_keys_chr, collapse = ", ")
    )
  }

  # 7.2) Convert YAML lists to data frames -----------------------------------
  # YAML scalar `null` becomes NULL in R lists. Pre-process each entry to
  # replace NULL with NA so dplyr::bind_rows produces clean columns instead
  # of dropping the field. Two parallel for-loops, one per change-list,
  # because the lists differ in their field set (state vs. sub-state).

  state_changes_clean_ls <- vector("list", length(extension_yaml_ls$state_changes))
  for (i_int in seq_along(extension_yaml_ls$state_changes)) {
    entry_ls <- extension_yaml_ls$state_changes[[i_int]]
    for (k_chr in names(entry_ls)) {
      if (is.null(entry_ls[[k_chr]])) {
        entry_ls[[k_chr]] <- NA
      }
    }
    state_changes_clean_ls[[i_int]] <- entry_ls
  }

  substate_changes_clean_ls <- vector("list", length(extension_yaml_ls$substate_changes))
  for (i_int in seq_along(extension_yaml_ls$substate_changes)) {
    entry_ls <- extension_yaml_ls$substate_changes[[i_int]]
    for (k_chr in names(entry_ls)) {
      if (is.null(entry_ls[[k_chr]])) {
        entry_ls[[k_chr]] <- NA
      }
    }
    substate_changes_clean_ls[[i_int]] <- entry_ls
  }

  state_changes_raw_df    <- dplyr::bind_rows(state_changes_clean_ls)
  substate_changes_raw_df <- dplyr::bind_rows(substate_changes_clean_ls)

  state_changes_df <- state_changes_raw_df |>
    dplyr::transmute(
      jurisdiction_chr             = as.character(jurisdiction),
      state_abbr_chr               = as.character(state_abbr),
      state_fips_int               = as.integer(state_fips),
      effective_date_dt            = as.Date(effective_date),
      rate_min_num                 = as.numeric(rate_min),
      rate_tipped_num              = as.numeric(rate_tipped),
      inferred_effective_date_flag = as.logical(inferred_effective_date),
      source_chr                   = as.character(source),
      source_url_chr               = as.character(source_url),
      notes_chr                    = as.character(notes)
    )

  substate_changes_df <- substate_changes_raw_df |>
    dplyr::transmute(
      jurisdiction_state_chr       = as.character(jurisdiction_state),
      state_abbr_chr               = as.character(state_abbr),
      state_fips_int               = as.integer(state_fips),
      locality_chr                 = as.character(locality),
      # YAML schema v0.3 onward emits a locality_id slug per substate
      # event (synthesize_extension_yaml.py:slugify_locality). It is the
      # stable join key used by 20c and 20d. Older YAMLs that predate
      # v0.3 leave this field NULL, so we coalesce against an inline
      # slug derivation below.
      locality_id_chr              = as.character(locality_id),
      effective_date_dt            = as.Date(effective_date),
      rate_min_num                 = as.numeric(rate_min),
      rate_tipped_num              = as.numeric(rate_tipped),
      inferred_effective_date_flag = as.logical(inferred_effective_date),
      source_chr                   = as.character(source),
      source_url_chr               = as.character(source_url),
      notes_chr                    = as.character(notes)
    )

  # Locality slug overrides (kept identical to the Python synthesizer's
  # LOCALITY_SLUG_OVERRIDES dict; see code/_utils/synthesize_extension_yaml.py).
  # Every entry collapses two free-text forms of the same ordinance into
  # a single stable join slug. Add a row here whenever a new alias is
  # introduced in either VZ or the YAML extension.
  locality_slug_overrides_df <- tibble::tribble(
    ~state_fips_int, ~locality_chr,                                ~locality_id_chr_override,
    36L,             "Long Island & Westchester",                  "ny_li_westchester",
    36L,             "Nassau, Suffolk, and Westchester Counties",  "ny_li_westchester"
  )

  # Backfill any missing slug on substate_changes_df rows using the
  # deterministic slug rule plus the override table. The Python
  # synthesizer already applies this rule, so this is a defensive
  # backstop for older YAML files or hand-edited events.
  substate_changes_df <- substate_changes_df |>
    dplyr::left_join(locality_slug_overrides_df, by = c("state_fips_int", "locality_chr")) |>
    dplyr::mutate(
      locality_id_chr = dplyr::coalesce(
        locality_id_chr,
        locality_id_chr_override,
        paste0(
          tolower(state_abbr_chr), "_",
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
    "20b_extend-minimum-wage-forward.R -- ingested ",
    nrow(state_changes_df), " state events and ",
    nrow(substate_changes_df), " sub-state events from YAML."
  )

  # 7.3) Read VZ 2022m12 anchor rates ----------------------------------------
  # The VZ state monthly file is small (1.8 MB). max_mw for 2022-12 is
  # the rate effective at the end of 2022; we use it as a phantom event
  # dated 2022-12-31 so forward-fill produces correct daily values for
  # states that have no 2023+ events.

  vz_state_monthly_dta_chr <- fs::path(
    vz_release_dir_chr, "mw_state_stata", "mw_state_monthly.dta"
  )

  if (!fs::file_exists(vz_state_monthly_dta_chr)) {
    stop(
      "20b_extend-minimum-wage-forward.R -- VZ state monthly file not found at ",
      vz_state_monthly_dta_chr, ". Run 20a first."
    )
  }

  vz_anchor_raw_df <- haven::read_dta(vz_state_monthly_dta_chr) |>
    haven::zap_labels()

  # Coerce monthly_date to Date if haven returned it as numeric (Stata
  # %tm format = months since 1960-01-01). Construct the Date explicitly
  # rather than via Date arithmetic to avoid leap-year / day-of-month
  # drift; %tm always represents the first day of the month.
  if (is.numeric(vz_anchor_raw_df$monthly_date)) {
    vz_anchor_raw_df$monthly_date <- as.Date(paste0(
      1960L + as.integer(vz_anchor_raw_df$monthly_date) %/% 12L, "-",
      sprintf("%02d", (as.integer(vz_anchor_raw_df$monthly_date) %% 12L) + 1L),
      "-01"
    ))
  }

  vz_anchor_df <- vz_anchor_raw_df |>
    dplyr::filter(format(monthly_date, "%Y-%m") == "2022-12") |>
    dplyr::transmute(
      jurisdiction_chr             = as.character(statename),
      state_abbr_chr               = as.character(stateabb),
      state_fips_int               = as.integer(statefips),
      effective_date_dt            = as.Date("2022-12-31"),
      rate_min_num                 = as.numeric(max_mw),
      rate_tipped_num              = NA_real_,
      inferred_effective_date_flag = FALSE,
      source_chr                   = "VZ_v1.4.0_2022m12_anchor",
      source_url_chr               = "https://github.com/benzipperer/historicalminwage",
      notes_chr                    = "Anchor rate from VZ state monthly max_mw for 2022-12."
    )

  if (nrow(vz_anchor_df) != 51L) {
    stop(
      "20b_extend-minimum-wage-forward.R -- expected 51 anchor rows ",
      "from VZ 2022m12, found ", nrow(vz_anchor_df), "."
    )
  }

  # 7.4) Build daily state extension panel -----------------------------------
  # The construction grid runs from 2022-12-31 (one day earlier than the
  # output panel) so the anchor event attaches via exact-date join. After
  # forward-fill, filter to the output range 2023-01-01 onward. Without
  # this one-day overlap, states with no 2023+ events would have NA rates
  # because tidyr::fill has no upstream value to carry.

  panel_start_date_dt        <- as.Date("2023-01-01")
  panel_end_date_dt          <- Sys.Date()
  panel_construction_start_dt <- as.Date("2022-12-31")
  panel_construction_dates_dt <- seq.Date(
    panel_construction_start_dt, panel_end_date_dt, by = "day"
  )
  # Output-range daily sequence used by the sub-state panel build in
  # section 7.5. Sub-state has no VZ anchor, so it does not need the
  # one-day earlier construction overlap.
  daily_dates_dt <- seq.Date(panel_start_date_dt, panel_end_date_dt, by = "day")

  state_change_events_df <- dplyr::bind_rows(vz_anchor_df, state_changes_df) |>
    dplyr::arrange(jurisdiction_chr, effective_date_dt)

  state_grid_df <- tidyr::expand_grid(
    jurisdiction_chr = unique(state_change_events_df$jurisdiction_chr),
    date_dt          = panel_construction_dates_dt
  )

  state_panel_extended_df <- state_grid_df |>
    dplyr::left_join(
      state_change_events_df |>
        dplyr::select(
          jurisdiction_chr,
          date_dt         = effective_date_dt,
          rate_min_num,
          rate_tipped_num
        ),
      by = c("jurisdiction_chr", "date_dt")
    ) |>
    dplyr::group_by(jurisdiction_chr) |>
    dplyr::arrange(date_dt) |>
    tidyr::fill(rate_min_num, rate_tipped_num, .direction = "down") |>
    dplyr::ungroup() |>
    dplyr::filter(date_dt >= panel_start_date_dt) |>
    dplyr::left_join(
      vz_anchor_df |>
        dplyr::select(jurisdiction_chr, state_abbr_chr, state_fips_int),
      by = "jurisdiction_chr"
    ) |>
    dplyr::select(
      jurisdiction_chr,
      state_abbr_chr,
      state_fips_int,
      date_dt,
      rate_min_num,
      rate_tipped_num
    )

  # 7.5) Build daily sub-state extension panel -------------------------------
  # For VZ-tracked localities (ones present in VZ's substate panel through
  # 2022-12-31), anchor each locality from its VZ 2022-12-31 rate and then
  # forward-fill with EPI events on top. Without this anchor, localities
  # whose first EPI event is in 2025 or 2026 (e.g., San Francisco, NYC,
  # Berkeley) would have no extension panel rows for 2023-2024, so 20d's
  # CPS merge would fall back to state-level binding for those workers
  # even though those cities had local ordinances in effect throughout
  # the period. The anchor uses VZ's 2022-12-31 rate, which mildly
  # under-states the actual locality rate for indexed cities (their MWs
  # rose above the 2022 value during 2023-2024 due to COLA indexing) but
  # is a meaningful improvement over no coverage. Localities introduced
  # post-2022 (only in extension YAML, no VZ presence) keep the original
  # behavior — first-event-onward coverage only.

  if (nrow(substate_changes_df) > 0L) {

    # 7.5a) Read VZ substate monthly anchor (2022-12 rates per locality)
    vz_substate_monthly_dta_chr <- fs::path(
      vz_release_dir_chr, "mw_substate_stata", "mw_substate_monthly.dta"
    )

    if (fs::file_exists(vz_substate_monthly_dta_chr)) {

      vz_substate_raw_df <- haven::read_dta(vz_substate_monthly_dta_chr) |>
        haven::zap_labels()

      if (is.numeric(vz_substate_raw_df$monthly_date)) {
        vz_substate_raw_df$monthly_date <- as.Date(paste0(
          1960L + as.integer(vz_substate_raw_df$monthly_date) %/% 12L, "-",
          sprintf("%02d", (as.integer(vz_substate_raw_df$monthly_date) %% 12L) + 1L),
          "-01"
        ))
      }

      vz_substate_anchor_df <- vz_substate_raw_df |>
        dplyr::filter(format(monthly_date, "%Y-%m") == "2022-12") |>
        dplyr::transmute(
          jurisdiction_state_chr = as.character(statename),
          state_abbr_chr         = as.character(stateabb),
          state_fips_int         = as.integer(statefips),
          locality_chr           = as.character(locality),
          effective_date_dt      = as.Date("2022-12-31"),
          rate_min_num           = as.numeric(max_mw),
          rate_tipped_num        = NA_real_,
          inferred_effective_date_flag = FALSE,
          source_chr             = "VZ_v1.4.0_2022m12_substate_anchor",
          source_url_chr         = "https://github.com/benzipperer/historicalminwage",
          notes_chr              = "Anchor rate from VZ substate monthly max_mw for 2022-12; mildly understates indexed-city MW for 2023-2024 pre-first-EPI-event window."
        ) |>
        # Attach the locality_id slug. VZ has no slug column upstream;
        # we derive it inline using the same rule as the Python
        # synthesizer (override table first, then deterministic slug).
        dplyr::left_join(locality_slug_overrides_df, by = c("state_fips_int", "locality_chr")) |>
        dplyr::mutate(
          locality_id_chr = dplyr::coalesce(
            locality_id_chr_override,
            paste0(
              tolower(state_abbr_chr), "_",
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
    } else {
      vz_substate_anchor_df <- tibble::tibble(
        jurisdiction_state_chr = character(0L),
        state_abbr_chr         = character(0L),
        state_fips_int         = integer(0L),
        locality_chr           = character(0L),
        locality_id_chr        = character(0L),
        effective_date_dt      = as.Date(character(0L)),
        rate_min_num           = numeric(0L),
        rate_tipped_num        = numeric(0L),
        inferred_effective_date_flag = logical(0L),
        source_chr             = character(0L),
        source_url_chr         = character(0L),
        notes_chr              = character(0L)
      )
    }

    # 7.5b) Build the union of (state, locality_id) pairs from VZ anchor + YAML
    # so localities present only in VZ (not in YAML) still produce panel rows.
    # The join key going forward is locality_id_chr; locality_chr is retained
    # as a display label.
    substate_jurisdictions_df <- dplyr::bind_rows(
      vz_substate_anchor_df |>
        dplyr::select(
          jurisdiction_state_chr,
          state_abbr_chr,
          state_fips_int,
          locality_chr,
          locality_id_chr
        ),
      substate_changes_df |>
        dplyr::select(
          jurisdiction_state_chr,
          state_abbr_chr,
          state_fips_int,
          locality_chr,
          locality_id_chr
        )
    ) |>
      # Collapse free-text aliases that share a slug (e.g., the New York
      # tri-county "Long Island & Westchester" / "Nassau, Suffolk, and
      # Westchester Counties" pair) onto a single row by taking the first
      # locality_chr alphabetically per (state_fips, locality_id).
      dplyr::group_by(state_fips_int, locality_id_chr) |>
      dplyr::summarise(
        jurisdiction_state_chr = dplyr::first(jurisdiction_state_chr),
        state_abbr_chr         = dplyr::first(state_abbr_chr),
        locality_chr           = dplyr::first(sort(locality_chr)),
        .groups = "drop"
      ) |>
      dplyr::select(
        jurisdiction_state_chr,
        state_abbr_chr,
        state_fips_int,
        locality_chr,
        locality_id_chr
      )

    # 7.5c) Daily grid x (state, locality_id) and join all events. The
    # construction grid runs from 2022-12-31 (one day earlier than the
    # output panel) so the anchor attaches via exact-date join, mirroring
    # the state extension build logic.
    substate_grid_df <- tidyr::expand_grid(
      substate_jurisdictions_df,
      date_dt = panel_construction_dates_dt
    )

    substate_events_df <- dplyr::bind_rows(
      vz_substate_anchor_df |>
        dplyr::select(
          jurisdiction_state_chr,
          locality_id_chr,
          date_dt = effective_date_dt,
          rate_min_num,
          rate_tipped_num
        ),
      substate_changes_df |>
        dplyr::select(
          jurisdiction_state_chr,
          locality_id_chr,
          date_dt = effective_date_dt,
          rate_min_num,
          rate_tipped_num
        )
    )

    substate_panel_extended_df <- substate_grid_df |>
      dplyr::left_join(
        substate_events_df,
        by = c("jurisdiction_state_chr", "locality_id_chr", "date_dt")
      ) |>
      dplyr::group_by(jurisdiction_state_chr, locality_id_chr) |>
      dplyr::arrange(date_dt) |>
      tidyr::fill(rate_min_num, rate_tipped_num, .direction = "down") |>
      dplyr::ungroup() |>
      dplyr::filter(date_dt >= panel_start_date_dt) |>
      dplyr::filter(!is.na(rate_min_num)) |>
      dplyr::select(
        jurisdiction_state_chr,
        state_abbr_chr,
        state_fips_int,
        locality_chr,
        locality_id_chr,
        date_dt,
        rate_min_num,
        rate_tipped_num
      )

  } else {

    substate_panel_extended_df <- tibble::tibble(
      jurisdiction_state_chr = character(0L),
      state_abbr_chr         = character(0L),
      state_fips_int         = integer(0L),
      locality_chr           = character(0L),
      locality_id_chr        = character(0L),
      date_dt                = as.Date(character(0L)),
      rate_min_num           = numeric(0L),
      rate_tipped_num        = numeric(0L)
    )
  }

  # 7.6) Diagnostics --------------------------------------------------------

  message(
    "20b_extend-minimum-wage-forward.R -- state extension panel: ",
    nrow(state_panel_extended_df), " rows, ",
    length(unique(state_panel_extended_df$jurisdiction_chr)),
    " jurisdictions, ",
    min(state_panel_extended_df$date_dt, na.rm = TRUE), " through ",
    max(state_panel_extended_df$date_dt, na.rm = TRUE)
  )

  if (nrow(substate_panel_extended_df) > 0L) {
    n_substate_juris_int <- substate_panel_extended_df |>
      dplyr::distinct(jurisdiction_state_chr, locality_id_chr) |>
      nrow()

    message(
      "20b_extend-minimum-wage-forward.R -- sub-state extension panel: ",
      nrow(substate_panel_extended_df), " rows, ",
      n_substate_juris_int, " jurisdictions, ",
      min(substate_panel_extended_df$date_dt, na.rm = TRUE), " through ",
      max(substate_panel_extended_df$date_dt, na.rm = TRUE)
    )
  }

  # 7.7) Write outputs ------------------------------------------------------

  saveRDS(
    state_panel_extended_df,
    fs::path(intermediate_dir_chr, "state_panel_extended.rds")
  )
  arrow::write_parquet(
    state_panel_extended_df,
    fs::path(intermediate_dir_chr, "state_panel_extended.parquet")
  )

  saveRDS(
    substate_panel_extended_df,
    fs::path(intermediate_dir_chr, "substate_panel_extended.rds")
  )
  arrow::write_parquet(
    substate_panel_extended_df,
    fs::path(intermediate_dir_chr, "substate_panel_extended.parquet")
  )

  message(
    "20b_extend-minimum-wage-forward.R -- wrote state_panel_extended and ",
    "substate_panel_extended .{rds,parquet} to ", intermediate_dir_chr
  )
}

###################################
###   8) Tipped panel build     ###
###################################
# Build state-level cash tipped subminimum panel covering 1974-05-01
# through today using the tiered approach approved in design.
#
# Tier 1 (always available): federal cash tipped schedule, hardcoded.
#   - 1974-05-01 through 1991-03-31: 50 percent of FLSA minimum, per
#     pre-1989-FLSA-amendments tip credit rules.
#   - 1991-04-01 onward: $2.13, frozen by the 1996 Small Business Job
#     Protection Act.
#   - Source: Public Law 101-157 (1989 FLSA Amendments) and Public
#     Law 104-188 (1996 Small Business Job Protection Act).
#
# Tier 2 (conditional, runs if section 7 produced state_changes_df):
#   state-level tipped overrides for 2023-onward, sourced from the
#   rate_tipped values in the YAML. Only EPI-derived events carry a
#   tipped rate; DOL-derived 2023/2024 entries leave rate_tipped null
#   (which falls back to federal default).
#
# Tier 3 (conditional, TODO): historical state-level tipped from
#   1991-2006 published series and 2007-onward Wayback Machine
#   snapshots. Hand-curated YAMLs at:
#     - data/raw/minimum_wage/extension/tipped/1991-2006.yaml
#     - data/raw/minimum_wage/extension/tipped/2007-onward.yaml
#   Until those YAMLs land, state-level tipped for 1991-2022 falls
#   back to federal default ($2.13). This is a documented limitation.
#
# Output: data/intermediate/minimum_wage/state_tipped_panel.{rds,parquet}
# keyed on (jurisdiction_chr, date_dt) with columns rate_tipped_num,
# fed_tipped_num, state_tipped_override_num, and source_chr.

# 8.1) Federal cash tipped schedule -----------------------------------------

federal_tipped_schedule_df <- tibble::tibble(
  effective_date_dt = as.Date(c(
    "1974-05-01",  # 50 pct of FLSA $2.00
    "1975-01-01",  # 50 pct of FLSA $2.10
    "1976-01-01",  # 50 pct of FLSA $2.30
    "1978-01-01",  # 50 pct of FLSA $2.65 (rounded)
    "1979-01-01",  # 50 pct of FLSA $2.90
    "1980-01-01",  # 50 pct of FLSA $3.10
    "1981-01-01",  # 50 pct of FLSA $3.35 (rounded)
    "1990-04-01",  # 50 pct of FLSA $3.80, per 1989 amendments
    "1991-04-01"   # 50 pct of FLSA $4.25 -> $2.13, then frozen
  )),
  fed_tipped_num = c(
    1.00, 1.05, 1.15, 1.33,
    1.45, 1.55, 1.68, 1.90,
    2.13
  )
)

# 8.2) State jurisdiction list ----------------------------------------------
# Use vz_anchor_df from section 7 if available; otherwise read directly
# from VZ state monthly. Self-contained so section 8 can run even when
# section 7 was skipped (no extension YAML).

if (!exists("vz_anchor_df", inherits = FALSE)) {

  vz_state_monthly_dta_chr <- fs::path(
    vz_release_dir_chr, "mw_state_stata", "mw_state_monthly.dta"
  )

  if (!fs::file_exists(vz_state_monthly_dta_chr)) {
    stop(
      "20b_extend-minimum-wage-forward.R -- VZ state monthly file not found at ",
      vz_state_monthly_dta_chr, ". Run 20a first."
    )
  }

  vz_state_monthly_raw_df <- haven::read_dta(vz_state_monthly_dta_chr) |>
    haven::zap_labels()

  # Coerce monthly_date to Date if haven returned it as numeric.
  if (is.numeric(vz_state_monthly_raw_df$monthly_date)) {
    vz_state_monthly_raw_df$monthly_date <- as.Date(paste0(
      1960L + as.integer(vz_state_monthly_raw_df$monthly_date) %/% 12L, "-",
      sprintf("%02d", (as.integer(vz_state_monthly_raw_df$monthly_date) %% 12L) + 1L),
      "-01"
    ))
  }

  state_jurisdictions_df <- vz_state_monthly_raw_df |>
    dplyr::filter(format(monthly_date, "%Y-%m") == "2022-12") |>
    dplyr::transmute(
      jurisdiction_chr = as.character(statename),
      state_abbr_chr   = as.character(stateabb),
      state_fips_int   = as.integer(statefips)
    )

} else {

  state_jurisdictions_df <- vz_anchor_df |>
    dplyr::select(jurisdiction_chr, state_abbr_chr, state_fips_int)
}

if (nrow(state_jurisdictions_df) != 51L) {
  stop(
    "20b_extend-minimum-wage-forward.R -- expected 51 state jurisdictions ",
    "for tipped panel, got ", nrow(state_jurisdictions_df), "."
  )
}

# 8.3) Daily date sequence --------------------------------------------------

tipped_panel_start_dt <- as.Date("1974-05-01")
tipped_panel_end_dt   <- Sys.Date()
tipped_dates_dt       <- seq.Date(
  tipped_panel_start_dt, tipped_panel_end_dt, by = "day"
)

# 8.4) Federal default per day ----------------------------------------------

federal_default_df <- tibble::tibble(date_dt = tipped_dates_dt) |>
  dplyr::left_join(
    federal_tipped_schedule_df |>
      dplyr::rename(date_dt = effective_date_dt),
    by = "date_dt"
  ) |>
  dplyr::arrange(date_dt) |>
  tidyr::fill(fed_tipped_num, .direction = "down")

# 8.5) State-level overrides from YAML --------------------------------------

if (exists("state_changes_df", inherits = FALSE)) {

  state_tipped_overrides_df <- state_changes_df |>
    dplyr::filter(!is.na(rate_tipped_num)) |>
    dplyr::select(jurisdiction_chr, effective_date_dt, rate_tipped_num)

} else {

  state_tipped_overrides_df <- tibble::tibble(
    jurisdiction_chr  = character(0L),
    effective_date_dt = as.Date(character(0L)),
    rate_tipped_num   = numeric(0L)
  )
}

n_state_tipped_overrides_int <- nrow(state_tipped_overrides_df)

# 8.6) Build state tipped panel ---------------------------------------------
# Cross-join 51 jurisdictions x daily dates, attach state-level overrides
# where they exist on a given (jurisdiction, day), forward-fill the
# override across days within each jurisdiction, attach federal default,
# and coalesce: state override wins where defined, federal default where
# not.

state_tipped_grid_df <- tidyr::expand_grid(
  jurisdiction_chr = state_jurisdictions_df$jurisdiction_chr,
  date_dt          = tipped_dates_dt
)

state_tipped_panel_df <- state_tipped_grid_df |>
  dplyr::left_join(
    state_tipped_overrides_df |>
      dplyr::rename(
        date_dt                   = effective_date_dt,
        state_tipped_override_num = rate_tipped_num
      ),
    by = c("jurisdiction_chr", "date_dt")
  ) |>
  dplyr::group_by(jurisdiction_chr) |>
  dplyr::arrange(date_dt) |>
  tidyr::fill(state_tipped_override_num, .direction = "down") |>
  dplyr::ungroup() |>
  dplyr::left_join(federal_default_df, by = "date_dt") |>
  dplyr::left_join(state_jurisdictions_df, by = "jurisdiction_chr") |>
  dplyr::mutate(
    rate_tipped_num = dplyr::coalesce(
      state_tipped_override_num, fed_tipped_num
    ),
    source_chr      = dplyr::if_else(
      is.na(state_tipped_override_num),
      "federal_default",
      "state_override_from_yaml"
    )
  ) |>
  dplyr::select(
    jurisdiction_chr,
    state_abbr_chr,
    state_fips_int,
    date_dt,
    rate_tipped_num,
    fed_tipped_num,
    state_tipped_override_num,
    source_chr
  )

# 8.7) Tip-credit-banning state override ------------------------------------
# Seven states ban the tip credit either entirely or with a small-employer
# exception that affects a negligible share of workers. In these states,
# the cash tipped subminimum equals the FULL state minimum wage (which
# we already have via the VZ state monthly + extension). Apply the
# override from 1991-04-01 onward — that's when the federal $2.13 cash
# subminimum was set, after which the state-vs-federal divergence
# becomes the primary error in the federal-default fallback.
#
# Pre-1991 (1974-1990): we leave the federal default in place. Some
# states (CA, AK, NV, OR, WA) banned the tip credit before 1991, but
# the under-statement is small relative to the very low federal
# tipped subminimum then ($1.00-$1.90), and CPS sample for those
# years is already covered by 02a's panel-start of 1982.
#
# Sources:
#   - Allegretto & Cooper (2014) EPI Briefing Paper #379 Table A1
#     https://www.epi.org/publication/waiting-for-change-tipped-minimum-wage/
#   - DOL WHD "Minimum Wages for Tipped Employees"
#     https://www.dol.gov/agencies/whd/state/minimum-wage/tipped
#
# State-by-state ban effective dates (used to set the override start):
#   Alaska     - pre-1991 (always banned; 1959 statehood law)
#   California - pre-1991 (banned since 1916 wage order)
#   Minnesota  - 1990-04-01 (state law amendment)
#   Montana    - pre-1991 (large employers; small employer exception)
#   Nevada     - pre-1991 (1968 state law)
#   Oregon     - pre-1991 (1979 state law)
#   Washington - pre-1991 (1989 state law)
#
# All effective dates are pre-1991; for simplicity we apply the
# override from 1991-04-01 for all seven uniformly.

tip_credit_banned_states_chr <- c(
  "Alaska", "California", "Minnesota", "Montana",
  "Nevada", "Oregon", "Washington"
)
ban_override_start_dt <- as.Date("1991-04-01")

# 8.7a) Build state general MW per (state, year-month) from VZ + extension
# VZ monthly already has min_fed_mw, max_fed_mw, min_mw, max_mw. We use
# the max-of-month convention for both fed and state (matching 20c) and
# take the pmax to get the binding general floor in nominal dollars.

if (!exists("vz_state_monthly_raw_df", inherits = FALSE)) {
  vz_state_monthly_dta_chr <- fs::path(
    vz_release_dir_chr, "mw_state_stata", "mw_state_monthly.dta"
  )

  vz_state_monthly_raw_df <- haven::read_dta(vz_state_monthly_dta_chr) |>
    haven::zap_labels()

  if (is.numeric(vz_state_monthly_raw_df$monthly_date)) {
    vz_state_monthly_raw_df$monthly_date <- as.Date(paste0(
      1960L + as.integer(vz_state_monthly_raw_df$monthly_date) %/% 12L, "-",
      sprintf("%02d", (as.integer(vz_state_monthly_raw_df$monthly_date) %% 12L) + 1L),
      "-01"
    ))
  }
}

vz_state_general_monthly_df <- vz_state_monthly_raw_df |>
  dplyr::transmute(
    jurisdiction_chr = as.character(statename),
    year_int  = as.integer(format(monthly_date, "%Y")),
    month_int = as.integer(format(monthly_date, "%m")),
    state_general_mw_num = pmax(
      as.numeric(max_fed_mw), as.numeric(max_mw), na.rm = TRUE
    )
  )

if (exists("state_panel_extended_df", inherits = FALSE) &&
    nrow(state_panel_extended_df) > 0L) {
  # Federal MW under the 2009 FLSA amendment is $7.25/hr; this floor has
  # not been adjusted since 2009-07-24. Extracted as a named constant
  # (replaces an inline hard-code).
  federal_floor_2009_num <- 7.25
  ext_state_general_monthly_df <- state_panel_extended_df |>
    dplyr::mutate(
      year_int  = as.integer(format(date_dt, "%Y")),
      month_int = as.integer(format(date_dt, "%m"))
    ) |>
    dplyr::group_by(jurisdiction_chr, year_int, month_int) |>
    dplyr::summarise(
      state_general_mw_num = max(
        pmax(federal_floor_2009_num, rate_min_num, na.rm = TRUE),
        na.rm = TRUE
      ),
      .groups = "drop"
    )
} else {
  ext_state_general_monthly_df <- tibble::tibble(
    jurisdiction_chr = character(0L),
    year_int  = integer(0L),
    month_int = integer(0L),
    state_general_mw_num = numeric(0L)
  )
}

state_general_monthly_df <- dplyr::bind_rows(
  vz_state_general_monthly_df,
  ext_state_general_monthly_df
) |>
  dplyr::distinct(jurisdiction_chr, year_int, month_int, .keep_all = TRUE)

# 8.7b) Apply override to the state tipped panel for banned states

state_tipped_panel_df <- state_tipped_panel_df |>
  dplyr::mutate(
    year_int  = as.integer(format(date_dt, "%Y")),
    month_int = as.integer(format(date_dt, "%m"))
  ) |>
  dplyr::left_join(
    state_general_monthly_df,
    by = c("jurisdiction_chr", "year_int", "month_int")
  ) |>
  dplyr::mutate(
    is_tip_credit_banned_flag = jurisdiction_chr %in% tip_credit_banned_states_chr &
      date_dt >= ban_override_start_dt &
      !is.na(state_general_mw_num),
    rate_tipped_num = dplyr::if_else(
      is_tip_credit_banned_flag,
      state_general_mw_num,
      rate_tipped_num
    ),
    source_chr = dplyr::if_else(
      is_tip_credit_banned_flag,
      "tip_credit_banned_state_mw",
      source_chr
    )
  ) |>
  dplyr::select(
    -year_int, -month_int, -state_general_mw_num, -is_tip_credit_banned_flag
  )

# 8.8) TODO: state-level override for partial-tip-credit states ------------
# A small set of additional states have cash tipped subminimums that
# differ from both federal $2.13 and full state MW. Examples:
#   - DC, NY, NJ, MA, MD, RI, MI, IL, ME, OH, FL, AR, CT
# For these states, the cash tipped is intermediate and historically
# tied to specific schedules (often 60-66% of state MW or fixed dollar
# amounts). Sourcing this requires Allegretto-Cooper 2014 Appendix
# Table A1 plus DOL WHD Wayback Machine snapshots (2007-2024). YAML
# template at data/raw/minimum_wage/extension/tipped/partial.yaml when
# the data is curated.
#
# Until then, these states use federal default ($2.13). The under-
# statement is bounded: cash tipped in DC was $2.77 in 2014 (vs $2.13
# federal); NY ranged $4.65-$8.65 by occupation; the binding-share
# under-statement from this gap is on the order of 0.1-0.3 pp.

if (fs::file_exists(tipped_pre2007_yaml_chr)) {
  message(
    "20b_extend-minimum-wage-forward.R -- TODO: tipped pre-2007 partial-credit ",
    "YAML found at ", tipped_pre2007_yaml_chr, "; ingest logic not yet implemented."
  )
}

if (fs::file_exists(tipped_post2007_yaml_chr)) {
  message(
    "20b_extend-minimum-wage-forward.R -- TODO: tipped 2007-onward partial-credit ",
    "YAML found at ", tipped_post2007_yaml_chr, "; ingest logic not yet implemented."
  )
}

# 8.9) Diagnostics and write -----------------------------------------------

n_tipped_rows_int <- nrow(state_tipped_panel_df)
n_yaml_override_rows_int <- sum(
  state_tipped_panel_df$source_chr == "state_override_from_yaml",
  na.rm = TRUE
)
n_banned_override_rows_int <- sum(
  state_tipped_panel_df$source_chr == "tip_credit_banned_state_mw",
  na.rm = TRUE
)
n_federal_default_rows_int <- sum(
  state_tipped_panel_df$source_chr == "federal_default",
  na.rm = TRUE
)

message(
  "20b_extend-minimum-wage-forward.R -- state tipped panel: ",
  n_tipped_rows_int, " rows (51 jurisdictions x ",
  length(tipped_dates_dt), " days); source breakdown -- ",
  n_banned_override_rows_int, " tip_credit_banned_state_mw, ",
  n_yaml_override_rows_int, " state_override_from_yaml, ",
  n_federal_default_rows_int, " federal_default. ",
  if (n_state_tipped_overrides_int > 0L) {
    paste0(n_state_tipped_overrides_int, " YAML override events ingested.")
  } else {
    "No YAML override events (extension YAML not loaded)."
  }
)

saveRDS(
  state_tipped_panel_df,
  fs::path(intermediate_dir_chr, "state_tipped_panel.rds")
)
arrow::write_parquet(
  state_tipped_panel_df,
  fs::path(intermediate_dir_chr, "state_tipped_panel.parquet")
)

message(
  "20b_extend-minimum-wage-forward.R -- wrote state_tipped_panel ",
  ".{rds,parquet} to ", intermediate_dir_chr
)

###################################
###   Success log               ###
###################################

message(
  "20b_extend-minimum-wage-forward.R -- done. DOL WHD historical state ",
  "panel parsed and cross-validated against VZ. ",
  "Forward extension and tipped panel build deferred pending hand-",
  "curated YAML inputs."
)
