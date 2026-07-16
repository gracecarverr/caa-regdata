# caa-regdata

Regulatory data infrastructure for **EPA stationary-source air-pollution enforcement** under the Clean Air
Act. A reproducible pipeline that **downloads** raw EPA data, **cleans** each source into a
one-table-per-source asset, **builds** facility × year panels (with attainment treatment), and **documents**
everything in a generated static site.

## What this is for

Building facility × year panels of regulatory activity — inspections, violations, enforcement, Title V
certifications, stack tests, emissions — for empirical work on enforcement and compliance. The `electric`
panel pairs regulatory activity with **PM2.5 (2012) nonattainment treatment**; the Wayback reconstruction
recovers year-varying operating status and facility entry/exit that the current EPA download lacks. See
[`briefs/00_institutional_overview.md`](briefs/00_institutional_overview.md) for the institutional setting.

## Reproduce

```r
# once, to install pinned package versions:
install.packages("renv"); renv::restore()
```
```sh
# full rebuild from raw (download → clean → panels → docs):
Rscript code/RUN_ALL.R

# skip the slow download step (reuse whatever is in data/raw/):
DOWNLOAD=false Rscript code/RUN_ALL.R

# also skip regenerating the docs site:
DOWNLOAD=false SKIP_SITE=true Rscript code/RUN_ALL.R
```

The documentation site (`docs/index.html`) is regenerated as part of `RUN_ALL.R` and committed, so GitHub
Pages serves it directly with no build step.

## Layout

```
caa-regdata/
├── code/                the pipeline (run with code/RUN_ALL.R)
│   ├── 00_setup/        package check, options, session record
│   ├── 01_data_download/  raw sources -> data/raw/ (immutable) + MANIFEST provenance
│   ├── 02_cleaning/     one bare-bones clean asset per raw table -> data/processed/
│   │                      (functions + parameters + a wayback/ subfolder for the bespoke cleaners)
│   ├── 03_panel_building/  facility spine + attainment treatment + the sample panels -> data/panels/
│   │                      (build_panel() functions + PANEL_SPECS parameters)
│   └── diagnostics/     NOT part of the build: panel summaries, site generation, previews, one-offs
├── data/
│   ├── raw/             immutable downloads (gitignored) + MANIFEST.csv (provenance)
│   ├── processed/       one clean asset per raw table (gitignored, rebuilt from code)
│   └── panels/          spine + attainment + sample panels (gitignored, rebuilt from code)
├── briefs/              institutional overview + construction-decision & open-question briefs
├── docs/                generated static site (index.html) + data_dictionary.md
├── output/             generated tables/figures (e.g. panel-summary LaTeX) + sessionInfo.txt
└── tests/              invariant checks on the built assets
```

Every folder has a `README.md`. Start with [`code/README.md`](code/README.md) for the pipeline and
[`data/README.md`](data/README.md) for the data.

## Design principles

- **Raw is immutable.** Nothing in `data/raw/` is ever edited; every asset rebuilds from code.
- **Cleaning is lossless.** One clean asset per raw table, keeping every column and every row (adds only
  `date`/`year`/`dup`/`dup_exact`). Sample selection, aggregation, and treatment live in the panel layer, so
  the processed assets stay a faithful, auditable image of the raw data.
- **Modular where it pays.** The two stages with heavy repetition (cleaning, panel building) are factored into
  a small set of **functions** plus a **parameters** file listing what differs per source/panel, driven by a
  thin loop. Genuinely one-off scripts (spine, attainment, the Wayback cleaners) stay explicit.
- **Docs are generated from the data**, so they can't drift from it.
- **Reproducible & deterministic.** `renv` pins packages; `RUN_ALL.R` rebuilds everything from raw;
  `data/raw/MANIFEST.csv` records source URLs/dates/checksums; there is no stochastic step (so no seed);
  `tests/` assert invariants.

## Documentation map

| you want… | look in |
|-----------|---------|
| to run the pipeline | [`code/README.md`](code/README.md), `code/RUN_ALL.R` |
| the institutional setting (statute, data systems) | [`briefs/00_institutional_overview.md`](briefs/00_institutional_overview.md) |
| **why** a construction choice was made | [`briefs/panel_construction_decisions.md`](briefs/panel_construction_decisions.md) |
| what's still undecided | [`briefs/panel_open_questions.md`](briefs/panel_open_questions.md) |
| column/field definitions | [`docs/data_dictionary.md`](docs/data_dictionary.md) |
| what each data file is + caveats | the per-layer READMEs under [`data/`](data/README.md) |

## Data sources

| Source | What | Acquisition |
|--------|------|-------------|
| ICIS-Air (EPA ECHO) | facilities, inspections, violations, enforcement, Title V certs, stack tests, programs | bulk download (automated) |
| ICIS-Air Wayback | 11 annual snapshots (2015–2025) → operating-status history & entry/exit | archived, staged manually |
| AFS | legacy (pre-2001) actions, air program, HPV, historical compliance | staged manually |
| FRS | facility coordinates / cross-system ids | staged manually |
| EPA Green Book | PM2.5 (2012) attainment status — current shapefiles + Wayback snapshots for history | staged manually |
| Combined emissions | facility emissions by pollutant × year | staged manually |

> Only the ICIS-Air current bulk download is one-click; the Wayback snapshots and other sources are staged
> into `data/raw/` by hand (see [`code/01_data_download/README.md`](code/01_data_download/README.md)).

## Status

Reorganized into the staged `code/` + `data/` + `briefs/` structure with per-folder and per-stage
documentation. The pipeline builds end-to-end (ICIS-Air + AFS + emissions cleaners, facility spine, PM2.5
attainment, and the universe / major_synmin / electric panels). Ozone/SO₂/lead attainment and the AFS↔ICIS
crosswalk are future work — see [`briefs/panel_open_questions.md`](briefs/panel_open_questions.md).

## License

TBD — decide before publishing.
