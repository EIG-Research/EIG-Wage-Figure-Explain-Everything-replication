# Decision 03 — Retain BLS-allocated earnings records

- Status: Active
- Decided: 2026-04-30
- Decided by: Benjamin Glasner, EIG
- Affects: `code/01b_build-org-panel.R`; the 2001 through 2002 segment of every percentile series in Figures A, B, and C; subgroup wage gaps in any downstream analysis that disaggregates by demographic cells.

## Context

The EPI State of Working America wage-analysis convention, inherited from the CEPR construction (Schmitt 2003), excludes records whose primary earnings variable was allocated by BLS. The harmonized IPUMS-CPS Q-flags (`QEARNWEE` for weekly, `QHOURWAG` for hourly) carry the allocation indicator; non-zero values mark records that BLS imputed via hot-deck. BLS reactivated public-use allocation flags in January 2002 after the post-1994 CAPI gap, which produces a step change in the non-zero-flag share from roughly 12 percent in 2001 to roughly 32 percent in 2002. Applying the SWA drop rule mechanically removes about 20 percent of records starting January 2002 and produces a structural break in the percentile series at exactly that month that does not appear in EPI's published State of Working America series.

## Options considered

- Apply the EPI SWA / CEPR drop rule — exclude every record with non-zero `QEARNWEE` or `QHOURWAG` on its primary wage variable.
- Retain all records regardless of allocation status, matching the EPI `epiextracts` extract retention rule (the extract keeps `a_weekpay` and `a_earnhour` as 0/1 indicators rather than dropping).
- Retain allocated records but down-weight them in downstream percentile estimation.
- Retain allocated records and exclude only the post-2001 allocation regime.

## Decision

Retain all records regardless of allocation status, matching the `epiextracts` extract retention rule. The SWA drop rule is implemented in code for diagnostic logging but is disabled in production by `apply_allocation_flag_drop_bool <- FALSE`.

## Rationale

EIG's intent is to mirror current EPI `epiextracts` rather than the older SWA drop convention. The `epiextracts` repository itself does not drop allocated records — `code/variables/generate_a_weekpay.do` and `code/variables/generate_a_earnhour.do` produce 0/1 indicator columns that downstream analysts can apply or ignore. The SWA drop is an analysis convention layered on top of the extract; choosing the extract-retention rule is the more conservative interpretation of "replicate EPI." Empirically, retention reproduces EPI's published 2001 through 2002 percentile trajectory within rounding (real P90 plus 1.9 to 2.1 percent year over year, matching EPI's published 1.90 percent), while the SWA drop produces a real P90 of plus 9.75 percent year over year in 2002 that is absent from EPI's series. The retention rule is therefore the choice that recovers EPI's headline numbers.

## Implementation

- `code/01b_build-org-panel.R`, configuration block: `apply_allocation_flag_drop_bool <- FALSE` (production default).
- Step 1c in the per-year loop computes the drop mask regardless of the toggle so the run log reports how many rows the SWA rule would have removed; the panel is filtered only when the toggle is `TRUE`.
- The January 1994 through August 1995 allocation-flag gap is retained unconditionally per EPI documentation.
- Q-flag columns are pulled by `code/00a_download-ipums-cps.R` with `data_quality_flags = TRUE` and harmonized to `QEARNWEE` and `QHOURWAG` by IPUMS.

## Trade-offs accepted

Retaining allocated records means hot-deck-imputed earnings enter the percentile estimates. Hirsch and Schumacher 2004 document that match bias in subgroup wage gaps follows from this inclusion — for example, union and non-union wage premiums measured on allocated data are attenuated toward the overall mean. For population-level percentiles the bias is small, but any subgroup figure that disaggregates by demographic cell should report the share of allocated records per cell as a diagnostic. The 2023 P90 gap of roughly 7.4 percent against EPI's published series is consistent with the Bollinger, Hirsch, Hokayem, and Ziliak 2019 documented 3 to 8 percent upward shift from retaining allocated records.

## References

- EPI `epiextracts`, `code/variables/generate_a_weekpay.do` (https://github.com/Economic/epiextracts).
- EPI `epiextracts`, `code/variables/generate_a_earnhour.do` (https://github.com/Economic/epiextracts).
- `code/01b_build-org-panel.R`, allocation-flag block in the per-year loop.
- `code/00a_download-ipums-cps.R`, `data_quality_flags = TRUE` switch.
- IPUMS-CPS variable documentation for `QEARNWEE` and `QHOURWAG`. https://cps.ipums.org/cps-action/variables/QEARNWEE; https://cps.ipums.org/cps-action/variables/QHOURWAG.
- EPI microdata wage variables documentation. https://microdata.epi.org/methodology/wagevariables/.
- Schmitt, John. "Creating a Consistent Hourly Wage Series from the Current Population Survey's Outgoing Rotation Group, 1979-2002." Center for Economic and Policy Research, 2003.
- Hirsch, Barry T., and Edward J. Schumacher. "Match Bias in Wage Gap Estimates Due to Earnings Imputation." *Journal of Labor Economics* 22, no. 3, 2004.
- Bollinger, Christopher R., Barry T. Hirsch, Charles M. Hokayem, and James P. Ziliak. "Trouble in the Tails? What We Know about Earnings Nonresponse 30 Years after Lillard, Smith, and Welch." *Journal of Political Economy* 127, no. 5, 2019.
