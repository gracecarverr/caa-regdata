> **Status:** draft — [ ] verified against the current script (Claude, 2026-07-30)

# `coord_county_flag.R` — shared helper: `flag_coord_county()`, coordinate-vs-ICIS-county cross-check

## Purpose in the pipeline
> **TODO (Grace):** write the 1-2 sentence purpose blurb here — why this script exists and what depends on
> it. Starting material, from the script's own header comment:
> "coord_county_flag.R -- coordinate quality flag, used by the coordinates dataset. flag_coord_county(fac,
> counties_sf) cross-checks each facility's FRS coordinate against its ICIS-listed county: it resolves
> (STATE, COUNTY_NAME) -> county GEOID using the SAME shapefile that assigned county_fips (so the derived
> side is vintage-consistent), then measures how far the coordinate falls from the ICIS-claimed county."

## Inputs & outputs
This is a **shared helper function** (`flag_coord_county(fac, counties_sf)`), not a standalone pipeline
stage — it has no `data/datasets/` output file of its own. It is sourced and called by `06_coordinates.R`.

- **Input (function arguments):** `fac` — a data frame that must carry `PGM_SYS_ID`, `STATE`, `COUNTY_NAME`,
  `county_fips`, `latitude`, `longitude` (built by `06_coordinates.R` before calling this helper);
  `counties_sf` — the county shapefile (`GEOID`, `NAME`, `NAMELSAD`, `STATEFP`, geometry), already loaded by
  the caller.
- **Output:** the `ICIS_COUNTY_FIPS` / `COORD_COUNTY_DIST_KM` / `COORD_GROSS_ERROR` columns it computes
  (returned as a tibble keyed on `PGM_SYS_ID`), consumed by `06_coordinates.R`'s output — see that file's
  README for example rows, since every row of `coordinates.csv.gz` carries this helper's output columns.

## At a glance
| | |
|---|---|
| **Input** | function arguments only — `fac` (facility attrs + lat/lon + `county_fips`) + `counties_sf` (shapefile); no file I/O of its own |
| **Output** | not a file — the three derived columns (`icis_county_fips`, `coord_county_dist_km`, `coord_gross_error`), consumed inline by `06_coordinates.R` |
| **Runtime** | not measured separately from `06_coordinates.R` — the geodesic-distance computation for the mismatch subset (`st_distance`) is the most expensive step, but only runs over checkable-and-mismatched rows, a small fraction of 279,665 |
| **Requires** | Not runnable standalone — sourced by `06_coordinates.R`, which supplies both arguments. |
| **Dependencies** | `dplyr`, `sf` |

## Walkthrough
1. **Build the shapefile crosswalk** — normalizes each county's `NAME` (via `.norm_name()`) and tags
   `is_city` (Census's "independent city" convention), keys by `(STATEFP, normalized name, is_city)`. A key
   mapping to >1 `GEOID` within a state refuses to resolve (`NA`) rather than guessing.
2. **`.norm_name()`** — case/whitespace normalization, strips `(CITY)` markers and admin-unit-type suffixes
   (COUNTY/PARISH/BOROUGH/CENSUS AREA/MUNICIPIO/MUNICIPALITY), normalizes "Saint"→"St", transliterates
   accented Latin to ASCII (added 2026-07-27 for Puerto Rico municipio names and NM's Doña Ana county),
   letters-only.
3. **Resolve `icis_county_fips`** — joins each facility's `(STATE, COUNTY_NAME)` (via `.STATE_FIPS` lookup +
   `.norm_name()`) against the crosswalk. `NA` when unresolvable.
4. **Determine checkability and match** — `checkable` = has both a `county_fips` (from the coordinate) and a
   resolved `icis_county_fips`; `is_match` = checkable AND the two agree.
5. **Compute distance** — `0` by construction where matched; for the mismatch subset only, computes geodesic
   distance (`st_distance`) from the coordinate to the ICIS-claimed county's polygon, on unprojected WGS84
   coordinates via `sf`'s s2 backend — no CRS reprojection needed.
6. **Return** a tibble keyed on `PGM_SYS_ID` with `icis_county_fips`, `coord_county_dist_km`,
   `coord_gross_error` (`1` iff checkable & `> 5 km`, `NA` iff uncheckable).

## Notes & gotchas
- ⚠ **This file is a duplicated copy — the load-bearing warning for this specific file.** Quoted from
  `code/03_datasets/README.md`'s build-order table (C3 row context) and the script's own docstring/FLAGGED
  ISSUES section:
  > "This is the same county-resolution logic as `archive/panel_building_legacy/code/03_panel_building/
  > coord_county_flag.R` (the pre-rename panel-building layer's copy, now frozen), plus one added output
  > column (`icis_county_fips`); the two aren't literally byte-identical (comments differ, this copy has a
  > FLAGGED ISSUES section the archived one doesn't), but the functions/fixes are the same. **Since the
  > archived copy is frozen, only this one can drift going forward — there's no live sync risk anymore.**"

  The script's own in-file framing (`FLAGGED ISSUES` item 1, and the module docstring `REVIEW(design)` note)
  puts it more cautiously, worth reading as the earlier, still-true half of the story:
  > "REVIEW(design): this is a byte-for-byte duplicate (module docstring aside) of
  > `code/03_panel_building/coord_county_flag.R` plus one added output column (icis_county_fips). Any future
  > fix to the shared logic -- e.g. the 2026-07-27 PR/VI/GU/MP + diacritics fix below -- has to be applied to
  > both copies by hand; nothing enforces they stay in sync. (Both copies WERE updated together this time,
  > and again 2026-07-28 for the EPSG:5070 -> geodesic distance fix below.)"

  Read together: at the time each fix landed, both copies were updated by hand (no automated sync); as of
  the archival of `code/03_panel_building/` (now `archive/panel_building_legacy/...`), that copy is frozen,
  so the byte-for-byte-duplicate risk this docstring warns about is now one-directional and closed going
  forward — only this copy can still drift, and there's nothing left to drift *from* it into.

- **C3 addendum (geodesic distance fix)**, quoted again here because it's this file's own logic, not just
  `06_coordinates.R`'s: "`COORD_COUNTY_DIST_KM` switched from EPSG:5070 to a direct geodesic distance: the
  2026-07-27 fix making AK/HI/PR/VI/GU/MP checkable didn't update the distance step, which still reprojected
  into EPSG:5070 (NAD83 / Conus Albers) — valid only for CONUS. Checked: CONUS mismatches were negligibly
  affected (mean 0.11 km, max 13 km vs. geodesic, over 3,379 cases) but Alaska mismatches diverged by up to
  ~21% (e.g. 817 km vs 993 km geodesic). `COORD_GROSS_ERROR` likely never flipped (every non-CONUS mismatch
  found was well past the 5 km cutoff either way), but the distance number itself wasn't trustworthy outside
  CONUS." The script's own in-file comment (lines 90-95) gives the identical explanation directly next to the
  `st_distance()` call.

- **Territory/diacritic fix (2026-07-27)**, from the script's own comment (lines 38-42, 53-61): the
  `.STATE_FIPS` map previously had no entries for PR/VI/GU/MP, silently making every such facility
  "uncheckable" for `ICIS_COUNTY_FIPS`/`COORD_GROSS_ERROR` despite their counties being present in the
  shapefile all along (`COUNTY_FIPS` itself, a plain spatial join in `06_coordinates.R`, was never affected).
  Fixed by adding PR=72/VI=78/GU=66/MP=69 plus ASCII transliteration for accented municipio names. Verified
  safe: "re-running the full 3,235-county crosswalk before/after gives the same 3,235 distinct keys and zero
  new >1-GEOID collisions either way."

- **0 ≠ NA is honored** throughout — a facility that couldn't be checked (no coordinate, or `COUNTY_NAME`
  unresolvable) gets `NA`, never a false `0` for "confirmed matching county."

- **Verified by reading the script directly:** the `.norm_name()` normalization steps, the `.STATE_FIPS`
  territory codes, the checkable/match/distance logic (lines 69-108), and the FLAGGED ISSUES section's own
  framing of the duplication risk. **Inferred/not independently re-run this pass:** the "same 3,235 distinct
  keys" crosswalk-stability check and the CONUS/Alaska distance-divergence figures — quoted from the
  decisions doc / script comments' own prior verification, not re-derived here.
