# =========================================================================================================
# R/download.R -- reusable acquisition helpers (used by scripts/01_download.R).
#   Each fetcher pulls one raw source into data/raw/ and appends a provenance row to MANIFEST.csv
#   (source, file, url, downloaded_at, sha256). Raw files are IMMUTABLE once written.
# =========================================================================================================

# TODO (vertical slice): implement fetchers.
#   fetch_icis_air(dest = RAW)   -> ICIS-Air bulk tables
#   fetch_frs(dest = RAW)        -> FRS facilities / coordinates
#   fetch_greenbook(dest = RAW)  -> Green Book shapefiles (+ assisted Wayback snapshots)

# Append a provenance record. Call after every successful download.
record_provenance <- function(source, file, url) {
  manifest <- file.path(RAW, "MANIFEST.csv")
  row <- data.frame(source = source, file = basename(file), url = url,
                    downloaded_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                    sha256 = if (file.exists(file)) tools::sha256sum(file) else NA_character_)
  readr::write_csv(row, manifest, append = file.exists(manifest))
  invisible(row)
}
