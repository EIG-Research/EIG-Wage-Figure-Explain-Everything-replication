# Decision 10 — Index the COVID-19 aftermath chart to January 2022, after the COVID composition effect had largely cleared

- Status: Active (the March 2020 start month below is superseded by the 2026-10-07 addendum at the end of this memo: the era now starts February 2020)
- Decided: 2026-09-29
- Decided by: Benjamin Glasner, EIG
- Affects: `code/figure_a_percentiles.R` (step 8e, `covid_aftermath` era), `code/figure_a_datawrapper_publish.R` (`figure_a_indexed_covid_aftermath`), and that era's PNG, CSV sidecars, and Datawrapper chart.
- Evidence: `code/12_covid_composition_diagnostic.R` and its outputs, `output/tables/diagnostics/covid_composition_gap_monthly.csv` and `output/figures/diagnostics/covid_composition_gap.png`.

## Context

The COVID-19 aftermath chart shows 12-month rolling averages of the five wage percentiles
from March 2020 to the latest month. It was previously indexed to its start month
(February 2020). The goal is to index it to the start of the period after the COVID-19
composition effect: in 2020 low-wage workers lost jobs disproportionately, which raised
measured wage percentiles without raising anyone's pay.

The monthly data suggest the effect had faded by about January 2021: the monthly median
jumped from $24.66 in March 2020 to $27.09 in April 2020 and was back to $24.83 by January
2021. But the chart's anchor is a 12-month rolling average, and the January 2021 value
averages February 2020 through January 2021, nine of whose months sit inside the spike. An
inflated anchor makes later growth look smaller.

## Measurement

`12_covid_composition_diagnostic.R` reweights each month's workers to the pooled 2019
workforce on occupation major group (22 groups), education (4 bins), age (6 bins), and sex,
by raking the earnings weights to those four marginals, and recomputes the percentiles. The
gap between actual and reweighted percentiles is the part of the level explained by who was
working. The gap drifted upward before COVID (0.3 to 0.8 log points a year, by percentile)
as the workforce shifted toward higher-paid occupations and more education, so the COVID
effect is the excess over a linear 2016–2019 trend, smoothed with the Decision 08 12-month
window to match the chart.

12-month rolling excess composition gap, log points (pre-COVID noise band in parentheses):

| Percentile | Peak (early 2021) | January 2021 | January 2022 |
|---|---|---|---|
| P10 | 1.8 | 1.6 | 0.1 (±0.4) |
| P25 | 2.6 | 2.3 | −0.2 (±0.8) |
| Median | 4.0 | 3.4 | 1.6 (±0.4) |
| P75 | 2.9 | 2.8 | 0.8 (±0.4) |
| P90 | 2.9 | 2.8 | 0.7 (±0.4) |

## Options considered

- **January 2021.** The monthly spike has faded, but the rolling base still carries 1.6 to
  3.4 log points of composition effect. Rejected.
- **January 2022 (chosen).** Every percentile has shed at least 60 percent of its peak
  effect; P10 and P25 are inside their pre-COVID band. It is also the first month after the
  repo's existing March 2020–December 2021 dashed COVID span, so the charts stay consistent.
- **April 2022.** The strictest reading of the metric: P90 enters its band and the median
  and P75 have leveled off. It differs from January 2022 by under one index point at every
  percentile and breaks the alignment with the dashed span. Rejected.

## Decision

The `covid_aftermath` era keeps its window at **March 2020 to the latest month** and is
**rebased to January 2022 = 100**. Its start moves from February to March 2020, the first
COVID month, matching the dashed span and Figure 6 era 5.

## Honest caveats

- **The median and P75 never fully return to trend.** From early 2022 they level off about
  1 and 0.8 log points above it, which looks like a lasting shift in who is working rather
  than a fading shock. The January 2022 anchor does not remove that residual.
- **Observables only.** Composition changes within a cell (for example, the lowest-paid
  workers in an occupation losing their jobs) are not captured, so the true effect is
  probably larger and longer-lasting than measured here.
- **Trend extrapolation.** The excess depends on extending the 2016–2019 linear trend. By
  2024–2025 the excess wanders within about ±2 log points, which likely reflects trend
  error rather than COVID.
- **Wage heaping.** Wages bunch at round dollar amounts, so the monthly gap moves in steps;
  only the 12-month mean should be read.

## Verification

- `12_covid_composition_diagnostic.R` warns (without halting the pipeline) if the January
  2022 rolling base retains more than half of any percentile's peak effect. At adoption it
  retains at most 40 percent.
- The `covid_aftermath` roll12 CSV equals 100 at every percentile in January 2022.
- Latest index (July 2026), January 2022 = 100: P10 108.5, P25 105.7, median 102.8, P75
  103.3, P90 108.1.

## Addendum, 2026-10-07: era boundary moves to the NBER peak month

- Decided by: Benjamin Glasner, EIG
- Supersedes only the start month in the Decision section above. The anchor decision
  (January 2022 = 100) and everything else in this memo stand.

The `covid_aftermath` era now starts **February 2020**, not March 2020, and the
`recovery` era ends **January 2020**, not February 2020. February 2020 is the NBER business-cycle
peak, so the aftermath era begins in the NBER peak month, the same convention as the
second long wage stagnation (March 2001). It is also the era-5 start the AWP comparison
already used, so the repo's eras and AWP's eras now share boundaries.

- **Unchanged:** the March 2020 to December 2021 dashed COVID span. It marks the months
  when COVID-driven changes in CPS sample composition confound the percentiles, not an era
  boundary, so February 2020 stays a bridge month in the dashed series. The January 2022
  anchor is a 12-month window (February 2021 to January 2022) and does not depend on the era
  start.
- **Reversal of the Decision section's "matching the dashed span":** the era start no
  longer coincides with the dashed span's first month. The two serve different purposes.
- **Affects:** `code/figure_a_percentiles.R` (step 8e, `recovery` and `covid_aftermath`),
  `code/figure_f_era_bars_tables.R` (`era_specs_df` eras 4 and 5), and every output built
  from the era table: Figures 6a-6c, Figure 7 (era timeline), Figure H (sex gap by era),
  their CSVs, and the `recovery` and `covid_aftermath` charts.
- **Effect on era 4 and era 5 (median, 12-month rolling):** era 4 is 63 months (was 64),
  annualized growth 1.81 percent (was 1.82), average unemployment 4.4 percent. Era 5 is 79
  months (was 78), annualized growth 1.01 percent (was 0.97), average unemployment 4.8
  percent.
