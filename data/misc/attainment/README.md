# data/misc/attainment — EPA Green Book NAAQS nonattainment data (reference only, not pipeline-wired)

Copied 2026-07-28 from the sibling `CAA_Project` repo's `data/raw/attainment shapefiles/`. This is raw EPA
source material — **not modified**, and **not read by any script in this repo**. PM2.5-attainment
construction was deliberately removed from `caa-regdata` on 2026-07-27 (decision **W10**,
[`briefs/panel/panel_construction_decisions.md`](../../../briefs/panel/panel_construction_decisions.md),
archived under `archive/panel_building_legacy/`) because the working version already lived in `CAA_Project`
and a fresh clone here had no way to stage the Green Book status files it needed. This copy exists so that
history and a possible future revival don't require going back to `CAA_Project`.

## What's here

| path | what | pollutant-standards covered |
|------|------|------------------------------|
| `pm25_2012std_naa_shapefile/` | NAA (nonattainment-area) polygons, EPA OAQPS, published 2015 | PM2.5, 2012 NAAQS |
| `ozone_8hr_2008std_naa_shapefile/` | NAA polygons | 8-hr Ozone, 2008 NAAQS |
| `ozone_8hr_2015std_naa_shapefile/` | NAA polygons | 8-hr Ozone, 2015 NAAQS |
| `so2_2010std_naa_shapefile/` | NAA polygons | SO2, 2010 NAAQS |
| `lead_2008std_naa_shapefile/` | NAA polygons | Lead, 2008 NAAQS |
| `attainment greenbook status/<pollutant>_external_files/` | `.dbf`/`.xls` attribute tables (composid, area name, class, NAAStatus, revoked_std) — a **single current-as-of-download snapshot**, not a time series | all five standards above |

Each shapefile is CRS `NAD83` (geographic, unprojected). `composid` is the shared join key between a
shapefile's polygons and its matching external-file attribute table (format: `pollutant.standard-year.area`,
e.g. `PM-2.5.2012.Cleveland`). Field definitions for the external files are documented inline in each
`externalfiledata.txt`.

**Not included in this copy** (present in `CAA_Project` but out of scope for what was asked here — needed
only if the build pipeline itself is ever revived):
- `data/raw/greenbook_wayback_machine/pm25_2012/` — the **yearly** Green Book status snapshots (2016–2025,
  2023 missing) that make status time-varying. The `attainment greenbook status/` folder above is a single
  snapshot only; it cannot reproduce a facility × year panel by itself.
- `data/raw/phistory.xls` — the county-level, all-pollutant, all-year EPA Green Book history lookup used by
  the archived county-level approach (below).

## How it was used in `CAA_Project`

Two different approaches were built there, at different granularities:

**1. Sub-county, point-in-polygon, PM2.5-only, 2016–2025** — the working/current version
(`panel/scripts/assets/attainment.R`, and an earlier near-identical copy at
`code/03_panel_building/01_attainment.R`):
- Stacks the yearly Green Book Wayback `.dbf` snapshots into an area × year status table (`N` = nonattainment,
  `M` = maintenance/redesignated); a missing year (2023) is carried forward from the prior year and flagged
  `imputed`.
- Places each facility into a PM2.5 NAA polygon by exact lat/long point-in-polygon against
  `pm25_2012std_naa_shapefile/PM25_2012Std_NAA.shp` (not by county — sub-county precision).
- Joins the two into a facility × year table; a facility-year **absent** from the result means the facility
  was not inside a PM2.5 NAA that year (i.e. attainment) — absence is the implicit "0".
- Output columns: `PGM_SYS_ID, year, composid, area_name, status (N|M), class, imputed`.
- This fed 4 treatment columns on `CAA_Project`'s electric panel (`pm25_status`, `pm25_area`, `naa_pm25_2012`,
  `any_naa`) and a published summary table (`output/tables/t6_electric_attainment.tex`): 127 electric
  facilities (4.2%) were ever in a PM2.5 nonattainment area, 1,165 facility-years nonattainment vs. 28,035
  attainment, concentrated in San Joaquin Valley CA, LA-South Coast CA, Cleveland OH, Imperial County CA,
  and Delaware County PA.
- A near-duplicate pair of archived scripts (`archive/panel_analyses/13_build_pm25_attainment.R` and
  `14_plot_pm25_attainment.R`) built the same area × year and facility × year tables standalone and produced
  a redesignation timeline plot (N→M transitions by area, 2016–2025) — useful as a template if a visual
  audit of status changes is wanted again.

**2. County-level, all five pollutant-standards, 2005–2025** — an earlier, retired approach
(`archive/panel_funnel_v1/04_attach_attainment.R`), using `phistory.xls` (not the shapefiles at all):
point-in-county via `data/raw/us_counties`, then join county FIPS to Green Book `phistory`'s per-county,
per-pollutant, per-year `W`/`P`/blank codes (whole-county nonattainment / part-county nonattainment / blank =
attainment). Produced
5 flag columns (`naa_ozone_2008`, `naa_ozone_2015`, `naa_pm25_2012`, `naa_so2_2010`, `naa_lead_2008`) plus
`any_naa`, all coarser (county, not polygon) but covering every standard and a longer year range than the
Wayback approach allows. Retired in favor of approach 1's sub-county precision, but the code is intact if
county-level, all-pollutant coverage is ever preferred over point-in-polygon precision.

## What's here but never used

The `ozone_8hr_2008std`, `ozone_8hr_2015std`, `so2_2010std`, and `lead_2008std` NAA shapefiles (and their
matching external-file attribute tables) were **never read by any script** in `CAA_Project` — only the
PM2.5 2012 shapefile was ever used for point-in-polygon placement. They're carried here unused, in case a
future extension wants sub-county attainment status for those four other criteria pollutants. Extending
approach 1 to any of them is mechanical: swap in the matching shapefile and, if time-varying status is
wanted, a Wayback-style yearly snapshot series (not present for these four — only PM2.5 2012 has stacked
yearly snapshots in `CAA_Project`).

## Caveats inherited from the source scripts

- Attainment status was only ever built for PM2.5 (2012 standard) in the working approach; the other four
  standards are shapefile-only, unused, county-level-only (via `phistory.xls`), or both.
- The Wayback-based time series only covers 2016–2025, with 2023 imputed (carried forward from 2022) because
  no snapshot exists for that year.
- Point-in-polygon placement requires a facility coordinate (FRS-derived); facilities without one cannot be
  placed and are simply absent, not flagged `NA`.
- `status` is maintenance-aware (`N` vs `M`) — a facility in a redesignated-to-maintenance area is not the
  same as one that was never in nonattainment; collapsing the two (as `any_naa` does) discards that
  distinction.
