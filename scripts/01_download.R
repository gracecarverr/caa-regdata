# =========================================================================================================
# scripts/01_download.R -- acquire raw data into data/raw/ (immutable) + record provenance.
#   Skipped when run_all.R is called with DOWNLOAD=false. Thin: calls fetchers in R/download.R.
# =========================================================================================================
source(here::here("R/download.R"))

fetch_icis_air(RAW)          # bulk ICIS-Air tables (idempotent; large)
# TODO (later slices):
#   fetch_frs(RAW)           # FRS coordinates
#   fetch_greenbook(RAW)     # Green Book shapefiles (+ assisted Wayback snapshots for history)
