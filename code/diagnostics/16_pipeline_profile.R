# =========================================================================================================
# code/diagnostics/16_pipeline_profile.R -- exploratory profiling of dataset 6 (pipeline.csv.gz, facility x
#   year) and its row-level source (data/processed/pipeline.csv.gz, real violations only). Purpose:
#   characterize both for a reader picking the project up cold. Companion to 11_operating_profile.R /
#   12_penalties_profile.R / 13_regulatory_profile.R / 14_hpv_profile.R (same discipline, different datasets).
#
#   in : data/processed/pipeline.csv.gz, data/datasets/pipeline.csv.gz
#   out: output/pipeline_profile/*.csv
#        output/figures/datasets/pipeline/pipeline_{linkage_rate_over_time,hpv_frv_share_over_time,
#        viol_to_ea_lag_distribution}.png
#
#   DISCIPLINE: pipeline.csv.gz (dataset 6) mirrors ds 0's zero-vs-NA gate (PL3) -- NA is unknown, never a
#   false 0; every rate below reports the NA share. The row-level source excludes the 7,193 EPA-generated
#   placeholder rows (PL1, no VIOL_START_DATE) exactly as 07_pipeline.R does. No numbers are hand-entered;
#   every cell is computed here. Hand-run (not part of RUN_ALL.R). No stochastic step.
#
#   FIGURE DESIGN: same print-ready convention as 13_regulatory_profile.R / 14_hpv_profile.R (dataviz skill,
#   validated categorical palette, direct end-of-line labels in place of a legend, 300dpi).
# =========================================================================================================
suppressPackageStartupMessages({library(data.table); library(ggplot2); library(scales)})
options(scipen = 999)

CLEAN    <- here::here("data/processed")
DATASETS <- here::here("data/datasets")
OUT      <- here::here("output/pipeline_profile")
OUT_FIG  <- here::here("output/figures/datasets/pipeline")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
dir.create(OUT_FIG, showWarnings = FALSE, recursive = TRUE)

YEARS <- 2005:2025                                      # same analysis window as the dataset layer (G1)

# =========================================================================================================
# PART A -- row-level source (data/processed/pipeline.csv.gz), real (non-placeholder) violations only
# =========================================================================================================
raw <- fread(file.path(CLEAN, "pipeline.csv.gz"))
raw[, `:=`(eval_date = as.Date(EVAL_DATE, format = "%m/%d/%Y"),
           viol_date = as.Date(VIOL_START_DATE, format = "%m/%d/%Y"),
           ea_date   = as.Date(EA_DATE, format = "%m/%d/%Y"))]
raw[, viol_year := year(viol_date)]
real <- raw[!is.na(viol_year) & viol_year %in% YEARS]   # drop placeholders (PL1) and out-of-window rows (G1)

# ---- CSV 1: overview + VIOL_TYPE breakdown ----------------------------------------------------------------
overview_raw <- data.table(n_rows_raw = nrow(raw), n_placeholder = raw[is.na(viol_year), .N],
                           n_real_in_window = nrow(real), n_facilities = uniqueN(real$SOURCE_ID))
fwrite(overview_raw, file.path(OUT, "overview_raw.csv"))

viol_type_breakdown <- real[, .N, by = VIOL_TYPE][order(-N)]
viol_type_breakdown[, pct := round(N / sum(N), 4)]
fwrite(viol_type_breakdown, file.path(OUT, "viol_type_breakdown.csv"))

# ---- CSV 2: linkage rates -- share of real violations tracing to a known evaluation / enforcement action --
linkage_rates <- data.table(
  n_real = nrow(real),
  n_with_eval = real[EVAL_FLAG == "Y", .N], pct_with_eval = round(real[EVAL_FLAG == "Y", .N] / nrow(real), 4),
  n_with_ea   = real[EA_FLAG == "Y", .N],   pct_with_ea   = round(real[EA_FLAG == "Y", .N] / nrow(real), 4),
  n_self_disclosed = real[EVAL_FLAG == "Y" & EVAL_TYPE_DESC == "Self-Disclosure", .N])
linkage_rates[, pct_self_disclosed_of_eval := round(n_self_disclosed / n_with_eval, 4)]
fwrite(linkage_rates, file.path(OUT, "linkage_rates.csv"))

# ---- CSV 3: EVAL_TYPE_DESC frequency (of the rows that carry a linked evaluation) --------------------------
eval_type_freq <- real[EVAL_FLAG == "Y" & EVAL_TYPE_DESC != "", .N, by = EVAL_TYPE_DESC][order(-N)]
eval_type_freq[, pct := round(N / sum(N), 4)]
fwrite(eval_type_freq, file.path(OUT, "eval_type_frequency.csv"))

# ---- CSV 4: EA_TYPE frequency (of the rows that carry a linked enforcement action) -------------------------
ea_type_freq <- real[EA_FLAG == "Y" & EA_TYPE != "", .N, by = EA_TYPE][order(-N)]
ea_type_freq[, pct := round(N / sum(N), 4)]
fwrite(ea_type_freq, file.path(OUT, "ea_type_frequency.csv"))

# ---- CSV 5: eval->violation lag (days), only rows with both dates and a non-negative lag -------------------
real[, eval_to_viol_lag := fifelse(EVAL_FLAG == "Y" & !is.na(eval_date) & viol_date >= eval_date,
                                   as.integer(viol_date - eval_date), NA_integer_)]
etv <- real[!is.na(eval_to_viol_lag), eval_to_viol_lag]
eval_to_viol_lag_summary <- data.table(n = length(etv), min = min(etv), p25 = quantile(etv, .25),
                                       median = median(etv), p75 = quantile(etv, .75), p90 = quantile(etv, .90),
                                       max = max(etv), mean = round(mean(etv), 1))
fwrite(eval_to_viol_lag_summary, file.path(OUT, "eval_to_viol_lag_days.csv"))

# ---- CSV 6: violation->enforcement lag (days), only rows with both dates and a non-negative lag ------------
real[, viol_to_ea_lag := fifelse(EA_FLAG == "Y" & !is.na(ea_date) & ea_date >= viol_date,
                                 as.integer(ea_date - viol_date), NA_integer_)]
vte <- real[!is.na(viol_to_ea_lag), viol_to_ea_lag]
viol_to_ea_lag_summary <- data.table(n = length(vte), min = min(vte), p25 = quantile(vte, .25),
                                     median = median(vte), p75 = quantile(vte, .75), p90 = quantile(vte, .90),
                                     max = max(vte), mean = round(mean(vte), 1))
fwrite(viol_to_ea_lag_summary, file.path(OUT, "viol_to_ea_lag_days.csv"))

# ---- CSV 7: EA_PENALTY_AMT among real violations with a positive linked penalty ----------------------------
real[, ea_penalty := suppressWarnings(as.numeric(EA_PENALTY_AMT))]
pen <- real[!is.na(ea_penalty) & ea_penalty > 0, ea_penalty]
penalty_summary <- data.table(n_with_penalty = length(pen), pct_of_real = round(length(pen) / nrow(real), 4),
                              min = min(pen), median = median(pen), p90 = quantile(pen, .90), max = max(pen),
                              total = sum(pen))
fwrite(penalty_summary, file.path(OUT, "ea_penalty_among_real_violations.csv"))

# =========================================================================================================
# PART B -- pipeline (dataset 6, facility x year, 5,863,431 rows)
# =========================================================================================================
pf <- fread(file.path(DATASETS, "pipeline.csv.gz"))

# ---- CSV 8: overview + observed/NA breakdown ---------------------------------------------------------------
overview_ds <- data.table(n_facility_years = nrow(pf), n_facilities = uniqueN(pf$PGM_SYS_ID),
                          n_observed = sum(pf$PIPELINE_OBSERVED == 1), n_unobserved = sum(pf$PIPELINE_OBSERVED == 0),
                          n_ever_observed_facilities = uniqueN(pf[PIPELINE_OBSERVED == 1, PGM_SYS_ID]))
overview_ds[, pct_observed := round(n_observed / n_facility_years, 4)]
fwrite(overview_ds, file.path(OUT, "overview_dataset.csv"))

# ---- CSV 9: observed facility-years and HPV/FRV split, by year (trend) --------------------------------------
obs <- pf[PIPELINE_OBSERVED == 1]
by_year <- obs[, .(n_obs = .N, n_hpv = sum(N_VIOL_HPV), n_frv = sum(N_VIOL_FRV),
                   n_with_eval = sum(N_VIOL_WITH_EVAL), n_with_ea = sum(N_VIOL_WITH_EA)), by = YEAR][order(YEAR)]
by_year[, `:=`(pct_hpv = round(n_hpv / (n_hpv + n_frv), 4),
              pct_viol_with_eval = round(n_with_eval / (n_hpv + n_frv), 4),
              pct_viol_with_ea   = round(n_with_ea   / (n_hpv + n_frv), 4))]
fwrite(by_year, file.path(OUT, "by_year_summary.csv"))

# ---- CSV 10: self-disclosure and penalty prevalence, dataset-wide (observed facility-years only) ------------
prevalence <- data.table(
  n_viol_total = sum(obs$N_VIOL_PIPELINE), n_self_disclosed = sum(obs$N_VIOL_SELF_DISCLOSED),
  n_with_ea_penalty = sum(obs$N_VIOL_WITH_EA_PENALTY), ea_penalty_amt_sum = sum(obs$EA_PENALTY_AMT_SUM))
prevalence[, `:=`(pct_self_disclosed = round(n_self_disclosed / n_viol_total, 4),
                  pct_with_ea_penalty = round(n_with_ea_penalty / n_viol_total, 4))]
fwrite(prevalence, file.path(OUT, "prevalence_summary.csv"))

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

# ---- FIGURE 1: linkage rate over time -- share of violations tracing to a known eval / enforcement action --
lr_long <- rbind(by_year[, .(YEAR, pct = pct_viol_with_eval, series = "linked to a known evaluation")],
                 by_year[, .(YEAR, pct = pct_viol_with_ea,   series = "linked to an enforcement action")])
lbl <- lr_long[YEAR == max(YEAR)]
fig1 <- ggplot(lr_long, aes(YEAR, pct, color = series)) +
  geom_line(linewidth = 0.9) + geom_point(size = 1.4) +
  scale_color_manual(values = c("linked to a known evaluation" = PAL[["blue"]],
                                "linked to an enforcement action" = PAL[["red"]])) +
  scale_x_continuous(breaks = seq(min(lr_long$YEAR), max(lr_long$YEAR), 5), expand = expansion(mult = c(0.02, 0.14))) +
  scale_y_continuous(labels = label_percent(), limits = c(0, NA)) +
  geom_text(data = lbl, aes(label = series), hjust = 0, nudge_x = 0.4, size = 3.1, fontface = "bold") +
  labs(title = "Share of pipeline violations linked to an evaluation or enforcement action, 2005-2025",
       subtitle = "Of observed facility-years' violations (dataset 6, PIPELINE_OBSERVED==1)",
       x = NULL, y = "Share of violations", caption = "Source: data/datasets/pipeline.csv.gz (dataset 6).") +
  theme_journal
save_fig("pipeline_linkage_rate_over_time.png", fig1)

# ---- FIGURE 2: HPV vs FRV share of pipeline violations over time -------------------------------------------
fig2 <- ggplot(by_year, aes(YEAR, pct_hpv)) +
  geom_line(color = PAL[["violet"]], linewidth = 0.9) + geom_point(color = PAL[["violet"]], size = 1.4) +
  scale_x_continuous(breaks = seq(min(by_year$YEAR), max(by_year$YEAR), 5)) +
  scale_y_continuous(labels = label_percent(), limits = c(0, NA)) +
  labs(title = "HPV share of pipeline violations, 2005-2025",
       subtitle = "Remainder is FRV (Federally Reportable Violation) -- the tier hpv_spells (dataset 2) excludes",
       x = NULL, y = "Share HPV (of HPV + FRV)", caption = "Source: data/datasets/pipeline.csv.gz (dataset 6).") +
  theme_journal
save_fig("pipeline_hpv_frv_share_over_time.png", fig2)

# ---- FIGURE 3: violation->enforcement lag distribution (truncated at p99 for readability) -------------------
p99 <- quantile(vte, .99)
fig3 <- ggplot(data.table(days = vte), aes(days)) +
  geom_histogram(binwidth = 15, fill = PAL[["blue"]], color = "white", linewidth = 0.15, boundary = 0) +
  coord_cartesian(xlim = c(0, p99)) +
  scale_x_continuous(labels = label_comma()) + scale_y_continuous(labels = label_comma()) +
  labs(title = "Violation-to-enforcement-action lag (days)",
       subtitle = sprintf("n = %s violations with a linked EA and a non-negative lag; x-axis truncated at the 99th pctile (%s days)",
                          format(length(vte), big.mark = ","), format(round(p99), big.mark = ",")),
       x = "Days from violation start to enforcement action", y = "Violations",
       caption = "Source: data/processed/pipeline.csv.gz, real (non-placeholder) rows.") +
  theme_journal
save_fig("pipeline_viol_to_ea_lag_distribution.png", fig3)

# ---- console summary -----------------------------------------------------------------------------------------
cat("data/processed/pipeline.csv.gz + data/datasets/pipeline.csv.gz -- profile summary\n")
cat("==========================================================================\n\n")
cat("PART A -- row-level source, real (non-placeholder) violations, 2005-2025\n")
print(as.data.frame(overview_raw), row.names = FALSE)
cat("\nVIOL_TYPE BREAKDOWN\n"); print(as.data.frame(viol_type_breakdown), row.names = FALSE)
cat("\nLINKAGE RATES\n"); print(as.data.frame(linkage_rates), row.names = FALSE)
cat("\nTOP EVAL_TYPE_DESC\n"); print(as.data.frame(head(eval_type_freq, 8)), row.names = FALSE)
cat("\nTOP EA_TYPE\n"); print(as.data.frame(head(ea_type_freq, 8)), row.names = FALSE)
cat("\nEVAL->VIOLATION LAG (days)\n"); print(as.data.frame(eval_to_viol_lag_summary), row.names = FALSE)
cat("\nVIOLATION->EA LAG (days)\n"); print(as.data.frame(viol_to_ea_lag_summary), row.names = FALSE)
cat("\nEA PENALTY AMONG REAL VIOLATIONS\n"); print(as.data.frame(penalty_summary), row.names = FALSE)

cat("\n\nPART B -- pipeline (facility x year, dataset 6)\n")
print(as.data.frame(overview_ds), row.names = FALSE)
cat("\nPREVALENCE (observed facility-years)\n"); print(as.data.frame(prevalence), row.names = FALSE)
cat("\nBY-YEAR SUMMARY (head)\n"); print(as.data.frame(head(by_year, 10)), row.names = FALSE)
