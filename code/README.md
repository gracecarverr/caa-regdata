# code — the pipeline

Everything that builds the data, in dependency order. Run the whole thing with **`Rscript code/RUN_ALL.R`**
(see options below). Each stage folder has its own README with the details.

```
code/
├── RUN_ALL.R          one command: runs every stage in order
├── 00_setup/          check packages, set options, record session         (no data)
├── 01_data_download/  acquire raw sources -> data/raw/ (immutable)         + MANIFEST provenance
├── 02_cleaning/       one bare-bones clean asset per raw table -> data/processed/
├── 04_datasets/        six purpose-built deliverable datasets -> data/datasets/  (NOT yet wired into RUN_ALL; this repo's main product)
└── diagnostics/       NOT part of the build: dataset profiling, site generation, previews, one-offs
```

**Facility-spine/panel building (`03_panel_building/` → `data/panels/`) moved to the CAA_Project repo
(2026-07-23).** This repo's pipeline now ends at `02 clean`; `04_datasets/` is the deliverable layer.

## Pipeline stages

| stage | script | output | notes |
|-------|--------|--------|-------|
| 00 setup | `00_setup/00_setup.R` | `output/sessionInfo.txt` | package check + options; no data |
| 01 download | `01_data_download/01_download.R` | `data/raw/*` | idempotent; skip with `DOWNLOAD=false` |
| 02 clean | `02_cleaning/02_clean.R` | `data/processed/*.csv.gz` | keep every column/row; add only `date`/`year`/`dup`/`dup_exact` |
| 04 datasets | `04_datasets/0{1..6}_*.R` (run individually) | `data/datasets/*.csv.gz` | six full-universe deliverables (regulatory, operating, hpv_spells, hpv_active, penalties, coordinates); attainment not yet built; **not run by `RUN_ALL.R`** — see `04_datasets/README.md` |
| docs | `diagnostics/build_site.R` | `docs/index.html` | generated from `data/raw`; skip with `SKIP_SITE=true` |

## Run

```sh
Rscript code/RUN_ALL.R                    # full rebuild from raw
DOWNLOAD=false Rscript code/RUN_ALL.R     # reuse data/raw/ (skip the slow download)
SKIP_SITE=true  Rscript code/RUN_ALL.R    # don't regenerate docs/index.html
```

Package versions are pinned with `renv` — run `renv::restore()` once first.

## How the code is organized (the conventions)

- **Numbered stages run in dependency order.** `02` needs `01`'s raw; `04` needs `02`'s processed assets.
- **Modular where it pays, explicit where it doesn't.** `02_cleaning/` — `02_cleaning_functions.R` +
  `02_cleaning_parameters.R` (16 regular sources as data) + a `wayback/` subfolder for the 3 bespoke
  operating-status cleaners. Genuinely one-off scripts stay as their own scripts.
- **Raw is immutable.** Nothing in `data/raw/` is edited; every asset rebuilds from code.
- **Cleaning is lossless; selection/aggregation/treatment live in the datasets layer.** Keeps processed assets
  a faithful image of raw and every downstream choice auditable.
- **Docs are generated from data** (`build_site.R`), so they can't drift from it.
- **Reproducible & deterministic.** `renv` pins packages; `MANIFEST.csv` records source provenance; no
  stochastic step (so no seed); `tests/` assert invariants.

## Where the "why" lives

Code READMEs explain *how*. For *why* a construction choice was made see
**`briefs/datasets/dataset_construction_decisions.md`** (facility-spine/panel-layer decisions moved to the
CAA_Project repo alongside the code); for the institutional setting see
**`briefs/institutional_overview.md`**; for column-level detail see **`data/processed/*.README.md`** and
**`docs/data_dictionary.md`**.
