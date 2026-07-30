> **Status:** draft — [ ] verified against the current script (Claude, 2026-07-30)

# `06_coordinates.R` — builds dataset 4, `coordinates.csv.gz` (one row per facility)

## Purpose in the pipeline
> **TODO (Grace):** write the 1-2 sentence purpose blurb here — why this script exists and what depends on
> it. Starting material, from the script's own header comment:
> "DATASET 4: coordinates. One row per facility. FRS lat/lon, the derived county FIPS (point-in-polygon), and
> coordinate-vs-ICIS-county error diagnostics. Over the FULL 279,665 universe."

## Inputs & outputs
- **Input:** `data/processed/facilities.csv.gz` (`PGM_SYS_ID`, `REGISTRY_ID`, `STATE`, `COUNTY_NAME` — ICIS
  current snapshot) + `data/raw/frs/FRS_FACILITIES.csv` (FRS, current-snapshot, one row per `REGISTRY_ID`,
  385 MB raw) + `data/raw/us_counties/us_counties.shp` (Census cartographic county boundary file, static
  reference, 56 `STATEFP` values — all 50 states + DC + 5 territories, not CONUS-restricted).
- **Output:** `data/datasets/coordinates.csv.gz` — one row per `PGM_SYS_ID` (facility), full 279,665-facility
  universe. Joins on `PGM_SYS_ID` to every facility-year dataset in this layer.

Example — 5 rows from `data/datasets/coordinates.csv.gz` (sampled 2026-07-30, filtered to rows with both
`ICIS_COUNTY_FIPS` and `COORD_COUNTY_DIST_KM` set, to show the checkable case):

| PGM_SYS_ID | STATE | COUNTY_NAME | ICIS_COUNTY_FIPS | LATITUDE | LONGITUDE | HAS_COORDINATE | COUNTY_FIPS | COORD_COUNTY_DIST_KM | COORD_GROSS_ERROR |
|---|---|---|---|---|---|---|---|---|---|
| 01000000E000000003 | MA | Bristol | 25005 | 41.751308 | -71.114646 | 1 | 25005 | 0 | 0 |
| 01000000E000000004 | MA | Middlesex | 25017 | 42.42239 | -71.23863 | 1 | 25017 | 0 | 0 |
| 01000000E000000005 | RI | Providence | 44007 | 41.92971 | -71.52835 | 1 | 44007 | 0 | 0 |
| 01000000E000000006 | ME | Penobscot | 23019 | 44.7707 | -68.7948 | 1 | 23019 | 0 | 0 |
| 01000000E000000015 | MA | Norfolk | 25021 | 42.172955 | -71.2016 | 1 | 25021 | 0 | 0 |

(Most rows in the file have `COORD_COUNTY_DIST_KM == NA` because it's only computed for the
checkable-and-mismatched subset — see gotchas. First 3 raw rows sampled without filtering show exactly this:
`ICIS_COUNTY_FIPS=NA`, `COORD_COUNTY_DIST_KM=NA` for three CT facilities whose `COUNTY_NAME` didn't resolve.)

Full column list (11): `PGM_SYS_ID`, `REGISTRY_ID`, `STATE`, `COUNTY_NAME`, `ICIS_COUNTY_FIPS`, `LATITUDE`,
`LONGITUDE`, `HAS_COORDINATE`, `COUNTY_FIPS`, `COORD_COUNTY_DIST_KM`, `COORD_GROSS_ERROR`.

## At a glance
| | |
|---|---|
| **Input** | `facilities.csv.gz` (279,665 rows) + `FRS_FACILITIES.csv` (385 MB raw) + `us_counties.shp` |
| **Output** | `data/datasets/coordinates.csv.gz` — 279,665 rows × 11 cols, 4.3 MB compressed |
| **Runtime** | not measured directly; likely 1-3 minutes — the raw FRS file is large (385 MB uncompressed) and the script does two spatial operations (`st_join` point-in-polygon for ~236K coordinates, plus geodesic distance in the helper) over the full facility universe |
| **Requires** | Only the cleaning layer (`data/processed/`) + raw FRS/shapefile — no dependency on any other `03_datasets/` script's output. Depends on the local helper `code/03_datasets/coord_county_flag.R` (sourced inline, own README in this batch). |
| **Dependencies** | `readr`, `dplyr`, `sf` |

## Walkthrough
1. **Read ICIS facility attributes** (`facilities.csv.gz`) — `PGM_SYS_ID`, `REGISTRY_ID`, `STATE`,
   `COUNTY_NAME`; asserts `PGM_SYS_ID` uniqueness.
2. **Read FRS coordinates** (`FRS_FACILITIES.csv`) — dedups to one row per `REGISTRY_ID` (first-row-wins,
   see gotcha), parses lat/lon to numeric, left-joins onto the facility attributes via `REGISTRY_ID`. A
   facility with no `REGISTRY_ID` or no FRS match gets `NA` lat/lon.
3. **Point-in-polygon county** — loads the county shapefile, converts facilities with non-missing lat/lon to
   an `sf` point layer (CRS 4326), transforms to the shapefile's CRS, and does `st_join(..., join =
   st_within)` to get `county_fips` — the county the *coordinate itself* falls in.
4. **Coordinate-quality diagnostics** — sources `coord_county_flag.R` and calls `flag_coord_county(fac, co)`,
   which independently resolves `ICIS_COUNTY_FIPS` from `(STATE, COUNTY_NAME)` text and computes
   `COORD_COUNTY_DIST_KM`/`COORD_GROSS_ERROR` by comparing the coordinate-derived county against the
   ICIS-claimed one. See `coord_county_flag_README.md` for that helper's own logic.
5. **Assemble final columns**, `arrange(PGM_SYS_ID)`.
6. **Invariants** (`stopifnot`) — facility grain unique; row count equals the facility universe;
   `HAS_COORDINATE` agrees with lat/lon non-missingness; `COORD_GROSS_ERROR` is `NA` exactly where
   `COORD_COUNTY_DIST_KM` is `NA`, and matches the `>5km` rule elsewhere; `county_fips` never set without a
   coordinate.
7. **Write + summary** — `write_dataset()` uppercases; console prints coordinate coverage, `ICIS_COUNTY_FIPS`
   vs `COUNTY_FIPS` agreement rate, and gross-error rate.

## Notes & gotchas
- **C1** (coordinate source): "Coordinate source = FRS via `REGISTRY_ID`** (deduped to one row/`REGISTRY_ID`).
  No FRS match → `HAS_COORDINATE == 0`, `NA` lat/lon... 84.5% of facilities get a coordinate; the ~15.5% gap
  is facilities with no `REGISTRY_ID` or no FRS row." ⚠ Flagged in-file (`FLAGGED ISSUES` item 1):
  "`distinct(REGISTRY_ID, .keep_all = TRUE)` is a first-row-wins dedup on duplicate `REGISTRY_ID`, with no
  preference for a row that actually carries a coordinate... A duplicate `REGISTRY_ID` whose first row lacks
  lat/lon stays coordinate-less even if a later duplicate row has one."

- **C2** (`COUNTY_FIPS`, point-in-polygon): "`COUNTY_FIPS` = point-in-polygon of the coordinate into the
  county shapefile... The shapefile is **NOT CONUS-only** (full Census county file, 56 `STATEFP` values: all
  50 states + DC + 5 territories...) and this join consults no state crosswalk, so it was never actually
  restricted to CONUS. Of AK/HI/PR/GU/MP/VI facilities with a valid FRS coordinate, **1,244 of 1,288 (96.6%)**
  get a real `COUNTY_FIPS`; the rest fail only because the point doesn't fall inside any polygon
  (offshore/imprecise coordinate), not a CONUS restriction."

- **C3** (error diagnostics) — quoted in full, including the geodesic-distance addendum:
  > "Error diagnostics via the shared `flag_coord_county` helper — `COORD_COUNTY_DIST_KM` (km from
  > coordinate to ICIS-claimed county; 0 = in-county, NA = uncheckable) and `COORD_GROSS_ERROR` (1 iff
  > checkable & >5 km)... '0 ≠ NA honored' — never asserts 0 for a facility whose county name couldn't be
  > resolved. '"Shared" is by convention, not by code' — `code/03_datasets/coord_county_flag.R` is a
  > standalone, byte-for-byte-duplicated copy of `archive/panel_building_legacy/code/03_panel_building/
  > coord_county_flag.R` (its own docstring flags this); a fix to one must be applied to both by hand.
  > **Addendum (2026-07-28) — `COORD_COUNTY_DIST_KM` switched from EPSG:5070 to a direct geodesic
  > distance:** the 2026-07-27 fix making AK/HI/PR/VI/GU/MP checkable didn't update the distance step, which
  > still reprojected into EPSG:5070 (NAD83 / Conus Albers) — valid only for CONUS. Checked: CONUS mismatches
  > were negligibly affected (mean 0.11 km, max 13 km vs. geodesic, over 3,379 cases) but Alaska mismatches
  > diverged by up to ~21% (e.g. 817 km vs 993 km geodesic). `COORD_GROSS_ERROR` likely never flipped (every
  > non-CONUS mismatch found was well past the 5 km cutoff either way), but the distance number itself wasn't
  > trustworthy outside CONUS. Fixed in both copies of the helper, kept in sync per the note above."

- **C4** (universe): "Full 279,665 universe (as of 2026-07-27; the spine computed this block for the 133,753
  ever-active subset only)... Consistent with the layer's full-universe rule; joins on `PGM_SYS_ID` to every
  facility-year dataset."

- **C5** (`ICIS_COUNTY_FIPS`): "`ICIS_COUNTY_FIPS` = GEOID resolved from `(STATE, COUNTY_NAME)` text alone
  (added 2026-07-22; same `flag_coord_county` helper as C3)... Needs no coordinate — pure function of the
  ICIS name — so coverage is wider than `COUNTY_FIPS`: set for **261,646 (93.6%)** of all 279,665 facilities
  ...vs. `COUNTY_FIPS`'s 236,059 (84.4%). Where both are set (225,216 facilities), they agree **97.3%** of
  the time (219,167/225,216)."

- **Depends on `coord_county_flag.R`** — this script does not restate that helper's logic (see its own
  README for the full geodesic-distance / territory-resolution detail); it only calls
  `flag_coord_county(fac, co)`.

- **Verified by reading the script directly:** the `stopifnot()` invariants at build time (facility-grain
  uniqueness, `HAS_COORDINATE`/lat-lon consistency, the `COORD_GROSS_ERROR`/`NA` alignment with
  `COORD_COUNTY_DIST_KM`), the first-row-wins FRS dedup (`FLAGGED ISSUES` item 1), and that
  `coord_county_flag.R` is sourced inline rather than duplicated into this file. **Inferred/not
  independently re-run this pass:** the exact coverage percentages (84.5%, 96.6%, 93.6%, 97.3%) and the
  EPSG:5070-vs-geodesic divergence figures — quoted from the decisions doc's own verification session, not
  re-derived here.
