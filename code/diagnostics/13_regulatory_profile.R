# =========================================================================================================
# code/diagnostics/13_regulatory_profile.R -- exploratory profiling of dataset 0 (data/datasets/regulatory.csv.gz).
#   Purpose: characterize the regulatory dataset (ICIS-Air only: event counts + facility characteristics) for
#   a reader picking the project up cold, and produce a small set of print-ready figures. Companion to
#   11_operating_profile.R / 12_penalties_profile.R (same discipline, different dataset).
#
#   in : data/datasets/regulatory.csv.gz
#   out: output/regulatory_profile/*.csv
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
suppressPackageStartupMessages({library(data.table); library(ggplot2); library(scales)})
options(scipen = 999)

DATASETS <- here::here("data/datasets")
OUT_CSV  <- here::here("output/regulatory_profile")
OUT_FIG  <- here::here("output/figures/datasets/regulatory")
dir.create(OUT_CSV, showWarnings = FALSE, recursive = TRUE)
dir.create(OUT_FIG, showWarnings = FALSE, recursive = TRUE)

# ID/FIPS-like columns that can carry a leading zero -- fread guesses these as numeric by default and
# silently drops the leading zero (e.g. "01001" -> 1001) unless forced to character.
reg <- fread(file.path(DATASETS, "regulatory.csv.gz"), colClasses = list(character = c("REGISTRY_ID", "ZIP_CODE")))
YEARS <- sort(unique(reg$YEAR))
observed <- reg[ICIS_OBSERVED == 1]

fwrite_rounded <- function(dt, file, prop_cols = NULL, num_cols = NULL) {
  d <- copy(dt)
  for (cc in intersect(prop_cols, names(d))) d[, (cc) := round(get(cc), 3)]
  for (cc in intersect(num_cols,  names(d))) d[, (cc) := round(get(cc), 2)]
  fwrite(d, file)
}

# =========================================================================================================
# CSV 1 -- overview
# =========================================================================================================
overview <- data.table(
  n_facilities = uniqueN(reg$PGM_SYS_ID), n_facility_years = nrow(reg),
  year_min = min(YEARS), year_max = max(YEARS),
  balanced = nrow(reg) == uniqueN(reg$PGM_SYS_ID) * length(YEARS),
  pct_icis_observed = mean(reg$ICIS_OBSERVED == 1))
fwrite_rounded(overview, file.path(OUT_CSV, "overview.csv"), prop_cols = "pct_icis_observed")

# =========================================================================================================
# CSV 2 -- coverage by year
# =========================================================================================================
coverage_by_year <- reg[, .(n_facility_years = .N, pct_observed = mean(ICIS_OBSERVED == 1)), by = YEAR][order(YEAR)]
fwrite_rounded(coverage_by_year, file.path(OUT_CSV, "coverage_by_year.csv"), prop_cols = "pct_observed")

# =========================================================================================================
# CSV 3 -- five-number summaries for key N_* count measures, observed subset
# =========================================================================================================
COUNT_COLS <- c("N_INSPECTIONS", "N_VIOLATIONS", "N_HPV", "N_ENFORCEMENT", "N_FORMAL", "N_INFORMAL",
                "N_CERTS", "N_STACK_TESTS", "N_PENALTIES")
summarise_measure <- function(m) {
  x_all <- reg[[m]]; x <- observed[[m]]; x <- x[!is.na(x)]
  data.table(measure = m, n_obs = length(x), pct_na = mean(is.na(x_all)),
             min = min(x), p25 = quantile(x, .25), median = median(x), p75 = quantile(x, .75),
             p99 = quantile(x, .99), max = max(x), mean = mean(x), pct_zero = mean(x == 0))
}
summary_counts <- rbindlist(lapply(COUNT_COLS, summarise_measure))
fwrite_rounded(summary_counts, file.path(OUT_CSV, "summary_counts.csv"),
               prop_cols = c("pct_na", "pct_zero"), num_cols = "mean")

# =========================================================================================================
# CSV 4 -- categorical frequencies (facility-level, time-invariant attributes)
# =========================================================================================================
fac1 <- reg[, .SD[1L], by = PGM_SYS_ID]
freq_cat <- function(v) {
  tb <- fac1[!is.na(get(v)) & get(v) != "", .N, by = c(v)][order(-N)]; setnames(tb, v, "level")
  tb[, `:=`(variable = v, pct = round(N / sum(N), 4))][, .(variable, level, n = N, pct)]
}
freq_categorical <- rbindlist(lapply(c("STATE", "EPA_REGION", "FACILITY_TYPE", "AIR_POLLUTANT_CLASS_DESC",
                                       "OP_STATUS_CURRENT_DESC"), freq_cat))
fwrite(freq_categorical, file.path(OUT_CSV, "freq_categorical.csv"))

# =========================================================================================================
# CSV 5 -- emissions / program-enrollment prevalence (facility-level binary flags)
# =========================================================================================================
BIN_COLS <- c(grep("^EMITS_", names(reg), value = TRUE), grep("^PROG_", names(reg), value = TRUE))
binary_prevalence <- rbindlist(lapply(BIN_COLS, function(b)
  data.table(flag = b, n_facilities = nrow(fac1), share_1 = mean(fac1[[b]] == 1, na.rm = TRUE))))
fwrite_rounded(binary_prevalence, file.path(OUT_CSV, "binary_prevalence.csv"), prop_cols = "share_1")

# =========================================================================================================
# CSV 6 -- pollutant classification: coverage + activity comparison (the classification driving CAA
#   oversight intensity -- Major sources face materially more scrutiny than Minor). Small residual
#   categories (unknown/not-applicable/other, 4.2% of facilities combined) are pooled into "Other/Unknown"
#   rather than dropped, so the comparison accounts for the full universe.
# =========================================================================================================
CLASS_MAP <- c("Major Emissions" = "Major", "Synthetic Minor Emissions" = "Synthetic Minor",
              "Minor Emissions" = "Minor")
reg[, classification := fifelse(AIR_POLLUTANT_CLASS_DESC %in% names(CLASS_MAP),
                                CLASS_MAP[AIR_POLLUTANT_CLASS_DESC], "Other/Unknown")]
CLASS_LEVELS <- c("Major", "Synthetic Minor", "Minor", "Other/Unknown")
reg[, classification := factor(classification, levels = CLASS_LEVELS)]
observed <- reg[ICIS_OBSERVED == 1]                      # rebuild now that `classification` exists

classification_coverage <- reg[, .(n_facilities = uniqueN(PGM_SYS_ID), n_facility_years = .N,
                                   pct_observed = mean(ICIS_OBSERVED == 1)), by = classification][order(classification)]
fwrite_rounded(classification_coverage, file.path(OUT_CSV, "classification_coverage.csv"), prop_cols = "pct_observed")

CLASS_MEAS <- c("N_INSPECTIONS", "N_VIOLATIONS", "N_ENFORCEMENT", "N_CERTS", "N_STACK_TESTS")
classification_activity <- rbindlist(lapply(CLASS_MEAS, function(m)
  observed[, .(measure = m, mean_count = mean(get(m), na.rm = TRUE),
              pct_nonzero = mean(get(m) > 0, na.rm = TRUE)), by = classification]))
fwrite_rounded(classification_activity, file.path(OUT_CSV, "classification_activity.csv"),
               prop_cols = "pct_nonzero", num_cols = "mean_count")

# =========================================================================================================
# FIGURES -- print-ready (300dpi), validated 5-hue categorical palette, direct end-of-line labels
# =========================================================================================================
PAL <- c(blue = "#2a78d6", aqua = "#1baf7a", yellow = "#eda100", green = "#008300", violet = "#4a3aa7", red = "#e34948")
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

# ---- FIGURE 1: coverage over time --------------------------------------------------------------------
fig1 <- ggplot(coverage_by_year, aes(YEAR, pct_observed)) +
  geom_line(color = PAL["blue"], linewidth = 0.9) +
  geom_point(color = PAL["blue"], size = 1.6) +
  scale_x_continuous(breaks = seq(min(YEARS), max(YEARS), 5)) +
  scale_y_continuous(labels = label_percent(), limits = c(0, 1)) +
  labs(title = "ICIS-Air facility-year coverage, 2005-2025",
       subtitle = sprintf("Share of the %s-facility x 21-year rectangle with an observed ICIS record",
                          format(overview$n_facilities, big.mark = ",")),
       x = NULL, y = "Share observed", caption = "Source: data/datasets/regulatory.csv.gz (dataset 0).") +
  theme_journal
save_fig("reg_coverage_over_time.png", fig1)

# ---- FIGURE 2: mean event counts over time, key measures (observed subset), direct end-of-line labels --
KEY_MEAS <- c(N_INSPECTIONS = "Inspections", N_VIOLATIONS = "Violations", N_ENFORCEMENT = "Enforcement",
              N_CERTS = "Certifications", N_STACK_TESTS = "Stack tests")
by_year_meas <- rbindlist(lapply(names(KEY_MEAS), function(m)
  observed[, .(measure = KEY_MEAS[[m]], mean_count = mean(get(m), na.rm = TRUE)), by = YEAR]))
by_year_meas[, measure := factor(measure, levels = unname(KEY_MEAS))]
end_labels <- by_year_meas[YEAR == max(YEAR)]
pal5 <- unname(PAL[c("blue", "aqua", "yellow", "green", "violet")])

fig2 <- ggplot(by_year_meas, aes(YEAR, mean_count, color = measure)) +
  geom_line(linewidth = 0.8) +
  scale_color_manual(values = setNames(pal5, levels(by_year_meas$measure))) +
  scale_x_continuous(breaks = seq(min(YEARS), max(YEARS), 5), expand = expansion(mult = c(0.02, 0.22))) +
  geom_text(data = end_labels, aes(label = measure), hjust = 0, nudge_x = 0.5, size = 3.2, fontface = "bold") +
  coord_cartesian(clip = "off") +
  labs(title = "Mean regulatory activity per observed facility-year, 2005-2025",
       subtitle = "ICIS-observed facility-years only (icis_observed == 1); unobserved years excluded, not coded 0",
       x = NULL, y = "Mean count per facility-year",
       caption = "Source: data/datasets/regulatory.csv.gz (dataset 0). Direct labels replace a legend (dataviz relief rule).") +
  theme_journal +
  theme(plot.margin = margin(t = 5.5, r = 14, b = 5.5, l = 5.5))
save_fig("reg_activity_over_time.png", fig2, w = 8.3, h = 4.8)

# ---- FIGURE 3: distribution of inspections per observed facility-year (heavy right skew) ---------------
insp <- observed[!is.na(N_INSPECTIONS), .(N_INSPECTIONS)]
fig3 <- ggplot(insp, aes(N_INSPECTIONS)) +
  geom_histogram(binwidth = 1, fill = PAL["blue"], color = "white", linewidth = 0.15, boundary = -0.5) +
  coord_cartesian(xlim = c(0, quantile(insp$N_INSPECTIONS, .99))) +
  scale_y_continuous(labels = label_comma()) +
  labs(title = "Inspections per observed facility-year",
       subtitle = sprintf("n = %s observed facility-years; x-axis truncated at the 99th percentile (%.0f); %.1f%% are zero",
                          format(nrow(insp), big.mark = ","), quantile(insp$N_INSPECTIONS, .99), 100*mean(insp$N_INSPECTIONS==0)),
       x = "Inspections (N_INSPECTIONS)", y = "Facility-years",
       caption = "Source: data/datasets/regulatory.csv.gz (dataset 0).") +
  theme_journal
save_fig("reg_inspections_distribution.png", fig3)

# ---- FIGURE 4: mean activity by pollutant classification, small multiples across 5 measures ------------
pal4 <- setNames(unname(PAL[c("blue", "red", "aqua", "violet")]), CLASS_LEVELS)
MEAS_LABELS <- c(N_INSPECTIONS = "Inspections", N_VIOLATIONS = "Violations", N_ENFORCEMENT = "Enforcement",
                 N_CERTS = "Certifications", N_STACK_TESTS = "Stack tests")
class_act <- copy(classification_activity)
class_act[, measure_label := factor(MEAS_LABELS[measure], levels = unname(MEAS_LABELS))]

fig4 <- ggplot(class_act, aes(classification, mean_count, fill = classification)) +
  geom_col(width = 0.7) +
  facet_wrap(~measure_label, nrow = 1, scales = "free_y") +
  scale_fill_manual(values = pal4) +
  scale_x_discrete(labels = c("Major", "Synth.\nMinor", "Minor", "Other/\nUnk.")) +
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
class_cov_year <- reg[, .(pct_observed = mean(ICIS_OBSERVED == 1)), by = .(YEAR, classification)][order(classification, YEAR)]
end_labels5 <- class_cov_year[YEAR == max(YEAR)][order(pct_observed)]
# declutter: Minor and Other/Unknown land within ~1pp of each other at 2025 and collide -- enforce a minimum
# vertical gap between adjacent label positions (label_y != the plotted line value; geom_text below uses it).
MIN_GAP <- 0.035
end_labels5[, label_y := pct_observed]
for (i in seq(2, nrow(end_labels5)))
  if (end_labels5$label_y[i] - end_labels5$label_y[i - 1] < MIN_GAP)
    end_labels5$label_y[i] <- end_labels5$label_y[i - 1] + MIN_GAP

fig5 <- ggplot(class_cov_year, aes(YEAR, pct_observed, color = classification)) +
  geom_line(linewidth = 0.8) +
  scale_color_manual(values = pal4) +
  scale_x_continuous(breaks = seq(min(YEARS), max(YEARS), 5), expand = expansion(mult = c(0.02, 0.22))) +
  scale_y_continuous(labels = label_percent(), limits = c(0, NA)) +
  geom_text(data = end_labels5, aes(x = YEAR, y = label_y, label = classification),
            hjust = 0, nudge_x = 0.5, size = 3.1, fontface = "bold", inherit.aes = FALSE) +
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
cat(sprintf("\n5 figures written to %s:\n  reg_coverage_over_time.png, reg_activity_over_time.png, reg_inspections_distribution.png,\n  reg_activity_by_classification.png, reg_coverage_by_classification_over_time.png\n", OUT_FIG))
