# code — the pipeline

Everything that builds the data, in dependency order. Run the whole thing with **`Rscript code/RUN_ALL.R`**
(see options below). Each stage folder has its own README with the details.

```
code/
├── RUN_ALL.R          one command: runs every stage in order
├── 00_setup/          check packages, set options, record session         (no data)
├── 01_data_download/  acquire raw sources -> data/raw/ (immutable)         + MANIFEST provenance
├── 02_cleaning/       one bare-bones clean asset per raw table -> data/processed/
├── 03_panel_building/  facility spine + attainment treatment + sample panels -> data/panels/
├── 04_datasets/        six purpose-built deliverable datasets -> data/datasets/  (NOT yet wired into RUN_ALL)
└── diagnostics/       NOT part of the build: panel summaries, site generation, previews, one-offs
```

## Pipeline stages

| stage | script | output | notes |
|-------|--------|--------|-------|
| 00 setup | `00_setup/00_setup.R` | `output/sessionInfo.txt` | package check + options; no data |
| 01 download | `01_data_download/01_download.R` | `data/raw/*` | idempotent; skip with `DOWNLOAD=false` |
| 02 clean | `02_cleaning/02_clean.R` | `data/processed/*.csv.gz` | keep every column/row; add only `date`/`year`/`dup`/`dup_exact` |
| 03 panels | `03_panel_building/03_build.R` | `data/panels/*.csv.gz` | spine → attainment → universe/major_synmin/electric |
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

- **Numbered stages run in dependency order.** `02` needs `01`'s raw; `03` needs `02`'s processed assets.
- **Modular where it pays, explicit where it doesn't.** The two stages with heavy repetition are factored
  into a small set of **functions** + a **parameters** file that lists what differs per source/panel, driven
  by a thin loop:
  - `02_cleaning/` — `02_cleaning_functions.R` + `02_cleaning_parameters.R` (16 regular sources as data) +
    a `wayback/` subfolder for the 3 bespoke operating-status cleaners.
  - `03_panel_building/` — `03_build_functions.R` (`build_panel()`) + `03_build_parameters.R` (`PANEL_SPECS`).
  Genuinely one-off scripts (spine, attainment, the wayback cleaners) stay as their own scripts.
- **Raw is immutable.** Nothing in `data/raw/` is edited; every asset rebuilds from code.
- **Cleaning is lossless; selection/aggregation/treatment live in the panel layer.** Keeps processed assets a
  faithful image of raw and every downstream choice auditable.
- **Docs are generated from data** (`build_site.R`), so they can't drift from it.
- **Reproducible & deterministic.** `renv` pins packages; `MANIFEST.csv` records source provenance; no
  stochastic step (so no seed); `tests/` assert invariants.

## Where the "why" lives

Code READMEs explain *how*. For *why* a construction choice was made (facility key, date rules, duplicate
handling, zero semantics, Wayback status, HPV intervals) see **`briefs/panel/panel_construction_decisions.md`**; for
the institutional setting see **`briefs/institutional_overview.md`**; for column-level detail see
**`data/processed/*.README.md`** and **`docs/data_dictionary.md`**.
