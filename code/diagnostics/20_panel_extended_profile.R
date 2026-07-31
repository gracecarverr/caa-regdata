# =========================================================================================================
# code/diagnostics/20_panel_extended_profile.R -- six more descriptive cuts of the panel layer
#   (data/panels/{major_synmin_2015_2025,electric_2015_2025}.csv.gz), brainstormed as follow-ups to
#   18_panel_profile.R / 19_panel_electric_lag_profile.R rather than duplicating either:
#   (1) concentration -- Lorenz curves + Gini coefficients for N_VIOLATIONS/N_ENFORCEMENT/PENALTY_AMOUNT,
#       summed per facility over its observed years -- how much of total enforcement activity sits with a
#       small share of facilities, and whether that concentration differs electric vs. other.
#   (2) facility exit curve -- cumulative % of facilities with a confirmed EXITED_YEAR, by calendar year.
#   (3) inspection hit rate -- of inspected facility-years, share that found >=1 violation, over time --
#       a size-adjusted companion to the raw enforcement-decline-after-2023 question.
#   (4) self-disclosure share -- of violations linked to a known evaluation, share discovered via
#       self-disclosure rather than inspection, over time (pipeline.csv.gz).
#   (5) state-level enforcement intensity -- mean N_ENFORCEMENT per ICIS-observed facility-year, by STATE.
#   (6) emissions vs. enforcement -- the one genuinely NEW cross-dataset join in this panel-layer line of
#       work: emissions.csv.gz's total criteria-pollutant mass joined to major_synmin, quartile-binned
#       against mean inspections/enforcement -- do bigger emitters get regulated more?
#   All six use the SAME IS_ELECTRIC tag as 19 (membership in electric_2015_2025's facility set, not a
#   re-derived NAICS/SIC regex) and the same electric/other framing throughout.
#
#   in : data/panels/{major_synmin_2015_2025,electric_2015_2025}.csv.gz, data/datasets/pipeline.csv.gz,
#        data/datasets/emissions.csv.gz
#   out: output/panel_profile/{concentration_lorenz,concentration_gini,exit_curve_by_year,
#        inspection_hit_rate_by_year,self_disclosure_share_by_year,state_enforcement_intensity,
#        emissions_enforcement_facility_year,emissions_enforcement_bin_summary}.csv
#        output/figures/panels/panel_{concentration_lorenz,exit_curve,inspection_hit_rate,
#                                      self_disclosure_share,state_enforcement_intensity,
#                                      emissions_enforcement}.png
#
#   Hand-run (not part of RUN_ALL.R, matching every sibling profile script 11-19, code/diagnostics/README.md).
#   No stochastic step. FIGURE DESIGN: same convention as 18/19 (dataviz skill, validated 5-hue categorical
#   palette, 300dpi, direct end-of-line labels for 2-series line charts) -- this script inlines its own copy
#   of the PAL/theme_journal/GROUP_PAL boilerplate, matching how every sibling script repeats it independently
#   rather than sourcing a shared helper file.
# =========================================================================================================
suppressPackageStartupMessages({library(data.table); library(ggplot2); library(scales)})  # data.table for fread/aggregation, ggplot2/scales for the print figures; quietly, to keep the console clean
options(scipen = 999)                                                 # disable scientific notation so large counts/dollars print as plain integers everywhere (console + CSVs)

PANELS   <- here::here("data/panels")                                 # source dir for the two-panel layer
DATASETS <- here::here("data/datasets")                                # source dir for datasets 6 (pipeline) and 7 (emissions)
OUT_CSV  <- here::here("output/panel_profile")                        # shares 18/19's CSV output dir -- same panel layer, same destination
OUT_FIG  <- here::here("output/figures/panels")                       # shares 18/19's figure output dir
dir.create(OUT_CSV, showWarnings = FALSE, recursive = TRUE)           # create if missing, silently if it already exists
dir.create(OUT_FIG, showWarnings = FALSE, recursive = TRUE)

ID_CHAR_COLS <- c("REGISTRY_ID", "ZIP_CODE", "COUNTY_FIPS", "ICIS_COUNTY_FIPS")  # same leading-zero-losing columns as 18/19 -- forced to character on read

# =========================================================================================================
# READ -- major_synmin (base population), electric's facility-ID set (only used to build IS_ELECTRIC, exactly
#   as in 19), and the two external datasets this script joins on (PGM_SYS_ID, YEAR)
# =========================================================================================================
maj <- fread(file.path(PANELS, "major_synmin_2015_2025.csv.gz"), colClasses = list(character = ID_CHAR_COLS))
elec_ids <- unique(fread(file.path(PANELS, "electric_2015_2025.csv.gz"), select = "PGM_SYS_ID")$PGM_SYS_ID)
maj[, IS_ELECTRIC := PGM_SYS_ID %in% elec_ids]
YEARS <- sort(unique(maj$YEAR))                                       # distinct years present (2015:2025 per PB3), NOT hard-coded
group_lab <- function(x) fifelse(x, "electric", "other")             # shared TRUE/FALSE -> display-label mapping (same helper as 19)
maj[, GROUP := factor(group_lab(IS_ELECTRIC), levels = c("electric", "other"))]

GROUP_PAL <- c(electric = "#1baf7a", other = "#2a78d6")               # same two hues as 19_panel_electric_lag_profile.R's GROUP_PAL, kept identical so all three scripts read as one visual family
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
fwrite_rounded <- function(dt, file, num_cols = NULL) {               # shared CSV writer, same rounding convention as 18/19
  d <- copy(dt)
  for (cc in intersect(num_cols, names(d))) d[, (cc) := round(get(cc), 4)]
  fwrite(d, file)
}
fac1 <- function(dt) dt[, .SD[1L], by = PGM_SYS_ID]                   # collapse to one row per facility (18_panel_profile.R's helper, reused verbatim) -- valid here since GROUP/EXITED_YEAR/STATE etc. are all time-invariant per facility

# =========================================================================================================
# FIGURE/CSV 1 -- concentration: Lorenz curves + Gini coefficients, N_VIOLATIONS / N_ENFORCEMENT /
#   PENALTY_AMOUNT, summed per facility over its observed years, electric vs. other
# =========================================================================================================
obs <- maj[ICIS_OBSERVED == 1]                                        # ICIS_OBSERVED==1 gate for the two count measures -- a facility-year with no ICIS record is NA, not a false 0, excluded from the per-facility sum exactly as 18/19 exclude it from means
fac_totals_counts <- obs[, .(N_VIOLATIONS = sum(N_VIOLATIONS), N_ENFORCEMENT = sum(N_ENFORCEMENT), n_obs_years = .N), by = .(PGM_SYS_ID, GROUP)]  # per-facility LIFETIME total, summed only over its ICIS-observed years
fac_totals_penalty <- maj[!is.na(PENALTY_AMOUNT), .(PENALTY_AMOUNT = sum(PENALTY_AMOUNT), n_obs_years = .N), by = .(PGM_SYS_ID, GROUP)]  # PENALTY_AMOUNT's own NA-vs-$0 ambiguity (data/panels/README.md) means this is a SEPARATE non-NA-year gate from the count measures, not the ICIS_OBSERVED one
n_zero_obs_years <- uniqueN(maj$PGM_SYS_ID) - uniqueN(fac_totals_counts$PGM_SYS_ID)  # facilities with ZERO ICIS_OBSERVED years across their whole 11-year rectangle -- structurally excluded from the count-measure Lorenz/Gini below (undefined lifetime total), see FLAGGED ISSUES
cat(sprintf("concentration: %s of %s major_synmin facilities have zero ICIS_OBSERVED years and are excluded from the count-measure Lorenz/Gini (see FLAGGED ISSUES)\n",
            format(n_zero_obs_years, big.mark = ","), format(uniqueN(maj$PGM_SYS_ID), big.mark = ",")))

gini <- function(x) {                                                 # standard discrete Gini coefficient on a non-negative vector (facility lifetime totals, including true zeros)
  x <- sort(as.double(x))                                             # as.double() FIRST -- x/n*sum(x) on ~34k integer facility totals overflows R's 32-bit integer (n * sum(x) silently produced NA for N_ENFORCEMENT/other until this was added, caught by inspecting the console output, not by an assertion)
  n <- length(x)
  if (sum(x) == 0) return(NA_real_)                                   # undefined when every facility totals exactly 0 -- avoids a 0/0
  2 * sum(seq_len(n) * x) / (n * sum(x)) - (n + 1) / n
}
lorenz_points <- function(x) {                                         # cumulative share of facilities (x-axis) vs. cumulative share of the measure's total (y-axis), ascending order -- standard Lorenz-curve construction
  x <- sort(as.double(x))                                             # as.double() -- same integer-overflow risk as gini() above (cumsum() over ~34k large integers)
  n <- length(x)
  data.table(cum_pct_facilities = (0:n) / n, cum_pct_measure = c(0, cumsum(x)) / sum(x))
}
CONC_MEAS <- list(N_VIOLATIONS = fac_totals_counts$N_VIOLATIONS, N_ENFORCEMENT = fac_totals_counts$N_ENFORCEMENT, PENALTY_AMOUNT = fac_totals_penalty$PENALTY_AMOUNT)  # measure name -> its full (both-group) vector, used only for reference; per-group vectors pulled inside the loop below
CONC_SRC <- list(N_VIOLATIONS = fac_totals_counts, N_ENFORCEMENT = fac_totals_counts, PENALTY_AMOUNT = fac_totals_penalty)  # which per-facility table each measure's group column lives in
concentration_lorenz <- rbindlist(lapply(names(CONC_MEAS), function(m) {
  src <- CONC_SRC[[m]]
  rbindlist(lapply(levels(maj$GROUP), function(g) {
    pts <- lorenz_points(src[GROUP == g][[m]])
    pts[, `:=`(measure = m, GROUP = g)][]
  }))
}))
concentration_gini <- rbindlist(lapply(names(CONC_MEAS), function(m) {
  src <- CONC_SRC[[m]]
  rbindlist(lapply(levels(maj$GROUP), function(g) {
    x <- src[GROUP == g][[m]]
    data.table(measure = m, GROUP = g, n_facilities = length(x), gini = gini(x))
  }))
}))
fwrite(concentration_lorenz, file.path(OUT_CSV, "concentration_lorenz.csv"))
fwrite_rounded(concentration_gini, file.path(OUT_CSV, "concentration_gini.csv"), num_cols = "gini")

CONC_LABELS <- c(N_VIOLATIONS = "Violations", N_ENFORCEMENT = "Enforcement (pooled)", PENALTY_AMOUNT = "Penalty $ (naive sum)")  # facet labels; PENALTY_AMOUNT's "naive sum" wording flags the same no-dedup caveat 18's penalty figures carry
lorenz_plot_data <- copy(concentration_lorenz)[, measure := factor(CONC_LABELS[measure], levels = unname(CONC_LABELS))]
gini_labels <- copy(concentration_gini)[, measure := factor(CONC_LABELS[measure], levels = unname(CONC_LABELS))]
fig1 <- ggplot(lorenz_plot_data, aes(cum_pct_facilities, cum_pct_measure, color = GROUP)) +
  geom_abline(intercept = 0, slope = 1, linetype = "dashed", color = AXIS, linewidth = 0.5) +  # 45-degree line of perfect equality, the Lorenz curve's reference
  geom_line(linewidth = 0.9) +
  facet_wrap(~measure, nrow = 1) +
  scale_color_manual(values = GROUP_PAL) +
  scale_x_continuous(labels = label_percent()) + scale_y_continuous(labels = label_percent()) +
  geom_text(data = gini_labels, aes(x = 0.05, y = 0.95 - 0.1 * (GROUP == "other"), label = sprintf("%s Gini=%.2f", GROUP, gini)),
            hjust = 0, size = 2.9, fontface = "bold", show.legend = FALSE) +               # direct in-panel Gini annotation instead of a separate legend/table reference
  labs(title = "Concentration of enforcement activity among facilities, 2015-2025",
       subtitle = "Lorenz curves: cumulative share of facilities (ascending) vs. cumulative share of the lifetime total.\nPer-facility totals summed over ICIS_OBSERVED==1 years (PENALTY_AMOUNT: non-NA years); farther from the\ndashed equality line = more concentrated among few facilities",
       x = "Cumulative % of facilities", y = "Cumulative % of measure total",
       caption = "Source: data/panels/major_synmin_2015_2025.csv.gz, grouped by data/panels/electric_2015_2025.csv.gz membership.") +
  theme_journal + theme(strip.text = element_text(face = "bold", size = 9.5),
                        plot.subtitle = element_text(color = INK_SECONDARY, size = 8.5, lineheight = 1.1))
save_fig("panel_concentration_lorenz.png", fig1, w = 10, h = 4.3)

# =========================================================================================================
# FIGURE/CSV 2 -- facility exit curve: cumulative % of facilities with a confirmed EXITED_YEAR <= Y, by
#   calendar year, electric vs. other
# =========================================================================================================
fac <- fac1(maj)                                                      # one row per facility -- GROUP/EXITED_YEAR are time-invariant, so "first row" is safe (same reasoning as 18's fac1 uses)
exit_curve_by_year <- rbindlist(lapply(YEARS, function(y)
  fac[, .(YEAR = y, pct_exited = mean(!is.na(EXITED_YEAR) & EXITED_YEAR <= y)), by = GROUP]))[order(GROUP, YEAR)]
fwrite_rounded(exit_curve_by_year, file.path(OUT_CSV, "exit_curve_by_year.csv"), num_cols = "pct_exited")

# NOTE: electric/other converge to nearly the same cumulative-exit level by 2025 (10.5% vs. 10.6%), so direct
# end-of-line labels collide -- unlike every other 2-series figure in 18/19/20 where the two lines stay
# visibly separated at the label point. Bottom legend used here instead, deviating from the direct-label
# convention only because the data itself makes end labels illegible for this one figure.
fig2 <- ggplot(exit_curve_by_year, aes(YEAR, pct_exited, color = GROUP)) +
  geom_line(linewidth = 0.9) + geom_point(size = 1.4) +
  scale_color_manual(values = GROUP_PAL) +
  scale_x_continuous(breaks = seq(min(YEARS), max(YEARS), 2)) +
  scale_y_continuous(labels = label_percent(), limits = c(0, NA)) +
  labs(title = "Cumulative facility exit, 2015-2025",
       subtitle = "Share of facilities with a confirmed EXITED_YEAR at or before the x-axis year (ENTERED_YEAR/EXITED_YEAR/\nEXIT_SOURCE, facility-level); right-censored -- facilities with no exit by 2025 may still exit later",
       x = NULL, y = "Cumulative % exited",
       caption = "Source: data/panels/major_synmin_2015_2025.csv.gz, grouped by data/panels/electric_2015_2025.csv.gz membership.") +
  theme_journal + theme(legend.position = "bottom", legend.title = element_blank(),
                        plot.subtitle = element_text(color = INK_SECONDARY, size = 8.5, lineheight = 1.1))
save_fig("panel_exit_curve.png", fig2, w = 8.3, h = 4.8)

# =========================================================================================================
# FIGURE/CSV 3 -- inspection hit rate: of inspected facility-years (ANY_INSPECTIONS==1), share that found
#   >=1 violation (ANY_VIOLATIONS==1), by year, electric vs. other
# =========================================================================================================
inspected <- obs[ANY_INSPECTIONS == 1]                                # ICIS_OBSERVED==1 (via `obs`) AND actually inspected that year -- the population a "hit rate" is meaningful for
inspection_hit_rate_by_year <- inspected[, .(n_inspected = .N, hit_rate = mean(ANY_VIOLATIONS == 1)), by = .(GROUP, YEAR)][order(GROUP, YEAR)]
fwrite_rounded(inspection_hit_rate_by_year, file.path(OUT_CSV, "inspection_hit_rate_by_year.csv"), num_cols = "hit_rate")

end_labels3 <- inspection_hit_rate_by_year[YEAR == max(YEAR)]
fig3 <- ggplot(inspection_hit_rate_by_year, aes(YEAR, hit_rate, color = GROUP)) +
  geom_line(linewidth = 0.9) + geom_point(size = 1.4) +
  scale_color_manual(values = GROUP_PAL) +
  scale_x_continuous(breaks = seq(min(YEARS), max(YEARS), 2), expand = expansion(mult = c(0.02, 0.2))) +
  scale_y_continuous(labels = label_percent(), limits = c(0, NA)) +
  geom_text(data = end_labels3, aes(label = GROUP), hjust = 0, nudge_x = 0.3, size = 3.2, fontface = "bold") +
  coord_cartesian(clip = "off") +
  labs(title = "Inspection hit rate, 2015-2025",
       subtitle = "Of inspected facility-years (ANY_INSPECTIONS==1, ICIS_OBSERVED==1), share finding >=1 violation\n(ANY_VIOLATIONS==1) -- a size-adjusted companion to raw violation/enforcement counts",
       x = NULL, y = "Hit rate (share with >=1 violation)",
       caption = "Source: data/panels/major_synmin_2015_2025.csv.gz, grouped by data/panels/electric_2015_2025.csv.gz membership.") +
  theme_journal + theme(plot.margin = margin(t = 5.5, r = 20, b = 5.5, l = 5.5),
                        plot.subtitle = element_text(color = INK_SECONDARY, size = 8.5, lineheight = 1.1))
save_fig("panel_inspection_hit_rate.png", fig3, w = 8.3, h = 4.8)

# =========================================================================================================
# FIGURE/CSV 4 -- self-disclosure share: of violations linked to a known evaluation (N_VIOL_WITH_EVAL), share
#   discovered via self-disclosure (N_VIOL_SELF_DISCLOSED) rather than inspection, by year, electric vs. other
# =========================================================================================================
pipe_sd <- fread(file.path(DATASETS, "pipeline.csv.gz"), select = c("PGM_SYS_ID", "YEAR", "PIPELINE_OBSERVED", "N_VIOL_SELF_DISCLOSED", "N_VIOL_WITH_EVAL"))
pipe_sd <- pipe_sd[PGM_SYS_ID %in% unique(maj$PGM_SYS_ID) & YEAR %in% YEARS & PIPELINE_OBSERVED == 1]  # restrict to major_synmin facilities and the panel's 2015-2025 window; PIPELINE_OBSERVED==1 gate matches 07_pipeline.R's own zero-vs-NA invariant (counts are non-NA iff observed)
pipe_sd <- merge(pipe_sd, unique(maj[, .(PGM_SYS_ID, GROUP)]), by = "PGM_SYS_ID")  # attach facility-level GROUP
# sum-then-divide (not mean-of-per-facility-ratios) -- avoids small-denominator noise from facility-years with
# only 1-2 linked-evaluation violations, same reasoning 18_panel_profile.R gives for preferring aggregated
# rates over facility-level ratio averages
self_disclosure_share_by_year <- pipe_sd[, .(n_with_eval = sum(N_VIOL_WITH_EVAL), n_self_disclosed = sum(N_VIOL_SELF_DISCLOSED),
                                             share_self_disclosed = sum(N_VIOL_SELF_DISCLOSED) / sum(N_VIOL_WITH_EVAL)), by = .(GROUP, YEAR)][order(GROUP, YEAR)]
fwrite_rounded(self_disclosure_share_by_year, file.path(OUT_CSV, "self_disclosure_share_by_year.csv"), num_cols = "share_self_disclosed")

end_labels4 <- self_disclosure_share_by_year[YEAR == max(YEAR)]
fig4 <- ggplot(self_disclosure_share_by_year, aes(YEAR, share_self_disclosed, color = GROUP)) +
  geom_line(linewidth = 0.9) + geom_point(size = 1.4) +
  scale_color_manual(values = GROUP_PAL) +
  scale_x_continuous(breaks = seq(min(YEARS), max(YEARS), 2), expand = expansion(mult = c(0.02, 0.2))) +
  scale_y_continuous(labels = label_percent(), limits = c(0, NA)) +
  geom_text(data = end_labels4, aes(label = GROUP), hjust = 0, nudge_x = 0.3, size = 3.2, fontface = "bold") +
  coord_cartesian(clip = "off") +
  labs(title = "Self-disclosure share of violations, 2015-2025",
       subtitle = "Of violations linked to a known evaluation (N_VIOL_WITH_EVAL, pipeline.csv.gz), share discovered via\nself-disclosure rather than inspection. Sum-then-divide by year, not mean-of-facility-ratios",
       x = NULL, y = "Share self-disclosed",
       caption = "Source: data/datasets/pipeline.csv.gz, restricted to major_synmin facility-years, grouped by electric_2015_2025.csv.gz membership.") +
  theme_journal + theme(plot.margin = margin(t = 5.5, r = 20, b = 5.5, l = 5.5),
                        plot.subtitle = element_text(color = INK_SECONDARY, size = 8.5, lineheight = 1.1))
save_fig("panel_self_disclosure_share.png", fig4, w = 8.3, h = 4.8)

# =========================================================================================================
# FIGURE/CSV 5 -- state-level enforcement intensity: mean N_ENFORCEMENT per ICIS-observed facility-year, by
#   STATE (facility-level, pooled electric+other -- a 2-group split would double the bar count; all 49
#   states/DC in major_synmin have >=50 facilities, confirmed before writing this script, so none need
#   excluding for a small-n concern)
# =========================================================================================================
state_enforcement_intensity <- obs[!is.na(STATE) & STATE != "", .(n_facilities = uniqueN(PGM_SYS_ID), n_facility_years = .N,
                                                                   mean_enforcement = mean(N_ENFORCEMENT)), by = STATE][order(-mean_enforcement)]
fwrite_rounded(state_enforcement_intensity, file.path(OUT_CSV, "state_enforcement_intensity.csv"), num_cols = "mean_enforcement")

state_plot_data <- copy(state_enforcement_intensity)[, STATE := factor(STATE, levels = rev(STATE))]  # rev() so highest-intensity state plots at the top of the horizontal bar chart
fig5 <- ggplot(state_plot_data, aes(STATE, mean_enforcement)) +
  geom_col(fill = GROUP_PAL[["other"]], width = 0.75) +
  scale_y_continuous(labels = label_number(accuracy = 0.01)) +
  coord_flip() +
  labs(title = "Enforcement intensity by state, 2015-2025",
       subtitle = "Mean N_ENFORCEMENT per ICIS-observed facility-year, all 49 states + DC in major_synmin (pooled\nelectric+other); ranked descending",
       x = NULL, y = "Mean enforcement actions per facility-year",
       caption = "Source: data/panels/major_synmin_2015_2025.csv.gz.") +
  theme_journal + theme(axis.text.y = element_text(size = 6.5),
                        plot.subtitle = element_text(color = INK_SECONDARY, size = 8.5, lineheight = 1.1))
save_fig("panel_state_enforcement_intensity.png", fig5, w = 7.5, h = 9)

# =========================================================================================================
# FIGURE/CSV 6 -- emissions vs. enforcement: does emissions volume relate to regulatory attention? The one
#   genuinely NEW cross-dataset join in this line of work -- no existing script joins emissions.csv.gz to
#   the panel layer. Descriptive/correlational only (same caveat as 19's lag figure): emissions volume and
#   inspection/enforcement intensity plausibly share confounders (facility size, program mix, sector).
# =========================================================================================================
em <- fread(file.path(DATASETS, "emissions.csv.gz"), select = c("PGM_SYS_ID", "YEAR", "EMISSIONS_OBSERVED", "VOC_LBS", "PM10_LBS", "PM25_LBS", "NOX_LBS", "SO2_LBS", "CO_LBS"))
em <- em[PGM_SYS_ID %in% unique(maj$PGM_SYS_ID) & YEAR %in% YEARS & EMISSIONS_OBSERVED == 1]  # restrict to major_synmin facility-years in-window with a real emissions observation
em[, TOTAL_CRITERIA_LBS := VOC_LBS + PM10_LBS + PM25_LBS + NOX_LBS + SO2_LBS + CO_LBS]  # composite criteria-pollutant mass -- GHG_MTCO2E/HAP_LBS deliberately excluded (different units/scale, would need a separate cut)
em <- em[TOTAL_CRITERIA_LBS > 0]                                      # positive-mass facility-years only -- the ~67% at exactly 0 (real, EMISSIONS_OBSERVED==1 zeros, not NA) would otherwise dominate a degenerate "zero" quartile bin, see FLAGGED ISSUES

emissions_enforcement <- merge(em[, .(PGM_SYS_ID, YEAR, TOTAL_CRITERIA_LBS)], maj[ICIS_OBSERVED == 1, .(PGM_SYS_ID, YEAR, GROUP, N_INSPECTIONS, N_ENFORCEMENT)],
                               by = c("PGM_SYS_ID", "YEAR"))          # inner join -- same-year (not lagged) emissions vs. regulatory activity, both gated on their own dataset's observed flag
emissions_enforcement[, EMISSIONS_QUARTILE := cut(TOTAL_CRITERIA_LBS, breaks = quantile(TOTAL_CRITERIA_LBS, probs = 0:4 / 4),
                                                  include.lowest = TRUE, labels = c("Q1 (lowest)", "Q2", "Q3", "Q4 (highest)")), by = GROUP]  # quartile cutpoints computed SEPARATELY within electric/other, same reasoning as 19's lag quartiles (electric's emissions distribution needn't line up with other's)
fwrite_rounded(emissions_enforcement, file.path(OUT_CSV, "emissions_enforcement_facility_year.csv"), num_cols = "TOTAL_CRITERIA_LBS")

emissions_enforcement_bin_summary <- rbindlist(lapply(c("N_INSPECTIONS", "N_ENFORCEMENT"), function(m)
  emissions_enforcement[, .(measure = m, n = .N, emissions_median_lbs = median(TOTAL_CRITERIA_LBS), mean_value = mean(get(m))), by = .(GROUP, EMISSIONS_QUARTILE)]))[order(measure, GROUP, EMISSIONS_QUARTILE)]
fwrite_rounded(emissions_enforcement_bin_summary, file.path(OUT_CSV, "emissions_enforcement_bin_summary.csv"), num_cols = c("emissions_median_lbs", "mean_value"))

ee_plot_data <- copy(emissions_enforcement_bin_summary)
ee_plot_data[, measure := factor(c(N_INSPECTIONS = "Inspections", N_ENFORCEMENT = "Enforcement (pooled)")[measure], levels = c("Inspections", "Enforcement (pooled)"))]
fig6 <- ggplot(ee_plot_data, aes(EMISSIONS_QUARTILE, mean_value, color = GROUP, group = GROUP)) +
  geom_line(linewidth = 0.9) + geom_point(size = 1.8) +
  facet_wrap(~measure, scales = "free_y") +
  scale_color_manual(values = GROUP_PAL) +
  scale_y_continuous(labels = label_number(accuracy = 0.01), limits = c(0, NA)) +
  labs(title = "Emissions volume vs. regulatory activity, same facility-year, 2015-2025",
       subtitle = sprintf("n = %s facility-years (positive-mass, EMISSIONS_OBSERVED==1 & ICIS_OBSERVED==1); emissions =\nVOC+PM10+PM25+NOX+SO2+CO (lbs); quartile cutpoints computed SEPARATELY within electric/other.\nDescriptive/correlational only -- emissions volume and regulatory attention plausibly share\nconfounders (facility size, program mix), so this is not a causal claim",
                          format(nrow(emissions_enforcement), big.mark = ",")),
       x = "Emissions quartile (within group)", y = "Mean count",
       caption = "Source: data/datasets/emissions.csv.gz joined to data/panels/major_synmin_2015_2025.csv.gz on (PGM_SYS_ID, YEAR).") +
  theme_journal + theme(legend.position = "bottom", legend.title = element_blank(),
                        strip.text = element_text(face = "bold", size = 9.5),
                        plot.subtitle = element_text(color = INK_SECONDARY, size = 8.5, lineheight = 1.1))
save_fig("panel_emissions_enforcement.png", fig6, w = 9, h = 5)

# ---- console summary ---------------------------------------------------------------------------------------
cat("\n20_panel_extended_profile.R -- profile summary\n")
cat("================================================================\n\n")
cat("CONCENTRATION (Gini coefficients)\n"); print(as.data.frame(concentration_gini), row.names = FALSE)
cat("\nFACILITY EXIT CURVE (final year)\n"); print(as.data.frame(exit_curve_by_year[YEAR == max(YEAR)]), row.names = FALSE)
cat("\nINSPECTION HIT RATE (final year)\n"); print(as.data.frame(inspection_hit_rate_by_year[YEAR == max(YEAR)]), row.names = FALSE)
cat("\nSELF-DISCLOSURE SHARE (final year)\n"); print(as.data.frame(self_disclosure_share_by_year[YEAR == max(YEAR)]), row.names = FALSE)
cat("\nSTATE ENFORCEMENT INTENSITY (top 5)\n"); print(as.data.frame(head(state_enforcement_intensity, 5)), row.names = FALSE)
cat("\nEMISSIONS VS. ENFORCEMENT (bin summary)\n"); print(as.data.frame(emissions_enforcement_bin_summary), row.names = FALSE)
cat(sprintf("\n6 figures written to %s:\n  panel_concentration_lorenz.png, panel_exit_curve.png, panel_inspection_hit_rate.png,\n  panel_self_disclosure_share.png, panel_state_enforcement_intensity.png, panel_emissions_enforcement.png\n", OUT_FIG))

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# 1. (concentration, FIGURE/CSV 1) facilities with ZERO ICIS_OBSERVED years across their whole 11-year
#    rectangle are excluded from the count-measure (N_VIOLATIONS/N_ENFORCEMENT) Lorenz curve/Gini -- their
#    lifetime total is genuinely undefined (no observed year to sum), not 0. The console prints this count
#    each run since it depends on the live build. PENALTY_AMOUNT uses a separate, independent non-NA-year
#    gate (its own NA-vs-exactly-$0 ambiguity, data/panels/README.md) -- the two measures' excluded-facility
#    sets are NOT the same population, so don't compare their Gini coefficients as if drawn from identical
#    denominators.
# 2. (concentration) "lifetime total" sums only OBSERVED years, not true lifetime activity -- a facility
#    entering the panel in 2023 has only 3 possible observed years to contribute to its total vs. a facility
#    present since 2015, understating apparent activity for late entrants relative to long-tenured facilities.
#    This is a real limitation of using the 2015-2025 window as a lifetime proxy, not a bug.
# 3. (exit curve, FIGURE/CSV 2) right-censored by construction -- a facility with no confirmed exit by 2025
#    may still exit afterward; this curve describes exits CONFIRMED so far, not eventual lifetime exit risk.
#    Same caveat 18_panel_profile.R's entry_exit_summary.csv already carries, just shown over time here.
# 4. (inspection hit rate, FIGURE/CSV 3) conditions on ANY_INSPECTIONS==1 -- if which facilities get
#    inspected changed over time (e.g., inspections increasingly targeted at higher-risk facilities), a
#    rising hit rate could reflect better TARGETING rather than more violations conditional on inspection
#    effort holding constant. This figure can't distinguish the two.
# 5. (self-disclosure share, FIGURE/CSV 4) electric/2015 has n_with_eval==0 (zero linked-evaluation
#    violations that year), making share_self_disclosed a genuine 0/0 -> NA -- correctly plotted as a gap in
#    the line (ggplot's "Removed 1 row" warning on this figure is this single expected case, not a bug).
# 6. (self-disclosure share, FIGURE/CSV 4) restricted to major_synmin facility-years within the panel's
#    2015-2025 window, unlike 16_pipeline_profile.R's own self-disclosure figures which use the FULL
#    2005-2025 ICIS universe -- levels here are not directly comparable to that script's numbers, by design
#    (this script stays within the panel-layer population the rest of 18/19/20 use).
# 7. (emissions vs. enforcement, FIGURE/CSV 6) same-year (not lagged) join -- a facility inspected heavily
#    in a given year might report DIFFERENT emissions that same year for reasons unrelated to the inspection
#    (e.g. a shutdown), so causality could run either direction or not at all; purely a same-year descriptive
#    association. Also: TOTAL_CRITERIA_LBS excludes GHG_MTCO2E and HAP_LBS (different units/scale) -- a
#    facility that's a heavy GHG or HAP emitter but a light criteria-pollutant emitter would be classified by
#    this figure as "low emissions," which may not match how a reader would otherwise categorize it.
