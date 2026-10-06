# Decision 06 — EPI replication of post-2022 topcode handling (legacy Pareto extension plus rotation-group bridge)

- Status: Active
- Decided: 2026-05-15
- Decided by: Benjamin Glasner, EIG
- Affects: `code/01b_build-org-panel.R`; `data/intermediate/cps_org_panel/year=2023/` and `year=2024/`; every P90 (and higher) downstream of the topcode block for 2023 through 2025; diagnostic outputs at `output/tables/diagnostics/epi_bridge_diagnostics.csv`, `output/tables/diagnostics/epi_pareto_extended_diagnostics.csv`, `output/tables/diagnostics/figure_a_p90_three_specs_annual.csv`, and `output/tables/diagnostics/synthetic_pareto_quantile_sensitivity.csv` (retained for reference).

## Context

BLS replaced the fixed $2,884.61 weekly EARNWEEK topcode with a dynamic per-month topcode set to the weighted average of the top 3 percent of earners (EARNWEEK2) in April 2023. The dynamic values run roughly $5,000 to $13,000 per week. The transition also interacts with the CPS rotation: households appear in two outgoing rotation groups (MISH 4 and MISH 8) separated by 12 calendar months, and a household's second visit retains the topcode methodology of its first visit. In April 2023 through March 2024, MISH 4 records are reported under the new dynamic topcode and same-month MISH 8 records remain compressed at the legacy $2,884.61. The result is a 12-month transition window where the two rotation groups produce structurally different upper-tail values, plus a permanent regime change at 2022 to 2023 that mechanically raises P90 of the reported distribution without any change in underlying wages.

## Options considered

- Accept the regime break and apply no special handling — produces a visible 2022 to 2023 step in P90 plus a 12-month rotation-group seam.
- Synthetic Pareto P95 (the 2026-05-15 first-amendment draft, now removed): fit an OLS log-log Pareto on every post-2022 sex-year cell using the weighted 95th percentile as a pseudo-topcode threshold, then replace records at or above that quantile with the conditional mean. Implemented and then withdrawn after EPI code review.
- EPI replication: extend the legacy $2,884.60 Pareto adjustment through December 2024, mirror EPI's `tc_fix.do` rotation-group bridge for April 2023 through March 2024, accept raw values from April 2024 onward, accept raw values from January 2025 onward.
- Hourly-paid subsample only — restrict the published series to `PAIDHOUR == 2`, which is governed by the separate HOURWAGE topcode that did not change in 2023.

## Decision

Mirror EPI exactly. The legacy $2,884.60 weekly-wage topcode serves as the analytical threshold for the OLS log-log Pareto fit in every year 1998 through 2024, including 2023 and 2024. The post-Pareto rotation-group bridge then overwrites the subset of 2023m4 through 2024m12 records that BLS actually topcoded under the dynamic EARNWEEK2 regime, per `tc_fix.do`. From January 2025 onward, no Pareto adjustment is applied; raw weekly wages flow through unchanged.

The synthetic Pareto P95 draft is removed; the sensitivity diagnostic at `output/tables/diagnostics/synthetic_pareto_quantile_sensitivity.csv` is retained for reference.

## Rationale

EPI does not bridge the regime change with a single uniform imputation. Instead, `epiextracts/code/variables/generate_weekpay.do` keeps the legacy $2,884.60 topcode for the Pareto fit through December 2024, and `epiextracts/code/tc_fix.do` handles the rotation-group seam with a three-piece sequence: MISH 4 topcoded records get their raw weekly wage restored, MISH 8 topcoded records receive the EARNWT-weighted mean of same-month MISH 4 records with raw weekly wage at or above $2,884.60, and 2024m4 onward applies raw-restore with no MISH split. Following EPI exactly keeps the EIG series replicable against EPI's published State of Working America wage data and accepts the residual 2022 to 2023 step in P90 as the irreducible signature of the topcode regime change rather than as a methodological choice. The synthetic Pareto P95 alternative was rejected after EPI code review because it imputes upper-tail values where EPI accepts raw observations, which would silently diverge from the canonical reference.

## Implementation

- `code/01b_build-org-panel.R`, configuration block: `pareto_max_year_int <- 2024L` (raised from 2022). The legacy topcode lookup table extended to cover 2023 and 2024 at $2,884.60.
- `nominal_weekly_wage_raw_num` preserved before the Pareto pass overwrites `nominal_weekly_wage_num` for topcoded records, so the bridge block can reference raw values.
- Post-Pareto bridge block (step 8b in the per-year processing loop): for `yr %in% c(2023L, 2024L)`, loop over bridge months (2023m4 through 2024m3) and raw-restore months (2024m4 through 2024m12); MISH 4 topcoded records identified at the empirical month-max within the MISH 4 cell, MISH 8 topcoded records identified at or above the legacy $2,884.60 within $0.01 tolerance, donor pool restricted to same-month MISH 4 records with raw weekly wage at or above $2,884.60 and positive EARNWT.
- 2025 onward: `yr > pareto_max_year_int` skips the Pareto fit entirely; topcoded records (if any) remain at raw values with `pareto_topcode_imputed_flag = FALSE`.
- Bridge diagnostics: `output/tables/diagnostics/epi_bridge_diagnostics.csv` (per (year, month) bridge actions, counts, dynamic topcode values, bridge values).
- Extended Pareto diagnostics: `output/tables/diagnostics/epi_pareto_extended_diagnostics.csv` (first-pass fit results for 2023 and 2024 sex-year cells).
- Three-specification comparison tables: `output/tables/diagnostics/figure_a_p90_three_specs_annual.csv` and `figure_a_p90_three_specs_monthly.csv`.
- The synthetic Pareto P95 toggle (`apply_synthetic_pareto_post2022_bool`) was removed from `01b_build-org-panel.R` after the EPI review; the sensitivity CSV at `output/tables/diagnostics/synthetic_pareto_quantile_sensitivity.csv` is retained for historical reference.

## Trade-offs accepted

The EPI-mirror specification accepts a roughly 6-percent level shift in P90 from 2022 to 2023 as the irreducible signature of the BLS topcode regime change. That step is visible in every downstream figure that crosses the 2022 to 2023 boundary; figure notes must explain it as a measurement event rather than a wage event. The 2024 sex 1 cell relies more heavily on the rotation-group bridge than on the first-pass Pareto because the extended legacy fit produces alpha at or below 1 in that cell (the bin window between weighted P80 and the legacy topcode is too narrow to support stable OLS log-log on the BLS mass alone); the script logs `alpha_not_gt_1` and falls back to leaving records at the topcode for the first pass, with the bridge then overwriting the BLS-topcoded subset. From 2025m1 onward, the dynamic EARNWEEK2 topcode value flows through as the de facto cap on the reported distribution; no methodological choice can fully bridge the difference, and EPI accepts the raw values.

## References

- EPI `epiextracts`, `code/variables/generate_weekpay.do` (https://github.com/Economic/epiextracts).
- EPI `epiextracts`, `code/tc_fix.do` (https://github.com/Economic/epiextracts).
- EPI `epiextracts`, `code/variables/generate_tc_weekpay.do` (https://github.com/Economic/epiextracts).
- EPI `epiextracts`, `code/ado/topcode_impute.ado` (https://github.com/Economic/epiextracts).
- `code/01b_build-org-panel.R`, legacy topcode lookup, `pareto_max_year_int`, post-Pareto bridge block.
- `data/intermediate/pareto_diagnostics.csv`.
- `data/intermediate/topcode_detection_diagnostics.csv`.
- `output/tables/diagnostics/epi_bridge_diagnostics.csv`.
- `output/tables/diagnostics/epi_pareto_extended_diagnostics.csv`.
- `output/tables/diagnostics/figure_a_p90_three_specs_annual.csv`.
- `output/tables/diagnostics/synthetic_pareto_quantile_sensitivity.csv`.
- `p90_artifact_memo.md` (internal working file) — diagnostic memo documenting the regime change and the deprecated synthetic Pareto draft.
- `p90_series_memo_final.md` (internal working file) — synthesis memo confirming the EPI-mirror specification.
- IPUMS-CPS variable documentation for `EARNWEEK2`. https://cps.ipums.org/cps-action/variables/EARNWEEK2.
- Bollinger, Christopher R., Barry T. Hirsch, Charles M. Hokayem, and James P. Ziliak. "Trouble in the Tails? What We Know about Earnings Nonresponse 30 Years after Lillard, Smith, and Welch." *Journal of Political Economy* 127, no. 5, 2019.
