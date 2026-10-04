#!/usr/bin/env Rscript
# =========================================================================================================
# RUN_ALL.R -- rebuild the entire regulatory-data infrastructure from raw, in order.
#
#   Usage:
#     Rscript code/RUN_ALL.R                     # full rebuild
#     DOWNLOAD=false Rscript code/RUN_ALL.R      # skip the (slow) download step; reuse data/raw/
#     SKIP_SITE=true  Rscript code/RUN_ALL.R     # skip regenerating docs/index.html
#
#   Stages (each stage's folder has a README with the details):
#     00 setup          code/00_setup/00_setup.R              -- check packages, options, record session
#     01 download       code/01_data_download/01_download.R  -> data/raw/            (immutable; skippable)
#     02 clean          code/02_cleaning/02_clean.R           -> data/processed/      (one asset per source)
#     03 datasets       code/03_datasets/0{1..8}_*.R           -> data/datasets/       (eight full-universe
#                        deliverables -- the project's main product; see code/03_datasets/README.md)
#     04 panels         code/04_panel_building/03_build.R     -> data/panels/         (2 continuous panels,
#                        built FROM the datasets above -- see code/04_panel_building/README.md)
#     (docs) build site code/diagnostics/build_site.R         -> docs/raw_data.html   (generated from data/raw)
#                        code/diagnostics/build_home.R        -> docs/index.html      (landing page)
#                        code/diagnostics/build_briefs_page.R -> docs/briefs.html     (twelve institutional
#                        briefs -- Clean Air Act structure + the data systems/identifiers; no data dependency)
#                        code/diagnostics/build_databases_page.R -> docs/databases.html (database overviews)
#                        code/diagnostics/build_panels_page.R -> docs/panels.html     (panel construction +
#                        summary stats; requires output/panel_profile/*.csv to already exist --
#                        Rscript code/diagnostics/18_panel_profile.R first, hand-run like every profile script)
#                        code/diagnostics/build_dictionary.R  -> docs/dictionary.html (renders the two
#                        hand-maintained docs/data_dictionary*.md files, cross-linked to raw_data.html/
#                        databases.html/panels.html -- reads only those two .md files, no data dependency)
#
#   Stage order was inverted 2026-07-28 -- datasets now build BEFORE panels (panel-building consumes
#   data/datasets/ instead of re-deriving facility-year aggregations from data/processed/ itself). The
#   folder numbers were swapped to match (03_panel_building -> archived; 04_datasets -> 03_datasets;
#   the new panel-building pipeline is 04_panel_building). See archive/panel_building_legacy/README.md
#   for what the old (data/processed/-based) panel pipeline looked like and why it was archived rather
#   than converted in place.
#
#   The panel-layer diagnostics that used to run as part of "docs: build site" (06_panel_profile.R,
#   the old build_panels_page.R) were archived along with the old panel-building pipeline -- they
#   profiled a panel structure (universe/major_synmin/electric) that no longer exists. 18_panel_profile.R
#   and a rewritten build_panels_page.R now profile/publish the new two-panel structure from scratch;
#   docs/panels.html is regenerated again as of that rewrite -- see code/diagnostics/README.md.
#   The pipeline has no stochastic step, so no seed is required (see 00_setup).
# =========================================================================================================
step        <- function(msg) cat(sprintf("\n========== %s ==========\n", msg))
do_download <- tolower(Sys.getenv("DOWNLOAD", "true")) != "false"
skip_site   <- tolower(Sys.getenv("SKIP_SITE", "false")) == "true"

step("00 setup");                source(here::here("code/00_setup/00_setup.R"))

if (do_download) { step("01 download"); source(here::here("code/01_data_download/01_download.R")) } else
                   step("01 download -- SKIPPED (DOWNLOAD=false)")

step("02 clean");                source(here::here("code/02_cleaning/02_clean.R"))

step("03 datasets")
# Run order is NOT the same as the 01..08 numeric file prefixes (those are stable "dataset 0..7" semantic
# IDs used throughout the briefs, not a build sequence -- see code/03_datasets/00_parameters.R). As of
# 2026-07-28, 02_operating.R reads BOTH 01_regulatory.R's output (for the ACTIVE tier's ICIS_OBSERVED
# signal) AND 08_emissions.R's output (for the ACTIVE_BROAD tier's EMISSIONS_OBSERVED/GHG_OBSERVED
# signal) -- see 02_operating.R's own header comment. So emissions must build before operating; every other
# file keeps its old relative order. 08_emissions.R itself only reads data/processed/, so moving it earlier
# is safe (confirmed by inspection -- it has no dependency on any other dataset in this layer).
DATASET_FILES <- c("01_regulatory.R", "08_emissions.R", "02_operating.R", "03_hpv_spells.R",
                   "04_hpv_active.R", "05_penalties.R", "06_coordinates.R", "07_pipeline.R")
for (f in file.path("code/03_datasets", DATASET_FILES)) {
  cat(sprintf(" - %s\n", f)); source(here::here(f))
}

step("04 panels");               source(here::here("code/04_panel_building/03_build.R"))

if (!skip_site) {
  step("docs: build site")
  source(here::here("code/diagnostics/build_site.R"))
  source(here::here("code/diagnostics/build_home.R"))
  source(here::here("code/diagnostics/build_briefs_page.R"))
  source(here::here("code/diagnostics/build_databases_page.R"))
  source(here::here("code/diagnostics/build_panels_page.R"))
  source(here::here("code/diagnostics/build_dictionary.R"))
} else step("docs: build site -- SKIPPED (SKIP_SITE=true)")

step("done")
