# `facilities` — the Facility Spine

**Source:** EPA ICIS-Air `ICIS-AIR_FACILITIES.csv`, `ICIS-AIR_POLLUTANTS.csv`, `ICIS-AIR_PROGRAMS.csv`;
EPA FRS `FRS_FACILITIES.csv` (coordinates); a CONUS county boundary shapefile. Provenance in `data/raw/MANIFEST.csv`.
**Built by:** [`09_facilities.R`](09_facilities.R) → `data/clean/facilities.csv.gz`. **Runs last** (reads the event assets).
**Grain:** **one row per facility** — an attribute table, not events, so it carries **no `dup` flags**.

## What it is

The merge spine: every facility that was active in the window, with its identity, geography, industry,
class, operating status, and two static "ever-*" profiles. Everything a panel joins onto a facility comes
from here.

## Cleaning decisions

- **Universe = "ever-active in window":** `PGM_SYS_ID` appearing in ≥1 event asset with an event dated in
  the analysis window. Ties the universe to observed regulatory activity. Consistent with the no-dedup
  policy, this counts **all rows** (any `dup` level): a facility whose only in-window record is a
  same-identifier duplicate row (e.g. an enforcement action re-using an `enf_identifier` at a later date)
  is still counted as active.
- **Attributes = current ICIS snapshot,** one row per facility (`distinct(PGM_SYS_ID)`). Class, industry,
  and operating status are time-invariant here (the source ships only the current snapshot).
- **Coordinates from FRS** via `REGISTRY_ID` (first lat/long per site). Facilities with no coordinate are
  **unplaceable** → no county and (later) no attainment.
- **County via point-in-county** (`st_within`) on the coordinate — exact, not a name match.
- **Two static profiles:** `emits_*` (ever regulated for a pollutant) and `prog_*` + `n_programs` (ever
  enrolled in a program), each matched from the ICIS code tables. `prog_nsps` pools major + non-major NSPS.
- **One row per facility is definitional** (a spine), so — unlike the event assets — there is no
  deduplication policy or `dup` flag here.

## Columns

Keys & geography: `PGM_SYS_ID`, `REGISTRY_ID`, `FACILITY_NAME`, `STREET_ADDRESS`, `CITY`, `COUNTY_NAME`,
`county_fips`, `STATE`, `ZIP_CODE`, `EPA_REGION`, `latitude`, `longitude`.
Industry & class: `NAICS_CODES`, `SIC_CODES`, `FACILITY_TYPE_CODE`, `facility_type`,
`AIR_POLLUTANT_CLASS_DESC`, `AIR_OPERATING_STATUS_DESC`.
Pollutant profile: `emits_voc/pm/co/nox/so2/hap`.
Program enrollment: `prog_sip/titlev/nsps/mact/neshap/fesop/nsr/psd`, `n_programs`.
Full definitions in the generated [data dictionary](../../docs/dictionary.qmd).

## Nuances

- **Snapshot attributes applied to all years.** Class / industry / operating status are current-snapshot;
  there is no facility entry/exit history here.
- **Unplaceable facilities cascade:** no FRS coordinate → no `county_fips` (and no geography-based joins).
- **`emits_*` / `prog_*` = 0 means "no record," not "confirmed not."** Missing profile rows coalesce to 0.
- **`prog_*` are ever-enrolled**, not time-varying (the program table has a start date but no end date).

Column definitions and current summaries are also generated into the docs site
([dictionary](../../docs/dictionary.qmd), [distributions](../../docs/distributions.qmd)).
