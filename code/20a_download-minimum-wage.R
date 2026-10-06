# 20a_download-minimum-wage -- download Vaghul-Zipperer historical minimum wage release
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - what share of US wage and salary workers are constrained by their applicable (federal, state, county, or city) minimum wage, 1979 through present?

rm(list = ls())
options(scipen = 999)
# set.seed retained for project-wide consistency with other tiers that
# do use randomness (bootstraps, splits). Stages 20a-20e are
# deterministic; the seed is a no-op here.
set.seed(42)

# Sourced by run_all.R inside new.env(parent = globalenv()).
#
# This script is the appendix-tier minimum-wage acquisition step. It
# downloads the Vaghul-Zipperer (VZ) historical state and sub-state
# minimum wage release from the GitHub release assets and unpacks the
# four release ZIPs into
#   data/raw/minimum_wage/vz_release/<release_tag>/<archive>/
# so that 20c_build-binding-minimum-panel.R can collapse the daily
# panels to monthly and merge to the CPS-ORG sample.
#
# Panel-start year (1979) is fixed across this tier. CPS-ORG hourly-
# wage microdata are conventionally usable from 1979 forward (the
# rotation-group format and the IPUMS-CPS hourly wage variable are
# both well-defined starting that year), and BLS Report 1117
# Characteristics of Minimum Wage Workers reports a continuous
# federal-binding share series starting 1979/1982. Earlier years
# are available in IPUMS-CPS but with reduced sample design
# coverage and weaker comparability to the BLS reference series
#.
#
# The forward extension to cover the period from VZ's coverage end
# (2022-12-31) to today is the responsibility of
# 20b_extend-minimum-wage-forward.R, which produces a separate panel
# in the same VZ schema using the UC Berkeley Labor Center inventory
# and the EPI Minimum Wage Tracker as primary sources. The two panels
# are stacked in 20c.
#
# The local cache-validity check is intentionally conservative. A new
# download is triggered when any of the following hold:
#   - the metadata RDS is missing or unreadable,
#   - the cached release tag does not match the configured release tag,
#   - any of the four expected ZIP files are missing on disk,
#   - any of the four expected unpack directories are missing or empty.
#
# Place-of-residence vs. place-of-work is a known measurement-error
# issue: CPS reports state and (where identified) county of residence,
# but the minimum wage applies at place of work. For commuters across
# jurisdictional boundaries the binding floor will be wrong. The
# pipeline assumes place-of-residence is a workable proxy.
#
# No custom functions are defined; all state management is inline.

source(here::here("code", "_utils", "00_packages.R"))

###################################
###   Configuration             ###
###################################

# VZ release tag and coverage end date. Bump these when a new VZ
# release is published; the cache-invalidation check at step 1 will
# trigger a re-download.
vz_release_tag_chr        <- "v1.4.0"
vz_coverage_end_chr       <- "2022-12-31"
vz_release_published_chr  <- "2022-11-11"

# Asset names exposed on the GitHub release. All four are required.
vz_assets_chr <- c(
  "mw_state_excel.zip",
  "mw_state_stata.zip",
  "mw_substate_excel.zip",
  "mw_substate_stata.zip"
)

# Asset sizes published on GitHub for v1.4.0, in bytes. Used as a
# light integrity check after download. Update alongside vz_release_tag_chr
# when a new release is configured.
vz_asset_sizes_int <- c(
  mw_state_excel.zip    = 770035L,
  mw_state_stata.zip    = 8715601L,
  mw_substate_excel.zip = 3702466L,
  mw_substate_stata.zip = 1950976L
)

vz_base_url_chr <- paste0(
  "https://github.com/benzipperer/historicalminwage/releases/download/",
  vz_release_tag_chr
)

raw_output_dir_chr   <- here::here("data", "raw", "minimum_wage")
release_dir_chr      <- fs::path(raw_output_dir_chr, "vz_release", vz_release_tag_chr)
release_info_rds_chr <- fs::path(release_dir_chr, "_release_info.rds")

fs::dir_create(release_dir_chr, recurse = TRUE)

###################################
###   1) Check local cache      ###
###################################

needs_download_bool <- TRUE
download_reason_chr <- "no cached release metadata"

if (fs::file_exists(release_info_rds_chr)) {

  prior_release_info_ls <- tryCatch(
    readRDS(release_info_rds_chr),
    error = function(e) NULL
  )

  if (is.null(prior_release_info_ls)) {

    download_reason_chr <- "cached metadata exists but could not be read"

  } else if (!identical(prior_release_info_ls$release_tag_chr, vz_release_tag_chr)) {

    download_reason_chr <- paste0(
      "cached metadata is for release ", prior_release_info_ls$release_tag_chr,
      " but the configured release is ", vz_release_tag_chr
    )

  } else {

    expected_zip_paths_chr    <- fs::path(release_dir_chr, vz_assets_chr)
    expected_unpack_dirs_chr  <- fs::path(release_dir_chr, fs::path_ext_remove(vz_assets_chr))

    zips_present_bool   <- all(fs::file_exists(expected_zip_paths_chr))
    unpack_present_bool <- all(fs::dir_exists(expected_unpack_dirs_chr))

    # Confirm every unpack directory contains at least one file. An
    # explicit loop is used in place of a vapply()+anonymous-function
    # pattern so RA reviewers can read the check linearly.
    nonempty_unpack_bool <- TRUE

    if (unpack_present_bool) {
      for (unpack_dir_check_chr in expected_unpack_dirs_chr) {
        n_entries_int <- length(fs::dir_ls(unpack_dir_check_chr, recurse = FALSE))
        if (n_entries_int == 0L) {
          nonempty_unpack_bool <- FALSE
          break
        }
      }
    } else {
      nonempty_unpack_bool <- FALSE
    }

    if (zips_present_bool && unpack_present_bool && nonempty_unpack_bool) {
      needs_download_bool <- FALSE
    } else {
      download_reason_chr <- "cached release tag matches but expected files or unpack directories are missing"
    }
  }
}

if (!needs_download_bool) {

  message(
    "20a_download-minimum-wage.R -- cached VZ release ", vz_release_tag_chr,
    " is current (coverage through ", vz_coverage_end_chr, "); skipping download."
  )

} else {

  message(
    "20a_download-minimum-wage.R -- refresh required: ", download_reason_chr
  )

  ###################################
  ###   2) Download release ZIPs  ###
  ###################################

  for (asset_chr in vz_assets_chr) {

    asset_url_chr  <- paste0(vz_base_url_chr, "/", asset_chr)
    asset_path_chr <- fs::path(release_dir_chr, asset_chr)

    message(
      "20a_download-minimum-wage.R -- downloading ", asset_chr,
      " from ", asset_url_chr
    )

    tryCatch(
      utils::download.file(
        url      = asset_url_chr,
        destfile = asset_path_chr,
        mode     = "wb",
        quiet    = FALSE
      ),
      error = function(e) {
        stop(
          "20a_download-minimum-wage.R -- failed to download ", asset_chr,
          ": ", conditionMessage(e)
        )
      }
    )

    actual_size_int   <- as.integer(fs::file_size(asset_path_chr))
    expected_size_int <- vz_asset_sizes_int[[asset_chr]]

    if (!is.na(expected_size_int) && actual_size_int != expected_size_int) {
      stop(
        "20a_download-minimum-wage.R -- size mismatch for ", asset_chr,
        ": expected ", expected_size_int, " bytes, got ", actual_size_int,
        " bytes. The release asset may have been re-uploaded; verify the ",
        "release on GitHub before proceeding."
      )
    }
  }

  ###################################
  ###   3) Unpack release ZIPs    ###
  ###################################

  for (asset_chr in vz_assets_chr) {

    asset_path_chr <- fs::path(release_dir_chr, asset_chr)
    unpack_dir_chr <- fs::path(release_dir_chr, fs::path_ext_remove(asset_chr))

    if (fs::dir_exists(unpack_dir_chr)) {
      stale_files_chr <- fs::dir_ls(unpack_dir_chr, recurse = TRUE, type = "file")
      if (length(stale_files_chr) > 0L) {
        fs::file_delete(stale_files_chr)
      }
    } else {
      fs::dir_create(unpack_dir_chr, recurse = TRUE)
    }

    message("20a_download-minimum-wage.R -- unpacking ", asset_chr, " ...")

    utils::unzip(
      zipfile  = asset_path_chr,
      exdir    = unpack_dir_chr,
      overwrite = TRUE
    )
  }

  ###################################
  ###   4) Write metadata         ###
  ###################################

  release_info_ls <- list(
    release_tag_chr           = vz_release_tag_chr,
    coverage_end_chr          = vz_coverage_end_chr,
    release_published_at_chr  = vz_release_published_chr,
    base_url_chr              = vz_base_url_chr,
    assets_chr                = vz_assets_chr,
    asset_sizes_int           = vz_asset_sizes_int,
    release_dir_chr           = release_dir_chr,
    downloaded_at_posix       = Sys.time()
  )

  saveRDS(release_info_ls, release_info_rds_chr)

  message(
    "20a_download-minimum-wage.R -- metadata written: ", release_info_rds_chr
  )
}

###################################
###   5) Audit summary          ###
###################################
# Inventory of files that ended up on disk. Written to release_dir_chr
# as a small RDS so 20c can verify the expected schema without re-walking
# the directory each time.

audit_paths_chr <- fs::dir_ls(release_dir_chr, recurse = TRUE, type = "file")

audit_summary_df <- tibble::tibble(
  path_rel_chr     = fs::path_rel(audit_paths_chr, release_dir_chr),
  size_bytes_int   = as.integer(fs::file_size(audit_paths_chr)),
  is_data_file_flag = stringr::str_detect(audit_paths_chr, "\\.(dta|xlsx)$")
)

audit_rds_chr <- fs::path(release_dir_chr, "_audit_summary.rds")
saveRDS(audit_summary_df, audit_rds_chr)

n_data_files_int <- sum(audit_summary_df$is_data_file_flag)

message(
  "20a_download-minimum-wage.R -- audit: ", nrow(audit_summary_df),
  " files staged in ", release_dir_chr, " (", n_data_files_int,
  " .dta/.xlsx data files)."
)

###################################
###   Success log               ###
###################################

message(
  "20a_download-minimum-wage.R -- done. VZ ", vz_release_tag_chr,
  " coverage through ", vz_coverage_end_chr,
  ". Forward extension handled by 20b_extend-minimum-wage-forward.R."
)
