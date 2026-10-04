# =========================================================================================================
# code/diagnostics/21_panel_agency_recidivism_profile.R -- two more descriptive cuts of the panel layer
#   (data/panels/{major_synmin_2015_2025,electric_2015_2025}.csv.gz), the two judged most likely to reveal
#   something non-obvious out of the six brainstormed for 20_panel_extended_profile.R:
#   (1) agency share -- N_INSP_EPA/STATE/LOCAL and N_ENF_EPA/STATE/LOCAL (in the panel already, unused by
#       every script through 20) partition N_INSPECTIONS/N_ENFORCEMENT exactly. Who is actually doing the
#       regulating, and has that mix shifted around the post-2023 enforcement decline noted in 20's §11
#       hit-rate discussion? Computed pooled across major_synmin (electric+other) -- an institutional "who
#       enforces" question about the whole regulated population, not a group comparison; 3 agencies x 2
#       groups per facet would be unreadable, same pooling rationale as 20's state-intensity figure.
#   (2) recidivism -- does 20's §11 concentration finding (enforcement activity concentrated in a small share
#       of facilities) reflect the SAME facilities recurring year after year, or a DIFFERENT small set each
#       year? P(ANY_VIOLATIONS==1 at t+k | ANY_VIOLATIONS status at t), k=1,2,3, electric vs. other.
#   Both purely descriptive/correlational: persistence could reflect genuine chronic noncompliance, or could
#   partly reflect facilities that are simply inspected more often (more chances to find a violation in any
#   given window) -- this script cannot separate the two.
#
#   in : data/panels/{major_synmin_2015_2025,electric_2015_2025}.csv.gz
#   out: output/panel_profile/{agency_share_by_year,recidivism_by_lag}.csv
#        output/figures/panels/panel_{agency_share_over_time,recidivism}.png
#
#   Hand-run (not part of RUN_ALL.R, matching every sibling profile script 11-20, code/diagnostics/README.md).
#   No stochastic step. FIGURE DESIGN: same convention as 18-20 (dataviz skill, validated 5-hue categorical
#   palette, 300dpi) -- this script inlines its own copy of the PAL/theme_journal/GROUP_PAL boilerplate,
#   matching how every sibling script repeats it independently rather than sourcing a shared helper file.
# =========================================================================================================
suppressPackageStartupMessages({library(data.table); library(ggplot2); library(scales)})  # data.table for fread/aggregation, ggplot2/scales for the print figures; quietly, to keep the console clean
options(scipen = 999)                                                 # disable scientific notation so large counts print as plain integers everywhere (console + CSVs)

PANELS  <- here::here("data/panels")                                  # source dir for the two-panel layer
OUT_CSV <- here::here("output/panel_profile")                         # shares 18-20's CSV output dir -- same panel layer, same destination
OUT_FIG <- here::here("output/figures/panels")                        # shares 18-20's figure output dir
dir.create(OUT_CSV, showWarnings = FALSE, recursive = TRUE)           # create if missing, silently if it already exists
dir.create(OUT_FIG, showWarnings = FALSE, recursive = TRUE)

ID_CHAR_COLS <- c("REGISTRY_ID", "ZIP_CODE", "COUNTY_FIPS", "ICIS_COUNTY_FIPS")  # same leading-zero-losing columns as 18-20 -- forced to character on read

# =========================================================================================================
# READ -- major_synmin (base population) + electric's facility-ID set (only used to build IS_ELECTRIC, exactly
#   as in 19/20, not re-derived)
# =========================================================================================================
maj <- fread(file.path(PANELS, "major_synmin_2015_2025.csv.gz"), colClasses = list(character = ID_CHAR_COLS))
elec_ids <- unique(fread(file.path(PANELS, "electric_2015_2025.csv.gz"), select = "PGM_SYS_ID")$PGM_SYS_ID)
maj[, IS_ELECTRIC := PGM_SYS_ID %in% elec_ids]
YEARS <- sort(unique(maj$YEAR))                                       # distinct years present (2015:2025 per PB3), NOT hard-coded
group_lab <- function(x) fifelse(x, "electric", "other")             # shared TRUE/FALSE -> display-label mapping (same helper as 19/20)
maj[, GROUP := factor(group_lab(IS_ELECTRIC), levels = c("electric", "other"))]

GROUP_PAL <- c(electric = "#1baf7a", other = "#2a78d6")               # same two hues as 19/20's GROUP_PAL, kept identical so all scripts read as one visual family
AGENCY_PAL <- c(EPA = "#e34948", state = "#2a78d6", local = "#eda100")  # red/blue/yellow -- distinct 3-way palette for Figure 1's agency lines (not a GROUP comparison, so GROUP_PAL doesn't apply here)
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
fwrite_rounded <- function(dt, file, num_cols = NULL) {               # shared CSV writer, same rounding convention as 18-20
  d <- copy(dt)
  for (cc in intersect(num_cols, names(d))) d[, (cc) := round(get(cc), 4)]
  fwrite(d, file)
}

# =========================================================================================================
# FIGURE/CSV 1 -- agency share: EPA/state/local share of total inspections and enforcement actions, by year,
#   pooled across major_synmin (electric+other) -- verified before writing this script that
#   N_INSP_EPA+N_INSP_STATE+N_INSP_LOCAL == N_INSPECTIONS and the N_ENF_* analogue holds exactly, no NA, on
#   the ICIS_OBSERVED==1 subset used throughout 18-20
# =========================================================================================================
obs <- maj[ICIS_OBSERVED == 1]                                        # ICIS_OBSERVED==1 gate -- a facility-year with no ICIS record is NA, not a false 0, excluded exactly as 18-20 exclude it
agency_sums_by_year <- obs[, .(insp_epa = sum(N_INSP_EPA), insp_state = sum(N_INSP_STATE), insp_local = sum(N_INSP_LOCAL),
                               enf_epa = sum(N_ENF_EPA), enf_state = sum(N_ENF_STATE), enf_local = sum(N_ENF_LOCAL)), by = YEAR][order(YEAR)]
agency_share_by_year <- rbindlist(list(
  agency_sums_by_year[, .(measure = "N_INSPECTIONS", YEAR, EPA = insp_epa, state = insp_state, local = insp_local,
                          total = insp_epa + insp_state + insp_local)],
  agency_sums_by_year[, .(measure = "N_ENFORCEMENT", YEAR, EPA = enf_epa, state = enf_state, local = enf_local,
                          total = enf_epa + enf_state + enf_local)]
))
agency_share_by_year <- melt(agency_share_by_year, id.vars = c("measure", "YEAR", "total"), measure.vars = c("EPA", "state", "local"),
                             variable.name = "AGENCY", value.name = "n")  # long format: one row per measure x year x agency, n = raw count, total = that year/measure's grand total (for recovering counts from shares downstream)
agency_share_by_year[, share := n / total]
fwrite_rounded(agency_share_by_year, file.path(OUT_CSV, "agency_share_by_year.csv"), num_cols = "share")

MEAS_LABELS_1 <- c(N_INSPECTIONS = "Inspections", N_ENFORCEMENT = "Enforcement (pooled)")
agency_plot_data <- copy(agency_share_by_year)[, measure := factor(MEAS_LABELS_1[measure], levels = unname(MEAS_LABELS_1))]
end_labels1 <- agency_plot_data[YEAR == max(YEAR)]
fig1 <- ggplot(agency_plot_data, aes(YEAR, share, color = AGENCY)) +
  geom_line(linewidth = 0.9) + geom_point(size = 1.4) +
  facet_wrap(~measure) +
  scale_color_manual(values = AGENCY_PAL) +
  scale_x_continuous(breaks = seq(min(YEARS), max(YEARS), 4), expand = expansion(mult = c(0.02, 0.28))) +
  scale_y_continuous(labels = label_percent(), limits = c(0, NA)) +
  geom_text(data = end_labels1, aes(label = AGENCY), hjust = 0, nudge_x = 0.3, size = 3.1, fontface = "bold") +
  coord_cartesian(clip = "off") +
  labs(title = "Who enforces: EPA vs. state vs. local share of activity, 2015-2025",
       subtitle = "Share of the year's total inspections/enforcement actions by responsible agency (N_INSP_*/N_ENF_*,\nICIS_OBSERVED==1 subset), pooled across major_synmin (electric+other)",
       x = NULL, y = "Share of total",
       caption = "Source: data/panels/major_synmin_2015_2025.csv.gz.") +
  theme_journal + theme(plot.margin = margin(t = 5.5, r = 24, b = 5.5, l = 5.5),
                        strip.text = element_text(face = "bold", size = 9.5),
                        plot.subtitle = element_text(color = INK_SECONDARY, size = 8.5, lineheight = 1.1))
save_fig("panel_agency_share_over_time.png", fig1, w = 9.5, h = 4.8)

# =========================================================================================================
# FIGURE/CSV 2 -- recidivism: P(ANY_VIOLATIONS==1 at t+k | ANY_VIOLATIONS status at t), k=1,2,3, electric vs.
#   other, against each group's unconditional baseline rate
# =========================================================================================================
viol <- obs[, .(PGM_SYS_ID, YEAR, GROUP, ANY_VIOLATIONS)]             # ICIS_OBSERVED==1 subset (via `obs`) -- ANY_VIOLATIONS is only meaningful where an ICIS record could have shown one
baseline_rate <- viol[, .(baseline = mean(ANY_VIOLATIONS == 1)), by = GROUP]  # unconditional P(violation), each group's own reference point -- NOT pooled, since 20's §11 already showed electric/other differ on raw violation levels

recidivism_by_lag <- rbindlist(lapply(1:3, function(k) {
  future <- copy(viol)[, .(PGM_SYS_ID, YEAR = YEAR - k, ANY_VIOLATIONS_FUTURE = ANY_VIOLATIONS)]  # shift YEAR back by k so a row labeled YEAR==t carries t+k's violation status -- joins directly onto viol's YEAR==t below, same year-shift pattern as 19's lag-vs-future-violations join
  m <- merge(viol, future, by = c("PGM_SYS_ID", "YEAR"))              # inner join -- keeps only facility-years with BOTH an ICIS-observed status at t and at t+k
  m[, .(k = k, n = .N, rate = mean(ANY_VIOLATIONS_FUTURE == 1)), by = .(GROUP, PRIOR_VIOLATION = ANY_VIOLATIONS == 1)]
}))
fwrite_rounded(merge(recidivism_by_lag, baseline_rate, by = "GROUP"), file.path(OUT_CSV, "recidivism_by_lag.csv"), num_cols = c("rate", "baseline"))

recidivism_plot_data <- copy(recidivism_by_lag)[, prior_lab := fifelse(PRIOR_VIOLATION, "had violation at t", "no violation at t")]
fig2 <- ggplot(recidivism_plot_data, aes(factor(k), rate, color = prior_lab, group = prior_lab)) +
  geom_hline(data = baseline_rate, aes(yintercept = baseline), linetype = "dashed", color = AXIS, linewidth = 0.5) +  # each facet's own unconditional baseline rate, for reference
  geom_line(linewidth = 0.9) + geom_point(size = 1.8) +
  facet_wrap(~GROUP) +
  scale_color_manual(values = c("had violation at t" = "#e34948", "no violation at t" = "#2a78d6")) +
  scale_y_continuous(labels = label_percent(), limits = c(0, NA)) +
  labs(title = "Repeat-offender persistence: does a violation today predict one later?",
       subtitle = "P(ANY_VIOLATIONS==1 at t+k | violation status at t), k=1..3 years later, ICIS_OBSERVED==1 both periods.\nDashed line = each group's unconditional violation rate. Descriptive/correlational -- persistence could reflect\nchronic noncompliance, or simply facilities inspected more often (more chances to find a violation)",
       x = "Years later (k)", y = "P(violation at t+k)",
       caption = "Source: data/panels/major_synmin_2015_2025.csv.gz, grouped by data/panels/electric_2015_2025.csv.gz membership.") +
  theme_journal + theme(legend.position = "bottom", legend.title = element_blank(),
                        strip.text = element_text(face = "bold", size = 9.5),
                        plot.subtitle = element_text(color = INK_SECONDARY, size = 8.5, lineheight = 1.1))
save_fig("panel_recidivism.png", fig2, w = 8.5, h = 4.8)

# ---- console summary ---------------------------------------------------------------------------------------
cat("\n21_panel_agency_recidivism_profile.R -- profile summary\n")
cat("================================================================\n\n")
cat("AGENCY SHARE (final year)\n"); print(as.data.frame(agency_share_by_year[YEAR == max(YEAR)]), row.names = FALSE)
cat("\nRECIDIVISM (baseline rates)\n"); print(as.data.frame(baseline_rate), row.names = FALSE)
cat("\nRECIDIVISM (conditional rates by lag)\n"); print(as.data.frame(recidivism_by_lag[order(GROUP, k, -PRIOR_VIOLATION)]), row.names = FALSE)
cat(sprintf("\n2 figures written to %s:\n  panel_agency_share_over_time.png, panel_recidivism.png\n", OUT_FIG))

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# 1. (agency share, FIGURE/CSV 1) pooled across electric+other -- a group-level asymmetry in agency mix (e.g.
#    if electric facilities are disproportionately EPA-inspected relative to other) would be invisible in this
#    figure; categorical_frequency.csv (18)/electric_vs_other_summary.csv (19) give the group-level activity
#    totals this figure doesn't decompose by agency.
# 2. (agency share) a facility-year's inspections/enforcement could in principle involve MULTIPLE agencies
#    (e.g. a joint EPA+state inspection); N_INSP_EPA/STATE/LOCAL sum exactly to N_INSPECTIONS by construction
#    (verified before writing this script), so this dataset's own convention attributes each inspection/
#    enforcement record to exactly one agency -- this script inherits that attribution rule from
#    01_regulatory.R/02_operating.R unchanged, not re-derived or re-verified at the row level here.
# 3. (recidivism, FIGURE/CSV 2) inner join on (PGM_SYS_ID, YEAR) for each k -- a facility-year is dropped from
#    a given k's calculation entirely if either t or t+k isn't ICIS_OBSERVED==1. Facilities that exit the
#    panel are therefore under-represented in the LARGER-k persistence estimates specifically (less chance to
#    still be observed k years later), not a uniform sample of all facility-years at every k.
# 4. (recidivism) cannot distinguish genuine chronic noncompliance from a facility simply being inspected more
#    often in both periods (more inspection opportunities mechanically raises the chance of finding a
#    violation in any window, independent of the facility's underlying compliance behavior) -- same
#    inspection-frequency confound noted in 20_panel_extended_profile.R's inspection-hit-rate FLAGGED ISSUES.
# 5. (recidivism) ANY_VIOLATIONS is a binary (>=1 violation) flag, not a count -- a facility with 1 violation
#    and a facility with 20 in the same year are treated identically here; 20's concentration/Gini figure is
#    the companion view for volume, this one is purely about presence/absence and its persistence over time.
