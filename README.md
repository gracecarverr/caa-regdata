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
[`briefs/institutional_overview.md`](briefs/institutional_overview.md) for the institutional setting.

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

The documentation site is a 3-page static site under `docs/` — Home (`index.html`, institutional overview),
Raw Data (`raw_data.html`, per-source summary tables), and Databases (`databases.html`). All three are
regenerated as part of `RUN_ALL.R` and committed, so GitHub Pages serves them directly with no build step —
see `code/diagnostics/README.md`. (A fourth, Panels, page existed while this repo also built facility-year
panels; it moved with the panel-building code — see below.)

## Computational requirements

- **R 4.4.3**, with package versions pinned in `renv.lock`. Run `renv::restore()` once to install the exact
  versions used to build this project — no manual package installation needed.
- No compiled dependencies outside CRAN binaries; no GPU, Stata, Python, or other language runtime required.
- No pseudo-random number generation is used anywhere in the pipeline (deterministic joins/aggregation only),
  so there is no seed to set.
- **Runtime and storage:** a full rebuild (`code/RUN_ALL.R` with `DOWNLOAD=true`) downloads several GB of raw
  EPA bulk data and takes on the order of an hour on a standard laptop, most of it in the download step;
  `DOWNLOAD=false` (reusing existing `data/raw/`) rebuilds processed/panel/dataset layers in a few minutes.
  Manually-staged sources (FRS, Wayback snapshots, Green Book yearly status — see Data Availability Statement
  below) must already be present in `data/raw/` for either mode to produce the full set of assets.

## Layout

```
caa-regdata/
├── code/                the pipeline (run with code/RUN_ALL.R)
│   ├── 00_setup/        package check, options, session record
│   ├── 01_data_download/  raw sources -> data/raw/ (immutable) + MANIFEST provenance
│   ├── 02_cleaning/     one bare-bones clean asset per raw table -> data/processed/
│   │                      (functions + parameters + a wayback/ subfolder for the bespoke cleaners)
│   ├── 04_datasets/     the six deliverable datasets (this repo's main product) -> data/datasets/
│   └── diagnostics/     NOT part of the build: dataset profiling, site generation, previews, one-offs
├── data/
│   ├── raw/             immutable downloads (gitignored) + MANIFEST.csv (provenance)
│   ├── processed/       one clean asset per raw table (gitignored, rebuilt from code)
│   └── datasets/        the six built datasets (gitignored, rebuilt from code)
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
| the institutional setting (statute, data systems) | [`briefs/institutional_overview.md`](briefs/institutional_overview.md) |
| **why** a construction choice was made | [`briefs/datasets/dataset_construction_decisions.md`](briefs/datasets/dataset_construction_decisions.md) (facility-spine/panel-layer decisions moved to the CAA_Project repo) |
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

### Data Availability Statement

All data used in this project are **public** EPA (or EPA-adjacent) data, either downloaded directly from
government servers or staged by hand from public archives (e.g. the Internet Archive Wayback Machine). No
confidential, proprietary, or access-restricted data are used, so nothing here is subject to a redistribution
or data-use-agreement restriction.

| Data.Name | Source | Location once staged | Provided in this repo | Acquisition |
|-----------|--------|----------------------|------------------------|-------------|
| ICIS-Air bulk tables | EPA ECHO bulk data downloads | `data/raw/ICIS-AIR_downloads/` | No (gitignored; rebuilt by `code/01_data_download/01_download.R`) | Automated |
| AFS legacy tables | EPA ECHO bulk data downloads (same bundle as ICIS-Air) | `data/raw/afs_downloads/` | No (gitignored) | Automated |
| Combined emissions report | EPA ECHO bulk data downloads | `data/raw/POLL_RPT_COMBINED_EMISSIONS.csv` | No (gitignored) | Automated |
| US counties boundaries | US Census Bureau cartographic boundary files (2022 vintage) | `data/raw/us_counties/` | No (gitignored) | Automated |
| EPA Green Book NAA polygons (current) | EPA Green Book shapefile download | `data/raw/greenbook/pm25_2012_naa/` | No (gitignored) | Automated |
| FRS facility coordinates | EPA Facility Registry Service (FRS) | `data/raw/frs/` | No (gitignored) | Manual — direct bulk download endpoint (`ordsext.epa.gov`) exists but repeatedly failed to transfer cleanly; staged by hand instead |
| ICIS-Air Wayback snapshots (2015–2025) | Internet Archive Wayback Machine, capturing the live ICIS-Air ECHO bundle | `data/raw/ICIS_AIR_WAYBACK/ICIS-AIR_downloads_<year>/` | No (gitignored) | Manual — no reliable per-year capture-selection rule found via the Wayback CDX API; see `code/01_data_download/README.md` |
| EPA Green Book yearly STATUS snapshots (2016–2025) | EPA Green Book, historical snapshots | `data/raw/greenbook/pm25_2012_status/` | No (gitignored) | Manual — no automatable source found |

Every raw file that `01_download.R` fetches is logged to `data/raw/MANIFEST.csv` with `source`, `file`, `url`,
`downloaded_at`, and `md5` — so any raw file's provenance can be traced even though raw data is not checked
into version control (see [`data/raw/README.md`](data/raw/README.md)). Manually-staged sources retain whatever
provenance was recorded at the time they were added; see `code/01_data_download/README.md` for exact
acquisition notes and known failure modes for the FRS and Wayback endpoints.

No rights or licensing restrictions apply: all sources are US federal government (EPA, Census) data or public
web archive captures of that same data, none of which carry redistribution restrictions.

## Status

Reorganized into the staged `code/` + `data/` + `briefs/` structure with per-folder and per-stage
documentation. The pipeline builds end-to-end through cleaning (ICIS-Air + AFS + emissions cleaners) and the
`04_datasets/` layer — the six deliverable datasets, this repo's main product (5 of 6 built & audited; PM2.5
attainment not yet started, see `briefs/datasets/dataset_construction_decisions.md`). Facility-spine/panel
building (universe / major_synmin / electric panels) moved to the CAA_Project repo (2026-07-23).

## License

TBD — decide before publishing.
