# Decision 05 — Uniform $200 / hour 1989-PCE upper outlier bound

- Status: Active
- Decided: 2026-05-15
- Decided by: Benjamin Glasner, EIG
- Affects: `code/02a_build_real_wages.R`; every percentile downstream of the outlier-bound block, especially P90 in 2023 through 2025; `output/tables/diagnostics/p90_upper_bound_sensitivity.csv`.

## Context

The EPI / SWA outlier-trim convention applies a $100 / hour upper bound in 1989 dollars deflated with CPI-U-RS (Schmitt 2003); EPI scales that bound by CPI-U-RS, not PCE. For reference, $100 in 1989 dollars is roughly $221.25 / hour in Dec 2025 PCE dollars. Under the legacy fixed $2,884.61 weekly EARNWEEK topcode (1998 through 2022), the $100 bound rarely binds on legitimate workers — all upper-bound drops had reported hours at or below 14. Under the dynamic EARNWEEK2 topcode (April 2023 onward, roughly $5,000 to $13,000 per week), full-time salaried workers at 40 hours can cross the $100 / hour 1989-PCE bound legitimately rather than as reporting errors, and the EPI $100 specification drops them. A specification that retains those workers is required, but the choice of how to retain them affects P90.

## Options considered

- Keep the EPI $100 / hour bound applied uniformly — drops legitimate full-time salaried workers post-2022.
- Hours-conditional gate: apply the $100 bound only when reported hours are below 20 — the 2026-04-24 specification, retained in earlier diagnostics. Effective drop rate jumps from 0.05 percent of weighted records pre-2023 to 1.27 percent in 2024, a discontinuity driven by the topcode regime change rather than by the underlying error pattern.
- Uniform $150 / hour 1989-PCE bound — drops 0.04 to 0.28 percent of records depending on year and attenuates 2022 to 2025 real P90 growth from plus 6.4 percent to plus 4.3 percent.
- Uniform $200 / hour 1989-PCE bound — drops 0.000 percent of weighted records in 2015 through 2024 and 0.014 percent in 2025. Annual P90 estimates match the prior hours-gated $100 specification to the cent across 2015 through 2025.

## Decision

Apply a uniform $200 / hour 1989-PCE upper bound, translating to $442.50 / hour in Dec 2025 PCE dollars. The bound applies regardless of reported hours, with no gating logic.

## Rationale

The uniform $200 bound is preferred for two reasons. First, it removes the specification-level discontinuity at the 2022 to 2023 boundary that the hours-conditional gate introduced. The gate's effective drop rate jumped from 0.05 percent pre-2023 to 1.27 percent in 2024, an artifact of the BLS topcode regime change rather than of the underlying error pattern; the uniform $200 bound trims a stable share (essentially zero) across the regime change. Second, a fixed threshold is simpler to document than a conditional rule and produces numerically identical annual P90 estimates to the prior hours-gated $100 specification, verified to the cent across 2015 through 2025 against `output/tables/diagnostics/p90_upper_bound_sensitivity.csv`. The lower bound remains at $0.50 / hour 1989-PCE, matching EPI.

## Implementation

- `code/02a_build_real_wages.R`, configuration block: `bound_lower_hourly_1989_num <- 0.50`, `bound_upper_hourly_1989_num <- 200`.
- Translation to Dec 2025 PCE dollars uses `pcepi_dec1989_base_num`, the PCEPI(Dec 1989) / PCEPI(Dec 2025) ratio, computed once at script start.
- Bounds applied to the hourly wage (not the weekly wage), per Schmitt 2003 CEPR convention. For hourly-paid workers (`PAIDHOUR == 2`) the hourly wage is `HOURWAGE_CANON_NUM`; for salaried workers (`PAIDHOUR == 1`) the hourly equivalent is `EARNWEEK_CANON_NUM / hours_for_bound`, with a 40-hour fallback for salaried records with missing or zero hours.
- Drops counted as `n_dropped_low_int` and `n_dropped_high_int` in `data/intermediate/real_wage_trim_counts.csv`.
- Sensitivity diagnostic: `output/tables/diagnostics/p90_upper_bound_sensitivity.csv` confirms numerical equivalence with the prior hours-gated $100 specification.

## Trade-offs accepted

The $200 bound is higher than EPI's published $100 bound, which means the EIG series retains observations EPI would trim. The difference is empirically small in P50 and below, but it is real for P90 in years where high salaried earners cross the $100 line at 40 hours. Choosing the higher uniform bound is a deliberate substantive call: the post-EARNWEEK2 distribution shows legitimate workers above the $100 line, and trimming them mechanically biases P90 downward. A future reviewer who prefers tighter trimming can flip the constant to 150 or 100 and re-run; the diagnostic CSV exposes the implied numerical impact.

## References

- `code/02a_build_real_wages.R`, bound-definition block at lines 73 through 134.
- `output/tables/diagnostics/p90_upper_bound_sensitivity.csv`.
- `p90_artifact_memo.md` (internal working file) — the diagnostic memo that surfaced the hours-gated specification's discontinuity.
- `p90_series_memo_final.md` (internal working file) — synthesis memo confirming numerical equivalence with the prior specification.
- Schmitt, John. "Creating a Consistent Hourly Wage Series from the Current Population Survey's Outgoing Rotation Group, 1979-2002." Center for Economic and Policy Research, 2003.
