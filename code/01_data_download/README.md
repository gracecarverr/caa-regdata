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
| **AFS** legacy tables | `data/raw/afs_downloads/` | **automated** — same ECHO bulk directory as ICIS-Air |
| combined **emissions** report | `data/raw/POLL_RPT_COMBINED_EMISSIONS.csv` | **automated** — same ECHO bulk directory |
| **US counties** boundaries | `data/raw/us_counties/` | **automated** — Census cartographic boundary file (2022 vintage), full US incl. AK/HI/PR |
| **Green Book** NAA boundary polygons (current) | `data/raw/greenbook/pm25_2012_naa/` | **automated** — direct EPA shapefile download |
| **FRS** facility coordinates | `data/raw/frs/` | staged manually — see note below |
| ICIS-Air **Wayback** snapshots (2015–2025) | `data/raw/ICIS_AIR_WAYBACK/ICIS-AIR_downloads_<year>/` | staged manually - all downlaoded in Q4 of given year|
| **Green Book** yearly STATUS snapshots (2016–2025) | `data/raw/greenbook/pm25_2012_status/` | staged manually — no automatable source found |

> Five of eight sources are automated (verified against the existing manually-staged files this session — byte-
> identical for ICIS-Air/AFS/Green Book NAA; US counties was found to differ structurally from the raw Census
> product and was deliberately updated to the full-US file, see `briefs/panel_construction_decisions.md` N18).
> **FRS** and the **Wayback snapshots** each had a working automation mechanism built and tested, but both
> were dropped in favor of staying manual:
> - **FRS**: `ordsext.epa.gov/FLA/www3/state_files/national_combined.zip` (~1.26 GB) is a real, direct URL, but
>   the endpoint failed to complete a clean transfer across 4 real attempts (truncated connections at varying
>   points). Not worth shipping an automation path that regularly fails.
>
> The **Green Book yearly status** snapshots never had a candidate mechanism — a Wayback query on the obvious
> URL returned no captures.
>
> `MANIFEST.csv` records provenance for whatever `01_download.R` actually downloads; manually-staged sources
> keep whatever provenance was recorded when they were added by hand.

## Institutional context

What each source *is* (ICIS-Air vs. the legacy AFS, FRS coordinates, Green Book attainment, the Wayback
snapshots) and why it matters is in `briefs/institutional_overview.md`. The Wayback snapshots exist because
the live ICIS-Air download is a single current snapshot with no history — see that brief, §2–§3.
