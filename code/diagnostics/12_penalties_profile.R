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
#
#   DISCIPLINE: PENALTY_AMOUNT is real for every row (0/none IS a value here, not NA -- ds3 is action-level,
#   not the facility-year zero-vs-NA convention of ds0/ds1). dup/dup_exact are event-key flags, NOT deduped
#   out (layer convention) -- summaries below report both all-rows and dup==0 views where it matters.
#   No numbers are hand-entered; every cell is computed here. Hand-run (not part of RUN_ALL.R). No stochastic step.
# =========================================================================================================
suppressPackageStartupMessages({library(data.table)})
options(scipen = 999)

DATASETS <- here::here("data/datasets")
OUT      <- here::here("output/penalties_profile")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

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
