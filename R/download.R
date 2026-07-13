# =========================================================================================================
# R/download.R -- reusable acquisition helpers (used by scripts/01_download.R).
#   Each fetcher pulls one raw source into data/raw/ and appends a provenance row to MANIFEST.csv
#   (source, file, url, downloaded_at, md5). Raw files are IMMUTABLE once written.
# =========================================================================================================

# Fetch the ICIS-Air bulk tables from EPA ECHO into data/raw/ICIS-AIR_downloads/.
#   Idempotent: if the CSVs are already present it does nothing (raw is immutable). Records provenance
#   for each extracted file. The download is large; run once, then use DOWNLOAD=false for rebuilds.
fetch_icis_air <- function(dest = RAW, url = CONFIG$sources$icis_air$url) {
  out_dir <- file.path(dest, "ICIS-AIR_downloads")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  if (length(list.files(out_dir, pattern = "[.]csv$"))) {
    message("  ICIS-Air already present in ", out_dir, " -- skipping download."); return(invisible())
  }
  zip <- file.path(dest, "ICIS-AIR_downloads.zip")
  message("  downloading ", url)
  utils::download.file(url, zip, mode = "wb", quiet = TRUE)
  utils::unzip(zip, exdir = out_dir); unlink(zip)
  for (f in list.files(out_dir, full.names = TRUE)) record_provenance("icis_air", f, url)
  invisible()
}

# TODO (later slices): fetch_frs(dest = RAW) ; fetch_greenbook(dest = RAW, assisted Wayback snapshots)

# Append a provenance record. Call after every successful download.
record_provenance <- function(source, file, url) {
  manifest <- file.path(RAW, "MANIFEST.csv")
  row <- data.frame(source = source, file = basename(file), url = url,
                    downloaded_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                    md5 = if (file.exists(file)) unname(tools::md5sum(file)) else NA_character_)
  readr::write_csv(row, manifest, append = file.exists(manifest))
  invisible(row)
}
