# =========================================================================================================
# code/04_datasets/08_emissions.R -- DATASET 7: emissions. Facility x year, built from the combined pollutant
#   report (data/processed/emissions.csv.gz, from EIS/TRIS/E-GGRT/CAMDBS -- see docs/data_dictionary.md).
#   Every line below is commented, matching the standard set for this workflow (07_pipeline.R).
#
#   in : data/processed/emissions.csv.gz, data/processed/facilities.csv.gz
#   out: data/datasets/emissions.csv.gz
#
#   WHAT'S NEW HERE -- ds 0's EMITS_* flags (regulatory.csv.gz) are booleans from ICIS-AIR_POLLUTANTS.csv
#     (undated, "ever permitted to emit"); nothing in this layer carries actual measured emission QUANTITIES.
#     This dataset adds annual pounds for VOC/PM10/PM2.5/NOx/SO2/CO, a broader HAP total, and GHG (metric
#     tons CO2e, kept in its own column/unit) -- a real magnitude axis, not a flag.
#
#   CROSS-PROGRAM SOURCE -- unlike every other dataset in this layer, the raw rows are NOT ICIS-Air-only:
#     PGM_SYS_ACRNM in {EIS (NEI point-source inventory), TRIS (Toxics Release Inventory), E-GGRT (mandatory
#     GHG reporting), CAMDBS (Clean Air Markets)}. Each program has its OWN facility id scheme, so REGISTRY_ID
#     (the FRS cross-program id) is the only usable join key back to this layer's PGM_SYS_ID universe --
#     PGM_SYS_ID from the raw file is deliberately NOT used to join here.
#
#   REGISTRY_ID FAN-OUT (new to this layer, same shape as ds 3's multi-facility settlements, P5) -- 8,632
#     REGISTRY_IDs map to more than one PGM_SYS_ID in facilities.csv.gz (max 150); 2,802 of those actually
#     carry emissions data. A straight join broadcasts one facility's reported emissions onto every co-mapped
#     PGM_SYS_ID identically -- exposed via IS_SHARED_REGISTRY / N_PGM_SYS_ID_SHARING_REGISTRY, not resolved.
#     Do NOT sum emissions across facilities that share a REGISTRY_ID without accounting for this.
#
#   POLLUTANT_NAME DOUBLE-COUNTING TRAP -- PM10/PM2.5 each have a canonical TOTAL string plus several
#     component/speciation variants that are SUBSETS of that total (e.g. "Primary PM10, filterable portion
#     only" is part of "Primary PM10 (filterables and condensibles)"). Every pollutant column below matches
#     the single canonical total string EXACTLY (==), never by substring/regex, so components are never
#     double-counted. VOC/NOx/SO2/CO have exactly one variant each, so exact match costs nothing there either.
#     HAP_LBS (NEI_TYPE == "HAP", 292 distinct pollutant names) was checked for a similar "Total HAP" row --
#     none exists, so summing every HAP-tagged row is safe.
#
#   ZERO-vs-NA -- EMISSIONS_OBSERVED == 1 iff >=1 non-GHG (EIS/TRIS/CAMDBS) row anchors that facility-year
#     (via the REGISTRY_ID broadcast); then every pounds column is a true value (0 if that specific pollutant
#     wasn't reported), NA otherwise. GHG_OBSERVED/GHG_MTCO2E follow the identical rule restricted to E-GGRT
#     rows -- kept independent of EMISSIONS_OBSERVED because GHG reporting is its own regulatory requirement,
#     not a subset of EIS/TRI/CAMD air-toxics reporting.
#
#   COVERAGE IS STRUCTURALLY UNEVEN, not incidental -- EIS (90% of raw rows) only has data in 2008, 2011,
#     2014, 2017, 2020 (its real triennial inventory cycle); TRIS/CAMDBS/E-GGRT report annually but only from
#     2015 on. Raw REPORTING_YEAR spans 2008-2024, narrower than this layer's 2005-2025 window (G1) -- 2005-
#     2007 and 2025 are simply never observed here.
# =========================================================================================================
library(readr)                                            # read_csv / write_csv
library(dplyr)                                            # filter / mutate / group_by / summarise / join
library(tidyr)                                            # expand_grid, for the full facility x year rectangle
source(here::here("code/04_datasets/00_parameters.R"))    # YEARS, CLEAN, DATASETS, write_dataset()

# ---- exact pollutant-name strings for the six ds0-comparable categories (see the double-counting note above)
POLLUTANT_MAP <- c(VOC = "Volatile organic compounds",              # single variant, no ambiguity
                   PM10 = "Primary PM10 (filterables and condensibles)",   # canonical TOTAL, not a component
                   PM25 = "Primary PM2.5 (filterables and condensibles)",  # canonical TOTAL, not a component
                   NOX = "Nitrogen oxides",                          # single variant, no ambiguity
                   SO2 = "Sulfur dioxide",                           # single variant, no ambiguity
                   CO  = "Carbon monoxide")                          # single variant, no ambiguity

# ---- read the cleaned emissions asset, keep only the columns this build needs -----------------------------
e <- read_csv(file.path(CLEAN, "emissions.csv.gz"),                     # data/processed/emissions.csv.gz
              col_select = c(REPORTING_YEAR, REGISTRY_ID, PGM_SYS_ACRNM, POLLUTANT_NAME,
                             ANNUAL_EMISSION, NEI_TYPE),                # program acronym, pollutant, value, HAP flag
              col_types = cols(REPORTING_YEAR = col_integer(),          # year is already a plain integer, no parse
                              ANNUAL_EMISSION = col_double(),           # emission quantity as a real number
                              .default = col_character()),              # everything else stays character
              show_col_types = FALSE)                                   # suppress the column-spec printout

# ---- restrict to the layer's analysis window (G1); real data is 2008-2024, entirely inside 2005-2025 -------
e <- e |> filter(REPORTING_YEAR %in% YEARS)                 # matches every other dataset's window convention

# ---- split into pounds-based rows (everything but GHG reporting) and GHG rows, per the independent-flag rule
pounds <- e |> filter(PGM_SYS_ACRNM != "E-GGRT")             # EIS/TRIS/CAMDBS: all reported in Pounds
ghg    <- e |> filter(PGM_SYS_ACRNM == "E-GGRT")             # E-GGRT: reported in MTCO2e, a different unit

# ---- aggregate the pounds-based rows to (REGISTRY_ID, year): one row per group that had >=1 pounds record --
pounds_agg <- pounds |> group_by(REGISTRY_ID, REPORTING_YEAR) |> summarise(  # group by facility-id and year
  voc_lbs  = sum(ANNUAL_EMISSION[POLLUTANT_NAME == POLLUTANT_MAP[["VOC"]]],  na.rm = TRUE), # exact-match sum
  pm10_lbs = sum(ANNUAL_EMISSION[POLLUTANT_NAME == POLLUTANT_MAP[["PM10"]]], na.rm = TRUE), # canonical total only
  pm25_lbs = sum(ANNUAL_EMISSION[POLLUTANT_NAME == POLLUTANT_MAP[["PM25"]]], na.rm = TRUE), # canonical total only
  nox_lbs  = sum(ANNUAL_EMISSION[POLLUTANT_NAME == POLLUTANT_MAP[["NOX"]]],  na.rm = TRUE), # exact-match sum
  so2_lbs  = sum(ANNUAL_EMISSION[POLLUTANT_NAME == POLLUTANT_MAP[["SO2"]]],  na.rm = TRUE), # exact-match sum
  co_lbs   = sum(ANNUAL_EMISSION[POLLUTANT_NAME == POLLUTANT_MAP[["CO"]]],   na.rm = TRUE), # exact-match sum
  hap_lbs  = sum(ANNUAL_EMISSION[NEI_TYPE == "HAP"], na.rm = TRUE),          # every HAP-tagged row, no aggregate to avoid
  emissions_observed = 1L,                                                  # this group exists -> >=1 real row
  .groups = "drop")                                                          # drop the grouping structure after

# ---- aggregate the GHG rows to (REGISTRY_ID, year): one row per group that had >=1 E-GGRT record -----------
ghg_agg <- ghg |> group_by(REGISTRY_ID, REPORTING_YEAR) |> summarise(         # group by facility-id and year
  ghg_mtco2e  = sum(ANNUAL_EMISSION, na.rm = TRUE),                          # metric tons CO2e, its own unit
  ghg_observed = 1L,                                                         # this group exists -> >=1 GHG row
  .groups = "drop")                                                          # drop the grouping structure after

# ---- combine into one (REGISTRY_ID, year) table; either side can be missing for a given group --------------
registry_year <- full_join(pounds_agg, ghg_agg, by = c("REGISTRY_ID", "REPORTING_YEAR")) |>
  rename(year = REPORTING_YEAR)                                              # match the layer's join-key name

# ---- facility crosswalk: every PGM_SYS_ID in the ICIS universe, with its REGISTRY_ID (blank if no FRS match)
crosswalk <- read_csv(file.path(CLEAN, "facilities.csv.gz"),                  # data/processed/facilities.csv.gz
                     col_types = cols_only(PGM_SYS_ID = col_character(),      # facility id (this layer's join key)
                                          REGISTRY_ID = col_character()),     # FRS cross-program id (G4 convention)
                     show_col_types = FALSE)                                  # suppress the column-spec printout
ids <- crosswalk$PGM_SYS_ID                                                   # the 279,211-facility id vector

# ---- REGISTRY_ID fan-out diagnostics: how many PGM_SYS_IDs share each non-blank REGISTRY_ID -----------------
reg_counts <- crosswalk |> filter(REGISTRY_ID != "") |>                       # only facilities with an FRS id
  count(REGISTRY_ID, name = "n_pgm_sys_id_sharing_registry")                  # facility-count per REGISTRY_ID
crosswalk <- crosswalk |> left_join(reg_counts, by = "REGISTRY_ID") |>        # attach the fan-out count
  mutate(is_shared_registry = as.integer(n_pgm_sys_id_sharing_registry > 1))  # 1 iff >1 facility shares it

# ---- broadcast (REGISTRY_ID, year) emissions data onto every PGM_SYS_ID sharing that REGISTRY_ID ------------
broadcast <- crosswalk |> filter(REGISTRY_ID != "") |>                        # blank REGISTRY_ID can't match anything
  inner_join(registry_year, by = "REGISTRY_ID", relationship = "many-to-many") |>  # deliberate fan-out (PL-style
                                                                               # broadcast), not an accidental cartesian join
  select(PGM_SYS_ID, year,                                                   # keep the join keys
        voc_lbs, pm10_lbs, pm25_lbs, nox_lbs, so2_lbs, co_lbs, hap_lbs,       # pounds-based measures
        emissions_observed, ghg_mtco2e, ghg_observed)                        # GHG measures + both observed flags

# ---- build the full facility x year rectangle and apply the zero-vs-NA discipline ---------------------------
em <- expand_grid(PGM_SYS_ID = ids, year = YEARS) |>            # every facility crossed with every window year
  left_join(broadcast, by = c("PGM_SYS_ID", "year")) |>         # attach broadcast data; no match -> NA everywhere
  mutate(emissions_observed = coalesce(emissions_observed, 0L), # NA (no pounds data) -> 0, a real "not observed"
        ghg_observed        = coalesce(ghg_observed, 0L)) |>    # NA (no GHG data) -> 0, independently of the above
  left_join(crosswalk |> select(PGM_SYS_ID, REGISTRY_ID, n_pgm_sys_id_sharing_registry, is_shared_registry),
           by = "PGM_SYS_ID") |>                                # attach REGISTRY_ID + fan-out flags (facility-level)
  relocate(REGISTRY_ID, .after = PGM_SYS_ID) |>                 # column order: PGM_SYS_ID, REGISTRY_ID, year, ...
  relocate(emissions_observed, ghg_observed, .after = year) |>  # observability flags right after the join keys
  arrange(PGM_SYS_ID, year)                                     # stable row order for reproducible diffs

# ---- invariants -----------------------------------------------------------------------------------------
stopifnot(
  "grain broken: PGM_SYS_ID x year is not unique"      =                    # the panel key must be unique
    !anyDuplicated(em[c("PGM_SYS_ID", "year")]),
  "rectangle incomplete: rows != facilities x years"    =                    # must be a full, dense rectangle
    nrow(em) == length(ids) * length(YEARS),
  "observability rule violated: EMISSIONS_OBSERVED with NA VOC_LBS"        = # observed -> pounds cols never NA
    !any(em$emissions_observed == 1 & is.na(em$voc_lbs)),
  "observability rule violated: unobserved row with non-NA VOC_LBS"        = # unobserved -> pounds cols always NA
    !any(em$emissions_observed == 0 & !is.na(em$voc_lbs)),
  "GHG observability rule violated: GHG_OBSERVED with NA GHG_MTCO2E"       = # same rule, independently for GHG
    !any(em$ghg_observed == 1 & is.na(em$ghg_mtco2e)),
  "GHG observability rule violated: unobserved row with non-NA GHG_MTCO2E" =
    !any(em$ghg_observed == 0 & !is.na(em$ghg_mtco2e)),
  "IS_SHARED_REGISTRY count mismatch vs. profiled fan-out (8,632 REGISTRY_IDs)" = # sanity check on the fan-out
    n_distinct(crosswalk$REGISTRY_ID[crosswalk$is_shared_registry == 1 & !is.na(crosswalk$is_shared_registry)]) == 8632)

# ---- write and summarize ------------------------------------------------------------------------------------
write_dataset(em, "emissions")                            # uppercases all columns on write (see 00_parameters.R)
cat(sprintf(                                               # one-line build summary, printed to the console
  "emissions: %s rows | %d cols | %s facilities | %s observed facility-years (%.2f%%) | %s GHG-observed facility-years\n",
  format(nrow(em), big.mark = ","), ncol(em), format(length(ids), big.mark = ","),
  format(sum(em$emissions_observed), big.mark = ","), 100 * mean(em$emissions_observed),
  format(sum(em$ghg_observed), big.mark = ",")))
