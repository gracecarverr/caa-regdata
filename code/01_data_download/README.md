# 01_data_download — acquire raw sources

**Stage input:** the internet (EPA ECHO) · **Stage output:** `data/raw/*` + `data/raw/MANIFEST.csv`
**Run:** `Rscript code/01_data_download/01_download.R` — or stage 1 of `code/RUN_ALL.R` (skipped when
`DOWNLOAD=false`).

## What this stage does

`01_download.R` fetches raw source tables into `data/raw/` and records provenance. It is **idempotent**: if a
source is already present it does nothing (raw is immutable — nothing here is ever edited or rebuilt in place).

Every successfully extracted file gets a row appended to `data/raw/MANIFEST.csv` recording `source`, `file`,
`url`, `downloaded_at`, and `md5` — so any raw file can be traced to where and when it came from.

## What is automated

| source | folder | acquisition |
|--------|--------|-------------|
| **ICIS-Air** bulk tables (EPA ECHO) | `data/raw/ICIS-AIR_downloads/` | **automated** — downloads & unzips the ECHO bundle |
| **AFS** legacy tables | `data/raw/afs_downloads/` | **automated** — same ECHO bulk directory as ICIS-Air |
| combined **emissions** report | `data/raw/POLL_RPT_COMBINED_EMISSIONS.csv` | **automated** — same ECHO bulk directory |
| **FRS** facility coordinates + program linkages | `data/raw/frs/` | **automated** — separate ECHO bulk zip; see note below |
| **US counties** boundaries | `data/raw/us_counties/` | **automated** — Census cartographic boundary file (2022 vintage), full US incl. AK/HI/PR |
| ICIS-Air **Wayback** snapshots (2015–2017, 2019–2025) | `data/raw/ICIS_AIR_WAYBACK/ICIS-AIR_downloads_<year>/` | **automated** — pinned per-year to a confirmed capture timestamp, not a live search; see note below |

> All sources fetched here are automated (verified against the existing manually-staged files this session —
> byte-identical for ICIS-Air/AFS/Wayback, schema- and content-identical for FRS; US counties
> was found to differ structurally from the raw Census product and was deliberately updated to the full-US
> file, see `briefs/panel/panel_construction_decisions.md` N18). **FRS** and the **Wayback snapshots** were
> both automated this session after their respective problems were solved (the Green Book / PM2.5-attainment
> source that used to appear in this table was removed from this repo entirely on 2026-07-27 — see
> `data/raw/README.md`):
> - **FRS**: the URL previously tried, `ordsext.epa.gov/FLA/www3/state_files/national_combined.zip` (~1.26 GB),
>   turned out to be a real, working download (confirmed 2026-07-27, completes via the same retry/resume logic
>   already used elsewhere in this script) — but it's the **wrong product**: a 33-column multi-table FRS
>   export, not the 10-column `FRS_FACILITIES.csv` this pipeline actually uses (different row count too — 5.3M
>   vs. 3.26M rows). The real source, found by tracing `MANIFEST.csv`'s own recorded provenance for
>   `FRS_PROGRAM_LINKS.csv` back to the ECHO `frs-download-summary` page, is
>   `echo.epa.gov/files/echodownloads/frs_downloads.zip` — same bulk-zip pattern as ICIS-Air/AFS, confirmed
>   schema- and (allowing for registry drift between snapshot dates) content-identical to the staged file. It
>   bundles `FRS_FACILITIES.csv` and `FRS_PROGRAM_LINKS.csv` (both previously manual) plus `FRS_SIC_CODES.csv`
>   and `FRS_NAICS_CODES.csv` (not currently used by this pipeline).
> - **Wayback snapshots**: an earlier attempt picked one candidate per year (the latest capture in that
>   calendar year) and only reproduced the staged files for *some* years (2015/2017/2019/2020/2025 matched,
>   2016 didn't). `code/diagnostics/wayback_verify/wayback_verify.R` replaced that guess with an exhaustive check — every
>   distinct-content candidate per year, most-recent-first — and found **every currently-staged year
>   reproduces byte-for-byte from *some* capture**, including 2016 (a capture 5 days older than the one the
>   old heuristic tried) and 2021–2024 (never tested before). See `code/diagnostics/wayback_verify/README.md`
>   for the full finding. `01_download.R` now fetches each year from its **pinned, confirmed timestamp** —
>   not a live "latest capture" search, since that's exactly what produced the false 2016 negative and would
>   do the same for 2022/2024. **2018 stays excluded**: zero captures of this URL exist in the Archive at any
>   status code (the staged "2018" folder was a mislabeled duplicate of 2019, deleted per decision W7); there
>   is no capture to pin.
>
> `MANIFEST.csv` records provenance for whatever `01_download.R` actually downloads. The Wayback files
> **already staged on disk** predate this automation and have no MANIFEST row (raw is immutable — they are
> not retroactively re-fetched just to backfill provenance); any year re-acquired by a fresh `01_download.R`
> run from here on gets a real MANIFEST row like every other automated source.

## Institutional context

What each source *is* (ICIS-Air vs. the legacy AFS, FRS coordinates, the Wayback snapshots) and why it
matters is in `briefs/institutional_overview.md`. The Wayback snapshots exist because the live ICIS-Air
download is a single current snapshot with no history — see that brief, §2–§3.
