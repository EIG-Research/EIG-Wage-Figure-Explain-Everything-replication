# run_all -- pipeline orchestrator for the EIG Wage Figure Explain Everything build
# Author - Ben Glasner
# research title - EIG Wage Figure Explain Everything
# research question - how have real hourly wages evolved across percentiles, age bins, and generations from 1982 through present?

rm(list = ls())
options(scipen = 999)
set.seed(42)

# Single entry point for the full pipeline. Each downstream script is
# sourced in an isolated child environment
# (`new.env(parent = globalenv())`) so orchestrator bindings and child
# bindings cannot leak across stages.
#
# Control the pipeline by flipping the TRUE/FALSE flags below. Each
# flag is independent; any subset may be TRUE. Elapsed time per stage
# is captured by `Sys.time()` bracketing and appended to a dated run
# log under `path_log_dir_chr` (overwritten per invocation).
#
# No custom functions are defined; all orchestration is inline.

###################################
###   Anchor here::             ###
###################################
# Anchor `here` to the directory containing this script. Guards against
# `here` having cached a wrong project root from R's initial working
# directory; throws if this file is moved without updating the path.

here::i_am("code/run_all.R")

###################################
###   Packages                  ###
###################################

source(here::here("code", "_utils", "00_packages.R"))

###################################
###   Run-stage flags           ###
###################################

# Flip to FALSE to skip a stage. Stage dependencies:
#   run_01a  <- run_00a (raw extract)
#   run_02a  <- run_01b + run_00b (deflator parquet)
#   figures (incl. figure_a_sex) <- run_02a
#   run_figure_f_tables <- run_02a (EDUC column) + run_01a (raw basic-monthly panel)
#   run_figure_f        <- run_figure_f_tables
#   run_figure_g        <- run_figure_f_tables + run_00c (UNRATE parquet)
#   run_12              <- run_02a (OCC2010 and EDUC columns)
#   run_02b is independent of the figures.
#   run_00c is independent of the wage pipeline (uses FRED only).

run_00a       <- FALSE   # 00a_download-ipums-cps.R   -- IPUMS API extract define/submit/download
run_00b       <- FALSE   # _utils/download_deflators.R -- FRED deflators (PCEPI primary + four CPI shadows)
run_00c       <- FALSE   # _utils/download_unemployment.R -- FRED UNRATE pull + below-5% spell identification
run_01a       <- FALSE    # 01a_load-ipums-cps.R       -- IPUMS loader, year-partitioned raw panel
run_01b       <- FALSE    # 01b_build-org-panel.R      -- EPI sample gate + hours imputation + Pareto topcode
run_02a       <- FALSE    # 02a_build_real_wages.R     -- PCEPI join + real weekly and hourly wages + EPI outlier bounds
run_02b       <- FALSE    # 02b_build_generation_panel.R -- generation panel: weighted median real wage by year x age x generation x sex
run_figure_a  <- TRUE    # code/figure_a_percentiles.R
run_figure_a_sex <- TRUE # code/figure_a_percentiles_by_sex.R -- indexed percentiles, split by sex
run_figure_b  <- TRUE    # code/figure_b_age_bins.R
run_figure_c  <- TRUE    # code/figure_c_generation.R
run_figure_e  <- TRUE    # code/figure_e_entry_cohorts.R -- synthetic-cohort real wage growth by 5-year labor-market-entry cohort
run_figure_f_tables <- TRUE # code/figure_f_era_bars_tables.R -- pooled 12-month percentiles, ratios, education-third medians + within-era change (decision 09)
run_figure_f  <- TRUE    # code/figure_f_era_bars.R -- Figures 6a-6c, lines over era bars; reads only the figure_f tables
run_figure_g  <- TRUE    # code/figure_g_era_timeline.R -- Figure 7, era timeline: duration x median growth bars over unemployment
run_10        <- TRUE    # code/10_epi_spot_checks.R -- numerical verification against EPI SWA Data Library; reference values in epi_reference_values.csv
run_11        <- TRUE    # code/11_deflator_gap_diagnostic.R -- recompute 1990/2010/2023 percentiles under PCE vs CPI-U-RS to quantify the deflator gap
run_12        <- TRUE    # code/12_covid_composition_diagnostic.R -- COVID-19 composition effect via reweighting to 2019 composition; evidence for the Decision 10 anchor

# Appendix tier: binding-minimum-wage sub-analysis. Runs after the
# main pipeline; each stage is independent of the figure pipeline and
# can be toggled separately.
run_20a       <- TRUE    # code/20a_download-minimum-wage.R -- VZ historical minimum wage release download
run_20b       <- TRUE    # code/20b_extend-minimum-wage-forward.R -- DOL WHD parse + VZ cross-validation + forward and tipped extensions
run_20c       <- TRUE    # code/20c_build-binding-minimum-panel.R  -- state-month and substate-month binding panels stacking VZ + extension + tipped
run_20d       <- TRUE    # code/20d_merge-cps-binding.R            -- merge binding floor to CPS ORG, construct at-or-below-binding indicator
run_20e       <- TRUE    # code/20e_binding-minimum-analysis.R     -- weighted binding-share time series, subgroup tabulations, BLS validation

# Summary tier: auto-generated internal digest of every figure and its
# headline numbers. Reads from output/tables/ produced by the figure
# stages above, so should run last. Produces two parallel outputs in
# drafts/: figures_summary.md (plain markdown) and figures_summary.html
# (styled, EIG palette + typography, self-contained). The script is not
# part of the public replication package, so the stage runs only when
# the script is present.
run_30        <- unname(fs::file_exists(here::here("code", "30_build_summary.R")))   # code/30_build_summary.R -- drafts/figures_summary.{md,html} auto-build

###################################
###   Paths                     ###
###################################
# `here::here()` resolves from the project root (located by the
# `.here` / `*.Rproj` sentinel).

path_project_chr     <- here::here()
path_code_chr        <- here::here("code")
path_log_dir_chr     <- here::here("output", "logs")

if (!fs::dir_exists(path_log_dir_chr)) {
  fs::dir_create(path_log_dir_chr, recurse = TRUE)
}

run_date_chr         <- format(Sys.Date(), "%Y-%m-%d")
run_log_path_chr     <- fs::path(
  path_log_dir_chr,
  paste0(run_date_chr, "_run.md")
)

###################################
###   Stage registry            ###
###################################
# Each element is one named list with: stage id, human label, script
# path, and the run-flag value.

stage_registry_ls <- list(
  list(
    id_chr    = "00a",
    label_chr = "00a IPUMS API extract download",
    path_chr  = fs::path(path_code_chr,    "00a_download-ipums-cps.R"),
    run_bool  = run_00a
  ),
  list(
    id_chr    = "00b",
    label_chr = "00b FRED deflators (PCEPI + CPI shadows)",
    path_chr  = fs::path(path_code_chr,    "_utils", "download_deflators.R"),
    run_bool  = run_00b
  ),
  list(
    id_chr    = "00c",
    label_chr = "00c FRED unemployment (UNRATE) + below-5% spell identification",
    path_chr  = fs::path(path_code_chr,    "_utils", "download_unemployment.R"),
    run_bool  = run_00c
  ),
  list(
    id_chr    = "01a",
    label_chr = "01a IPUMS loader",
    path_chr  = fs::path(path_code_chr,    "01a_load-ipums-cps.R"),
    run_bool  = run_01a
  ),
  list(
    id_chr    = "01b",
    label_chr = "01b ORG panel build",
    path_chr  = fs::path(path_code_chr,    "01b_build-org-panel.R"),
    run_bool  = run_01b
  ),
  list(
    id_chr    = "02a",
    label_chr = "02a Real-wage build",
    path_chr  = fs::path(path_code_chr,    "02a_build_real_wages.R"),
    run_bool  = run_02a
  ),
  list(
    id_chr    = "02b",
    label_chr = "02b Generation panel",
    path_chr  = fs::path(path_code_chr,    "02b_build_generation_panel.R"),
    run_bool  = run_02b
  ),
  list(
    id_chr    = "figure_a",
    label_chr = "Figure (a) percentiles",
    path_chr  = fs::path(path_code_chr,    "figure_a_percentiles.R"),
    run_bool  = run_figure_a
  ),
  list(
    id_chr    = "figure_a_sex",
    label_chr = "Figure (a) percentiles, indexed by sex",
    path_chr  = fs::path(path_code_chr,    "figure_a_percentiles_by_sex.R"),
    run_bool  = run_figure_a_sex
  ),
  list(
    id_chr    = "figure_b",
    label_chr = "Figure (b) age bins",
    path_chr  = fs::path(path_code_chr,    "figure_b_age_bins.R"),
    run_bool  = run_figure_b
  ),
  list(
    id_chr    = "figure_c",
    label_chr = "Figure (c) generation",
    path_chr  = fs::path(path_code_chr,    "figure_c_generation.R"),
    run_bool  = run_figure_c
  ),
  list(
    id_chr    = "figure_e",
    label_chr = "Figure (e) labor-market-entry cohorts",
    path_chr  = fs::path(path_code_chr,    "figure_e_entry_cohorts.R"),
    run_bool  = run_figure_e
  ),
  list(
    id_chr    = "figure_f_tables",
    label_chr = "Figure (f) era-bar tables (pooled 12-month windows, era change)",
    path_chr  = fs::path(path_code_chr,    "figure_f_era_bars_tables.R"),
    run_bool  = run_figure_f_tables
  ),
  list(
    id_chr    = "figure_f",
    label_chr = "Figure (f) lines over era bars (6a-6c)",
    path_chr  = fs::path(path_code_chr,    "figure_f_era_bars.R"),
    run_bool  = run_figure_f
  ),
  list(
    id_chr    = "figure_g",
    label_chr = "Figure (g) era timeline (duration, median growth, unemployment)",
    path_chr  = fs::path(path_code_chr,    "figure_g_era_timeline.R"),
    run_bool  = run_figure_g
  ),
  list(
    id_chr    = "10",
    label_chr = "10 EPI spot-check verification",
    path_chr  = fs::path(path_code_chr,    "10_epi_spot_checks.R"),
    run_bool  = run_10
  ),
  list(
    id_chr    = "11",
    label_chr = "11 Deflator gap diagnostic (PCE vs CPI-U-RS)",
    path_chr  = fs::path(path_code_chr,    "11_deflator_gap_diagnostic.R"),
    run_bool  = run_11
  ),
  list(
    id_chr    = "12",
    label_chr = "12 COVID-19 composition-effect diagnostic (reweighted percentiles)",
    path_chr  = fs::path(path_code_chr,    "12_covid_composition_diagnostic.R"),
    run_bool  = run_12
  ),
  list(
    id_chr    = "20a",
    label_chr = "20a VZ historical minimum wage download",
    path_chr  = fs::path(path_code_chr,    "20a_download-minimum-wage.R"),
    run_bool  = run_20a
  ),
  list(
    id_chr    = "20b",
    label_chr = "20b Forward minimum-wage extension",
    path_chr  = fs::path(path_code_chr,    "20b_extend-minimum-wage-forward.R"),
    run_bool  = run_20b
  ),
  list(
    id_chr    = "20c",
    label_chr = "20c Binding-minimum panel build",
    path_chr  = fs::path(path_code_chr,    "20c_build-binding-minimum-panel.R"),
    run_bool  = run_20c
  ),
  list(
    id_chr    = "20d",
    label_chr = "20d Merge binding floor to CPS ORG",
    path_chr  = fs::path(path_code_chr,    "20d_merge-cps-binding.R"),
    run_bool  = run_20d
  ),
  list(
    id_chr    = "20e",
    label_chr = "20e Binding-minimum analysis and BLS validation",
    path_chr  = fs::path(path_code_chr,    "20e_binding-minimum-analysis.R"),
    run_bool  = run_20e
  ),
  list(
    id_chr    = "30",
    label_chr = "30 Auto-build figures summary markdown + HTML",
    path_chr  = fs::path(path_code_chr,    "30_build_summary.R"),
    run_bool  = run_30
  )
)

###################################
###   Preflight path checks     ###
###################################
# Verify that every script selected to run exists on disk before
# starting. Catching a typo'd path here is cheaper than discovering it
# mid-pipeline after a long-running upstream stage has completed.

missing_paths_chr <- character(0L)

for (stage_ls in stage_registry_ls) {
  if (isTRUE(stage_ls$run_bool) && !fs::file_exists(stage_ls$path_chr)) {
    missing_paths_chr <- c(missing_paths_chr, stage_ls$path_chr)
  }
}

if (length(missing_paths_chr) > 0L) {
  stop(
    "run_all.R -- the following script(s) are selected to run but do ",
    "not exist: ", paste(missing_paths_chr, collapse = "; ")
  )
}

###################################
###   Open session log          ###
###################################

log_header_chr <- c(
  paste0("# Pipeline Run -- ", run_date_chr),
  "",
  paste0("- **Orchestrator:** `code/run_all.R`"),
  paste0("- **Run start:** ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  paste0("- **R version:** ", R.version.string),
  paste0("- **Project root:** ", path_project_chr),
  "",
  "## Stage status",
  "",
  "| Stage | Enabled | Script | Elapsed (s) | Status |",
  "|-------|---------|--------|-------------|--------|"
)

writeLines(log_header_chr, con = run_log_path_chr)

message("run_all.R -- logging to ", run_log_path_chr)

###################################
###   Stage runner              ###
###################################

run_overall_start_posix <- Sys.time()
run_had_failure_bool    <- FALSE

for (stage_ls in stage_registry_ls) {

  if (!isTRUE(stage_ls$run_bool)) {
    stage_row_chr <- paste0(
      "| ", stage_ls$id_chr,
      " | FALSE | `", fs::path_rel(stage_ls$path_chr, path_project_chr),
      "` | -- | skipped |"
    )
    cat(stage_row_chr, "\n",
        file = run_log_path_chr, sep = "", append = TRUE)
    message("run_all.R -- [", stage_ls$id_chr, "] skipped (flag FALSE)")
    next
  }

  message(
    "run_all.R -- [", stage_ls$id_chr, "] starting: ",
    stage_ls$label_chr
  )

  stage_start_posix <- Sys.time()

  stage_status_chr <- tryCatch(
    {
      source(
        stage_ls$path_chr,
        local = new.env(parent = globalenv()),
        chdir = FALSE
      )
      "ok"
    },
    error = function(e) {
      paste0("ERROR: ", conditionMessage(e))
    }
  )

  stage_end_posix   <- Sys.time()
  stage_elapsed_num <- as.numeric(
    difftime(stage_end_posix, stage_start_posix, units = "secs")
  )

  stage_row_chr <- paste0(
    "| ", stage_ls$id_chr,
    " | TRUE | `", fs::path_rel(stage_ls$path_chr, path_project_chr),
    "` | ", format(round(stage_elapsed_num, 2), nsmall = 2L),
    " | ", stage_status_chr, " |"
  )
  cat(stage_row_chr, "\n",
      file = run_log_path_chr, sep = "", append = TRUE)

  if (!identical(stage_status_chr, "ok")) {
    message(
      "run_all.R -- [", stage_ls$id_chr, "] FAILED after ",
      round(stage_elapsed_num, 2L), "s: ", stage_status_chr
    )
    run_had_failure_bool <- TRUE
    # Stop at the first failure; downstream stages depend on upstream
    # output and would produce misleading errors.
    break
  }

  message(
    "run_all.R -- [", stage_ls$id_chr, "] done in ",
    round(stage_elapsed_num, 2L), "s"
  )
}

###################################
###   Finalise session log      ###
###################################

run_overall_end_posix    <- Sys.time()
run_overall_elapsed_num  <- as.numeric(
  difftime(run_overall_end_posix, run_overall_start_posix, units = "secs")
)

log_footer_chr <- c(
  "",
  paste0("- **Run end:** ", format(run_overall_end_posix, "%Y-%m-%d %H:%M:%S %Z")),
  paste0(
    "- **Total elapsed:** ",
    format(round(run_overall_elapsed_num, 2), nsmall = 2L), " seconds"
  ),
  paste0(
    "- **Overall status:** ",
    ifelse(run_had_failure_bool, "FAILED", "ok")
  )
)

cat(paste(log_footer_chr, collapse = "\n"), "\n",
    file = run_log_path_chr, sep = "", append = TRUE)

if (run_had_failure_bool) {
  stop(
    "run_all.R -- pipeline halted due to a stage failure; ",
    "see ", run_log_path_chr, " for details."
  )
}

message(
  "run_all.R -- pipeline complete in ",
  round(run_overall_elapsed_num, 2L), "s. Log: ", run_log_path_chr
)
