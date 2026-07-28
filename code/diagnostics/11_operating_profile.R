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
suppressPackageStartupMessages({library(data.table); library(ggplot2); library(scales)})  # quiet attach: data.table verbs, ggplot2/scales for the figures
options(scipen = 999)  # disable scientific notation in printed/console output

DATASETS <- here::here("data/datasets")                        # project-root-relative path to dataset layer (dataset 1 lives here)
OUT      <- here::here("output/operating_profile")             # this script's CSV output directory
OUT_FIG  <- here::here("output/figures/datasets/operating")    # this script's figure output directory
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)        # create CSV output dir if missing, silent if it already exists
dir.create(OUT_FIG, showWarnings = FALSE, recursive = TRUE)    # create figure output dir if missing, silent if it already exists

op <- fread(file.path(DATASETS, "operating.csv.gz"))    # load dataset 1: one row per facility-year
YEARS  <- sort(unique(op$YEAR))                          # full YEAR span present in the file (used for x-axis breaks and the "balanced rectangle" check)
WB_YRS <- op[WAYBACK_OBSERVED == 1, sort(unique(YEAR))]  # years with at least one wayback-observed facility-year -- NOT necessarily contiguous, see FLAG below
# FLAG: WB_YRS is derived from the data, not asserted as a fixed 2015-2025 span -- and it needs to be: 2018 has
# ZERO WAYBACK_OBSERVED rows (verified: pct_wayback_observed by year is 76%/82%/83%/0%/88%/90%/91%/92%/93%/94%/95%
# for 2015-2025, i.e. a total blackout in 2018, not just partial coverage like every other year). Downstream this
# is handled correctly (2018 %in% WB_YRS is FALSE, so pct_operating below is NA_real_ for 2018, not a
# misleading 0), but a reader skimming coverage_by_year.csv or op_coverage_over_time.png could easily read the
# 2018 dip as a genuine data-quality problem rather than what it is: no wayback snapshot exists for that year at all.
PROG_COLS <- grep("^PROG_.*_ACTIVE$", names(op), value = TRUE)  # all program-active flag columns, discovered by name pattern rather than hand-listed

fwrite_rounded <- function(dt, file, prop_cols = NULL, num_cols = NULL) {  # helper: round proportion/numeric columns before writing so CSVs don't carry float noise
  d <- copy(dt)                                                # copy so the caller's table is untouched
  for (cc in intersect(prop_cols, names(d))) d[, (cc) := round(get(cc), 3)]  # proportions rounded to 3 dp
  for (cc in intersect(num_cols,  names(d))) d[, (cc) := round(get(cc), 2)]  # other numerics rounded to 2 dp
  fwrite(d, file)                                               # write the rounded copy
}
fac1 <- op[, .SD[1L], by = PGM_SYS_ID]     # one row per facility, for facility-level (time-invariant) fields
# FLAG: this collapse takes the first row per facility as-is, with no assertion that ENTERED_YEAR / EXITED_YEAR /
# EXIT_SOURCE / LEFT_CENSORED / RIGHT_CENSORED / EARLIEST_PROGRAM_BEGIN_YEAR are actually constant within a
# facility (the header states they are "broadcast to all years" but that invariant is never checked here). If any
# facility ever had a non-constant value on one of these columns, fac1 would silently pick up whatever row happens
# to sort first, and every facility-level summary below (entry/exit counts, begin-year coverage, O5 screen effect)
# would inherit that silent misrepresentation without any warning.

# =========================================================================================================
# CSV 1 -- overview
# =========================================================================================================
overview <- data.table(
  n_facilities        = uniqueN(op$PGM_SYS_ID),                          # distinct facilities in dataset 1
  n_facility_years    = nrow(op),                                        # total rows = facility x year observations
  year_min            = min(op$YEAR), year_max = max(op$YEAR),           # observed YEAR range
  balanced            = nrow(op) == uniqueN(op$PGM_SYS_ID) * length(YEARS),  # TRUE iff every facility has a row for every year (full rectangle)
  wayback_window      = paste(min(WB_YRS), max(WB_YRS), sep = "-"),      # min/max of WB_YRS -- a span label; note per the FLAG above this is NOT proof of contiguous coverage (2018 is a hole inside it)
  pct_facility_years_wayback_observed = mean(op$WAYBACK_OBSERVED == 1),  # share of ALL facility-years (across all YEARS, not just the window) that are wayback-observed
  pct_facilities_any_entered_year     = fac1[, mean(!is.na(ENTERED_YEAR))],  # facility-level: share with a recorded wayback entry year (see n_never_operating FLAG below for what NA here actually means)
  pct_facilities_any_exited_year      = fac1[, mean(!is.na(EXITED_YEAR))],   # facility-level: share with a recorded wayback exit year
  pct_facilities_screened_begin_year  = fac1[, mean(!is.na(EARLIEST_PROGRAM_BEGIN_YEAR))])  # facility-level: share with a non-NA begin year AFTER the O5 plausibility screen
fwrite_rounded(overview, file.path(OUT, "overview.csv"),
               prop_cols = c("pct_facility_years_wayback_observed", "pct_facilities_any_entered_year",
                             "pct_facilities_any_exited_year", "pct_facilities_screened_begin_year"))  # write overview.csv, rounding the four proportion columns

# =========================================================================================================
# CSV 2 -- coverage & operating-status rate by year
# =========================================================================================================
coverage_by_year <- op[, .(
  n_facility_years  = .N,                                        # row count for this YEAR
  pct_wayback_observed = mean(WAYBACK_OBSERVED == 1),             # share of this year's facility-years that are wayback-observed (denominator = ALL facility-years that year, observed or not)
  pct_operating     = if (.BY$YEAR %in% WB_YRS) mean(OPERATING == 1, na.rm = TRUE) else NA_real_,
  # ^ pct_operating: na.rm=TRUE relies on OPERATING being NA exactly when WAYBACK_OBSERVED==0 (verified true for
  # every row in this file: OPERATING is NA for all 3,402,224 WAYBACK_OBSERVED==0 rows and non-NA for all
  # 2,470,741 WAYBACK_OBSERVED==1 rows). That alignment is NOT enforced by this script -- it's an assumption
  # inherited from upstream construction. If it ever decoupled (an OPERATING NA for some other reason), na.rm=TRUE
  # would silently drop those rows from the denominator too, and this table gives the reader no separate pct_na
  # column to catch it -- only the coincidentally-matching pct_wayback_observed in the same row.
  pct_begin_year_le = mean(!is.na(EARLIEST_PROGRAM_BEGIN_YEAR) & EARLIEST_PROGRAM_BEGIN_YEAR <= .BY$YEAR)  # share of ALL facility-years (not just observed ones) whose screened begin year is on or before this YEAR
), by = YEAR][order(YEAR)]
fwrite_rounded(coverage_by_year, file.path(OUT, "coverage_by_year.csv"),
               prop_cols = c("pct_wayback_observed", "pct_operating", "pct_begin_year_le"))  # write coverage_by_year.csv, rounding the three rate columns

# =========================================================================================================
# CSV 3 -- OP_STATUS_CODE frequency, wayback-observed rows only
# =========================================================================================================
status_freq <- op[WAYBACK_OBSERVED == 1, .N, by = .(OP_STATUS_CODE, OP_STATUS_DESC)][order(-N)]  # explicit filter to the observed subset (correct denominator for a status code that's structurally NA elsewhere), counts by code/description pair, most frequent first
status_freq[, pct := round(N / sum(N), 4)]  # share of observed rows in each status category
fwrite(status_freq, file.path(OUT, "op_status_freq.csv"))  # write as-is (already rounded above; fwrite_rounded not needed)

# =========================================================================================================
# CSV 4 -- binary-flag prevalence: OPERATING + each PROG_*_ACTIVE, wayback window only
# =========================================================================================================
BIN_COLS <- c("OPERATING", PROG_COLS)  # every binary flag to profile: OPERATING plus each program-active indicator
binary_prevalence <- rbindlist(lapply(BIN_COLS, function(b) {
  x <- op[WAYBACK_OBSERVED == 1][[b]]  # restrict to the observed subset first, then pull the column -- correct denominator
  data.table(flag = b, window = paste(min(WB_YRS), max(WB_YRS), sep = "-"),
             n = length(x), share_1 = mean(x == 1, na.rm = TRUE), pct_na = mean(is.na(x)))  # share_1 among observed rows (na.rm drops any residual NA) AND pct_na reported explicitly -- full zero-vs-NA discipline observed here
}))
fwrite_rounded(binary_prevalence, file.path(OUT, "binary_prevalence.csv"), prop_cols = c("share_1", "pct_na"))  # write binary_prevalence.csv, rounding the two rate columns

# =========================================================================================================
# CSV 5 -- entry/exit spell summary (facility-level)
# =========================================================================================================
entry_exit_summary <- data.table(
  n_facilities            = nrow(fac1),                            # total facilities (facility-level count, from the one-row-per-facility collapse)
  n_ever_entered          = fac1[!is.na(ENTERED_YEAR), .N],         # facilities with a recorded wayback entry year
  n_ever_exited           = fac1[!is.na(EXITED_YEAR), .N],
  # FLAG: per dataset_construction_decisions.md (O4), EXIT_SOURCE in this dataset is "effectively pure cls"
  # (confirmed closures) -- of 11,801 wayback "dropout" exits (last-seen-operating then vanished from snapshots),
  # only 2 survive the O1 facility-universe restriction; the other 11,799 are wayback-only facilities dropped
  # entirely. So n_ever_exited/EXITED_YEAR here overwhelmingly reflect confirmed closures, not the full universe
  # of facilities that stopped appearing in wayback snapshots -- true disappearance is largely invisible in ds 1.
  n_left_censored         = fac1[LEFT_CENSORED == 1, .N],           # facilities already operating at wayback's first snapshot (true entry year unknown, predates the window)
  n_right_censored        = fac1[RIGHT_CENSORED == 1, .N],          # facilities still operating at wayback's last snapshot (no exit observed -- correctly treated as censored, not as "exited in the last year")
  n_never_operating       = fac1[is.na(ENTERED_YEAR), .N])
  # FLAG: "never operating" is read directly off NA ENTERED_YEAR, but per 10_begin_year_proxy.R's own taxonomy
  # (categories C/D) that NA bucket mixes two different populations: facilities present in wayback snapshots but
  # never coded OPERATING==1 (e.g. already closed by 2015) -- verified 58,075 of these -- and facilities with
  # ZERO wayback observation at all, i.e. no evidence either way -- verified 14,482 of these. Labeling the whole
  # 72,557-facility bucket "never operating" overstates what's actually known for the ~20% with no data at all.
fwrite(entry_exit_summary, file.path(OUT, "entry_exit_summary.csv"))  # write as-is (already integer counts, no rounding needed)

exit_source_freq <- fac1[!is.na(EXIT_SOURCE), .N, by = EXIT_SOURCE][order(-N)]  # facility-level frequency of exit reason, among facilities with a recorded exit
exit_source_freq[, pct := round(N / sum(N), 4)]  # share of recorded exits attributable to each source
fwrite(exit_source_freq, file.path(OUT, "exit_source_freq.csv"))

# entries and exits BY YEAR (facility-level events, not facility-years)
entries_by_year <- fac1[!is.na(ENTERED_YEAR), .(n_entered = .N), by = .(YEAR = ENTERED_YEAR)]  # count of facilities entering in each year, from the facility-level table (not double-counted across observed years)
exits_by_year   <- fac1[!is.na(EXITED_YEAR),  .(n_exited  = .N), by = .(YEAR = EXITED_YEAR)]   # count of facilities exiting in each year, same facility-level basis
entry_exit_by_year <- merge(entries_by_year, exits_by_year, by = "YEAR", all = TRUE)[order(YEAR)]  # full outer join so a year with entries but no exits (or vice versa) still appears
entry_exit_by_year[is.na(entry_exit_by_year)] <- 0L  # merge-induced NAs (a year absent from one side) become an explicit 0 count, not a missing value
# FLAG: unlike Figure 2 below, this CSV is NOT filtered to exclude 2015 -- 2015's ~155,230 "entries" are wayback
# left-censoring (every facility already present at the first snapshot), not real entry events. A reader of
# entry_exit_by_year.csv directly (rather than the figure, whose caption explains the exclusion) could easily
# mistake that 2015 spike for genuine entry activity.
fwrite(entry_exit_by_year, file.path(OUT, "entry_exit_by_year.csv"))

# =========================================================================================================
# CSV 6 -- EARLIEST_PROGRAM_BEGIN_YEAR coverage (five-number summary; see begin_year_operating_proxy.md for
#   proxy-validity analysis, not repeated here)
# =========================================================================================================
begin_year_summary <- rbindlist(lapply(c("EARLIEST_PROGRAM_BEGIN_YEAR_RAW", "EARLIEST_PROGRAM_BEGIN_YEAR"), function(cc) {
  x <- fac1[[cc]]; x <- x[!is.na(x)]  # facility-level column, dropping NA for the five-number summary (pct_na computed separately below against the full facility count)
  data.table(column = cc, n_non_na = length(x), pct_na = 1 - length(x) / nrow(fac1),
             min = min(x), p25 = quantile(x, .25), median = median(x), p75 = quantile(x, .75), max = max(x))  # five-number summary plus non-NA count and NA share, for both the raw and O5-screened versions of the column
}))
fwrite_rounded(begin_year_summary, file.path(OUT, "begin_year_summary.csv"), prop_cols = "pct_na")

# =========================================================================================================
# CSV 7 -- O5 screen effect: how many facilities the [1970,2025] plausibility screen actually changes, and
#   the raw/screened out-of-range counts on each side (backs O5 in dataset_construction_decisions.md --
#   added 2026-07-27, this specific breakdown previously had no script, only the five-number summary above).
# =========================================================================================================
screen_effect <- data.table(
  n_below_1970  = fac1[, sum(EARLIEST_PROGRAM_BEGIN_YEAR_RAW < 1970, na.rm = TRUE)],
  n_above_2025  = fac1[, sum(EARLIEST_PROGRAM_BEGIN_YEAR_RAW > 2025, na.rm = TRUE)],
  # FLAG: 1970 and 2025 are hard-coded literals here, duplicating BEGIN_YEAR_MIN/BEGIN_YEAR_MAX defined in
  # code/04_datasets/02_operating.R (the script that actually applies the O5 screen). If those parameters ever
  # change upstream, this diagnostic's breakdown would silently go stale and no longer match the screen actually
  # applied to EARLIEST_PROGRAM_BEGIN_YEAR -- there's no reference back to the parameter, only a re-typed value.
  n_changed_by_screen = fac1[, sum(!is.na(EARLIEST_PROGRAM_BEGIN_YEAR_RAW) &
                                    (is.na(EARLIEST_PROGRAM_BEGIN_YEAR) |
                                     EARLIEST_PROGRAM_BEGIN_YEAR != EARLIEST_PROGRAM_BEGIN_YEAR_RAW))],  # facilities where screening changed the value (either nulled out or, in principle, altered)
  n_screened_to_na     = fac1[, sum(!is.na(EARLIEST_PROGRAM_BEGIN_YEAR_RAW) & is.na(EARLIEST_PROGRAM_BEGIN_YEAR))])  # subset of the above specifically nulled out by the screen (raw present, screened NA)
fwrite(screen_effect, file.path(OUT, "screen_effect.csv"))

# =========================================================================================================
# FIGURES -- print-ready (300dpi), validated categorical palette, direct end-of-line labels
# =========================================================================================================
PAL <- c(blue = "#2a78d6", aqua = "#1baf7a", yellow = "#eda100", green = "#008300", violet = "#4a3aa7", red = "#e34948")  # validated categorical palette (shared with 13_regulatory_profile.R)
INK <- "#0b0b0b"; INK_SECONDARY <- "#52514e"; GRID <- "#e1e0d9"; AXIS <- "#c3c2b7"  # text/gridline/axis colors for the print theme
theme_journal <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), panel.grid.major = element_line(color = GRID, linewidth = 0.3),
        axis.line = element_line(color = AXIS, linewidth = 0.3), axis.ticks = element_line(color = AXIS, linewidth = 0.3),
        text = element_text(color = INK), axis.text = element_text(color = INK_SECONDARY),
        plot.title = element_text(face = "bold", size = 12), plot.subtitle = element_text(color = INK_SECONDARY, size = 9.5),
        plot.caption = element_text(color = INK_SECONDARY, size = 8, hjust = 0), legend.position = "none")  # shared print theme: muted gridlines, no legend (direct labels used instead)
save_fig <- function(name, plot, w = 7.5, h = 4.5) ggsave(file.path(OUT_FIG, name), plot, width = w, height = h, dpi = 300)  # helper: save a figure at print resolution into OUT_FIG

# ---- FIGURE 1: wayback coverage vs operating rate, 2005-2025 ---------------------------------------------
cov_long <- rbindlist(list(
  coverage_by_year[, .(YEAR, value = pct_wayback_observed, series = "Wayback-observed (share of all facility-years)")],  # series 1: coverage, denominator = all facility-years
  coverage_by_year[!is.na(pct_operating), .(YEAR, value = pct_operating, series = "Operating (share of observed facility-years)")]))  # series 2: operating rate, explicitly filtered to years where it's defined (drops pre-2015/2018 NA years rather than plotting a gap silently)
end1 <- cov_long[, .SD[YEAR == max(YEAR)], by = series]  # last observed point per series, for the end-of-line label position
fig1 <- ggplot(cov_long, aes(YEAR, value, color = series)) +
  geom_line(linewidth = 0.9) +  # one line per series
  scale_color_manual(values = setNames(c(PAL[["blue"]], PAL[["aqua"]]), unique(cov_long$series))) +  # fixed color assignment per series
  scale_x_continuous(breaks = seq(min(YEARS), max(YEARS), 5), expand = expansion(mult = c(0.02, 0.30))) +  # 5-year tick marks; extra right-hand expansion to leave room for end labels
  scale_y_continuous(labels = label_percent(), limits = c(0, 1)) +  # y-axis as a percentage, fixed 0-1 scale
  geom_text(data = end1, aes(label = series), hjust = 0, nudge_x = 0.5, size = 3.1, fontface = "bold",
            lineheight = 0.9) +  # direct end-of-line labels in place of a legend
  coord_cartesian(clip = "off") +  # allow labels to render outside the panel area
  labs(title = "Wayback coverage and operating rate, 2005-2025",
       subtitle = "Operating rate is undefined (NA) before 2015 -- no wayback snapshot exists to compute it from",
       x = NULL, y = NULL, caption = "Source: data/datasets/operating.csv.gz (dataset 1).") +
  theme_journal + theme(plot.margin = margin(t = 5.5, r = 90, b = 5.5, l = 5.5))  # extra right margin to accommodate the end labels
save_fig("op_coverage_over_time.png", fig1, w = 9, h = 4.8)

# ---- FIGURE 2: facility entries vs exits by year, EXCLUDING 2015 -- 2015's "155,230 entries" is left-
#   censoring (every facility already present at wayback's first snapshot), not a real entry event, and
#   including it swamps the actually-interesting 2016-2025 variation on the same axis (noted in the caption,
#   not silently dropped). ------------------------------------------------------------------------------
ee_long <- melt(entry_exit_by_year[YEAR > 2015], id.vars = "YEAR", variable.name = "series", value.name = "n")
# FLAG: this figure explicitly excludes 2015 (see the block comment above), but entry_exit_by_year.csv written
# above at CSV 5 does NOT apply the same exclusion -- the figure and the CSV disagree on whether 2015 belongs in
# the entries series, and only the figure's caption documents why. A reader using the CSV alone would not know.
ee_long[, series := fifelse(series == "n_entered", "Entries", "Exits")]  # relabel the melted variable names for display
end2 <- ee_long[, .SD[YEAR == max(YEAR)], by = series]  # last point per series, for end-of-line labels
end2[, label_n := n]  # separate label-position column so it can be nudged without altering the plotted value
if (abs(end2$label_n[1] - end2$label_n[2]) < diff(range(ee_long$n)) * 0.06) {  # if the two end labels would visually collide (within 6% of the y-range)...
  ord <- order(end2$label_n)
  end2$label_n[ord] <- end2$label_n[ord] + c(-1, 1) * diff(range(ee_long$n)) * 0.04  # ...nudge the lower label down and the higher label up to declutter (cosmetic only -- does not change plotted lines or underlying data)
}
fig2 <- ggplot(ee_long, aes(YEAR, n, color = series)) +
  geom_line(linewidth = 0.9) + geom_point(size = 1.6) +  # line + point markers per series
  scale_color_manual(values = setNames(c(PAL[["blue"]], PAL[["red"]]), c("Entries", "Exits"))) +  # fixed color assignment
  scale_x_continuous(breaks = seq(min(ee_long$YEAR), max(ee_long$YEAR), 2), expand = expansion(mult = c(0.02, 0.16))) +  # 2-year tick marks over the 2016-2025 range actually plotted
  scale_y_continuous(labels = label_comma()) +  # comma-formatted facility counts
  geom_text(data = end2, aes(x = YEAR, y = label_n, label = series), hjust = 0, nudge_x = 0.3, size = 3.2,
            fontface = "bold", inherit.aes = FALSE) +  # end-of-line labels at the (possibly decluttered) label_n position
  coord_cartesian(clip = "off") +
  labs(title = "Facility entries and exits per year, 2016-2025",
       subtitle = "2015 excluded (155,230 \"entries\" that year are left-censoring -- already present at wayback's first\nsnapshot, not a real entry event); reconstructed from snapshot presence, not source-recorded dates",
       x = NULL, y = "Facilities", caption = "Source: data/datasets/operating.csv.gz (dataset 1).") +
  theme_journal + theme(plot.margin = margin(t = 5.5, r = 40, b = 5.5, l = 5.5),
                        plot.subtitle = element_text(color = INK_SECONDARY, size = 8.7, lineheight = 1.1))
save_fig("op_entry_exit_by_year.png", fig2, w = 8, h = 4.8)

# ---- FIGURE 3: program-active prevalence, wayback window -------------------------------------------------
prog_prev <- binary_prevalence[flag != "OPERATING"]  # drop OPERATING itself, keep only the PROG_*_ACTIVE flags
prog_prev[, program := sub("^PROG_(.*)_ACTIVE$", "\\1", flag)]  # strip the PROG_/_ACTIVE wrapper for a cleaner axis label
prog_prev <- prog_prev[order(-share_1)]  # sort descending by prevalence
prog_prev[, program := factor(program, levels = program)]  # lock factor levels to this sort order so ggplot doesn't re-alphabetize the bars
fig3 <- ggplot(prog_prev, aes(program, share_1)) +
  geom_col(fill = PAL[["blue"]], width = 0.7) +  # single-color bar chart (categorical, not a series comparison, so no palette cycling needed)
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
            format(overview$n_facility_years, big.mark=","), overview$balanced))  # top-line shape of the dataset
cat(sprintf("wayback-observed: %.1f%% of facility-years (window %s)\n",
            100 * overview$pct_facility_years_wayback_observed, overview$wayback_window))  # overall observed share and the nominal window span (see WB_YRS FLAG re: the 2018 gap inside it)
cat("\nCOVERAGE / OPERATING RATE BY YEAR\n"); print(as.data.frame(coverage_by_year), row.names = FALSE)
cat("\nOP_STATUS_CODE FREQUENCY (wayback-observed rows)\n"); print(as.data.frame(status_freq), row.names = FALSE)
cat("\nBINARY FLAG PREVALENCE (wayback window)\n"); print(as.data.frame(binary_prevalence), row.names = FALSE)
cat("\nENTRY/EXIT SUMMARY (facility-level)\n"); print(as.data.frame(entry_exit_summary), row.names = FALSE)
cat("\nEXIT_SOURCE FREQUENCY\n"); print(as.data.frame(exit_source_freq), row.names = FALSE)
cat("\nBEGIN-YEAR COVERAGE (facility-level; see begin_year_operating_proxy.md for proxy validity)\n")
print(as.data.frame(begin_year_summary), row.names = FALSE)
cat("\nO5 SCREEN EFFECT\n"); print(as.data.frame(screen_effect), row.names = FALSE)

# =========================================================================================================
# FLAGGED ISSUES
#   1.  (~line 34)  WB_YRS / wayback window is NOT contiguous: 2018 has zero WAYBACK_OBSERVED rows (a total
#       blackout year), not just partial coverage like every other year in 2015-2025. Handled correctly downstream
#       (pct_operating is NA_real_, not 0, for 2018) but easy to misread as a data-quality dip rather than a
#       structural hole in the source snapshots.
#   2.  (~line 43)  fac1's first-row-per-facility collapse assumes ENTERED_YEAR/EXITED_YEAR/EXIT_SOURCE/
#       LEFT_CENSORED/RIGHT_CENSORED/EARLIEST_PROGRAM_BEGIN_YEAR are constant within a facility, but that
#       invariant is never verified in this script -- every facility-level summary below inherits the assumption.
#   3.  (~line 68)  pct_operating's na.rm=TRUE relies on OPERATING being NA exactly when WAYBACK_OBSERVED==0.
#       Verified true in the current data, but not asserted here, and this row has no separate pct_na column of
#       its own to catch future drift (only the coincidentally-aligned pct_wayback_observed).
#   4.  (~line 98)  n_ever_exited/EXIT_SOURCE reflect confirmed closures almost exclusively -- per O4 in
#       dataset_construction_decisions.md, only 2 of 11,801 wayback "dropout" exits survive the O1 facility
#       universe; disappearance-type exits are largely invisible in this dataset.
#   5.  (~line 101) n_never_operating (NA ENTERED_YEAR) conflates two populations: ~58,075 facilities that ARE
#       wayback-observed but never coded operating (e.g. closed pre-2015), and ~14,482 facilities with NO wayback
#       observation at all (no evidence either way). Labeling the combined bucket "never operating" overstates
#       what's known for the latter group.
#   6.  (~line 112) entry_exit_by_year.csv includes 2015 unfiltered, while Figure 2 explicitly excludes 2015 as a
#       left-censoring artifact (155,230 facilities already present at the first snapshot, not real entries). The
#       CSV and figure disagree, and only the figure documents why.
#   7.  (~line 132) n_below_1970 / n_above_2025 hard-code the O5 plausibility-screen bounds as literals, duplicating
#       BEGIN_YEAR_MIN/BEGIN_YEAR_MAX defined in code/04_datasets/02_operating.R with no reference back to them --
#       if the parameters change upstream, this breakdown goes stale silently.
#   8.  (~line 176) Figure 2 excludes 2015 from the entries/exits plot for the reason above; flagged here as the
#       figure-vs-CSV split point referenced in item 6.
# =========================================================================================================
