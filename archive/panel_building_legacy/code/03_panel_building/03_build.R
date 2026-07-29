# =========================================================================================================
# 03_build.R -- driver for the panel-building stage. Builds the facility spine, then the sample facility x
#   year panels.
#
#   Order:
#     00_spine.R  -> data/panels/spine.csv.gz   (one row per ever-active facility + attributes)
#     PANEL_SPECS -> data/panels/<name>.csv.gz   (universe, major_synmin, electric)
#
#   Standalone:  Rscript code/03_panel_building/03_build.R   (assumes data/processed/ is already built)
#   Or sourced by code/RUN_ALL.R.
# =========================================================================================================
library(readr); library(dplyr)

# 1. prerequisite construction --------------------------------------------------------------------------
cat(" - 00_spine.R\n"); source(here::here("code/03_panel_building/00_spine.R"))
  # runs 00_spine.R in this environment (source(), not a subprocess) -- writes data/panels/spine.csv.gz and
  # also leaves its own top-level objects (fac, co, active, YEARS=2005:2025, etc.) in this session, some of
  # which get shadowed below

# 2. the sample panels: one recipe (build_panel) over per-panel filters ----------------------------------
source(here::here("code/03_panel_building/03_build_functions.R"))    # build_panel() and its helpers
source(here::here("code/03_panel_building/03_build_parameters.R"))
  # REVIEW(design): 03_build_parameters.R defines its OWN `YEARS <- 2005:2025`, silently overwriting the
  # `YEARS` already left in this environment by 00_spine.R (same value today, so harmless -- but nothing
  # enforces the two literals staying in sync if one is ever changed without the other; build_panel() in
  # 03_build_functions.R uses whichever `YEARS` is in scope when it's called, i.e. this second one)

spine <- read_csv(here::here("data/panels/spine.csv.gz"),
                  col_types = cols(PGM_SYS_ID = col_character(), .default = col_guess()),
                  show_col_types = FALSE)
                  # re-reads spine.csv.gz from disk (rather than reusing the in-memory `spine` object 00_spine.R
                  # just built) -- round-trips it through CSV text, which is what protects columns like
                  # county_fips/ZIP_CODE from being guessed as numeric: readr's col_guess() specifically avoids
                  # guessing integer/double for strings with a leading zero (verified: county_fips stays
                  # character here even under col_guess default), so this round trip is safe in practice

for (spec in PANEL_SPECS) {                             # one iteration per sample panel (universe, major_synmin, electric)
  facs  <- spec$filter(spine)                            # apply this panel's facility filter to the spine
  panel <- build_panel(facs)                              # the shared facility x year build recipe
  dir.create(here::here("data/panels"), showWarnings = FALSE, recursive = TRUE)
  write_csv(panel, here::here("data/panels", paste0(spec$name, ".csv.gz")))
  cat(sprintf("%s panel: %d rows | %d facilities | %d cols | %d-%d\n",
              spec$name, nrow(panel), n_distinct(panel$PGM_SYS_ID), ncol(panel), min(YEARS), max(YEARS)))
}
