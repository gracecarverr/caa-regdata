# =========================================================================================================
# code/03_panel_building/00_spine.R -- build the FACILITY SPINE used by the panels (a derived construction, not a
#   raw-source clean asset). One row per ever-active facility, with coordinates, county, and static profiles.
#   in : data/processed/{inspections,violations,formal_actions,informal_actions,certs,stacktests}.csv.gz  (active set)
#        data/processed/{facilities,pollutants,programs}.csv.gz  +  data/raw/frs/FRS_FACILITIES.csv
#        data/raw/us_counties/us_counties.shp
#   out: data/panels/spine.csv.gz
# =========================================================================================================
library(readr); library(dplyr); library(sf)
CLEAN <- here::here("data/processed"); RAW <- here::here("data/raw"); PANELS <- here::here("data/panels")
YEARS <- 2005:2025                                     # panel window used only to define the "active" universe here
FACILITY_TYPE <- c(POF = "Privately owned", COR = "Corporation", CNG = "County government",
                   CTG = "City government", FDF = "Federal facility", STF = "State facility",
                   DIS = "District", NON = "Non-classified")
                   # REVIEW(design): lookup table used below as FACILITY_TYPE[FACILITY_TYPE_CODE] -- any raw
                   # FACILITY_TYPE_CODE value not in this named vector (e.g. an ICIS code added after this list
                   # was written) silently resolves to NA with no warning or count of how many rows were affected

# active universe = facilities with >= 1 event (in YEARS) across the six event assets
active <- unique(unlist(lapply(c("inspections","violations","formal_actions","informal_actions","certs","stacktests"), function(a)
  read_csv(file.path(CLEAN, paste0(a, ".csv.gz")), col_select = c(PGM_SYS_ID, year),
           col_types = cols(PGM_SYS_ID = col_character(), year = col_integer()), show_col_types = FALSE) |>
    filter(year %in% YEARS) |> pull(PGM_SYS_ID))))
    # for each of the 6 event tables: read just (PGM_SYS_ID, year), keep rows in the panel window, pull the
    # facility IDs; unlist() flattens the per-table lists into one vector, unique() collapses to the distinct
    # facility-ID set that had >=1 qualifying event anywhere -- this becomes the row universe for the spine

attrs <- read_csv(file.path(CLEAN, "facilities.csv.gz"),
  col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  select(PGM_SYS_ID, REGISTRY_ID, FACILITY_NAME, STREET_ADDRESS, CITY, COUNTY_NAME, STATE, ZIP_CODE, EPA_REGION,
         NAICS_CODES, SIC_CODES, FACILITY_TYPE_CODE, AIR_POLLUTANT_CLASS_DESC,
         op_status_current_desc = AIR_OPERATING_STATUS_DESC) |>   # CURRENT snapshot only; year-varying status lives in the panels
  filter(PGM_SYS_ID %in% active)                       # restrict facility attributes to the active universe above

frs <- read_csv(file.path(RAW, "frs", "FRS_FACILITIES.csv"),
  col_select = c(REGISTRY_ID, LATITUDE_MEASURE, LONGITUDE_MEASURE),
  col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  distinct(REGISTRY_ID, .keep_all = TRUE) |>
  # REVIEW(design): if FRS_FACILITIES.csv has multiple rows per REGISTRY_ID with different (or some missing)
  # coordinates, distinct() keeps whichever row appears FIRST in the raw file -- there's no preference for a
  # row that actually HAS a non-missing lat/long over one that doesn't, so a facility could end up coordinate-
  # less here even though a usable coordinate exists a few rows later in the same source file
  transmute(REGISTRY_ID, latitude = suppressWarnings(as.numeric(LATITUDE_MEASURE)),
            longitude = suppressWarnings(as.numeric(LONGITUDE_MEASURE)))
            # as.numeric() on a non-numeric string yields NA with a coercion warning; suppressWarnings() hides
            # that warning (rows just become NA lat/long silently, filtered out of the spatial join below)
fac <- attrs |> left_join(frs, by = "REGISTRY_ID")     # attach FRS coordinates onto the facility attribute rows

co  <- st_read(file.path(RAW, "us_counties", "us_counties.shp"), quiet = TRUE); co$GEOID <- as.character(co$GEOID)
   # load the county polygons; GEOID forced to character (protects the 5-digit FIPS leading zero, e.g. "01001")
pts <- fac |> filter(!is.na(latitude), !is.na(longitude)) |>
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326) |> st_transform(st_crs(co))
  # only facilities with BOTH coordinates present become spatial points; assumed WGS84 (EPSG:4326, the FRS
  # convention), reprojected to whatever CRS the county shapefile uses. No sanity check here on the coordinate
  # values themselves (e.g. 0,0 "null island", or a lat/long that's plausible but in the wrong hemisphere) --
  # that's deferred entirely to the coord_county_flag.R gross-error check below, which can only catch cases
  # where the bad point still falls inside SOME real county (a point far out in the ocean or off the shapefile
  # entirely just produces an NA match at the st_join below, silently excluded rather than flagged as "bad")
fac_fips <- st_join(pts, co["GEOID"], join = st_within) |> st_drop_geometry() |>
  transmute(PGM_SYS_ID, county_fips = as.character(GEOID)) |> distinct(PGM_SYS_ID, .keep_all = TRUE)
  # st_within: a point that falls exactly on a shared county boundary can in principle match >1 polygon,
  # producing duplicate rows for that facility that distinct() then collapses to whichever came first from
  # st_join -- an edge case, but the tie-break is implicit (join/data order), not a documented rule

# coordinate-quality flag: is the FRS coordinate in the ICIS-listed county? (helper does the vintage-safe
# name resolution + distance grading; see code/diagnostics/coord_county_check/ for the analysis behind it.)
source(here::here("code/03_panel_building/coord_county_flag.R"))
coord_flags <- flag_coord_county(fac |> left_join(fac_fips, by = "PGM_SYS_ID"), co)
  # re-joins county_fips onto fac (not reusing `fac_fips` alone) so flag_coord_county() also has STATE/
  # COUNTY_NAME available for its own independent (STATE, COUNTY_NAME) -> GEOID resolution

prof <- read_csv(file.path(CLEAN, "pollutants.csv.gz"),
  col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  filter(PGM_SYS_ID %in% active) |>
  group_by(PGM_SYS_ID) |> summarise(                   # one row per facility: does it EVER report each pollutant class?
    emits_voc = as.integer(any(grepl("VOLATILE ORGANIC", POLLUTANT_DESC, ignore.case = TRUE))),
    emits_pm  = as.integer(any(grepl("PARTICULATE MATTER", POLLUTANT_DESC, ignore.case = TRUE))),
    emits_co  = as.integer(any(grepl("carbon monoxide", POLLUTANT_DESC, ignore.case = TRUE))),
    emits_nox = as.integer(any(grepl("NITROGEN OXIDES", POLLUTANT_DESC, ignore.case = TRUE))),
    emits_so2 = as.integer(any(grepl("sulfur dioxide", POLLUTANT_DESC, ignore.case = TRUE))),
    emits_hap = as.integer(any(grepl("HAZARDOUS AIR POLLUTANT", POLLUTANT_DESC, ignore.case = TRUE))),
    .groups = "drop")
    # each emits_* flag is a simple substring match against POLLUTANT_DESC text -- exact phrasing dependent;
    # a pollutant recorded under different wording (e.g. an abbreviation not containing these substrings)
    # would silently fail to set the flag, with no coverage check of what fraction of POLLUTANT_DESC values
    # matched none of the six categories

progs <- read_csv(file.path(CLEAN, "programs.csv.gz"),
  col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  filter(PGM_SYS_ID %in% active) |>
  group_by(PGM_SYS_ID) |> summarise(                   # one row per facility: program enrollment flags + earliest year
    prog_sip = as.integer(any(PROGRAM_CODE == "CAASIP")), prog_titlev = as.integer(any(PROGRAM_CODE == "CAATVP")),
    prog_nsps = as.integer(any(PROGRAM_CODE %in% c("CAANSPS","CAANSPSM"))), prog_mact = as.integer(any(PROGRAM_CODE == "CAAMACT")),
    # CAAGACTM = the Part 63 AREA-source counterpart to CAAMACT (major sources). Kept as its own flag, not
    # folded into prog_mact, so the major/area distinction stays visible.
    prog_gact = as.integer(any(PROGRAM_CODE == "CAAGACTM")),
    prog_neshap = as.integer(any(PROGRAM_CODE == "CAANESH")), prog_fesop = as.integer(any(PROGRAM_CODE == "CAAFESOP")),
    prog_nsr = as.integer(any(PROGRAM_CODE == "CAANSR")), prog_psd = as.integer(any(PROGRAM_CODE == "CAAPSD")),
    prog_cfc = as.integer(any(PROGRAM_CODE == "CAACFC")),   # Title VI stratospheric ozone protection
    n_programs = n_distinct(PROGRAM_CODE),                # count of distinct program codes this facility ever carried
    # earliest program-enrollment year from BEGIN_DATE (MM/DD/YYYY). Facility-level, provisional -- no end
    # date, so this dates first enrollment only (see data/processed/README.md). Junk years guarded to NA.
    program_begin_year = { y <- suppressWarnings(as.integer(sub(".*/", "", BEGIN_DATE)))
                           # sub(".*/", "", ...) strips everything up to and including the LAST "/", i.e.
                           # takes the year portion of an MM/DD/YYYY string; as.integer() on anything that
                           # isn't purely digits (a malformed/blank BEGIN_DATE) yields NA (warning suppressed)
                           y <- y[!is.na(y) & y >= 1900 & y <= 2026]
                           # REVIEW(design): upper bound 2026 is a hardcoded literal, not derived from
                           # Sys.Date()/YEARS -- once real data extends past 2026 this will start silently
                           # discarding otherwise-valid future BEGIN_DATE years as "junk" until the literal
                           # is updated by hand
                           if (length(y) == 0) NA_integer_ else min(y) },
    .groups = "drop")

# reconstructed entry/exit spell summary from the ICIS-AIR wayback snapshots (built in code/02_cleaning/wayback/18_).
# Time-INVARIANT per facility (one row); the year-varying operating status itself lives in the panels.
spells <- read_csv(file.path(CLEAN, "wayback_facility_spells.csv.gz"),
  col_types = cols(PGM_SYS_ID = col_character(), entered_year = col_integer(), exited_year = col_integer(),
                   exit_source = col_character(), left_censored = col_integer(), right_censored = col_integer()),
  show_col_types = FALSE) |> filter(PGM_SYS_ID %in% active)

flags <- c("emits_voc","emits_pm","emits_co","emits_nox","emits_so2","emits_hap",
           "prog_sip","prog_titlev","prog_nsps","prog_mact","prog_gact","prog_neshap","prog_fesop",
           "prog_nsr","prog_psd","prog_cfc","n_programs")
           # note: despite the variable name, n_programs is a COUNT not a 0/1 flag -- included here only
           # because it needs the same "NA -> 0 after left_join" coalesce treatment as the true flags below
spine <- fac |> left_join(fac_fips, by = "PGM_SYS_ID") |>       # attach spatial-join county
  left_join(coord_flags, by = "PGM_SYS_ID") |>                 # attach coordinate-quality QC columns
  left_join(prof, by = "PGM_SYS_ID") |> left_join(progs, by = "PGM_SYS_ID") |>   # attach pollutant/program flags
  left_join(spells, by = "PGM_SYS_ID") |>                       # attach wayback-derived entry/exit spell
  mutate(facility_type = unname(FACILITY_TYPE[FACILITY_TYPE_CODE]),   # human-readable label (NA if code unmapped)
         across(all_of(flags), \(x) as.integer(coalesce(x, 0L)))) |>  # facilities absent from prof/progs (no
                                                                        # pollutant/program row at all) get 0,
                                                                        # not NA, for every flag in `flags`
  relocate(county_fips, .after = COUNTY_NAME) |>
  relocate(coord_county_dist_km, coord_gross_error, .after = county_fips) |>
  relocate(facility_type, .after = FACILITY_TYPE_CODE) |> arrange(PGM_SYS_ID)   # cosmetic column ordering + sort

dir.create(PANELS, showWarnings = FALSE, recursive = TRUE)
write_csv(spine, file.path(PANELS, "spine.csv.gz"))
cat(sprintf("spine: %d facilities | %d columns\n", nrow(spine), ncol(spine)))
