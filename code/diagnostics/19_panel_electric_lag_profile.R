# =========================================================================================================
# code/diagnostics/19_panel_electric_lag_profile.R -- two descriptive cuts of the panel layer
#   (data/panels/{major_synmin_2015_2025,electric_2015_2025}.csv.gz) not covered by 18_panel_profile.R:
#   (1) electric vs. OTHER (non-electric) facilities netted out WITHIN major_synmin -- 18's own
#   panel_comparison.csv compares the two panel FILES directly, but electric_2015_2025 is a strict NAICS-2211/
#   SIC-4911 subset of major_synmin_2015_2025 (code/04_panel_building/README.md), so that comparison is really
#   "electric vs. electric-plus-everyone-else," diluting "other." Here IS_ELECTRIC tags every major_synmin
#   facility by membership in electric_2015_2025's own facility-ID set (NOT a re-derivation of the NAICS/SIC
#   regex -- reusing the already-built panel means this can't drift from 03_build_parameters.R's actual filter
#   logic), so the two groups partition major_synmin cleanly.
#   (2) regulatory lag (MEAN_VIOL_TO_EA_LAG_DAYS, dataset 6 pipeline.csv.gz -- mean days from violation to
#   enforcement action, already computed facility x year by 07_pipeline.R; row-level version of this same lag
#   concept is profiled in 16_pipeline_profile.R's viol_to_ea_lag_distribution.png) vs. FUTURE violations
#   (major_synmin's own N_VIOLATIONS, year t+1, ICIS_OBSERVED==1 gate) -- strictly prior-period lag against a
#   later violation count, no leakage. Purely descriptive/correlational (see FIGURE 3 caption + FLAGGED
#   ISSUES): facilities with long violation-to-EA lags likely differ systematically (case complexity, program
#   mix, agency), so a relationship here is not a causal claim about what lag itself does.
#
#   in : data/panels/{major_synmin_2015_2025,electric_2015_2025}.csv.gz, data/datasets/pipeline.csv.gz
#   out: output/panel_profile/{electric_vs_other_summary,electric_vs_other_by_year,
#        lag_future_violations}.csv
#        output/figures/panels/panel_{electric_vs_other_means,electric_vs_other_over_time,
#                                      lag_future_violations}.png
#
#   Hand-run (not part of RUN_ALL.R, matching every sibling profile script 11-18, code/diagnostics/README.md).
#   No stochastic step. FIGURE DESIGN: same convention as 18_panel_profile.R (dataviz skill, validated 5-hue
#   categorical palette, 300dpi, direct end-of-line labels where there are 2 series) -- this script inlines its
#   own copy of the PAL/theme_journal boilerplate rather than sourcing 18's, matching how every one of 13/16/17
#   already repeats it independently (no shared helper file in this layer).
# =========================================================================================================
suppressPackageStartupMessages({library(data.table); library(ggplot2); library(scales)})  # data.table for fread/aggregation, ggplot2/scales for the print figures; quietly, to keep the console clean
options(scipen = 999)                                                 # disable scientific notation so large counts/lag-days print as plain integers everywhere (console + CSVs)

PANELS   <- here::here("data/panels")                                 # source dir for the two-panel layer
DATASETS <- here::here("data/datasets")                                # source dir for dataset 6 (pipeline.csv.gz)
OUT_CSV  <- here::here("output/panel_profile")                        # shares 18_panel_profile.R's CSV output dir -- same panel layer, same destination
OUT_FIG  <- here::here("output/figures/panels")                       # shares 18_panel_profile.R's figure output dir
dir.create(OUT_CSV, showWarnings = FALSE, recursive = TRUE)           # create if missing, silently if it already exists
dir.create(OUT_FIG, showWarnings = FALSE, recursive = TRUE)

ID_CHAR_COLS <- c("REGISTRY_ID", "ZIP_CODE", "COUNTY_FIPS", "ICIS_COUNTY_FIPS")  # same leading-zero-losing columns as 18_panel_profile.R -- forced to character on read

# =========================================================================================================
# READ -- major_synmin (the base population for both analyses below), electric's facility-ID set (only used
#   to build IS_ELECTRIC -- electric_2015_2025's own rows are not otherwise used in this script), and
#   pipeline.csv.gz (only the 3 columns this script needs, filtered to major_synmin facilities/years)
# =========================================================================================================
maj <- fread(file.path(PANELS, "major_synmin_2015_2025.csv.gz"), colClasses = list(character = ID_CHAR_COLS))
elec_ids <- unique(fread(file.path(PANELS, "electric_2015_2025.csv.gz"), select = "PGM_SYS_ID")$PGM_SYS_ID)  # facility-ID set only -- this IS the electric filter, already applied by the panel build (03_build_parameters.R's electric_filter())
maj[, IS_ELECTRIC := PGM_SYS_ID %in% elec_ids]                        # tag every major_synmin row electric/non-electric; FALSE = "other" throughout this script
cat(sprintf("major_synmin: %s facilities total, %s (%.1f%%) tagged IS_ELECTRIC\n",
            format(uniqueN(maj$PGM_SYS_ID), big.mark = ","), format(uniqueN(maj[IS_ELECTRIC == TRUE, PGM_SYS_ID]), big.mark = ","),
            100 * uniqueN(maj[IS_ELECTRIC == TRUE, PGM_SYS_ID]) / uniqueN(maj$PGM_SYS_ID)))

YEARS <- sort(unique(maj$YEAR))                                       # distinct years present (2015:2025 per PB3), NOT hard-coded
GROUP_PAL <- c(electric = "#1baf7a", other = "#2a78d6")               # aqua/blue -- same two hues 18_panel_profile.R's PANEL_PAL uses for electric/major_synmin, reused here for electric/other so the two scripts read as one visual family
group_lab <- function(x) fifelse(x, "electric", "other")             # shared TRUE/FALSE -> display-label mapping, used everywhere below a group column is built

maj[, GROUP := factor(group_lab(IS_ELECTRIC), levels = c("electric", "other"))]  # fixed display/plot order: electric first, other second (mirrors 18's major_synmin-then-electric convention, adapted since "other" is the new category here)

pipe <- fread(file.path(DATASETS, "pipeline.csv.gz"), select = c("PGM_SYS_ID", "YEAR", "MEAN_VIOL_TO_EA_LAG_DAYS"))  # dataset 6, only the 3 columns needed (full file is 5.87M rows x 14 cols, no reason to read the rest)
pipe <- pipe[PGM_SYS_ID %in% unique(maj$PGM_SYS_ID) & YEAR %in% 2015:2024 & !is.na(MEAN_VIOL_TO_EA_LAG_DAYS)]  # restrict to major_synmin's facility set; YEAR <= 2024 since every row needs a t+1 inside the panel's 2015-2025 window; non-NA gate (NA = no EA-linked violation eligible that facility-year, per 07_pipeline.R's NaN->NA coercion) is sufficient on its own -- it subsumes PIPELINE_OBSERVED per that script's own zero-vs-NA invariant

fwrite_rounded <- function(dt, file, num_cols = NULL) {                # shared CSV writer, same rounding convention as 18_panel_profile.R's fwrite_rounded
  d <- copy(dt)
  for (cc in intersect(num_cols, names(d))) d[, (cc) := round(get(cc), 2)]
  fwrite(d, file)
}

# =========================================================================================================
# CSV 1 -- mean/median of key N_* count measures, electric vs. other, ICIS_OBSERVED subset (same 9 measures,
#   same gate as 18_panel_profile.R's summary_counts.csv, just grouped by IS_ELECTRIC instead of by panel)
# =========================================================================================================
COUNT_COLS <- c("N_INSPECTIONS", "N_VIOLATIONS", "N_HPV", "N_ENFORCEMENT", "N_FORMAL", "N_INFORMAL",
                "N_CERTS", "N_STACK_TESTS", "N_PENALTIES")
obs <- maj[ICIS_OBSERVED == 1]                                        # ICIS_OBSERVED==1 subset -- a facility-year with no ICIS record that year is NA, not a false 0, so it's excluded here exactly as 18's summary_counts.csv excludes it
electric_vs_other_summary <- rbindlist(lapply(COUNT_COLS, function(m) {
  x <- obs[[m]]
  obs[, .(n_obs = sum(!is.na(get(m))), mean = mean(get(m), na.rm = TRUE), median = as.double(median(get(m), na.rm = TRUE))), by = GROUP][, measure := m][]
}))[, .(measure, GROUP, n_obs, mean, median)][order(measure, GROUP)]
fwrite_rounded(electric_vs_other_summary, file.path(OUT_CSV, "electric_vs_other_summary.csv"), num_cols = c("mean", "median"))

# =========================================================================================================
# CSV 2 -- same 9 measures x GROUP x YEAR (mean only) -- feeds FIGURE 2, the "regulatory intensity over time,
#   electric vs. other" ask
# =========================================================================================================
electric_vs_other_by_year <- rbindlist(lapply(COUNT_COLS, function(m)
  obs[, .(measure = m, n_obs = sum(!is.na(get(m))), mean = mean(get(m), na.rm = TRUE)), by = .(GROUP, YEAR)]))[order(measure, GROUP, YEAR)]
fwrite_rounded(electric_vs_other_by_year, file.path(OUT_CSV, "electric_vs_other_by_year.csv"), num_cols = "mean")

# =========================================================================================================
# CSV 3 -- regulatory lag (year t) vs. future violations (year t+1), electric vs. other. Join is strictly
#   prior-period: pipe's YEAR is t, N_VIOLATIONS is pulled from major_synmin's YEAR == t+1 row for the SAME
#   facility -- a facility-year's own-year violations never enter this table.
# =========================================================================================================
future_viol <- maj[ICIS_OBSERVED == 1, .(PGM_SYS_ID, YEAR = YEAR - 1L, N_VIOLATIONS_FUTURE = N_VIOLATIONS)]  # shift YEAR back by 1 so a row labeled YEAR==t carries t+1's N_VIOLATIONS -- joins directly onto pipe's YEAR==t below
lag_future_violations <- merge(pipe, future_viol, by = c("PGM_SYS_ID", "YEAR"))  # inner join: keeps only facility-years with BOTH a non-NA lag at t AND an ICIS-observed t+1 row
lag_future_violations <- merge(lag_future_violations, unique(maj[, .(PGM_SYS_ID, IS_ELECTRIC)]), by = "PGM_SYS_ID")  # attach the facility-level IS_ELECTRIC tag (time-invariant, so any one row per facility gives the same value)
lag_future_violations[, GROUP := factor(group_lab(IS_ELECTRIC), levels = c("electric", "other"))]
n_by_group <- lag_future_violations[, .N, by = GROUP]
cat(sprintf("lag_future_violations: %s facility-years with a non-NA lag(t) + observed N_VIOLATIONS(t+1) join (electric: %s, other: %s)\n",
            format(nrow(lag_future_violations), big.mark = ","),
            n_by_group[GROUP == "electric", N], n_by_group[GROUP == "other", N]))

# quartile bins computed SEPARATELY within each group (electric's much smaller n needs its own cutpoints to
# stay group-balanced -- a single pooled quartile cut would put almost all of electric's 874 rows in one or
# two bins, since electric's own lag distribution needn't line up with other's)
lag_future_violations[, LAG_QUARTILE := cut(MEAN_VIOL_TO_EA_LAG_DAYS,
                                            breaks = quantile(MEAN_VIOL_TO_EA_LAG_DAYS, probs = 0:4 / 4, na.rm = TRUE),
                                            include.lowest = TRUE, labels = c("Q1 (fastest)", "Q2", "Q3", "Q4 (slowest)")), by = GROUP]
lag_bin_summary <- lag_future_violations[, .(n = .N, lag_days_median = median(MEAN_VIOL_TO_EA_LAG_DAYS),
                                             mean_future_violations = mean(N_VIOLATIONS_FUTURE)),
                                         by = .(GROUP, LAG_QUARTILE)][order(GROUP, LAG_QUARTILE)]
fwrite_rounded(lag_future_violations[, .(PGM_SYS_ID, YEAR, GROUP, MEAN_VIOL_TO_EA_LAG_DAYS, LAG_QUARTILE, N_VIOLATIONS_FUTURE)],
               file.path(OUT_CSV, "lag_future_violations.csv"), num_cols = "MEAN_VIOL_TO_EA_LAG_DAYS")
fwrite_rounded(lag_bin_summary, file.path(OUT_CSV, "lag_future_violations_bin_summary.csv"), num_cols = c("lag_days_median", "mean_future_violations"))

# Spearman correlation (rank-based -- appropriate given MEAN_VIOL_TO_EA_LAG_DAYS's heavy right skew, same
# reasoning 18_panel_profile.R's FLAGGED ISSUES gives for preferring median over mean on skewed count data),
# reported per group as a single descriptive summary number alongside the binned view -- NOT a causal estimate
lag_corr <- lag_future_violations[, .(spearman_rho = cor(MEAN_VIOL_TO_EA_LAG_DAYS, N_VIOLATIONS_FUTURE, method = "spearman")), by = GROUP]
cat("\nSpearman rank correlation, lag(t) vs. N_VIOLATIONS(t+1), by group (descriptive only -- see FLAGGED ISSUES)\n")
print(as.data.frame(lag_corr), row.names = FALSE)

# =========================================================================================================
# FIGURES -- print-ready (300dpi), same palette/theme convention as 18_panel_profile.R
# =========================================================================================================
INK <- "#0b0b0b"; INK_SECONDARY <- "#52514e"; GRID <- "#e1e0d9"; AXIS <- "#c3c2b7"
theme_journal <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major = element_line(color = GRID, linewidth = 0.3),
        axis.line = element_line(color = AXIS, linewidth = 0.3),
        axis.ticks = element_line(color = AXIS, linewidth = 0.3),
        text = element_text(color = INK),
        axis.text = element_text(color = INK_SECONDARY),
        plot.title = element_text(face = "bold", size = 12),
        plot.subtitle = element_text(color = INK_SECONDARY, size = 9.5),
        plot.caption = element_text(color = INK_SECONDARY, size = 8, hjust = 0),
        legend.position = "none")
save_fig <- function(name, plot, w = 7.5, h = 4.5) ggsave(file.path(OUT_FIG, name), plot, width = w, height = h, dpi = 300)

MEAS_LABELS <- c(N_INSPECTIONS = "Inspections", N_VIOLATIONS = "Violations", N_HPV = "HPV violations",
                 N_ENFORCEMENT = "Enforcement (pooled)", N_FORMAL = "Formal enforcement",
                 N_INFORMAL = "Informal enforcement", N_CERTS = "Title V certifications",
                 N_STACK_TESTS = "Stack tests", N_PENALTIES = "Penalty actions")  # same measure set/labels/order as 18_panel_profile.R's MEAS_LABELS

# ---- FIGURE 1: mean regulatory activity, electric vs. other, faceted by measure (bar chart) ----------------
bar_data <- copy(electric_vs_other_summary)
bar_data[, measure := factor(MEAS_LABELS[measure], levels = unname(MEAS_LABELS))]
fig1 <- ggplot(bar_data, aes(GROUP, mean, fill = GROUP)) +
  geom_col(width = 0.6) +
  facet_wrap(~measure, nrow = 3, scales = "free_y") +
  scale_fill_manual(values = GROUP_PAL) +
  scale_y_continuous(labels = label_number(accuracy = 0.01)) +
  labs(title = "Mean regulatory activity per ICIS-observed facility-year: electric vs. other, 2015-2025",
       subtitle = "Electric = NAICS 2211 / SIC 4911 (electric_2015_2025's own facility set); other = the rest of\nmajor_synmin. ICIS_OBSERVED == 1 subset, same gate as 18_panel_profile.R's summary_counts.csv",
       x = NULL, y = "Mean count",
       caption = "Source: data/panels/major_synmin_2015_2025.csv.gz, grouped by data/panels/electric_2015_2025.csv.gz membership.") +
  theme_journal + theme(strip.text = element_text(face = "bold", size = 9),
                        plot.subtitle = element_text(color = INK_SECONDARY, size = 8.5, lineheight = 1.1))
save_fig("panel_electric_vs_other_means.png", fig1, w = 9, h = 8)

# ---- FIGURE 2: regulatory intensity over time, electric vs. other, faceted by measure (line chart) ---------
line_data <- copy(electric_vs_other_by_year)
line_data[, measure := factor(MEAS_LABELS[measure], levels = unname(MEAS_LABELS))]
fig2 <- ggplot(line_data, aes(YEAR, mean, color = GROUP)) +
  geom_line(linewidth = 0.9) + geom_point(size = 1.1) +
  facet_wrap(~measure, ncol = 3, scales = "free_y") +
  scale_color_manual(values = GROUP_PAL) +
  scale_x_continuous(breaks = seq(min(YEARS), max(YEARS), 4)) +
  scale_y_continuous(labels = label_number(accuracy = 0.01)) +
  labs(title = "Regulatory intensity over time, electric vs. other, 2015-2025",
       subtitle = "Mean count per ICIS-observed facility-year; same measures/gate as FIGURE 1. Complements\n18_panel_profile.R's panel-vs-panel view (electric_2015_2025 vs. major_synmin_2015_2025 as-is) with\nthe netted-out electric-vs-other-within-major_synmin cut",
       x = NULL, y = "Mean count",
       caption = "Source: data/panels/major_synmin_2015_2025.csv.gz, grouped by data/panels/electric_2015_2025.csv.gz membership.") +
  theme_journal + theme(legend.position = "bottom", legend.title = element_blank(),
                        strip.text = element_text(face = "bold", size = 9),
                        plot.subtitle = element_text(color = INK_SECONDARY, size = 8.5, lineheight = 1.1))
save_fig("panel_electric_vs_other_over_time.png", fig2, w = 9.5, h = 8)

# ---- FIGURE 3: regulatory lag (t) vs. future violations (t+1), binned by within-group lag quartile ----------
end_labels3 <- lag_bin_summary[LAG_QUARTILE == "Q4 (slowest)"]
fig3 <- ggplot(lag_bin_summary, aes(LAG_QUARTILE, mean_future_violations, color = GROUP, group = GROUP)) +
  geom_line(linewidth = 0.9) + geom_point(size = 1.8) +
  scale_color_manual(values = GROUP_PAL) +
  scale_y_continuous(labels = label_number(accuracy = 0.01), limits = c(0, NA)) +
  geom_text(data = end_labels3, aes(label = GROUP), hjust = 0, nudge_x = 0.1, size = 3.2, fontface = "bold") +
  coord_cartesian(clip = "off") +
  labs(title = "Regulatory lag (year t) vs. future violations (year t+1), by within-group lag quartile",
       subtitle = sprintf("n = %s facility-years (electric: %s, other: %s); lag = MEAN_VIOL_TO_EA_LAG_DAYS (pipeline.csv.gz);\nquartile cutpoints computed SEPARATELY within electric/other given electric's much smaller n.\nDescriptive/correlational only -- facilities with long violation-to-EA lags likely differ\nsystematically (case complexity, program mix), so this is not a causal claim about lag itself",
                          format(nrow(lag_future_violations), big.mark = ","), n_by_group[GROUP == "electric", N], n_by_group[GROUP == "other", N]),
       x = "Lag quartile (within group, Q1 = fastest EA)", y = "Mean N_VIOLATIONS, year t+1",
       caption = "Source: data/datasets/pipeline.csv.gz joined to data/panels/major_synmin_2015_2025.csv.gz on (PGM_SYS_ID, YEAR).") +
  theme_journal + theme(plot.margin = margin(t = 5.5, r = 20, b = 5.5, l = 5.5),
                        plot.subtitle = element_text(color = INK_SECONDARY, size = 8.5, lineheight = 1.1))
save_fig("panel_lag_future_violations.png", fig3, w = 7.5, h = 5.5)

# ---- console summary ---------------------------------------------------------------------------------------
cat("\n19_panel_electric_lag_profile.R -- profile summary\n")
cat("================================================================\n\n")
cat("MEAN REGULATORY ACTIVITY, ELECTRIC VS. OTHER (ICIS_OBSERVED subset)\n"); print(as.data.frame(electric_vs_other_summary), row.names = FALSE)
cat("\nLAG(t) VS. FUTURE VIOLATIONS(t+1), BINNED BY WITHIN-GROUP QUARTILE\n"); print(as.data.frame(lag_bin_summary), row.names = FALSE)
cat(sprintf("\n3 figures written to %s:\n  panel_electric_vs_other_means.png, panel_electric_vs_other_over_time.png,\n  panel_lag_future_violations.png\n", OUT_FIG))

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# 1. (IS_ELECTRIC) tagged by membership in electric_2015_2025's facility-ID set, NOT by re-deriving the
#    NAICS-2211/SIC-4911 regex from 03_build_parameters.R -- deliberate, to guarantee this script can't drift
#    from the panel build's actual filter logic, but it does mean this script inherits electric_2015_2025's own
#    build (including its EVER_ACTIVE prefilter) as a black box rather than re-verifying it independently.
# 2. (lag_future_violations join) inner join on (PGM_SYS_ID, YEAR) -- a facility-year is dropped entirely if
#    EITHER MEAN_VIOL_TO_EA_LAG_DAYS(t) is NA (no EA-linked violation that year) OR the t+1 row isn't
#    ICIS_OBSERVED==1 (no ICIS record the following year). The resulting n (12,682 facility-years as of the
#    2026-07-30 build) is NOT representative of the full major_synmin population -- it's conditioned on having
#    BOTH a resolved EA-linked violation this year AND continued ICIS observation next year, which likely
#    selects for larger, more actively-regulated facilities. Don't read FIGURE 3 / lag_bin_summary.csv as
#    describing "the average facility," only this conditioned subpopulation.
# 3. (electric's n=874 in the lag join) small enough that its own quartile cutpoints are noisier than other's
#    11,808 -- FIGURE 3's electric line should be read with wider implied uncertainty than the other line, even
#    though no formal interval is plotted (this is a descriptive figure, not an inferential one).
# 4. (spearman_rho) reported once as a single pooled-within-group descriptive number, not decomposed by year
#    or measure -- a facility-level confound (e.g. large multi-year enforcement cases showing up as both long
#    lag AND high future violations) could produce a positive correlation even with no genuine "slow
#    enforcement causes more violations" mechanism, and this script cannot distinguish the two.
# 5. (MEAN_VIOL_TO_EA_LAG_DAYS itself) inherits pipeline.csv.gz's own definition/caveats verbatim (07_pipeline.R
#    README, PL5 self-disclosure NA-guard, PL2 VIOL_START_DATE-not-SORT_DATE anchor) -- not re-derived or
#    re-verified here. Also note pipeline's N_VIOL_HPV/N_VIOL_FRV split does NOT reconcile with dataset 2's
#    hpv_spells/hpv_active HPV definition (07_pipeline_README.md's "three non-reconciling HPV/FRV definitions"
#    note) -- irrelevant to this script since only the lag column is used, not pipeline's violation-type counts.
