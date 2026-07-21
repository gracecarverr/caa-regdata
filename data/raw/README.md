# data/raw — immutable source downloads

**Never edit anything here.** Raw is immutable; every derived asset is rebuilt from these by code. Files are
**gitignored** (large); only `.gitkeep` and `MANIFEST.csv` are tracked. Acquisition is documented in
[`code/01_data_download/README.md`](../../code/01_data_download/README.md); institutional context for each
source is in [`briefs/00_institutional_overview.md`](../../briefs/00_institutional_overview.md).

## Sources

| path | source | what | downloaded | cleaned into (`data/processed/`) |
|------|--------|------|------------|----------------------------------|
| `ICIS-AIR_downloads/` | ICIS-Air (EPA ECHO), current bulk download | 10 tables: facilities, FCES/PCES, violations, formal/informal actions, Title V certs, stack tests, pollutants, programs, program subparts | 2026-07-13 (MANIFEST) | inspections, violations, formal_actions, informal_actions, certs, stacktests, facilities, pollutants, programs, program_subparts |
| `ICIS_AIR_WAYBACK/ICIS-AIR_downloads_<year>/` | archived annual ICIS-Air snapshots, 2015–2025 (~Q4 each year) | staged ~2026-07-13; each file's OWN mtime is the original **capture** date (Sep 2015 – Sep 2025), not the staging date — no MANIFEST row | **10 real** yearly snapshots — 2018 has no real archived capture (was a mislabeled duplicate of 2019, removed 2026-07-21; see W7) and is carried as explicit `NA`, not a folder | wayback_facility_status, wayback_facility_spells, wayback_program_status |
| `afs_downloads/` | AFS — legacy Air Facility System (pre-2001) | 2026-07-13 (file mtime; no MANIFEST row) | 5 tables: actions, air program, facilities, historical compliance, HPV history | afs_actions, afs_air_program, afs_facilities, afs_hist_compliance, afs_hpv |
| `frs/FRS_FACILITIES.csv` | FRS — Facility Registry Service | 2026-07-13 (MANIFEST) | cross-system facility registry → **coordinates** (via `REGISTRY_ID`) | used by the spine (not a standalone processed asset) |
| `greenbook/pm25_2012_status/<year>.dbf` | EPA Green Book (archived) | 2026-07-13 (file mtime; no MANIFEST row) | yearly PM2.5 (2012 std) nonattainment/maintenance **status** by area | attainment (panel layer) |
| `greenbook/pm25_2012_naa/PM25_2012Std_NAA.shp` | EPA Green Book | 2026-07-13 (MANIFEST) | PM2.5 nonattainment **area polygons** (for point-in-polygon placement) | attainment (panel layer) |
| `us_counties/us_counties.shp` | US county boundaries | 2026-07-13 (MANIFEST); **replaced 2026-07-21** with the full-US Census file (N18) — old CONUS-filtered file was not the raw product | county polygons → `county_fips` via point-in-polygon | used by the spine |
| `POLL_RPT_COMBINED_EMISSIONS.csv` | EPA combined emissions report | 2026-07-13 (file mtime; no MANIFEST row) | facility emissions by pollutant × reporting year | emissions |
| `MANIFEST.csv` | — (generated) | — | provenance: `source, file, url, downloaded_at, md5` per downloaded file | — |

`code/01_data_download/01_download.R` automates ICIS-Air, AFS, combined emissions, US counties, and the Green
Book NAA shapefile as of 2026-07-21 (re-verified byte-identical against the 2026-07-13 staged files that
session, except US counties — see N18). FRS and the Wayback snapshots stay manually staged (unreliable source
server / incomplete capture coverage respectively — see `code/01_data_download/README.md`).

## Institutional facts that matter here

- **The current ICIS-Air download is a single snapshot** — it has current operating status/class/industry and
  **no facility entry/exit dates**. That is *why* `ICIS_AIR_WAYBACK/` exists: the annual snapshots let the
  pipeline reconstruct year-varying operating status and entry/exit spells (see the overview brief §3, and
  decisions W1–W7 / F7). **2018 has no real snapshot** (W7) — treated as an explicit gap, not inferred.
- **FRS coordinates gate all geography.** A facility with no FRS match → `NA` coordinates → no county and no
  attainment placement (nuance N4).
- **Green Book coverage is narrow here** — only PM2.5 (2012 std), only the snapshot years — which is why the
  attainment asset is PM2.5-2016–2025 only (AT1).
- **AFS uses different identifiers than ICIS-Air**; don't join them without an explicit crosswalk.

## Provenance

`MANIFEST.csv` records where and when each raw file came from, but only for **icis_air/frs/us_counties/
greenbook-NAA** — AFS, the Wayback snapshots, and Green Book's yearly status files were staged without a
MANIFEST row (dates above are file-mtime estimates, not guaranteed). Keep `MANIFEST.csv` accurate as you add
files; `01_download.R` writes a row automatically for anything it fetches.
