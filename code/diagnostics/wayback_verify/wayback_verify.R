# =========================================================================================================
# code/diagnostics/wayback_verify/wayback_verify.R
#   Per-year, per-file verification of data/raw/ICIS_AIR_WAYBACK/ICIS-AIR_downloads_<year>/ against the
#   Internet Archive Wayback Machine's CDX index for EPA's live ICIS-Air bulk download URL. A prior,
#   uncommitted attempt at automating this source picked one candidate per year (the latest capture in that
#   calendar year) and hoped it matched -- it did, byte-for-byte, for 2015/2017/2019/2020/2025, but not 2016,
#   and 2018 has zero captures of the URL at any status code (see code/01_data_download/01_download.R header
#   and decision W7 in briefs/panel/panel_construction_decisions.md). This script replaces that guess with an
#   exhaustive check: every distinct-content Wayback capture in a year's window is downloaded and md5-compared
#   against the staged files, so the answer per year is proven, not assumed.
#
#   Method: md5 every staged CSV first (the ground truth). Then, per staged year, query the CDX API for
#   captures of the target URL within that calendar year, filter to HTTP 200, sort most-recent-first, and
#   collapse by content digest (identical digest = identical bytes, so never fetch the same content twice).
#   Walk candidates in that order; the first one whose extracted CSVs md5-match every staged file is recorded
#   as the match (set EXHAUSTIVE=true to keep checking the rest anyway). A candidate missing a staged filename
#   is INCOMPLETE (not hashed, not a "mismatch"). No candidates at all / no 200s / all tried and none matched
#   are each their own explicit status -- nothing here is a silent pass.
#
#   Read-only w.r.t. data/raw/ (immutable) and data/raw/MANIFEST.csv (written only by 01_download.R's actual
#   fetch automation). Downloaded candidate zips are cached under this folder's _cache/ (gitignored,
#   disposable) purely to avoid re-fetching across repeated runs during development.
#
#   in : data/raw/ICIS_AIR_WAYBACK/ICIS-AIR_downloads_<year>/*.csv   (staged files being verified)
#   out: output/wayback_verify/staged_file_md5s.csv    (ground-truth md5 per staged file)
#        output/wayback_verify/summary_by_year.csv     (headline: status + matched capture per year)
#        output/wayback_verify/candidates_by_year.csv  (every unique candidate considered, tried or not)
#        output/wayback_verify/file_mismatches.csv     (per-file md5 diffs for tried-and-failed candidates)
#   Hand-run diagnostic (not part of RUN_ALL.R). Deterministic given Wayback's index at run time; makes
#   network requests (CDX + candidate zip downloads), so re-running can in principle see a different index
#   (e.g. a new recrawl) -- any such change would show up as a divergence from the console's documented-
#   expectations diff, not be silently absorbed.
# =========================================================================================================
suppressPackageStartupMessages({library(tools)})

RAW           <- here::here("data/raw/ICIS_AIR_WAYBACK")
OUT           <- here::here("output/wayback_verify")
CACHE         <- here::here("code/diagnostics/wayback_verify/_cache")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
dir.create(CACHE, showWarnings = FALSE, recursive = TRUE)

TARGET_URL      <- "https://echo.epa.gov/files/echodownloads/ICIS-AIR_downloads.zip"
REQUEST_DELAY_S <- 1.5
EXHAUSTIVE      <- identical(tolower(Sys.getenv("EXHAUSTIVE", "false")), "true")

# expectations documented in 01_download.R's header / code/01_data_download/README.md -- used only to flag
# divergence in the console summary, never to alter behavior. Updated 2026-07-29 after the Q4 re-pin
# (dataset_construction_decisions.md O8): all 10 currently-staged years are now confirmed PASS, established
# across two runs this session (each hit a transient CDX-API timeout on a different subset of years -- 2015
# failed-then-passed in one run, 2024/2025 failed-then-passed in the other, with zero disagreement on any
# year that succeeded in both -- see output/wayback_verify/summary_by_year.csv). 2018 stays
# NO_CAPTURES_ANY_STATUS (it isn't a staged folder, so never appears in the loop below, but the entry
# documents the finding for anyone reading this constant).
DOCUMENTED_STATUS <- c(
  "2015" = "PASS", "2016" = "PASS", "2017" = "PASS", "2018" = "NO_CAPTURES_ANY_STATUS",
  "2019" = "PASS", "2020" = "PASS", "2021" = "PASS", "2022" = "PASS", "2023" = "PASS",
  "2024" = "PASS", "2025" = "PASS"
)

pace <- function() Sys.sleep(REQUEST_DELAY_S)

# ---- CDX query: one per year, digest-collapsed, unfiltered by status (so callers can distinguish -------
# "nothing archived" from "archived but never 200"), most-recent-first. Retries an apparently-empty
# response a few times before trusting it as a genuine zero-capture year (an empty response has been
# observed on a first attempt for a year later shown to have real captures) -- this matters because the
# 2018 zero-captures claim needs to survive more than one flaky request.
cdx_query <- function(year, attempts = 3) {
  encoded <- utils::URLencode(TARGET_URL, reserved = TRUE)
  url <- sprintf(
    "https://web.archive.org/cdx/search/cdx?url=%s&from=%d&to=%d&collapse=digest&limit=10000",
    encoded, year, year)
  lines <- character(0)
  for (attempt in seq_len(attempts)) {
    pace()
    lines <- system2("curl", c("-s", "--max-time", "45", shQuote(url)), stdout = TRUE, stderr = FALSE)
    if (length(lines) > 0) break
  }
  empty <- data.frame(timestamp = character(), statuscode = character(), digest = character(),
                       stringsAsFactors = FALSE)
  if (length(lines) == 0) return(empty)
  recs <- strsplit(trimws(lines), "\\s+")
  recs <- recs[lengths(recs) == 7]
  if (length(recs) == 0) return(empty)
  df <- as.data.frame(do.call(rbind, recs), stringsAsFactors = FALSE)
  names(df) <- c("urlkey", "timestamp", "original", "mimetype", "statuscode", "digest", "length")
  df[order(df$timestamp, decreasing = TRUE), c("timestamp", "statuscode", "digest")]
}

# collapse to one row per unique digest (most-recent timestamp kept), recording the others alongside
dedupe_by_digest <- function(cdx_df) {
  if (nrow(cdx_df) == 0) return(cdx_df[0, ])
  by_digest <- split(cdx_df$timestamp, cdx_df$digest)
  keep <- vapply(by_digest, `[`, character(1), 1)          # first = most recent, since cdx_df is sorted
  also <- vapply(by_digest, function(ts) paste(ts[-1], collapse = ";"), character(1))
  out <- data.frame(timestamp = keep, digest = names(by_digest), also_timestamps_same_digest = also,
                     stringsAsFactors = FALSE)
  out[order(out$timestamp, decreasing = TRUE), ]
}

# ---- fetch one candidate's raw zip bytes, cached by timestamp ------------------------------------------
fetch_capture_zip <- function(timestamp, min_bytes = 1e4, attempts = 6) {
  dest <- file.path(CACHE, paste0(timestamp, ".zip"))
  if (file.exists(dest) && !is.na(file.size(dest)) && file.size(dest) >= min_bytes) return(dest)
  wb_url <- sprintf("https://web.archive.org/web/%sid_/%s", timestamp, TARGET_URL)
  for (attempt in seq_len(attempts)) {
    pace()
    system2("curl", c("-s", "-L", "-C", "-", "--retry", "2", "--retry-delay", "3", "--max-time", "120",
                       "-o", shQuote(dest), shQuote(wb_url)), stdout = FALSE, stderr = FALSE)
    got <- suppressWarnings(file.size(dest))
    if (!is.na(got) && got >= min_bytes) return(dest)
  }
  NA_character_
}

# ---- compare one candidate zip's extracted CSVs against the staged md5s -------------------------------
compare_candidate <- function(zip_path, staged_files, staged_md5) {
  contents <- tryCatch(utils::unzip(zip_path, list = TRUE)$Name, error = function(e) character(0))
  base_contents <- basename(contents)
  missing <- setdiff(staged_files, base_contents)
  if (length(missing) > 0) {
    return(list(result = "INCOMPLETE", missing = missing, n_compared = 0, n_matched = 0, mismatches = NULL))
  }
  tmp <- tempfile("wbverify_")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  full_paths <- contents[match(staged_files, base_contents)]
  utils::unzip(zip_path, files = full_paths, exdir = tmp, junkpaths = TRUE)
  mismatches <- list(); n_matched <- 0
  for (f in staged_files) {
    extracted <- file.path(tmp, f)
    cand_md5 <- if (file.exists(extracted)) unname(tools::md5sum(extracted)) else NA_character_
    if (!is.na(cand_md5) && identical(cand_md5, staged_md5[[f]])) {
      n_matched <- n_matched + 1
    } else {
      mismatches[[length(mismatches) + 1]] <- data.frame(
        file = f, staged_md5 = staged_md5[[f]], candidate_md5 = cand_md5, stringsAsFactors = FALSE)
    }
  }
  result <- if (n_matched == length(staged_files)) "MATCH" else "MISMATCH"
  list(result = result, missing = character(0), n_compared = length(staged_files),
       n_matched = n_matched,
       mismatches = if (length(mismatches)) do.call(rbind, mismatches) else NULL)
}

# ---- discover staged years from disk (not hardcoded) ---------------------------------------------------
year_dirs <- list.files(RAW, pattern = "^ICIS-AIR_downloads_[0-9]{4}$", full.names = TRUE)
years <- as.integer(sub(".*_([0-9]{4})$", "\\1", year_dirs))
names(year_dirs) <- years
years <- sort(years)

message("Found ", length(years), " staged years: ", paste(years, collapse = ", "))

# ---- ground truth: md5 every staged CSV --------------------------------------------------------------
staged_md5_rows <- list()
staged_files_by_year <- list()
staged_md5_by_year <- list()
for (yr in years) {
  d <- year_dirs[[as.character(yr)]]
  fs <- list.files(d, pattern = "[.]csv$", full.names = TRUE)
  fnames <- basename(fs)
  md5s <- unname(tools::md5sum(fs))
  staged_files_by_year[[as.character(yr)]] <- fnames
  staged_md5_by_year[[as.character(yr)]] <- setNames(md5s, fnames)
  staged_md5_rows[[length(staged_md5_rows) + 1]] <- data.frame(
    year = yr, file = fnames, size_bytes = file.size(fs), md5 = md5s, stringsAsFactors = FALSE)
}
staged_file_md5s <- do.call(rbind, staged_md5_rows)
write.csv(staged_file_md5s, file.path(OUT, "staged_file_md5s.csv"), row.names = FALSE)

# ---- main per-year verification loop -------------------------------------------------------------------
summary_rows <- list()
candidate_rows <- list()
mismatch_rows <- list()

for (yr in years) {
  message("== ", yr, " ==")
  staged_files <- staged_files_by_year[[as.character(yr)]]
  staged_md5   <- staged_md5_by_year[[as.character(yr)]]

  cdx_all <- cdx_query(yr)
  n_any <- nrow(cdx_all)
  cdx_200 <- cdx_all[cdx_all$statuscode == "200", ]
  n_200 <- nrow(cdx_200)

  if (n_any == 0) {
    summary_rows[[length(summary_rows) + 1]] <- data.frame(
      year = yr, n_staged_files = length(staged_files), n_captures_any_status = 0, n_captures_200 = 0,
      n_unique_candidates = 0, status = "NO_CAPTURES_ANY_STATUS", matched_timestamp = NA,
      matched_digest = NA, match_rank = NA,
      note = "zero captures of the URL in this calendar-year window at any status code", stringsAsFactors = FALSE)
    next
  }
  if (n_200 == 0) {
    summary_rows[[length(summary_rows) + 1]] <- data.frame(
      year = yr, n_staged_files = length(staged_files), n_captures_any_status = n_any, n_captures_200 = 0,
      n_unique_candidates = 0, status = "NO_200_CAPTURES", matched_timestamp = NA, matched_digest = NA,
      match_rank = NA,
      note = sprintf("%d capture(s) exist but none returned HTTP 200", n_any), stringsAsFactors = FALSE)
    next
  }

  cands <- dedupe_by_digest(cdx_200)
  n_unique <- nrow(cands)
  message("  ", n_200, " captures at HTTP 200 -> ", n_unique, " unique candidate(s) after digest-collapse")

  matched <- NULL
  best_partial <- NULL  # track closest miss for the FAIL note
  for (rank in seq_len(n_unique)) {
    ts <- cands$timestamp[rank]; dg <- cands$digest[rank]
    zip_path <- fetch_capture_zip(ts)
    if (is.na(zip_path)) {
      candidate_rows[[length(candidate_rows) + 1]] <- data.frame(
        year = yr, rank = rank, timestamp = ts, digest = dg,
        also_timestamps_same_digest = cands$also_timestamps_same_digest[rank],
        tried = TRUE, download_ok = FALSE, missing_staged_files = NA, n_files_compared = 0,
        n_files_matched = 0, result = "DOWNLOAD_FAILED", stringsAsFactors = FALSE)
      next
    }
    cmp <- compare_candidate(zip_path, staged_files, staged_md5)
    candidate_rows[[length(candidate_rows) + 1]] <- data.frame(
      year = yr, rank = rank, timestamp = ts, digest = dg,
      also_timestamps_same_digest = cands$also_timestamps_same_digest[rank],
      tried = TRUE, download_ok = TRUE,
      missing_staged_files = if (length(cmp$missing)) paste(cmp$missing, collapse = ";") else NA,
      n_files_compared = cmp$n_compared, n_files_matched = cmp$n_matched, result = cmp$result,
      stringsAsFactors = FALSE)

    if (!is.null(cmp$mismatches)) {
      mismatch_rows[[length(mismatch_rows) + 1]] <- data.frame(
        year = yr, timestamp = ts, cmp$mismatches, stringsAsFactors = FALSE)
    }
    if (is.null(best_partial) || cmp$n_matched > best_partial$n_matched) {
      best_partial <- list(timestamp = ts, n_matched = cmp$n_matched, n_compared = cmp$n_compared)
    }

    if (cmp$result == "MATCH") {
      matched <- list(timestamp = ts, digest = dg, rank = rank)
      message("  MATCH at rank ", rank, " (timestamp ", ts, ")")
      if (!EXHAUSTIVE) break
    }
  }
  # remaining untried candidates (only when EXHAUSTIVE is off and we stopped early) get a NOT_TRIED row
  if (!is.null(matched) && !EXHAUSTIVE && matched$rank < n_unique) {
    for (rank in (matched$rank + 1):n_unique) {
      candidate_rows[[length(candidate_rows) + 1]] <- data.frame(
        year = yr, rank = rank, timestamp = cands$timestamp[rank], digest = cands$digest[rank],
        also_timestamps_same_digest = cands$also_timestamps_same_digest[rank],
        tried = FALSE, download_ok = NA, missing_staged_files = NA, n_files_compared = NA,
        n_files_matched = NA, result = "NOT_TRIED", stringsAsFactors = FALSE)
    }
  }

  if (!is.null(matched)) {
    status <- "PASS"
    note <- sprintf("matched at rank %d of %d unique candidate(s)%s", matched$rank, n_unique,
                     if (EXHAUSTIVE) " (exhaustive: all candidates checked)" else "")
  } else {
    status <- "FAIL"
    note <- if (!is.null(best_partial)) {
      sprintf("%d candidate(s) tried, none matched; closest miss: %s (%d of %d files matched)",
              n_unique, best_partial$timestamp, best_partial$n_matched, best_partial$n_compared)
    } else {
      sprintf("%d candidate(s) tried, none downloaded successfully", n_unique)
    }
  }

  summary_rows[[length(summary_rows) + 1]] <- data.frame(
    year = yr, n_staged_files = length(staged_files), n_captures_any_status = n_any, n_captures_200 = n_200,
    n_unique_candidates = n_unique, status = status,
    matched_timestamp = if (!is.null(matched)) matched$timestamp else NA,
    matched_digest = if (!is.null(matched)) matched$digest else NA,
    match_rank = if (!is.null(matched)) matched$rank else NA, note = note, stringsAsFactors = FALSE)
}

summary_by_year <- do.call(rbind, summary_rows)
candidates_by_year <- if (length(candidate_rows)) do.call(rbind, candidate_rows) else NULL
file_mismatches <- if (length(mismatch_rows)) do.call(rbind, mismatch_rows) else
  data.frame(year = integer(), timestamp = character(), file = character(),
             staged_md5 = character(), candidate_md5 = character())

write.csv(summary_by_year, file.path(OUT, "summary_by_year.csv"), row.names = FALSE)
if (!is.null(candidates_by_year)) write.csv(candidates_by_year, file.path(OUT, "candidates_by_year.csv"), row.names = FALSE)
write.csv(file_mismatches, file.path(OUT, "file_mismatches.csv"), row.names = FALSE)

# ---- console summary: three buckets + divergence from documented expectations -------------------------
message("\n================ WAYBACK VERIFICATION SUMMARY ================")
for (bucket in list(c("PASS", "PROVEN REPRODUCIBLE (byte-for-byte match found)"),
                     c("FAIL", "PROVEN NOT REPRODUCIBLE (all candidates tried, none matched)"),
                     c("NO_200_CAPTURES", "NO USABLE CAPTURES -- archived, but never HTTP 200"),
                     c("NO_CAPTURES_ANY_STATUS", "NO USABLE CAPTURES -- nothing archived at all"))) {
  yrs <- summary_by_year$year[summary_by_year$status == bucket[1]]
  message(bucket[2], ": ", if (length(yrs)) paste(yrs, collapse = " ") else "(none)")
}

message("\n-- divergence from documented expectations (01_download.R header) --")
any_diverged <- FALSE
for (yr in names(DOCUMENTED_STATUS)) {
  yr_i <- as.integer(yr)
  row <- summary_by_year[summary_by_year$year == yr_i, ]
  if (nrow(row) == 0) next
  expected <- DOCUMENTED_STATUS[[yr]]
  actual <- row$status[1]
  if (!identical(expected, actual)) {
    any_diverged <- TRUE
    message("  DIVERGENCE ", yr, ": documented=", expected, " actual=", actual, " -- ", row$note[1])
  }
}
if (!any_diverged) message("  none -- every previously-documented year reproduced its expected status")

new_years <- setdiff(years, as.integer(names(DOCUMENTED_STATUS)))
if (length(new_years)) {
  message("\n-- previously-untested years (2021-2024 etc.), new information --")
  for (yr in new_years) {
    row <- summary_by_year[summary_by_year$year == yr, ]
    message("  ", yr, ": ", row$status[1], " -- ", row$note[1])
  }
}
message("================================================================\n")
message("Wrote output/wayback_verify/{staged_file_md5s,summary_by_year,candidates_by_year,file_mismatches}.csv")
