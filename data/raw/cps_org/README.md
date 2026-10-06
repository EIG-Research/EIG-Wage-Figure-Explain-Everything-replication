# Raw CPS ORG extract (IPUMS-CPS)

This directory holds the IPUMS-CPS extract that drives the analysis. IPUMS microdata may
not be redistributed, so the data payload is never committed. You obtain your own copy
under your own IPUMS account.

## How to obtain the extract

1. **API (recommended).** Register for a free IPUMS-CPS account at https://cps.ipums.org,
   create an API key at https://account.ipums.org/api_keys, and set it as `IPUMS_API_KEY`
   in your user-level `.Renviron`. With `run_00a <- TRUE` in `code/run_all.R`,
   `code/00a_download-ipums-cps.R` defines the extract (every CPS basic monthly sample from
   January 1982 onward, plus the variable list in that script), submits it, waits for IPUMS
   to build it, and downloads it into `_ipums_extract/`.
2. **Manual.** Build the same extract in the IPUMS-CPS web interface using the variable
   list in `code/00a_download-ipums-cps.R`, then place the downloaded `.xml` codebook and
   `.dat.gz` data file in `_ipums_extract/`.

`00a` re-submits an extract only when the files are missing, the IPUMS sample list has
changed, or the variable list has changed. The full extract is several gigabytes.

## What appears here after a run

- `_ipums_extract/cps_NNNNN.xml` and `cps_NNNNN.dat.gz`: the IPUMS codebook and data.
- `_ipums_extract/_extract_info.rds`: extract metadata used for the cache check.
- `year=YYYY/part-0.parquet` and `.rds`: year partitions written by
  `code/01a_load-ipums-cps.R`.

The data, metadata, and partition files are gitignored and never published.

## Citation

Sarah Flood, Miriam King, Renae Rodgers, Steven Ruggles, J. Robert Warren, Daniel
Backman, Etienne Breton, Grace Cooper, Julia A. Rivera Drew, Stephanie Richards, David
Van Riper, and Kari C.W. Williams. IPUMS CPS: Version 13.0 [dataset]. Minneapolis, MN:
IPUMS, 2025. https://doi.org/10.18128/D030.V13.0 (the version used for the published
estimates; cite the version printed in your own extract's codebook).
