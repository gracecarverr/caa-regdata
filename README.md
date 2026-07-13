# caa-regdata

Regulatory data infrastructure for EPA stationary-source air-pollution enforcement.
A reproducible pipeline that **downloads** raw EPA data, **cleans** each source into a
one-table-per-source data asset, **summarizes** the assets in a static site, and **builds**
sample facility × year panels.

> **Status: scaffold.** Structure and conventions are in place; the pipeline stages are
> stubs to be filled in dataset by dataset. See *Roadmap* below.

## Reproduce

```r
# once, to install pinned package versions:
install.packages("renv"); renv::restore()

# full rebuild from raw (downloads, cleans, documents, builds panels):
Rscript run_all.R

# skip the slow download step (reuse whatever is in data/raw/):
DOWNLOAD=false Rscript run_all.R
```

The documentation site (`docs/index.html`) is regenerated as part of `run_all.R` (the build-site step)
and committed, so GitHub Pages serves it directly with no build step.

## Layout

```
caa-regdata/
├── run_all.R           one command: sources the numbered pipeline in order
├── scripts/            the pipeline — self-contained scripts (no shared R/ layer, no config)
│   ├── 01_download.R   raw sources into data/raw/ (immutable) + provenance
│   ├── 02_clean/       one bare-bones cleaner per raw table (numbered)
│   ├── 03_build_site.R writes docs/index.html summary tables from data/clean/
│   └── 04_panels/      facility spine (00), attainment treatment (01), then sample panels
├── data/
│   ├── raw/            immutable downloads (gitignored) + MANIFEST.csv (provenance)
│   ├── clean/          one clean asset per raw table (gitignored, rebuilt from code)
│   └── panels/         spine + attainment + sample panels (gitignored, rebuilt from code)
├── docs/               committed static site (index.html) + nuances.md / decisions.md
└── tests/              invariant checks
```

Every script is standalone: it hard-codes its own paths and constants and inlines whatever it needs,
so it can be read and run on its own without chasing sourced helpers.

## Design principles

- **Raw is immutable.** Nothing in `data/raw/` is ever edited; every asset rebuilds from code.
- **One job per file.** One cleaner per raw table; cleaning keeps every column and every row (adds only
  `date`/`year`/`dup`/`dup_exact`) and never does sample selection or aggregation (that lives in the
  panel layer).
- **Self-contained scripts.** No shared `R/` helper layer and no `config.yml`; each script hard-codes its
  own paths and constants, so nothing is hidden behind a `source()`.
- **Docs are generated from the data** (`03_build_site.R`), so they can't drift from it.
- **Reproducible.** `renv` pins packages; `run_all.R` rebuilds everything from raw;
  `data/raw/MANIFEST.csv` records source URLs, dates, and checksums; `tests/` assert invariants.

## Data sources

| Source | What | Acquisition |
|---|---|---|
| ICIS-Air (EPA ECHO) | facilities, inspections, violations, enforcement, Title V certs, stack tests, programs | bulk download |
| FRS | facility coordinates / cross-system ids | bulk download |
| EPA Green Book | attainment / nonattainment status | current shapefiles + **Wayback snapshots** for history (semi-manual) |

> Caveat: attainment *history* is only recoverable from archived Green Book snapshots
> (Wayback). That fetcher is assisted, not fully one-click — see `scripts/01_download.R`.

## Roadmap

- [x] Scaffold (structure, `run_all.R`, docs skeleton)
- [x] Vertical slice: **violations** end-to-end (download → clean → test)
- [x] Remaining cleaners + facilities spine
- [x] Static site (`03_build_site.R`): per-asset summary tables; committed nuances / decisions
- [x] Sample panels — standalone scripts in `scripts/04_panels/` (no configurable builder)
- [x] Flatten to self-contained scripts (remove the `R/` helper layer and `config.yml`)
- [x] Validation tests (`tests/test_assets.R`)
- [x] Attainment (Green Book / Wayback) + treatment panel (`electric.R`) — PM2.5 (2012); ozone next

## License

TBD — decide before publishing.
