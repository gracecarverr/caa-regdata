# `stacktests` — ICIS-Air Stack Tests

**Source:** EPA ICIS-Air `ICIS-AIR_STACK_TESTS.csv` (ECHO bulk download; provenance in `data/raw/MANIFEST.csv`).
**Built by:** [`05_stacktests.R`](05_stacktests.R) → `data/clean/stacktests.csv.gz`.
**Grain:** one row per raw record. Distinct tests = `filter(dup == 0)`.

## What it is

One **stack test** per event, with a `status` (Pass / Fail / Pending / ...). Stack tests measure emissions
at the source; the result indicates whether the facility passed.

## Cleaning decisions

- **Date** = `ACTUAL_END_DATE`, parsed with `mdy()`.
- **No pollutant detail.** The source pollutant field is effectively empty, so it is not carried.
- **No deduplication.** Every raw row is kept; duplicates flagged `dup` / `dup_exact`.
- **Dropped rows.** Records with no `PGM_SYS_ID` or an unparseable date are dropped (never imputed);
  count printed at build time.

## Columns

| column | definition |
|---|---|
| `PGM_SYS_ID` | ICIS-Air facility id |
| `activity_id` | distinct stack-test id (the event id) |
| `date` | stack-test date (parsed) |
| `year` | stack-test calendar year |
| `status` | test result (Pass / Fail / Pending / ...) |
| `agency` | agency flag |
| `dup` | occurrence index within the event id (0 = first row) |
| `dup_exact` | 1 if byte-identical (on kept columns) to an earlier row |

## Nuances

- **Very low duplication** at this grain — the flag is near-inert here, kept for schema consistency.
- **`status` includes non-terminal values** (e.g., Pending); Pass/Fail do not sum to all tests.

Column definitions and current summaries are also generated into the docs site
([dictionary](../../docs/dictionary.qmd), [distributions](../../docs/distributions.qmd)).
