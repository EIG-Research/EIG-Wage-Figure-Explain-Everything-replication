# Real Hourly Wages in the United States, 1982–2026 — Replication Package

Public replication materials for the Economic Innovation Group (EIG) analysis of real
hourly wages in the United States. This repository holds the analysis code, the tables
behind every figure, the R-rendered figures, and the documentation needed to obtain the
input data.

- **Author:** Benjamin Glasner, Economic Innovation Group — benjamin@eig.org
- **Publication:** *[title, link, and publication date to be added]*

The analysis measures real (inflation-adjusted) hourly wages from January 1982 through
August 2026 using Current Population Survey (CPS) microdata. It tracks wages across the
wage distribution (10th, 25th, 50th, 75th, and 90th percentiles), across the life cycle
(age groups), across generations (Silent through Gen Z), across labor-market-entry
cohorts, by education, and by sex. It also measures the share of workers paid at or below
the applicable minimum wage. All dollar values are December 2025 dollars, deflated with
the Personal Consumption Expenditures (PCE) price index. Every statistic uses the CPS
earnings weight.

## What is here

| Path | Contents |
|---|---|
| `code/` | The analysis pipeline. Entry point: `code/run_all.R`. |
| `code/_utils/` | Package manifest, FRED download scripts, EIG palette tokens, font and palette loaders, and weighted-statistic helpers. |
| `output/figures/` | Figures rendered in R. |
| `output/tables/` | The tidy data behind every figure (CSV, plus two XLSX workbooks), and `diagnostics/`. |
| `output/robustness/` | Smoothing-window robustness checks. |
| `output/verification/` | Hand-entered EPI and BLS benchmark values used by the validation stages. |
| `data/raw/minimum_wage/` | EIG-built minimum-wage inputs: locality concordances and the 2023-onward rate schedule. |
| `data/intermediate/` | Small diagnostic CSVs that document the construction of the wage panel. |
| `docs/decisions/` | One memo per methodological decision, with rationale and alternatives. |
| `DATA.md` | Every data source, its vintage, and how to obtain it. |

No source data are redistributed. The IPUMS-CPS microdata, the FRED and BLS price series,
and the third-party minimum-wage sources must be obtained as described in `DATA.md`; the
scripts that fetch them through their APIs are included.

## Figures and the code behind each

Several charts in the publication were finished in Datawrapper. Those rendered images and
the Datawrapper publishing code are not included; the R-rendered versions and the tables
behind them are.

| Figure | Content | Produced by | Tables (`output/tables/`) |
|---|---|---|---|
| A | Real hourly wage at five percentiles, level and indexed to December 1982 = 100; named-era windows; split by sex | `figure_a_percentiles.R`, `figure_a_percentiles_by_sex.R` | `figure_a_*` |
| B | Median real hourly wage for six age groups | `figure_b_age_bins.R` | `figure_b_*` |
| C | Life-cycle wage profile by generation | `figure_c_generation.R` | `figure_c_generation.csv` |
| D | Share of hourly workers at or below the federal, or the highest applicable federal, state, or local, minimum wage | `20a`–`20e` | `figure_d_*` |
| E | Real wage growth by five-year labor-market-entry cohort | `figure_e_entry_cohorts.R` | `figure_e_*` |
| 6a–6c | Indexed lines over era bars: percentiles, wage ratios (50/10, 90/50, 90/10), and education thirds | `figure_f_era_bars_tables.R`, `figure_f_era_bars.R` | `figure_f_*` |
| 7 | Five wage eras: duration, median growth, and unemployment | `figure_g_era_timeline.R` | `figure_g_era_timeline.csv` |
| H | Men's and women's wage levels, growth, and pay gap by era | `figure_h_sex_gap_eras.R` | `figure_h_*` |

Supporting analyses:

- `10_epi_spot_checks.R` compares the series with the Economic Policy Institute's published
  wage percentiles.
- `11_deflator_gap_diagnostic.R` measures how much the PCE versus CPI-U-RS choice moves the
  results.
- `12_covid_composition_diagnostic.R` measures the COVID-19 workforce-composition effect.
- `robustness_smoothing_window.R` compares display-smoothing choices.

## How to replicate

1. **Install R and packages.** R 4.3 or later, plus the packages listed in
   `code/_utils/00_packages.R`. The minimum-wage YAML generator
   (`code/_utils/synthesize_extension_yaml.py`) also needs Python 3 with `pandas` and
   `pyyaml`, but only if you rebuild the YAML; the R pipeline reads the shipped copy.

2. **Set API keys** in your user-level `.Renviron` (never commit it):

   ```
   IPUMS_API_KEY=your-ipums-key
   FRED_API_KEY=your-fred-key
   ```

   Both keys are free: IPUMS at https://account.ipums.org/api_keys and FRED at
   https://fred.stlouisfed.org/docs/api/api_key.html.

3. **Download the files that cannot be fetched by script**, as listed in `DATA.md`: the
   BLS R-CPI-U-RS workbook (`data/allitems.xlsx`) and, for Figure D, the four
   minimum-wage source pages. The EPI State of Working America data are optional; the
   spot-check stage uses the shipped benchmark file.

4. **Turn on the build stages.** In `code/run_all.R`, set `run_00a` through `run_02b` to
   `TRUE` for the first run. They are `FALSE` by default so that later runs reuse the
   built panel. `00a` submits the IPUMS extract and waits for it, `00b` and `00c` pull
   the FRED series, and `01a` through `02b` build the wage panel.

5. **Run the pipeline** from the repository root:

   ```bash
   Rscript code/run_all.R
   ```

   Each stage runs in a fresh environment and a run log is written to `output/logs/`.
   Figure H and the smoothing robustness check run separately, after the main pipeline:

   ```bash
   Rscript code/figure_h_sex_gap_eras.R
   ```

   ```bash
   Rscript code/robustness_smoothing_window.R
   ```

A full build takes about two hours on a recent Windows workstation, plus the time IPUMS
needs to prepare the extract. The raw extract and the intermediate panels need roughly
10 GB of disk.

### What will and will not match exactly

- **IPUMS vintage.** The published estimates use IPUMS CPS Version 13.0 (extract produced
  September 29, 2026). IPUMS revises harmonized variables between releases, so a newer
  extract can move estimates slightly.
- **FRED vintage.** The price series were pulled on September 30, 2026 (PCE through August
  2026). The Bureau of Economic Analysis revises PCE, so a later pull can shift real wages
  by small amounts.
- **Fonts.** The published figures use EIG's licensed brand fonts, which are not
  distributed. Without them the figures render in a standard sans-serif font; the data are
  unaffected.
- **Randomness.** The only stochastic step, the random-forest hours imputation, uses a fixed
  seed and a single thread, so it is deterministic.

## Method

The wage series follow the Economic Policy Institute's methodology for the CPS outgoing
rotation groups ([`epiextracts`](https://github.com/Economic/epiextracts) and the State of
Working America wage analysis), with six documented departures:

1. The PCE price index replaces CPI-U-RS as the deflator.
2. When the Pareto fit for topcoded earnings fails, no `1.5 × topcode` fallback is applied.
3. Earnings records with values allocated (imputed) by BLS are retained.
4. Hours for respondents whose hours vary are imputed with a per-year random forest rather
   than EPI's stratified regressions.
5. The upper outlier bound is a uniform $200 per hour in 1989 dollars (translated via PCE).
6. Post-2022 topcode changes are handled the way EPI handles them, including EPI's
   rotation-group bridge.

Display series are 12-month backward-looking rolling averages. The memos in
`docs/decisions/` give the rationale, the alternatives considered, and where each choice
is implemented.

## Environment used for the published run

Recorded for reference; versions are not pinned and no lockfile is shipped.

| Component | Version |
|---|---|
| R | 4.4.3 |
| `arrow` | 23.0.1.2 |
| `dplyr` | 1.2.1 |
| `fredr` | 2.1.0 |
| `ggplot2` | 4.0.3 |
| `here` | 1.0.2 |
| `ipumsr` | 0.10.0 |
| `patchwork` | 1.3.2 |
| `ragg` | 1.5.2 |
| `ranger` | 0.18.0 |
| `readr` | 2.2.0 |
| `tidyverse` | 2.0.0 |
| `zoo` | 1.8-15 |
| Python (YAML generator only) | 3.12 |

## License and citation

Code is released under the MIT License (`LICENSE`). Cite this package using
`CITATION.cff`. The underlying data remain subject to their providers' terms; see
`DATA.md`.

## Contact

Benjamin Glasner, Economic Innovation Group — benjamin@eig.org
