# =========================================================================================================
# code/03_panel_building/coord_county_flag.R -- coordinate quality flag for the facility spine.
#   flag_coord_county(fac, counties_sf) cross-checks each facility's FRS coordinate against its ICIS-listed
#   county: it resolves (STATE, COUNTY_NAME) -> county GEOID using the SAME shapefile that assigned
#   county_fips (so the derived side is vintage-consistent), then measures how far the coordinate falls from
#   the ICIS-claimed county. See code/diagnostics/coord_county_check/ for the standalone analysis + rationale.
#
#   Returns one row per PGM_SYS_ID with:
#     coord_county_dist_km -- geodesic km from the coordinate to the ICIS-claimed county polygon (computed
#                             directly on unprojected WGS84 coordinates via sf's s2 backend -- accurate
#                             globally, not just CONUS; see the distance-computation comment below for why).
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

# 2-letter USPS -> 2-digit state FIPS. The shapefile itself is NOT CONUS-only (verified: 56 STATEFP values --
# all 50 states + DC + AK + HI + 5 territories), so this map covers every jurisdiction that actually appears
# in ICIS's STATE field, including the territories: PR=72, VI=78, GU=66, MP=69 (added 2026-07-27; previously
# missing, which silently made every PR/VI/GU/MP facility "uncheckable" here despite their counties being
# present in the shapefile all along -- see briefs/panel/panel_construction_decisions.md).
.STATE_FIPS <- c(
  AL="01",AZ="04",AR="05",CA="06",CO="08",CT="09",DE="10",DC="11",FL="12",GA="13",ID="16",IL="17",IN="18",
  IA="19",KS="20",KY="21",LA="22",ME="23",MD="24",MA="25",MI="26",MN="27",MS="28",MO="29",MT="30",NE="31",
  NV="32",NH="33",NJ="34",NM="35",NY="36",NC="37",ND="38",OH="39",OK="40",OR="41",PA="42",RI="44",SC="45",
  SD="46",TN="47",TX="48",UT="49",VT="50",VA="51",WA="53",WV="54",WI="55",WY="56", AK="02",HI="15",
  PR="72",VI="78",GU="66",MP="69")

# collapse a county/city name to a comparable key (letters only); is_city is tracked separately so VA/MD/MO
# independent cities stay distinct from the like-named county.
.norm_name <- function(x) {
  x <- iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT")  # accented Latin -> plain ASCII (e.g. "Bayamon" from
                                                            # "Bayamón"): added 2026-07-27 alongside the
                                                            # PR/VI/GU/MP FIPS codes above -- without this, Census's
                                                            # accented Puerto Rico municipio names (and NM's own
                                                            # Doña Ana county) would never match ICIS's
                                                            # unaccented spellings even with statefp resolved.
                                                            # Verified safe: re-running the full 3,235-county
                                                            # crosswalk before/after gives the same 3,235 distinct
                                                            # keys and zero new >1-GEOID collisions either way.
  x <- toupper(trimws(x))                              # case/whitespace-insensitive comparison
  x <- gsub("\\(CITY\\)", "", x)                        # strip an explicit "(CITY)" marker before suffix-stripping
  x <- gsub("\\s+(COUNTY|PARISH|BOROUGH|CENSUS AREA|MUNICIPIO|MUNICIPALITY)$", "", x)
    # drop the trailing administrative-unit-type word so "Cook County" and "Cook" key the same way
  x <- gsub("\\bSAINT\\b", "ST", x)                     # normalize "Saint" vs "St" spelling variants
  gsub("[^A-Z]", "", x)                                 # finally strip everything but letters (spaces, punctuation)
}

flag_coord_county <- function(fac, counties_sf) {
  # crosswalk from the shapefile: (STATEFP, normalized name, is_city) -> GEOID; drop keys hitting >1 GEOID.
  cd <- st_drop_geometry(counties_sf) |>                # work with the attribute table only (no geometry needed yet)
    mutate(GEOID = as.character(GEOID), STATEFP = as.character(STATEFP),
           is_city = grepl(" city$", NAMELSAD),         # Census's "independent city" naming convention (e.g. "Norfolk city")
           key = paste(STATEFP, .norm_name(NAME), is_city, sep = "|"))
  xwalk <- cd |> group_by(key) |>
    summarise(resolved_geoid = if (n_distinct(GEOID) == 1L) GEOID[1] else NA_character_, .groups = "drop")
    # if a normalized key somehow maps to MORE than one distinct GEOID (a genuine name collision within a
    # state), refuse to resolve it (NA) rather than guessing -- conservative and correct

  f <- fac |>
    mutate(statefp = unname(.STATE_FIPS[STATE]),        # NA only for a STATE value truly absent from the map above
           is_city = grepl("\\(city\\)", COUNTY_NAME, ignore.case = TRUE),   # ICIS's own "(city)" convention
           key     = paste(statefp, .norm_name(COUNTY_NAME), is_city, sep = "|")) |>
    left_join(xwalk, by = "key")                        # resolve ICIS's claimed county name to a GEOID

  checkable <- !is.na(f$county_fips) & f$county_fips != "" & !is.na(f$resolved_geoid)
    # only facilities with BOTH a spatially-assigned county_fips (from the point-in-polygon join upstream)
    # AND a successfully name-resolved ICIS county can be compared at all
  is_match  <- checkable & f$resolved_geoid == f$county_fips   # exact GEOID agreement = correct county, no distance needed

  # distance only for the mismatch subset (matches are 0 by construction). Computed directly on unprojected
  # WGS84 coordinates -- sf's s2 backend (active in this environment) gives an accurate geodesic distance
  # everywhere, so no CRS reprojection is needed at all. Previously reprojected into EPSG:5070 (NAD83 / Conus
  # Albers): fine for CONUS (checked 2026-07-28 -- negligible difference vs geodesic, mean 0.11 km / max 13 km
  # over 3,379 CONUS mismatches) but measurably wrong once AK/HI/territories became checkable (2026-07-27 fix
  # above) -- e.g. one Alaska mismatch read 817 km under EPSG:5070 vs 993 km geodesic, a 21% error. The
  # gross_error 0/1 call itself likely never flipped (every non-CONUS mismatch found was tens-to-hundreds of
  # km past the 5 km cutoff either way), but coord_county_dist_km was not a trustworthy distance outside CONUS.
  dist_km <- rep(NA_real_, nrow(f)); dist_km[is_match] <- 0    # matches get an exact 0 without any distance computation
  mm <- which(checkable & !is_match)                    # only compute the (comparatively expensive) distance for mismatches
  if (length(mm)) {
    co4326  <- st_transform(counties_sf, 4326)          # match the points' CRS -- s2 geodesic needs no further projection
    claimed <- co4326[match(f$resolved_geoid[mm], as.character(co4326$GEOID)), ]  # the ICIS-claimed polygon per mismatch row
    pts     <- st_as_sf(f[mm, ], coords = c("longitude", "latitude"), crs = 4326)  # the actual coordinate
    dist_km[mm] <- as.numeric(st_distance(pts, claimed, by_element = TRUE)) / 1000  # metres -> km, element-wise (not a full matrix)
  }

  tibble(PGM_SYS_ID = f$PGM_SYS_ID,
         coord_county_dist_km = dist_km,
         coord_gross_error = ifelse(is.na(dist_km), NA_integer_, as.integer(dist_km > GROSS_ERROR_KM)))
           # NA propagates cleanly through ifelse() here -- "uncheckable" stays uncheckable, never coerced to 0
}
