# data

Everything the pipeline reads and writes. Four layers, in the order the pipeline builds them:

```
data/
├── raw/         immutable source downloads (gitignored; rebuilt via 01_download + manual staging)
├── processed/   one bare-bones "clean" asset per raw table (gitignored; rebuilt from raw by 02_cleaning)
├── panels/      derived spine + attainment + sample facility x year panels (gitignored; rebuilt by 03_panel_building)
└── datasets/    six purpose-built deliverable datasets, full universe (gitignored; rebuilt by 04_datasets)
```

Only `.gitkeep` files and `data/raw/MANIFEST.csv` are tracked; the data files themselves are **gitignored**
and rebuilt from code (`code/RUN_ALL.R`). This keeps the repo small and guarantees the data is always a
product of the committed pipeline, never hand-edited.

## What these data capture

This is **US Clean Air Act stationary-source regulatory data** — who is regulated, how often they're
inspected, what violations and enforcement actions occur, Title V compliance certifications, stack-test
results, emissions, and (via archived snapshots) how facilities' operating status and attainment designations
change over time. The backbone is **EPA ICIS-Air** (the current compliance/enforcement system), supplemented
by the legacy **AFS** system, **FRS** for coordinates, and the **Green Book** for attainment status. The
institutional setting — what each system is and why it matters — is in
[`briefs/institutional_overview.md`](../briefs/institutional_overview.md).

**What it's useful for.** Building facility × year panels of regulatory activity for empirical work on
enforcement and compliance: e.g. how inspections/violations/enforcement respond to attainment designation
(the `electric` panel pairs activity with PM2.5 nonattainment treatment), facility entry/exit dynamics (the
reconstructed Wayback spells), or program-specific compliance patterns.

## The four layers

| layer | built by | contents | README |
|-------|----------|----------|--------|
| [`raw/`](raw/) | `code/01_data_download` (+ manual staging) | EPA source CSVs/shapefiles, unmodified | [`raw/README.md`](raw/README.md) |
| [`processed/`](processed/) | `code/02_cleaning` | one lossless clean asset per raw table (+ `date`/`year`/`dup`/`dup_exact`) | [`processed/README.md`](processed/README.md) |
| [`panels/`](panels/) | `code/03_panel_building` | facility spine, PM2.5 attainment, and the three sample panels | [`panels/README.md`](panels/README.md) |
| [`datasets/`](datasets/) | `code/04_datasets` | six purpose-built deliverables (regulatory, operating, HPV spells/status, penalties, coordinates) over the full facility universe | [`datasets/README.md`](datasets/README.md) |

## Documentation map

- **Column/field definitions** (raw sources, from EPA's published dictionaries): [`docs/data_dictionary.md`](../docs/data_dictionary.md).
- **What each processed asset is, its counts, added columns, and institutional caveats:** the per-asset
  sections in [`processed/README.md`](processed/README.md).
- **Why construction choices were made (panels):** [`briefs/panel/panel_construction_decisions.md`](../briefs/panel/panel_construction_decisions.md).
- **Why construction choices were made (the six datasets):** [`briefs/datasets/dataset_construction_decisions.md`](../briefs/datasets/dataset_construction_decisions.md).
- **Provenance** (source, URL, download date, MD5) for raw files: `raw/MANIFEST.csv`.

> **Reproducibility invariant.** Never edit files under `raw/`. Derived data (`processed/`, `panels/`,
> `datasets/`) is rebuilt from code — change the script, not the data file. Every number in a table or
> figure should trace to a script and a logged run.
