# =========================================================================================================
# code/diagnostics/12_penalties_profile.R -- exploratory profiling of dataset 3 (data/datasets/penalties.csv.gz).
#   Purpose: characterize the penalties dataset for a reader picking the project up cold -- coverage,
#   penalty-amount distribution, action/enforcement-type composition, and the multi-facility settlement
#   structure (P5). The settlement-structure deep dive that actually informs the broadcast-rule DECISION
#   lives in briefs/datasets/multi_facility_settlement_decision.md, not here -- this script is descriptive only.
#   Companion to 11_operating_profile.R (same discipline, different dataset).
#
#   in : data/datasets/penalties.csv.gz
#   out: output/penalties_profile/*.csv
#        output/figures/datasets/penalties/pen_{amount_distribution,total_by_year,co_defendant_distribution}.png
#
#   DISCIPLINE: PENALTY_AMOUNT is real for every row (0/none IS a value here, not NA -- ds3 is action-level,
#   not the facility-year zero-vs-NA convention of ds0/ds1). dup/dup_exact are event-key flags, NOT deduped
#   out (layer convention) -- summaries below report both all-rows and dup==0 views where it matters.
#   No numbers are hand-entered; every cell is computed here. Hand-run (not part of RUN_ALL.R). No stochastic step.
#
#   FIGURE DESIGN: same print-ready convention as 13_regulatory_profile.R (dataviz skill, validated
#   categorical palette, direct end-of-line labels in place of a legend, 300dpi). The by-year total-$ figure
#   is naive (dup==0, not settlement-broadcast-corrected) -- see multi_facility_settlement_decision.md for why
#   that matters (35.2% of the all-time total is broadcast inflation); noted in the figure caption, not fixed.
# =========================================================================================================
suppressPackageStartupMessages({library(data.table); library(ggplot2); library(scales)})
options(scipen = 999)

DATASETS <- here::here("data/datasets")
OUT      <- here::here("output/penalties_profile")
OUT_FIG  <- here::here("output/figures/datasets/penalties")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
dir.create(OUT_FIG, showWarnings = FALSE, recursive = TRUE)

pen <- fread(file.path(DATASETS, "penalties.csv.gz"))

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
  n_actions            = nrow(pen),
  n_facilities         = uniqueN(pen$PGM_SYS_ID),
  n_settlements        = uniqueN(pen$ENF_IDENTIFIER),
  year_min             = min(pen$YEAR, na.rm = TRUE), year_max = max(pen$YEAR, na.rm = TRUE),
  pct_has_penalty      = mean(pen$HAS_PENALTY == 1),
  total_penalty_all_rows = sum(pen$PENALTY_AMOUNT),
  total_penalty_dup0     = pen[DUP == 0, sum(PENALTY_AMOUNT)],
  pct_actions_multi_facility = mean(pen$IS_MULTI_FACILITY == 1),
  pct_dup_gt0          = mean(pen$DUP > 0))
fwrite_rounded(overview, file.path(OUT, "overview.csv"),
               prop_cols = c("pct_has_penalty", "pct_actions_multi_facility", "pct_dup_gt0"),
               num_cols = c("total_penalty_all_rows", "total_penalty_dup0"))

# =========================================================================================================
# CSV 2 -- penalty amount five-number summary, nonzero rows only (all rows, then dup==0 only)
# =========================================================================================================
summarise_penalty <- function(d, label) {
  x <- d[PENALTY_AMOUNT > 0, PENALTY_AMOUNT]
  data.table(subset = label, n_nonzero = length(x), min = min(x), p25 = quantile(x, .25),
             median = median(x), p75 = quantile(x, .75), p99 = quantile(x, .99), max = max(x),
             mean = mean(x), total = sum(x))
}
summary_penalty <- rbindlist(list(summarise_penalty(pen, "all rows"), summarise_penalty(pen[DUP == 0], "dup==0 only")))
fwrite_rounded(summary_penalty, file.path(OUT, "summary_penalty.csv"), num_cols = c("mean", "total"))

# =========================================================================================================
# CSV 3 -- penalties by year (dup==0, count + total + nonzero share)
# =========================================================================================================
by_year <- pen[DUP == 0, .(n_actions = .N, n_with_penalty = sum(HAS_PENALTY),
                           total_penalty = sum(PENALTY_AMOUNT)), by = YEAR][order(YEAR)]
by_year[, pct_with_penalty := round(n_with_penalty / n_actions, 3)]
fwrite_rounded(by_year, file.path(OUT, "by_year.csv"), num_cols = "total_penalty")

# =========================================================================================================
# CSV 4 -- ENF_TYPE / ACTIVITY_TYPE / STATE_EPA_FLAG frequency (dup==0)
# =========================================================================================================
freq_cat <- function(d, v) {
  tb <- d[, .N, by = c(v)][order(-N)]; setnames(tb, v, "level")
  tb[, `:=`(variable = v, pct = round(N / sum(N), 4))][, .(variable, level, n = N, pct)]
}
d0 <- pen[DUP == 0]
freq_categorical <- rbindlist(lapply(c("ENF_TYPE_DESC", "ACTIVITY_TYPE_DESC", "STATE_EPA_FLAG"), freq_cat, d = d0))
fwrite(freq_categorical, file.path(OUT, "freq_categorical.csv"))

# =========================================================================================================
# CSV 5 -- multi-facility settlement structure (headline numbers only; deep dive is in the brief)
# =========================================================================================================
settlements <- pen[, .(n_facilities = uniqueN(PGM_SYS_ID), n_rows = .N,
                       n_distinct_amounts = uniqueN(PENALTY_AMOUNT)), by = ENF_IDENTIFIER]
multi <- settlements[n_facilities > 1]
settlement_structure <- data.table(
  n_settlements_total          = nrow(settlements),
  n_settlements_multi_facility = nrow(multi),
  pct_settlements_multi_facility = round(nrow(multi) / nrow(settlements), 4),
  max_co_defendants            = max(settlements$n_facilities),
  n_multi_with_uniform_amount  = multi[n_distinct_amounts == 1, .N],
  n_multi_with_differing_amounts = multi[n_distinct_amounts > 1, .N])
fwrite(settlement_structure, file.path(OUT, "settlement_structure.csv"))

co_defendant_dist <- settlements[n_facilities > 1, .N, by = n_facilities][order(n_facilities)]
fwrite(co_defendant_dist, file.path(OUT, "co_defendant_distribution.csv"))

# =========================================================================================================
# CSV 6 -- settlement-broadcast deep dive backing briefs/datasets/multi_facility_settlement_decision.md.
#   METHOD (must stay consistent throughout, per that brief's correction note): settlement structure --
#   which ENF_IDENTIFIERs are multi-facility / uniform / differing -- is identified from ALL rows, matching
#   the dataset's own shipped IS_MULTI_FACILITY/N_SETTLEMENT_FACILITIES columns (built in 05_penalties.R from
#   unfiltered data). Dollar and spread figures are then computed from DUP==0 rows WITHIN those identified
#   settlements only -- consistent with stripping row-level duplicate inflation before the cross-facility
#   comparison (same rationale as summary_penalty/by_year above). Mixing the two (e.g. identifying via
#   DUP==0-first grouping) changes which settlements even qualify as "differing" -- a real bug caught while
#   extending this analysis, corrected in the brief.
# =========================================================================================================
multi_ids  <- settlements[n_facilities > 1, ENF_IDENTIFIER]
differ_ids <- settlements[n_facilities > 1 & n_distinct_amounts > 1, ENF_IDENTIFIER]

dollars_for <- function(ids) {
  x <- d0[ENF_IDENTIFIER %in% ids, .(naive = sum(PENALTY_AMOUNT), distinct = sum(unique(PENALTY_AMOUNT))), by = ENF_IDENTIFIER]
  data.table(n_settlements = length(ids), naive_sum = sum(x$naive), distinct_sum = sum(x$distinct))
}
settlement_dollars <- rbindlist(list(
  cbind(population = "all 588 multi-facility", dollars_for(multi_ids)),
  cbind(population = "72 differing-amount",     dollars_for(differ_ids))))
fwrite(settlement_dollars, file.path(OUT, "settlement_dollars_by_population.csv"))

# per-settlement spread (max-min) for the 72 differing ones, DUP==0 basis
differ_detail <- d0[ENF_IDENTIFIER %in% differ_ids,
                    .(min_amt = min(PENALTY_AMOUNT), max_amt = max(PENALTY_AMOUNT),
                      naive = sum(PENALTY_AMOUNT), distinct = sum(unique(PENALTY_AMOUNT))), by = ENF_IDENTIFIER]
differ_detail[, spread := max_amt - min_amt]
differ_detail[, trivial := spread <= 5]
differ_detail[, is_texas := grepl("^TX", ENF_IDENTIFIER)]
fwrite(differ_detail, file.path(OUT, "differing_settlements_detail.csv"))

differ_summary <- differ_detail[, .(n_settlements = .N, naive_sum = sum(naive), distinct_sum = sum(distinct),
                                    n_texas = sum(is_texas)), by = trivial][order(-trivial)]
fwrite(differ_summary, file.path(OUT, "differing_settlements_trivial_vs_large.csv"))

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

# ---- FIGURE 1: penalty amount distribution (nonzero, dup==0), log10 x-axis given heavy right skew ---------
nz <- d0[PENALTY_AMOUNT > 0, PENALTY_AMOUNT]
fig1 <- ggplot(data.table(amount = nz), aes(amount)) +
  geom_histogram(bins = 50, fill = PAL[["blue"]], color = "white", linewidth = 0.1) +
  scale_x_log10(labels = label_dollar(scale_cut = cut_short_scale())) +
  scale_y_continuous(labels = label_comma()) +
  labs(title = "Penalty amount distribution (nonzero actions)",
       subtitle = sprintf("n = %s nonzero, DUP==0 actions; log10 x-axis (heavy right skew: median $%s, max $%s)",
                          format(length(nz), big.mark = ","), format(round(median(nz)), big.mark = ","),
                          format(round(max(nz)), big.mark = ",")),
       x = "Penalty amount (log scale)", y = "Actions", caption = "Source: data/datasets/penalties.csv.gz (dataset 3).") +
  theme_journal
save_fig("pen_amount_distribution.png", fig1)

# ---- FIGURE 2: total penalty dollars by year (naive, dup==0 -- see caption caveat) --------------------------
by_year_plot <- by_year[YEAR >= 1990 & YEAR <= 2025]
fig2 <- ggplot(by_year_plot, aes(YEAR, total_penalty)) +
  geom_col(fill = PAL[["blue"]], width = 0.8) +
  scale_x_continuous(breaks = seq(1990, 2025, 5)) +
  scale_y_continuous(labels = label_dollar(scale_cut = cut_short_scale())) +
  labs(title = "Total penalty dollars by year, 1990-2025",
       subtitle = "Naive sum (DUP==0, NOT settlement-broadcast-corrected) -- large multi-facility settlements can\ninflate a single year materially; see multi_facility_settlement_decision.md (35.2% of the all-time\ntotal is broadcast inflation, concentrated in a handful of large settlements)",
       x = NULL, y = "Total penalty ($)", caption = "Source: data/datasets/penalties.csv.gz (dataset 3). 1972-1989 omitted (sparse, <150 actions/year combined).") +
  theme_journal + theme(plot.subtitle = element_text(color = INK_SECONDARY, size = 8.3, lineheight = 1.15))
save_fig("pen_total_by_year.png", fig2, w = 8, h = 4.8)

# ---- FIGURE 3: co-defendant count distribution (multi-facility settlements), log10 y given long tail --------
fig3 <- ggplot(co_defendant_dist, aes(n_facilities, N)) +
  geom_col(fill = PAL[["blue"]], width = 0.8) +
  scale_x_continuous(breaks = c(2, 5, 10, 20, 50, 100, 117)) +
  scale_y_log10(labels = label_comma()) +
  labs(title = "Co-defendant count distribution, multi-facility settlements",
       subtitle = sprintf("n = %s multi-facility settlements; log10 y-axis; max %s co-defendants in one settlement",
                          format(sum(co_defendant_dist$N), big.mark = ","), format(max(co_defendant_dist$n_facilities))),
       x = "Facilities in the settlement", y = "Settlements (log scale)",
       caption = "Source: data/datasets/penalties.csv.gz (dataset 3).") +
  theme_journal
save_fig("pen_co_defendant_distribution.png", fig3)

# ---- console summary ---------------------------------------------------------------------------------------
cat("data/datasets/penalties.csv.gz -- profile summary\n")
cat("=====================================================\n\n")
cat(sprintf("%s actions | %s facilities | %s settlements | years %d-%d\n",
            format(overview$n_actions, big.mark=","), format(overview$n_facilities, big.mark=","),
            format(overview$n_settlements, big.mark=","), overview$year_min, overview$year_max))
cat(sprintf("has_penalty: %.1f%% | total $ (all rows, INCLUDES broadcast/dup double-counting): $%s | total $ (dup==0): $%s\n",
            100*overview$pct_has_penalty, format(round(overview$total_penalty_all_rows), big.mark=","),
            format(round(overview$total_penalty_dup0), big.mark=",")))
cat("\nPENALTY AMOUNT SUMMARY (nonzero)\n"); print(as.data.frame(summary_penalty), row.names = FALSE)
cat("\nBY YEAR (dup==0)\n"); print(as.data.frame(by_year), row.names = FALSE)
cat("\nCATEGORICAL FREQUENCIES (dup==0)\n"); print(as.data.frame(freq_categorical), row.names = FALSE)
cat("\nSETTLEMENT STRUCTURE\n"); print(as.data.frame(settlement_structure), row.names = FALSE)
cat("\nCO-DEFENDANT COUNT DISTRIBUTION (multi-facility settlements)\n")
print(as.data.frame(co_defendant_dist), row.names = FALSE)
cat("\nSETTLEMENT DOLLARS BY POPULATION (DUP==0 basis)\n"); print(as.data.frame(settlement_dollars), row.names = FALSE)
cat("\nDIFFERING SETTLEMENTS: TRIVIAL (spread<=$5) VS GENUINELY LARGE\n")
print(as.data.frame(differ_summary), row.names = FALSE)
