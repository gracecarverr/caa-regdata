# `<asset>` — <Human Title>

**Source:** <raw file(s)> (<acquisition>; provenance in `data/raw/MANIFEST.csv`).
**Built by:** [`<NN>_<asset>.R`](<NN>_<asset>.R) → `data/clean/<asset>.csv.gz`.
**Grain:** one row per <raw record>. Distinct <events> = `filter(dup == 0)`.

## What it is

<One paragraph: what a row represents.>

## Cleaning decisions

- **Date** = <rule>.
- **No deduplication.** Every raw row is kept; duplicates are labelled `dup` / `dup_exact`.
- **Dropped rows.** <what is dropped and why> — never imputed; count printed at build time.
- <other dataset-specific decisions>

## Columns

| column | definition |
|---|---|
| ... | ... |

## Nuances

- <reporting artifacts, coverage ramps, duplicate structure, delimited fields, junk values ...>

Column definitions and current summaries are also generated into the docs site
([dictionary](../../docs/dictionary.qmd), [distributions](../../docs/distributions.qmd)).
