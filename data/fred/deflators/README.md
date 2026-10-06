# Deflator pulls (FRED and BLS)

This directory holds the inflation series used to convert nominal CPS earnings into real wages. All series are written here by `code/_utils/download_deflators.R` and consumed by `code/02a_build_real_wages.R`.

## Files

- `_manifest.csv` — one row per series. Columns identify the deflator key (`pcepi`, `cpiurs`, `ccpiu`, `cpiu_sa`, `cpiu_nsa`), source, role (`primary` or `shadow`), frequency, base period, rebase scalar, coverage range, output parquet path, and the UTC timestamp at which the series was pulled. `code/02a_build_real_wages.R` reads this manifest to find the active deflator and to enforce a freshness check.
- `*.parquet` and `*.rds` — the canonical and R-native deflator files. Gitignored because they are regenerable from FRED via `download_deflators.R` and from the BLS XLSX at `data/allitems.xlsx`.

## Series

| Key | Source | Role | Frequency | Base period |
|---|---|---|---|---|
| `pcepi` | FRED `PCEPI` (BEA Personal Consumption Expenditures: Chain-type Price Index) | primary | monthly | December 2025 = 1 |
| `ccpiu` | FRED `SUUR0000SA0` (BLS C-CPI-U, all items, NSA) | shadow | monthly | December 2025 = 1 |
| `cpiu_sa` | FRED `CPIAUCSL` (BLS CPI-U, all items, seasonally adjusted) | shadow | monthly | December 2025 = 1 |
| `cpiu_nsa` | FRED `CPIAUCNS` (BLS CPI-U, all items, not seasonally adjusted) | shadow | monthly | December 2025 = 1 |
| `cpiurs` | BLS `allitems.xlsx` (R-CPI-U-RS research series, https://www.bls.gov/cpi/research-series/allitems.xlsx, saved as `data/allitems.xlsx`; BLS blocks scripted downloads, so save it by hand) | shadow | annual | 2025 annual average = 1 |

## Why these choices

PCE is the production primary because it is the deflator the Bureau of Economic Analysis recommends for cross-time comparisons of consumption-relevant prices. CPI-U-RS is retained as a shadow because EPI publishes its real-wage series in CPI-U-RS dollars and the spot-checks in `code/10_epi_spot_checks.R` rely on a CPI-U-RS-to-PCE rescale. C-CPI-U, CPI-U SA, and CPI-U NSA are retained as shadows so a reader can re-deflate the panel against any of the standard alternatives by changing one line in `code/02a_build_real_wages.R`.

## Refreshing

Set `FRED_API_KEY` in the environment, set `run_00b <- TRUE` in `code/run_all.R`, and source. The script overwrites all parquet outputs and updates `_manifest.csv` with the new pull timestamp. The freshness check in `02a_build_real_wages.R` warns when the pull is more than seven days old.
