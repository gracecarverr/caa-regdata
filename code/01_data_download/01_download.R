# =========================================================================================================
# code/01_data_download/01_download.R -- acquire raw data into data/raw/ (immutable) + record provenance.
#   Skipped when code/RUN_ALL.R is called with DOWNLOAD=false. Standalone: no shared helpers, no config.
#
#   Fetches ICIS-Air, AFS, combined emissions, FRS facility/program-link data (all from the same EPA ECHO
#   bulk directory), US county boundaries, and the ICIS-Air Wayback annual snapshots (pinned to specific
#   confirmed captures -- see below). Idempotent throughout: if a source's files are already present it
#   does nothing (raw is immutable). Records a provenance row per extracted file in data/raw/MANIFEST.csv
#   (source, file, url, downloaded_at, md5).
#
#   Wayback snapshots (data/raw/ICIS_AIR_WAYBACK/ICIS-AIR_downloads_<year>/, 2015-2017/2019-2025) are
#   fetched from PINNED per-year capture timestamps, not a live "latest capture" search -- a live search is
#   exactly what previously produced a false "2016 doesn't reproduce" conclusion (its true match is a capture
#   5 days older than the latest one that year; 2022 and 2024 have the same pattern). Every pinned timestamp
#   was confirmed byte-for-byte against the staged files by code/diagnostics/wayback_verify/wayback_verify.R
#   (run 2026-07-27; see that stage's README and output/wayback_verify/summary_by_year.csv). 2018 is NOT
#   automated here -- the Internet Archive has ZERO captures of this URL at any status code for 2018 (the
#   staged "2018" data was found to be a mislabeled duplicate of 2019 and was deleted from data/raw/, W7);
#   there is no capture to pin.
#
#   NB: the confirmed capture zips always contain all 10 ICIS-Air tables, but the folders currently staged
#   on disk for 2022 (9 files) and 2023-2025 (8 files each) were trimmed down at some point after staging --
#   a fresh run of this section will produce the FULL 10-file set for every year, which differs from what's
#   on disk right now for those 4 years. Harmless: the wayback cleaning scripts
#   (code/02_cleaning/wayback/17-19_*.R) read specific named files only, never list.files()-glob the
#   directory, so extra tables are simply never read.
#
#   FRS note: the URL previously tried here (ordsext.epa.gov/FLA/www3/state_files/national_combined.zip,
#   ~1.26 GB) is a real, working download (confirmed 2026-07-27 -- the earlier "truncated connections" finding
#   was a transient issue with that specific transfer, not a dead endpoint) but it is the WRONG product: a
#   33-column multi-table FRS export, not the 10-column FRS_FACILITIES.csv this pipeline actually uses. The
#   real source is echo.epa.gov/files/echodownloads/frs_downloads.zip (confirmed schema- and content-identical
#   to the staged file, same bulk-download pattern as ICIS-Air/AFS above) -- that's what's automated below.
#
#   Green Book / PM2.5 attainment data is NOT fetched here: the attainment layer (data/raw/greenbook/,
#   code/03_panel_building/01_attainment.R, data/panels/attainment.csv.gz) was removed from this repo
#   2026-07-27 -- that code was already synced to the CAA_Project repo (2026-07-23) and lives there now.
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

# ---- FRS (Facility Registry Service) -- facility coordinates + program linkages -- same ECHO bulk -----
# directory as ICIS-Air/AFS above. NOT ordsext.epa.gov/.../national_combined.zip (see file header) -- that
# is a different, larger FRS export with a different schema.
FRS_URL <- "https://echo.epa.gov/files/echodownloads/frs_downloads.zip"
frs_dir <- file.path(RAW, "frs")
dir.create(frs_dir, showWarnings = FALSE, recursive = TRUE)
if (length(list.files(frs_dir, pattern = "[.]csv$"))) {
  message("  FRS already present in ", frs_dir, " -- skipping download.")
} else {
  zip <- file.path(RAW, "frs_downloads.zip")
  message("  downloading ", FRS_URL)
  fetch_zip(FRS_URL, zip)
  utils::unzip(zip, exdir = frs_dir); unlink(zip)
  for (f in list.files(frs_dir, full.names = TRUE)) record_provenance("frs", f, FRS_URL)
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

# ---- ICIS-Air Wayback annual snapshots (2015-2017, 2019-2025) ------------------------------------------
# Pinned to the exact capture confirmed byte-for-byte against the staged files by
# code/diagnostics/wayback_verify/wayback_verify.R (run 2026-07-27 -- see that stage's README and
# output/wayback_verify/summary_by_year.csv). NOT a live "latest capture" search: a live search is what
# produced the false "2016 doesn't match" conclusion in the first place (the true match is 5 days older
# than 2016's latest capture; 2022 and 2024 have the same pattern), and the Archive's index can grow new,
# non-matching captures over time. 2018 is excluded -- zero captures of this URL exist at any status code
# (W7); its data/raw folder was deleted as a mislabeled 2019 duplicate and is not reconstructable here.
WAYBACK_URL <- "https://echo.epa.gov/files/echodownloads/ICIS-AIR_downloads.zip"
WAYBACK_TIMESTAMPS <- c(
  "2015" = "20150927111008", "2016" = "20161225101825", "2017" = "20170514071503",
  "2019" = "20190525005616", "2020" = "20201016201845", "2021" = "20211031083633",
  "2022" = "20221129221859", "2023" = "20230601011243", "2024" = "20240926180831",
  "2025" = "20250914052608"
)
for (yr in names(WAYBACK_TIMESTAMPS)) {
  yr_dir <- file.path(RAW, "ICIS_AIR_WAYBACK", paste0("ICIS-AIR_downloads_", yr))
  dir.create(yr_dir, showWarnings = FALSE, recursive = TRUE)
  if (length(list.files(yr_dir, pattern = "[.]csv$"))) {
    message("  Wayback ", yr, " already present in ", yr_dir, " -- skipping download.")
  } else {
    ts <- WAYBACK_TIMESTAMPS[[yr]]
    wb_url <- sprintf("https://web.archive.org/web/%sid_/%s", ts, WAYBACK_URL)
    zip <- file.path(RAW, paste0("ICIS-AIR_downloads_wayback_", yr, ".zip"))
    message("  downloading Wayback ", yr, " (capture ", ts, ")")
    fetch_zip(wb_url, zip, min_bytes = 1e6)
    utils::unzip(zip, exdir = yr_dir); unlink(zip)
    for (f in list.files(yr_dir, full.names = TRUE))
      record_provenance(paste0("icis_air_wayback_", yr), f, wb_url)
  }
}
