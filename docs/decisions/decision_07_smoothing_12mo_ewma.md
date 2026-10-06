# Decision 07 — Smooth the wage-percentile display series with a 12-month geometric EWMA (not a 6-month flat mean, and not a 12-month flat mean)

- Status: **Superseded by Decision 08** (2026-07-30) — the display smoother is now a plain 12-month backward-facing rolling average. See `docs/decisions/decision_08_smoothing_12mo_flat.md`. The reversal re-weighted the interpretability / responsiveness trade-off analysed below; it did not overturn any of this memo's evidence. Retained as the record of the prior choice.
- Decided: 2026-07-11
- Decided by: Benjamin Glasner, EIG
- Affects: `code/figure_a_percentiles.R`, `code/figure_a_percentiles_by_sex.R`, `code/figure_b_age_bins.R`, `code/30_build_summary.R`, `code/figure_a_datawrapper_publish.R`; every smoothed Figure-A / Figure-B deliverable in `output/tables/` and `output/figures/`; the published Datawrapper charts and their PNG exports in `output/datawrapper/`.
- Evidence: `code/robustness_smoothing_window.R` and its outputs in `output/robustness/` (`seasonality_diagnostics.csv`, `robustness_smoothing_fullpanel.png`, `robustness_smoothing_uncertainty.png`).

## Context

The wage-percentile figures plot a smoothed line over noisy monthly points. The smoother was a **6-month flat trailing mean**. Reviewers found the lines still visibly bumpy, especially on zoomed-in (short-window and indexed) charts, which raised the question of whether to lengthen the window.

The conventional default for de-noising a monthly economic series is a **12-month flat trailing mean**: equal weights over a full year exactly cancel any annual seasonal cycle (its frequency response has a zero at the seasonal frequency), and it roughly halves sampling-noise variance relative to a 6-month window. **We are deliberately not choosing that default**, for the reasons documented below, and this memo exists to make that departure explicit and honest.

## Options considered

- **6-month flat trailing mean** — status quo. Responsive (~2.5-month lag) but visibly noisy; does not remove seasonality (a 6-month window is half an annual cycle).
- **12-month flat trailing mean** — the conventional choice. Smoothest and the only option that cleanly removes seasonality, but lags turning points by ~5.5 months and mutes genuine inflections.
- **12-month geometric EWMA (chosen)** — a 12-month trailing window with weights `ratio^k` on the month `k` periods back (`ratio = 0.85`, half-life ≈ 4.3 months). Recency weighting keeps turning points roughly where the 6-month mean puts them, while still averaging over 12 months to cut noise.

## Decision

Adopt the **12-month geometric EWMA (`ratio = 0.85`)** as the single smoother for every wage-percentile display series (levels, indexed, by-sex, and age-bin medians), replacing the 6-month flat mean everywhere.

## Rationale and the evidence behind it

The robustness test (`code/robustness_smoothing_window.R`) settled two empirical questions:

1. **Is the bumpiness seasonal or sampling noise?** Mostly sampling noise. STL seasonal strength is 0.03–0.14 across percentiles (anything under ~0.3 is weak), and the peak-to-trough seasonal amplitude is only ~1–2% of the wage level. Month effects are statistically significant for the 25th–90th percentiles — but that is expected with ~530 monthly observations and reflects an economically small effect, not a large seasonal swing. See `output/robustness/seasonality_diagnostics.csv`.

2. **What do the three smoothers actually look like?** On the full panel, the 12-month flat mean and the 12-month EWMA are nearly identical and both clearly smoother than the 6-month. On the short (January 2024 onward) window, the difference is decisive: the 12-month flat mean **shifts the 10th-percentile peak from ~May 2025 to ~September–November 2025** (the ~5-month lag) and mutes the recent decline, whereas the EWMA keeps the turning point aligned with the raw data while remaining much smoother than the 6-month. See `output/robustness/robustness_smoothing_uncertainty.png`.

Because seasonality is weak, the 12-month flat mean's one decisive advantage — clean deseasonalization — buys little here, while its cost (turning-point lag) is real and visible on exactly the charts that carry recent policy signal (the COVID-19 aftermath and the "Liberation Day" tariff window). The EWMA captures the noise reduction of a long window without that lag, and it is a single, tunable, well-understood filter that applies uniformly across long and short charts.

## Honest caveats (why this is a considered departure, not a free win)

- **The conventional default is the 12-month flat mean, and it is defensible to prefer it.** A reviewer who weights deseasonalization and simplicity over recent responsiveness could reasonably choose it instead. We chose responsiveness because several deliverables are about recent dynamics.
- **The EWMA does not remove the (small) residual seasonality.** Unequal weights do not cancel the annual cycle, so the ~1–2% seasonal component survives. Given its size we judge this immaterial; a reader who disagrees should prefer the flat 12-month mean.
- **The half-life is a choice.** `ratio = 0.85` (≈4.3-month half-life) is a middle setting from the robustness comparison, not an optimized value. A gentler ratio approaches the flat 12-month mean (smoother, laggier); a steeper ratio approaches the 6-month (more responsive, noisier).
- **Interpretability cost.** "Six-month average" is trivially explainable; "12-month average weighted toward recent months" is a heavier caption and is disclosed as such on the figures.

## Implementation

- `rolling_window_int` is set to `12L` and a new `ewma_ratio_num <- 0.85` constant is added in each affected figure script. The `zoo::rollapplyr` call keeps a right-aligned, partial-window, NA-skipping form, but its `FUN` is now a weighted mean with geometric weights `ratio^k` (most recent month weight 1, oldest in-window month weight `ratio^(n-1)`), matching the robustness script exactly.
- Figure captions, chart subtitles, and the summary digest describe the series as a "12-month average weighted toward recent months." The Datawrapper publish/export pipeline is re-run so the live charts and 1000×750 PNGs reflect the new smoother.
- **Legacy identifiers retained on purpose.** Output filenames and internal columns keep the historical `rolling6` / `roll6` tokens (e.g., `figure_a_percentiles_indexed_rolling6.csv`, `real_hourly_wage_roll6_num`) to avoid a high-risk rename across five interdependent scripts. Their **contents are the 12-month EWMA** as of this decision. This is a known, documented naming debt; a future pass may rename the tokens to `roll12ewma` once the pipeline is quiet.

## Verification

- Re-run `code/robustness_smoothing_window.R` to regenerate the diagnostics and the three-way comparison if the input series change.
- After rebuild, confirm each indexed series still equals 100 at its anchor month (the EWMA at the anchor is the new base) and that value ranges remain plausible.
