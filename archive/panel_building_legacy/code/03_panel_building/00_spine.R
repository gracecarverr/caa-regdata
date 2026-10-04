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
# all 15 codes from the official ICIS-Air data dictionary (FACILITY_TYPE_CODE field definition,
# https://echo.epa.gov/tools/data-downloads/icis-air-download-summary, fetched 2026-07-28) -- previously
# only 8 were mapped and 2 of those (CTG, NON) used wording that drifted from the official meaning: CTG
# was labeled "City government" (official: "Municipality") and NON was labeled "Non-classified" (official:
# "Non-Government" -- a specific ownership category, not "unclassified"). The unmapped-code gap was real:
# 558 facilities (2026-07-28 snapshot) carried a code -- TRB (260), MWD (177), SDT (61), MXO (60) -- that
# silently resolved to NA facility_type under the old 8-code list.
FACILITY_TYPE <- c(POF = "Privately owned", COR = "Corporation", CNG = "County government",
                   CTG = "Municipality", FDF = "Federal facility", STF = "State facility",
                   DIS = "District", NON = "Non-government", GOC = "GOCO (government-owned, contractor-operated)",
                   IND = "Individual", MXO = "Mixed ownership (public/private)",
                   MWD = "Municipal or water district", SDT = "School district", TRB = "Tribal government",
                   UNK = "Unknown")
                   # any FACILITY_TYPE_CODE value still not in this named vector (e.g. a future ICIS code
                   # added after 2026-07-28) silently resolves to NA -- there is no warning or count of how
                   # many rows that would affect, but the list above is now the complete official code set,
                   # so this should only trigger on a genuinely new ICIS addition, not a pre-existing gap

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
  # a point that's garbage but still lands inside SOME real county is caught by the coord_county_flag.R
  # gross-error check below; a point that lands outside every county (ocean, off-map, wrong hemisphere) is
  # caught instead by coord_no_county_match below, since it produces no st_join match at all
fac_fips <- st_join(pts, co["GEOID"], join = st_within) |> st_drop_geometry() |>
  transmute(PGM_SYS_ID, county_fips = as.character(GEOID)) |> distinct(PGM_SYS_ID, .keep_all = TRUE) |>
  mutate(coord_no_county_match = as.integer(is.na(county_fips)))
  # coord_no_county_match: 1 = facility had a usable (lat, long) but it fell outside every county polygon in
  # the shapefile, so county_fips is NA for a reason distinct from "no coordinates were available at all"
  # (that case is NA on both columns after the left_join into `spine` below, since such facilities never
  # entered `pts` in the first place). st_within: a point exactly on a shared county boundary can in
  # principle match >1 polygon; distinct() then keeps whichever row came first out of st_join -- a real but
  # vanishingly rare edge case for continuous-valued coordinates, tie-break left undocumented/arbitrary.

# coordinate-quality flag: is the FRS coordinate in the ICIS-listed county? (helper does the vintage-safe
# name resolution + distance grading; see code/diagnostics/coord_county_check/ for the analysis behind it.)
source(here::here("code/03_panel_building/coord_county_flag.R"))
coord_flags <- flag_coord_county(fac |> left_join(fac_fips, by = "PGM_SYS_ID"), co)
  # re-joins county_fips onto fac (not reusing `fac_fips` alone) so flag_coord_county() also has STATE/
  # COUNTY_NAME available for its own independent (STATE, COUNTY_NAME) -> GEOID resolution

source(here::here("code/03_panel_building/hap_list_112b.R"))   # HAP_112B, HAP_COMPOUND_CLASS_PATTERNS
hap_cas <- HAP_112B$cas_number[!HAP_112B$is_compound_class]     # real CAS numbers on the current CAA
                                                                 # 112(b) list -- exact join key, not text
hap_class_regex <- paste(HAP_COMPOUND_CLASS_PATTERNS, collapse = "|")  # one combined pattern for the 17
                                                                 # CAS-"0" compound classes (no CAS to join on)

pollutants_raw <- read_csv(file.path(CLEAN, "pollutants.csv.gz"),
  col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  filter(PGM_SYS_ID %in% active)

prof <- pollutants_raw |>
  group_by(PGM_SYS_ID) |> summarise(                   # one row per facility: does it EVER report each pollutant class?
    # (?<!NON-) excludes POLLUTANT_CODE 300000310 "NON-VOLATILE ORGANIC COMPOUNDS" -- the opposite category,
    # which otherwise matches "VOLATILE ORGANIC" as a plain substring (found 2026-07-28, 49 facilities/54 rows;
    # same fix applied to code/04_datasets/01_regulatory.R's identical emits_voc rule)
    emits_voc = as.integer(any(grepl("(?<!NON-)VOLATILE ORGANIC", POLLUTANT_DESC, ignore.case = TRUE, perl = TRUE))),
    emits_pm  = as.integer(any(grepl("PARTICULATE MATTER", POLLUTANT_DESC, ignore.case = TRUE))),
    emits_co  = as.integer(any(grepl("carbon monoxide", POLLUTANT_DESC, ignore.case = TRUE))),
    emits_nox = as.integer(any(grepl("NITROGEN OXIDES", POLLUTANT_DESC, ignore.case = TRUE))),
    emits_so2 = as.integer(any(grepl("sulfur dioxide", POLLUTANT_DESC, ignore.case = TRUE))),
    # emits_hap: the UNION of three signals, not a replacement of the old rule -- checked empirically
    # (2026-07-28) that each catches facilities the others miss:
    #  (1) umbrella-phrase match ("HAZARDOUS AIR POLLUTANT" in POLLUTANT_DESC) -- this is what the old
    #      rule used alone. It turns out to mean something specific and real: ICIS lets a facility report
    #      an aggregate "TOTAL HAZARDOUS AIR POLLUTANTS (HAPS)" figure (no CAS number -- it's a summary
    #      record, not a substance) instead of, or in addition to, itemizing individual HAP species.
    #      16,868 facilities (of 122,847 checked) have ONLY this aggregate record and no itemized HAP --
    #      dropping this signal entirely would have silently misclassified all of them as non-HAP-emitting.
    #  (2) CAS-number match against the official CAA 112(b) list (HAP_112B, hap_list_112b.R) -- exact,
    #      not text-fuzzy. Catches facilities that itemize a named HAP species (Benzene, Formaldehyde,
    #      Lead, Mercury, ...) without ever reporting the (1) aggregate total. 13,177 facilities are
    #      caught only this way -- this is the coverage gap the old umbrella-only rule had.
    #  (3) name match against the 17 compound-class entries that have no single CAS to join on.
    # See panel_construction_decisions.md for the full before/after facility counts.
    emits_hap = as.integer(any(grepl("HAZARDOUS AIR POLLUTANT", POLLUTANT_DESC, ignore.case = TRUE)) ||
                             any(trimws(CHEMICAL_ABSTRACT_SERVICE_NMBR) %in% hap_cas) ||
                             any(grepl(hap_class_regex, POLLUTANT_DESC, ignore.case = TRUE))),
    .groups = "drop")
    # the other five emits_* flags stay simple substring matches -- confirmed low-risk (2026-07-28): each
    # is backed by only 1-8 distinct POLLUTANT_CODE values in the current data, unlike HAP's long tail of
    # ~600+ named compounds, so umbrella-phrase substring matching doesn't have the same coverage gap here.

# coverage diagnostic: how much of the raw pollutant record still falls outside all six categories after
# the emits_hap fix, so any residual gap is visible in the run log rather than silent (see also the
# coord_no_county_match diagnostic above)
uncovered <- !(grepl("(?<!NON-)VOLATILE ORGANIC|PARTICULATE MATTER|NITROGEN OXIDES|carbon monoxide|sulfur dioxide|HAZARDOUS AIR POLLUTANT",
                     pollutants_raw$POLLUTANT_DESC, ignore.case = TRUE, perl = TRUE) |
               trimws(pollutants_raw$CHEMICAL_ABSTRACT_SERVICE_NMBR) %in% hap_cas |
               grepl(hap_class_regex, pollutants_raw$POLLUTANT_DESC, ignore.case = TRUE))
cat(sprintf("pollutants coverage: %d / %d rows (%.1f%%) match none of the six emits_* categories\n",
            sum(uncovered), length(uncovered), 100 * mean(uncovered)))

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
  relocate(county_fips, coord_no_county_match, .after = COUNTY_NAME) |>
  relocate(coord_county_dist_km, coord_gross_error, .after = coord_no_county_match) |>
  relocate(facility_type, .after = FACILITY_TYPE_CODE) |> arrange(PGM_SYS_ID)   # cosmetic column ordering + sort

dir.create(PANELS, showWarnings = FALSE, recursive = TRUE)
write_csv(spine, file.path(PANELS, "spine.csv.gz"))
cat(sprintf("spine: %d facilities | %d columns | %d with coordinates outside every county polygon\n",
            nrow(spine), ncol(spine), sum(spine$coord_no_county_match == 1, na.rm = TRUE)))
