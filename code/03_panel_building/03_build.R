# =========================================================================================================
# 03_build.R -- driver for the panel-building stage. Builds the facility spine and the attainment treatment
#   asset, then the sample facility x year panels.
#
#   Order:
#     00_spine.R       -> data/panels/spine.csv.gz        (one row per ever-active facility + attributes)
#     01_attainment.R  -> data/panels/attainment.csv.gz   (PM2.5 2012 nonattainment, facility x year)
#     PANEL_SPECS      -> data/panels/<name>.csv.gz        (universe, major_synmin, electric)
#
#   Standalone:  Rscript code/03_panel_building/03_build.R   (assumes data/processed/ is already built)
#   Or sourced by code/RUN_ALL.R.
# =========================================================================================================
library(readr); library(dplyr)

# 1. prerequisite constructions (each is a self-contained script) ---------------------------------------
cat(" - 00_spine.R\n");      source(here::here("code/03_panel_building/00_spine.R"))
cat(" - 01_attainment.R\n"); source(here::here("code/03_panel_building/01_attainment.R"))

# 2. the sample panels: one recipe (build_panel) over per-panel filters ----------------------------------
source(here::here("code/03_panel_building/03_build_functions.R"))
source(here::here("code/03_panel_building/03_build_parameters.R"))

spine <- read_csv(here::here("data/panels/spine.csv.gz"),
                  col_types = cols(PGM_SYS_ID = col_character(), .default = col_guess()),
                  show_col_types = FALSE)

for (spec in PANEL_SPECS) {
  facs  <- spec$filter(spine)
  panel <- build_panel(facs, treatment = spec$treatment)
  dir.create(here::here("data/panels"), showWarnings = FALSE, recursive = TRUE)
  write_csv(panel, here::here("data/panels", paste0(spec$name, ".csv.gz")))
  cat(sprintf("%s panel: %d rows | %d facilities | %d cols | %d-%d\n",
              spec$name, nrow(panel), n_distinct(panel$PGM_SYS_ID), ncol(panel), min(YEARS), max(YEARS)))
}
