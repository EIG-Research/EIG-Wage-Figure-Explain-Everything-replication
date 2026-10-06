# 00a_download-ipums-cps -- define, submit, and download the IPUMS-CPS raw extract
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

rm(list = ls())
options(scipen = 999)
set.seed(42)

# Sourced by run_all.R inside new.env(parent = globalenv()).
#
# This script is the pre-01a acquisition step. It uses the IPUMS API to:
#   1) discover the currently available CPS monthly samples,
#   2) define the minimum extract needed by the current analytic pipeline,
#   3) submit the extract only when the local raw extract is missing or stale,
#   4) download the resulting DDI XML plus associated .dat.gz file into
#      data/raw/cps_org/_ipums_extract/
# so that 01a_load-ipums-cps.R can perform the standardized load,
# uppercase-name normalization, scope-creep stripping, and year partitioning.
#
# The local cache-validity check is intentionally conservative. A new download
# is triggered when any of the following hold:
#   - the raw extract files are missing,
#   - the cached sample list no longer matches the current IPUMS sample list,
#   - the requested variable list changed,
#   - the prior metadata file is absent or unreadable.
#
# No custom functions are defined; all state management is inline.

source(here::here("code", "_utils", "00_packages.R"))

###################################
###   Configuration             ###
###################################

collection_chr       <- "cps"
extract_start_year_int <- 1982L
extract_timeout_sec_num <- 3600

raw_output_dir_chr   <- here::here("data", "raw", "cps_org")
extract_dir_chr      <- fs::path(raw_output_dir_chr, "_ipums_extract")
extract_info_rds_chr <- fs::path(extract_dir_chr, "_extract_info.rds")

# Minimum defensible variable set for the current pipeline. Variables
# are passed to ipumsr::define_extract_micro() as a list of
# ipumsr::var_spec() calls. Six variables carry data_quality_flags =
# TRUE so IPUMS attaches the harmonized Q-prefix allocation flags.
#
# Q-flag conventions:
#   QEARNWEE  covers EARNWEEK and EARNWEEK2 (one shared flag).
#   QHOURWAG  covers HOURWAGE and HOURWAGE2 (one shared flag).
#   QUHRSWORKORG (12-char; not truncated) for UHRSWORKORG.
#   QUHRSWORK1   (10-char; not truncated) for UHRSWORK1.
# Code 0 = unaltered; nonzero = edited or allocated.
#
# 01b applies the optional SWA allocation-drop using these flags; see
# docs/decisions/decision_03_retain_allocated_records.md.
#
# HOURWAGE2 / EARNWEEK2 are the post-April-2023 successor variables.
# 01a builds *_CANON_NUM columns by switching from legacy to *2 at
# YEAR >= 2023.
#
# UHRSWORK1 / UHRSWORKORG: 01b coalesces these as the primary-hours
# source (UHRSWORK1 preferred).
#
# CLASSWKR supports the 01b self-employment exclusion (CLASSWKR %in%
# 10:14) and the public-sector indicator (CLASSWKR 25-28) used as an
# RF feature.
#
# RACE, HISPAN, MARST, CITIZEN, IND1990, UNION, EDUC, EMPSTAT, WTFINL
# are features in the 01b random-forest hours imputation
# (docs/decisions/decision_04_random_forest_hours_imputation.md) and
# supports downstream descriptive analyses.
#
# BIRTHYR is not requested. IPUMS-CPS has no native BIRTHYR; 01a
# derives it as YEAR - AGE.
variables_list <- list(
  ipumsr::var_spec("YEAR"),
  ipumsr::var_spec("MONTH"),
  ipumsr::var_spec("MISH"),
  ipumsr::var_spec("CPSIDP"),
  ipumsr::var_spec("EARNWT"),
  ipumsr::var_spec("WTFINL"),
  ipumsr::var_spec("AGE"),
  ipumsr::var_spec("SEX"),
  ipumsr::var_spec("RACE"),
  ipumsr::var_spec("HISPAN"),
  ipumsr::var_spec("MARST"),
  ipumsr::var_spec("EDUC"),
  ipumsr::var_spec("EMPSTAT"),
  ipumsr::var_spec("CLASSWKR"),
  ipumsr::var_spec("PAIDHOUR"),
  ipumsr::var_spec("HOURWAGE",    data_quality_flags = TRUE),
  ipumsr::var_spec("EARNWEEK",    data_quality_flags = TRUE),
  ipumsr::var_spec("HOURWAGE2",   data_quality_flags = TRUE),
  ipumsr::var_spec("EARNWEEK2",   data_quality_flags = TRUE),
  ipumsr::var_spec("UHRSWORKORG", data_quality_flags = TRUE),
  ipumsr::var_spec("UHRSWORK1",   data_quality_flags = TRUE),
  # Geographic identifiers and occupation code (binding-minimum-wage
  # sub-analysis 20a-20e plus RF hours-imputation features). STATEFIP
  # is universal; COUNTY and METFIPS identify ~45 percent of
  # households; INDIVIDCC carries CPS principal city codes for cities
  # not in COUNTY / METFIPS.
  ipumsr::var_spec("STATEFIP"),
  ipumsr::var_spec("COUNTY"),
  ipumsr::var_spec("METFIPS"),
  ipumsr::var_spec("INDIVIDCC"),
  ipumsr::var_spec("OCC2010"),
  # RF hours-imputation features. CITIZEN is 1994+ only (NA pre-1994);
  # IND1990 is the harmonized 1990-basis industry code (~230
  # categories); UNION is 1983+ in ORG (NIU/NA pre-1983). The
  # hours-vary signal on UHRSWORK1 / UHRSWORKORG is 1994+ so pre-1994
  # rows are not imputed regardless.
  ipumsr::var_spec("CITIZEN"),
  ipumsr::var_spec("IND1990"),
  ipumsr::var_spec("UNION")
)

# Flat character vector of the columns expected in the loaded extract.
# Cache-invalidation marker stored in _extract_info.rds so the cache
# check at step 3 detects requested-column-set changes. BIRTHYR is
# absent; it is derived by 01a from YEAR - AGE.
#
# Q-flag names follow the IPUMS 8-character DDI truncation. IPUMS
# returns one shared Q-flag per earner-study variable across legacy
# and *2 successor — QEARNWEE covers both EARNWEEK and EARNWEEK2,
# QHOURWAG covers both HOURWAGE and HOURWAGE2. QUHRSWORKORG and
# QUHRSWORK1 are within the IPUMS length limit and are not truncated.
requested_vars_chr <- c(
  # Core non-flagged variables
  "YEAR", "MONTH", "MISH", "CPSIDP",
  "EARNWT", "WTFINL",
  "AGE", "SEX", "RACE", "HISPAN", "MARST",
  "EDUC", "EMPSTAT", "CLASSWKR", "PAIDHOUR",
  # Wage and hours variables (all with data_quality_flags = TRUE in
  # var_spec).
  "HOURWAGE", "EARNWEEK", "HOURWAGE2", "EARNWEEK2",
  "UHRSWORKORG", "UHRSWORK1",
  # Harmonized IPUMS Q-flags returned alongside the above
  "QHOURWAG", "QEARNWEE",
  "QUHRSWORKORG", "QUHRSWORK1",
  # Geographic identifiers and occupation code (binding-MW sub-analysis
  # and RF hours-imputation features)
  "STATEFIP", "COUNTY", "METFIPS", "INDIVIDCC", "OCC2010",
  # RF hours-imputation features
  "CITIZEN", "IND1990", "UNION"
)

fs::dir_create(raw_output_dir_chr, recurse = TRUE)
fs::dir_create(extract_dir_chr, recurse = TRUE)

###################################
###   1) API key preflight      ###
###################################

api_key_chr <- Sys.getenv("IPUMS_API_KEY", unset = "")

if (!nzchar(api_key_chr)) {
  stop(
    "00a_download-ipums-cps.R -- IPUMS_API_KEY is not set in the R ",
    "environment. Set it before running run_all.R."
  )
}

ipumsr::set_ipums_api_key(api_key_chr)

###################################
###   2) Discover CPS samples   ###
###################################

message("00a_download-ipums-cps.R -- querying IPUMS CPS sample metadata ...")

sample_info_df <- ipumsr::get_sample_info(collection_chr)

sample_name_col_chr <- if ("name" %in% names(sample_info_df)) {
  "name"
} else {
  names(sample_info_df)[1L]
}

sample_frame_df <- sample_info_df |>
  dplyr::rename(sample_chr = dplyr::all_of(sample_name_col_chr)) |>
  dplyr::mutate(
    year_int = as.integer(stringr::str_match(sample_chr, "^cps(\\d{4})_")[, 2]),
    month_int = as.integer(stringr::str_match(sample_chr, "^cps\\d{4}_(\\d{2})")[, 2]),
    sample_date = as.Date(sprintf("%04d-%02d-01", year_int, month_int))
  ) |>
  dplyr::filter(!is.na(sample_date), year_int >= extract_start_year_int) |>
  dplyr::arrange(sample_date)

if (nrow(sample_frame_df) == 0L) {
  stop(
    "00a_download-ipums-cps.R -- no CPS monthly samples were discovered ",
    "for ", extract_start_year_int, "+. Cannot define the extract."
  )
}

sample_list_chr <- sample_frame_df$sample_chr
sample_start_chr <- as.character(min(sample_frame_df$sample_date))
sample_end_chr   <- as.character(max(sample_frame_df$sample_date))

message(
  "00a_download-ipums-cps.R -- sample range discovered: ",
  sample_start_chr, " to ", sample_end_chr,
  " (", length(sample_list_chr), " monthly samples)"
)

###################################
###   3) Check local cache      ###
###################################

ddi_paths_chr <- fs::dir_ls(extract_dir_chr, regexp = "\\.xml$")
dat_paths_chr <- fs::dir_ls(extract_dir_chr, regexp = "\\.dat\\.gz$")

has_clean_extract_files_bool <- length(ddi_paths_chr) == 1L &&
  length(dat_paths_chr) == 1L

has_extract_info_bool <- fs::file_exists(extract_info_rds_chr)

needs_download_bool  <- TRUE
download_reason_chr  <- "no cached extract metadata"
prior_extract_info_ls <- NULL

if (has_extract_info_bool) {
  prior_extract_info_ls <- tryCatch(
    readRDS(extract_info_rds_chr),
    error = function(e) NULL
  )
}

if (!has_clean_extract_files_bool && has_extract_info_bool) {
  download_reason_chr <- "metadata exists but the raw XML/.dat.gz files are missing or ambiguous"
} else if (has_clean_extract_files_bool && !has_extract_info_bool) {
  download_reason_chr <- "raw XML/.dat.gz files exist but metadata is missing"
} else if (!has_clean_extract_files_bool && !has_extract_info_bool) {
  download_reason_chr <- "no cached raw extract present"
} else if (is.null(prior_extract_info_ls)) {
  download_reason_chr <- "cached metadata exists but could not be read"
} else if (!identical(prior_extract_info_ls$samples_chr, sample_list_chr)) {
  download_reason_chr <- "IPUMS sample list changed since the cached extract"
} else if (!setequal(prior_extract_info_ls$variables_chr, requested_vars_chr)) {
  download_reason_chr <- "requested variable list changed since the cached extract"
} else {
  needs_download_bool <- FALSE
}

if (!needs_download_bool) {
  message("00a_download-ipums-cps.R -- cached extract is current; skipping download.")
  message(
    "00a_download-ipums-cps.R -- DDI XML: ",
    basename(ddi_paths_chr[[1L]]),
    "; data file: ", basename(dat_paths_chr[[1L]])
  )
  message(
    "00a_download-ipums-cps.R -- cached extract number: ",
    prior_extract_info_ls$extract_number_int,
    "; downloaded at: ", as.character(prior_extract_info_ls$downloaded_at_posix)
  )
} else {
  message("00a_download-ipums-cps.R -- refresh required: ", download_reason_chr)

  ###################################
  ###   4) Define the extract     ###
  ###################################

  extract_description_chr <- paste0(
    "EIG Wage Figure pipeline raw CPS extract: ",
    sample_start_chr, " to ", sample_end_chr
  )

  extract_definition <- ipumsr::define_extract_micro(
    collection     = collection_chr,
    description    = extract_description_chr,
    samples        = sample_list_chr,
    variables      = variables_list,
    data_format    = "fixed_width",
    data_structure = "rectangular"
  )

  ###################################
  ###   5) Submit and wait        ###
  ###################################

  extract_submitted_at_posix <- Sys.time()
  submitted_extract <- ipumsr::submit_extract(extract_definition)

  message(
    "00a_download-ipums-cps.R -- submitted IPUMS extract #",
    submitted_extract$number
  )
  message(
    "00a_download-ipums-cps.R -- waiting for completion (timeout: ",
    extract_timeout_sec_num, " seconds) ..."
  )

  downloadable_extract <- ipumsr::wait_for_extract(
    submitted_extract,
    timeout_seconds = extract_timeout_sec_num,
    verbose         = TRUE
  )

  ###################################
  ###   6) Remove stale files      ###
  ###################################
  # Keep the extract directory single-purpose: one XML, one .dat.gz, one
  # metadata RDS. 01a expects exactly one extract bundle.

  stale_raw_paths_chr <- fs::dir_ls(
    extract_dir_chr,
    regexp = "\\.(xml|dat\\.gz)$"
  )

  if (length(stale_raw_paths_chr) > 0L) {
    fs::file_delete(stale_raw_paths_chr)
    message(
      "00a_download-ipums-cps.R -- removed ",
      length(stale_raw_paths_chr), " stale raw extract file(s) from ",
      extract_dir_chr
    )
  }

  ###################################
  ###   7) Download extract       ###
  ###################################

  ddi_path_chr <- ipumsr::download_extract(
    downloadable_extract,
    download_dir = extract_dir_chr,
    overwrite    = TRUE,
    progress     = TRUE
  )

  ddi_paths_chr <- fs::dir_ls(extract_dir_chr, regexp = "\\.xml$")
  dat_paths_chr <- fs::dir_ls(extract_dir_chr, regexp = "\\.dat\\.gz$")

  if (length(ddi_paths_chr) != 1L) {
    stop(
      "00a_download-ipums-cps.R -- expected exactly one DDI XML after ",
      "download, found ", length(ddi_paths_chr), " in ", extract_dir_chr, "."
    )
  }

  if (length(dat_paths_chr) != 1L) {
    stop(
      "00a_download-ipums-cps.R -- expected exactly one .dat.gz file after ",
      "download, found ", length(dat_paths_chr), " in ", extract_dir_chr, "."
    )
  }

  ###################################
  ###   8) Write metadata         ###
  ###################################

  extract_info_ls <- list(
    collection_chr      = collection_chr,
    extract_number_int  = as.integer(submitted_extract$number),
    description_chr     = extract_description_chr,
    sample_start_chr    = sample_start_chr,
    sample_end_chr      = sample_end_chr,
    n_samples_int       = as.integer(length(sample_list_chr)),
    samples_chr         = sample_list_chr,
    n_variables_int     = as.integer(length(requested_vars_chr)),
    variables_chr       = requested_vars_chr,
    ddi_file_chr        = basename(ddi_paths_chr[[1L]]),
    data_file_chr       = basename(dat_paths_chr[[1L]]),
    download_dir_chr    = extract_dir_chr,
    submitted_at_posix  = extract_submitted_at_posix,
    downloaded_at_posix = Sys.time()
  )

  saveRDS(extract_info_ls, extract_info_rds_chr)

  message(
    "00a_download-ipums-cps.R -- downloaded DDI XML: ",
    basename(ddi_path_chr)
  )
  message(
    "00a_download-ipums-cps.R -- downloaded raw data file: ",
    basename(dat_paths_chr[[1L]])
  )
  message(
    "00a_download-ipums-cps.R -- metadata written: ",
    extract_info_rds_chr
  )
}

###################################
###   Success log               ###
###################################

message(
  "00a_download-ipums-cps.R -- done. Raw IPUMS extract staged in ",
  extract_dir_chr, " for 01a_load-ipums-cps.R."
)
