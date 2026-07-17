# coord_county_check — do facility coordinates land in the ICIS-listed county?

## Question
How accurate are the facility lat/long coordinates? We check them at **county resolution** by comparing two
*independent* county signals carried in the spine:

- **`COUNTY_NAME`** — the county text listed in the ICIS `facilities` attributes (independent of coordinates).
- **`county_fips`** — the county the FRS lat/long actually falls in, assigned by point-in-polygon in
  [`../../03_panel_building/00_spine.R`](../../03_panel_building/00_spine.R).

Agreement ⇒ the coordinate is *county-consistent*. Disagreement is a **screening flag**, not proof the
coordinate is wrong: the ICIS label, the county-boundary vintage, or name-resolution could be the culprit.
The check bounds **county-level** error only — a point can be in the right county yet still far from the site.
Neither field is ground truth; this is a consistency cross-check between two imperfect sources.

## Method (`coord_county_check.R`)
1. Resolve ICIS `(STATE, COUNTY_NAME)` → GEOID using the **same** county shapefile
   (`data/raw/us_counties/us_counties.shp`) that produced `county_fips`, so the derived side is
   vintage-consistent. Compare **GEOID to GEOID**.
2. Names are normalized (uppercase, strip type suffixes, fold `SAINT→ST`, keep letters only) and matched
   **within state**. Independent cities (VA/MD/MO) are disambiguated with an `is_city` flag so e.g.
   `Richmond (city)` (51760) ≠ `Richmond County` (51159).
3. Every facility is bucketed: `match` / `mismatch` / `name_unresolved` (ICIS name has no GEOID in this
   shapefile vintage) / `ambiguous_name` / `no_coordinate`. Only `match`+`mismatch` enter the match-rate
   denominator.
4. Mismatches are graded by distance from the coordinate to the ICIS-claimed county polygon (CONUS Albers,
   EPSG:5070) — separating near-border cases from gross errors.

Outputs → `output/coord_county_check/`: `facility_flags.csv` (per-facility status, distances, coordinate
pathology flags), `summary_by_state.csv` (match rate by state), `worst_mismatches.csv`.

## Finding (run 2026-07-16, spine = 136,505 facilities)
- **County match rate 97.1%** over 116,706 checkable facilities (113,282 match / 3,424 mismatch).
- **Distance grading is essential**: ~50% of the 3,424 mismatches are within 5 km (near-border / precision,
  likely benign), while **412 are >100 km** — genuine gross errors (e.g. Denver-CO coordinates landing in
  West Virginia, ~1,970 km off). Threshold `dist_claimed_km` in `facility_flags.csv` to grade severity.
- **WI is a systematic outlier** (match rate 0.70): 264 of 289 WI mismatches are >25 km (184 >100 km) — not
  border noise. Worth a dedicated investigation (coordinate source or county labeling for WI). **Flagged, not
  resolved.**
- **NY's low rate (0.85) is the opposite** — 1,020 of 1,033 mismatches are <25 km (dense counties / NYC
  boroughs), so NY coordinates are effectively fine; the binary rate understates accuracy.
- **Coverage/known artifacts**: 15,730 facilities (11.5%) have no coordinate and can't be checked; 4,069 are
  `name_unresolved` — dominated by **Connecticut** (1,129), whose ICIS legacy county names (`Hartford`, …)
  do not exist in the shapefile's 2022 planning-region vintage (`Capitol`, …), plus `Undetermined` labels.
  These are correctly kept out of the mismatch count.
