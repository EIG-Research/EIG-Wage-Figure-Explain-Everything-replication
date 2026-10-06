# Decision 02 — Drop the 1.5-times-topcode Pareto fallback

- Status: Active
- Decided: 2026-04-22
- Decided by: Benjamin Glasner, EIG
- Affects: `code/01b_build-org-panel.R`; `data/intermediate/pareto_diagnostics.csv`; every percentile downstream of the Pareto block, especially upper-tail percentiles in pre-1989 cells where alpha estimation is most fragile.

## Context

When the sex-year Pareto fit fails — most commonly because the OLS log-log regression returns alpha at or below one, which makes the conditional-mean formula undefined — the analyst must decide what to do with topcoded records in that cell. The CEPR and earlier EPI State of Working America convention (Schmitt 2003) substitutes `1.5 * topcode` for the topcoded value. The current EPI `epiextracts` codebase (`code/ado/topcode_impute.ado`) has no such fallback; topcoded records simply remain at the reported topcode value when the fit fails.

## Options considered

- Use `1.5 * topcode` as a closed-form fallback when alpha fails — the CEPR / Schmitt 2003 convention.
- Leave topcoded records at the reported topcode value and flag them as un-imputed — current EPI `epiextracts` behavior.
- Use a year-pooled or sex-pooled alpha as a fallback fit before falling back further.

## Decision

Match current EPI: when the OLS log-log fit fails or yields alpha at or below one, topcoded observations remain at the reported topcode value with `pareto_topcode_imputed_flag = FALSE`. No `1.5 * topcode` substitution is performed anywhere in the pipeline.

## Rationale

The current EPI `epiextracts` repository is the canonical implementation EIG mirrors, and `code/ado/topcode_impute.ado` does not implement the `1.5 * topcode` fallback. The topcoding literature provides no theoretical defense of the 1.5 multiplier: Burkhauser, Feng, Jenkins, and Larrimore 2011 and Bollinger, Hirsch, Hokayem, and Ziliak 2019 both treat reported-topcode retention as the appropriate fallback when a parametric fit is unavailable, because the 1.5 multiplier is sensitive to the underlying tail shape and can over- or under-state the conditional mean by a wide margin. Leaving the record at topcode preserves an honest signal for downstream readers that the upper-tail value is censored, and the flag column documents which observations are affected.

## Implementation

- `code/01b_build-org-panel.R`, Pareto fit block: when `alpha_num` is non-finite or at or below one, the cell's diagnostics row is written with `fit_status = "alpha_not_gt_1"` and topcoded rows for that sex-year remain unchanged.
- No fallback substitution exists anywhere in `01b_build-org-panel.R`; the absence is intentional and is verified by the diagnostic CSV at `data/intermediate/pareto_diagnostics.csv`, which exposes `n_left_at_topcode_int` alongside `n_imputed_int`.
- The flag column `pareto_topcode_imputed_flag` is `TRUE` only where a successful Pareto fit replaced the reported value.

## Trade-offs accepted

The pipeline produces fewer imputed values in cells where the fit fails — most often pre-1989 sex-year cells where the $999 topcode mass is concentrated. P90 and P95 in those cells reflect the censored topcode value, which understates the true upper tail. The trade-off is in favor of transparency: the flag column makes the censoring auditable, and the diagnostic CSV reports both successful fits and failed fits per cell.

## References

- EPI `epiextracts`, `code/ado/topcode_impute.ado` (https://github.com/Economic/epiextracts).
- `code/01b_build-org-panel.R`, Pareto fit block in the per-year processing loop.
- `data/intermediate/pareto_diagnostics.csv`.
- Schmitt, John. "Creating a Consistent Hourly Wage Series from the Current Population Survey's Outgoing Rotation Group, 1979-2002." Center for Economic and Policy Research, 2003.
- Burkhauser, Richard V., Shuaizhang Feng, Stephen P. Jenkins, and Jeff Larrimore. "Estimating Trends in U.S. Income Inequality Using the Current Population Survey: The Importance of Controlling for Censoring." *Journal of Economic Inequality* 9, no. 3, 2011.
- Bollinger, Christopher R., Barry T. Hirsch, Charles M. Hokayem, and James P. Ziliak. "Trouble in the Tails? What We Know about Earnings Nonresponse 30 Years after Lillard, Smith, and Welch." *Journal of Political Economy* 127, no. 5, 2019.
