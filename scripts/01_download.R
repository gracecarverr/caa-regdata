# =========================================================================================================
# scripts/01_download.R -- acquire raw data into data/raw/ (immutable) + record provenance.
#   Skipped when run_all.R is called with DOWNLOAD=false. Standalone: no shared helpers, no config.
#
#   Fetches the ICIS-Air bulk tables from EPA ECHO. Idempotent: if the CSVs are already present it does
#   nothing (raw is immutable). Records a provenance row per extracted file in data/raw/MANIFEST.csv
#   (source, file, url, downloaded_at, md5).
# =========================================================================================================
library(readr)

RAW      <- here::here("data/raw")
ICIS_URL <- "https://echo.epa.gov/files/echodownloads/ICIS-AIR_downloads.zip"
dir.create(RAW, showWarnings = FALSE, recursive = TRUE)

# append a provenance record (call after every successful download)
record_provenance <- function(source, file, url) {
  manifest <- file.path(RAW, "MANIFEST.csv")
  row <- data.frame(source = source, file = basename(file), url = url,
                    downloaded_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                    md5 = if (file.exists(file)) unname(tools::md5sum(file)) else NA_character_)
  write_csv(row, manifest, append = file.exists(manifest))
  invisible(row)
}

# fetch the ICIS-Air bulk tables into data/raw/ICIS-AIR_downloads/
out_dir <- file.path(RAW, "ICIS-AIR_downloads")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
if (length(list.files(out_dir, pattern = "[.]csv$"))) {
  message("  ICIS-Air already present in ", out_dir, " -- skipping download.")
} else {
  zip <- file.path(RAW, "ICIS-AIR_downloads.zip")
  message("  downloading ", ICIS_URL)
  utils::download.file(ICIS_URL, zip, mode = "wb", quiet = TRUE)
  utils::unzip(zip, exdir = out_dir); unlink(zip)
  for (f in list.files(out_dir, full.names = TRUE)) record_provenance("icis_air", f, ICIS_URL)
}

# TODO (later slices):
#   FRS coordinates (data/raw/frs/), Green Book shapefiles + Wayback snapshots (data/raw/greenbook/),
#   AFS historical tables, county boundaries -- currently staged manually into data/raw/.
