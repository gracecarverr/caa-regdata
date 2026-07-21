# =========================================================================================================
# code/04_datasets/00_parameters.R -- shared window + paths for the six-dataset build.
#
#   The deliverable is SIX datasets, not one wide panel (see code/04_datasets/README.md):
#     0 regulatory  facility x year   ICIS-Air only: event counts + ICIS facility characteristics
#     1 operating   facility x year   wayback status, program-active flags, entry/exit, earliest program year
#     2 hpv_spells  spell             one row per HPV spell, UNcollapsed (ENF tier == HPV)
#       hpv_active  facility x year   R2 collapse of hpv_spells -> HPV-active flag; joins 1:1 to ds 0/1
#     3 penalties   formal action     action-level penalties + multi-facility settlement key
#     4 coordinates facility          FRS lat/lon, county, coordinate-error diagnostics
#     5 attainment  facility x year   PM2.5 (2012) nonattainment
#
#   Everything joins on PGM_SYS_ID (+ year where the grain is facility x year). Datasets 1-5 are built once
#   over the FULL facility universe, so any sample restriction is a filter the user applies downstream --
#   there are no pre-built sample panels.
# =========================================================================================================

YEARS <- 2005:2025          # analysis window (the cleaned assets keep every dated event; the window is here)

CLEAN    <- here::here("data/processed")
DATASETS <- here::here("data/datasets")

# The six ICIS-Air EVENT assets. Presence of >=1 row across these defines `icis_observed` (see 01_regulatory.R).
EVENT_ASSETS <- c("inspections", "violations", "formal_actions", "informal_actions", "certs", "stacktests")

# ---- naming convention ----------------------------------------------------------------------------------
# Every column in the DATASET layer is UPPER_SNAKE_CASE. The cleaning layer (data/processed) keeps its
#   source-native casing; each builder assembles with readable lowercase names internally, then uppercases
#   ONCE on write via write_dataset() below. This keeps the join keys (PGM_SYS_ID, YEAR) and every derived
#   column on one convention across all six datasets, so cross-dataset merges line up without per-file fixups.
#   toupper() is idempotent on the already-uppercase ICIS attributes (REGISTRY_ID, STATE, ...).
write_dataset <- function(df, name) {
  dir.create(DATASETS, showWarnings = FALSE, recursive = TRUE)
  readr::write_csv(dplyr::rename_with(df, toupper), file.path(DATASETS, paste0(name, ".csv.gz")))
}
