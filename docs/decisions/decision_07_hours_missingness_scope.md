# Decision 07 — Hours-missingness imputation scope (don't-know extension), the NIU investigation, and verification that pre-1994 salaried workers are NOT excluded

- Status: Active
- Decided: 2026-06-04
- Decided by: Benjamin Glasner, EIG
- Affects: `code/01b_build-org-panel.R` (hours classification and RF imputation scope, new `hours_missingness_diagnostics.csv`); `code/02a_build_real_wages.R` (new trim-count column `n_salaried_no_hours_hourly_na_int`); the salaried share of the hourly figures (A, B, C, E).

## Context

For salaried workers (`PAIDHOUR == 1`) the hourly wage is weekly earnings divided by usual weekly hours; when usual hours are not a usable positive number the hourly wage is `NA` and the worker drops out of the hourly series (they remain in the weekly series). A review raised the concern that workers might be *systematically* excluded — in particular salaried workers before 1994, when the main-job usual-hours variable was thought to be unavailable. This decision records (1) the investigation into not-in-universe (NIU) hours, (2) direct data verification that the feared pre-1994 exclusion does NOT occur, and (3) the per-reason classification, diagnostic, and don't-know imputation extension that were added.

## How EPI sources salaried hours

EPI uses the earner-study usual-hours question, which covers all earners (not only hourly):

- 1973–1978: `hoursumay = wkhrswk` (May supplement).
- 1979–1993: `hoursuorg = ernush` (the earner-study usual hours for all ORG earners).
- 1994+: `peernhro` (the ORG hours field, "only defined for some hourly workers" per EPI's own comment) with a fallback to `hoursu1 = pehrusl1` (basic-monthly usual hours) for everyone else, plus `hoursu1i` for hours-vary records.

Source: `epiextracts/code/variables/generate_hoursuorg.do`, `generate_hoursumay.do`, `generate_hoursu1.do`, `generate_wage.do`.

## The NIU investigation — how a worker with valid salary can also be NIU on hours

The two IPUMS hours variables have different universes (IPUMS-CPS documentation):

- **UHRSWORKORG** — universe "Employed civilians 15+ in outgoing rotation groups that were paid by the hour; excludes the self-employed," available 1989+. It is an **hourly-paid-only** field and is **not a salaried-hours source in any year**. https://cps.ipums.org/cps-action/variables/UHRSWORKORG.
- **UHRSWORK1** — labeled "usual hours, main job," but its universe for 1982–1993 is "employed civilians 15+ in outgoing rotation groups, excluding the self-employed" — i.e., **all ORG earners, including salaried**. IPUMS explicitly states the early-year ORG hours are "included in UHRSWORK1 instead of UHRSWORKORG." Codes: 997 = hours vary, 999 = NIU. https://cps.ipums.org/cps-action/variables/UHRSWORK1.

So "valid salary + NIU hours" arises in two ways, only one of which is even a question:

1. **Salaried worker, NIU on UHRSWORKORG — routine and benign.** Every salaried worker is NIU on UHRSWORKORG by construction. The pipeline already handles it: `coalesce(UHRSWORK1, UHRSWORKORG)` sources salaried hours from UHRSWORK1. This is the IPUMS-native equivalent of EPI's `ernush` (pre-1994) and `hoursu1`-fallback (1994+) logic.
2. **Salaried worker, NIU on UHRSWORK1 with valid earnings — essentially empty.** A worker with valid earnings is employed and therefore in the UHRSWORK1 universe, so they are not NIU on it. Any residual is a rare artifact, not a population to model.

**The feared third case — pre-1994 salaried workers having no hours source — does not occur.** It rested on the assumption that UHRSWORK1 is unavailable before 1994. The data refute that assumption (see verification below).

## Verification (direct data inspection)

`temp/hours_coverage_probe.py` reads the raw ORG partitions and measures, among salaried (`PAIDHOUR == 1`) wage-and-salary earners, the share with usable primary hours:

| Year | Salaried earners | UHRSWORK1 valid (1–99) | Usable primary hours |
|------|------------------|------------------------|----------------------|
| 1983 | 72,326 | 99.9% | 99.9% |
| 1985 | 74,285 | 99.9% | 99.9% |
| 1988 | 69,307 | 99.9% | 99.9% |
| 1990 | 80,941 | 100.0% | 100.0% |
| 1993 | 75,574 | 100.0% | 100.0% |
| 1994 | 71,338 | 94.3% | 94.3% (remainder = 997 "hours vary," imputed) |
| 2000 | 69,025 | 93.4% | 93.4% (remainder = 997 "hours vary," imputed) |

Conclusion: salaried earners have usable usual hours throughout 1982–1993 via UHRSWORK1. There is **no systematic pre-1994 exclusion** and **no divergence from EPI** on this point — the repo's coalesce already mirrors EPI's earner-study sourcing. The only genuine salaried missing-hours cases are post-1994 "hours vary" records, which the random-forest imputation already repairs.

## Decision

1. Classify every missing-hours row by reason: `vary` (997), `dont_know` (UHRSWORKORG 998), `niu` (999), or `other_missing`.
2. Set `hours_impute_reasons_chr <- c("vary", "dont_know")`. The don't-know extension is a small **completeness** improvement: it imputes the rare salaried record that is missing UHRSWORK1 and carries a UHRSWORKORG "Don't know." Given the coverage above, its effect on the series is expected to be minor.
3. Exclude `niu` and `other_missing` from imputation: NIU on hours for salaried workers is a structural universe artifact (UHRSWORKORG is hourly-only), not random non-response, and a model trained on workers who report hours would fabricate values.
4. Write `data/intermediate/hours_missingness_diagnostics.csv` (year x pay type x reason x imputed status x count) and add `n_salaried_no_hours_hourly_na_int` to `data/intermediate/real_wage_trim_counts.csv`, so the (small) residual exclusion is measured on every run rather than assumed.

## Implementation

- `code/01b_build-org-panel.R`: `hours_impute_reasons_chr` constant; raw-code capture before the NA sentinel; `hours_missing_reason_chr` classification; `alloc_hours_bool` selects in-scope reasons; per-year diagnostic accumulator.
- `code/02a_build_real_wages.R`: per-year count of salaried rows retained but excluded from the hourly series.
- Revert path: set `hours_impute_reasons_chr <- c("vary")` to restore the prior production behavior exactly.

## Trade-offs and required validation

- The don't-know extension changes the reported hourly series, though by a small amount given the verified coverage. A full pipeline rerun, inspection of `hours_missingness_diagnostics.csv` and `real_wage_trim_counts.csv`, and a pass of `10_epi_spot_checks.R` are still required before publishing figures built under this change.
- The earlier "pre-1994 salaried coverage gap" concern is **withdrawn**; it was based on a documentation universe note for UHRSWORKORG and the misleading "(1994+)" label on UHRSWORK1, both corrected in code comments. The data show no gap.

## References

- `temp/hours_coverage_probe.py` (the verification script; safe to delete).
- `code/01b_build-org-panel.R`, hours classification block and `hours_impute_reasons_chr`.
- `code/02a_build_real_wages.R`, salaried-no-hours trim count.
- IPUMS-CPS, "UHRSWORKORG." https://cps.ipums.org/cps-action/variables/UHRSWORKORG.
- IPUMS-CPS, "UHRSWORK1." https://cps.ipums.org/cps-action/variables/UHRSWORK1.
- EPI epiextracts, `code/variables/generate_hoursuorg.do`, `generate_hoursumay.do`, `generate_hoursu1.do`, `generate_hoursu1i.do`, `generate_wage.do`.
- `docs/decisions/decision_04_random_forest_hours_imputation.md`.
