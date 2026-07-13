# =========================================================================================================
# scripts/01_download.R -- acquire raw data into data/raw/ (immutable) + record provenance.
#   Skipped when run_all.R is called with DOWNLOAD=false. Thin: calls fetchers in R/download.R.
# =========================================================================================================
source(here::here("R/download.R"))

# TODO (vertical slice / acquire phase):
#   fetch_icis_air(RAW)    # bulk ICIS-Air tables
#   fetch_frs(RAW)         # FRS coordinates
#   fetch_greenbook(RAW)   # Green Book shapefiles (+ assisted Wayback snapshots for history)
cat("01_download.R -- stub (no sources wired yet). See README > Roadmap.\n")
