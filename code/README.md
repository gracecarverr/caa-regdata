# code — the pipeline

Everything that builds the data, in dependency order. Run the whole thing with **`Rscript code/RUN_ALL.R`**
(see options below). Each stage folder has its own README with the details.

```
code/
├── RUN_ALL.R          one command: runs every stage in order
├── 00_setup/          check packages, set options, record session         (no data)
├── 01_data_download/  acquire raw sources -> data/raw/ (immutable)         + MANIFEST provenance
├── 02_cleaning/       one bare-bones clean asset per raw table -> data/processed/
├── 03_datasets/        nine purpose-built deliverable datasets -> data/datasets/  (this repo's main product)
├── 04_panel_building/  facility spine + the two continuous panels -> data/panels/
└── diagnostics/       NOT part of the build: panel summaries, dataset profiling, site generation, previews, one-offs
```

## Pipeline stages

| stage | script | output | notes |
|-------|--------|--------|-------|
| 00 setup | `00_setup/00_setup.R` | `output/sessionInfo.txt` | package check + options; no data |
| 01 download | `01_data_download/01_download.R` | `data/raw/*` | idempotent; skip with `DOWNLOAD=false` |
| 02 clean | `02_cleaning/02_clean.R` | `data/processed/*.csv.gz` | keep every column/row; add only `date`/`year`/`dup`/`dup_exact` |
| 03 datasets | `03_datasets/0{1..8}_*.R` | `data/datasets/*.csv.gz` | nine full-universe deliverables (regulatory, operating, hpv_spells, hpv_active, penalties, coordinates, pipeline, emissions, wayback_only_facilities) — see `03_datasets/README.md` |
| 04 panels | `04_panel_building/00_spine.R` + panel builders | `data/panels/*.csv.gz` | two continuous facility × year panels, built on top of `03_datasets`' output |
| docs | `diagnostics/build_site.R`, `build_home.R`, `build_databases_page.R`, `18_panel_profile.R` + `build_panels_page.R` | `docs/{raw_data,index,databases,panels}.html` | 4-page site, generated from `data/raw`/briefs/panels; skip with `SKIP_SITE=true` |

## Run

```sh
Rscript code/RUN_ALL.R                    # full rebuild from raw
DOWNLOAD=false Rscript code/RUN_ALL.R     # reuse data/raw/ (skip the slow download)
SKIP_SITE=true  Rscript code/RUN_ALL.R    # don't regenerate docs/index.html
```

Package versions are pinned with `renv` — run `renv::restore()` once first.

## How the code is organized (the conventions)

- **Numbered stages run in dependency order.** `02` needs `01`'s raw; `03` needs `02`'s processed assets;
  `04` (panel building) needs `03`'s dataset outputs, not just `02`'s processed assets — the build order was
  inverted on 2026-07-28 so datasets build before panels.
- **Modular where it pays, explicit where it doesn't.** The two stages with heavy repetition are factored
  into a small set of **functions** + a **parameters** file that lists what differs per source/panel, driven
  by a thin loop:
  - `02_cleaning/` — `02_cleaning_functions.R` + `02_cleaning_parameters.R` (17 regular sources as data) +
    a `wayback/` subfolder for the 3 bespoke operating-status cleaners.
  - `04_panel_building/` — `03_build_functions.R` (`build_panel()`) + `03_build_parameters.R` (`PANEL_SPECS`).
  Genuinely one-off scripts (spine, the wayback cleaners) stay as their own scripts.
- **Raw is immutable.** Nothing in `data/raw/` is edited; every asset rebuilds from code.
- **Cleaning is lossless; selection/aggregation/treatment live in the panel and datasets layers.** Keeps
  processed assets a faithful image of raw and every downstream choice auditable.
- **Docs are generated from data** (`build_site.R`), so they can't drift from it.
- **Reproducible & deterministic.** `renv` pins packages; `MANIFEST.csv` records source provenance; no
  stochastic step (so no seed); `tests/` assert invariants.

## Where the "why" lives

Code READMEs explain *how*. For *why* a construction choice was made (facility key, date rules, duplicate
handling, zero semantics, Wayback status, HPV intervals) see **`briefs/panel/panel_construction_decisions.md`**
(panel layer) or **`briefs/datasets/dataset_construction_decisions.md`** (nine-dataset layer); for
the institutional setting see **`briefs/institutional_overview.md`**; for column-level detail see
the matching section in **`data/processed/README.md`** and **`docs/data_dictionary.md`**.
