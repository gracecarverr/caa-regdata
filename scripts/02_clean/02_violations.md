# `violations` — ICIS-Air Violation History

**Source:** EPA ICIS-Air `ICIS-AIR_VIOLATION_HISTORY.csv` (ECHO bulk download; provenance in `data/raw/MANIFEST.csv`).
**Built by:** [`02_violations.R`](02_violations.R) → `data/clean/violations.csv.gz`.
**Grain:** one row per raw determination record. Distinct compliance determinations = `filter(dup == 0)`.

## What it is

One **compliance determination** per event — a determination the regulator recorded against a
facility. A determination may be a Federally Reportable Violation (FRV) or escalate to a
High Priority Violation (HPV), tracked by its day-zero and resolution dates.

## Cleaning decisions

- **Determination date** = first non-blank of `EARLIEST_FRV_DETERM_DATE`, then `HPV_DAYZERO_DATE`,
  parsed with `mdy()`. The FRV date is the best-populated determination date; HPV day-zero is the fallback.
- **HPV flag** = 1 when `HPV_DAYZERO_DATE` is present. The spell endpoints `hpv_dayzero_date`
  (clock start) and `hpv_resolved_date` (close, `NA` if unresolved) are kept as parsed dates so a
  panel can derive time-in-HPV-status.
- **No deduplication.** Every raw row is kept; duplicates are labelled `dup` / `dup_exact`
  (filter `dup == 0` for one row per determination).
- **Dropped rows.** Records with no `PGM_SYS_ID` or an unparseable date are dropped — never imputed —
  and the count is printed at build time.
- **Multi-valued fields** (`program`, `pollutant`) are kept as delimited strings, not split.

## Columns

| column | definition |
|---|---|
| `PGM_SYS_ID` | ICIS-Air facility (program-system) id |
| `comp_determination_uid` | distinct compliance-determination id (the event id) |
| `date` | determination date (parsed; FRV date, else HPV day-zero) |
| `year` | determination calendar year |
| `hpv` | 1 if a High Priority Violation (day-zero present), else 0 |
| `hpv_dayzero_date` | HPV clock start (parsed Date; `NA` for non-HPV) |
| `hpv_resolved_date` | HPV close (parsed Date; `NA` if unresolved) |
| `program` | regulatory program(s), delimited string |
| `pollutant` | pollutant(s), delimited string |
| `agency` | agency type |
| `dup` | occurrence index within the event id (0 = first row) |
| `dup_exact` | 1 if byte-identical (on kept columns) to an earlier row |

## Nuances

- **Coverage ramp.** Coverage of the determination-date fields increases over the window, so
  early-year counts are sparse — a reporting artifact, not a real decline.
- **Junk dates.** A few source dates carry implausible years (e.g. 3-digit years); these fail to
  parse (`NA`), and the row is dropped if it has no other usable date.
- **HPV spells span years.** Many HPV spells run across multiple calendar years (day-zero to
  resolution); some are unresolved (`hpv_resolved_date` is `NA`).
- **Delimited codes.** `program` and `pollutant` may hold several values in one string.

Column definitions and current summaries are also generated into the docs site
([dictionary](../../docs/dictionary.qmd), [distributions](../../docs/distributions.qmd)).
