# =========================================================================================================
# code/01_data_download/01_download.R -- acquire raw data into data/raw/ (immutable) + record provenance.
#   Skipped when code/RUN_ALL.R is called with DOWNLOAD=false. Standalone: no shared helpers, no config.
#
#   Fetches ICIS-Air, AFS, combined emissions (all from the same EPA ECHO bulk directory), US county
#   boundaries, and the Green Book PM2.5 (2012) nonattainment-area polygons. Idempotent throughout: if a
#   source's files are already present it does nothing (raw is immutable). Records a provenance row per
#   extracted file in data/raw/MANIFEST.csv (source, file, url, downloaded_at, md5).
#
#   NOT automated here (stay manually staged; see this stage's README):
#   - data/raw/frs/FRS_FACILITIES.csv -- a direct URL exists (ordsext.epa.gov/FLA/www3/state_files/
#     national_combined.zip, ~1.26 GB) but that EPA endpoint proved unreliable across 4 real attempts
#     (truncated connections at various points, never a clean complete transfer). Rather than ship an
#     automation path that regularly fails, this stays manually staged.
#   - data/raw/ICIS_AIR_WAYBACK/ICIS-AIR_downloads_<year>/ (11 years, 2015-2025) -- an Internet Archive
#     Wayback Machine mechanism was built and verified for SOME years (2015, 2017, 2019, 2020, 2025 matched
#     the existing staged files byte-for-byte) but NOT all: 2016 did not match even after correcting the
#     capture-selection rule, and 2018 has ZERO captures of this URL in the Archive at any status code -- the
#     staged 2018 data did not come from this mechanism. Given the reliability gap and no confirmed selection
#     rule that works for every year, this stays manually staged rather than risk silently reproducing the
#     wrong archived snapshot for a subset of years.
#   - data/raw/greenbook/pm25_2012_status/<year>.dbf (11 yearly Green Book STATUS snapshots, distinct from
#     the NAA boundary polygons below) -- no automatable source was found at all (a Wayback Machine query on
#     the obvious URL returned zero captures).
# =========================================================================================================
library(readr)

RAW <- here::here("data/raw")
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

# fetch one zip and extract it, retrying transient truncated/dropped connections (seen in practice on some
# EPA endpoints for large single-file transfers); verifies the download against the server's own
# Content-Length before trusting it, rather than accepting whatever curl/download.file happened to receive.
# Shells out to curl directly (not utils::download.file) so -C - can RESUME a partial file across attempts --
#   some EPA endpoints (observed on the FRS national_combined.zip) drop the connection mid-transfer on a
#   large single file; restarting from zero each retry (what download.file(method="libcurl") would do, since
#   its `extra` argument is silently ignored under libcurl) wastes bandwidth against a server that reliably
#   fails at a similar point. Verifies the final size against Content-Length rather than trusting curl's exit
#   status alone (a truncated transfer has been observed to still report HTTP 200).
fetch_zip <- function(url, dest_zip, min_bytes = 1e5) {
  hdrs <- curlGetHeaders(url)
  expected <- suppressWarnings(as.numeric(sub(".*content-length:\\s*(\\d+).*", "\\1",
    tolower(paste(names(hdrs), hdrs, sep = ": ", collapse = " ")))))
  for (attempt in 1:8) {
    system2("curl", c("-L", "-C", "-", "--retry", "3", "--retry-delay", "5", "--max-time", "300",
                      "-o", shQuote(dest_zip), shQuote(url)), stdout = FALSE, stderr = FALSE)
    got <- file.size(dest_zip)
    if (!is.na(got) && got >= min_bytes && (is.na(expected) || got >= expected * 0.99)) return(invisible(TRUE))
    message("    attempt ", attempt, ": got ", got, " of ", expected, " bytes -- resuming")
    Sys.sleep(3)
  }
  stop("fetch_zip: could not get a complete download of ", url, " after 8 attempts")
}
curlGetHeaders <- function(url) tryCatch(curlGetHeaders_impl(url), error = function(e) character())
curlGetHeaders_impl <- function(url) {
  h <- system2("curl", c("-sI", "--max-time", "20", shQuote(url)), stdout = TRUE)
  vals <- sub("^[^:]+:\\s*", "", h); names(vals) <- sub(":.*$", "", h); vals
}

# ---- ICIS-Air (current bulk download) ---------------------------------------------------------------
ICIS_URL <- "https://echo.epa.gov/files/echodownloads/ICIS-AIR_downloads.zip"
out_dir <- file.path(RAW, "ICIS-AIR_downloads")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
if (length(list.files(out_dir, pattern = "[.]csv$"))) {
  message("  ICIS-Air already present in ", out_dir, " -- skipping download.")
} else {
  zip <- file.path(RAW, "ICIS-AIR_downloads.zip")
  message("  downloading ", ICIS_URL)
  fetch_zip(ICIS_URL, zip)
  utils::unzip(zip, exdir = out_dir); unlink(zip)
  for (f in list.files(out_dir, full.names = TRUE)) record_provenance("icis_air", f, ICIS_URL)
}

# ---- AFS (legacy Air Facility System) -- same ECHO bulk directory as ICIS-Air -------------------------
AFS_URL <- "https://echo.epa.gov/files/echodownloads/afs_downloads.zip"
afs_dir <- file.path(RAW, "afs_downloads")
dir.create(afs_dir, showWarnings = FALSE, recursive = TRUE)
if (length(list.files(afs_dir, pattern = "[.]csv$"))) {
  message("  AFS already present in ", afs_dir, " -- skipping download.")
} else {
  zip <- file.path(RAW, "afs_downloads.zip")
  message("  downloading ", AFS_URL)
  fetch_zip(AFS_URL, zip)
  utils::unzip(zip, exdir = afs_dir); unlink(zip)
  for (f in list.files(afs_dir, full.names = TRUE)) record_provenance("afs", f, AFS_URL)
}

# ---- combined emissions report -- same ECHO bulk directory --------------------------------------------
EMISSIONS_URL <- "https://echo.epa.gov/files/echodownloads/POLL_RPT_COMBINED_EMISSIONS.zip"
emissions_csv <- file.path(RAW, "POLL_RPT_COMBINED_EMISSIONS.csv")
if (file.exists(emissions_csv)) {
  message("  combined emissions already present -- skipping download.")
} else {
  zip <- file.path(RAW, "POLL_RPT_COMBINED_EMISSIONS.zip")
  message("  downloading ", EMISSIONS_URL)
  fetch_zip(EMISSIONS_URL, zip)
  utils::unzip(zip, exdir = RAW); unlink(zip)
  record_provenance("emissions", emissions_csv, EMISSIONS_URL)
}

# ---- US county cartographic boundaries (Census, 2022 vintage) -----------------------------------------
COUNTIES_URL <- "https://www2.census.gov/geo/tiger/GENZ2022/shp/cb_2022_us_county_500k.zip"
counties_dir <- file.path(RAW, "us_counties")
dir.create(counties_dir, showWarnings = FALSE, recursive = TRUE)
if (file.exists(file.path(counties_dir, "us_counties.shp"))) {
  message("  US counties already present in ", counties_dir, " -- skipping download.")
} else {
  zip <- file.path(RAW, "cb_2022_us_county_500k.zip")
  message("  downloading ", COUNTIES_URL)
  fetch_zip(COUNTIES_URL, zip)
  tmp <- file.path(RAW, "us_counties_tmp"); dir.create(tmp, showWarnings = FALSE)
  utils::unzip(zip, exdir = tmp); unlink(zip)
  for (ext in c("shp", "shx", "dbf", "prj", "cpg")) {          # keep only the components sf/00_spine.R need
    src <- file.path(tmp, paste0("cb_2022_us_county_500k.", ext))
    if (file.exists(src)) file.rename(src, file.path(counties_dir, paste0("us_counties.", ext)))
  }
  unlink(tmp, recursive = TRUE)
  for (f in list.files(counties_dir, full.names = TRUE)) record_provenance("us_counties", f, COUNTIES_URL)
}

# ---- Green Book PM2.5 (2012 std) nonattainment-area POLYGONS (current, time-invariant boundary) -------
# NB: this is only the boundary shapefile. The 11 yearly STATUS snapshots (pm25_2012_status/<year>.dbf)
#   are a SEPARATE, NOT-yet-automated source -- see the file header and this stage's README.
GREENBOOK_NAA_URL <- "https://www3.epa.gov/airquality/greenbook/shapefile/pm25_2012std_naa_shapefile.zip"
naa_dir <- file.path(RAW, "greenbook", "pm25_2012_naa")
dir.create(naa_dir, showWarnings = FALSE, recursive = TRUE)
if (file.exists(file.path(naa_dir, "PM25_2012Std_NAA.shp"))) {
  message("  Green Book NAA shapefile already present in ", naa_dir, " -- skipping download.")
} else {
  zip <- file.path(RAW, "pm25_2012std_naa_shapefile.zip")
  message("  downloading ", GREENBOOK_NAA_URL)
  fetch_zip(GREENBOOK_NAA_URL, zip, min_bytes = 1e4)
  utils::unzip(zip, exdir = naa_dir); unlink(zip)
  for (f in list.files(naa_dir, pattern = "^PM25_2012Std_NAA[.]", full.names = TRUE))
    record_provenance("greenbook", f, GREENBOOK_NAA_URL)
}
