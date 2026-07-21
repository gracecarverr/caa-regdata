# =========================================================================================================
# code/04_datasets/06_coordinates.R -- DATASET 4: coordinates. One row per facility. FRS lat/lon, the derived
#   county FIPS (point-in-polygon), and coordinate-vs-ICIS-county error diagnostics. Over the FULL 279,211
#   universe (the panel spine computed the same block for the ever-active subset only).
#
#   in : data/processed/facilities.csv.gz  +  data/raw/frs/FRS_FACILITIES.csv  +  data/raw/us_counties/us_counties.shp
#   out: data/datasets/coordinates.csv.gz
#
#   COORDINATE SOURCE -- FRS (Facility Registry Service), joined via REGISTRY_ID (deduped to one row/REGISTRY_ID).
#     A facility with no REGISTRY_ID or no FRS match has HAS_COORDINATE == 0 and NA lat/lon/county.
#   COUNTY_FIPS -- point-in-polygon of the coordinate into the county shapefile (EPSG:4326 -> shapefile CRS).
#     The shapefile is CONUS + DC (+AK/HI in the state crosswalk only); non-CONUS facilities resolve to NA.
#   ERROR DIAGNOSTICS (flag_coord_county, shared with the spine) -- COORD_COUNTY_DIST_KM = km from the
#     coordinate to the ICIS-CLAIMED county polygon (0 if the coordinate lands in the claimed county, positive
#     for a mismatch, NA if uncheckable); COORD_GROSS_ERROR = 1 iff checkable & dist > 5 km, 0 iff checkable &
#     <= 5, NA if uncheckable. 0 != NA is honored -- never asserts 0 for a facility we could not check.
#
#   GRAIN -- one row per PGM_SYS_ID (facility). Joins on PGM_SYS_ID to every facility-year dataset.
# =========================================================================================================
library(readr); library(dplyr); library(sf)
source(here::here("code/04_datasets/00_parameters.R"))
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
  distinct(REGISTRY_ID, .keep_all = TRUE) |>
  transmute(REGISTRY_ID, latitude = suppressWarnings(as.numeric(LATITUDE_MEASURE)),
            longitude = suppressWarnings(as.numeric(LONGITUDE_MEASURE)))
fac <- attrs |> left_join(frs, by = "REGISTRY_ID")

# county FIPS via point-in-polygon.
co <- st_read(file.path(RAW, "us_counties", "us_counties.shp"), quiet = TRUE); co$GEOID <- as.character(co$GEOID)
pts <- fac |> filter(!is.na(latitude), !is.na(longitude)) |>
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326) |> st_transform(st_crs(co))
fac_fips <- st_join(pts, co["GEOID"], join = st_within) |> st_drop_geometry() |>
  transmute(PGM_SYS_ID, county_fips = as.character(GEOID)) |> distinct(PGM_SYS_ID, .keep_all = TRUE)
fac <- fac |> left_join(fac_fips, by = "PGM_SYS_ID")

# coordinate-quality diagnostics (shared helper, same as the spine).
source(here::here("code/03_panel_building/coord_county_flag.R"))
coords <- fac |> left_join(flag_coord_county(fac, co), by = "PGM_SYS_ID") |>
  transmute(PGM_SYS_ID, REGISTRY_ID, STATE, county_name = COUNTY_NAME,
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

write_dataset(coords, "coordinates")             # uppercases all columns on write (see 00_parameters.R)
n <- nrow(coords)
cat(sprintf("coordinates: %s facilities | %d cols\n", format(n, big.mark = ","), ncol(coords)))
cat(sprintf("  has coordinate : %s (%.1f%%)\n", format(sum(coords$has_coordinate), big.mark = ","),
            100 * mean(coords$has_coordinate)))
cat(sprintf("  county_fips set: %s | checkable vs ICIS county: %s | gross errors (>5km): %s (%.1f%% of checkable)\n",
            format(sum(!is.na(coords$county_fips)), big.mark = ","),
            format(sum(!is.na(coords$coord_county_dist_km)), big.mark = ","),
            format(sum(coords$coord_gross_error, na.rm = TRUE), big.mark = ","),
            100 * mean(coords$coord_gross_error[!is.na(coords$coord_gross_error)])))
