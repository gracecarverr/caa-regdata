# =========================================================================================================
# code/03_panel_building/coord_county_flag.R -- coordinate quality flag for the facility spine.
#   flag_coord_county(fac, counties_sf) cross-checks each facility's FRS coordinate against its ICIS-listed
#   county: it resolves (STATE, COUNTY_NAME) -> county GEOID using the SAME shapefile that assigned
#   county_fips (so the derived side is vintage-consistent), then measures how far the coordinate falls from
#   the ICIS-claimed county. See code/diagnostics/coord_county_check/ for the standalone analysis + rationale.
#
#   Returns one row per PGM_SYS_ID with:
#     coord_county_dist_km -- km from the coordinate to the ICIS-claimed county polygon (EPSG:5070).
#                             0 when the coordinate's county == the claimed county; positive for a mismatch;
#                             NA when uncheckable (no coordinate, or COUNTY_NAME unresolvable in this vintage).
#     coord_gross_error    -- 1 if checkable AND coord_county_dist_km > 5 (a gross error); 0 if checkable and
#                             <= 5 (match or near-border); NA if uncheckable. Honors 0 != NA: we never assert
#                             0 for a facility we could not actually check (e.g. Connecticut, "Undetermined").
#
#   `fac` must carry: PGM_SYS_ID, STATE, COUNTY_NAME, county_fips, latitude, longitude.
#   `counties_sf` is the county shapefile (GEOID, NAME, NAMELSAD, STATEFP, geometry) already loaded by the spine.
# =========================================================================================================
library(dplyr); library(sf)

GROSS_ERROR_KM <- 5   # a coordinate > this far from its ICIS-claimed county is a "gross error"

# 2-letter USPS -> 2-digit state FIPS (CONUS + DC; AK/HI/territories are absent from the CONUS shapefile).
.STATE_FIPS <- c(
  AL="01",AZ="04",AR="05",CA="06",CO="08",CT="09",DE="10",DC="11",FL="12",GA="13",ID="16",IL="17",IN="18",
  IA="19",KS="20",KY="21",LA="22",ME="23",MD="24",MA="25",MI="26",MN="27",MS="28",MO="29",MT="30",NE="31",
  NV="32",NH="33",NJ="34",NM="35",NY="36",NC="37",ND="38",OH="39",OK="40",OR="41",PA="42",RI="44",SC="45",
  SD="46",TN="47",TX="48",UT="49",VT="50",VA="51",WA="53",WV="54",WI="55",WY="56", AK="02",HI="15")

# collapse a county/city name to a comparable key (letters only); is_city is tracked separately so VA/MD/MO
# independent cities stay distinct from the like-named county.
.norm_name <- function(x) {
  x <- toupper(trimws(x))
  x <- gsub("\\(CITY\\)", "", x)
  x <- gsub("\\s+(COUNTY|PARISH|BOROUGH|CENSUS AREA|MUNICIPIO|MUNICIPALITY)$", "", x)
  x <- gsub("\\bSAINT\\b", "ST", x)
  gsub("[^A-Z]", "", x)
}

flag_coord_county <- function(fac, counties_sf) {
  # crosswalk from the shapefile: (STATEFP, normalized name, is_city) -> GEOID; drop keys hitting >1 GEOID.
  cd <- st_drop_geometry(counties_sf) |>
    mutate(GEOID = as.character(GEOID), STATEFP = as.character(STATEFP),
           is_city = grepl(" city$", NAMELSAD),
           key = paste(STATEFP, .norm_name(NAME), is_city, sep = "|"))
  xwalk <- cd |> group_by(key) |>
    summarise(resolved_geoid = if (n_distinct(GEOID) == 1L) GEOID[1] else NA_character_, .groups = "drop")

  f <- fac |>
    mutate(statefp = unname(.STATE_FIPS[STATE]),
           is_city = grepl("\\(city\\)", COUNTY_NAME, ignore.case = TRUE),
           key     = paste(statefp, .norm_name(COUNTY_NAME), is_city, sep = "|")) |>
    left_join(xwalk, by = "key")

  checkable <- !is.na(f$county_fips) & f$county_fips != "" & !is.na(f$resolved_geoid)
  is_match  <- checkable & f$resolved_geoid == f$county_fips

  # distance only for the mismatch subset (matches are 0 by construction); EPSG:5070 = CONUS Albers, metres.
  dist_km <- rep(NA_real_, nrow(f)); dist_km[is_match] <- 0
  mm <- which(checkable & !is_match)
  if (length(mm)) {
    co5070  <- st_transform(counties_sf, 5070)
    claimed <- co5070[match(f$resolved_geoid[mm], as.character(co5070$GEOID)), ]
    pts     <- st_transform(st_as_sf(f[mm, ], coords = c("longitude", "latitude"), crs = 4326), 5070)
    dist_km[mm] <- as.numeric(st_distance(pts, claimed, by_element = TRUE)) / 1000
  }

  tibble(PGM_SYS_ID = f$PGM_SYS_ID,
         coord_county_dist_km = dist_km,
         coord_gross_error = ifelse(is.na(dist_km), NA_integer_, as.integer(dist_km > GROSS_ERROR_KM)))
}
