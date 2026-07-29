# =========================================================================================================
# code/04_panel_building/00_spine.R -- build the shared CANDIDATE FACILITY SET for the two panels this
#   pipeline ships (major_synmin_continuous_2015_2025, electric_continuous_2015_2025). NOT a general-purpose
#   "ever-active universe" like the old (archived) spine -- both target panels require CONUS + Major/
#   Synthetic-Minor class, so that filter is applied HERE, once, rather than duplicated per panel spec.
#   electric is a strict subset of this candidate set (03_build_parameters.R adds the NAICS/SIC filter).
#
#   This is a from-scratch rewrite, NOT the old code/03_panel_building/00_spine.R renamed -- that file
#   (and the rest of the old, data/processed/-based panel pipeline) is archived in full at
#   archive/panel_building_legacy/, see that directory's README for why. This version reads ONLY from
#   data/datasets/ (the eight-dataset layer) -- no raw event assets, no FRS/shapefile spatial join, no HAP
#   list -- all of that work already happened once, upstream, building regulatory.csv.gz/coordinates.csv.gz.
#
#   in : data/datasets/{regulatory,coordinates,operating}.csv.gz
#   out: an in-memory `spine` data frame (no CSV written -- only two panels consume it, both built in the
#        same R session by 03_build.R, so there's no reuse case that would justify a persisted intermediate;
#        revisit this if a third panel or a debugging need for a standalone spine.csv.gz ever comes up)
# =========================================================================================================
library(readr); library(dplyr); library(tidyr)
DATASETS <- here::here("data/datasets")

# 48 contiguous states + DC (excludes AK, HI, and all territories) -- identical list to the archived
# pipeline's CONUS constant (archive/panel_building_legacy/code/03_panel_building/03_build_parameters.R)
CONUS <- c("AL","AZ","AR","CA","CO","CT","DE","DC","FL","GA","ID","IL","IN","IA","KS","KY","LA","ME","MD",
           "MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH","OK","OR","PA","RI",
           "SC","SD","TN","TX","UT","VT","VA","WA","WV","WI","WY")

# Emissions classes both target panels require (electric is a further-restricted subset of this).
MAJOR_SYNMIN_CLASSES <- c("Major Emissions", "Synthetic Minor Emissions")

CONTINUITY_YEARS <- 2015:2025   # the window the continuity screen (and both final panels) are defined over --
                                 # matches Wayback's real coverage window, not this repo's usual 2005:2025

# ---- facility attributes (one row per facility) -----------------------------------------------------------
# regulatory.csv.gz (dataset 0) already carries the current-snapshot attributes, the 6 EMITS_* flags, and the
# 8-group PROG_* flags (GACT/CFC are NOT in this file at all -- dataset 0 excludes them by its own design,
# R6 -- so there's no extra work needed here to drop them, unlike the archived pipeline which had to
# deliberately exclude them from its own 10-group wayback read).
attrs <- read_csv(file.path(DATASETS, "regulatory.csv.gz"),
                  col_select = c(PGM_SYS_ID, YEAR, REGISTRY_ID, FACILITY_NAME, STREET_ADDRESS, CITY,
                                 COUNTY_NAME, STATE, ZIP_CODE, EPA_REGION, NAICS_CODES, SIC_CODES,
                                 FACILITY_TYPE_CODE, FACILITY_TYPE, AIR_POLLUTANT_CLASS_DESC,
                                 OP_STATUS_CURRENT_DESC, EMITS_VOC, EMITS_PM, EMITS_CO, EMITS_NOX, EMITS_SO2,
                                 EMITS_HAP, PROG_SIP, PROG_TITLEV, PROG_NSPS, PROG_MACT, PROG_NESHAP,
                                 PROG_FESOP, PROG_NSR, PROG_PSD, N_PROGRAMS),
                  # every column typed explicitly, not col_guess() -- guessing on this large a file is
                  # unreliable when a column's first-sampled rows happen to be unrepresentative (caught a
                  # real instance of this in 03_build_functions.R's read_counts: PENALTY_AMOUNT is NA in
                  # ~99.6% of rows, so col_guess() sampled all-NA and typed it col_logical(), which then
                  # SILENTLY discarded every real dollar figure later in the file as an unparseable "logical"
                  # value -- no error, no warning surfaced to problems(), just quiet data loss). REGISTRY_ID
                  # is character here (not numeric) to protect it from the same class of bug even though a
                  # numeric guess wouldn't currently corrupt it -- IDs are never arithmetic.
                  col_types = cols(PGM_SYS_ID = col_character(), YEAR = col_integer(),
                                   REGISTRY_ID = col_character(), FACILITY_NAME = col_character(),
                                   STREET_ADDRESS = col_character(), CITY = col_character(),
                                   COUNTY_NAME = col_character(), STATE = col_character(),
                                   ZIP_CODE = col_character(), EPA_REGION = col_character(),
                                   NAICS_CODES = col_character(), SIC_CODES = col_character(),
                                   FACILITY_TYPE_CODE = col_character(), FACILITY_TYPE = col_character(),
                                   AIR_POLLUTANT_CLASS_DESC = col_character(),
                                   OP_STATUS_CURRENT_DESC = col_character(),
                                   EMITS_VOC = col_integer(), EMITS_PM = col_integer(),
                                   EMITS_CO = col_integer(), EMITS_NOX = col_integer(),
                                   EMITS_SO2 = col_integer(), EMITS_HAP = col_integer(),
                                   PROG_SIP = col_integer(), PROG_TITLEV = col_integer(),
                                   PROG_NSPS = col_integer(), PROG_MACT = col_integer(),
                                   PROG_NESHAP = col_integer(), PROG_FESOP = col_integer(),
                                   PROG_NSR = col_integer(), PROG_PSD = col_integer(),
                                   N_PROGRAMS = col_integer()),
                  show_col_types = FALSE) |>
  arrange(PGM_SYS_ID, YEAR) |>                          # ensure a stable, deterministic "first" row per facility
  distinct(PGM_SYS_ID, .keep_all = TRUE) |>              # attributes are time-invariant -- one row/facility is enough
  select(-YEAR)                                          # was only needed to pick a stable row above

# ---- CONUS + class filter: the shared baseline for BOTH target panels --------------------------------------
candidates <- attrs |> filter(STATE %in% CONUS, AIR_POLLUTANT_CLASS_DESC %in% MAJOR_SYNMIN_CLASSES)
cand_ids <- candidates$PGM_SYS_ID
stopifnot("regulatory.csv.gz: PGM_SYS_ID not unique after distinct()" = !anyDuplicated(attrs$PGM_SYS_ID))

# ---- coordinates (one row per facility) --------------------------------------------------------------------
coords <- read_csv(file.path(DATASETS, "coordinates.csv.gz"),
                   col_select = c(PGM_SYS_ID, LATITUDE, LONGITUDE, HAS_COORDINATE, COUNTY_FIPS,
                                  ICIS_COUNTY_FIPS, COORD_COUNTY_DIST_KM, COORD_GROSS_ERROR),
                   # COUNTY_FIPS/ICIS_COUNTY_FIPS MUST be character, not guessed -- these are 5-digit FIPS
                   # codes with a leading zero for ~10 states (e.g. "01001" Alabama); a numeric guess would
                   # silently truncate that leading zero on every affected row, corrupting the code without
                   # any parse error (same silent-corruption family as the PENALTY_AMOUNT bug documented in
                   # the attrs read above, just via truncation instead of an all-NA guess).
                   col_types = cols(PGM_SYS_ID = col_character(), LATITUDE = col_double(),
                                    LONGITUDE = col_double(), HAS_COORDINATE = col_integer(),
                                    COUNTY_FIPS = col_character(), ICIS_COUNTY_FIPS = col_character(),
                                    COORD_COUNTY_DIST_KM = col_double(), COORD_GROSS_ERROR = col_integer()),
                   show_col_types = FALSE) |>
  filter(PGM_SYS_ID %in% cand_ids) |>                    # only need coordinates for candidate facilities
  mutate(COORD_NO_COUNTY_MATCH = as.integer(HAS_COORDINATE == 1 & is.na(COUNTY_FIPS)))
  # coordinates.csv.gz doesn't ship this flag directly (it's a coordinates-layer diagnostic the archived
  # spine used to compute inline) -- derived here the same way: a facility WITH a usable coordinate whose
  # point-in-polygon lookup still failed to land in any county polygon at all (distinct from "no coordinate
  # to begin with", which is HAS_COORDINATE==0 and COUNTY_FIPS NA for a different reason)

# ---- facility-level operating fields (entry/exit spell + begin-year), one row per facility -----------------
op_facility <- read_csv(file.path(DATASETS, "operating.csv.gz"),
                        col_select = c(PGM_SYS_ID, YEAR, ENTERED_YEAR, EXITED_YEAR, EXIT_SOURCE,
                                       LEFT_CENSORED, RIGHT_CENSORED, EARLIEST_PROGRAM_BEGIN_YEAR,
                                       EARLIEST_PROGRAM_BEGIN_YEAR_RAW),
                        # EXITED_YEAR/EXIT_SOURCE are NA for most facilities (only ~14% have ever exited),
                        # so col_guess() samples mostly-NA rows and mistypes both as col_logical() --
                        # CONFIRMED empirically this session (spec_csv on this exact column set guessed
                        # EXITED_YEAR/EXIT_SOURCE as logical) -- the same silent-corruption bug class as
                        # PENALTY_AMOUNT above, caught before it could corrupt this panel's spell columns.
                        col_types = cols(PGM_SYS_ID = col_character(), YEAR = col_integer(),
                                         ENTERED_YEAR = col_integer(), EXITED_YEAR = col_integer(),
                                         EXIT_SOURCE = col_character(), LEFT_CENSORED = col_integer(),
                                         RIGHT_CENSORED = col_integer(),
                                         EARLIEST_PROGRAM_BEGIN_YEAR = col_integer(),
                                         EARLIEST_PROGRAM_BEGIN_YEAR_RAW = col_integer()),
                        show_col_types = FALSE) |>
  filter(PGM_SYS_ID %in% cand_ids) |>
  arrange(PGM_SYS_ID, YEAR) |> distinct(PGM_SYS_ID, .keep_all = TRUE) |>   # these 7 fields are broadcast
  select(-YEAR)                                                            # identically across all 21 rows
                                                                             # in operating.csv.gz already --
                                                                             # one row/facility is enough here

# ---- continuity screen: ACTIVE_BROAD == 1 in EVERY year 2015-2025 ------------------------------------------
# The load-bearing new rule (replaces the archived pipeline's "active every year" via raw regulatory events
# only). ACTIVE_BROAD (operating.csv.gz, decision O6 in dataset_construction_decisions.md) is itself a union
# of wayback-operating, ICIS-observed, and emissions/GHG-reported evidence for that SPECIFIC year -- using it
# here means a facility only counts as "continuously active" if every one of the 11 years has POSITIVE
# evidence from at least one of those three channels; a single year with a confirmed non-operating status
# (ACTIVE_BROAD == 0) OR a single year of no evidence at all (ACTIVE_BROAD == NA) fails the screen. There is
# no partial credit and no imputation across the gap -- `all()` on an 11-element vector requires every
# element to be exactly 1.
continuity <- read_csv(file.path(DATASETS, "operating.csv.gz"),
                       col_select = c(PGM_SYS_ID, YEAR, ACTIVE_BROAD),
                       col_types = cols(PGM_SYS_ID = col_character(), YEAR = col_integer(),
                                        ACTIVE_BROAD = col_integer()), show_col_types = FALSE) |>
  filter(PGM_SYS_ID %in% cand_ids, YEAR %in% CONTINUITY_YEARS) |>
  group_by(PGM_SYS_ID) |>
  summarise(CONTINUOUSLY_ACTIVE = all(ACTIVE_BROAD == 1), .groups = "drop")
  # `all(ACTIVE_BROAD == 1)`: if ANY of the 11 years has ACTIVE_BROAD == 0, this is FALSE (fails); if ANY
  # year has ACTIVE_BROAD == NA, `NA == 1` is NA, and all() with an NA present (no FALSE) returns NA -- which
  # R then treats as "not TRUE" everywhere this is used as a filter condition below (dplyr::filter() keeps
  # only rows where the condition is exactly TRUE, silently dropping NA rows same as FALSE ones) -- so a
  # facility with a data GAP in the 2015-2025 span fails the screen exactly like a confirmed-inactive year
  # would, never passes by silent coercion. Verified this is the desired behavior (not merely a side effect)
  # against the spec: "continuously active" should mean no gaps, not "no confirmed gaps."
stopifnot("continuity: PGM_SYS_ID x YEAR not unique in operating.csv.gz" =
            !anyDuplicated(read_csv(file.path(DATASETS, "operating.csv.gz"),
                                    col_select = c(PGM_SYS_ID, YEAR),
                                    col_types = cols(PGM_SYS_ID = col_character(), YEAR = col_integer()),
                                    show_col_types = FALSE)[c("PGM_SYS_ID", "YEAR")]))

# ---- assemble the candidate spine --------------------------------------------------------------------------
spine <- candidates |>
  left_join(coords,      by = "PGM_SYS_ID") |>
  left_join(op_facility, by = "PGM_SYS_ID") |>
  left_join(continuity,  by = "PGM_SYS_ID") |>
  mutate(CONTINUOUSLY_ACTIVE = coalesce(CONTINUOUSLY_ACTIVE, FALSE)) |>
  # a candidate facility absent from `continuity` entirely (zero rows in operating.csv.gz for 2015-2025,
  # which shouldn't happen given operating.csv.gz is a full balanced rectangle -- but coalesced defensively
  # rather than left as NA, since a missing continuity read must mean "fails the screen," not "unknown")
  arrange(PGM_SYS_ID)

stopifnot(
  "spine: PGM_SYS_ID not unique"                    = !anyDuplicated(spine$PGM_SYS_ID),
  "spine: a non-CONUS state leaked in"               = all(spine$STATE %in% CONUS),
  "spine: a non-major/synmin class leaked in"        = all(spine$AIR_POLLUTANT_CLASS_DESC %in% MAJOR_SYNMIN_CLASSES),
  "spine: COORD_NO_COUNTY_MATCH set without a coordinate" =
    all(spine$COORD_NO_COUNTY_MATCH[spine$HAS_COORDINATE == 0] == 0 | is.na(spine$COORD_NO_COUNTY_MATCH[spine$HAS_COORDINATE == 0])),
  "spine: CONTINUOUSLY_ACTIVE is not a clean logical (TRUE/FALSE, no NA)" =
    all(!is.na(spine$CONTINUOUSLY_ACTIVE)))

cat(sprintf("spine (candidate set: CONUS + major/synmin class): %d facilities | %d continuously active 2015-2025 (%.1f%%)\n",
            nrow(spine), sum(spine$CONTINUOUSLY_ACTIVE), 100 * mean(spine$CONTINUOUSLY_ACTIVE)))

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# 1. (continuity uniqueness check, ~line 75) Re-reads operating.csv.gz's (PGM_SYS_ID, YEAR) columns a
#    second time purely to assert grain uniqueness -- a small redundant read, kept because
#    stopifnot() needs the check to run against the UNFILTERED file (the `continuity` object above is
#    already filtered to `cand_ids`/CONTINUITY_YEARS, which would only assert uniqueness on a subset).
#    Cheap relative to the rest of this script's reads; not worth a third read to avoid.
# 2. (COORD_NO_COUNTY_MATCH, ~line 55) Derived here rather than read from coordinates.csv.gz, since that
#    dataset doesn't ship this exact flag -- a small duplication of logic (the same derivation would need
#    to happen in any other consumer that wants it). Not promoted upstream since this is the only
#    consumer today.
# =========================================================================================================
