# `enforcement` — ICIS-Air Formal + Informal Actions

**Source:** EPA ICIS-Air `ICIS-AIR_FORMAL_ACTIONS.csv` + `ICIS-AIR_INFORMAL_ACTIONS.csv` (ECHO bulk download; provenance in `data/raw/MANIFEST.csv`).
**Built by:** [`03_enforcement.R`](03_enforcement.R) → `data/clean/enforcement.csv.gz`.
**Grain:** one row per raw action record. Distinct actions = `filter(dup == 0)`.

## What it is

One **enforcement action** per event. Formal and informal actions are pooled into one measure, tagged
by `kind`. Formal actions may carry a monetary penalty; informal actions do not.

## Cleaning decisions

- **Date** = formal: `SETTLEMENT_ENTERED_DATE`; informal: `ACHIEVED_DATE` (parsed).
- **Penalty** = `parse_number(PENALTY_AMOUNT)` on **formal** actions only (else `NA`).
- **No deduplication.** Every raw row is kept; duplicates flagged within `(kind, PGM_SYS_ID, enf_identifier)`.
- **Dropped rows.** Records with no `PGM_SYS_ID` or an unparseable date are dropped (never imputed);
  count printed at build time.

## Columns

| column | definition |
|---|---|
| `PGM_SYS_ID` | ICIS-Air facility id |
| `enf_identifier` | enforcement action id (the event id, within `kind`) |
| `date` | action date (formal: settlement; informal: achieved) |
| `year` | action calendar year |
| `kind` | `formal` \| `informal` |
| `agency` | lead agency flag |
| `enf_type` | action type |
| `penalty` | monetary penalty (formal only, else `NA`) |
| `dup` | occurrence index within `(kind, PGM_SYS_ID, enf_identifier)` (0 = first row) |
| `dup_exact` | 1 if byte-identical (on kept columns) to an earlier row |

## Nuances

- **Informal actions are substantially duplicated** at this grain; formal actions barely.
  Use `dup == 0` for a distinct-action count.
- **Settlement-date lag.** A formal action's settlement date can trail the filing by months or years.
- **Multi-facility settlements broadcast one penalty** across every co-defendant facility — do **not**
  sum `penalty` across facilities for a national total; sum over `dup == 0` within a facility.

Column definitions and current summaries are also generated into the docs site
([dictionary](../../docs/dictionary.qmd), [distributions](../../docs/distributions.qmd)).
