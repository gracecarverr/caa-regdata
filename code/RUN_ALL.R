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
#     03 panels         code/03_panel_building/03_build.R     -> data/panels/         (spine, sample panels)
#     04 datasets       code/04_datasets/0{1..8}_*.R           -> data/datasets/       (eight full-universe
#                        deliverables -- the project's main product; see code/04_datasets/README.md)
#     (docs) build site code/diagnostics/build_site.R         -> docs/raw_data.html   (generated from data/raw)
#                        code/diagnostics/build_home.R        -> docs/index.html      (institutional overview)
#                        code/diagnostics/build_databases_page.R -> docs/databases.html (database overviews)
#                        code/diagnostics/06_panel_profile.R  -> output/panel_profile/*.csv (panel tabulations)
#                        code/diagnostics/build_panels_page.R -> docs/panels.html     (panel construction + stats)
#
#   Other diagnostics (05_panel_summaries.R, 07_majsyn_operating_profile.R, previews, one-offs) are NOT run
#   here -- run them by hand from code/diagnostics/ (see its README).
#   The pipeline has no stochastic step, so no seed is required (see 00_setup).
# =========================================================================================================
step        <- function(msg) cat(sprintf("\n========== %s ==========\n", msg))
do_download <- tolower(Sys.getenv("DOWNLOAD", "true")) != "false"
skip_site   <- tolower(Sys.getenv("SKIP_SITE", "false")) == "true"

step("00 setup");                source(here::here("code/00_setup/00_setup.R"))

if (do_download) { step("01 download"); source(here::here("code/01_data_download/01_download.R")) } else
                   step("01 download -- SKIPPED (DOWNLOAD=false)")

step("02 clean");                source(here::here("code/02_cleaning/02_clean.R"))

step("03 panels");               source(here::here("code/03_panel_building/03_build.R"))

step("04 datasets")
for (f in sprintf("code/04_datasets/%02d_%s.R", 1:8,
                   c("regulatory", "operating", "hpv_spells", "hpv_active",
                     "penalties", "coordinates", "pipeline", "emissions"))) {
  cat(sprintf(" - %s\n", f)); source(here::here(f))
}

if (!skip_site) {
  step("docs: build site")
  source(here::here("code/diagnostics/build_site.R"))
  source(here::here("code/diagnostics/build_home.R"))
  source(here::here("code/diagnostics/build_databases_page.R"))
  source(here::here("code/diagnostics/06_panel_profile.R"))
  source(here::here("code/diagnostics/build_panels_page.R"))
} else step("docs: build site -- SKIPPED (SKIP_SITE=true)")

step("done")
