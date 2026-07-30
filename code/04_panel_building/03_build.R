# =========================================================================================================
# code/04_panel_building/03_build.R -- driver for the panel-building stage. Builds the shared candidate
#   facility spine, then the two panels.
#
#   Order:
#     00_spine.R  -> in-memory `spine` (CONUS + Major/Synthetic-Minor class, eligibility precomputed)
#     PANEL_SPECS -> data/panels/<name>.csv.gz (major_synmin_2015_2025, electric_2015_2025)
#
#   Standalone: Rscript code/04_panel_building/03_build.R  (assumes data/datasets/ is already built --
#   see code/RUN_ALL.R's stage order, datasets now build BEFORE panels).
#   Or sourced by code/RUN_ALL.R.
#
#   This is a from-scratch rewrite, NOT the old code/03_panel_building/03_build.R renamed -- see
#   archive/panel_building_legacy/README.md for the original.
# =========================================================================================================
library(readr); library(dplyr)

# 1. prerequisite construction ----------------------------------------------------------------------------
cat(" - 00_spine.R\n"); source(here::here("code/04_panel_building/00_spine.R"))
  # leaves `spine` (and CONUS/MAJOR_SYNMIN_CLASSES/SCREEN_YEARS) in this session

# 2. the two panels: one recipe (build_panel) over per-panel filters --------------------------------------
source(here::here("code/04_panel_building/03_build_functions.R"))     # build_panel() and its helpers
source(here::here("code/04_panel_building/03_build_parameters.R"))    # YEARS (2015:2025), PANEL_SPECS
  # REVIEW(design): 03_build_parameters.R defines its own `YEARS <- 2015:2025`, distinct from the repo-wide
  # `YEARS <- 2005:2025` (00_setup.R) and from 00_spine.R's `SCREEN_YEARS` (which happens to be the
  # same 2015:2025 span today) -- three separately-defined literals that currently agree but nothing
  # enforces staying in sync if one is ever changed without the others. Same class of drift risk already
  # documented for YEARS/BEGIN_YEAR_MAX/DZ_MAX elsewhere in this repo.

for (spec in PANEL_SPECS) {
  facs  <- spec$filter(spine)                          # apply this panel's facility filter to the spine
  panel <- build_panel(facs, YEARS)                     # the shared facility x year build recipe
  dir.create(here::here("data/panels"), showWarnings = FALSE, recursive = TRUE)
  write_csv(panel, here::here("data/panels", paste0(spec$name, ".csv.gz")))
  cat(sprintf("%s panel: %d rows | %d facilities | %d cols | %d-%d\n",
              spec$name, nrow(panel), n_distinct(panel$PGM_SYS_ID), ncol(panel), min(YEARS), max(YEARS)))
}

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# 1. (YEARS, ~line 20) Three separately-defined 2015:2025 literals (this file's YEARS, 00_spine.R's
#    SCREEN_YEARS, and the fact both happen to match) -- see the REVIEW(design) comment above. Not
#    unified into one shared constant because 00_spine.R and 03_build_parameters.R are sourced independently
#    and don't currently share a params-only file the way the datasets layer's 00_parameters.R does.
# =========================================================================================================
