# =========================================================================================================
# code/diagnostics/11_operating_profile.R -- exploratory profiling of dataset 1 (data/datasets/operating.csv.gz).
#   Purpose: characterize the operating dataset for a reader picking the project up cold -- coverage,
#   operating-status distribution, program-active prevalence, entry/exit spells, begin-year coverage.
#   Companion to 06_panel_profile.R (same discipline, different asset: this profiles dataset 1 directly,
#   not the sample panels' OPERATING column).
#
#   in : data/datasets/operating.csv.gz
#   out: output/operating_profile/*.csv
#        output/figures/datasets/operating/op_{coverage_over_time,entry_exit_by_year,program_prevalence}.png
#
#   DISCIPLINE (do not "fix" away): OPERATING / OP_STATUS_CODE / PROG_*_ACTIVE are NA outside the wayback
#   window (2015-2025, WAYBACK_OBSERVED==0) -- every rate below is computed on the observed subset AND
#   reports the NA share, so a structural NA is never read as a zero. ENTERED_YEAR/EXITED_YEAR/EXIT_SOURCE
#   are facility-level (one value per facility, broadcast to all years) -- summarised once per facility, not
#   once per row. EARLIEST_PROGRAM_BEGIN_YEAR is profiled here for coverage only; see
#   briefs/datasets/begin_year_operating_proxy.md for whether it's usable as an operating-status proxy. No numbers are
#   hand-entered; every cell is computed here. Hand-run (not part of RUN_ALL.R). No stochastic step.
#
#   FIGURE DESIGN: same print-ready convention as 13_regulatory_profile.R (dataviz skill, validated
#   categorical palette, direct end-of-line labels in place of a legend, 300dpi).
# =========================================================================================================
suppressPackageStartupMessages({library(data.table); library(ggplot2); library(scales)})
options(scipen = 999)

DATASETS <- here::here("data/datasets")
OUT      <- here::here("output/operating_profile")
OUT_FIG  <- here::here("output/figures/datasets/operating")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
dir.create(OUT_FIG, showWarnings = FALSE, recursive = TRUE)

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
# FIGURES -- print-ready (300dpi), validated categorical palette, direct end-of-line labels
# =========================================================================================================
PAL <- c(blue = "#2a78d6", aqua = "#1baf7a", yellow = "#eda100", green = "#008300", violet = "#4a3aa7", red = "#e34948")
INK <- "#0b0b0b"; INK_SECONDARY <- "#52514e"; GRID <- "#e1e0d9"; AXIS <- "#c3c2b7"
theme_journal <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), panel.grid.major = element_line(color = GRID, linewidth = 0.3),
        axis.line = element_line(color = AXIS, linewidth = 0.3), axis.ticks = element_line(color = AXIS, linewidth = 0.3),
        text = element_text(color = INK), axis.text = element_text(color = INK_SECONDARY),
        plot.title = element_text(face = "bold", size = 12), plot.subtitle = element_text(color = INK_SECONDARY, size = 9.5),
        plot.caption = element_text(color = INK_SECONDARY, size = 8, hjust = 0), legend.position = "none")
save_fig <- function(name, plot, w = 7.5, h = 4.5) ggsave(file.path(OUT_FIG, name), plot, width = w, height = h, dpi = 300)

# ---- FIGURE 1: wayback coverage vs operating rate, 2005-2025 ---------------------------------------------
cov_long <- rbindlist(list(
  coverage_by_year[, .(YEAR, value = pct_wayback_observed, series = "Wayback-observed (share of all facility-years)")],
  coverage_by_year[!is.na(pct_operating), .(YEAR, value = pct_operating, series = "Operating (share of observed facility-years)")]))
end1 <- cov_long[, .SD[YEAR == max(YEAR)], by = series]
fig1 <- ggplot(cov_long, aes(YEAR, value, color = series)) +
  geom_line(linewidth = 0.9) +
  scale_color_manual(values = setNames(c(PAL[["blue"]], PAL[["aqua"]]), unique(cov_long$series))) +
  scale_x_continuous(breaks = seq(min(YEARS), max(YEARS), 5), expand = expansion(mult = c(0.02, 0.30))) +
  scale_y_continuous(labels = label_percent(), limits = c(0, 1)) +
  geom_text(data = end1, aes(label = series), hjust = 0, nudge_x = 0.5, size = 3.1, fontface = "bold",
            lineheight = 0.9) +
  coord_cartesian(clip = "off") +
  labs(title = "Wayback coverage and operating rate, 2005-2025",
       subtitle = "Operating rate is undefined (NA) before 2015 -- no wayback snapshot exists to compute it from",
       x = NULL, y = NULL, caption = "Source: data/datasets/operating.csv.gz (dataset 1).") +
  theme_journal + theme(plot.margin = margin(t = 5.5, r = 90, b = 5.5, l = 5.5))
save_fig("op_coverage_over_time.png", fig1, w = 9, h = 4.8)

# ---- FIGURE 2: facility entries vs exits by year, EXCLUDING 2015 -- 2015's "155,230 entries" is left-
#   censoring (every facility already present at wayback's first snapshot), not a real entry event, and
#   including it swamps the actually-interesting 2016-2025 variation on the same axis (noted in the caption,
#   not silently dropped). ------------------------------------------------------------------------------
ee_long <- melt(entry_exit_by_year[YEAR > 2015], id.vars = "YEAR", variable.name = "series", value.name = "n")
ee_long[, series := fifelse(series == "n_entered", "Entries", "Exits")]
end2 <- ee_long[, .SD[YEAR == max(YEAR)], by = series]
end2[, label_n := n]
if (abs(end2$label_n[1] - end2$label_n[2]) < diff(range(ee_long$n)) * 0.06) {
  ord <- order(end2$label_n)
  end2$label_n[ord] <- end2$label_n[ord] + c(-1, 1) * diff(range(ee_long$n)) * 0.04
}
fig2 <- ggplot(ee_long, aes(YEAR, n, color = series)) +
  geom_line(linewidth = 0.9) + geom_point(size = 1.6) +
  scale_color_manual(values = setNames(c(PAL[["blue"]], PAL[["red"]]), c("Entries", "Exits"))) +
  scale_x_continuous(breaks = seq(min(ee_long$YEAR), max(ee_long$YEAR), 2), expand = expansion(mult = c(0.02, 0.16))) +
  scale_y_continuous(labels = label_comma()) +
  geom_text(data = end2, aes(x = YEAR, y = label_n, label = series), hjust = 0, nudge_x = 0.3, size = 3.2,
            fontface = "bold", inherit.aes = FALSE) +
  coord_cartesian(clip = "off") +
  labs(title = "Facility entries and exits per year, 2016-2025",
       subtitle = "2015 excluded (155,230 \"entries\" that year are left-censoring -- already present at wayback's first\nsnapshot, not a real entry event); reconstructed from snapshot presence, not source-recorded dates",
       x = NULL, y = "Facilities", caption = "Source: data/datasets/operating.csv.gz (dataset 1).") +
  theme_journal + theme(plot.margin = margin(t = 5.5, r = 40, b = 5.5, l = 5.5),
                        plot.subtitle = element_text(color = INK_SECONDARY, size = 8.7, lineheight = 1.1))
save_fig("op_entry_exit_by_year.png", fig2, w = 8, h = 4.8)

# ---- FIGURE 3: program-active prevalence, wayback window -------------------------------------------------
prog_prev <- binary_prevalence[flag != "OPERATING"]
prog_prev[, program := sub("^PROG_(.*)_ACTIVE$", "\\1", flag)]
prog_prev <- prog_prev[order(-share_1)]
prog_prev[, program := factor(program, levels = program)]
fig3 <- ggplot(prog_prev, aes(program, share_1)) +
  geom_col(fill = PAL[["blue"]], width = 0.7) +
  scale_y_continuous(labels = label_percent()) +
  labs(title = "Program-active prevalence, 2015-2025 (wayback-observed facility-years)",
       subtitle = "Share of observed facility-years where the program group is coded active",
       x = NULL, y = "Share active", caption = "Source: data/datasets/operating.csv.gz (dataset 1).") +
  theme_journal
save_fig("op_program_prevalence.png", fig3)

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
