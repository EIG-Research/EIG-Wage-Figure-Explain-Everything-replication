# 00_packages -- pinned package manifest and loader for the EIG Wage Figure build
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

# This file is sourced at the top of every analysis script via
# source(here::here("code", "_utils", "00_packages.R"))
# It defines the pinned package manifest, checks availability, and loads the
# core tidyverse and project packages into the current environment.

# Version pins are CRAN releases available as of the most recent EIG lab
# refresh. If renv is introduced later, these are the versions that should be
# captured in renv.lock.

###################################
###   Pinned package manifest   ###
###################################
# Format: package = minimum known-good version

required_packages_list <- list(
  # Core tidyverse
  tidyverse = "2.0.0",

  # Data I/O
  arrow     = "14.0.0",   # parquet read/write
  haven     = "2.5.4",    # labelled Stata/SAS; zap_labels for IPUMS
  ipumsr    = "0.8.0",    # read_ipums_micro, DDI parsing
  fredr     = "2.1.0",    # FRED series pull for PCEPI and sensitivity deflators
  readxl    = "1.4.3",    # BLS CPI-U-RS XLSX parse (code/_utils/download_deflators.R)
  jsonlite  = "1.8.8",    # style tokens JSON parsing (code/_utils/load_palette.R)
  rvest     = "1.0.4",    # HTML table parsing (code/20b_extend-minimum-wage-forward.R)
  xml2      = "1.3.6",    # rvest dependency, used directly for HTML node selection
  writexl   = "1.5.0",    # multi-sheet XLSX export (code/figure_a_percentiles_by_sex.R)

  # Utilities
  fs        = "1.6.3",    # file system operations, path handling
  here      = "1.0.1",    # project-root-relative paths
  lubridate = "1.9.3",    # date handling; loaded via tidyverse 2.0+
  scales    = "1.3.0",    # axis formatters for figures
  yaml      = "2.3.8",    # literature catalog.yaml parsing
  zoo       = "1.8-12",   # rollapplyr for the 12-month flat rolling-average smoother in figures A and B

  # Random-forest hours imputation
  ranger    = "0.16.0",   # per-year RF imputer for hours-vary respondents (01b)
  # Figure F (lines over era bars)
  patchwork   = "1.3.2",  # stacks the line and bar panels on one shared date axis (figure_f_era_bars.R)
  systemfonts = "1.3.2",  # text-width measurement for label placement and wrapping (figure_f_era_bars.R)
  ragg        = "1.5.2",  # layout measurement device; also the eig_fonts.R render device
  png         = "0.1.9"   # reads the rendered PNG to verify era-rule alignment (figure_f_era_bars.R)
)

# Note: fixest, lfe, survey, fastverse, data.table are NOT in the manifest.
# This build has no regressions or survey design declarations. ranger is
# the lone modeling package, used exclusively in 01b for the hours
# imputation block.

required_packages_chr <- names(required_packages_list)

############################
###   Availability check ###
############################

installed_packages_chr <- rownames(installed.packages())
missing_packages_chr   <- setdiff(required_packages_chr, installed_packages_chr)

if (length(missing_packages_chr) > 0L) {
  stop(
    "Missing required packages: ",
    paste(missing_packages_chr, collapse = ", "),
    ". Install via install.packages() before sourcing this script."
  )
}

#############################
###   Version pin check   ###
#############################

for (pkg in required_packages_chr) {
  installed_ver_chr <- as.character(utils::packageVersion(pkg))
  required_ver_chr  <- required_packages_list[[pkg]]
  if (utils::compareVersion(installed_ver_chr, required_ver_chr) < 0L) {
    warning(
      "Package '", pkg, "' version ", installed_ver_chr,
      " is older than the pinned minimum ", required_ver_chr, "."
    )
  }
}

#####################################
###   Load core project packages  ###
#####################################

suppressPackageStartupMessages({
  library(tidyverse)
  library(arrow)
  library(haven)
  library(ipumsr)
  library(fredr)
  library(jsonlite)
  library(fs)
  library(here)
  library(scales)
  library(yaml)
  library(rvest)
  library(xml2)
  library(ranger)
  library(writexl)
})

message("00_packages.R -- manifest loaded; ", length(required_packages_chr),
        " packages checked and available.")

#####################################
###   Shared statistical helpers  ###
#####################################
# weighted_quantile() and weighted_population() are defined in one place
# so every reporting path uses an identical implementation. See the file
# header for the no-interpolation quantile convention and the
# divide-by-survey-months population rule.

source(here::here("code", "_utils", "weighted_stats.R"))

message("00_packages.R -- shared weighted_stats helpers loaded.")
