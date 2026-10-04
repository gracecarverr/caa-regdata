# =========================================================================================================
# code/03_datasets/06_coordinates.R -- DATASET 4: coordinates. One row per facility. FRS lat/lon, the derived
# county FIPS (point-in-polygon), and coordinate-vs-ICIS-county error diagnostics. Over the FULL 279,665
#   universe.
#
#   in : data/processed/facilities.csv.gz  +  data/raw/frs/FRS_FACILITIES.csv  +  data/raw/us_counties/us_counties.shp
#   out: data/datasets/coordinates.csv.gz
#
#   COORDINATE SOURCE -- FRS (Facility Registry Service), joined via REGISTRY_ID (deduped to one row/REGISTRY_ID).
#     A facility with no REGISTRY_ID or no FRS match has HAS_COORDINATE == 0 and NA lat/lon/county.
#   COUNTY_FIPS -- point-in-polygon of the coordinate into the county shapefile (EPSG:4326 -> shapefile CRS).
#     The shapefile itself is NOT CONUS-only -- it's the full Census county file (56 STATEFP values: all 50
#     states + DC + 5 territories) -- and this point-in-polygon join doesn't consult any state crosswalk at
#     all, so it was never actually restricted to CONUS. Of facilities with STATE in {AK, HI, PR, GU, MP, VI}
#     and a valid FRS coordinate, 1,244 of 1,288 (96.6%) get a real COUNTY_FIPS; the remainder fail only
#     because their specific point doesn't fall inside any polygon (e.g. an offshore or imprecise
#     coordinate), not because of a CONUS restriction.
#   ICIS_COUNTY_FIPS below (coord_county_flag.R's name-based resolution) previously WAS restricted, for a
#     different reason: its .STATE_FIPS lookup had no entry for PR/GU/MP/VI, so those ~800 facilities always
#     resolved to NA regardless of the shapefile. Fixed 2026-07-27 (see coord_county_flag.R) by adding the 4
#     territory FIPS codes plus accent-transliteration for Puerto Rico's diacritic municipio names -- raises
#     resolution for those 800 facilities from 0% to 94.9%; the remaining 5.1% is literally
#     COUNTY_NAME == "Undetermined", correctly unresolvable. See briefs/datasets/dataset_construction_decisions.md.
#   ICIS_COUNTY_FIPS -- GEOID resolved from ICIS (STATE, COUNTY_NAME) text alone (flag_coord_county.R, local
#     to this datasets layer), independent of any coordinate. NA when the name doesn't resolve to exactly one
#     GEOID in this shapefile vintage. Cross-check it against COUNTY_FIPS to flag lat/long-vs-label disagreements.
#   ERROR DIAGNOSTICS (flag_coord_county.R) -- COORD_COUNTY_DIST_KM = km from the
#     coordinate to the ICIS-CLAIMED county polygon (0 if the coordinate lands in the claimed county, positive
#     for a mismatch, NA if uncheckable); COORD_GROSS_ERROR = 1 iff checkable & dist > 5 km, 0 iff checkable &
#     <= 5, NA if uncheckable. 0 != NA is honored -- never asserts 0 for a facility we could not check.
#
#   GRAIN -- one row per PGM_SYS_ID (facility). Joins on PGM_SYS_ID to every facility-year dataset.
# =========================================================================================================
library(readr); library(dplyr); library(sf)
source(here::here("code/03_datasets/00_parameters.R"))
RAW <- here::here("data/raw")

attrs <- read_csv(file.path(CLEAN, "facilities.csv.gz"),
                  col_select = c(PGM_SYS_ID, REGISTRY_ID, STATE, COUNTY_NAME),
                  col_types = cols(.default = col_character()), show_col_types = FALSE)
stopifnot("facilities: PGM_SYS_ID not unique" = !anyDuplicated(attrs$PGM_SYS_ID))

# FRS coordinates via REGISTRY_ID (one row per REGISTRY_ID, same read as the spine).
frs <- read_csv(file.path(RAW, "frs", "FRS_FACILITIES.csv"),
                col_select = c(REGISTRY_ID, LATITUDE_MEASURE, LONGITUDE_MEASURE),
                col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  mutate(REGISTRY_ID = as.character(REGISTRY_ID)) |>
  distinct(REGISTRY_ID, .keep_all = TRUE) |>            # first-row-wins on duplicate REGISTRY_ID, same
                                                          # caveat as 03_panel_building/00_spine.R: no
                                                          # preference for a row that actually has a coordinate
  transmute(REGISTRY_ID, latitude = suppressWarnings(as.numeric(LATITUDE_MEASURE)),
            longitude = suppressWarnings(as.numeric(LONGITUDE_MEASURE)))
fac <- attrs |> left_join(frs, by = "REGISTRY_ID")

# county FIPS via point-in-polygon.
co <- st_read(file.path(RAW, "us_counties", "us_counties.shp"), quiet = TRUE); co$GEOID <- as.character(co$GEOID)
pts <- fac |> filter(!is.na(latitude), !is.na(longitude)) |>
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326) |> st_transform(st_crs(co))
fac_fips <- st_join(pts, co["GEOID"], join = st_within) |> st_drop_geometry() |>
  transmute(PGM_SYS_ID, county_fips = as.character(GEOID)) |> distinct(PGM_SYS_ID, .keep_all = TRUE)
  # same boundary-point tie-break caveat as 03_panel_building/00_spine.R's identical pattern
fac <- fac |> left_join(fac_fips, by = "PGM_SYS_ID")

# coordinate-quality diagnostics (standalone copy, local to this datasets layer -- see coord_county_flag.R).
source(here::here("code/03_datasets/coord_county_flag.R"))
coords <- fac |> left_join(flag_coord_county(fac, co), by = "PGM_SYS_ID") |>
  transmute(PGM_SYS_ID, REGISTRY_ID, STATE, county_name = COUNTY_NAME, icis_county_fips,
            latitude, longitude, has_coordinate = as.integer(!is.na(latitude) & !is.na(longitude)),
            county_fips, coord_county_dist_km, coord_gross_error) |>
  arrange(PGM_SYS_ID)

# ---- invariants -----------------------------------------------------------------------------------------
stopifnot(
  "facility grain broken: PGM_SYS_ID not unique"  = !anyDuplicated(coords$PGM_SYS_ID),
  "row count != facility universe"                = nrow(coords) == nrow(attrs),
  "HAS_COORDINATE disagrees with lat/lon"         =
    all(coords$has_coordinate == as.integer(!is.na(coords$latitude) & !is.na(coords$longitude))),
  "COORD_GROSS_ERROR set where dist is NA"        =
    all(is.na(coords$coord_gross_error) == is.na(coords$coord_county_dist_km)),
  "COORD_GROSS_ERROR not the >5km flag"           =
    all(coords$coord_gross_error[!is.na(coords$coord_county_dist_km)] ==
        as.integer(coords$coord_county_dist_km[!is.na(coords$coord_county_dist_km)] > 5)),
  "county_fips present without a coordinate"      = all(is.na(coords$county_fips) | coords$has_coordinate == 1))

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# 1. (frs, ~line 48) distinct(REGISTRY_ID, .keep_all = TRUE) is a first-row-wins dedup on duplicate
#    REGISTRY_ID, with no preference for a row that actually carries a coordinate -- same caveat as
#    03_panel_building/00_spine.R's identical pattern. A duplicate REGISTRY_ID whose first row lacks lat/lon
#    stays coordinate-less even if a later duplicate row has one.
# =========================================================================================================

write_dataset(coords, "coordinates")             # uppercases all columns on write (see 00_parameters.R)
n <- nrow(coords)
cat(sprintf("coordinates: %s facilities | %d cols\n", format(n, big.mark = ","), ncol(coords)))
cat(sprintf("  has coordinate : %s (%.1f%%)\n", format(sum(coords$has_coordinate), big.mark = ","),
            100 * mean(coords$has_coordinate)))
both <- !is.na(coords$icis_county_fips) & !is.na(coords$county_fips)
cat(sprintf("  icis_county_fips set: %s (%.1f%%) | agrees with county_fips where both set: %s/%s (%.1f%%)\n",
            format(sum(!is.na(coords$icis_county_fips)), big.mark = ","),
            100 * mean(!is.na(coords$icis_county_fips)),
            format(sum(coords$icis_county_fips[both] == coords$county_fips[both]), big.mark = ","),
            format(sum(both), big.mark = ","),
            100 * mean(coords$icis_county_fips[both] == coords$county_fips[both])))
cat(sprintf("  county_fips set: %s | checkable vs ICIS county: %s | gross errors (>5km): %s (%.1f%% of checkable)\n",
            format(sum(!is.na(coords$county_fips)), big.mark = ","),
            format(sum(!is.na(coords$coord_county_dist_km)), big.mark = ","),
            format(sum(coords$coord_gross_error, na.rm = TRUE), big.mark = ","),
            100 * mean(coords$coord_gross_error[!is.na(coords$coord_gross_error)])))
