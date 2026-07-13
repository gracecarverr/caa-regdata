# `attainment` — PM2.5 (2012 NAAQS) Nonattainment Treatment

**Source:** EPA Green Book PM2.5 (2012 std) status snapshots recovered from the Wayback Machine
(`data/raw/greenbook/pm25_2012_status/<year>.dbf`) + the nonattainment-area polygon shapefile
(`.../pm25_2012_naa/PM25_2012Std_NAA.shp`); facility coordinates from the spine. Provenance in `data/raw/MANIFEST.csv`.
**Built by:** [`10_attainment.R`](10_attainment.R) → `data/clean/attainment.csv.gz`. **Runs after** the facilities spine.
**Grain:** one row per **facility-year** for facilities **inside** a PM2.5 NAA. Absence = attainment.

## What it is

A time-varying, sub-county, maintenance-aware PM2.5 nonattainment status: for each facility that sits inside a
PM2.5 (2012) nonattainment-area boundary, its `N` (nonattainment) / `M` (maintenance) status by year.

## Cleaning decisions

- **Stack yearly Green Book snapshots** into an area × year status series, then place each facility into a
  NAA polygon by **point-in-polygon** on its exact coordinate (not by county).
- **Maintenance-aware:** `status` is `N` or `M`; a facility-year **absent** from this asset means the
  facility was not inside a PM2.5 NAA that year (attainment).
- **One missing snapshot year is carried forward** from the prior year and flagged `imputed`.
- Facilities **without coordinates cannot be placed** and are absent.

## Columns

| column | definition |
|---|---|
| `PGM_SYS_ID` | ICIS-Air facility id |
| `year` | calendar year (snapshot window only) |
| `composid` | id of the PM2.5 NAA the facility falls inside |
| `area_name` | nonattainment-area name |
| `status` | `N` = nonattainment / `M` = maintenance |
| `class` | NAA classification |
| `imputed` | `TRUE` if that year's snapshot was missing and carried forward |

## Coverage / limitations (deliberately narrow)

- **PM2.5 (2012 standard) only** — ozone / SO2 / lead are not built.
- **Snapshot window only** (2016–2025 here; 2023 carried forward). Outside it there is no PM2.5 status.
- **Sub-county:** placement is by coordinate against the actual NAA boundary.
- To use as treatment on a panel, join with `attach_pm25_attainment()` (`R/panel.R`), which turns absence
  into attainment and marks facility-years outside coverage / unplaceable facilities as `NA`.

Column definitions and current summaries are also generated into the docs site
([dictionary](../../docs/dictionary.qmd), [distributions](../../docs/distributions.qmd)).
