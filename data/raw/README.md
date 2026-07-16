# data/raw — immutable source downloads

**Never edit anything here.** Raw is immutable; every derived asset is rebuilt from these by code. Files are
**gitignored** (large); only `.gitkeep` and `MANIFEST.csv` are tracked. Acquisition is documented in
[`code/01_data_download/README.md`](../../code/01_data_download/README.md); institutional context for each
source is in [`briefs/00_institutional_overview.md`](../../briefs/00_institutional_overview.md).

## Sources

| path | source | what | cleaned into (`data/processed/`) |
|------|--------|------|----------------------------------|
| `ICIS-AIR_downloads/` | ICIS-Air (EPA ECHO), current bulk download | 10 tables: facilities, FCES/PCES, violations, formal/informal actions, Title V certs, stack tests, pollutants, programs, program subparts | inspections, violations, formal_actions, informal_actions, certs, stacktests, facilities, pollutants, programs, program_subparts |
| `ICIS_AIR_WAYBACK/ICIS-AIR_downloads_<year>/` | archived annual ICIS-Air snapshots, 2015–2025 (~Q4 each year) | 11 yearly snapshots of the ICIS-Air tables | wayback_facility_status, wayback_facility_spells, wayback_program_status |
| `afs_downloads/` | AFS — legacy Air Facility System (pre-2001) | 5 tables: actions, air program, facilities, historical compliance, HPV history | afs_actions, afs_air_program, afs_facilities, afs_hist_compliance, afs_hpv |
| `frs/FRS_FACILITIES.csv` | FRS — Facility Registry Service | cross-system facility registry → **coordinates** (via `REGISTRY_ID`) | used by the spine (not a standalone processed asset) |
| `greenbook/pm25_2012_status/<year>.dbf` | EPA Green Book (archived) | yearly PM2.5 (2012 std) nonattainment/maintenance **status** by area | attainment (panel layer) |
| `greenbook/pm25_2012_naa/PM25_2012Std_NAA.shp` | EPA Green Book | PM2.5 nonattainment **area polygons** (for point-in-polygon placement) | attainment (panel layer) |
| `us_counties/us_counties.shp` | US county boundaries | county polygons → `county_fips` via point-in-polygon | used by the spine |
| `POLL_RPT_COMBINED_EMISSIONS.csv` | EPA combined emissions report | facility emissions by pollutant × reporting year | emissions |
| `MANIFEST.csv` | — (generated) | provenance: `source, file, url, downloaded_at, md5` per downloaded file | — |

## Institutional facts that matter here

- **The current ICIS-Air download is a single snapshot** — it has current operating status/class/industry and
  **no facility entry/exit dates**. That is *why* `ICIS_AIR_WAYBACK/` exists: the 11 annual snapshots let the
  pipeline reconstruct year-varying operating status and entry/exit spells (see the overview brief §3, and
  decisions W1–W6 / F7).
- **FRS coordinates gate all geography.** A facility with no FRS match → `NA` coordinates → no county and no
  attainment placement (nuance N4).
- **Green Book coverage is narrow here** — only PM2.5 (2012 std), only the snapshot years — which is why the
  attainment asset is PM2.5-2016–2025 only (AT1).
- **AFS uses different identifiers than ICIS-Air**; don't join them without an explicit crosswalk.

## Provenance

`MANIFEST.csv` records where and when each raw file came from. Only the ICIS-Air current bulk download is
fully automated; the Wayback snapshots and other sources are staged manually — keep `MANIFEST.csv` accurate
as you add files.
