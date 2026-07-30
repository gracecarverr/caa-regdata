# =========================================================================================================
# code/diagnostics/wayback_verify/wayback_q4_repin.R
#   Selects a Q4 (Oct-Dec) Wayback Machine capture of the ICIS-Air bulk zip for each of the years whose
#   CURRENT pin (code/01_data_download/01_download.R:240-245) does NOT land in Q4 -- 2015 (Sep 27), 2017
#   (May 14), 2019 (May 25), 2023 (Jun 1), 2024 (Sep 26), 2025 (Sep 14). Those pins were never chosen for
#   calendar consistency -- wayback_verify.R (this folder) picks whichever capture byte-for-byte reproduces
#   whatever was ALREADY staged on disk, which is a different goal. This script answers a different question:
#   "what is the best available Q4 capture for this year," full stop -- there is no staged ground truth to
#   match against, because EPA's live ICIS-Air extract genuinely differs month to month, so a Q4 capture is
#   expected to have real content differences from the currently-staged (non-Q4) file, not reproduce it.
#
#   Selection rule, per year: query the Wayback CDX API for HTTP-200 captures of the target URL within
#   Oct 1 - Dec 31 of that year, dedupe by content digest, walk most-recent-first, download each candidate,
#   and accept the first one whose zip contains the full 10-table ICIS_AIR_TABLES set (completeness, not a
#   byte-match -- there's nothing to byte-match against). If NO candidate in strict Q4 is complete (e.g. a
#   crawl mid-transfer, or simply no capture that quarter), widen the window symmetrically in fixed 15-day
#   steps (Sep16-Jan15, then Sep1-Jan31, ...) up to a capped number of steps, re-querying each time and only
#   trying candidates not already tried at a narrower step -- "widen minimally," not "accept whatever's in
#   the year" (that would defeat the point of re-pinning for Q4 consistency in the first place). A year that
#   exhausts the widening cap with no complete candidate is reported UNRESOLVED for manual follow-up, not
#   silently left on its old pin or silently given a random distant-month capture.
#
#   Does NOT modify code/01_data_download/01_download.R or data/raw/ itself -- purely a selection/reporting
#   tool. Output is meant to be read by a human (or the next edit to 01_download.R), not consumed downstream.
#
#   in : none (network only -- CDX API + candidate zip downloads)
#   out: output/wayback_verify/q4_repin_candidates.csv  (every candidate tried, every year, every window step)
#        output/wayback_verify/q4_repin_summary.csv     (headline: chosen timestamp + window used per year)
#   Hand-run diagnostic (not part of RUN_ALL.R). Caches downloaded candidate zips in this folder's _cache/
#   (gitignored, shared with wayback_verify.R -- same cache key scheme, timestamp.zip) so re-running doesn't
#   re-fetch a candidate already downloaded by either script.
# =========================================================================================================
suppressPackageStartupMessages({library(tools)})

OUT   <- here::here("output/wayback_verify")
CACHE <- here::here("code/diagnostics/wayback_verify/_cache")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
dir.create(CACHE, showWarnings = FALSE, recursive = TRUE)

TARGET_URL      <- "https://echo.epa.gov/files/echodownloads/ICIS-AIR_downloads.zip"
REQUEST_DELAY_S <- 1.5                                 # same pacing convention as wayback_verify.R
MAX_WIDEN_STEPS <- 4                                    # widen up to 4 times (60 days each side) before
                                                         # giving up and reporting UNRESOLVED for that year
WIDEN_STEP_DAYS <- 15                                   # each widen step expands the window by this many
                                                         # days on BOTH ends (symmetric, "minimal" widening)

# years whose CURRENT pin (01_download.R:240-245) is NOT already in Q4 -- see file header for each year's
# actual current-pin month. 2016/2020/2021/2022 are already Q4 and are intentionally excluded here (nothing
# to re-pin). 2018 is intentionally excluded -- zero captures exist at any status code in ANY window
# (confirmed by wayback_verify.R and decision W7), so no amount of widening can resolve it.
TARGET_YEARS <- c(2015, 2017, 2019, 2023, 2024, 2025)

# the canonical 10-table ICIS-Air manifest -- MUST stay identical to ICIS_AIR_TABLES in
# code/01_data_download/01_download.R:119-124 (duplicated here rather than sourced, matching this repo's
# "standalone diagnostic, no shared helpers" convention already used by wayback_verify.R)
ICIS_AIR_TABLES <- c(
  "ICIS-AIR_FACILITIES.csv", "ICIS-AIR_FCES_PCES.csv", "ICIS-AIR_FORMAL_ACTIONS.csv",
  "ICIS-AIR_INFORMAL_ACTIONS.csv", "ICIS-AIR_POLLUTANTS.csv", "ICIS-AIR_PROGRAMS.csv",
  "ICIS-AIR_PROGRAM_SUBPARTS.csv", "ICIS-AIR_STACK_TESTS.csv", "ICIS-AIR_TITLEV_CERTS.csv",
  "ICIS-AIR_VIOLATION_HISTORY.csv"
)

pace <- function() Sys.sleep(REQUEST_DELAY_S)          # rate-limit courtesy pause before every network call

# ---- CDX query: arbitrary from/to date window (YYYYMMDD strings), digest-collapsed, most-recent-first ----
# Identical in spirit to wayback_verify.R's cdx_query(), but takes explicit from/to strings (that script only
# ever queries a full calendar year) so the widening loop below can pass an arbitrary Q4-centered window,
# including windows that cross a calendar-year boundary (e.g. Sep16-Jan15) -- the CDX API accepts any
# yyyyMMdd-style date string in from/to regardless of whether it aligns to a single year.
cdx_query <- function(from_str, to_str, attempts = 3) {
  encoded <- utils::URLencode(TARGET_URL, reserved = TRUE)
  url <- sprintf(
    "https://web.archive.org/cdx/search/cdx?url=%s&from=%s&to=%s&collapse=digest&limit=10000",
    encoded, from_str, to_str)
  lines <- character(0)
  for (attempt in seq_len(attempts)) {                  # retry an apparently-empty response a few times --
    pace()                                              # mirrors wayback_verify.R's defensive retry, since a
    lines <- system2("curl", c("-s", "--max-time", "45", shQuote(url)), stdout = TRUE, stderr = FALSE)
    if (length(lines) > 0) break                        # flaky first-attempt empty response has been observed
  }
  empty <- data.frame(timestamp = character(), statuscode = character(), digest = character(),
                       stringsAsFactors = FALSE)
  if (length(lines) == 0) return(empty)
  recs <- strsplit(trimws(lines), "\\s+")
  recs <- recs[lengths(recs) == 7]                      # CDX rows have 7 space-separated fields; drop any
  if (length(recs) == 0) return(empty)                  # malformed/partial lines rather than erroring on them
  df <- as.data.frame(do.call(rbind, recs), stringsAsFactors = FALSE)
  names(df) <- c("urlkey", "timestamp", "original", "mimetype", "statuscode", "digest", "length")
  df <- df[df$statuscode == "200", ]                    # filter to HTTP 200 here (unlike wayback_verify.R,
                                                         # which keeps all statuses to distinguish "nothing
                                                         # archived" from "archived but never 200" -- not
                                                         # needed here since TARGET_YEARS all have >=1 200
                                                         # capture somewhere in the full year, per wayback_verify.R)
  df[order(df$timestamp, decreasing = TRUE), c("timestamp", "statuscode", "digest")]
}

# collapse to one row per unique digest (most-recent timestamp kept) -- identical logic to wayback_verify.R
dedupe_by_digest <- function(cdx_df) {
  if (nrow(cdx_df) == 0) return(cdx_df[0, ])
  by_digest <- split(cdx_df$timestamp, cdx_df$digest)
  keep <- vapply(by_digest, `[`, character(1), 1)       # first = most recent, since cdx_df is sorted desc
  out <- data.frame(timestamp = keep, digest = names(by_digest), stringsAsFactors = FALSE)
  out[order(out$timestamp, decreasing = TRUE), ]
}

# ---- fetch one candidate's raw zip bytes, cached by timestamp (shared cache dir with wayback_verify.R) ---
fetch_capture_zip <- function(timestamp, min_bytes = 1e6, attempts = 6) {
  dest <- file.path(CACHE, paste0(timestamp, ".zip"))
  if (file.exists(dest) && !is.na(file.size(dest)) && file.size(dest) >= min_bytes) return(dest)  # reuse
  wb_url <- sprintf("https://web.archive.org/web/%sid_/%s", timestamp, TARGET_URL)  # "id_" = raw bytes,
  for (attempt in seq_len(attempts)) {                  # no HTML rewriting (essential for a binary zip)
    pace()
    system2("curl", c("-s", "-L", "-C", "-", "--retry", "2", "--retry-delay", "3", "--max-time", "120",
                       "-o", shQuote(dest), shQuote(wb_url)), stdout = FALSE, stderr = FALSE)
    got <- suppressWarnings(file.size(dest))
    if (!is.na(got) && got >= min_bytes) return(dest)   # min_bytes=1e6 matches 01_download.R's own floor for
  }                                                      # Wayback fetches (real snapshots are tens of MB)
  NA_character_
}

# ---- completeness check: does this candidate's zip contain the full 10-table set, uncorrupted? -----------
# Unlike wayback_verify.R's compare_candidate(), there is no staged md5 to match against -- a Q4 capture is
# EXPECTED to differ in content from whatever (non-Q4) file is currently staged. "Good" here means: the zip
# opens, and every required table name is present inside it. That's the same bar 01_download.R's own
# idempotency check applies (data/raw/01_download.R:249, "all 10 filenames present"), so a candidate that
# passes this check is exactly as trustworthy as what the live download path already accepts.
check_completeness <- function(zip_path, required_files) {
  contents <- tryCatch(utils::unzip(zip_path, list = TRUE)$Name, error = function(e) NULL)
  if (is.null(contents)) return(list(result = "CORRUPT_ZIP", missing = required_files))  # unzip() itself
                                                                                          # failed -- treat as
                                                                                          # unusable, not a
                                                                                          # silent empty-file pass
  missing <- setdiff(required_files, basename(contents))
  if (length(missing) > 0) return(list(result = "INCOMPLETE", missing = missing))
  list(result = "COMPLETE", missing = character(0))
}

# ---- main per-year selection loop, widening the window only if strict Q4 has no complete candidate -------
candidate_rows <- list()
summary_rows   <- list()
already_tried  <- setNames(vector("list", length(TARGET_YEARS)), as.character(TARGET_YEARS))  # per-year set
                                                                                                # of timestamps
                                                                                                # already tried
                                                                                                # at a narrower
                                                                                                # window, so a
                                                                                                # widen step
                                                                                                # never re-tests
                                                                                                # the same capture

for (yr in TARGET_YEARS) {
  message("== ", yr, " (target: Q4, widening if needed) ==")
  chosen <- NULL
  window_used <- NA_integer_
  n_tried_total <- 0

  for (step_idx in 0:MAX_WIDEN_STEPS) {                 # step 0 = strict Q4; each further step widens
    widen_days <- step_idx * WIDEN_STEP_DAYS            # 15/30/45/60 days on each side for steps 1..4
    from_date <- as.Date(sprintf("%d-10-01", yr)) - widen_days
    to_date   <- as.Date(sprintf("%d-12-31", yr)) + widen_days
    from_str  <- format(from_date, "%Y%m%d")
    to_str    <- format(to_date, "%Y%m%d")

    cdx_200 <- cdx_query(from_str, to_str)
    cands <- dedupe_by_digest(cdx_200)
    new_cands <- cands[!(cands$timestamp %in% already_tried[[as.character(yr)]]), , drop = FALSE]
    message("  window +/-", widen_days, "d (", from_str, "-", to_str, "): ",
            nrow(cands), " unique candidate(s), ", nrow(new_cands), " not yet tried")

    if (nrow(new_cands) == 0) next                      # nothing new to try at this width -- widen further

    for (rank in seq_len(nrow(new_cands))) {
      ts <- new_cands$timestamp[rank]; dg <- new_cands$digest[rank]
      already_tried[[as.character(yr)]] <- c(already_tried[[as.character(yr)]], ts)
      n_tried_total <- n_tried_total + 1

      zip_path <- fetch_capture_zip(ts)
      if (is.na(zip_path)) {
        candidate_rows[[length(candidate_rows) + 1]] <- data.frame(
          year = yr, widen_days = widen_days, rank_in_window = rank, timestamp = ts, digest = dg,
          result = "DOWNLOAD_FAILED", missing_files = NA, stringsAsFactors = FALSE)
        next
      }
      chk <- check_completeness(zip_path, ICIS_AIR_TABLES)
      candidate_rows[[length(candidate_rows) + 1]] <- data.frame(
        year = yr, widen_days = widen_days, rank_in_window = rank, timestamp = ts, digest = dg,
        result = chk$result,
        missing_files = if (length(chk$missing)) paste(chk$missing, collapse = ";") else NA,
        stringsAsFactors = FALSE)

      if (chk$result == "COMPLETE") {
        chosen <- list(timestamp = ts, digest = dg)
        window_used <- widen_days
        message("  CHOSEN: ", ts, " (widen +/-", widen_days, "d)")
        break
      }
    }
    if (!is.null(chosen)) break                          # stop widening once a complete candidate is found
  }

  summary_rows[[length(summary_rows) + 1]] <- data.frame(
    year = yr,
    status = if (!is.null(chosen)) "RESOLVED" else "UNRESOLVED",
    chosen_timestamp = if (!is.null(chosen)) chosen$timestamp else NA,
    window_widen_days = window_used,
    n_candidates_tried = n_tried_total,
    note = if (!is.null(chosen)) {
      sprintf("complete 10-table capture found %s", if (window_used == 0) "within strict Q4"
              else sprintf("only after widening +/-%d days", window_used))
    } else {
      sprintf("no complete candidate found after widening up to +/-%d days (%d total candidate(s) tried) -- needs manual review",
              MAX_WIDEN_STEPS * WIDEN_STEP_DAYS, n_tried_total)
    },
    stringsAsFactors = FALSE)
}

candidates_df <- if (length(candidate_rows)) do.call(rbind, candidate_rows) else NULL
summary_df    <- do.call(rbind, summary_rows)

if (!is.null(candidates_df)) write.csv(candidates_df, file.path(OUT, "q4_repin_candidates.csv"), row.names = FALSE)
write.csv(summary_df, file.path(OUT, "q4_repin_summary.csv"), row.names = FALSE)

message("\n================ Q4 RE-PIN SELECTION SUMMARY ================")
for (i in seq_len(nrow(summary_df))) {
  r <- summary_df[i, ]
  message(r$year, ": ", r$status, " -- ", r$note)
}
message("===============================================================\n")
message("Wrote output/wayback_verify/{q4_repin_candidates,q4_repin_summary}.csv")

# =========================================================================================================
# FLAGGED ISSUES
#   1. "COMPLETE" here means the zip contains all 10 required filenames -- it does NOT verify the CSVs
#      inside are well-formed (parseable, non-truncated content), only that unzip() lists/extracts them
#      without erroring and every name is present. This is the same bar 01_download.R's own idempotency
#      check applies post-download, so it's not a new risk introduced by this script, but it means a
#      candidate with a genuinely corrupted (but present) CSV inside would still read as COMPLETE here.
#   2. MAX_WIDEN_STEPS=4 (+/-60 days max, i.e. as far as Aug 2 - Feb 29) is a judgment call, not derived
#      from anything in the data -- chosen to keep "minimal widening" meaningfully different from "just
#      take whatever's available that year" (which would defeat the point of re-pinning for Q4
#      consistency). If a year comes back UNRESOLVED, that cap -- not the year's actual Wayback coverage
#      -- may be the binding constraint; check q4_repin_candidates.csv before assuming the year truly has
#      no viable capture anywhere near Q4.
#   3. This script's candidate ranking is most-recent-first WITHIN each window, matching wayback_verify.R's
#      convention -- but unlike that script, there is no byte-match to fall back on if the first COMPLETE
#      candidate happens to be a low-quality/edge-of-crawl capture. No further validation (e.g. spot-
#      checking row counts against neighboring years) is performed here; that's left to the human reviewing
#      q4_repin_summary.csv before transcribing a chosen timestamp into 01_download.R.
#   4. Network-dependent and non-deterministic across runs in principle (the Wayback index can grow new
#      captures over time) -- a re-run could in principle choose a different timestamp than a prior run if
#      a new, more-recent-but-still-Q4 capture has since been archived. Not a bug given what this script is
#      for (finding the best CURRENTLY available capture), but worth knowing before treating its output as
#      permanently reproducible without re-running.
# =========================================================================================================
