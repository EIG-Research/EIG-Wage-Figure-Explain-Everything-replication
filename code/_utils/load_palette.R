# load_palette -- read the 2022 primary EIG palette as a named character vector
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

# Sourced by code/figure_a_percentiles.R, code/figure_b_age_bins.R, and
# code/figure_c_generation.R via
#   source(here::here("code", "_utils", "load_palette.R"))
# The script populates `eig_palette_2022_primary` (named character vector of
# hex codes, keyed by token id) and `eig_palette_tokens_meta` (meta block from
# the token JSON) in the calling environment. No custom functions are defined.

# jsonlite is loaded explicitly so the script can be sourced standalone
# in a code review (it is otherwise a transitive tidyverse dependency).

suppressPackageStartupMessages(library(jsonlite))
suppressPackageStartupMessages(library(here))

#####################################
###   Locate canonical token file ###
#####################################

eig_palette_tokens_path <- here("code", "_utils", "eig-style-tokens.v1.json")

if (!file.exists(eig_palette_tokens_path)) {
  stop(
    "load_palette.R -- cannot find EIG style tokens at ",
    eig_palette_tokens_path
  )
}

#####################################
###   Parse tokens JSON           ###
#####################################

eig_palette_tokens_raw <- jsonlite::read_json(
  eig_palette_tokens_path,
  simplifyVector = TRUE
)

eig_palette_tokens_meta <- eig_palette_tokens_raw$meta

#####################################
###   Extract 2022 primary brand  ###
#####################################
# The token file stores brand colors as a flat list of records with fields
# `id`, `hex`, `rgb`, `source`, `status`, `role`. The 2022 primary palette is
# the subset where source == "2022" and status == "primary".

brand_df <- tibble::as_tibble(eig_palette_tokens_raw$colors$brand)

required_brand_cols_chr <- c("id", "hex", "source", "status")
missing_brand_cols_chr  <- setdiff(required_brand_cols_chr, names(brand_df))

if (length(missing_brand_cols_chr) > 0L) {
  stop(
    "load_palette.R -- brand records missing required columns: ",
    paste(missing_brand_cols_chr, collapse = ", ")
  )
}

primary_2022_bool <- brand_df$source == "2022" & brand_df$status == "primary"

if (sum(primary_2022_bool) == 0L) {
  stop(
    "load_palette.R -- no brand entries with source=='2022' and status=='primary' ",
    "found in ", eig_palette_tokens_path
  )
}

primary_2022_df <- brand_df[primary_2022_bool, , drop = FALSE]

#####################################
###   Build named character vector ###
#####################################

eig_palette_2022_primary <- setNames(
  primary_2022_df$hex,
  primary_2022_df$id
)

#####################################
###   Sanity and diagnostic log    ###
#####################################

if (!all(grepl("^#[0-9A-Fa-f]{6}$", eig_palette_2022_primary))) {
  stop(
    "load_palette.R -- one or more hex values do not match the 6-digit hex pattern: ",
    paste(
      names(eig_palette_2022_primary)[
        !grepl("^#[0-9A-Fa-f]{6}$", eig_palette_2022_primary)
      ],
      collapse = ", "
    )
  )
}

message(
  "load_palette.R -- loaded ", length(eig_palette_2022_primary),
  " colors from the 2022 primary palette (version ",
  eig_palette_tokens_meta$version, ", generated ",
  eig_palette_tokens_meta$generated_on, ")."
)
