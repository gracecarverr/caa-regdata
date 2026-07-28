# =========================================================================================================
# code/01_data_download/01_download.R -- acquire raw data into data/raw/ (immutable) + record provenance.
#   Skipped when code/RUN_ALL.R is called with DOWNLOAD=false. Standalone: no shared helpers, no config.
#
#   Fetches ICIS-Air, AFS, combined emissions, the CAA Compliance Pipeline dataset, FRS facility/program-link
#   data (all from the same EPA ECHO bulk directory), US county boundaries, and the ICIS-Air Wayback annual
#   snapshots (pinned to specific confirmed captures -- see below). Idempotent throughout: if a source's
#   files are already present it does nothing (raw is immutable). Records a provenance row per extracted
#   file in data/raw/MANIFEST.csv (source, file, url, downloaded_at, md5).
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
#
#   CAA Pipeline note: data/raw/PIPELINE_CAA_00_COMPLETE.csv was manually staged 2026-07-23 (not fetched by
#   this script); automated here 2026-07-27 once confirmed the ECHO page's "CAA Pipeline Dataset" link
#   (pipeline_caa_downloads.zip) unzips to that exact filename -- same single-CSV pattern as EMISSIONS_URL.
#
#   REVIEWED 2026-07-27: every base URL below (ICIS-Air, AFS, combined emissions, CAA pipeline, FRS, Census
#   counties) was independently re-verified live with `curl -sI` -- all return HTTP 200 from the expected
#   host with a plausible content-length/content-type. All 10 pinned Wayback timestamps were also
#   independently re-verified live -- each resolves to HTTP 200 with an x-archive-orig-date matching its
#   intended year. See chat summary for the full verification table.
# =========================================================================================================
library(readr)                     # only need write_csv() here (for MANIFEST.csv); no other tidyverse verbs used

RAW <- here::here("data/raw")                       # project-root-relative path to the immutable raw-data dir
dir.create(RAW, showWarnings = FALSE, recursive = TRUE)  # create if absent; no warning/error if it already exists

# append a provenance record (call after every successful download)
record_provenance <- function(source, file, url) {
  manifest <- file.path(RAW, "MANIFEST.csv")        # single running ledger for ALL sources, not per-source
  row <- data.frame(source = source, file = basename(file), url = url,   # one row per extracted file: which
                    downloaded_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),  # source, filename only (not
                    md5 = if (file.exists(file)) unname(tools::md5sum(file)) else NA_character_)  # full path),
                                                     # source URL, ISO-8601-ish local timestamp with offset, md5
  write_csv(row, manifest, append = file.exists(manifest))  # append if manifest already exists, else write
  invisible(row)                                    # fresh (with header) -- so first-ever row also creates the
}                                                    # file; returns the row invisibly (unused by callers here)

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
  hdrs <- curlGetHeaders(url)                        # HEAD request once, up front, to learn the expected size
  expected <- suppressWarnings(as.numeric(sub(".*content-length:\\s*(\\d+).*", "\\1",
    tolower(paste(names(hdrs), hdrs, sep = ": ", collapse = " ")))))
    # REVIEW(bug): this concatenates ALL header name:value pairs into one lowercased string and takes the
    # LAST "content-length:"-containing match (greedy `.*` backtracks minimally from the right). For a plain
    # HTTPS response this is fine (only one "content-length" header exists). But every Wayback response below
    # also carries an "x-archive-orig-content-length" header, whose name *contains* the substring
    # "content-length:" -- so on Wayback fetches this regex actually extracts x-archive-orig-content-length,
    # not the response's real Content-Length. In every case checked here the two values are identical, so
    # this hasn't caused a false failure -- but that's incidental, not guaranteed, since x-archive-orig-* is
    # the Internet Archive's record of the ORIGINAL response, not necessarily a promise about what it will
    # actually serve back on this request.
  for (attempt in 1:8) {                             # up to 8 attempts before giving up
    system2("curl", c("-L", "-C", "-", "--retry", "3", "--retry-delay", "5", "--max-time", "300",
                      "-o", shQuote(dest_zip), shQuote(url)), stdout = FALSE, stderr = FALSE)
      # -L: follow redirects. -C -: resume from wherever dest_zip currently ends (0 bytes on first attempt).
      # --retry 3 / --retry-delay 5: curl's OWN built-in retry on top of this function's outer retry loop.
      # --max-time 300: hard cap of 5 minutes per attempt regardless of resume progress. stdout/stderr
      # suppressed -- curl's progress meter and any warnings are silently discarded, not logged anywhere.
    got <- file.size(dest_zip)                       # bytes actually on disk after this attempt
    if (!is.na(got) && got >= min_bytes && (is.na(expected) || got >= expected * 0.99)) return(invisible(TRUE))
      # success if: file exists, is at least the sanity-floor size, AND (we couldn't determine an expected
      # size OR we're within 1% of it -- allows for minor Content-Length/actual-bytes slop). REVIEW(design):
      # if `expected` is NA (header probe failed or, per above, was silently wrong), the ONLY completeness
      # check left is min_bytes -- a 100KB-vs-68MB partial ICIS-Air download would pass this check as "done".
    message("    attempt ", attempt, ": got ", got, " of ", expected, " bytes -- resuming")  # progress note;
    Sys.sleep(3)                                     # only visible when running interactively / logs captured
  }                                                   # brief pause between attempts, on top of curl's own retry-delay
  stop("fetch_zip: could not get a complete download of ", url, " after 8 attempts")  # hard failure after all
}                                                     # 8 attempts exhausted -- stops the whole script (no partial
                                                       # continuation), which is the right call for raw-data integrity
curlGetHeaders <- function(url) tryCatch(curlGetHeaders_impl(url), error = function(e) character())
  # wraps the real implementation so a network hiccup on the HEAD probe degrades to "no headers" (character())
  # rather than crashing the whole download -- fetch_zip then treats `expected` as NA and falls back to min_bytes
curlGetHeaders_impl <- function(url) {
  h <- system2("curl", c("-sI", "--max-time", "20", shQuote(url)), stdout = TRUE)
    # REVIEW(design): -I (HEAD) without -L (no redirect-follow), unlike the -L used in fetch_zip's actual GET
    # below. If this URL ever started redirecting (it currently doesn't -- verified live, see file header),
    # this HEAD probe would report the redirect response's headers (possibly no/small content-length) while
    # the real download follows the redirect to a different resource -- expected-size and actual-download
    # would silently target different responses.
  vals <- sub("^[^:]+:\\s*", "", h); names(vals) <- sub(":.*$", "", h); vals
    # crude "HTTP-header-line" -> named vector parser: splits each returned line on the first colon. The
    # status line ("HTTP/2 200", no colon) doesn't match either substitution pattern and passes through
    # unchanged as both its own name and value -- harmless (never matched by the content-length regex above)
    # but is a stray, slightly odd entry if this vector is ever inspected directly.
}

# ---- ICIS-Air (current bulk download) ---------------------------------------------------------------
ICIS_URL <- "https://echo.epa.gov/files/echodownloads/ICIS-AIR_downloads.zip"
out_dir <- file.path(RAW, "ICIS-AIR_downloads")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
if (length(list.files(out_dir, pattern = "[.]csv$"))) {
  # REVIEW(design): idempotency check is "does at least one .csv already exist here", not "does the expected
  # set of files exist". A previous run that was interrupted mid-unzip (leaving a subset of the 10 ICIS-Air
  # tables) would be silently treated as fully downloaded on every future run and never retried/completed.
  message("  ICIS-Air already present in ", out_dir, " -- skipping download.")  # idempotent no-op branch
} else {
  zip <- file.path(RAW, "ICIS-AIR_downloads.zip")    # download to RAW/ first, not directly into out_dir
  message("  downloading ", ICIS_URL)
  fetch_zip(ICIS_URL, zip)                           # retrying, size-verified fetch (see fetch_zip above)
  utils::unzip(zip, exdir = out_dir); unlink(zip)    # extract all members into out_dir, then delete the zip
  for (f in list.files(out_dir, full.names = TRUE)) record_provenance("icis_air", f, ICIS_URL)
    # one MANIFEST.csv row per extracted file (not one row for the zip as a whole)
}

# ---- AFS (legacy Air Facility System) -- same ECHO bulk directory as ICIS-Air -------------------------
AFS_URL <- "https://echo.epa.gov/files/echodownloads/afs_downloads.zip"
afs_dir <- file.path(RAW, "afs_downloads")
dir.create(afs_dir, showWarnings = FALSE, recursive = TRUE)
if (length(list.files(afs_dir, pattern = "[.]csv$"))) {
  message("  AFS already present in ", afs_dir, " -- skipping download.")  # same shallow idempotency caveat as ICIS-Air above
} else {
  zip <- file.path(RAW, "afs_downloads.zip")
  message("  downloading ", AFS_URL)
  fetch_zip(AFS_URL, zip)
  utils::unzip(zip, exdir = afs_dir); unlink(zip)
  for (f in list.files(afs_dir, full.names = TRUE)) record_provenance("afs", f, AFS_URL)
}

# ---- combined emissions report -- same ECHO bulk directory --------------------------------------------
EMISSIONS_URL <- "https://echo.epa.gov/files/echodownloads/POLL_RPT_COMBINED_EMISSIONS.zip"
emissions_csv <- file.path(RAW, "POLL_RPT_COMBINED_EMISSIONS.csv")  # single expected output file (not a directory of many)
if (file.exists(emissions_csv)) {
  # this idempotency check IS exact (one specific expected filename), unlike the "any .csv present" checks above
  message("  combined emissions already present -- skipping download.")
} else {
  zip <- file.path(RAW, "POLL_RPT_COMBINED_EMISSIONS.zip")
  message("  downloading ", EMISSIONS_URL)
  fetch_zip(EMISSIONS_URL, zip)
  utils::unzip(zip, exdir = RAW); unlink(zip)        # extracted straight into RAW/ (not a subfolder), unlike ICIS/AFS/FRS
  record_provenance("emissions", emissions_csv, EMISSIONS_URL)  # single provenance row (single file), not a loop
}

# ---- CAA Compliance Pipeline dataset -- same ECHO bulk directory --------------------------------------
PIPELINE_URL <- "https://echo.epa.gov/files/echodownloads/pipeline_caa_downloads.zip"
pipeline_csv <- file.path(RAW, "PIPELINE_CAA_00_COMPLETE.csv")
if (file.exists(pipeline_csv)) {
  message("  CAA pipeline already present -- skipping download.")   # exact-filename idempotency check, same as emissions above
} else {
  zip <- file.path(RAW, "pipeline_caa_downloads.zip")
  message("  downloading ", PIPELINE_URL)
  fetch_zip(PIPELINE_URL, zip)
  utils::unzip(zip, exdir = RAW); unlink(zip)
  record_provenance("pipeline", pipeline_csv, PIPELINE_URL)
}

# ---- FRS (Facility Registry Service) -- facility coordinates + program linkages -- same ECHO bulk -----
# directory as ICIS-Air/AFS above. NOT ordsext.epa.gov/.../national_combined.zip (see file header) -- that
# is a different, larger FRS export with a different schema.
FRS_URL <- "https://echo.epa.gov/files/echodownloads/frs_downloads.zip"
frs_dir <- file.path(RAW, "frs")
dir.create(frs_dir, showWarnings = FALSE, recursive = TRUE)
if (length(list.files(frs_dir, pattern = "[.]csv$"))) {
  message("  FRS already present in ", frs_dir, " -- skipping download.")  # same shallow idempotency caveat as ICIS-Air/AFS above
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
  # exact-filename check on the renamed .shp (post-processing below renames every component to "us_counties.*")
  message("  US counties already present in ", counties_dir, " -- skipping download.")
} else {
  zip <- file.path(RAW, "cb_2022_us_county_500k.zip")
  message("  downloading ", COUNTIES_URL)
  fetch_zip(COUNTIES_URL, zip)
  tmp <- file.path(RAW, "us_counties_tmp"); dir.create(tmp, showWarnings = FALSE)  # extract to a scratch dir first
  utils::unzip(zip, exdir = tmp); unlink(zip)
  for (ext in c("shp", "shx", "dbf", "prj", "cpg")) {          # keep only the components sf/00_spine.R need
    src <- file.path(tmp, paste0("cb_2022_us_county_500k.", ext))    # original Census filename per extension
    if (file.exists(src)) file.rename(src, file.path(counties_dir, paste0("us_counties.", ext)))
      # rename+move into counties_dir with a stable, shorter name; silently skips any extension not present
      # in the zip (e.g. if Census ever drops .cpg) rather than erroring -- fine since sf tolerates a missing
      # optional component like .cpg, but would silently produce an incomplete shapefile if .shp/.shx/.dbf
      # were ever missing, with no explicit check that the "required" three actually landed
  }
  unlink(tmp, recursive = TRUE)                       # discard the scratch dir and any un-kept extracted files
                                                        # (e.g. Census's .shp.xml / .shp.ea.iso.xml metadata files)
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
WAYBACK_URL <- "https://echo.epa.gov/files/echodownloads/ICIS-AIR_downloads.zip"  # the ORIGINAL (live) URL --
                                                        # gets prefixed with the Wayback machine's capture syntax below
WAYBACK_TIMESTAMPS <- c(                               # one pinned capture ID (yyyyMMddHHmmss) per target year;
  "2015" = "20150927111008", "2016" = "20161225101825", "2017" = "20170514071503",  # independently
  "2019" = "20190525005616", "2020" = "20201016201845", "2021" = "20211031083633",  # re-verified live
  "2022" = "20221129221859", "2023" = "20230601011243", "2024" = "20240926180831",  # 2026-07-27: all 10
  "2025" = "20250914052608"                                                          # resolve, dates match
)
for (yr in names(WAYBACK_TIMESTAMPS)) {                # one iteration per pinned year (2018 has no entry, so is skipped)
  yr_dir <- file.path(RAW, "ICIS_AIR_WAYBACK", paste0("ICIS-AIR_downloads_", yr))
  dir.create(yr_dir, showWarnings = FALSE, recursive = TRUE)
  if (length(list.files(yr_dir, pattern = "[.]csv$"))) {
    # same shallow "any .csv present" idempotency caveat as ICIS-Air/AFS/FRS above -- doubly relevant here
    # given the file header's own note that 4 of these years (2022-2025) currently have FEWER files staged
    # than a fresh download would produce; this check would treat that trimmed set as "already present" and
    # never top it up to the full 10-table set
    message("  Wayback ", yr, " already present in ", yr_dir, " -- skipping download.")
  } else {
    ts <- WAYBACK_TIMESTAMPS[[yr]]                     # this year's pinned capture timestamp
    wb_url <- sprintf("https://web.archive.org/web/%sid_/%s", ts, WAYBACK_URL)
      # Wayback "id_" modifier: serves the raw captured resource byte-for-byte, without Archive's usual
      # HTML-rewriting/toolbar injection that applies to normal (non-id_) replay URLs -- essential for a
      # binary zip, since the rewritten version would corrupt it
    zip <- file.path(RAW, paste0("ICIS-AIR_downloads_wayback_", yr, ".zip"))
    message("  downloading Wayback ", yr, " (capture ", ts, ")")
    fetch_zip(wb_url, zip, min_bytes = 1e6)            # higher min_bytes floor (1MB) than the other sources'
                                                        # default 100KB -- reasonable given every ICIS-Air
                                                        # snapshot has historically been tens of MB
    utils::unzip(zip, exdir = yr_dir); unlink(zip)
    for (f in list.files(yr_dir, full.names = TRUE))
      record_provenance(paste0("icis_air_wayback_", yr), f, wb_url)  # source tagged per-year (e.g. "icis_air_wayback_2016")
  }
}
