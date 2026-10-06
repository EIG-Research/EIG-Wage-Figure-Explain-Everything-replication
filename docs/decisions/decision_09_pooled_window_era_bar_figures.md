# Decision 09 — Figure 6 follows the repo wage standard (decision-08 smoother, partial windows, start-month era anchors); the AWP pooled-window definition is reversed; bars show cumulative change

- Status: Active. Revised 2026-09-29, which reverses the same-day first version.
- Decided: 2026-09-29
- Decided by: Benjamin Glasner, EIG
- Supersedes: the first version of this memo, which scoped a pooled 12-month window to Figure 6.
- Affects: `code/figure_f_era_bars_tables.R`, `code/figure_f_era_bars.R`, and the `output/tables/figure_f_*.csv` and `output/figures/figure_f_era_bars_*.png` outputs.
- Evidence:
  - `output/tables/figure_f_awp_definition_comparison.csv` (repo standard vs. AWP definition, series × era)
  - `output/tables/figure_f_awp_reference_check.csv` (the AWP definition, rebuilt here, still reproduces all 72 AWP reference values)

## Context

Figures 6a–6c rebuild slides 12–14 of the EIG American Worker Project (AWP) slim deck:
- 6a: real wage percentiles
- 6b: wage ratios
- 6c: median wage by education third

Each figure has an indexed line panel over era bars. The AWP specification defined four
things differently from this repository:

| # | Item | AWP definition | Repo standard |
|---|---|---|---|
| B1 | Estimator | One weighted quantile of the pooled trailing 12 months | Decision 08: flat 12-month trailing mean of monthly quantiles |
| B2 | Window resolution | Needs 11 of 12 months; nothing before December 1982 | Partial windows allowed; missing months drop out |
| B3 | Era anchoring | Chained from the window before each era starts, so the bars multiply exactly to the line | `figure_a_percentiles.R` step 8e: each era is measured from its own start month |
| B4 | Bar metric | Cumulative change | Figure 5d plots annualized growth |

The first version of this memo kept the AWP definitions for B1–B4. The owner then directed
that this repository's wage analysis is the reference standard, and that the AWP repository
should adopt its conventions.

## Decision

- **B1–B3: adopt the repo standard.** The decision-08 rolling mean, partial windows, and
  start-month era anchors replace the AWP definitions.
- **Ratios.** The ratios are formed from the smoothed percentiles, so
  90/10 = 50/10 × 90/50 still holds exactly in every month and in every era.
- **B4: keep cumulative bars.** Figure 5d's annualized convention was tried and rejected by
  the owner after comparing both renders. The bars show cumulative change within each era;
  the annualized rate is stored in the era tables.
- **The AWP definition** is rebuilt in step 11 of the table script as a comparison only.
  Nothing plotted uses it.

## Consequences

- Figure 6a's lines are identical to Figure 1b's 12-month rolling-average series: maximum
  difference 0 across the 513 months both publish.
- **The bars no longer multiply exactly to the whole-period change.** Adjacent eras are
  anchored one month apart, which leaves four one-month seams. The largest gap is
  1.7 index points.
- **Values move relative to the AWP deck.**
  - Cumulative era change moves by up to 1.84 pp. For example, P10 in the COVID-19
    aftermath is 19.0% here vs. 18.1% in AWP.
  - Latest index values move by up to 3.4 points. For example, P10 is 153.8 vs. 150.4, and
    50/10 is 91.0 vs. 93.1.
  - All headline claims still hold and are asserted in code.
- The AWP repository should adopt B1–B3 and the cumulative-bar choice (B4) to match; see
  the Figure 6 verification note (internal working file).
