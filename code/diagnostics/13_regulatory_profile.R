# =========================================================================================================
# code/diagnostics/13_regulatory_profile.R -- exploratory profiling of dataset 0 (data/datasets/regulatory.csv.gz).
#   Purpose: characterize the regulatory dataset (ICIS-Air only: event counts + facility characteristics) for
#   a reader picking the project up cold, and produce a small set of print-ready figures. Companion to
#   11_operating_profile.R / 12_penalties_profile.R (same discipline, different dataset).
#
#   in : data/datasets/regulatory.csv.gz
#   out: output/regulatory_profile/*.csv (incl. facility_level_overview.csv for R1/R7, and
#        naics_211111_coverage.csv / fine_grained_enforcement.csv for the missing-classification S5 wrinkle
#        in regulatory_dataset_profile.md -- added 2026-07-27, backing figures that previously had no script)
#        output/figures/datasets/regulatory/reg_{coverage_over_time,activity_over_time,inspections_distribution,
#                                                activity_by_classification,coverage_by_classification_over_time}.png
#
#   DISCIPLINE: ICIS_OBSERVED is the zero-vs-NA gate -- a facility-year is icis_observed==1 iff ICIS holds
#   any record that year (n_inspections non-NA); every N_* count is a real 0/positive when observed, NA when
#   not. Every rate/summary below is computed on the observed subset AND reports the NA share, so a
#   structural NA (facility not yet reporting / already closed / outside ICIS coverage) is never read as a
#   zero. No numbers are hand-entered; every cell/figure is computed here. Hand-run (not part of RUN_ALL.R).
#   No stochastic step.
#
#   FIGURE DESIGN (dataviz skill, static/print variant -- no hover/dark-mode, those are screen-only concerns):
#   validated 5-hue categorical palette (blue/aqua/green/violet slots; light-surface contrast WARN on
#   aqua/yellow mitigated with direct end-of-line labels per the skill's relief rule), one axis per chart,
#   thin 2px lines, muted gridlines, 300dpi for print.
# =========================================================================================================
suppressPackageStartupMessages({library(data.table); library(ggplot2); library(scales)})  # data.table for the aggregation, ggplot2/scales for the print figures; quietly, to keep the console clean
options(scipen = 999)                                                 # disable scientific notation so large counts print as plain integers everywhere (console + CSVs)

DATASETS <- here::here("data/datasets")                               # source dir for the six-dataset layer
OUT_CSV  <- here::here("output/regulatory_profile")                   # destination for every computed CSV below
OUT_FIG  <- here::here("output/figures/datasets/regulatory")          # destination for every PNG figure below
dir.create(OUT_CSV, showWarnings = FALSE, recursive = TRUE)           # create if missing, silently if it already exists
dir.create(OUT_FIG, showWarnings = FALSE, recursive = TRUE)

# ID/FIPS-like columns that can carry a leading zero -- fread guesses these as numeric by default and
# silently drops the leading zero (e.g. "01001" -> 1001) unless forced to character.
reg <- fread(file.path(DATASETS, "regulatory.csv.gz"), colClasses = list(character = c("REGISTRY_ID", "ZIP_CODE")))  # force these two ID-like columns to character on read, per the comment above
YEARS <- sort(unique(reg$YEAR))                                       # distinct years present in the data, ascending -- used for axis breaks and range checks below, NOT hard-coded to 2005:2025
observed <- reg[ICIS_OBSERVED == 1]                                   # the zero-vs-NA gate subset: rows where ICIS actually holds a record this year

fwrite_rounded <- function(dt, file, prop_cols = NULL, num_cols = NULL) {
  d <- copy(dt)                                                       # copy first so rounding below doesn't mutate the caller's table in place (data.table `:=` would otherwise modify by reference)
  for (cc in intersect(prop_cols, names(d))) d[, (cc) := round(get(cc), 3)]  # proportions rounded to 3 decimals (e.g. 0.1 pct resolution)
  for (cc in intersect(num_cols,  names(d))) d[, (cc) := round(get(cc), 2)]  # other numeric columns (e.g. means) rounded to 2 decimals
  fwrite(d, file)                                                     # write the rounded copy to disk; rounding here only affects the CSV output, not any in-memory value used elsewhere in the script
}

# =========================================================================================================
# CSV 1 -- overview
# =========================================================================================================
overview <- data.table(
  n_facilities = uniqueN(reg$PGM_SYS_ID), n_facility_years = nrow(reg),  # distinct facilities and total rows, over ALL of reg (not the observed subset)
  year_min = min(YEARS), year_max = max(YEARS),
  balanced = nrow(reg) == uniqueN(reg$PGM_SYS_ID) * length(YEARS),    # sanity check: is reg a full facility x year rectangle with no gaps?
  pct_icis_observed = mean(reg$ICIS_OBSERVED == 1))                   # overall share of facility-years that are ICIS-observed, across the whole panel
fwrite_rounded(overview, file.path(OUT_CSV, "overview.csv"), prop_cols = "pct_icis_observed")

# =========================================================================================================
# CSV 2 -- coverage by year
# =========================================================================================================
coverage_by_year <- reg[, .(n_facility_years = .N, pct_observed = mean(ICIS_OBSERVED == 1)), by = YEAR][order(YEAR)]  # per-year row count + observed share, sorted chronologically
fwrite_rounded(coverage_by_year, file.path(OUT_CSV, "coverage_by_year.csv"), prop_cols = "pct_observed")

# =========================================================================================================
# CSV 3 -- five-number summaries for key N_* count measures, observed subset
# =========================================================================================================
COUNT_COLS <- c("N_INSPECTIONS", "N_VIOLATIONS", "N_HPV", "N_ENFORCEMENT", "N_FORMAL", "N_INFORMAL",
                "N_CERTS", "N_STACK_TESTS", "N_PENALTIES")            # the count measures profiled in this table
summarise_measure <- function(m) {
  x_all <- reg[[m]]; x <- observed[[m]]; x <- x[!is.na(x)]            # x_all = the column over ALL rows (used only for pct_na below); x = the column over the OBSERVED subset, then NA-dropped (should be a no-op if ICIS_OBSERVED==1 implies non-NA, but this is defensive)
  data.table(measure = m, n_obs = length(x), pct_na = mean(is.na(x_all)),  # FLAG: pct_na's denominator is x_all (ALL of reg, unobserved rows included), while every other statistic in this row (min/median/mean/etc.) is computed on x (the observed, non-NA subset). That's the intended design -- pct_na is meant to report the share of the FULL panel that's missing -- but it means pct_na is NOT "share of x that's NA" (which would trivially be 0 by construction); a reader skimming the row could misread pct_na as relative to n_obs rather than to the whole panel.
             min = min(x), p25 = quantile(x, .25), median = median(x), p75 = quantile(x, .75),
             p99 = quantile(x, .99), max = max(x), mean = mean(x), pct_zero = mean(x == 0))  # all five-number-summary stats computed on the observed, non-NA subset x
}
summary_counts <- rbindlist(lapply(COUNT_COLS, summarise_measure))    # one row per measure, stacked
fwrite_rounded(summary_counts, file.path(OUT_CSV, "summary_counts.csv"),
               prop_cols = c("pct_na", "pct_zero"), num_cols = "mean")

# =========================================================================================================
# CSV 4 -- categorical frequencies (facility-level, time-invariant attributes)
# =========================================================================================================
fac1 <- reg[, .SD[1L], by = PGM_SYS_ID]                                # collapse to one row per facility (the FIRST row encountered per PGM_SYS_ID) -- used for every facility-level (not facility-year-level) summary in this file
freq_cat <- function(v) {
  tb <- fac1[!is.na(get(v)) & get(v) != "", .N, by = c(v)][order(-N)]; setnames(tb, v, "level")  # drop NA and empty-string levels before counting, then sort descending by frequency
  tb[, `:=`(variable = v, pct = round(N / sum(N), 4))][, .(variable, level, n = N, pct)]  # FLAG: pct's denominator (sum(N)) is the count AFTER dropping NA/"" levels, so pct is "share of facilities with a KNOWN, non-blank value for this variable," not "share of all facilities" -- a facility with a missing STATE, say, contributes to neither the numerator nor the denominator here, unlike CSV 1's "Class: other/missing" treatment of NA class in 05_panel_summaries.R which folds NA into the denominator as a residual bucket. The two conventions differ across files; worth knowing which one a given "pct" column follows before comparing across scripts.
}
freq_categorical <- rbindlist(lapply(c("STATE", "EPA_REGION", "FACILITY_TYPE", "AIR_POLLUTANT_CLASS_DESC",
                                       "OP_STATUS_CURRENT_DESC"), freq_cat))  # stack frequency tables for each of these 5 facility-level categorical columns
fwrite(freq_categorical, file.path(OUT_CSV, "freq_categorical.csv"))  # not rounded via fwrite_rounded (pct is already pre-rounded to 4dp above), written directly

# =========================================================================================================
# CSV 5 -- emissions / program-enrollment prevalence (facility-level binary flags)
# =========================================================================================================
BIN_COLS <- c(grep("^EMITS_", names(reg), value = TRUE), grep("^PROG_", names(reg), value = TRUE))  # every column starting with EMITS_ or PROG_, discovered dynamically -- automatically picks up new binary flag columns without needing this list updated by hand
binary_prevalence <- rbindlist(lapply(BIN_COLS, function(b)
  data.table(flag = b, n_facilities = nrow(fac1), share_1 = mean(fac1[[b]] == 1, na.rm = TRUE))))  # share of facilities (not facility-years) where the flag is 1, among facilities with a non-NA value for that flag (na.rm=TRUE drops NA from the mean's implicit denominator too, since `== 1` on NA is NA)
fwrite_rounded(binary_prevalence, file.path(OUT_CSV, "binary_prevalence.csv"), prop_cols = "share_1")

# =========================================================================================================
# CSV 6 -- pollutant classification: coverage + activity comparison (the classification driving CAA
#   oversight intensity -- Major sources face materially more scrutiny than Minor). Small residual
#   categories (unknown/not-applicable/other, 4.2% of facilities combined) are pooled into "Other/Unknown"
#   rather than dropped, so the comparison accounts for the full universe.
# =========================================================================================================
CLASS_MAP <- c("Major Emissions" = "Major", "Synthetic Minor Emissions" = "Synthetic Minor",
              "Minor Emissions" = "Minor")                            # source ICIS label -> short display label, for the 3 "named" classes
reg[, classification := fifelse(AIR_POLLUTANT_CLASS_DESC %in% names(CLASS_MAP),
                                CLASS_MAP[AIR_POLLUTANT_CLASS_DESC], "Other/Unknown")]  # every row not in the 3 named classes (including NA, since NA %in% is FALSE) is bucketed as "Other/Unknown" -- so classification is NEVER NA itself, even though AIR_POLLUTANT_CLASS_DESC can be
CLASS_LEVELS <- c("Major", "Synthetic Minor", "Minor", "Other/Unknown")
reg[, classification := factor(classification, levels = CLASS_LEVELS)]  # fix the display/plot order of the 4 classification levels
observed <- reg[ICIS_OBSERVED == 1]                      # rebuild now that `classification` exists
# FLAG: `observed` was already built once (near the top of the file, before `classification` existed) and is
# now rebuilt here so that classification_activity below can group by it. This is handled correctly (the
# comment says so explicitly), but it's a real trap: every computation between the first `observed <-` and
# this line (CSVs 1-5) used the OLD `observed`, which is fine since none of them reference `classification`
# -- but if a future edit inserts a new CSV between CSV 5 and this rebuild that both uses `observed` AND
# needs `classification`, it would silently get a `classification`-less error or, worse if classification
# were added earlier by mistake, a stale/inconsistent `observed`. The dependency (classification must exist
# before this rebuild, and any classification-aware use of `observed` must come after it) is enforced only
# by code order, not by structure.

classification_coverage <- reg[, .(n_facilities = uniqueN(PGM_SYS_ID), n_facility_years = .N,
                                   pct_observed = mean(ICIS_OBSERVED == 1)), by = classification][order(classification)]  # n_facilities here counts facility-YEAR rows' distinct PGM_SYS_ID within each classification group -- since classification is treated as time-invariant per the header note, this is equivalent to per-facility counts, but relies on that invariant holding (a facility whose classification changed across years would be double-counted across two classification buckets)
fwrite_rounded(classification_coverage, file.path(OUT_CSV, "classification_coverage.csv"), prop_cols = "pct_observed")

CLASS_MEAS <- c("N_INSPECTIONS", "N_VIOLATIONS", "N_ENFORCEMENT", "N_CERTS", "N_STACK_TESTS")  # the 5 measures compared by classification, a subset of the 9 in COUNT_COLS above
classification_activity <- rbindlist(lapply(CLASS_MEAS, function(m)
  observed[, .(measure = m, mean_count = mean(get(m), na.rm = TRUE),  # mean count per observed facility-year, na.rm defensive (observed rows should already be non-NA for these columns per the zero-vs-NA gate)
              pct_nonzero = mean(get(m) > 0, na.rm = TRUE)), by = classification]))
fwrite_rounded(classification_activity, file.path(OUT_CSV, "classification_activity.csv"),
               prop_cols = "pct_nonzero", num_cols = "mean_count")

# =========================================================================================================
# CSV 7 -- facility-level "ever observed" and programs-table-gap stats (backs R1/R7 in
#   dataset_construction_decisions.md). One row per facility, so aggregate on facility grain, not
#   facility-year, unlike the CSVs above.
# =========================================================================================================
by_facility <- reg[, .(any_observed = any(ICIS_OBSERVED == 1), n_programs_na = all(is.na(N_PROGRAMS))),
                   by = PGM_SYS_ID]                                    # per facility: was it EVER ICIS-observed in any year, and is N_PROGRAMS missing in EVERY year
facility_level_overview <- data.table(
  n_facilities                 = nrow(by_facility),
  n_facilities_zero_events     = sum(!by_facility$any_observed),      # facilities with NO ICIS-observed year at all, across the entire panel
  pct_facilities_zero_events   = mean(!by_facility$any_observed),
  n_facilities_no_programs     = sum(by_facility$n_programs_na),      # facilities where N_PROGRAMS is NA in every single year
  pct_facilities_no_programs   = mean(by_facility$n_programs_na),
  n_facility_years_no_programs = sum(is.na(reg$N_PROGRAMS)))          # FLAG: this last field switches grain mid-table -- every other field in facility_level_overview is a facility-level count/share (denominator = n_facilities), but n_facility_years_no_programs is a facility-YEAR count (raw row count with NA N_PROGRAMS), not divided by anything and not comparable in scale to the facility-level fields around it. Not incorrect, but a reader scanning the CSV could easily misread it as being on the same grain as its neighbors.
fwrite_rounded(facility_level_overview, file.path(OUT_CSV, "facility_level_overview.csv"),
               prop_cols = c("pct_facilities_zero_events", "pct_facilities_no_programs"))

# =========================================================================================================
# CSV 8 -- missing AIR_POLLUTANT_CLASS_DESC, fine-grained: NAICS 211111 vs. every other facility, plus the
#   fine vs. coarse "Other/Unknown" enforcement-rate reconciliation (backs regulatory_dataset_profile.md
#   S5's "wrinkle" -- the coarse classification_activity.csv row above pools missing-class facilities
#   together with the three NAMED residual categories (Not applicable / Emissions classification unknown /
#   Other), which dilutes the enforcement-rate signal specific to the missing-field subset).
# =========================================================================================================
fac_naics <- reg[!duplicated(PGM_SYS_ID), .(PGM_SYS_ID, NAICS_CODES, AIR_POLLUTANT_CLASS_DESC)]  # one row per facility (first-occurrence dedup via !duplicated, equivalent in effect to the .SD[1L] pattern used for fac1 above but implemented differently -- both rely on the same "first row = the whole facility" assumption)
fac_naics[, is_211111 := grepl("(^|[^0-9])211111([^0-9]|$)", NAICS_CODES)]  # regex match for NAICS code 211111 (crude oil & natural gas extraction) as a whole token within a possibly multi-code string, guarding against matching it as a substring of a longer code
fac_naics[, is_missing_class := is.na(AIR_POLLUTANT_CLASS_DESC)]      # note: this is a STRICT NA check, unlike `classification` above which pools NA together with three OTHER named-residual categories -- is_missing_class is narrower (NA only) than "Other/Unknown" (NA + 3 residual labels), which is exactly the fine-vs-coarse distinction this CSV exists to surface
naics_211111_coverage <- fac_naics[, .(n_facilities = .N, n_missing_class = sum(is_missing_class),
                                       pct_missing_class = mean(is_missing_class)), by = is_211111]  # missing-classification rate, split by whether the facility is a NAICS 211111 (oil & gas) facility or not
fwrite_rounded(naics_211111_coverage, file.path(OUT_CSV, "naics_211111_coverage.csv"), prop_cols = "pct_missing_class")

reg[, class_bucket := fifelse(is.na(AIR_POLLUTANT_CLASS_DESC), "missing_field",
                    fifelse(AIR_POLLUTANT_CLASS_DESC %in% c("Not applicable", "Emissions classification unknown", "Other"),
                            "named_residual", as.character(classification)))]  # three-way split: strictly-missing field vs. named-but-residual label vs. one of the 3 real named classes (Major/Synthetic Minor/Minor, taken from `classification`) -- this is the fine-grained partition that CSV 6's coarser "Other/Unknown" bucket collapses together
fine_grained_enforcement <- reg[ICIS_OBSERVED == 1, .(n = .N, mean_enforcement = mean(N_ENFORCEMENT, na.rm = TRUE)),
                                by = class_bucket][order(-mean_enforcement)]  # mean enforcement actions per observed facility-year, by the fine-grained bucket, sorted descending -- this is the number that CSV 6's classification_activity.csv dilutes by pooling missing_field into the same bucket as named_residual and the true unclassified labels
fwrite_rounded(fine_grained_enforcement, file.path(OUT_CSV, "fine_grained_enforcement.csv"), num_cols = "mean_enforcement")

# =========================================================================================================
# FIGURES -- print-ready (300dpi), validated 5-hue categorical palette, direct end-of-line labels
# =========================================================================================================
PAL <- c(blue = "#2a78d6", aqua = "#1baf7a", yellow = "#eda100", green = "#008300", violet = "#4a3aa7", red = "#e34948")  # named hex palette, per the dataviz-skill validated set noted in the header
INK <- "#0b0b0b"; INK_SECONDARY <- "#52514e"; GRID <- "#e1e0d9"; AXIS <- "#c3c2b7"  # text/gridline/axis colors for the shared theme below

theme_journal <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(),                          # no minor gridlines (print-clean)
        panel.grid.major = element_line(color = GRID, linewidth = 0.3),  # thin, muted major gridlines
        axis.line = element_line(color = AXIS, linewidth = 0.3),
        axis.ticks = element_line(color = AXIS, linewidth = 0.3),
        text = element_text(color = INK),
        axis.text = element_text(color = INK_SECONDARY),
        plot.title = element_text(face = "bold", size = 12),
        plot.subtitle = element_text(color = INK_SECONDARY, size = 9.5),
        plot.caption = element_text(color = INK_SECONDARY, size = 8, hjust = 0),
        legend.position = "none")                                    # legends suppressed globally -- every figure below uses direct end-of-line labels instead (dataviz skill's "relief rule")
save_fig <- function(name, plot, w = 7.5, h = 4.5) ggsave(file.path(OUT_FIG, name), plot, width = w, height = h, dpi = 300)  # shared save helper: fixed 300dpi, default 7.5x4.5in, overridable per-figure

# ---- FIGURE 1: coverage over time --------------------------------------------------------------------
fig1 <- ggplot(coverage_by_year, aes(YEAR, pct_observed)) +           # base layer: one point/line per year, y = share ICIS-observed
  geom_line(color = PAL["blue"], linewidth = 0.9) +                  # the trend line
  geom_point(color = PAL["blue"], size = 1.6) +                      # a point marker per year on top of the line
  scale_x_continuous(breaks = seq(min(YEARS), max(YEARS), 5)) +      # x-axis ticks every 5 years, spanning the actual observed YEARS range (not hard-coded)
  scale_y_continuous(labels = label_percent(), limits = c(0, 1)) +   # y-axis as a percentage, fixed 0-100% range
  labs(title = "ICIS-Air facility-year coverage, 2005-2025",
       subtitle = sprintf("Share of the %s-facility x 21-year rectangle with an observed ICIS record",
                          format(overview$n_facilities, big.mark = ",")),  # subtitle text pulls n_facilities from the CSV-1 `overview` table computed above, so it can't drift out of sync with that CSV
       x = NULL, y = "Share observed", caption = "Source: data/datasets/regulatory.csv.gz (dataset 0).") +
  theme_journal
save_fig("reg_coverage_over_time.png", fig1)

# ---- FIGURE 2: mean event counts over time, key measures (observed subset), direct end-of-line labels --
KEY_MEAS <- c(N_INSPECTIONS = "Inspections", N_VIOLATIONS = "Violations", N_ENFORCEMENT = "Enforcement",
              N_CERTS = "Certifications", N_STACK_TESTS = "Stack tests")  # 5 of the 9 COUNT_COLS measures, chosen for this figure
by_year_meas <- rbindlist(lapply(names(KEY_MEAS), function(m)
  observed[, .(measure = KEY_MEAS[[m]], mean_count = mean(get(m), na.rm = TRUE)), by = YEAR]))  # mean count per observed facility-year, by measure x year -- long format for ggplot's color-by-measure mapping below
by_year_meas[, measure := factor(measure, levels = unname(KEY_MEAS))]  # fix legend/label order to match KEY_MEAS's declared order
end_labels <- by_year_meas[YEAR == max(YEAR)]                          # one row per measure at the final year, used to place the direct end-of-line text labels
pal5 <- unname(PAL[c("blue", "aqua", "yellow", "green", "violet")])   # 5-color subset of PAL, in the order the 5 measures will be colored

fig2 <- ggplot(by_year_meas, aes(YEAR, mean_count, color = measure)) +
  geom_line(linewidth = 0.8) +
  scale_color_manual(values = setNames(pal5, levels(by_year_meas$measure))) +  # map each measure level to a fixed color from pal5, in level order
  scale_x_continuous(breaks = seq(min(YEARS), max(YEARS), 5), expand = expansion(mult = c(0.02, 0.22))) +  # extra right-side expansion (22%) to leave room for the end-of-line labels
  geom_text(data = end_labels, aes(label = measure), hjust = 0, nudge_x = 0.5, size = 3.2, fontface = "bold") +  # the direct labels themselves, placed just right of each line's final point
  coord_cartesian(clip = "off") +                                    # allow the labels to render outside the normal plot panel bounds (into the expanded margin)
  labs(title = "Mean regulatory activity per observed facility-year, 2005-2025",
       subtitle = "ICIS-observed facility-years only (icis_observed == 1); unobserved years excluded, not coded 0",
       x = NULL, y = "Mean count per facility-year",
       caption = "Source: data/datasets/regulatory.csv.gz (dataset 0). Direct labels replace a legend (dataviz relief rule).") +
  theme_journal +
  theme(plot.margin = margin(t = 5.5, r = 14, b = 5.5, l = 5.5))     # extra right margin to match the axis expansion above, so labels aren't clipped by the device edge
save_fig("reg_activity_over_time.png", fig2, w = 8.3, h = 4.8)

# ---- FIGURE 3: distribution of inspections per observed facility-year (heavy right skew) ---------------
insp <- observed[!is.na(N_INSPECTIONS), .(N_INSPECTIONS)]             # observed subset, explicit NA-drop on N_INSPECTIONS (defensive, same as summarise_measure() above)
fig3 <- ggplot(insp, aes(N_INSPECTIONS)) +
  geom_histogram(binwidth = 1, fill = PAL["blue"], color = "white", linewidth = 0.15, boundary = -0.5) +  # 1-count-wide bins, boundary=-0.5 so bins align on integers (0, 1, 2, ...) rather than straddling them
  coord_cartesian(xlim = c(0, quantile(insp$N_INSPECTIONS, .99))) +   # x-axis visually truncated at the 99th percentile -- this only clips the DISPLAY (coord_cartesian, not scale_x_continuous with limits), so all data still contributes to the histogram bin heights, it's just that high-count bins beyond p99 aren't shown
  scale_y_continuous(labels = label_comma()) +
  labs(title = "Inspections per observed facility-year",
       subtitle = sprintf("n = %s observed facility-years; x-axis truncated at the 99th percentile (%.0f); %.1f%% are zero",
                          format(nrow(insp), big.mark = ","), quantile(insp$N_INSPECTIONS, .99), 100*mean(insp$N_INSPECTIONS==0)),  # subtitle recomputes n / p99 / pct-zero directly from `insp`, independent of summary_counts.csv above -- consistent as long as both draw from the same `observed` table, but a second independent computation of the same numbers rather than reading them back from CSV 3
       x = "Inspections (N_INSPECTIONS)", y = "Facility-years",
       caption = "Source: data/datasets/regulatory.csv.gz (dataset 0).") +
  theme_journal
save_fig("reg_inspections_distribution.png", fig3)

# ---- FIGURE 4: mean activity by pollutant classification, small multiples across 5 measures ------------
pal4 <- setNames(unname(PAL[c("blue", "red", "aqua", "violet")]), CLASS_LEVELS)  # 4 colors mapped to the 4 CLASS_LEVELS in order (Major/Synthetic Minor/Minor/Other-Unknown); note this reuses "aqua" for a 3rd slot here vs. pal5's use of aqua as its 2nd of 5 -- fine since these are different figures with different legends, just not the same color-to-category mapping across figures 2 and 4/5
MEAS_LABELS <- c(N_INSPECTIONS = "Inspections", N_VIOLATIONS = "Violations", N_ENFORCEMENT = "Enforcement",
                 N_CERTS = "Certifications", N_STACK_TESTS = "Stack tests")  # duplicate of KEY_MEAS above (same names, same values) -- redefined under a new name rather than reused
class_act <- copy(classification_activity)                            # copy so the factor-column addition below doesn't mutate the classification_activity table already written to CSV
class_act[, measure_label := factor(MEAS_LABELS[measure], levels = unname(MEAS_LABELS))]  # map machine measure name -> display label, fixed facet order

fig4 <- ggplot(class_act, aes(classification, mean_count, fill = classification)) +
  geom_col(width = 0.7) +
  facet_wrap(~measure_label, nrow = 1, scales = "free_y") +          # one panel per measure, each with its OWN y-axis scale (free_y) -- bars are not comparable in height across panels, only within a panel
  scale_fill_manual(values = pal4) +
  scale_x_discrete(labels = c("Major", "Synth.\nMinor", "Minor", "Other/\nUnk.")) +  # abbreviated 2-line x-axis labels to fit the narrow facet panels
  labs(title = "Regulatory activity by pollutant classification, 2005-2025",
       subtitle = "Mean count per ICIS-observed facility-year, by AIR_POLLUTANT_CLASS_DESC",
       x = NULL, y = "Mean count per observed facility-year",
       caption = "Source: data/datasets/regulatory.csv.gz (dataset 0). \"Other/Unknown\" pools unknown/not-applicable/other (4.2% of facilities).") +
  theme_journal +
  theme(strip.text = element_text(face = "bold", size = 9.5),
        axis.text.x = element_text(size = 7.5),
        panel.spacing = unit(1, "lines"))
save_fig("reg_activity_by_classification.png", fig4, w = 9.5, h = 4.3)

# ---- FIGURE 5: ICIS coverage rate by classification, over time -----------------------------------------
class_cov_year <- reg[, .(pct_observed = mean(ICIS_OBSERVED == 1)), by = .(YEAR, classification)][order(classification, YEAR)]  # coverage rate by year x classification, over ALL of reg (not `observed`) since the whole point is the observed VS unobserved share
end_labels5 <- class_cov_year[YEAR == max(YEAR)][order(pct_observed)]  # final-year value per classification, sorted ascending by value (so the label-declutter loop below processes them low-to-high)
# declutter: Minor and Other/Unknown land within ~1pp of each other at 2025 and collide -- enforce a minimum
# vertical gap between adjacent label positions (label_y != the plotted line value; geom_text below uses it).
MIN_GAP <- 0.035                                                      # minimum vertical separation (in y-axis share units) between adjacent end-of-line labels
end_labels5[, label_y := pct_observed]                                # label_y starts equal to the true value; only nudged where it collides with the previous label
for (i in seq(2, nrow(end_labels5)))                                  # walk the sorted labels bottom-to-top
  if (end_labels5$label_y[i] - end_labels5$label_y[i - 1] < MIN_GAP)  # if this label is too close to the one below it...
    end_labels5$label_y[i] <- end_labels5$label_y[i - 1] + MIN_GAP    # ...push it up just enough to clear the minimum gap (label_y only, NOT the underlying pct_observed value -- the line itself is unaffected, only the text label's y-position is adjusted)

fig5 <- ggplot(class_cov_year, aes(YEAR, pct_observed, color = classification)) +
  geom_line(linewidth = 0.8) +
  scale_color_manual(values = pal4) +
  scale_x_continuous(breaks = seq(min(YEARS), max(YEARS), 5), expand = expansion(mult = c(0.02, 0.22))) +
  scale_y_continuous(labels = label_percent(), limits = c(0, NA)) +   # y-axis floor fixed at 0%, no fixed ceiling (NA lets ggplot auto-scale the top)
  geom_text(data = end_labels5, aes(x = YEAR, y = label_y, label = classification),  # uses the DECLUTTERED label_y, not pct_observed, per the comment above
            hjust = 0, nudge_x = 0.5, size = 3.1, fontface = "bold", inherit.aes = FALSE) +  # inherit.aes=FALSE: this layer's aes() is independent of the base ggplot() aes(), since end_labels5 has different columns (label_y vs pct_observed)
  coord_cartesian(clip = "off") +
  labs(title = "ICIS-Air coverage rate by pollutant classification, 2005-2025",
       subtitle = "Share of facility-years with an observed ICIS record, by AIR_POLLUTANT_CLASS_DESC",
       x = NULL, y = "Share observed",
       caption = "Source: data/datasets/regulatory.csv.gz (dataset 0). Direct labels replace a legend (dataviz relief rule).") +
  theme_journal +
  theme(plot.margin = margin(t = 5.5, r = 14, b = 5.5, l = 5.5))
save_fig("reg_coverage_by_classification_over_time.png", fig5, w = 8.3, h = 4.8)

# ---- console summary ---------------------------------------------------------------------------------------
cat("data/datasets/regulatory.csv.gz -- profile summary\n")
cat("======================================================\n\n")
cat(sprintf("%s facilities x %d years (%d-%d) = %s facility-years | balanced: %s | ICIS-observed: %.1f%%\n",
            format(overview$n_facilities, big.mark=","), length(YEARS), overview$year_min, overview$year_max,
            format(overview$n_facility_years, big.mark=","), overview$balanced, 100*overview$pct_icis_observed))
cat("\nCOVERAGE BY YEAR\n"); print(as.data.frame(coverage_by_year), row.names = FALSE)
cat("\nKEY COUNT MEASURES (observed subset)\n"); print(as.data.frame(summary_counts), row.names = FALSE)
cat("\nBINARY FLAG PREVALENCE (facility-level)\n"); print(as.data.frame(binary_prevalence), row.names = FALSE)
cat("\nFACILITY-LEVEL OVERVIEW (R1/R7)\n"); print(as.data.frame(facility_level_overview), row.names = FALSE)
cat("\nNAICS 211111 vs. missing classification (S5 wrinkle)\n"); print(as.data.frame(naics_211111_coverage), row.names = FALSE)
cat("\nFINE-GRAINED ENFORCEMENT BY CLASS BUCKET (S5 wrinkle)\n"); print(as.data.frame(fine_grained_enforcement), row.names = FALSE)
cat(sprintf("\n5 figures written to %s:\n  reg_coverage_over_time.png, reg_activity_over_time.png, reg_inspections_distribution.png,\n  reg_activity_by_classification.png, reg_coverage_by_classification_over_time.png\n", OUT_FIG))

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# 1. (summarise_measure(), ~line 55) pct_na's denominator is the FULL panel (x_all = reg[[m]]), while every
#    other statistic in that row is computed on the observed, non-NA subset (x). Intended design (pct_na is
#    meant to report "share of the whole panel missing"), but easy to misread as relative to the observed n.
# 2. (freq_cat(), ~line 68) pct's denominator is facilities with a KNOWN, non-blank value for the variable
#    (NA/"" rows are dropped from both numerator and denominator) -- a DIFFERENT NA convention than CSV 6's
#    "Other/Unknown" classification bucket, which folds NA into the denominator as a residual category. Two
#    different "pct" conventions coexist in this file; check which one applies before comparing across CSVs.
# 3. (`observed` rebuild, ~line 111) `observed` is built once early (before `classification` exists), used
#    for CSVs 1-5, then rebuilt after `classification` is added so CSV 6/Figures can group by it. Correctly
#    commented and currently safe (nothing between the two definitions needs classification), but the
#    dependency ordering is enforced only by code position, not by structure -- a future insertion between
#    CSV 5 and the rebuild that assumes classification exists would break silently.
# 4. (classification_coverage, ~line 118) n_facilities is a distinct-PGM_SYS_ID count WITHIN each
#    classification bucket, computed on facility-YEAR rows -- correct only under the (stated, but here
#    unverified) assumption that a facility's classification never changes across its observed years. A
#    facility whose class changed would be counted in more than one bucket's n_facilities.
# 5. (facility_level_overview, ~line 137) n_facility_years_no_programs is a facility-YEAR count, unlike every
#    other field in the same table (which are facility-level counts/shares) -- a grain switch within one row
#    that's easy to misread as comparable in scale to its neighbors.
# 6. (fac_naics$is_missing_class, ~line 150) Deliberately a STRICT NA-only check, narrower than
#    `classification`'s "Other/Unknown" (NA + 3 named residual labels) -- this is the intended fine-vs-coarse
#    contrast the CSV exists to show, not a bug, but worth flagging as the load-bearing distinction for S5.
# 7. (Figure 3 subtitle, ~line 226) Recomputes n / p99 / pct-zero directly from `insp` rather than reading
#    them back from summary_counts.csv (CSV 3) -- a second independent computation of the same numbers. Both
#    draw from the same underlying `observed` table so they should always agree, but if CSV 3's computation
#    ever changes (e.g. a different NA-handling tweak in summarise_measure), this subtitle would silently
#    drift out of sync with the CSV rather than erroring.
# 8. (pal4 vs. pal5, ~line 201 & 232) Figure 4/5's 4-color palette reuses "aqua" in a different category slot
#    than Figure 2's 5-color palette does -- not a bug (each figure has its own self-contained legend/labels),
#    but the same color does not mean the same category across figures 2 and 4/5.
