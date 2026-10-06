# 01a_load-ipums-cps -- load IPUMS-CPS ORG extract, strip scope-creep, partition by year
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

rm(list = ls())
options(scipen = 999)
set.seed(42)

# Sourced by run_all.R inside new.env(parent = globalenv()).
#
# This script reads the raw IPUMS-CPS ORG extract staged in
# data/raw/cps_org/_ipums_extract/ (normally by 00a_download-ipums-cps.R;
# manual placement also works), strips a small set of scope-creep variables
# that are not used by this analysis, uppercases raw CPS variable names so
# they match the IPUMS canonical labels in the codebooks, zaps haven
# labelled metadata so downstream arithmetic is plain numeric, and writes a
# year-partitioned parquet raw extract at
#     data/raw/cps_org/year=YYYY/part-0.parquet  (snappy compression)
# with an .rds sidecar at
#     data/raw/cps_org/year=YYYY/part-0.rds      (xz compression)
# Dual-format checkpointing lets downstream scripts read the parquet for
# arrow-friendly columnar workflows and the .rds for native R caching.
#
# Canonical variable reference: IPUMS-CPS documentation
#   (https://cps.ipums.org/cps/). EARNWT is the ORG earnings weight and
#   is the correct weight for any person-year statistic computed from the
#   ORG earnings questions. Basic-monthly WTFINL and supplement ASECWT are
#   distinct weights and must not substitute for it; see the IPUMS-CPS
#   EARNWT variable description (https://cps.ipums.org/cps-action/variables/EARNWT). WTFINL is pulled through here for downstream
#   descriptive analyses that need the basic-monthly weight.
#
# No custom functions are defined; all transformations are inline.

source(here::here("code", "_utils", "00_packages.R"))

###################################
###   Configuration             ###
###################################

raw_output_dir_chr    <- here::here("data", "raw", "cps_org")
input_extract_dir_chr <- fs::path(raw_output_dir_chr, "_ipums_extract")

# Scope-creep variables stripped from any extract that happens to
# include them. None of these are used in the wage analysis. Names
# match the IPUMS canonical uppercase labels applied in step 3 below.
scope_creep_vars_chr <- c(
  "SCHLCOLL", "VETSTAT",
  "NATIVITY", "PRCITSHP"
)

# Minimum variable set that must be present for the downstream pipeline.
# Missing any of these is a fatal error because 01b onward cannot
# recover. Step 8b constructs the canonical wage columns by switching
# from legacy EARNWEEK / HOURWAGE to EARNWEEK2 / HOURWAGE2 at
# YEAR >= 2023. UHRSWORK1 is the basic-monthly usual-hours variable on
# the main job; 01b coalesces it with UHRSWORKORG as the hours source.
# CITIZEN, IND1990, and UNION are features in the 01b random-forest
# hours imputation. BIRTHYR is not requested from IPUMS (no native
# mnemonic); 01a derives it as YEAR - AGE in step 8 below.
required_cols_chr <- c(
  "YEAR", "EARNWT", "WTFINL",
  "AGE", "SEX", "RACE", "HISPAN", "MARST",
  "EDUC", "EMPSTAT", "CLASSWKR", "PAIDHOUR",
  "EARNWEEK", "HOURWAGE", "UHRSWORKORG", "UHRSWORK1",
  "EARNWEEK2", "HOURWAGE2",
  # RF hours-imputation features; STATEFIP and OCC2010 are also used
  # by the binding-MW sub-analysis (20a-20e).
  "STATEFIP", "OCC2010",
  "CITIZEN", "IND1990", "UNION"
)

# Q-flag columns expected after data_quality_flags = TRUE on the six
# wage and hours variables in 00a. IPUMS publishes one harmonized
# Q-flag per earner-study variable, shared between the legacy and the
# *2 successor: QEARNWEE covers both EARNWEEK and EARNWEEK2; QHOURWAG
# covers both HOURWAGE and HOURWAGE2. No separate QEARNWEE2 /
# QHOURWAG2 columns exist. Step 8c below halts if any expected flag is
# missing.
expected_qflag_cols_chr <- c(
  "QEARNWEE",      # harmonized flag for EARNWEEK AND EARNWEEK2
  "QHOURWAG",      # harmonized flag for HOURWAGE AND HOURWAGE2
  "QUHRSWORKORG",  # for UHRSWORKORG (12-char; not truncated)
  "QUHRSWORK1"     # for UHRSWORK1   (10-char; not truncated)
)

###################################
###   1) Locate the extract     ###
###################################
# The preferred path is: 00a_download-ipums-cps.R downloads the extract into
# _ipums_extract/, and this script loads it from there. A manually downloaded
# extract is also acceptable as long as the directory contains exactly one DDI
# XML file and exactly one associated .dat.gz microdata file.

if (!fs::dir_exists(input_extract_dir_chr)) {
  stop(
    "01a_load-ipums-cps.R -- IPUMS extract directory does not exist: ",
    input_extract_dir_chr,
    "\n  Run 00a_download-ipums-cps.R first, or place the DDI XML and ",
    ".dat.gz file there manually, then re-run."
  )
}

ddi_xml_paths_chr <- fs::dir_ls(input_extract_dir_chr, regexp = "\\.xml$")

if (length(ddi_xml_paths_chr) != 1L) {
  stop(
    "01a_load-ipums-cps.R -- expected exactly one DDI XML in ",
    input_extract_dir_chr, "; found ", length(ddi_xml_paths_chr), "."
  )
}

microdata_paths_chr <- fs::dir_ls(input_extract_dir_chr, regexp = "\\.dat\\.gz$")

if (length(microdata_paths_chr) != 1L) {
  stop(
    "01a_load-ipums-cps.R -- expected exactly one .dat.gz microdata file in ",
    input_extract_dir_chr, "; found ", length(microdata_paths_chr), "."
  )
}

ddi_path_chr <- as.character(ddi_xml_paths_chr)

message(
  "01a_load-ipums-cps.R -- DDI XML: ", basename(ddi_path_chr),
  "; raw data file: ", basename(microdata_paths_chr[[1L]])
)

###################################
###   2) Read DDI and microdata ###
###################################

ddi_obj <- tryCatch(
  ipumsr::read_ipums_ddi(ddi_path_chr),
  error = function(e) {
    stop(
      "01a_load-ipums-cps.R -- failed to parse DDI XML (",
      basename(ddi_path_chr), "): ", conditionMessage(e)
    )
  }
)

message(
  "01a_load-ipums-cps.R -- IPUMS project: ",
  ddi_obj$ipums_project,
  "; extract date: ", as.character(ddi_obj$extract_date),
  "; variables in DDI: ", nrow(ddi_obj$var_info)
)

cps_raw_df <- tryCatch(
  ipumsr::read_ipums_micro(ddi = ddi_obj, verbose = FALSE),
  error = function(e) {
    stop(
      "01a_load-ipums-cps.R -- failed to read microdata via ipumsr: ",
      conditionMessage(e)
    )
  }
)

message(
  "01a_load-ipums-cps.R -- microdata loaded; rows: ",
  format(nrow(cps_raw_df), big.mark = ","),
  "; columns: ", ncol(cps_raw_df)
)

###################################
###   3) Uppercase raw names    ###
###################################
# ipumsr returns raw variable names in lowercase; convert once to
# uppercase here so every downstream script can rely on the EIG-style
# UPPERCASE convention for raw source variables.

names(cps_raw_df) <- toupper(names(cps_raw_df))

###################################
###   4) Strip scope-creep vars ###
###################################

scope_creep_present_chr <- intersect(scope_creep_vars_chr, names(cps_raw_df))

if (length(scope_creep_present_chr) > 0L) {
  message(
    "01a_load-ipums-cps.R -- stripping ",
    length(scope_creep_present_chr),
    " scope-creep variable(s) (not used in the wage analysis): ",
    paste(scope_creep_present_chr, collapse = ", ")
  )
  keep_vars_chr <- setdiff(names(cps_raw_df), scope_creep_present_chr)
  cps_raw_df    <- cps_raw_df[, keep_vars_chr, drop = FALSE]
} else {
  message(
    "01a_load-ipums-cps.R -- no scope-creep variables present in extract."
  )
}

###################################
###   5) Guard required cols    ###
###################################

missing_required_chr <- setdiff(required_cols_chr, names(cps_raw_df))

if (length(missing_required_chr) > 0L) {
  stop(
    "01a_load-ipums-cps.R -- extract is missing required variable(s): ",
    paste(missing_required_chr, collapse = ", "),
    ". Rebuild the IPUMS web UI extract to include these."
  )
}

###################################
###   6) Zap labelled metadata  ###
###################################
# Strip haven_labelled metadata so downstream scripts see plain
# integer / numeric / character vectors and arrow does not need to
# round-trip IPUMS value labels through parquet.

cps_raw_df <- haven::zap_labels(cps_raw_df)

###################################
###   7) Validate YEAR column   ###
###################################

years_loaded_int <- sort(unique(as.integer(cps_raw_df$YEAR)))

if (length(years_loaded_int) == 0L || any(is.na(years_loaded_int))) {
  stop("01a_load-ipums-cps.R -- YEAR column is empty or all NA.")
}

message(
  "01a_load-ipums-cps.R -- years loaded (",
  length(years_loaded_int), "): ",
  min(years_loaded_int), "-", max(years_loaded_int)
)

###################################
###   8) Derive BIRTHYR         ###
###################################
# IPUMS-CPS has no native BIRTHYR; derive it as YEAR - AGE per the
# IPUMS-CPS documentation convention. NA in YEAR or AGE propagates to
# NA_integer_ through integer subtraction.

cps_raw_df$BIRTHYR <- as.integer(cps_raw_df$YEAR) - as.integer(cps_raw_df$AGE)

n_na_birthyr_int <- sum(is.na(cps_raw_df$BIRTHYR))
message(
  "01a_load-ipums-cps.R -- derived BIRTHYR = YEAR - AGE (IPUMS-CPS has ",
  "no native BIRTHYR); NA count: ",
  format(n_na_birthyr_int, big.mark = ","),
  " of ", format(nrow(cps_raw_df), big.mark = ",")
)

###################################
### 8b) Canonical wage columns  ###
###################################
# Build EARNWEEK_CANON_NUM and HOURWAGE_CANON_NUM by switching from
# legacy EARNWEEK / HOURWAGE to the *2 successors at YEAR >= 2023.
# Using legacy for the pre-2023 panel preserves the already-vetted
# historical series and accepts the visible seam at 2023, which 02a
# and downstream diagnostics flag. dplyr::if_else is used in place of
# base ifelse() for type-strict numeric coercion and NA propagation.

year_int_vec <- as.integer(cps_raw_df$YEAR)
use_star2_bool <- year_int_vec >= 2023L

cps_raw_df$EARNWEEK_CANON_NUM <- dplyr::if_else(
  use_star2_bool,
  as.numeric(cps_raw_df$EARNWEEK2),
  as.numeric(cps_raw_df$EARNWEEK),
  missing = NA_real_
)

cps_raw_df$HOURWAGE_CANON_NUM <- dplyr::if_else(
  use_star2_bool,
  as.numeric(cps_raw_df$HOURWAGE2),
  as.numeric(cps_raw_df$HOURWAGE),
  missing = NA_real_
)

# Per-era sanity messages. Zero-nonmissing on the wrong side of the
# seam (legacy populated in 2024+, or *2 unpopulated post-2023)
# indicates an extract problem or misconfigured switch threshold.
n_legacy_era_int <- sum(!use_star2_bool, na.rm = TRUE)
n_star2_era_int  <- sum( use_star2_bool, na.rm = TRUE)
n_canon_earnwk_nonmissing_legacy_int <- sum(
  !use_star2_bool & !is.na(cps_raw_df$EARNWEEK_CANON_NUM),
  na.rm = TRUE
)
n_canon_earnwk_nonmissing_star2_int  <- sum(
   use_star2_bool & !is.na(cps_raw_df$EARNWEEK_CANON_NUM),
  na.rm = TRUE
)
n_canon_hrwage_nonmissing_legacy_int <- sum(
  !use_star2_bool & !is.na(cps_raw_df$HOURWAGE_CANON_NUM),
  na.rm = TRUE
)
n_canon_hrwage_nonmissing_star2_int  <- sum(
   use_star2_bool & !is.na(cps_raw_df$HOURWAGE_CANON_NUM),
  na.rm = TRUE
)

message(
  "01a_load-ipums-cps.R -- canonical wage seam at YEAR = 2023 ",
  "(legacy rows: ", format(n_legacy_era_int, big.mark = ","),
  "; *2 rows: ", format(n_star2_era_int, big.mark = ","), ")"
)
message(
  "01a_load-ipums-cps.R -- EARNWEEK_CANON_NUM non-missing rows -- ",
  "legacy era: ", format(n_canon_earnwk_nonmissing_legacy_int, big.mark = ","),
  "; *2 era: ", format(n_canon_earnwk_nonmissing_star2_int, big.mark = ",")
)
message(
  "01a_load-ipums-cps.R -- HOURWAGE_CANON_NUM non-missing rows -- ",
  "legacy era: ", format(n_canon_hrwage_nonmissing_legacy_int, big.mark = ","),
  "; *2 era: ", format(n_canon_hrwage_nonmissing_star2_int, big.mark = ",")
)

###################################
### 8c) Q-flag diagnostic       ###
###################################
# Post-deployment verification of the Q-flag column names. IPUMS's 8-char
# DDI truncation is applied to some but not all Q-prefix flag names;
# the *2 successor truncations are not publicly documented. This block
# enumerates the actual Q-prefix columns present in the loaded data so
# any unanticipated truncation surfaces before 01b's allocation drop
# tries to read an absent column.
#
# The diagnostic fails fast on missing flags with a named error that
# points the operator at the specific column to repair. If IPUMS has
# changed the DDI truncation, update `expected_qflag_cols_chr` near
# the top of this script and rerun.

qflag_present_chr <- intersect(
  expected_qflag_cols_chr, names(cps_raw_df)
)
qflag_missing_chr <- setdiff(
  expected_qflag_cols_chr, names(cps_raw_df)
)
qflag_unexpected_chr <- setdiff(
  grep("^Q", names(cps_raw_df), value = TRUE),
  expected_qflag_cols_chr
)

message(
  "01a_load-ipums-cps.R -- Q-flag diagnostic: ",
  length(qflag_present_chr), " expected Q-flags present (",
  paste(qflag_present_chr, collapse = ", "),
  "); ", length(qflag_missing_chr), " expected missing (",
  paste(qflag_missing_chr, collapse = ", "),
  "); ", length(qflag_unexpected_chr), " unexpected Q-prefix columns (",
  paste(qflag_unexpected_chr, collapse = ", "), ")"
)

if (length(qflag_missing_chr) > 0L) {
  stop(
    "01a_load-ipums-cps.R -- expected Q-flag column(s) missing from the ",
    "loaded extract: ",
    paste(qflag_missing_chr, collapse = ", "),
    ". Either rebuild the extract with data_quality_flags = TRUE on the ",
    "corresponding source variable in 00a, or update ",
    "`expected_qflag_cols_chr` near the top of 01a to match the actual ",
    "DDI truncation. Unexpected Q-prefix columns present in the extract: ",
    paste(qflag_unexpected_chr, collapse = ", "), "."
  )
}

###################################
###   9) Write year partitions  ###
###################################
# Layout: data/raw/cps_org/year=YYYY/part-0.parquet (snappy) plus a
# matching part-0.rds (xz) sidecar per the EIG dual-format checkpoint
# convention.

row_counts_per_year_int <- integer(length(years_loaded_int))
names(row_counts_per_year_int) <- as.character(years_loaded_int)

for (yr in years_loaded_int) {

  year_mask_bool <- cps_raw_df$YEAR == yr
  year_df        <- cps_raw_df[year_mask_bool, , drop = FALSE]

  year_partition_dir_chr <- fs::path(
    raw_output_dir_chr, paste0("year=", yr)
  )
  fs::dir_create(year_partition_dir_chr, recurse = TRUE)

  parquet_path_chr <- fs::path(year_partition_dir_chr, "part-0.parquet")
  rds_path_chr     <- fs::path(year_partition_dir_chr, "part-0.rds")

  arrow::write_parquet(
    x           = year_df,
    sink        = parquet_path_chr,
    compression = "snappy"
  )

  saveRDS(year_df, file = rds_path_chr, compress = "xz")

  row_counts_per_year_int[as.character(yr)] <- nrow(year_df)

  message(
    "01a_load-ipums-cps.R -- wrote year ", yr, ": ",
    format(nrow(year_df), big.mark = ","),
    " rows -> part-0.parquet, part-0.rds"
  )
}

###################################
###  10) Write manifest         ###
###################################
# One row per year with row counts, extract DDI file, and IPUMS extract
# date. A second column-level manifest records each variable's R dtype
# so downstream schema-consistency checks can compare across years.

manifest_per_year_df <- tibble::tibble(
  year               = years_loaded_int,
  n_rows             = as.integer(
    row_counts_per_year_int[as.character(years_loaded_int)]
  ),
  extract_ddi_file   = basename(ddi_path_chr),
  ipums_project      = ddi_obj$ipums_project,
  ipums_extract_date = as.character(ddi_obj$extract_date)
)

manifest_path_chr <- fs::path(raw_output_dir_chr, "_manifest.csv")
readr::write_csv(manifest_per_year_df, manifest_path_chr)

# Column-level manifest (variable name, R dtype).
colinfo_df <- tibble::tibble(
  variable_name = names(cps_raw_df),
  r_dtype       = vapply(cps_raw_df, function(col) class(col)[[1L]],
                         character(1L))
)
colinfo_path_chr <- fs::path(raw_output_dir_chr, "_columns.csv")
readr::write_csv(colinfo_df, colinfo_path_chr)

message(
  "01a_load-ipums-cps.R -- manifest rows: ",
  nrow(manifest_per_year_df),
  "; column manifest rows: ", nrow(colinfo_df),
  "; total microdata rows: ",
  format(sum(manifest_per_year_df$n_rows), big.mark = ",")
)

###################################
###   Success log               ###
###################################

message(
  "01a_load-ipums-cps.R -- done. ",
  length(years_loaded_int),
  " year partitions written under ", raw_output_dir_chr, "/year=YYYY/."
)
