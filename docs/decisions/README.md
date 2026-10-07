# Methodological decision records

One memo per methodological choice. Each records the context, the options considered, the
decision, its rationale, where it is implemented, and the trade-offs accepted. Code
comments point to these memos by file name.

The wage series replicate the Economic Policy Institute's CPS ORG methodology
([`epiextracts`](https://github.com/Economic/epiextracts) and the State of Working America
wage analysis). Decisions 01 through 06 are the documented departures from it. The rest
record display, figure-construction, and data-handling choices.

| Memo | Decision | Status |
|---|---|---|
| `decision_01_pce_deflator.md` | PCE price index in place of CPI-U-RS | Active (EPI departure 1) |
| `decision_02_no_pareto_fallback.md` | No `1.5 × topcode` fallback when the Pareto fit fails | Active (EPI departure 2) |
| `decision_03_retain_allocated_records.md` | Retain BLS-allocated earnings records | Active (EPI departure 3) |
| `decision_04_random_forest_hours_imputation.md` | Random-forest imputation of "hours vary" responses | Active (EPI departure 4) |
| `decision_05_uniform_200_upper_bound.md` | Uniform $200/hour (1989 dollars, via PCE) upper outlier bound | Active (EPI departure 5) |
| `decision_06_epi_rotation_group_bridge.md` | EPI's post-2022 topcode handling, including the rotation-group bridge | Active (EPI departure 6) |
| `decision_07_hours_missingness_scope.md` | Scope of the hours imputation; pre-1994 salaried workers | Active |
| `decision_07_smoothing_12mo_ewma.md` | 12-month EWMA display smoother | Superseded by 08 |
| `decision_08_smoothing_12mo_flat.md` | Flat 12-month backward rolling-average display smoother | Active |
| `decision_09_pooled_window_era_bar_figures.md` | Construction of the Figure 6 era-bar charts | Active |
| `decision_10_covid_composition_anchor.md` | COVID-19 aftermath chart indexed to January 2022; addendum 2026-10-07 moves the era boundary to February 2020 (NBER peak) | Active |
| `decision_11_drop_asec_sample_records.md` | Drop the March ASEC-sample duplicate records | Active |
| `decision_12_figure_d_calendar_rolling_window.md` | Figure D rolling window spans 12 calendar months | Active |

Some memos cite diagnostic memos and retired diagnostic outputs that are kept in EIG's
internal working files and are not part of the public replication package.
