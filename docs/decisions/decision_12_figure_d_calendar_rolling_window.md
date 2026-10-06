# Decision 12 — Figure D's 12-month rolling average spans 12 calendar months, not 12 rows

- Status: Active
- Decided: 2026-09-29
- Decided by: Benjamin Glasner, EIG
- Type: correction to match decision 08. No new convention.
- Affects: `code/20e_binding-minimum-analysis.R` section 5; `output/tables/figure_d_binding_share_monthly.csv`
  (gains an explicit October 2025 row and a `window_n_int` column); `output/figures/figure_d_binding_share_monthly.png`;
  the "latest 12-month average" in the internal figures summary digest (`code/30_build_summary.R`, unchanged).
- Source: raised by the EIG American Worker Project (AWP) team on 2026-09-29. AWP decision D6 (revised
  2026-09-29) ports the same rule.

## Context

Decision 08 says the smoothed line means one thing in every figure: a flat, trailing 12-month mean over calendar
months, with a missing survey month dropping out of the window. Figures A, B, and 6 implement that on a
calendar-complete grid. Figure D did not.

20e built its monthly table with `group_by(YEAR, MONTH) |> summarise()`, so October 2025 (no CPS sample, federal
shutdown) had no row. It then applied `zoo::rollapplyr(x, 12L, mean, ...)`, which counts rows. Every window after
the gap therefore reached back 13 calendar months; for example, June 2026 averaged June 2025 through June 2026.

`30_build_summary.R`'s "latest 12-month average" (`tail(share_num, 12L)`) had the same row-counting problem.

## Decision

Section 5 now does the following:

1. **Calendar grid.** Put the monthly shares on a calendar-complete grid (`month_idx_int = YEAR * 12 + MONTH - 1`,
   first to last observed month), mirroring `figure_a_percentiles.R` step 3. October 2025 is an explicit row with NA
   shares and is kept in the CSV.
2. **Rolling mean.** Roll with `zoo::rollapplyr(width = 12L, FUN = all-NA guard + mean(na.rm = TRUE),
   fill = NA_real_, partial = TRUE)`, the Figure A construction. A gap month itself receives the mean of its
   window's observed months, as in Figure A.
3. **Window count.** Add `window_n_int`, the number of observed months in each window.
4. **Build-stopping checks:**
   - every observed month has both shares;
   - no rolling value is NA in a window with observed months;
   - every rolling value and every `window_n_int`, across all 535 months, equals the plain mean (count) of that
     row's calendar window, recomputed from `month_idx_int`.

The yearly table, the BLS ±1 pp validation, and the share definitions are unchanged.

Because the grid now gives October 2025 its own calendar row and the shares are averaged with `na.rm = TRUE`,
`30_build_summary.R` becomes calendar-correct with no code change.

## Not defects (for clarity)

- Partial windows at the series start (January 1982 is a one-month mean) follow decision 08.
- A December rolling value is a mean of monthly shares, so it does not equal the pooled annual share.

## Effect

Measured on the published CSV (pre-ASEC-fix panel), the fix reproduces the AWP team's figures exactly:
- 8 months change (November 2025 to June 2026), by at most 0.029 pp (federal) and 0.086 pp (federal-or-state);
- June 2026 moves from 7.216 to 7.294 percent (federal-or-state) and from 0.826 to 0.814 percent (federal).

On the rebuilt panel (after decision 11), the fix alone moves 9 months (November 2025 to July 2026), by at most
0.086 pp. Every window from October 2025 to July 2026 has `window_n_int == 11`.

Combined with decision 11, federal-or-state share, published → new:

| Month | Published | New |
|---|---|---|
| December 2025 | 6.897% | 6.935% |
| June 2026 | 7.216% | 7.294% |
| July 2026 | — (the published table ended June 2026) | 7.322% |

The federal shares for the same months are 0.974% → 0.972%, 0.826% → 0.814%, and 0.824% for July 2026.
