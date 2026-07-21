# =========================================================================================================
# code/diagnostics/11_operating_profile.R -- exploratory profiling of dataset 1 (data/datasets/operating.csv.gz).
#   Purpose: characterize the operating dataset for a reader picking the project up cold -- coverage,
#   operating-status distribution, program-active prevalence, entry/exit spells, begin-year coverage.
#   Companion to 06_panel_profile.R (same discipline, different asset: this profiles dataset 1 directly,
#   not the sample panels' OPERATING column).
#
#   in : data/datasets/operating.csv.gz
#   out: output/operating_profile/*.csv
#
#   DISCIPLINE (do not "fix" away): OPERATING / OP_STATUS_CODE / PROG_*_ACTIVE are NA outside the wayback
#   window (2015-2025, WAYBACK_OBSERVED==0) -- every rate below is computed on the observed subset AND
#   reports the NA share, so a structural NA is never read as a zero. ENTERED_YEAR/EXITED_YEAR/EXIT_SOURCE
#   are facility-level (one value per facility, broadcast to all years) -- summarised once per facility, not
#   once per row. EARLIEST_PROGRAM_BEGIN_YEAR is profiled here for coverage only; see
#   briefs/begin_year_operating_proxy.md for whether it's usable as an operating-status proxy. No numbers are
#   hand-entered; every cell is computed here. Hand-run (not part of RUN_ALL.R). No stochastic step.
# =========================================================================================================
suppressPackageStartupMessages({library(data.table)})
options(scipen = 999)

DATASETS <- here::here("data/datasets")
OUT      <- here::here("output/operating_profile")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

op <- fread(file.path(DATASETS, "operating.csv.gz"))
YEARS  <- sort(unique(op$YEAR))
WB_YRS <- op[WAYBACK_OBSERVED == 1, sort(unique(YEAR))]
PROG_COLS <- grep("^PROG_.*_ACTIVE$", names(op), value = TRUE)

fwrite_rounded <- function(dt, file, prop_cols = NULL, num_cols = NULL) {
  d <- copy(dt)
  for (cc in intersect(prop_cols, names(d))) d[, (cc) := round(get(cc), 3)]
  for (cc in intersect(num_cols,  names(d))) d[, (cc) := round(get(cc), 2)]
  fwrite(d, file)
}
fac1 <- op[, .SD[1L], by = PGM_SYS_ID]     # one row per facility, for facility-level (time-invariant) fields

# =========================================================================================================
# CSV 1 -- overview
# =========================================================================================================
overview <- data.table(
  n_facilities        = uniqueN(op$PGM_SYS_ID),
  n_facility_years    = nrow(op),
  year_min            = min(op$YEAR), year_max = max(op$YEAR),
  balanced            = nrow(op) == uniqueN(op$PGM_SYS_ID) * length(YEARS),
  wayback_window      = paste(min(WB_YRS), max(WB_YRS), sep = "-"),
  pct_facility_years_wayback_observed = mean(op$WAYBACK_OBSERVED == 1),
  pct_facilities_any_entered_year     = fac1[, mean(!is.na(ENTERED_YEAR))],
  pct_facilities_any_exited_year      = fac1[, mean(!is.na(EXITED_YEAR))],
  pct_facilities_screened_begin_year  = fac1[, mean(!is.na(EARLIEST_PROGRAM_BEGIN_YEAR))])
fwrite_rounded(overview, file.path(OUT, "overview.csv"),
               prop_cols = c("pct_facility_years_wayback_observed", "pct_facilities_any_entered_year",
                             "pct_facilities_any_exited_year", "pct_facilities_screened_begin_year"))

# =========================================================================================================
# CSV 2 -- coverage & operating-status rate by year
# =========================================================================================================
coverage_by_year <- op[, .(
  n_facility_years  = .N,
  pct_wayback_observed = mean(WAYBACK_OBSERVED == 1),
  pct_operating     = if (.BY$YEAR %in% WB_YRS) mean(OPERATING == 1, na.rm = TRUE) else NA_real_,
  pct_begin_year_le = mean(!is.na(EARLIEST_PROGRAM_BEGIN_YEAR) & EARLIEST_PROGRAM_BEGIN_YEAR <= .BY$YEAR)
), by = YEAR][order(YEAR)]
fwrite_rounded(coverage_by_year, file.path(OUT, "coverage_by_year.csv"),
               prop_cols = c("pct_wayback_observed", "pct_operating", "pct_begin_year_le"))

# =========================================================================================================
# CSV 3 -- OP_STATUS_CODE frequency, wayback-observed rows only
# =========================================================================================================
status_freq <- op[WAYBACK_OBSERVED == 1, .N, by = .(OP_STATUS_CODE, OP_STATUS_DESC)][order(-N)]
status_freq[, pct := round(N / sum(N), 4)]
fwrite(status_freq, file.path(OUT, "op_status_freq.csv"))

# =========================================================================================================
# CSV 4 -- binary-flag prevalence: OPERATING + each PROG_*_ACTIVE, wayback window only
# =========================================================================================================
BIN_COLS <- c("OPERATING", PROG_COLS)
binary_prevalence <- rbindlist(lapply(BIN_COLS, function(b) {
  x <- op[WAYBACK_OBSERVED == 1][[b]]
  data.table(flag = b, window = paste(min(WB_YRS), max(WB_YRS), sep = "-"),
             n = length(x), share_1 = mean(x == 1, na.rm = TRUE), pct_na = mean(is.na(x)))
}))
fwrite_rounded(binary_prevalence, file.path(OUT, "binary_prevalence.csv"), prop_cols = c("share_1", "pct_na"))

# =========================================================================================================
# CSV 5 -- entry/exit spell summary (facility-level)
# =========================================================================================================
entry_exit_summary <- data.table(
  n_facilities            = nrow(fac1),
  n_ever_entered          = fac1[!is.na(ENTERED_YEAR), .N],
  n_ever_exited           = fac1[!is.na(EXITED_YEAR), .N],
  n_left_censored         = fac1[LEFT_CENSORED == 1, .N],
  n_right_censored        = fac1[RIGHT_CENSORED == 1, .N],
  n_never_operating       = fac1[is.na(ENTERED_YEAR), .N])
fwrite(entry_exit_summary, file.path(OUT, "entry_exit_summary.csv"))

exit_source_freq <- fac1[!is.na(EXIT_SOURCE), .N, by = EXIT_SOURCE][order(-N)]
exit_source_freq[, pct := round(N / sum(N), 4)]
fwrite(exit_source_freq, file.path(OUT, "exit_source_freq.csv"))

# entries and exits BY YEAR (facility-level events, not facility-years)
entries_by_year <- fac1[!is.na(ENTERED_YEAR), .(n_entered = .N), by = .(YEAR = ENTERED_YEAR)]
exits_by_year   <- fac1[!is.na(EXITED_YEAR),  .(n_exited  = .N), by = .(YEAR = EXITED_YEAR)]
entry_exit_by_year <- merge(entries_by_year, exits_by_year, by = "YEAR", all = TRUE)[order(YEAR)]
entry_exit_by_year[is.na(entry_exit_by_year)] <- 0L
fwrite(entry_exit_by_year, file.path(OUT, "entry_exit_by_year.csv"))

# =========================================================================================================
# CSV 6 -- EARLIEST_PROGRAM_BEGIN_YEAR coverage (five-number summary; see begin_year_operating_proxy.md for
#   proxy-validity analysis, not repeated here)
# =========================================================================================================
begin_year_summary <- rbindlist(lapply(c("EARLIEST_PROGRAM_BEGIN_YEAR_RAW", "EARLIEST_PROGRAM_BEGIN_YEAR"), function(cc) {
  x <- fac1[[cc]]; x <- x[!is.na(x)]
  data.table(column = cc, n_non_na = length(x), pct_na = 1 - length(x) / nrow(fac1),
             min = min(x), p25 = quantile(x, .25), median = median(x), p75 = quantile(x, .75), max = max(x))
}))
fwrite_rounded(begin_year_summary, file.path(OUT, "begin_year_summary.csv"), prop_cols = "pct_na")

# =========================================================================================================
# console summary
# =========================================================================================================
cat("data/datasets/operating.csv.gz -- profile summary\n")
cat("===================================================\n\n")
cat(sprintf("%s facilities x %s years (%d-%d) = %s facility-years | balanced rectangle: %s\n",
            format(overview$n_facilities, big.mark=","), length(YEARS), overview$year_min, overview$year_max,
            format(overview$n_facility_years, big.mark=","), overview$balanced))
cat(sprintf("wayback-observed: %.1f%% of facility-years (window %s)\n",
            100 * overview$pct_facility_years_wayback_observed, overview$wayback_window))
cat("\nCOVERAGE / OPERATING RATE BY YEAR\n"); print(as.data.frame(coverage_by_year), row.names = FALSE)
cat("\nOP_STATUS_CODE FREQUENCY (wayback-observed rows)\n"); print(as.data.frame(status_freq), row.names = FALSE)
cat("\nBINARY FLAG PREVALENCE (wayback window)\n"); print(as.data.frame(binary_prevalence), row.names = FALSE)
cat("\nENTRY/EXIT SUMMARY (facility-level)\n"); print(as.data.frame(entry_exit_summary), row.names = FALSE)
cat("\nEXIT_SOURCE FREQUENCY\n"); print(as.data.frame(exit_source_freq), row.names = FALSE)
cat("\nBEGIN-YEAR COVERAGE (facility-level; see begin_year_operating_proxy.md for proxy validity)\n")
print(as.data.frame(begin_year_summary), row.names = FALSE)
