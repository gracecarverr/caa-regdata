# =========================================================================================================
# code/03_datasets/00_parameters.R -- shared window + paths for the eight-dataset build.
#
#   The deliverable is EIGHT datasets, not one wide panel (see code/04_datasets/README.md):
#     0 regulatory  facility x year   ICIS-Air only: event counts + ICIS facility characteristics
#     1 operating   facility x year   wayback status, program-active flags, entry/exit, earliest program year
#     2 hpv_spells  spell             one row per HPV spell, UNcollapsed (ENF tier == HPV)
#       hpv_active  facility x year   R2 collapse of hpv_spells -> HPV-active flag; joins 1:1 to ds 0/1
#     3 penalties   formal action     action-level penalties + multi-facility settlement key
#     4 coordinates facility          FRS lat/lon, county, coordinate-error diagnostics
#     6 pipeline    facility x year   EPA ECHO's CAA Compliance Pipeline: evaluation-to-enforcement chain + FRV
#     7 emissions   facility x year   combined pollutant report (EIS/TRIS/E-GGRT/CAMDBS), real magnitude axis
#
#   Everything joins on PGM_SYS_ID (+ year where the grain is facility x year). All eight are built once
#   over the FULL facility universe, so any sample restriction is a filter the user applies downstream --
#   there are no pre-built sample panels.
# =========================================================================================================

YEARS <- 2005:2025          # analysis window (the cleaned assets keep every dated event; the window is here)
                             # REVIEW(design): this is a SEPARATE literal from 03_panel_building's own
                             # `YEARS <- 2005:2025` (00_spine.R / 03_build_parameters.R) -- same value today,
                             # not shared code, so the two layers can silently drift apart if one is edited

CLEAN    <- here::here("data/processed")   # cleaning-layer output (input to every dataset builder here)
DATASETS <- here::here("data/datasets")    # this layer's output directory

# The six ICIS-Air EVENT assets. Presence of >=1 row across these defines `icis_observed` (see 01_regulatory.R).
EVENT_ASSETS <- c("inspections", "violations", "formal_actions", "informal_actions", "certs", "stacktests")

# ---- naming convention ----------------------------------------------------------------------------------
# Every column in the DATASET layer is UPPER_SNAKE_CASE. The cleaning layer (data/processed) keeps its
#   source-native casing; each builder assembles with readable lowercase names internally, then uppercases
#   ONCE on write via write_dataset() below. This keeps the join keys (PGM_SYS_ID, YEAR) and every derived
#   column on one convention across all eight datasets, so cross-dataset merges line up without per-file fixups.
#   toupper() is idempotent on the already-uppercase ICIS attributes (REGISTRY_ID, STATE, ...).
write_dataset <- function(df, name) {
  dir.create(DATASETS, showWarnings = FALSE, recursive = TRUE)   # ensure data/datasets/ exists
  readr::write_csv(dplyr::rename_with(df, toupper), file.path(DATASETS, paste0(name, ".csv.gz")))
    # rename_with(df, toupper) renames every column name via toupper() before writing; idempotent for names
    # already uppercase (e.g. REGISTRY_ID, STATE), so mixed-case internal columns and pre-uppercase ICIS
    # attribute columns end up on the same convention without any per-file special-casing
}

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# 1. (YEARS, ~line 17) A SEPARATE literal from 03_panel_building's own `YEARS <- 2005:2025` (00_spine.R /
#    03_build_parameters.R) -- same value today, not shared code, so the two layers can silently drift apart
#    if one is edited without the other. Every builder in this layer sources YEARS from here.
# =========================================================================================================
