#!/usr/bin/env Rscript
# =========================================================================================================
# run_all.R -- rebuild the entire regulatory-data infrastructure from raw, in order.
#   Usage:  Rscript run_all.R                    # full rebuild
#           DOWNLOAD=false Rscript run_all.R     # skip the (slow) download step; reuse data/raw/
#
# The pipeline is a plain, ordered sequence of self-contained scripts (no shared R/ layer, no config):
#   01 download            -> raw sources into data/raw/ (immutable)
#   02 clean (per source)  -> one bare-bones clean asset per raw table in data/clean/
#   03 build site          -> docs/index.html summary tables
#   04 panels              -> facility spine + attainment treatment, then the sample facility x year panels
# Scripts in scripts/02_clean/ and scripts/04_panels/ are NUMBER-PREFIXED so they run in dependency order.
# =========================================================================================================
step <- function(msg) cat(sprintf("\n========== %s ==========\n", msg))
do_download <- tolower(Sys.getenv("DOWNLOAD", "true")) != "false"

if (do_download) { step("01 download"); source(here::here("scripts/01_download.R")) } else
                   step("01 download -- SKIPPED (DOWNLOAD=false)")

step("02 clean")
for (f in sort(list.files(here::here("scripts/02_clean"), pattern = "^[0-9].*[.]R$", full.names = TRUE))) {
  cat(" -", basename(f), "\n"); source(f)
}

step("03 build site"); source(here::here("scripts/03_build_site.R"))

step("04 panels")
for (f in sort(list.files(here::here("scripts/04_panels"), pattern = "[.]R$", full.names = TRUE))) {
  cat(" -", basename(f), "\n"); source(f)
}
step("done")
