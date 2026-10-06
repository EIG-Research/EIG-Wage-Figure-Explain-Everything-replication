# Data sources

This package redistributes no source data. Each source below lists how it is used, the
vintage behind the published estimates, and how to obtain it. Where a script fetches the
data through an API, the script is named.

## 1. IPUMS-CPS: Current Population Survey basic monthly microdata

- **Used for:** every wage series. The analysis sample is the outgoing rotation groups
  (the earnings questions), January 1982 onward, weighted by the earnings weight `EARNWT`.
- **Vintage:** IPUMS CPS Version 13.0; extract produced September 29, 2026, covering CPS
  monthly samples through August 2026.
- **How to obtain:** register for a free account at https://cps.ipums.org and create an API
  key at https://account.ipums.org/api_keys. Set `IPUMS_API_KEY` in your user-level
  `.Renviron`. Then `code/00a_download-ipums-cps.R` (stage `run_00a` in `code/run_all.R`)
  defines the extract (every monthly sample from 1982 onward, plus the variable list in
  the script), submits it, waits for IPUMS to build it, and downloads it to
  `data/raw/cps_org/_ipums_extract/`. You can also build the same extract by hand in the
  IPUMS web interface. See `data/raw/cps_org/README.md`.
- **Terms:** IPUMS microdata may not be redistributed. Users must agree to the IPUMS
  terms of use and cite the data:
  Sarah Flood, Miriam King, Renae Rodgers, Steven Ruggles, J. Robert Warren, Daniel
  Backman, Etienne Breton, Grace Cooper, Julia A. Rivera Drew, Stephanie Richards, David
  Van Riper, and Kari C.W. Williams. IPUMS CPS: Version 13.0 [dataset]. Minneapolis, MN:
  IPUMS, 2025. https://doi.org/10.18128/D030.V13.0

## 2. Price indexes (FRED and BLS)

- **Used for:** converting nominal wages to December 2025 dollars.
  - **Primary:** Personal Consumption Expenditures chain-type price index (FRED `PCEPI`,
    Bureau of Economic Analysis), monthly, seasonally adjusted.
  - **Sensitivity only:** C-CPI-U (`SUUR0000SA0`), CPI-U seasonally adjusted (`CPIAUCSL`),
    CPI-U not seasonally adjusted (`CPIAUCNS`), and the annual R-CPI-U-RS research series.
- **Vintage:** pulled September 30, 2026; monthly series through August 2026.
- **How to obtain:** create a free FRED API key at
  https://fred.stlouisfed.org/docs/api/api_key.html and set `FRED_API_KEY`.
  `code/_utils/download_deflators.R` (stage `run_00b`) pulls the FRED series. BLS blocks
  scripted downloads of the R-CPI-U-RS workbook, so download
  https://www.bls.gov/cpi/research-series/allitems.xlsx in a browser and save it as
  `data/allitems.xlsx`. Outputs go to `data/fred/deflators/` (see the README there).

## 3. Unemployment rate (FRED)

- **Used for:** the five-era timeline (Figure 7), which marks spells of unemployment
  below 5 percent.
- **Series:** civilian unemployment rate, FRED `UNRATE`, monthly; pulled September 30, 2026.
- **How to obtain:** `code/_utils/download_unemployment.R` (stage `run_00c`), using the same
  `FRED_API_KEY`. Output goes to `data/fred/unemployment/`.

## 4. Minimum wages (Figure D)

- **Vaghul–Zipperer historical minimum wage data**, release v1.4.0
  (https://github.com/benzipperer/historicalminwage). State and sub-state minimum wages
  through 2022. Downloaded automatically by `code/20a_download-minimum-wage.R`.
- **Source pages for 2023 onward**, saved by hand on May 4, 2026. `code/20b` reads them
  from `data/raw/minimum_wage/sources/<source>/2026-05-04/` and stops with a named error if
  any is missing. Save each page as HTML under the file name shown:
  - U.S. Department of Labor, Wage and Hour Division, state minimum wage history:
    https://www.dol.gov/agencies/whd/state/minimum-wage/history →
    `dol_whd/2026-05-04/state-minimum-wage-history.html`
  - U.S. Department of Labor, tipped minimum wages:
    https://www.dol.gov/agencies/whd/state/minimum-wage/tipped →
    `dol_whd/2026-05-04/state-minimum-wage-tipped.html`
  - Economic Policy Institute, Minimum Wage Tracker:
    https://www.epi.org/minimum-wage-tracker/ →
    `epi/2026-05-04/minimum-wage-tracker.html`
  - UC Berkeley Labor Center, inventory of U.S. city and county minimum wage ordinances:
    https://laborcenter.berkeley.edu/inventory-of-us-city-and-county-minimum-wage-ordinances/ →
    `berkeley/2026-05-04/inventory-of-us-city-and-county-minimum-wage-ordinances.html`

  These pages change over time. A copy saved today will reflect later changes; archived
  copies of the May 4, 2026 versions may be available from the Internet Archive.
- **EIG-built inputs (included):**
  - `data/raw/minimum_wage/extension/2023-onward.yaml`: the 2023-onward state and local
    rate schedule. `code/_utils/synthesize_extension_yaml.py` synthesized it from the
    sources above, and every entry records its source and URL.
  - `data/raw/minimum_wage/concordance/`: crosswalks from CPS county and principal-city
    codes to minimum-wage localities.

## 5. Validation benchmarks (included)

- `output/verification/epi_reference_values.csv`: selected hourly-wage percentiles from
  the Economic Policy Institute's State of Working America Data Library
  (https://www.epi.org/data/, data version 2026.4.17), rescaled to December 2025 PCE
  dollars. `code/10_epi_spot_checks.R` compares the series against these. The full EPI data
  library is not needed to run the pipeline; see `data/epi_swa_data_library/README.md`.
- `output/verification/bls_min_wage_workers_reference.csv`: the share of hourly workers
  at or below the federal minimum, from BLS *Characteristics of Minimum Wage Workers*
  reports. Each row records its source. `code/20e` compares Figure D against it.

## Generation definitions

Birth-year cutoffs follow the Pew Research Center: Michael Dimock, "Defining generations:
Where Millennials end and Generation Z begins," January 17, 2019.
