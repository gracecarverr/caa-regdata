# caa-regdata

Regulatory data infrastructure for EPA stationary-source air-pollution enforcement.
A reproducible pipeline that **downloads** raw EPA data, **cleans** each source into a
documented data asset, **documents** it (dictionary, variable distributions, known
nuances), and **builds** sample facility × year panels.

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

Render the documentation site (requires [Quarto](https://quarto.org)):

```bash
quarto render docs
```

## Layout

```
caa-regdata/
├── run_all.R           one command: sources the numbered pipeline in order
├── config.yml          single source of truth — window, paths, source URLs
├── R/                  reusable functions (scripts stay thin, call these)
│   ├── setup.R         config, paths, constants, shared helpers
│   ├── download.R  clean.R  panel.R  document.R
├── scripts/            the pipeline (numbered, ordered)
│   ├── 01_download.R
│   ├── 02_clean/       one cleaning script per dataset (numbered; spine last)
│   ├── 03_document.R   writes generated tables/figures the docs read
│   └── 04_build_panels.R
├── data/
│   ├── raw/            immutable downloads (gitignored) + MANIFEST.csv (provenance)
│   ├── clean/          documented assets
│   └── panels/         sample panels (gitignored, rebuilt from code)
├── docs/               Quarto site — auto-rendered from data/clean/
└── tests/              schema + invariant checks
```

## Design principles

- **Raw is immutable.** Nothing in `data/raw/` is ever edited; every asset rebuilds from code.
- **One job per file.** One cleaning script per dataset; cleaning never does sample
  selection or aggregation (that lives in the panel layer).
- **Docs are generated from the data**, so they can't drift from it.
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

- [x] Scaffold (structure, config, `run_all.R`, docs skeleton)
- [x] Vertical slice: **violations** end-to-end (download → clean → dictionary → distribution → test)
- [ ] Remaining cleaners + facilities spine
- [ ] Quarto site: generated dictionary + distributions, nuances, decisions
- [ ] `build_panel()` + sample panels + codebooks
- [ ] Validation tests

## License

TBD — decide before publishing.
