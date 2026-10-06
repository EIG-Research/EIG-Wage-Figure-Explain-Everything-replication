# Decision 11 — Drop the March ASEC-sample records from the ORG wage panel

- Status: Active
- Decided: 2026-09-29
- Decided by: Benjamin Glasner, EIG
- Type: correction of a data-handling defect. Not a methodology change and not an EPI departure; no wage-standard
  convention changes.
- Affects: `code/01b_build-org-panel.R` (new step 0, new diagnostic
  `data/intermediate/asec_records_dropped.csv`), and through it every EARNWT statistic downstream: 02a, 02b, Figures
  A–G and 6, 10–12, 20d–20e, and the Datawrapper charts.
- Source: raised by the EIG American Worker Project (AWP) team on 2026-09-29. The fix matches the AWP
  wage-cleaning code so the two projects converge.

## Context

`00a_download-ipums-cps.R` builds the extract's sample list with the regex `^cps\d{4}_(\d{2})`. That pattern matches
the monthly basic samples and also the March ASEC samples (`cpsYYYY_03s`). In those Marches IPUMS delivers every
ASEC respondent as a separate record, with `ASECFLAG == 1`, alongside the basic-monthly record of the same person
(`ASECFLAG == 2`). Nothing in 01a or 01b filtered on `ASECFLAG`; only the Figure 6 ranking population did.

Measured on this repo's panel before the fix (extract `cps_00586`), for records with a non-missing real hourly
wage:

| Years | March / February records | March / February EARNWT |
|---|---|---|
| 1982–1988 | 0.98–1.02 | 1.00–1.01 |
| 1989 | 2.00 | 1.00 (all 14,913 ASEC copies had NA EARNWT) |
| 1990–2000 | 1.84–2.09 | 1.84–2.01 |
| 2001–2004 | 2.40–2.63 | 2.37–2.42 (includes the ASEC oversample) |
| 2005–2023 | 1.86–2.01 | 1.92–2.02 |
| 2024 | 1.47 | 1.49 |
| 2025–2026 | 0.98 | 1.01 |

The duplicate copies disagree with the originals:
- **Weights:** the matched pairs' weights almost always differ.
- **Weekly earnings:** the two copies agree in all 28,840 matched pairs in 1990, but agree less often in later
  years.

From 1990 to 2024, therefore, every March counted each earner twice, with inconsistent values. That affected:
- the per-year random-forest hours fit;
- the sex-year Pareto fit and the rotation-group bridge;
- every monthly and annual percentile;
- the Figure D binding shares.

The tapering in 2024 and 2025 has a specific cause: IPUMS stops populating `EARNWEEK2` on the ASEC copies. With
positive EARNWT, 4,864 of 19,435 ASEC copies carry `EARNWEEK2` in March 2024 and 55 of 19,187 in March 2025, so most
copies failed the sample gate. Forty March 2025 duplicates still reached the panel.

## Options considered

- **Filter in 01b on `ASECFLAG` (chosen).** Drop `ASECFLAG == 1` right after each year's raw records are read,
  before sentinels, the sample gate, allocation diagnostics, hours classification, the RF fit, Pareto, and the
  bridge. Keying on `ASECFLAG` is authoritative; sample-name suffixes are not, because monthly IDs end in both `b`
  and `s`. `data/raw` stays as loaded, which the Figure 6 ranking population also reads (it already excludes
  `ASECFLAG == 1`).
- **Exclude the ASEC samples at source in 00a.** Cleaner extract, but it changes the extract definition and forces
  a re-pull. It is redundant with the 01b filter, and doing both silently would hide which one is load-bearing.
  Not adopted.
- **Keep the ASEC copies, reweight March.** Rejected: the copies are not independent observations, and their
  weights and earnings disagree with the basic-monthly records.

## Decision

`01b_build-org-panel.R` step 0 drops every record with `ASECFLAG == 1` and writes per-(year, month) counts to
`data/intermediate/asec_records_dropped.csv` (`year_int, month_int, n_asec_records_int, n_asec_earnwt_pos_int`, the
AWP layout). The step stops if `ASECFLAG` is absent from a partition. Nothing else changes: decisions 01–10, the RF
hyperparameters and seed, Pareto, the bridge, the bounds, and the estimator.

## Effect (rebuild of 2026-09-29, extract `cps_00601`)

The rebuild was a full `run_all.R`. IPUMS had added `cps2026_08s` and `cps2026_03s`, so 00a re-pulled the extract
(`cps_00601` replaced `cps_00586`). The re-pull is not a confound, because none of the following changed anything:
- PCEPI is identical in all 571 months;
- the 1982–1988 panel rows are byte-identical;
- August 2026 was dropped in 02a for lack of a PCEPI value, so the series still ends July 2026;
- one April/May 2026 record moved month in the IPUMS revision (±0.01 percent of that month's EARNWT).

The minimum-wage and UNRATE refreshes are separate; they extend Figure D and the UNRATE series by one month and
leave history unchanged.

- **Records dropped:** 7,745,574 ASEC-sample records across 45 Marches (1982–2026), 979,079 of them with EARNWT > 0.
  Panel rows fall by 14,913 in 1989, 10,036–22,557 a year in 1990–2023, 4,849 in 2024, and 40 in 2025.
- **Verification:**
  - March/February EARNWT ratio is 0.98–1.01 in every year 1982–2026.
  - The record ratio is 0.95–1.05 in every year except March 2020 (0.93), the COVID-19 response collapse, which
    EARNWT reweights away.
  - 0 NA-EARNWT rows remain (the 1989 copies are gone), and 0 `ASECFLAG == 1` rows remain in `cps_org_panel`.
- **Published wage series:**
  - Small in levels. The 12-month rolling percentiles move by at most 0.24 percent in any month (P50, July 1998;
    $0.05), and the July 2026 values are unchanged to the cent except P75 ($41.46 → $41.45).
  - Datawrapper era-chart end indexes move by at most 0.2 points.
  - Figure 6 era bars move by at most 0.3 pp (50/10 ratio, era 3: 0.1 → 0.4).
  - Figure 7's median growth moves 0.01 pp a year at most.
- **EPI spot checks:**
  - 1990 P50 $19.01 → $18.99 (delta −$0.44 → −$0.45, −2.25 → −2.34 percent).
  - 2010 P50 $22.54 and 2023 P90 $66.99 are unchanged.
  - Valid N falls from 200,266 to 184,924 (1990), 180,458 to 167,185 (2010), and 135,401 to 125,369 (2023).
  - The dual gate passes, 3 of 3.
- **Population counts:** `earnwt_pop_num` (average monthly EARNWT population) falls by 6.9 to 8.1 percent a
  year in 1990–2023 (1990: 113.4 million → 104.8 million), by about 10.5 percent in 2001–2004, and by 3.9 percent in
  2024, because the duplicates had inflated March's weight sum. Any use of
  these as worker counts was overstated.
- **Figure D (yearly):** 35 of 45 years change by more than 0.005 pp; the largest change is 1991 (federal −0.30 pp,
  state −0.24 pp). BLS validation is still 43 of 43 years within ±1 pp.
- **Figure 6 AWP reference check:** `figure_f_awp_reference_check.csv` now reproduces 34 of the 72 former AWP
  values (max |diff| 0.61), down from 72 of 72. This is expected, because those values were computed on the
  double-counted data. Nothing was tuned toward them.

The headline old → new tables and the full cell-level list of changes (every changed cell of every `output/tables` CSV) are kept in EIG's internal working files.

## Follow-up

- The AWP parity check should compare against extract `cps_00601` (or a fresh pull), since `cps_00586` is no
  longer this project's extract.
- The live Datawrapper charts (16 Figure A charts plus Figure 7) must be republished to reflect the fix.
