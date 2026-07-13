# =========================================================================================================
# scripts/02_clean/09_facilities.R -- the FACILITY SPINE: one row per ever-active facility, with attributes
#   and join keys. RUNS LAST (reads the event assets to define the active universe).
#   in : data/clean/{inspections,violations,enforcement,certs}.csv.gz  (active set)
#        data/raw/ICIS-AIR_downloads/ICIS-AIR_{FACILITIES,POLLUTANTS,PROGRAMS}.csv
#        data/raw/frs/FRS_FACILITIES.csv  +  data/raw/us_counties/us_counties.shp
#   out: data/clean/facilities.csv.gz
#
#   Unlike the event assets, the spine is ONE ROW PER FACILITY (a facility attribute table, not events), so
#   it carries no dup flags -- that grain is definitional. Attributes are the current ICIS snapshot
#   (time-invariant here). Static "ever-*" profiles: emits_* (pollutants) and prog_* (program enrollment).
# =========================================================================================================
source(here::here("R/clean.R"))
suppressPackageStartupMessages(library(sf))

# ICIS FACILITY_TYPE_CODE decode (best-effort; not in the source data dictionary).
FACILITY_TYPE <- c(POF = "Privately owned", COR = "Corporation", CNG = "County government",
                   CTG = "City government",  FDF = "Federal facility", STF = "State facility",
                   DIS = "District",         NON = "Non-classified")

# ---- active universe = facilities with >= 1 event (in YEARS) across the four event assets ----------------
active <- unique(unlist(lapply(c("inspections", "violations", "enforcement", "certs"), function(a)
  read_csv(file.path(CLEAN, paste0(a, ".csv.gz")), col_select = c(PGM_SYS_ID, year),
           col_types = cols(PGM_SYS_ID = col_character(), year = col_integer()), show_col_types = FALSE) |>
    filter(year %in% YEARS) |> pull(PGM_SYS_ID))))

# ---- current attribute snapshot (one row per facility) --------------------------------------------------
attrs <- read_csv(file.path(RAW, "ICIS-AIR_downloads", "ICIS-AIR_FACILITIES.csv"),
  col_select = c(PGM_SYS_ID, REGISTRY_ID, FACILITY_NAME, STREET_ADDRESS, CITY, COUNTY_NAME, STATE, ZIP_CODE,
                 EPA_REGION, NAICS_CODES, SIC_CODES, FACILITY_TYPE_CODE, AIR_POLLUTANT_CLASS_DESC,
                 AIR_OPERATING_STATUS_DESC),
  col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  filter(PGM_SYS_ID %in% active) |> distinct(PGM_SYS_ID, .keep_all = TRUE)

# ---- FRS coordinates (one lat/long per physical site, keyed on REGISTRY_ID) ------------------------------
frs <- read_csv(file.path(RAW, "frs", "FRS_FACILITIES.csv"),
  col_select = c(REGISTRY_ID, LATITUDE_MEASURE, LONGITUDE_MEASURE),
  col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  distinct(REGISTRY_ID, .keep_all = TRUE) |>
  transmute(REGISTRY_ID, latitude = suppressWarnings(as.numeric(LATITUDE_MEASURE)),
            longitude = suppressWarnings(as.numeric(LONGITUDE_MEASURE)))
fac <- attrs |> left_join(frs, by = "REGISTRY_ID")

# ---- point-in-county: exact county FIPS from the coordinate ---------------------------------------------
co  <- st_read(file.path(RAW, "us_counties", "us_counties.shp"), quiet = TRUE); co$GEOID <- as.character(co$GEOID)
pts <- fac |> filter(!is.na(latitude), !is.na(longitude)) |>
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326) |> st_transform(st_crs(co))
fac_fips <- st_join(pts, co["GEOID"], join = st_within) |> st_drop_geometry() |>
  transmute(PGM_SYS_ID, county_fips = as.character(GEOID)) |> distinct(PGM_SYS_ID, .keep_all = TRUE)

# ---- pollutant profile: static "ever regulated for" flags (ICIS-AIR_POLLUTANTS) -------------------------
prof <- read_csv(file.path(RAW, "ICIS-AIR_downloads", "ICIS-AIR_POLLUTANTS.csv"),
  col_select = c(PGM_SYS_ID, POLLUTANT_DESC), col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  filter(PGM_SYS_ID %in% active) |>
  group_by(PGM_SYS_ID) |> summarise(
    emits_voc = as.integer(any(grepl("VOLATILE ORGANIC",        POLLUTANT_DESC, ignore.case = TRUE))),
    emits_pm  = as.integer(any(grepl("PARTICULATE MATTER",      POLLUTANT_DESC, ignore.case = TRUE))),
    emits_co  = as.integer(any(grepl("carbon monoxide",         POLLUTANT_DESC, ignore.case = TRUE))),
    emits_nox = as.integer(any(grepl("NITROGEN OXIDES",         POLLUTANT_DESC, ignore.case = TRUE))),
    emits_so2 = as.integer(any(grepl("sulfur dioxide",          POLLUTANT_DESC, ignore.case = TRUE))),
    emits_hap = as.integer(any(grepl("HAZARDOUS AIR POLLUTANT", POLLUTANT_DESC, ignore.case = TRUE))),
    .groups = "drop")

# ---- program-enrollment profile: static "ever enrolled" flags (ICIS-AIR_PROGRAMS) -----------------------
progs <- read_csv(file.path(RAW, "ICIS-AIR_downloads", "ICIS-AIR_PROGRAMS.csv"),
  col_select = c(PGM_SYS_ID, PROGRAM_CODE), col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  filter(PGM_SYS_ID %in% active) |>
  group_by(PGM_SYS_ID) |> summarise(
    prog_sip    = as.integer(any(PROGRAM_CODE == "CAASIP")),
    prog_titlev = as.integer(any(PROGRAM_CODE == "CAATVP")),
    prog_nsps   = as.integer(any(PROGRAM_CODE %in% c("CAANSPS", "CAANSPSM"))),
    prog_mact   = as.integer(any(PROGRAM_CODE == "CAAMACT")),
    prog_neshap = as.integer(any(PROGRAM_CODE == "CAANESH")),
    prog_fesop  = as.integer(any(PROGRAM_CODE == "CAAFESOP")),
    prog_nsr    = as.integer(any(PROGRAM_CODE == "CAANSR")),
    prog_psd    = as.integer(any(PROGRAM_CODE == "CAAPSD")),
    n_programs  = n_distinct(PROGRAM_CODE), .groups = "drop")

# ---- assemble -------------------------------------------------------------------------------------------
prof_cols <- c("emits_voc","emits_pm","emits_co","emits_nox","emits_so2","emits_hap")
prog_cols <- c("prog_sip","prog_titlev","prog_nsps","prog_mact","prog_neshap","prog_fesop","prog_nsr","prog_psd")
facilities <- fac |> left_join(fac_fips, by = "PGM_SYS_ID") |>
  left_join(prof, by = "PGM_SYS_ID") |> left_join(progs, by = "PGM_SYS_ID") |>
  mutate(facility_type = unname(FACILITY_TYPE[FACILITY_TYPE_CODE]),
         across(all_of(c(prof_cols, prog_cols, "n_programs")), \(x) as.integer(coalesce(x, 0L)))) |>
  transmute(PGM_SYS_ID, REGISTRY_ID, FACILITY_NAME, STREET_ADDRESS, CITY, COUNTY_NAME, county_fips, STATE,
            ZIP_CODE, EPA_REGION, latitude, longitude, NAICS_CODES, SIC_CODES,
            FACILITY_TYPE_CODE, facility_type, AIR_POLLUTANT_CLASS_DESC, AIR_OPERATING_STATUS_DESC,
            emits_voc, emits_pm, emits_co, emits_nox, emits_so2, emits_hap,
            prog_sip, prog_titlev, prog_nsps, prog_mact, prog_neshap, prog_fesop, prog_nsr, prog_psd, n_programs) |>
  arrange(PGM_SYS_ID)

write_asset(facilities, "facilities", dict = c(
  PGM_SYS_ID = "ICIS-Air facility (program-system) id -- the spine key",
  REGISTRY_ID = "FRS physical-site id (cross-system join key)",
  FACILITY_NAME = "facility name", STREET_ADDRESS = "street address", CITY = "city",
  COUNTY_NAME = "county name (as reported)", county_fips = "county FIPS from point-in-county on the coordinate",
  STATE = "state", ZIP_CODE = "ZIP code", EPA_REGION = "EPA region",
  latitude = "FRS latitude (NA if unplaceable)", longitude = "FRS longitude (NA if unplaceable)",
  NAICS_CODES = "NAICS code(s), delimited", SIC_CODES = "SIC code(s), delimited",
  FACILITY_TYPE_CODE = "ownership code (FACILITY_TYPE_CODE)", facility_type = "ownership, decoded",
  AIR_POLLUTANT_CLASS_DESC = "air pollutant class (Major / Synthetic Minor / ...)",
  AIR_OPERATING_STATUS_DESC = "operating status (current snapshot)",
  emits_voc = "1 if ever regulated for volatile organic compounds",
  emits_pm  = "1 if ever regulated for particulate matter",
  emits_co  = "1 if ever regulated for carbon monoxide",
  emits_nox = "1 if ever regulated for nitrogen oxides",
  emits_so2 = "1 if ever regulated for sulfur dioxide",
  emits_hap = "1 if ever regulated for hazardous air pollutants",
  prog_sip = "1 if ever enrolled in State Implementation Plan (CAASIP)",
  prog_titlev = "1 if ever enrolled in Title V Permits (CAATVP)",
  prog_nsps = "1 if ever enrolled in New Source Performance Standards (CAANSPS/CAANSPSM)",
  prog_mact = "1 if ever enrolled in MACT Standards (CAAMACT)",
  prog_neshap = "1 if ever enrolled in NESHAP (CAANESH)",
  prog_fesop = "1 if ever enrolled in Federally-Enforceable State Operating Permit (CAAFESOP)",
  prog_nsr = "1 if ever enrolled in New Source Review (CAANSR)",
  prog_psd = "1 if ever enrolled in Prevention of Significant Deterioration (CAAPSD)",
  n_programs = "count of all distinct programs the facility is enrolled in"
))
