# =========================================================================================================
# code/diagnostics/coord_county_check/coord_county_check.R
#   Cross-check facility coordinate accuracy at COUNTY resolution by comparing two INDEPENDENT county
#   signals in the spine:
#     (a) COUNTY_NAME  -- ICIS-listed county text (from data/processed/facilities; independent of coords)
#     (b) county_fips  -- the county the FRS lat/long falls in, via point-in-polygon (00_spine.R)
#   Agreement => the coordinate is county-consistent. Disagreement => a screening flag (the coordinate, the
#   ICIS label, the crosswalk vintage, or name-resolution is off). This is a consistency check between two
#   imperfect sources, NOT validation against ground truth, and it speaks only to COUNTY-level accuracy --
#   a point can be county-consistent yet still far from the true site.
#
#   Method: resolve ICIS (STATE, COUNTY_NAME) -> GEOID using the SAME county shapefile that produced
#   county_fips (so the derived side is vintage-consistent), then compare GEOID to GEOID. Independent cities
#   (VA/MD/MO) are disambiguated with an is_city flag; names that cannot be resolved (e.g. Connecticut's
#   legacy county names vs the shapefile's 2022 planning regions, or "Undetermined") are bucketed separately
#   and never counted as coordinate mismatches. Mismatches are graded by distance from the coordinate to the
#   ICIS-claimed county polygon.
#
#   in : data/panels/spine.csv.gz          (one row per facility: STATE, COUNTY_NAME, county_fips, lat/long)
#        data/raw/us_counties/us_counties.shp  (GEOID, NAME, NAMELSAD, STATEFP -- the PIP crosswalk)
#   out: output/coord_county_check/facility_flags.csv     (per-facility status + distances + coord flags)
#        output/coord_county_check/summary_by_state.csv   (match rate by state)
#        output/coord_county_check/worst_mismatches.csv   (largest coordinate/label disagreements)
#   Hand-run diagnostic (not part of RUN_ALL.R). Deterministic; no seed needed.
# =========================================================================================================
suppressPackageStartupMessages({library(data.table); library(sf)})

SPINE <- here::here("data/panels/spine.csv.gz")
SHP   <- here::here("data/raw/us_counties/us_counties.shp")
OUT   <- here::here("output/coord_county_check")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

# 2-letter USPS -> 2-digit state FIPS (CONUS + DC; AK/HI/territories absent from the CONUS shapefile).
STATE_FIPS <- c(
  AL="01",AZ="04",AR="05",CA="06",CO="08",CT="09",DE="10",DC="11",FL="12",GA="13",ID="16",IL="17",IN="18",
  IA="19",KS="20",KY="21",LA="22",ME="23",MD="24",MA="25",MI="26",MN="27",MS="28",MO="29",MT="30",NE="31",
  NV="32",NH="33",NJ="34",NM="35",NY="36",NC="37",ND="38",OH="39",OK="40",OR="41",PA="42",RI="44",SC="45",
  SD="46",TN="47",TX="48",UT="49",VT="50",VA="51",WA="53",WV="54",WI="55",WY="56", AK="02",HI="15")

# ---- name normalization --------------------------------------------------------------------------------
# Collapse a county/city name to a comparable key: uppercase, drop the "(city)" marker and geographic-type
# suffixes, fold SAINT->ST, then strip everything but letters. is_city is captured separately (below) so
# VA/MD/MO independent cities stay distinct from the like-named county.
norm_name <- function(x) {
  x <- toupper(trimws(x))
  x <- gsub("\\(CITY\\)", "", x)
  x <- gsub("\\s+(COUNTY|PARISH|BOROUGH|CENSUS AREA|MUNICIPIO|MUNICIPALITY)$", "", x)
  x <- gsub("\\bSAINT\\b", "ST", x)
  gsub("[^A-Z]", "", x)
}

# ---- (a) ICIS side: spine facilities -------------------------------------------------------------------
s <- fread(SPINE, select = c("PGM_SYS_ID","STATE","COUNTY_NAME","county_fips","latitude","longitude"),
           colClasses = list(character = "county_fips"))
s[, statefp := STATE_FIPS[STATE]]
s[, is_city := grepl("\\(city\\)", COUNTY_NAME, ignore.case = TRUE)]
s[, icis_key := paste(statefp, norm_name(COUNTY_NAME), is_city, sep = "|")]

# ---- county shapefile: the crosswalk (GEOID <-> name) + geometry for distance --------------------------
co <- st_read(SHP, quiet = TRUE)
co$GEOID <- as.character(co$GEOID); co$STATEFP <- as.character(co$STATEFP)
cd <- as.data.table(st_drop_geometry(co))
cd[, is_city := grepl(" city$", NAMELSAD)]                 # TIGER independent cities: "Richmond city"
cd[, key := paste(STATEFP, norm_name(NAME), is_city, sep = "|")]

# resolve ICIS name -> GEOID. A key that maps to >1 GEOID is ambiguous (resolved to NA, bucketed separately).
xwalk <- cd[, .(geoid = if (uniqueN(GEOID) == 1L) GEOID[1] else NA_character_, n = uniqueN(GEOID)), by = key]
s[xwalk, on = .(icis_key = key), `:=`(resolved_geoid = i.geoid, key_n = i.n)]
s[is.na(key_n), key_n := 0L]                               # icis_key absent from crosswalk -> unresolved

# derived name = the county the COORDINATE landed in (county_fips -> shapefile NAME), for readability
s[cd, on = .(county_fips = GEOID), derived_name := i.NAMELSAD]

# ---- classify every facility ---------------------------------------------------------------------------
s[, status := fifelse(
  is.na(county_fips) | county_fips == "",              "no_coordinate",
  fifelse(is.na(resolved_geoid) & key_n > 1L,          "ambiguous_name",
  fifelse(is.na(resolved_geoid),                       "name_unresolved",
  fifelse(resolved_geoid == county_fips,               "match", "mismatch"))))]

# ---- coordinate pathology flags (independent of the county comparison) ---------------------------------
s[, zero_coord   := !is.na(latitude) & !is.na(longitude) & latitude == 0 & longitude == 0]
s[, positive_lon := !is.na(longitude) & longitude > 0]
s[, outside_conus := !is.na(latitude) & !is.na(longitude) &
     !(longitude > -125 & longitude < -66 & latitude > 24 & latitude < 50)]

# ---- grade mismatches: distance from the coordinate to the ICIS-claimed county polygon -----------------
s[, `:=`(dist_claimed_km = NA_real_, dist_centroid_km = NA_real_)]
mm <- s[status == "mismatch" & !is.na(resolved_geoid) & !is.na(latitude) & !is.na(longitude)]
if (nrow(mm)) {
  co5070   <- st_transform(co, 5070)                                   # CONUS Albers equal-area (metres)
  claimed  <- co5070[match(mm$resolved_geoid, co5070$GEOID), ]
  pts      <- st_transform(st_as_sf(mm, coords = c("longitude","latitude"), crs = 4326), 5070)
  d_poly   <- as.numeric(st_distance(pts, claimed, by_element = TRUE)) / 1000
  d_cent   <- as.numeric(st_distance(pts, st_centroid(claimed), by_element = TRUE)) / 1000
  s[status == "mismatch" & !is.na(resolved_geoid) & !is.na(latitude) & !is.na(longitude),
    `:=`(dist_claimed_km = d_poly, dist_centroid_km = d_cent)]
}

# ---- outputs -------------------------------------------------------------------------------------------
flags <- s[, .(PGM_SYS_ID, STATE, COUNTY_NAME, county_fips, derived_name,
               resolved_geoid, status, dist_claimed_km, dist_centroid_km,
               zero_coord, positive_lon, outside_conus)]
setorder(flags, -dist_claimed_km, na.last = TRUE)
fwrite(flags, file.path(OUT, "facility_flags.csv"))

# per-state match rate (denominator = resolvable + coordinate-present, i.e. match + mismatch only)
by_state <- s[, .(
  n_total          = .N,
  n_match          = sum(status == "match"),
  n_mismatch       = sum(status == "mismatch"),
  n_name_unresolved= sum(status == "name_unresolved"),
  n_ambiguous      = sum(status == "ambiguous_name"),
  n_no_coordinate  = sum(status == "no_coordinate")
), by = STATE][, match_rate := round(n_match / (n_match + n_mismatch), 4)][order(match_rate)]
fwrite(by_state, file.path(OUT, "summary_by_state.csv"))

# largest disagreements, for eyeballing
worst <- head(flags[status == "mismatch"][order(-dist_claimed_km)], 100)
fwrite(worst, file.path(OUT, "worst_mismatches.csv"))

# ---- console summary -----------------------------------------------------------------------------------
tab <- s[, .N, by = status][order(-N)]
checkable <- sum(s$status %in% c("match","mismatch"))
cat(sprintf("facilities: %s\n", format(nrow(s), big.mark=",")))
for (i in seq_len(nrow(tab))) cat(sprintf("  %-16s %s\n", tab$status[i], format(tab$N[i], big.mark=",")))
cat(sprintf("\ncounty match rate (match / (match+mismatch)) = %.3f  over %s checkable facilities\n",
            sum(s$status=="match")/checkable, format(checkable, big.mark=",")))
if (nrow(mm)) cat(sprintf("mismatch distance to claimed county: median %.1f km, p90 %.1f km, max %.0f km\n",
            median(s$dist_claimed_km, na.rm=TRUE), quantile(s$dist_claimed_km, .9, na.rm=TRUE),
            max(s$dist_claimed_km, na.rm=TRUE)))
cat(sprintf("wrote 3 CSVs to %s\n", OUT))
