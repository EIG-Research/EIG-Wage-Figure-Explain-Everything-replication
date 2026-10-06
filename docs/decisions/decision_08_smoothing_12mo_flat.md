# Decision 08 — Smooth the wage-percentile display series with a plain 12-month backward-facing rolling average (superseding the 12-month recency-weighted EWMA)

- Status: Active
- Decided: 2026-07-30
- Decided by: Benjamin Glasner, EIG
- Supersedes: `docs/decisions/decision_07_smoothing_12mo_ewma.md` (Decision 07, 12-month geometric EWMA, `ratio = 0.85`)
- Affects: `code/figure_a_percentiles.R`, `code/figure_a_percentiles_by_sex.R`, `code/figure_b_age_bins.R`, `code/30_build_summary.R`, `code/figure_a_datawrapper_publish.R`; every smoothed Figure-A / Figure-B deliverable in `output/tables/` and `output/figures/`; the published Datawrapper charts and their PNG exports in `output/datawrapper/`.
- Evidence: `code/robustness_smoothing_window.R` and its outputs in `output/robustness/` (`seasonality_diagnostics.csv`, `robustness_smoothing_fullpanel.png`, `robustness_smoothing_uncertainty.png`).

## Context

Decision 07 adopted a 12-month geometric EWMA — a 12-month trailing window with weights
`0.85^k` on the month `k` periods back, half-life ≈ 4.3 months — explicitly *in preference to*
the conventional 12-month flat trailing mean. That memo priced the trade-off correctly and
chose responsiveness. This decision reverses that choice.

Nothing in the evidence base changed. The reversal is a change in how the trade-off is
weighted: the interpretability and seasonal-cancellation properties of an equally weighted
annual window are now judged to matter more than keeping recent turning points unlagged.
Decision 07's analysis stands as written and is retained as the record of the prior choice.

## Options considered

The same three candidates Decision 07 compared, re-weighted:

- **6-month flat trailing mean** — the pre-Decision-07 production smoother. Responsive
  (~2.5-month lag) but visibly noisy, and a 6-month window is half an annual cycle, so it
  does not remove seasonality. Still rejected.
- **12-month geometric EWMA (`ratio = 0.85`)** — the Decision 07 choice. Keeps turning points
  roughly where the 6-month mean puts them while averaging over a full year. Now rejected on
  interpretability and residual-seasonality grounds.
- **12-month flat trailing mean, adaptive to missing months (chosen)** — equal weight on
  every *observed* month in the calendar window `[t-11, t]`.

## Decision

Adopt the **plain 12-month backward-facing (trailing) rolling average** as the single
smoother for every wage-percentile display series — levels, indexed, by-sex, and age-bin
medians. Equal weights, no recency weighting, no tuning parameter.

The window is **adaptive to missing months**. A month with no survey data — October 2025,
lost to the federal government shutdown — drops out of both the numerator and the
denominator. The average at a given month is taken over the months actually observed inside
`[t-11, t]`; the window does not reach back a thirteenth month to make up the count, and a
missing month does not propagate `NA` through the following year. Partial windows at the
series start are allowed. An all-missing window yields `NA_real_`.

## Rationale

**Interpretability is the decisive gain.** "12-month rolling average" is a phrase every
reader already understands and needs no caption footnote. Decision 07 acknowledged this cost
directly: "'Six-month average' is trivially explainable; '12-month average weighted toward
recent months' is a heavier caption." These figures are public-facing and bound for eig.org,
and a smoother a reader can restate in one sentence is worth more here than a few months of
responsiveness at the right-hand edge.

**Equal weights cancel the annual cycle; the EWMA did not.** A flat 12-month window has a
zero in its frequency response at the seasonal frequency. Decision 07 conceded that unequal
weights leave the ~1–2 percent seasonal component in place, and judged that immaterial. That
residual is small, but removing it is free under this smoother rather than something to
argue away.

**No tuning parameter.** `ratio = 0.85` was, in Decision 07's own words, "a middle setting
from the robustness comparison, not an optimized value." Any reader could reasonably ask why
0.85 rather than 0.80 or 0.90, and the honest answer was that it was a judgment call. A flat
mean has nothing to defend.

**Consistency inside the repo.** `code/20e_binding-minimum-analysis.R` already smooths the
Figure D binding-share series with a flat 12-month trailing mean with NA skipping. Figure A
and Figure B now use the same convention, so "the smoothed line" means one thing across every
figure in the project.

*Correction, 2026-09-29.* That statement was not true of Figure D until this date. 20e rolled
over table rows, so every window after the missing October 2025 spanned 13 calendar months.
Figure D now uses the calendar-grid construction of Figure A; eight published months moved,
by at most 0.09 pp. See `docs/decisions/decision_12_figure_d_calendar_rolling_window.md`.

## Honest caveats (the cost this decision accepts)

- **Turning points lag by roughly 5.5 months, versus ~2.5 for the EWMA.** This is the real
  price, and Decision 07 rejected the flat mean specifically because of it.
- **Concretely: the 10th-percentile peak moves from ~May 2025 to ~September–November 2025,
  and the recent decline is muted.** This is documented in
  `output/robustness/robustness_smoothing_uncertainty.png` and was Decision 07's central
  objection. It shows up on exactly the charts carrying recent policy signal — the COVID-19
  aftermath window and the "Liberation Day" tariff window. A reader drawing conclusions about
  the timing of a recent inflection from the smoothed line will be reading a date that is
  months late. The raw monthly points are plotted alongside the line on every figure
  precisely so that the unlagged timing remains visible.
- **A reviewer who weights recent responsiveness above interpretability should prefer the
  EWMA**, and Decision 07 documents that position fully. This is a genuine judgment call
  between two defensible smoothers, not a correction of an error.
- **Missing-month adaptivity is itself a choice.** Averaging over 11 observed months instead
  of 12 makes the October-2025-affected windows marginally noisier than their neighbours, and
  weights the observed months in those windows slightly more heavily (1/11 rather than 1/12
  each). The alternatives — propagating `NA` for twelve months, or interpolating the missing
  month — are both worse: one blanks a year of the series, the other invents data.

## Implementation

- `rolling_window_int` stays `12L`. The `ewma_ratio_num <- 0.85` constant is **deleted** from
  all three figure scripts.
- The `zoo::rollapplyr` call keeps its right-aligned, partial-window, NA-skipping form. Its
  `FUN` becomes:

  ```r
  FUN = function(x) if (all(is.na(x))) NA_real_ else mean(x, na.rm = TRUE)
  ```

  The `all(is.na(x))` guard is required: `mean(x, na.rm = TRUE)` on an all-`NA` window returns
  `NaN`, not `NA_real_`. This matches the `flat12` branch of
  `code/robustness_smoothing_window.R` exactly.
- Figure captions, chart subtitles, axis labels, and the summary digest describe the series as
  a **"12-month rolling average."** The phrasings introduced by Decision 07 —
  "recency-weighted average" and "12-month average weighted toward recent months" — are
  removed everywhere.
- **The legacy naming debt is cleared.** Decision 07 retained the historical `rolling6` /
  `roll6` tokens in output filenames and internal columns to avoid a rename across five
  interdependent scripts, and flagged it as "a known, documented naming debt." Those tokens
  are now renamed to `roll12`: output filenames (`figure_a_percentiles_level_roll12.csv` and
  the fifteen others), internal columns (`real_hourly_wage_roll12_num`, `index_roll12_num`,
  the anchor columns), and the Datawrapper era-spec field (`roll12_file_chr`). The superseded
  `*_rolling6.*` artifacts are deleted from `output/tables/`.
- `code/robustness_smoothing_window.R` retains all three smoothers — the three-way comparison
  is the evidence base for both this decision and Decision 07 — with the annotations swapped
  so the flat 12-month mean is marked as production and the EWMA as the rejected alternative.

## Verification

- Re-run `code/robustness_smoothing_window.R` to regenerate the diagnostics and the three-way
  comparison if the input series change.
- Confirm each indexed series still equals exactly 100 at its anchor month. Scaling commutes
  with a flat mean, so this holds by construction and is a regression test of the rename
  rather than of the smoother.
- Confirm the 10th-percentile short-window peak has shifted later (~September–November 2025).
  If it has not, the smoother did not actually change and the rebuild did not take effect.
- Confirm level percentiles remain inside the Decision 05 outlier-trim range (~$1.10 to $442
  per hour in December 2025 PCE dollars).

## Downstream state at the time of this decision

The Datawrapper publish stage was **not** re-run. The live charts and the baked PNG exports
in `output/datawrapper/exports/` still carry EWMA-smoothed data and EWMA caption wording, and
will until the publish stage runs.
