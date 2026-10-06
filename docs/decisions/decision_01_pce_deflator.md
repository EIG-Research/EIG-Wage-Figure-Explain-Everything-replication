# Decision 01 — Substitute PCE deflator for CPI-U-RS in the main real-wage series

- Status: Active
- Decided: 2026-04-22
- Decided by: Benjamin Glasner, EIG
- Affects: `code/_utils/download_deflators.R`, `code/02a_build_real_wages.R`, every Figure-A, Figure-B, and Figure-C deliverable; downstream tables in `output/tables/`; `data/intermediate/cps_real_wages/`.

## Context

EPI's State of Working America wage series deflates nominal earnings with CPI-U-RS. EIG production figures must align with EIG house style for real-dollar reporting, which uses the Personal Consumption Expenditures price index (PCEPI) so the wage figures are comparable to other EIG outputs that report real dollars on the PCE base. The deflator choice is the first and most visible departure from EPI methodology and is intended rather than incidental.

## Options considered

- PCE chained price index (PCEPI, FRED series `PCEPI`) — monthly, current methodology, the EIG house deflator.
- CPI-U-RS — EPI's chosen deflator, annual only, BLS-published research series.
- C-CPI-U (FRED series `SUUR0000SA0`) — monthly chained Laspeyres alternative, 1999 forward.
- CPI-U SA / CPI-U NSA — BLS headline monthly series, exposed to substitution and outlet bias.

## Decision

Use PCEPI as the primary deflator on a monthly (year, month) join; retain CPI-U-RS, C-CPI-U, and CPI-U SA / NSA as shadow series for sensitivity comparisons but not in the production figures.

## Rationale

PCEPI is monthly, current, and chain-weighted, which closes the year-within-year variation that CPI-U-RS hides by being annual only. The PCE basket better reflects the consumption mix EIG reports against in other real-dollar work, so substituting it preserves comparability across the broader EIG output. The shadow series remain useful: the W10 spot-check confirms the EIG-versus-EPI reconciliation gap is about two percentage points on the 1990 P50 (−2.25 percent), the magnitude users can expect when reconciling the EIG figure against EPI's published State of Working America values. See the Verification note below.

## Implementation

- `code/_utils/download_deflators.R` pulls PCEPI from FRED and writes monthly parquet plus a manifest at `data/fred/deflators/_manifest.csv`.
- `code/02a_build_real_wages.R` reads the manifest, resolves the primary key, joins the deflator on `(YEAR, MONTH)`, and divides nominal wages by `pcepi_dec2025_base` to produce real Dec 2025 PCE-dollar columns.
- Configuration toggle: `primary_deflator_key_chr <- "pcepi"` in `02a_build_real_wages.R`. A compatibility guard halts the script with an instructive error if any non-PCEPI key is set, because the downstream column references are PCEPI-specific.
- Shadow keys (`cpiurs`, `ccpiu`, `cpiu_sa`, `cpiu_nsa`) are produced and stored in the manifest for sensitivity comparisons.

## Trade-offs accepted

The PCE basket and the CPI-U-RS basket are not interchangeable; the choice systematically attenuates measured real growth in early years where CPI-U-RS runs hotter than PCEPI. In the full EIG-versus-EPI reconciliation this nets to about two percentage points on the 1990 P50 (W10 spot-check: −2.25 percent); the deflator effect measured in isolation is larger (see Verification below). EIG figures are therefore not numerically identical to EPI's published State of Working America series even where every other methodological choice matches. Documenting the deflator switch as a primary departure makes that gap legible to readers rather than hidden.

## Verification (2026-06-04)

Two independent checks bear on the deflator gap, and they measure different things:

1. **EIG-versus-EPI reconciliation (W10 spot-check, `code/10_epi_spot_checks.R`).** Comparing the EIG figure against EPI's *published* State of Working America values (EPI deflates with CPI-U-RS; the published value is rescaled to the Dec-2025 PCE base for comparison), the 1990 P50 delta is **−2.25 percent**, 2010 P50 is **+1.80 percent**, and 2023 P90 is **+7.37 percent** — all within the documented dual tolerance. The original "~2 percentage points on the 1990 P50" is therefore **confirmed** as the net EIG-versus-EPI reconciliation gap.

2. **Isolated deflator swap (`code/11_deflator_gap_diagnostic.R`).** Holding the EIG pipeline fixed and swapping only the deflator (PCE vs CPI-U-RS, both on a common reference-year base), the 1990 P50 gap is **−8.6 percent** and the 2010 P50 gap is **−2.7 percent** (reference year 2019; see the data limitation below). This isolates the deflator effect alone, which is larger than the net reconciliation in (1). The two are not contradictory: in the full EIG-versus-EPI comparison the deflator effect is partly offset by EPI's differing topcode and allocation conventions and by the 2025-versus-2019 horizon. The exact decomposition of the roughly six-point difference between (1) and (2) has not been worked out, and is recorded here as an open item rather than asserted.

**Data limitation.** The repo's vendored CPI-U-RS file (`data/allitems.xlsx`) currently **ends in 2019**, so `_utils/download_deflators.R` silently rebases the CPI-U-RS shadow to 2019 rather than to 2025 (the `cpiurs_2025annual_base` column name is therefore a misnomer), and any CPI-U-RS comparison for years after 2019 — including the 2023 P90 cell in check (2) — cannot be produced. Refreshing the BLS R-CPI-U-RS file (and, if a current series is needed, splicing forward as EPI does) is required before the shadow series can support post-2019 reconciliation. This does not affect the production figures, which use PCE.

## References

- `code/_utils/download_deflators.R`.
- `code/02a_build_real_wages.R`, configuration block at lines 50 through 71.
- `PROJECT.md` Constraints, Departure #1.
- FRED, "Personal Consumption Expenditures: Chain-type Price Index (PCEPI)." Federal Reserve Bank of St. Louis. https://fred.stlouisfed.org/series/PCEPI.
- BLS, "Consumer Price Index Research Series (CPI-U-RS)." U.S. Bureau of Labor Statistics. https://www.bls.gov/cpi/research-series/home.htm.
- Economic Policy Institute, "Methodology for measuring wages and benefits." State of Working America Data Library. https://www.epi.org/data/methodology/. Accessed 2026-06-04. Confirms EPI deflates real wages with CPI-U-RS, establishing the deflator EIG departs from.
