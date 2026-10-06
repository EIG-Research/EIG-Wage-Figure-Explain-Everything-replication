# EPI State of Working America Data Library

This directory is the local landing zone for series downloaded from the Economic Policy Institute's State of Working America Data Library (https://www.epi.org/data/). The data are used by `code/10_epi_spot_checks.R` to validate the pipeline against EPI's published numbers.

## What is in the repository

Nothing. The series CSVs and the bundle ZIP are gitignored: most exceed GitHub's 100 MB limit because EPI publishes long-running demographic-by-month panels, and they are EPI's data to distribute.

## How to populate this directory

1. Visit the EPI State of Working America Data Library and download the bundle (or individual series) the analysis uses. The pipeline relies primarily on hourly-wage percentiles for the spot-checks in `10_epi_spot_checks.R`.
2. Place the CSVs in this directory (filenames matching EPI's distribution; for example, `hourly_wage_percentiles.csv`).
3. Optionally also place `epi_swa_data_library.zip` if you want to keep the bundle locally.

`code/10_epi_spot_checks.R` does not read the EPI series directly. It reads a small hand-built reference file, `output/verification/epi_reference_values.csv`, holding the specific year-by-percentile EPI values (rescaled to December 2025 PCE dollars) to compare against. That file ships with the repository.

## Citation

Economic Policy Institute. State of Working America Data Library. https://www.epi.org/data/. Accessed at the date of pipeline run. Cite the specific series (for example, "EPI State of Working America Data Library, Hourly Wage Percentiles") in any downstream report that uses the spot-check comparisons.
