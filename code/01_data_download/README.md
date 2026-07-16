# 01_data_download — acquire raw sources

**Stage input:** the internet (EPA ECHO) · **Stage output:** `data/raw/*` + `data/raw/MANIFEST.csv`
**Run:** `Rscript code/01_data_download/01_download.R` — or stage 1 of `code/RUN_ALL.R` (skipped when
`DOWNLOAD=false`).

## What this stage does

`01_download.R` fetches raw source tables into `data/raw/` and records provenance. It is **idempotent**: if a
source is already present it does nothing (raw is immutable — nothing here is ever edited or rebuilt in place).

Every successfully extracted file gets a row appended to `data/raw/MANIFEST.csv` recording `source`, `file`,
`url`, `downloaded_at`, and `md5` — so any raw file can be traced to where and when it came from.

## What is automated vs. staged manually

| source | folder | acquisition |
|--------|--------|-------------|
| **ICIS-Air** bulk tables (EPA ECHO) | `data/raw/ICIS-AIR_downloads/` | **automated** — downloads & unzips the ECHO bundle |
| ICIS-Air **Wayback** snapshots (2015–2025) | `data/raw/ICIS_AIR_WAYBACK/ICIS-AIR_downloads_<year>/` | **semi-manual** — archived annual captures, staged by hand |
| **FRS** facility coordinates | `data/raw/frs/` | staged manually |
| **AFS** legacy tables | `data/raw/afs_downloads/` | staged manually |
| **Green Book** attainment (current + Wayback) | `data/raw/greenbook/` | staged manually |
| **US counties** boundaries | `data/raw/us_counties/` | staged manually |
| combined **emissions** report | `data/raw/POLL_RPT_COMBINED_EMISSIONS.csv` | staged manually |

> Only the ICIS-Air bulk download is fully one-click today. The Wayback snapshots and the other sources are
> staged into `data/raw/` by hand (see the `TODO` in `01_download.R`); their provenance is recorded in
> `MANIFEST.csv` when present. Because these are the historical backbone of the panels, keep `MANIFEST.csv`
> accurate as you add snapshots.

## Institutional context

What each source *is* (ICIS-Air vs. the legacy AFS, FRS coordinates, Green Book attainment, the Wayback
snapshots) and why it matters is in `briefs/00_institutional_overview.md`. The Wayback snapshots exist because
the live ICIS-Air download is a single current snapshot with no history — see that brief, §2–§3.
