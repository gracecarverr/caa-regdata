# `inspections` — ICIS-Air Compliance Evaluations (FCE/PCE)

**Source:** EPA ICIS-Air `ICIS-AIR_FCES_PCES.csv` (ECHO bulk download; provenance in `data/raw/MANIFEST.csv`).
**Built by:** [`01_inspections.R`](01_inspections.R) → `data/clean/inspections.csv.gz`.
**Grain:** one row per raw evaluation record. Distinct evaluations = `filter(dup == 0)`.

## What it is

One **compliance evaluation** per event. Full Compliance Evaluations (FCE) and Partial Compliance
Evaluations (PCE) are pooled into a single "inspections" measure; `type` preserves the distinction.

## Cleaning decisions

- **Date** = `ACTUAL_END_DATE` (evaluation completion), parsed with `mdy()`.
- **Pool FCE + PCE** into one measure; keep `type`, `monitor_type`, and conducting `agency`.
- **No deduplication.** Every raw row is kept; duplicates flagged `dup` / `dup_exact`.
- **Dropped rows.** Records with no `PGM_SYS_ID` or an unparseable date are dropped (never imputed);
  count printed at build time.

## Columns

| column | definition |
|---|---|
| `PGM_SYS_ID` | ICIS-Air facility id |
| `activity_id` | distinct evaluation id (the event id) |
| `date` | evaluation completion date (parsed) |
| `year` | evaluation calendar year |
| `type` | full (FCE) vs partial (PCE), etc. |
| `monitor_type` | compliance-monitoring type |
| `agency` | conducting agency (E=EPA / S=State / L=Local) |
| `dup` | occurrence index within the event id (0 = first row) |
| `dup_exact` | 1 if byte-identical (on kept columns) to an earlier row |

## Nuances

- **Very low duplication** at this grain — the flag is near-inert here, kept for schema consistency.
- **Pooled measure.** FCE and PCE are combined; split on `type` if the distinction matters.

Column definitions and current summaries are also generated into the docs site
([dictionary](../../docs/dictionary.qmd), [distributions](../../docs/distributions.qmd)).
