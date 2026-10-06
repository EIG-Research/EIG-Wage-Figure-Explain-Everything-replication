# Decision 04 — Replace stratified OLS hours imputation with a per-year random forest

- Status: Active
- Decided: 2026-05-15
- Decided by: Benjamin Glasner, EIG
- Affects: `code/00a_download-ipums-cps.R` (added `CITIZEN`, `IND1990`, `UNION` to the extract); `code/01a_load-ipums-cps.R`; `code/01b_build-org-panel.R`; `data/intermediate/hours_rf_diagnostics.csv`; `data/intermediate/hours_rf_feature_importance.csv`; hourly wage estimates for the roughly 5 to 7 percent of ORG records reported as "hours vary."

## Context

Salaried workers whose usual hours are coded "hours vary" (`UHRSWORK1 == 997` or `UHRSWORKORG == 997`) have no reported denominator for the implied hourly wage. EPI imputes hours via four stratified OLS regressions in `generate_hoursu1i.do`, with strata defined by sex by full-time / part-time intent (`hoursuint`), and covariates `AGE` polynomial plus `EDUC` plus `WBHO` plus `CITISTAT` plus `MARRIED` plus `STATEFIPS` plus `UNION` plus `PUBSEC` plus `MIND16`. The BLS full-time / part-time-intent variable EPI uses for stratification is not exposed in IPUMS-CPS, which forces a methodological choice.

## Options considered

- Reproduce the EPI four-stratum OLS specification exactly, treating IPUMS-CPS variables as proxies for the BLS strata where the underlying variable is unavailable.
- Pool to a single OLS regression with stratifying variables entered as covariates.
- Replace the parametric model with a per-year non-parametric ensemble (random forest) on a 12-feature set that covers every EPI covariate via either a direct IPUMS counterpart or a close substitute.
- Skip imputation entirely and drop hours-vary records from the analytical sample.

## Decision

Replace EPI's stratified OLS with a per-year `ranger::ranger` random forest fit on a 12-feature set (`AGE`, `SEX`, `EDUC`, `RACE`, `HISPAN`, `MARST`, `STATEFIP`, `CLASSWKR`, `OCC2010`, `CITIZEN`, `IND1990`, `UNION`), weighted by `EARNWT`, with hyperparameters locked at the defaults specified below. The fit runs once per year on training rows that report valid hours and are not flagged as allocated, then predicts hours for hours-vary records in that year.

## Rationale

Random forest captures interaction structure and non-linearities without requiring the analyst to specify an explicit stratification on a variable that IPUMS does not expose. The four-way sex by full-time / part-time-intent stratification EPI uses is approximated in expectation by data-driven splits on `SEX` combined with continuous and categorical features that vary with full-time / part-time intent (`OCC2010`, `IND1990`, `CLASSWKR`, `AGE`). Per-year fits accommodate slow drift in the hours distribution without manual retuning. The hours-vary share is roughly 5 to 7 percent of the ORG sample, dispersed across the wage distribution, so per-year random-forest predictions affect P10 through P90 only at the margin. Hyperparameters are locked at sensible defaults (`num.trees = 500`, `mtry = floor(sqrt(p))`, `min.node.size = 5`, `splitrule = "variance"`, `seed = 42`, `num.threads = 1`) so the imputation is fully deterministic under `set.seed(42)` and does not drift across runs.

## Implementation

- `code/00a_download-ipums-cps.R` adds `CITIZEN`, `IND1990`, `UNION` to the IPUMS extract variables list.
- `code/01b_build-org-panel.R`, configuration block: `hours_min_training_rows_int <- 500L`, `hours_rf_num_trees_int <- 500L`, `hours_rf_min_node_size_int <- 5L`, `hours_rf_seed_int <- 42L`, `hours_rf_num_threads_int <- 1L`, `hours_lower_bound_num <- 1`, `hours_upper_bound_num <- 99`.
- Per-year ranger fit block in step 4 of the per-year processing loop in `01b_build-org-panel.R`; categorical features are recoded with explicit `NIU` levels so ranger handles missingness via an explicit factor level rather than via surrogate splits.
- Predictions are clamped to [1, 99] hours, matching EPI's clamp in `generate_hoursu1i.do`.
- Imputed rows are flagged with `hours_imputed_flag = TRUE`.
- Per-year fit diagnostics (OOB R-squared, OOB MSE, training row count, imputed row count, mtry) written to `data/intermediate/hours_rf_diagnostics.csv`.
- Per-(year, feature) impurity-based importance written to `data/intermediate/hours_rf_feature_importance.csv`.

## Trade-offs accepted

The random forest does not reproduce the EPI specification line for line; the OLS coefficients EPI reports are not interpretable analogues of the random-forest predictions. The trade-off is correct for the project: the IPUMS-exposed feature set is not perfectly aligned with EPI's BLS covariates, and pretending otherwise by forcing a parametric specification on a different variable set would produce a comparable bias with worse predictive fit. Per-year OOB R-squared values in the 0.28 to 0.33 range are similar to the predictive performance of the prior pooled-OLS implementation, so the imputation quality is preserved. The 12-feature random forest is also more transparent about its assumptions: the feature importance CSV exposes which covariates carry the prediction in each year, and a future analyst can audit whether a feature collapses unexpectedly.

## References

- EPI `epiextracts`, `code/variables/generate_hoursu1i.do` (https://github.com/Economic/epiextracts).
- `code/00a_download-ipums-cps.R`, variables list at the configuration block.
- `code/01b_build-org-panel.R`, RF hours imputation parameters block and step 4 of the per-year loop.
- `data/intermediate/hours_rf_diagnostics.csv`.
- `data/intermediate/hours_rf_feature_importance.csv`.
- IPUMS-CPS variable documentation for `UHRSWORK1` and `UHRSWORKORG`. https://cps.ipums.org/cps-action/variables/UHRSWORK1; https://cps.ipums.org/cps-action/variables/UHRSWORKORG.
- Wright, Marvin N., and Andreas Ziegler. "ranger: A Fast Implementation of Random Forests for High Dimensional Data in C plus plus and R." *Journal of Statistical Software* 77, no. 1, 2017.
