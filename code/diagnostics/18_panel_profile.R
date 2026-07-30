# =========================================================================================================
# code/diagnostics/18_panel_profile.R -- exploratory profiling of the panel layer
#   (data/panels/{major_synmin_2015_2025,electric_2015_2025}.csv.gz), built by
#   code/04_panel_building/. Purpose: characterize both panels for a reader picking the project up cold --
#   coverage, count-measure distributions, HPV/penalty summaries, geography, and the electric-is-a-subset-of-
#   major_synmin relationship the two panels are built to share. Companion to 11_operating_profile.R ..
#   17_emissions_profile.R (same discipline, one layer up -- these are dataset-layer profiles, this is the
#   panel-layer profile). Fills the gap left when the OLD panel-layer profiles (06_panel_profile.R,
#   06b_panel_deep_stats.R, 07_majsyn_operating_profile.R) were archived on 2026-07-28 along with the old
#   panel-building pipeline they profiled -- see archive/panel_building_legacy/README.md. This script profiles
#   the NEW two-panel structure from scratch; it is not a revival of the archived scripts.
#
#   in : data/panels/{major_synmin_2015_2025,electric_2015_2025}.csv.gz
#   out: output/panel_profile/*.csv (incl. mean_counts_by_year.csv)
#        output/figures/panels/panel_{coverage_over_time,hpv_active_over_time,count_distributions,
#                                      penalty_dist,state_composition,facility_count_over_time,
#                                      mean_counts_over_time,violations_enforcement}.png
#
#   DISCIPLINE (REVISED 2026-07-29, PB2's eligibility-rule change): both panels are eligibility-screened on
#   ACTIVE_BROAD==1 in AT LEAST ONE of the 11 years (PB2 in briefs/panel/panel_construction_decisions.md), not
#   every year as before -- so OBS_SOURCE=="unobserved" is now a REAL, EXPECTED value (a facility can be
#   eligible via one qualifying year while other years in its 11-year rectangle have no confirmed activity),
#   not an impossible one. Every table/figure below that touches OBS_SOURCE treats "unobserved" as a normal
#   category to report, not a build-defect signal to warn on. N_* count measures still follow the dataset
#   layer's zero-vs-NA gate (ICIS_OBSERVED==1 -- a facility-year with no ICIS record that year is NA, not a
#   false 0); every summary below is computed on the ICIS_OBSERVED==1 subset and reports the NA share.
#   PENALTY_AMOUNT is NA-if-none-OR-if-summed-to-exactly-$0 (data/panels/README.md's own documented ambiguity,
#   inherited unchanged here -- NOT re-derived or disambiguated by this script). No numbers are hand-entered;
#   every cell/figure is computed here. Hand-run (not part of RUN_ALL.R, matching every sibling profile
#   script -- see code/diagnostics/README.md). No stochastic step.
#
#   FIGURE DESIGN (dataviz skill, static/print variant -- no hover/dark-mode, those are screen-only concerns):
#   validated 5-hue categorical palette (blue/aqua/green/violet slots), one axis per chart, thin 2px lines,
#   muted gridlines, 300dpi for print, direct end-of-line labels instead of a legend where there are few series.
# =========================================================================================================
suppressPackageStartupMessages({library(data.table); library(ggplot2); library(scales)})  # data.table for the aggregation, ggplot2/scales for the print figures; quietly, to keep the console clean
options(scipen = 999)                                                 # disable scientific notation so large counts print as plain integers everywhere (console + CSVs)

PANELS  <- here::here("data/panels")                                  # source dir for the two-panel layer
OUT_CSV <- here::here("output/panel_profile")                         # destination for every computed CSV below
OUT_FIG <- here::here("output/figures/panels")                        # destination for every PNG figure below
dir.create(OUT_CSV, showWarnings = FALSE, recursive = TRUE)           # create if missing, silently if it already exists
dir.create(OUT_FIG, showWarnings = FALSE, recursive = TRUE)

# ID/FIPS-like columns that can carry a leading zero -- fread guesses these as numeric by default and
# silently drops the leading zero (e.g. "01001" -> 1001) unless forced to character. Same set as
# 13_regulatory_profile.R (REGISTRY_ID, ZIP_CODE) plus 15_coordinates_profile.R (COUNTY_FIPS,
# ICIS_COUNTY_FIPS) -- this file joins both of those datasets' columns, so it forces both sets. PGM_SYS_ID is
# NOT forced: it's alphanumeric (e.g. "TX0000012345"), so fread already infers it as character.
ID_CHAR_COLS <- c("REGISTRY_ID", "ZIP_CODE", "COUNTY_FIPS", "ICIS_COUNTY_FIPS")

PANEL_FILES <- c(major_synmin = "major_synmin_2015_2025.csv.gz",  # named vector: short panel label -> file name, used throughout to read/tag/label consistently
                 electric     = "electric_2015_2025.csv.gz")
PANEL_LEVELS <- names(PANEL_FILES)                                    # fixed display/plot order: major_synmin first (the larger, less-restricted panel), electric second (its subset)

read_panel <- function(label, file) {                                 # read one panel file and tag every row with its panel label
  dt <- fread(file.path(PANELS, file), colClasses = list(character = ID_CHAR_COLS))
  dt[, panel := label]                                                # tag column, used to split/compare/facet everywhere below
  dt
}
panels_list <- Map(read_panel, PANEL_LEVELS, unname(PANEL_FILES))     # named list: panels_list$major_synmin, panels_list$electric -- kept separate (not just the stacked version) since several CSVs below operate on one panel at a time
all_panels <- rbindlist(panels_list, use.names = TRUE)                # stacked long table (identical 116-col schema on both sides, per code/04_panel_building/README.md's "same recipe" design) -- used for every per-panel-comparison table/figure
all_panels[, panel := factor(panel, levels = PANEL_LEVELS)]           # fix factor order for consistent table/legend ordering downstream
YEARS <- sort(unique(all_panels$YEAR))                                # distinct years present (should be 2015:2025 per PB3), NOT hard-coded

fwrite_rounded <- function(dt, file, prop_cols = NULL, num_cols = NULL) {  # shared CSV writer, identical convention to 11-17_*_profile.R
  d <- copy(dt)                                                       # copy first so rounding below doesn't mutate the caller's table in place
  for (cc in intersect(prop_cols, names(d))) d[, (cc) := round(get(cc), 3)]  # proportions rounded to 3 decimals
  for (cc in intersect(num_cols,  names(d))) d[, (cc) := round(get(cc), 2)]  # other numeric columns (e.g. means) rounded to 2 decimals
  fwrite(d, file)
}
fac1 <- function(dt) dt[, .SD[1L], by = PGM_SYS_ID]                   # collapse a panel to one row per facility (first row encountered) -- used for every facility-level (not facility-year-level) summary below; every panel row for a given facility shares the same time-invariant attributes (STATE, AIR_POLLUTANT_CLASS_DESC, etc.), so which row is "first" doesn't matter for those columns

# =========================================================================================================
# CSV 1 -- overview, both panels
# =========================================================================================================
overview <- all_panels[, .(n_facilities = uniqueN(PGM_SYS_ID), n_facility_years = .N,
                           year_min = min(YEAR), year_max = max(YEAR)), by = panel]
overview[, balanced := n_facility_years == n_facilities * length(YEARS)]  # sanity check: is each panel a full facility x year rectangle -- should be TRUE by construction (build_panel()'s expand_grid always gives every eligible facility a full 11-year rectangle, PB3; NOT a claim that every year has confirmed activity -- see coverage_by_year's pct_unobserved for that)
fwrite(overview, file.path(OUT_CSV, "overview.csv"))

# =========================================================================================================
# CSV 2 -- OBS_SOURCE composition by year, both panels (coverage: event vs. operating vs. unobserved)
# =========================================================================================================
coverage_by_year <- all_panels[, .(n_facility_years = .N, pct_event = mean(OBS_SOURCE == "event"),
                                   pct_operating = mean(OBS_SOURCE == "operating"),
                                   pct_unobserved = mean(OBS_SOURCE == "unobserved")),  # REVISED 2026-07-29 (PB2): no longer expected to be 0 -- the eligibility screen only requires ACTIVE_BROAD==1 in >=1 of the 11 years, so a facility-year outside its qualifying year(s) can genuinely have no confirmed activity. A real, informative share now, not a build-defect signal (contrast the pre-2026-07-29 version of this file, which warned on any nonzero value here).
                                by = .(panel, YEAR)][order(panel, YEAR)]
n_unobserved <- sum(coverage_by_year$n_facility_years * coverage_by_year$pct_unobserved)  # total facility-years with OBS_SOURCE=="unobserved", across both panels -- expected to be > 0 under the >=1-year eligibility rule
cat(sprintf("coverage_by_year: %s facility-years have OBS_SOURCE=='unobserved' across both panels (expected under the >=1-year eligibility rule, PB2)\n", format(round(n_unobserved), big.mark = ",")))
fwrite_rounded(coverage_by_year, file.path(OUT_CSV, "coverage_by_year.csv"),
               prop_cols = c("pct_event", "pct_operating", "pct_unobserved"))

# =========================================================================================================
# CSV 3 -- five-number summaries for key N_* count measures, ICIS_OBSERVED subset, both panels
# =========================================================================================================
COUNT_COLS <- c("N_INSPECTIONS", "N_VIOLATIONS", "N_HPV", "N_ENFORCEMENT", "N_FORMAL", "N_INFORMAL",
                "N_CERTS", "N_STACK_TESTS", "N_PENALTIES")            # same measure list as 13_regulatory_profile.R's CSV 3 -- these columns ride along on the panel unchanged from data/datasets/regulatory.csv.gz
summarise_measure <- function(dt, label, m) {
  x_all <- dt[[m]]; x <- dt[ICIS_OBSERVED == 1][[m]]; x <- x[!is.na(x)]  # x_all = column over ALL rows of this panel (denominator for pct_na); x = column over the ICIS_OBSERVED==1 subset, NA-dropped defensively
  data.table(panel = label, measure = m, n_obs = length(x), pct_na = mean(is.na(x_all)),  # pct_na's denominator is the WHOLE panel (x_all), not n_obs -- same convention/caveat as 13_regulatory_profile.R's summarise_measure(), see FLAGGED ISSUES
             min = min(x), p25 = quantile(x, .25), median = median(x), p75 = quantile(x, .75),
             p99 = quantile(x, .99), max = max(x), mean = mean(x), pct_zero = mean(x == 0))
}
summary_counts <- rbindlist(lapply(PANEL_LEVELS, function(p)
  rbindlist(lapply(COUNT_COLS, function(m) summarise_measure(panels_list[[p]], p, m)))))  # one row per panel x measure, stacked
fwrite_rounded(summary_counts, file.path(OUT_CSV, "summary_counts.csv"),
               prop_cols = c("pct_na", "pct_zero"), num_cols = "mean")

# =========================================================================================================
# CSV 4 -- HPV_ACTIVE prevalence by year, both panels (H6 zero-vs-NA discipline: NA is unknown, never a
#   false 0 -- mirrors 14_hpv_profile.R's active_rate_by_year.csv)
# =========================================================================================================
hpv_active_by_year <- all_panels[, .(n_facility_years = .N, n_known = sum(!is.na(HPV_ACTIVE)),
                                     n_active = sum(HPV_ACTIVE == 1, na.rm = TRUE)),
                                 by = .(panel, YEAR)][order(panel, YEAR)]
hpv_active_by_year[, `:=`(n_na = n_facility_years - n_known,          # facility-years where HPV_ACTIVE status is structurally unknown that year
                          pct_active = round(n_active / n_known, 4),  # active rate is on the KNOWN-status denominator (H6), not n_facility_years
                          pct_na = round((n_facility_years - n_known) / n_facility_years, 4))]
fwrite(hpv_active_by_year, file.path(OUT_CSV, "hpv_active_by_year.csv"))

# =========================================================================================================
# CSV 5 -- PENALTY_AMOUNT summary, both panels. NA-if-none-or-exactly-$0 (data/panels/README.md's documented
#   ambiguity -- inherited from the panel build, not re-derived here); no "nonzero-only" filter is applied
#   since a true $0 can't be distinguished from NA at this layer.
# =========================================================================================================
penalty_summary <- all_panels[, {                                     # data.table `{}`-block j-expression: compute the full row inline per panel group
  x <- PENALTY_AMOUNT[!is.na(PENALTY_AMOUNT)]                         # non-NA PENALTY_AMOUNT values within this panel (could include real $0s that happened to sum to nonzero, per the ambiguity noted above -- NA rows are excluded, everything else kept as-is)
  .(n_facility_years = .N, n_na = sum(is.na(PENALTY_AMOUNT)), pct_na = round(mean(is.na(PENALTY_AMOUNT)), 4),
    n_nonna = length(x), min = min(x), median = median(x), p95 = quantile(x, .95), max = max(x),
    mean = round(mean(x), 2), total = round(sum(x), 2))
}, by = panel]
fwrite(penalty_summary, file.path(OUT_CSV, "penalty_summary.csv"))

# =========================================================================================================
# CSV 6 -- categorical frequencies (facility-level, time-invariant attributes), both panels
# =========================================================================================================
freq_cat <- function(fac, label, v) {
  tb <- fac[!is.na(get(v)) & get(v) != "", .N, by = c(v)][order(-N)]; setnames(tb, v, "level")  # drop NA/blank levels before counting, then sort descending
  tb[, `:=`(panel = label, variable = v, pct = round(N / sum(N), 4))][, .(panel, variable, level, n = N, pct)]  # pct's denominator is facilities with a KNOWN, non-blank value for this variable -- same convention as 13_regulatory_profile.R's freq_cat()
}
CAT_COLS <- c("STATE", "EPA_REGION", "AIR_POLLUTANT_CLASS_DESC", "FACILITY_TYPE")
categorical_frequency <- rbindlist(lapply(PANEL_LEVELS, function(p) {
  fac <- fac1(panels_list[[p]])
  rbindlist(lapply(CAT_COLS, function(v) freq_cat(fac, p, v)))
}))
fwrite(categorical_frequency, file.path(OUT_CSV, "categorical_frequency.csv"))  # not rounded via fwrite_rounded (pct already pre-rounded to 4dp above)

# =========================================================================================================
# CSV 7 -- coordinate coverage (facility-level), both panels -- HAS_COORDINATE gates the rest, same
#   discipline as 15_coordinates_profile.R
# =========================================================================================================
coordinate_coverage <- rbindlist(lapply(PANEL_LEVELS, function(p) {
  fac <- fac1(panels_list[[p]])
  dist <- fac[!is.na(COORD_COUNTY_DIST_KM), COORD_COUNTY_DIST_KM]     # coordinate-vs-ICIS-county distance, only defined where both a coordinate and a matched county exist
  data.table(panel = p, n_facilities = nrow(fac),
             pct_has_coordinate = round(mean(fac$HAS_COORDINATE == 1, na.rm = TRUE), 4),
             pct_gross_error = round(mean(fac$COORD_GROSS_ERROR == 1, na.rm = TRUE), 4),  # among facilities where COORD_GROSS_ERROR is defined (na.rm=TRUE) -- NA here means "not evaluable" (e.g. no coordinate or no county match), not "no error"
             dist_median_km = round(median(dist), 2), dist_p95_km = round(quantile(dist, .95), 2), dist_max_km = round(max(dist), 2))
}))
fwrite(coordinate_coverage, file.path(OUT_CSV, "coordinate_coverage.csv"))

# =========================================================================================================
# CSV 8 -- entry/exit summary (facility-level), both panels. REVISED 2026-07-29 (PB2 + explicit user
#   decision): LEFT_CENSORED/RIGHT_CENSORED are no longer carried by the panel build (00_spine.R) -- dropped
#   as a derived convenience on top of ENTERED_YEAR/EXITED_YEAR/EXIT_SOURCE, which already carry the same
#   entry/exit information directly. This CSV now reports only what those three fields give directly:
#   whether a facility has a confirmed exit at all, and its entry-year distribution. Under the old
#   all-11-years continuity screen, every facility was active through 2025 by construction, so a confirmed
#   exit was near-impossible; under the >=1-year eligibility rule that's no longer true (see PB2, `pct_exited`
#   below is now a real, substantial number, not near-zero).
# =========================================================================================================
entry_exit_summary <- rbindlist(lapply(PANEL_LEVELS, function(p) {
  fac <- fac1(panels_list[[p]])
  data.table(panel = p, n_facilities = nrow(fac),
             pct_exited = round(mean(!is.na(fac$EXITED_YEAR)), 4),                       # has a confirmed EXITED_YEAR at all
             entered_year_median = median(fac$ENTERED_YEAR, na.rm = TRUE))
}))
fwrite(entry_exit_summary, file.path(OUT_CSV, "entry_exit_summary.csv"))

# =========================================================================================================
# CSV 9 -- panel comparison: electric vs. major_synmin, headline facility-count and subset check (electric's
#   filter is major_synmin's filter + NAICS 2211/SIC 4911, per code/04_panel_building/README.md -- every
#   electric facility should therefore also be a major_synmin facility)
# =========================================================================================================
maj_fac <- unique(panels_list$major_synmin$PGM_SYS_ID)
elec_fac <- unique(panels_list$electric$PGM_SYS_ID)
is_subset <- all(elec_fac %in% maj_fac)                               # the documented subset relationship -- should be TRUE; FALSE would mean the two panels' filters have drifted apart
if (!is_subset) warning(sprintf("18_panel_profile.R: %d of %d electric facilities are NOT in major_synmin -- this violates the documented subset relationship (code/04_panel_building/README.md); investigate before trusting panel_comparison.csv", sum(!elec_fac %in% maj_fac), length(elec_fac)))
panel_comparison <- data.table(
  n_facilities_major_synmin = length(maj_fac), n_facilities_electric = length(elec_fac),
  electric_subset_of_major_synmin = is_subset,
  pct_major_synmin_facilities_that_are_electric = round(length(elec_fac) / length(maj_fac), 4))
fwrite(panel_comparison, file.path(OUT_CSV, "panel_comparison.csv"))

# =========================================================================================================
# CSV 10 -- mean of key N_* count measures BY YEAR, both panels (same measures/gate as CSV 3's
#   summarise_measure(), grouped by YEAR too) -- feeds FIGURE 7 below, the mean-over-time companion to
#   FIGURE 3's overall-distribution ECDF
# =========================================================================================================
mean_counts_by_year <- rbindlist(lapply(PANEL_LEVELS, function(p) {
  dt <- panels_list[[p]][ICIS_OBSERVED == 1]                           # same ICIS_OBSERVED==1 gate as CSV 3 -- a facility-year with no ICIS record that year is NA, not a false 0, so it's excluded from the mean's numerator and denominator alike
  rbindlist(lapply(COUNT_COLS, function(m)
    dt[, .(panel = p, measure = m, n_obs = sum(!is.na(get(m))), mean = mean(get(m), na.rm = TRUE)), by = YEAR]))
}))[order(panel, measure, YEAR)]
fwrite_rounded(mean_counts_by_year, file.path(OUT_CSV, "mean_counts_by_year.csv"), num_cols = "mean")

# =========================================================================================================
# FIGURES -- print-ready (300dpi), validated 5-hue categorical palette, direct end-of-line labels
# =========================================================================================================
PAL <- c(blue = "#2a78d6", aqua = "#1baf7a", yellow = "#eda100", green = "#008300", violet = "#4a3aa7", red = "#e34948")  # named hex palette, per the dataviz-skill validated set noted in the header
INK <- "#0b0b0b"; INK_SECONDARY <- "#52514e"; GRID <- "#e1e0d9"; AXIS <- "#c3c2b7"  # text/gridline/axis colors for the shared theme below
PANEL_PAL <- c(major_synmin = unname(PAL["blue"]), electric = unname(PAL["aqua"]))  # fixed panel -> color mapping, reused across every 2-series figure below

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
        legend.position = "none")                                    # legends suppressed globally -- every figure below uses direct end-of-line labels or facets instead
save_fig <- function(name, plot, w = 7.5, h = 4.5) ggsave(file.path(OUT_FIG, name), plot, width = w, height = h, dpi = 300)

# ---- FIGURE 1: OBS_SOURCE composition (event share) over time, both panels ------------------------------
end_labels1 <- coverage_by_year[YEAR == max(YEAR)]                    # final-year value per panel, for the direct end-of-line labels
fig1 <- ggplot(coverage_by_year, aes(YEAR, pct_event, color = panel)) +
  geom_line(linewidth = 0.9) + geom_point(size = 1.4) +
  scale_color_manual(values = PANEL_PAL) +
  scale_x_continuous(breaks = seq(min(YEARS), max(YEARS), 2), expand = expansion(mult = c(0.02, 0.2))) +
  scale_y_continuous(labels = label_percent(), limits = c(0, 1)) +
  geom_text(data = end_labels1, aes(label = panel), hjust = 0, nudge_x = 0.3, size = 3.2, fontface = "bold") +
  coord_cartesian(clip = "off") +
  labs(title = "Share of facility-years with an ICIS event, 2015-2025",
       subtitle = "OBS_SOURCE == \"event\" vs. \"operating\" (no ICIS event that year, but confirmed active another way) vs.\n\"unobserved\" (no confirmed activity that year -- expected under the >=1-year eligibility rule, PB2)",
       x = NULL, y = "Share \"event\"",
       caption = "Source: data/panels/*_2015_2025.csv.gz.") +
  theme_journal + theme(plot.margin = margin(t = 5.5, r = 14, b = 5.5, l = 5.5),
                        plot.subtitle = element_text(color = INK_SECONDARY, size = 8.5, lineheight = 1.1))
save_fig("panel_coverage_over_time.png", fig1, w = 8.3, h = 4.8)

# ---- FIGURE 2: HPV-active rate over time, both panels ------------------------------------------------------
end_labels2 <- hpv_active_by_year[YEAR == max(YEAR)]
fig2 <- ggplot(hpv_active_by_year, aes(YEAR, pct_active, color = panel)) +
  geom_line(linewidth = 0.9) + geom_point(size = 1.4) +
  scale_color_manual(values = PANEL_PAL) +
  scale_x_continuous(breaks = seq(min(YEARS), max(YEARS), 2), expand = expansion(mult = c(0.02, 0.2))) +
  scale_y_continuous(labels = label_percent(), limits = c(0, NA)) +
  geom_text(data = end_labels2, aes(label = panel), hjust = 0, nudge_x = 0.3, size = 3.2, fontface = "bold") +
  coord_cartesian(clip = "off") +
  labs(title = "Share of facilities in HPV-active status, 2015-2025",
       subtitle = "Of facility-years with known HPV_ACTIVE status (non-NA); H6 zero-vs-NA discipline",
       x = NULL, y = "Share HPV-active",
       caption = "Source: data/panels/*_2015_2025.csv.gz.") +
  theme_journal + theme(plot.margin = margin(t = 5.5, r = 14, b = 5.5, l = 5.5))
save_fig("panel_hpv_active_over_time.png", fig2, w = 8.3, h = 4.8)

# ---- FIGURE 3: ECDF of key count measures, both panels, faceted by measure ---------------------------------
KEY_MEAS <- c(N_INSPECTIONS = "Inspections", N_ENFORCEMENT = "Enforcement", N_HPV = "HPV violations")  # 3 of the 9 COUNT_COLS measures, chosen for this figure
ecdf_data <- rbindlist(lapply(PANEL_LEVELS, function(p) {
  dt <- panels_list[[p]][ICIS_OBSERVED == 1]                          # ICIS_OBSERVED subset, same gate as CSV 3
  rbindlist(lapply(names(KEY_MEAS), function(m)
    data.table(panel = p, measure = KEY_MEAS[[m]], value = dt[[m]][!is.na(dt[[m]])])))
}))
ecdf_data[, measure := factor(measure, levels = unname(KEY_MEAS))]
fig3 <- ggplot(ecdf_data, aes(value, color = panel)) +
  stat_ecdf(geom = "step", linewidth = 0.8) +
  facet_wrap(~measure, nrow = 1, scales = "free_x") +
  scale_color_manual(values = PANEL_PAL) +
  scale_x_continuous(trans = scales::pseudo_log_trans(sigma = 1), breaks = c(0, 1, 5, 20, 100)) +  # pseudo-log compresses the heavy right tail while keeping 0 visible (unlike log10, which can't represent 0) -- avoids picking a single truncation point that would have to differ by measure
  labs(title = "Distribution of key count measures, ICIS-observed facility-years, 2015-2025",
       subtitle = "Empirical CDF; x-axis on a pseudo-log scale (compresses the long right tail, keeps 0 visible)",
       x = "Count (pseudo-log scale)", y = "Cumulative share of facility-years",
       caption = "Source: data/panels/*_2015_2025.csv.gz.") +
  theme_journal + theme(legend.position = "bottom", legend.title = element_blank(),
                        strip.text = element_text(face = "bold", size = 9.5))
save_fig("panel_count_distributions.png", fig3, w = 9.5, h = 4.3)

# ---- FIGURE 4: PENALTY_AMOUNT distribution (non-NA), log10 x-axis, faceted by panel (free_y given the large
#   size difference between the two panels) --------------------------------------------------------------
pen_nonna <- all_panels[!is.na(PENALTY_AMOUNT) & PENALTY_AMOUNT > 0, .(panel, PENALTY_AMOUNT)]  # log10 x-axis requires strictly positive values; PENALTY_AMOUNT==0 (a real, if rare, value here per the NA-ambiguity note) is excluded from this log-scale view, not from penalty_summary.csv above
fig4 <- ggplot(pen_nonna, aes(PENALTY_AMOUNT, fill = panel)) +
  geom_histogram(bins = 40, color = "white", linewidth = 0.1) +
  facet_wrap(~panel, ncol = 1, scales = "free_y") +
  scale_fill_manual(values = PANEL_PAL) +
  scale_x_log10(labels = label_dollar(scale_cut = cut_short_scale())) +
  scale_y_continuous(labels = label_comma()) +
  labs(title = "PENALTY_AMOUNT distribution (non-NA, positive), 2015-2025",
       subtitle = sprintf("n = %s facility-years; log10 x-axis; NA (no formal action, or summed to exactly $0) excluded per\ndata/panels/README.md's documented ambiguity",
                          format(nrow(pen_nonna), big.mark = ",")),
       x = "Penalty amount (log scale)", y = "Facility-years",
       caption = "Source: data/panels/*_2015_2025.csv.gz.") +
  theme_journal + theme(strip.text = element_text(face = "bold", size = 9.5),
                        plot.subtitle = element_text(color = INK_SECONDARY, size = 8.5, lineheight = 1.1))
save_fig("panel_penalty_dist.png", fig4, w = 7.5, h = 5.5)

# ---- FIGURE 5: top 10 states by major_synmin facility count, both panels side by side ----------------------
top_states <- categorical_frequency[variable == "STATE" & panel == "major_synmin"][order(-n)][1:10, level]  # top 10 states ranked by major_synmin (the larger panel); electric's bars use the SAME state ordering for direct comparison, even though electric's own top-10 could differ slightly
state_plot_data <- categorical_frequency[variable == "STATE" & level %in% top_states]
state_plot_data[, level := factor(level, levels = rev(top_states))]   # rev() so the highest-count state plots at the top of a horizontal bar chart
fig5 <- ggplot(state_plot_data, aes(level, n, fill = panel)) +
  geom_col(position = position_dodge(width = 0.75), width = 0.7) +
  scale_fill_manual(values = PANEL_PAL) +
  scale_y_continuous(labels = label_comma()) +
  coord_flip() +
  labs(title = "Top 10 states by facility count (ranked by major_synmin), 2015-2025",
       subtitle = "Facility-level (one row per PGM_SYS_ID); electric bars use major_synmin's state ordering",
       x = NULL, y = "Facilities",
       caption = "Source: data/panels/*_2015_2025.csv.gz.") +
  theme_journal + theme(legend.position = "bottom", legend.title = element_blank())
save_fig("panel_state_composition.png", fig5, w = 7.5, h = 5)

# ---- FIGURE 6: facility count over time, both panels -- should STILL be FLAT within each panel even after
#   the PB2 eligibility-rule revision: build_panel()'s expand_grid always gives every eligible facility a row
#   in every one of the 11 years (03_build_functions.R) -- eligibility is evaluated once, over the facility's
#   whole 2015-2025 record, not per-year, so the SET of facilities in the panel can't vary by year regardless
#   of which eligibility rule is used. This figure doubles as a visual check of that (build-recipe, not
#   eligibility-rule) invariant, not just a display of the (otherwise unsurprising) subset relationship ------
facility_by_year <- all_panels[, .(n_facilities = uniqueN(PGM_SYS_ID)), by = .(panel, YEAR)][order(panel, YEAR)]
n_distinct_counts <- facility_by_year[, uniqueN(n_facilities), by = panel]  # should be 1 for both panels (flat line) -- if not, the expand_grid rectangle isn't actually holding for this build, which would be a real problem, not a display nuance
if (any(n_distinct_counts$V1 > 1)) warning("18_panel_profile.R: facility count varies by year within a panel -- this should be impossible given build_panel()'s expand_grid recipe (03_build_functions.R); panel_facility_count_over_time.png will show this visually; investigate before trusting the panel build")
end_labels6 <- facility_by_year[YEAR == max(YEAR)]
fig6 <- ggplot(facility_by_year, aes(YEAR, n_facilities, color = panel)) +
  geom_line(linewidth = 0.9) + geom_point(size = 1.4) +
  scale_color_manual(values = PANEL_PAL) +
  scale_x_continuous(breaks = seq(min(YEARS), max(YEARS), 2), expand = expansion(mult = c(0.02, 0.2))) +
  scale_y_continuous(labels = label_comma(), limits = c(0, NA)) +
  geom_text(data = end_labels6, aes(label = sprintf("%s (%s)", panel, format(n_facilities, big.mark = ","))),
            hjust = 0, nudge_x = 0.3, size = 3.2, fontface = "bold") +
  coord_cartesian(clip = "off") +
  labs(title = "Facility count by year, both panels, 2015-2025",
       subtitle = "Expected to be flat within each panel -- eligibility is evaluated once over each facility's whole 2015-2025 record",
       x = NULL, y = "Facilities",
       caption = "Source: data/panels/*_2015_2025.csv.gz.") +
  theme_journal + theme(plot.margin = margin(t = 5.5, r = 20, b = 5.5, l = 5.5))
save_fig("panel_facility_count_over_time.png", fig6, w = 8.3, h = 4.8)

# ---- FIGURE 7: mean of key N_* count measures over time, both panels, faceted by measure -- the
#   mean-over-time companion to FIGURE 3's overall-distribution ECDF; all 9 COUNT_COLS (not just the 3
#   FIGURE 3 picks), since "mean enforcement, violations, etc." spans the full measure set -------------------
MEAS_LABELS <- c(N_INSPECTIONS = "Inspections", N_VIOLATIONS = "Violations", N_HPV = "HPV violations",
                 N_ENFORCEMENT = "Enforcement (pooled)", N_FORMAL = "Formal enforcement",
                 N_INFORMAL = "Informal enforcement", N_CERTS = "Title V certifications",
                 N_STACK_TESTS = "Stack tests", N_PENALTIES = "Penalty actions")  # facet-friendly labels, same measures/order as COUNT_COLS -- analogous to build_panels_page.R's measure_labels (that page's Table 2 is this figure's overall, not-by-year, counterpart)
mean_plot_data <- copy(mean_counts_by_year)
mean_plot_data[, measure := factor(MEAS_LABELS[measure], levels = unname(MEAS_LABELS))]  # relabel + fix facet order to COUNT_COLS order
fig7 <- ggplot(mean_plot_data, aes(YEAR, mean, color = panel)) +
  geom_line(linewidth = 0.9) + geom_point(size = 1.1) +
  facet_wrap(~measure, ncol = 3, scales = "free_y") +                  # free_y -- measures span very different scales (e.g. inspections vs. stack tests), a shared axis would flatten most facets
  scale_color_manual(values = PANEL_PAL) +
  scale_x_continuous(breaks = seq(min(YEARS), max(YEARS), 4)) +
  scale_y_continuous(labels = label_number(accuracy = 0.01)) +
  labs(title = "Mean count measures per ICIS-observed facility-year, 2015-2025",
       subtitle = "ICIS_OBSERVED == 1 subset (same gate as summary_counts.csv); means are right-skew-sensitive --\nsee FIGURE 3's ECDF / summary_counts.csv's median for the fuller distributional picture",
       x = NULL, y = "Mean count",
       caption = "Source: data/panels/*_2015_2025.csv.gz.") +
  theme_journal + theme(legend.position = "bottom", legend.title = element_blank(),
                        strip.text = element_text(face = "bold", size = 9),
                        plot.subtitle = element_text(color = INK_SECONDARY, size = 8.5, lineheight = 1.1))
save_fig("panel_mean_counts_over_time.png", fig7, w = 9.5, h = 8)

# ---- FIGURE 8: violations & enforcement (formal/informal) over time, both panels -- a clean, journal-ready
#   companion to FIGURE 7 restricted to the 3 measures a reader most often cites (violations, formal/informal
#   enforcement), one row of facets, direct end-of-line panel labels instead of a bottom legend (matching
#   FIGURES 1/2/6's single-series convention rather than FIGURE 3/7's faceted-with-legend convention) --------
VE_MEAS <- MEAS_LABELS[c("N_VIOLATIONS", "N_FORMAL", "N_INFORMAL")]    # 3-measure subset of FIGURE 7's labels, same wording, fixed left-to-right order
ve_data <- mean_counts_by_year[measure %in% names(VE_MEAS)]
ve_data[, measure := factor(VE_MEAS[measure], levels = unname(VE_MEAS))]
end_labels8 <- ve_data[YEAR == max(YEAR)]                              # final-year value per measure x panel, for the direct end-of-line labels
fig8 <- ggplot(ve_data, aes(YEAR, mean, color = panel)) +
  geom_line(linewidth = 0.9) + geom_point(size = 1.4) +
  facet_wrap(~measure, nrow = 1, scales = "free_y") +
  scale_color_manual(values = PANEL_PAL) +
  scale_x_continuous(breaks = seq(min(YEARS), max(YEARS), 4),
                     expand = expansion(mult = c(0.02, 0.62))) +       # generous right expansion (no coord_cartesian(clip="off") here, unlike FIGURES 1/2/6) so each facet's end label ("major_synmin", the longer of the two panel names) stays fully INSIDE its own panel and can't bleed into the next facet over -- 0.38 clipped the trailing "n" in testing, 0.62 does not
  scale_y_continuous(labels = label_number(accuracy = 0.01), limits = c(0, NA)) +
  geom_text(data = end_labels8, aes(label = panel), hjust = 0, nudge_x = 0.3, size = 3.1, fontface = "bold") +
  labs(title = "Violations and enforcement actions, mean per ICIS-observed facility-year, 2015-2025",
       subtitle = "ICIS_OBSERVED == 1 subset; means are right-skew-sensitive -- see FIGURE 3's ECDF / summary_counts.csv's\nmedian for the fuller distributional picture",
       x = NULL, y = "Mean count",
       caption = "Source: data/panels/*_2015_2025.csv.gz.") +
  theme_journal + theme(strip.text = element_text(face = "bold", size = 9.5),
                        plot.subtitle = element_text(color = INK_SECONDARY, size = 8.5, lineheight = 1.1))
save_fig("panel_violations_enforcement.png", fig8, w = 10, h = 4.3)

# ---- console summary ---------------------------------------------------------------------------------------
cat("data/panels/*_2015_2025.csv.gz -- profile summary\n")
cat("================================================================\n\n")
print(as.data.frame(overview), row.names = FALSE)
cat("\nOBS_SOURCE COMPOSITION BY YEAR (event vs. operating; unobserved should be 0)\n"); print(as.data.frame(coverage_by_year), row.names = FALSE)
cat("\nKEY COUNT MEASURES (ICIS_OBSERVED subset)\n"); print(as.data.frame(summary_counts), row.names = FALSE)
cat("\nHPV-ACTIVE RATE BY YEAR\n"); print(as.data.frame(hpv_active_by_year), row.names = FALSE)
cat("\nPENALTY_AMOUNT SUMMARY\n"); print(as.data.frame(penalty_summary), row.names = FALSE)
cat("\nCOORDINATE COVERAGE (facility-level)\n"); print(as.data.frame(coordinate_coverage), row.names = FALSE)
cat("\nENTRY/EXIT CENSORING (facility-level)\n"); print(as.data.frame(entry_exit_summary), row.names = FALSE)
cat("\nPANEL COMPARISON (electric vs. major_synmin)\n"); print(as.data.frame(panel_comparison), row.names = FALSE)
cat("\nMEAN COUNT MEASURES BY YEAR (ICIS_OBSERVED subset)\n"); print(as.data.frame(mean_counts_by_year), row.names = FALSE)
cat(sprintf("\n8 figures written to %s:\n  panel_coverage_over_time.png, panel_hpv_active_over_time.png, panel_count_distributions.png,\n  panel_penalty_dist.png, panel_state_composition.png, panel_facility_count_over_time.png,\n  panel_mean_counts_over_time.png, panel_violations_enforcement.png\n", OUT_FIG))

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# 1. (summarise_measure(), CSV 3) pct_na's denominator is the FULL panel (x_all), while every other statistic
#    in that row is computed on the ICIS_OBSERVED==1, non-NA subset (x) -- same convention/caveat as
#    13_regulatory_profile.R's summarise_measure(); easy to misread pct_na as relative to n_obs rather than
#    to the whole panel.
# 2. (freq_cat(), CSV 6) pct's denominator is facilities with a KNOWN, non-blank value for the variable
#    (NA/"" rows dropped from both numerator and denominator) -- consistent with 13_regulatory_profile.R's
#    freq_cat(), but worth noting since other CSVs in this file (e.g. hpv_active_by_year's pct_na) use a
#    different convention (NA counted in the denominator).
# 3. (penalty_summary, CSV 5 / FIGURE 4) PENALTY_AMOUNT's NA-vs-$0 ambiguity is inherited from
#    data/panels/README.md unchanged -- "NA if no formal action or if it summed to exactly $0 -- both read
#    the same." penalty_summary.csv's min/median/etc. are computed on all non-NA values (real $0s, if any
#    survived the ambiguity, are included); FIGURE 4's log-scale histogram additionally excludes exact $0
#    (log10 can't represent it), so the two views have slightly different denominators by necessity.
# 4. (FIGURE 5, top_states) Electric's bars are ordered/restricted to major_synmin's top-10 state list, not
#    electric's own top 10 -- deliberate, for a direct side-by-side comparison, but means a state where
#    electric utilities are unusually concentrated relative to major_synmin as a whole (if outside the
#    major_synmin top 10) would not appear in this figure. categorical_frequency.csv itself is unfiltered and
#    has electric's true top states, if needed.
# 5. (FIGURE 3, pseudo-log x-axis) scale_x_continuous(trans = pseudo_log_trans()) was chosen over per-measure
#    p99 truncation (13_regulatory_profile.R's Figure 3 approach) because facet_wrap(scales = "free_x") can't
#    easily take a different coord_cartesian(xlim=) per facet -- pseudo-log applies one transform globally and
#    still compresses each measure's long right tail reasonably, at the cost of a slightly less intuitive axis
#    than a linear truncated one.
# 6. (mean_counts_by_year, FIGURE 7) the mean is sensitive to the heavy right-skew already visible in FIGURE
#    3's ECDF and in summary_counts.csv's median-vs-mean gap -- a small share of high-count facility-years
#    (e.g. a large inspection sweep or a multi-facility enforcement action) can pull a year's mean well above
#    where most facility-years actually sit. Read this figure alongside FIGURE 3 / summary_counts.csv, not as
#    a replacement for either -- a rising mean could reflect either a genuine broad-based increase or just a
#    handful of outlier facility-years in that year, and this figure alone can't distinguish the two.
