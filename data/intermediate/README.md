# Intermediate panel checkpoints

This directory holds the year-partitioned parquet checkpoints written between pipeline stages. The partitioned datasets are large and gitignored; only small summary CSVs are tracked because they document the construction of the wage panel.

## What is tracked

- `pareto_diagnostics.csv` — per (year, sex) summary of the Pareto topcode fit produced by `code/01b_build-org-panel.R`: number of rows in the fit window, OLS-estimated alpha, mean-above-topcode used to replace each topcoded observation, and a flag indicating whether the fit succeeded.
- `real_wage_summary_stats.csv` — per-year weighted summary statistics on the real-wage panel produced by `code/02a_build_real_wages.R`: count, mean, median, and selected percentiles of the real hourly and weekly wage columns.
- `real_wage_trim_counts.csv` — per-year row counts before and after the EPI outlier-bound trim in `code/02a_build_real_wages.R`, and the number of rows dropped at the lower and upper bounds. Lets a reader verify that the bounds are doing what the methodology says they are doing.
- `hours_missingness_diagnostics.csv` — per (year, `PAIDHOUR`, reason) counts of records whose usual hours were missing or reported as varying, and whether each group was imputed, produced by `code/01b_build-org-panel.R`.
- `deflator_gap_diagnostic.csv` — selected real-wage percentiles recomputed under PCE and CPI-U-RS, with the absolute and percent gap, produced by `code/11_deflator_gap_diagnostic.R`.

## What is gitignored

- `cps_org_panel/year=YYYY/part-0.parquet` and `.rds` — output of `code/01b_build-org-panel.R`. ORG sample gate, hours imputation, and Pareto-adjusted weekly wage applied. ~50-65 MB per year.
- `cps_real_wages/year=YYYY/part-0.parquet` and `.rds` — output of `code/02a_build_real_wages.R`. Real wages joined to PCEPI and EPI outlier bounds applied.

Both are regenerable end-to-end from the raw IPUMS extract by setting the appropriate flags in `code/run_all.R` and sourcing.
