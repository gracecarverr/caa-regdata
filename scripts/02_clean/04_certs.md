# `certs` — ICIS-Air Title V Compliance Certifications

**Source:** EPA ICIS-Air `ICIS-AIR_TITLEV_CERTS.csv` (ECHO bulk download; provenance in `data/raw/MANIFEST.csv`).
**Built by:** [`04_certs.R`](04_certs.R) → `data/clean/certs.csv.gz`.
**Grain:** one row per raw record. Distinct certifications = `filter(dup == 0)`.

## What it is

One **annual Title V compliance certification** per event. The raw table carries roughly five rows per
certification (one per program/pollutant), so it is heavily duplicated at the certification grain.

## Cleaning decisions

- **Date** = `ACTUAL_END_DATE` (certification date), parsed with `mdy()`.
- **No deduplication.** Every raw row is kept; duplicates flagged `dup` / `dup_exact`. Use `dup == 0`
  for one row per certification.
- **Dropped rows.** Records with no `PGM_SYS_ID` or an unparseable date are dropped (never imputed);
  count printed at build time.

## Columns

| column | definition |
|---|---|
| `PGM_SYS_ID` | ICIS-Air facility id |
| `activity_id` | distinct certification id (the event id) |
| `date` | certification date (parsed) |
| `year` | certification calendar year |
| `deviation_flag` | facility-reported deviation flag (Y/N) |
| `agency` | agency flag |
| `dup` | occurrence index within the event id (0 = first row → one per certification) |
| `dup_exact` | 1 if byte-identical (on kept columns) to an earlier row |

## Nuances

- **~80% duplicate rows** at the certification grain (the per-program/pollutant expansion). Always
  filter `dup == 0` to count certifications; the raw row count counts program/pollutant sub-rows.
- **Certifications do not cover every major facility every year** — class-major is not the same as an
  annual Title V certifier; don't assume one certification per major.

Column definitions and current summaries are also generated into the docs site
([dictionary](../../docs/dictionary.qmd), [distributions](../../docs/distributions.qmd)).
