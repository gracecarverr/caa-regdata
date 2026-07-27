# data/raw — immutable source downloads

**Never edit anything here.** Raw is immutable; every derived asset is rebuilt from these by code. Files are
**gitignored** (large); only `.gitkeep` and `MANIFEST.csv` are tracked. Acquisition is documented in
[`code/01_data_download/README.md`](../../code/01_data_download/README.md); institutional context for each
source is in [`briefs/institutional_overview.md`](../../briefs/institutional_overview.md).

## Sources

| path | source | what | downloaded | cleaned into (`data/processed/`) |
|------|--------|------|------------|----------------------------------|
| `ICIS-AIR_downloads/` | ICIS-Air (EPA ECHO), current bulk download | 10 tables: facilities, FCES/PCES, violations, formal/informal actions, Title V certs, stack tests, pollutants, programs, program subparts | **re-downloaded 2026-07-26** (MANIFEST) — original 2026-07-13 snapshot had 2 files (FCES_PCES, TITLEV_CERTS) go missing from disk; refreshed as a full new snapshot rather than patched, since ICIS-Air is EPA's live current-bulk download (no fixed archival checksum to restore against) | inspections, violations, formal_actions, informal_actions, certs, stacktests, facilities, pollutants, programs, program_subparts |
| `ICIS_AIR_WAYBACK/ICIS-AIR_downloads_<year>/` | archived annual ICIS-Air snapshots, 2015–2025 (~Q4 each year) | staged ~2026-07-13 (these 10 folders predate the automation below and have no MANIFEST row; each file's OWN mtime is the original **capture** date, Sep 2015 – Sep 2025, not the staging date) — `01_download.R` now automates re-acquisition, pinned per-year to the capture timestamp confirmed byte-for-byte by `code/diagnostics/wayback_verify/wayback_verify.R` (2026-07-27); any year fetched fresh from here on gets a real MANIFEST row — note the confirmed capture always contains all 10 tables, so a fresh fetch for 2022 (currently 9 files on disk) or 2023–2025 (currently 8) will end up with more files than what's staged right now, harmlessly (the cleaning scripts below read specific named files only) | **10 real** yearly snapshots — 2018 has no real archived capture (was a mislabeled duplicate of 2019, removed 2026-07-21; see W7) and is carried as explicit `NA`, not a folder | wayback_facility_status, wayback_facility_spells, wayback_program_status |
| `afs_downloads/` | AFS — legacy Air Facility System (pre-2001) | 2026-07-13 (file mtime; no MANIFEST row) | 5 tables: actions, air program, facilities, historical compliance, HPV history | afs_actions, afs_air_program, afs_facilities, afs_hist_compliance, afs_hpv |
| `frs/FRS_FACILITIES.csv` | FRS — Facility Registry Service | 2026-07-13 (MANIFEST) | cross-system facility registry → **coordinates** (via `REGISTRY_ID`) | used by the spine (not a standalone processed asset) |
| `frs/FRS_PROGRAM_LINKS.csv` | FRS — Facility Registry Service, program-system id crosswalk | 2026-07-26 (MANIFEST) | per-facility ids across every EPA program system (`PGM_SYS_ACRNM`, `PGM_SYS_ID`, `REGISTRY_ID`) — used ONLY as the bridge for the exploratory AFS↔ICIS crosswalk diagnostic (`code/diagnostics/afs_frs_match/`); not read by any pipeline stage | diagnostic-only, not cleaned into `data/processed/` |
| `us_counties/us_counties.shp` | US county boundaries | 2026-07-13 (MANIFEST); **replaced 2026-07-21** with the full-US Census file (N18) — old CONUS-filtered file was not the raw product | county polygons → `county_fips` via point-in-polygon | used by the spine |
| `POLL_RPT_COMBINED_EMISSIONS.csv` | EPA combined emissions report | 2026-07-13 (file mtime; no MANIFEST row) | facility emissions by pollutant × reporting year | emissions |
| `MANIFEST.csv` | — (generated) | — | provenance: `source, file, url, downloaded_at, md5` per downloaded file | — |

`code/01_data_download/01_download.R` automates every source in this table — ICIS-Air, AFS, combined
emissions, FRS, US counties, and the ICIS-Air Wayback snapshots (pinned per-year to a confirmed capture,
not a live search; see `code/diagnostics/wayback_verify/README.md`). Nothing here is staged manually.

**Removed 2026-07-27**: `greenbook/pm25_2012_status/` and `greenbook/pm25_2012_naa/` (PM2.5 attainment
data) — that code (`code/03_panel_building/01_attainment.R`) was already synced to the sibling `CAA_Project`
repo on 2026-07-23 and has been dropped from here entirely; see decision W10 in
`briefs/panel/panel_construction_decisions.md`.

## Institutional facts that matter here

- **The current ICIS-Air download is a single snapshot** — it has current operating status/class/industry and
  **no facility entry/exit dates**. That is *why* `ICIS_AIR_WAYBACK/` exists: the annual snapshots let the
  pipeline reconstruct year-varying operating status and entry/exit spells (see the overview brief §3, and
  decisions W1–W7 / F7). **2018 has no real snapshot** (W7) — treated as an explicit gap, not inferred.
- **FRS coordinates gate all geography.** A facility with no FRS match → `NA` coordinates → no county
  (nuance N4).
- **AFS uses different identifiers than ICIS-Air**; don't join them without an explicit crosswalk. A
  crosswalk (bridged through `frs/FRS_PROGRAM_LINKS.csv`) has been attempted — see
  `code/diagnostics/afs_frs_match/` and `briefs/datasets/afs_crosswalk_feasibility.md` — with partial,
  not-fully-resolved coverage.

## Provenance

`MANIFEST.csv` records where and when each raw file came from, but only for **icis_air/frs/us_counties**
(this includes `FRS_PROGRAM_LINKS.csv`, staged manually 2026-07-26 — not fetched by `01_download.R`) — AFS
was staged without a MANIFEST row (dates above are file-mtime estimates, not guaranteed). The 10 Wayback
year-folders **currently on disk** were also staged without a MANIFEST row (they predate `01_download.R`'s
Wayback automation and, being immutable raw data, are not retroactively re-fetched just to backfill
provenance) — but the automation now in place does write a MANIFEST row for any Wayback year it actually
fetches (e.g. on a fresh clone). Keep `MANIFEST.csv` accurate as you add files; `01_download.R` writes a
row automatically for anything it fetches.
