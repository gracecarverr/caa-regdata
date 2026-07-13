# =========================================================================================================
# scripts/04_panels/00_spine.R -- build the FACILITY SPINE used by the panels (a derived construction, not a
#   raw-source clean asset). One row per ever-active facility, with coordinates, county, and static profiles.
#   in : data/clean/{inspections,violations,formal_actions,informal_actions,certs}.csv.gz  (active set)
#        data/clean/{facilities,pollutants,programs}.csv.gz  +  data/raw/frs/FRS_FACILITIES.csv
#        data/raw/us_counties/us_counties.shp
#   out: data/panels/spine.csv.gz
# =========================================================================================================
library(readr); library(dplyr); library(sf)
CLEAN <- here::here("data/clean"); RAW <- here::here("data/raw"); PANELS <- here::here("data/panels")
YEARS <- 2005:2025
FACILITY_TYPE <- c(POF = "Privately owned", COR = "Corporation", CNG = "County government",
                   CTG = "City government", FDF = "Federal facility", STF = "State facility",
                   DIS = "District", NON = "Non-classified")

# active universe = facilities with >= 1 event (in YEARS) across the five event assets
active <- unique(unlist(lapply(c("inspections","violations","formal_actions","informal_actions","certs"), function(a)
  read_csv(file.path(CLEAN, paste0(a, ".csv.gz")), col_select = c(PGM_SYS_ID, year),
           col_types = cols(PGM_SYS_ID = col_character(), year = col_integer()), show_col_types = FALSE) |>
    filter(year %in% YEARS) |> pull(PGM_SYS_ID))))

attrs <- read_csv(file.path(CLEAN, "facilities.csv.gz"),
  col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  select(PGM_SYS_ID, REGISTRY_ID, FACILITY_NAME, STREET_ADDRESS, CITY, COUNTY_NAME, STATE, ZIP_CODE, EPA_REGION,
         NAICS_CODES, SIC_CODES, FACILITY_TYPE_CODE, AIR_POLLUTANT_CLASS_DESC, AIR_OPERATING_STATUS_DESC) |>
  filter(PGM_SYS_ID %in% active) |> distinct(PGM_SYS_ID, .keep_all = TRUE)

frs <- read_csv(file.path(RAW, "frs", "FRS_FACILITIES.csv"),
  col_select = c(REGISTRY_ID, LATITUDE_MEASURE, LONGITUDE_MEASURE),
  col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  distinct(REGISTRY_ID, .keep_all = TRUE) |>
  transmute(REGISTRY_ID, latitude = suppressWarnings(as.numeric(LATITUDE_MEASURE)),
            longitude = suppressWarnings(as.numeric(LONGITUDE_MEASURE)))
fac <- attrs |> left_join(frs, by = "REGISTRY_ID")

co  <- st_read(file.path(RAW, "us_counties", "us_counties.shp"), quiet = TRUE); co$GEOID <- as.character(co$GEOID)
pts <- fac |> filter(!is.na(latitude), !is.na(longitude)) |>
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326) |> st_transform(st_crs(co))
fac_fips <- st_join(pts, co["GEOID"], join = st_within) |> st_drop_geometry() |>
  transmute(PGM_SYS_ID, county_fips = as.character(GEOID)) |> distinct(PGM_SYS_ID, .keep_all = TRUE)

prof <- read_csv(file.path(CLEAN, "pollutants.csv.gz"),
  col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  filter(PGM_SYS_ID %in% active) |>
  group_by(PGM_SYS_ID) |> summarise(
    emits_voc = as.integer(any(grepl("VOLATILE ORGANIC", POLLUTANT_DESC, ignore.case = TRUE))),
    emits_pm  = as.integer(any(grepl("PARTICULATE MATTER", POLLUTANT_DESC, ignore.case = TRUE))),
    emits_co  = as.integer(any(grepl("carbon monoxide", POLLUTANT_DESC, ignore.case = TRUE))),
    emits_nox = as.integer(any(grepl("NITROGEN OXIDES", POLLUTANT_DESC, ignore.case = TRUE))),
    emits_so2 = as.integer(any(grepl("sulfur dioxide", POLLUTANT_DESC, ignore.case = TRUE))),
    emits_hap = as.integer(any(grepl("HAZARDOUS AIR POLLUTANT", POLLUTANT_DESC, ignore.case = TRUE))),
    .groups = "drop")

progs <- read_csv(file.path(CLEAN, "programs.csv.gz"),
  col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  filter(PGM_SYS_ID %in% active) |>
  group_by(PGM_SYS_ID) |> summarise(
    prog_sip = as.integer(any(PROGRAM_CODE == "CAASIP")), prog_titlev = as.integer(any(PROGRAM_CODE == "CAATVP")),
    prog_nsps = as.integer(any(PROGRAM_CODE %in% c("CAANSPS","CAANSPSM"))), prog_mact = as.integer(any(PROGRAM_CODE == "CAAMACT")),
    prog_neshap = as.integer(any(PROGRAM_CODE == "CAANESH")), prog_fesop = as.integer(any(PROGRAM_CODE == "CAAFESOP")),
    prog_nsr = as.integer(any(PROGRAM_CODE == "CAANSR")), prog_psd = as.integer(any(PROGRAM_CODE == "CAAPSD")),
    n_programs = n_distinct(PROGRAM_CODE), .groups = "drop")

flags <- c("emits_voc","emits_pm","emits_co","emits_nox","emits_so2","emits_hap",
           "prog_sip","prog_titlev","prog_nsps","prog_mact","prog_neshap","prog_fesop","prog_nsr","prog_psd","n_programs")
spine <- fac |> left_join(fac_fips, by = "PGM_SYS_ID") |>
  left_join(prof, by = "PGM_SYS_ID") |> left_join(progs, by = "PGM_SYS_ID") |>
  mutate(facility_type = unname(FACILITY_TYPE[FACILITY_TYPE_CODE]),
         across(all_of(flags), \(x) as.integer(coalesce(x, 0L)))) |>
  relocate(county_fips, .after = COUNTY_NAME) |>
  relocate(facility_type, .after = FACILITY_TYPE_CODE) |> arrange(PGM_SYS_ID)

dir.create(PANELS, showWarnings = FALSE, recursive = TRUE)
write_csv(spine, file.path(PANELS, "spine.csv.gz"))
cat(sprintf("spine: %d facilities | %d columns\n", nrow(spine), ncol(spine)))
