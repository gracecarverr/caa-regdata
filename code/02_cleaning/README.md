# 02_cleaning — raw sources → bare-bones "clean" assets

**Stage inputs:** `data/raw/*` (immutable downloads)
**Stage outputs:** `data/processed/*.csv.gz` (one per raw source)
**Run:** `Rscript code/02_cleaning/02_clean.R` — or as stage 2 of `code/RUN_ALL.R`.

## What this stage does (and deliberately does *not* do)

Cleaning here is **minimal by design**. Each raw source table becomes one `data/processed/<name>.csv.gz`
that **keeps every original column and every original row** — nothing is dropped, deduplicated, recoded,
or type-cast. All facility-selection, collapsing, and treatment logic happens later, in the datasets layer
(`code/04_datasets/`). Keeping cleaning lossless means the processed assets are a faithful, traceable
image of the raw data, and every downstream decision is auditable against them.

The only columns ever **added**:

| column      | added to        | meaning |
|-------------|-----------------|---------|
| `date`      | event tables    | a source date column parsed to a real `Date` |
| `year`      | event tables    | calendar year of `date` |
| `dup`       | event tables    | 0-based occurrence index within a within-facility event key (0 = first row). **Not** a dedup — it labels repeats so the panel layer can decide how to collapse them. |
| `dup_exact` | every table     | `1` if the row is byte-identical to an **earlier** row (a true duplicate record) |

> **Why label duplicates instead of dropping them?** Whether a repeat is a genuine second event or a data
> artifact is a *downstream construction* decision, not a cleaning one. Labeling keeps the choice visible
> and reversible. See `briefs/datasets/dataset_construction_decisions.md` (facility-spine/panel-layer
> decisions moved to the CAA_Project repo).

## Files

| file | role |
|------|------|
| `02_clean.R` | **driver** — sources the two files below, loops over `CLEAN_SPECS`, then runs the Wayback cleaners |
| `02_cleaning_functions.R` | shared mechanics: `read_raw`, `dup_index`, `write_clean`, `clean_one` |
| `02_cleaning_parameters.R` | `CLEAN_SPECS` — one entry per regular source (16 of 19) |
| `02_cleaning_functions_README.md` | function-by-function reference |
| `02_cleaning_parameters_README.md` | field-by-field reference + the full source→output table |
| `wayback/` | the 3 bespoke operating-status cleaners (17–19); see `wayback/README.md` |

## Structure: why 16 sources are data and 3 are scripts

16 of the 19 sources follow one of two regular shapes — **event** (add date/year/dup/dup_exact) or
**attribute** (add only dup_exact). Those differ only in *which* file, *which* date column, and *which*
duplicate key, so they are expressed as data in `CLEAN_SPECS` and executed by one function, `clean_one()`.

The 3 **Wayback** operating-status cleaners reconstruct a facility × year status history from 11 annual
snapshots (LOCF gap-filling, spell collapsing). That logic is genuinely bespoke, so those keep their own
scripts in `wayback/`.

## Per-asset documentation

Column-level definitions, row/facility counts, and **institutional implications** for each cleaned asset
live next to the data, in `data/processed/<name>.README.md`. The generated column dictionary is
`docs/data_dictionary.md`.
