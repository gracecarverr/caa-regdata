#!/usr/bin/env Rscript
# =========================================================================================================
# run_all.R -- rebuild the entire regulatory-data infrastructure from raw, in order.
#   Usage:  Rscript run_all.R                    # full rebuild
#           DOWNLOAD=false Rscript run_all.R     # skip the (slow) download step; reuse data/raw/
#
# The pipeline is intentionally a plain, ordered sequence (no hidden dependency graph):
#   01 download  ->  02 clean (per dataset)  ->  03 document  ->  04 build panels
# Cleaning scripts in scripts/02_clean/ are NUMBER-PREFIXED so they run in dependency order
# (event datasets first, the facilities spine last).
# =========================================================================================================
source(here::here("R/setup.R"))

step <- function(msg) cat(sprintf("\n========== %s ==========\n", msg))
do_download <- tolower(Sys.getenv("DOWNLOAD", "true")) != "false"

if (do_download) { step("01 download"); source(here::here("scripts/01_download.R")) } else
                   step("01 download -- SKIPPED (DOWNLOAD=false)")

step("02 clean")
clean_scripts <- sort(list.files(here::here("scripts/02_clean"), pattern = "^[0-9].*[.]R$", full.names = TRUE))
for (f in clean_scripts) { cat(" -", basename(f), "\n"); source(f) }

step("03 document");     source(here::here("scripts/03_document.R"))
step("04 build panels"); source(here::here("scripts/04_build_panels.R"))
step("done")
