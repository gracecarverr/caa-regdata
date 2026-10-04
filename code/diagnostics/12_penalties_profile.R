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
suppressPackageStartupMessages({library(data.table); library(ggplot2); library(scales)})  # load data.table/ggplot2/scales quietly (suppress each package's startup banner)
options(scipen = 999)                                                 # disable scientific notation so dollar totals print as e.g. 1200000, not 1.2e+06

DATASETS <- here::here("data/datasets")                               # source dir for the built datasets layer
OUT      <- here::here("output/penalties_profile")                    # destination dir for this script's CSV outputs
OUT_FIG  <- here::here("output/figures/datasets/penalties")           # destination dir for this script's figure PNGs
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)               # create OUT if missing; no warning if it already exists
dir.create(OUT_FIG, showWarnings = FALSE, recursive = TRUE)           # same for the figures dir

pen <- fread(file.path(DATASETS, "penalties.csv.gz"))                 # read dataset 3 in full -- one row per enforcement action; not deduped (DUP/DUP_EXACT flags retained, see header)

fwrite_rounded <- function(dt, file, prop_cols = NULL, num_cols = NULL) {  # shared CSV writer: rounds proportion/dollar columns before writing so output files are print-clean
  d <- copy(dt)                                                       # copy so rounding doesn't mutate the caller's data.table by reference
  for (cc in intersect(prop_cols, names(d))) d[, (cc) := round(get(cc), 3)]  # round share/proportion columns to 3 decimals
  for (cc in intersect(num_cols,  names(d))) d[, (cc) := round(get(cc), 2)]  # round dollar/count columns to 2 decimals
  fwrite(d, file)                                                     # write the rounded copy to disk
}

# =========================================================================================================
# CSV 1 -- overview
# =========================================================================================================
overview <- data.table(
  n_actions            = nrow(pen),                                  # total action-level rows, all rows (no dup filter) -- one row per action/settlement-facility pairing as shipped
  n_facilities         = uniqueN(pen$PGM_SYS_ID),                     # distinct facilities appearing anywhere in the dataset
  n_settlements        = uniqueN(pen$ENF_IDENTIFIER),                 # distinct settlements/enforcement identifiers (an ENF_IDENTIFIER can span multiple facilities -- see CSV 5)
  year_min             = min(pen$YEAR, na.rm = TRUE), year_max = max(pen$YEAR, na.rm = TRUE),  # observed year range; na.rm guards against any NA YEAR rows
  pct_has_penalty      = mean(pen$HAS_PENALTY == 1),                  # share of all-rows actions flagged as carrying a penalty (derived flag, not literally PENALTY_AMOUNT > 0 recomputed here)
  total_penalty_all_rows = sum(pen$PENALTY_AMOUNT),                   # FLAG: sums PENALTY_AMOUNT over EVERY row -- includes DUP>0 duplicate rows AND every co-defendant facility's own full copy of a multi-facility settlement amount, so this is a deliberate upper-bound total (double-counts both dup rows and settlement broadcast), not a "true" total; labeled explicitly in the console summary below
  total_penalty_dup0     = pen[DUP == 0, sum(PENALTY_AMOUNT)],        # FLAG: removes DUP>0 rows but does NOT correct multi-facility broadcast (each co-defendant facility still carries its own full copy of the settlement amount) -- "dup==0" and "broadcast-corrected" are two different corrections; only the CSV 6 deep dive below addresses the latter
  pct_actions_multi_facility = mean(pen$IS_MULTI_FACILITY == 1),      # share of all-rows actions belonging to a multi-facility (co-defendant) settlement
  pct_dup_gt0          = mean(pen$DUP > 0))                           # share of all-rows actions that are event-key duplicates (DUP flag > 0); not deduped out anywhere below unless explicitly noted
fwrite_rounded(overview, file.path(OUT, "overview.csv"),
               prop_cols = c("pct_has_penalty", "pct_actions_multi_facility", "pct_dup_gt0"),  # share columns to round to 3dp
               num_cols = c("total_penalty_all_rows", "total_penalty_dup0"))  # dollar columns to round to 2dp

# =========================================================================================================
# CSV 2 -- penalty amount five-number summary, nonzero rows only (all rows, then dup==0 only)
# =========================================================================================================
summarise_penalty <- function(d, label) {                             # five-number summary of PENALTY_AMOUNT, restricted to nonzero rows within whatever subset `d` is
  x <- d[PENALTY_AMOUNT > 0, PENALTY_AMOUNT]                          # FLAG: deliberately excludes real $0 penalties (0 is a genuine value here, not NA/missing) so the "amount distribution" describes actions that actually had a penalty; matches the "nonzero rows only" section label, but is a design choice worth flagging since summary_penalty's n_nonzero != nrow(d)
  data.table(subset = label, n_nonzero = length(x), min = min(x), p25 = quantile(x, .25),  # row count + min/p25 among nonzero actions
             median = median(x), p75 = quantile(x, .75), p99 = quantile(x, .99), max = max(x),  # median/p75/p99/max among nonzero actions
             mean = mean(x), total = sum(x))                          # mean and total dollars among nonzero actions only (excludes $0 rows by construction, unlike overview's totals)
}
summary_penalty <- rbindlist(list(summarise_penalty(pen, "all rows"), summarise_penalty(pen[DUP == 0], "dup==0 only")))  # two views stacked: "all rows" (full data, includes dup duplicates) and "dup==0 only" (deduped on the event-key flag)
fwrite_rounded(summary_penalty, file.path(OUT, "summary_penalty.csv"), num_cols = c("mean", "total"))  # write CSV 2

# =========================================================================================================
# CSV 3 -- penalties by year (dup==0, count + total + nonzero share)
# =========================================================================================================
by_year <- pen[DUP == 0, .(n_actions = .N, n_with_penalty = sum(HAS_PENALTY),  # FLAG: this is the file's documented "naive" by-year total -- computed on DUP==0 rows only (event-key duplicates removed) but each co-defendant facility in a multi-facility settlement still contributes its own full row, so multi-facility settlements are still broadcast (not corrected) into this by-year total; matches the header's stated convention for by_year / the Figure 2 total-by-year chart, not a bug
                           total_penalty = sum(PENALTY_AMOUNT)), by = YEAR][order(YEAR)]  # total $ per year (naive, per above), sorted ascending by year
by_year[, pct_with_penalty := round(n_with_penalty / n_actions, 3)]   # add share-with-penalty column, rounded to 3dp
fwrite_rounded(by_year, file.path(OUT, "by_year.csv"), num_cols = "total_penalty")  # write CSV 3

# =========================================================================================================
# CSV 4 -- ENF_TYPE / ACTIVITY_TYPE / STATE_EPA_FLAG frequency (dup==0)
# =========================================================================================================
freq_cat <- function(d, v) {                                          # frequency table (n, share) for one categorical column `v` within data `d`
  tb <- d[, .N, by = c(v)][order(-N)]; setnames(tb, v, "level")       # count by level, sort descending, rename the grouping column to a common "level" name for stacking across variables
  tb[, `:=`(variable = v, pct = round(N / sum(N), 4))][, .(variable, level, n = N, pct)]  # tag which variable this came from, add within-variable share, reorder columns
}
d0 <- pen[DUP == 0]                                                   # the "dup==0" view used by CSV 4 (categorical frequencies) and reused as the base for CSV 6's dollar figures below
freq_categorical <- rbindlist(lapply(c("ENF_TYPE_DESC", "ACTIVITY_TYPE_DESC", "STATE_EPA_FLAG"), freq_cat, d = d0))  # stack frequency tables for the three categorical columns, dup==0 basis
fwrite(freq_categorical, file.path(OUT, "freq_categorical.csv"))      # write CSV 4 (not rounded via fwrite_rounded -- pct already rounded to 4dp above)

# =========================================================================================================
# CSV 5 -- multi-facility settlement structure (headline numbers only; deep dive is in the brief)
# =========================================================================================================
settlements <- pen[, .(n_facilities = uniqueN(PGM_SYS_ID), n_rows = .N,  # settlement structure identified from ALL rows (pen, not d0) -- matches the dataset's own shipped IS_MULTI_FACILITY/N_SETTLEMENT_FACILITIES columns per the CSV 6 header note below; uniqueN() is unaffected by DUP duplicate rows since it counts distinct facilities, not row count
                       n_distinct_amounts = uniqueN(PENALTY_AMOUNT)), by = ENF_IDENTIFIER]  # distinct dollar amounts seen across the settlement's rows -- also unaffected by DUP duplicates (a repeated identical amount adds no new distinct value)
multi <- settlements[n_facilities > 1]                                # subset to multi-facility (co-defendant) settlements
settlement_structure <- data.table(
  n_settlements_total          = nrow(settlements),                   # count of distinct ENF_IDENTIFIERs (one row per settlement, from the group-by above)
  n_settlements_multi_facility = nrow(multi),                         # count of settlements naming more than one facility
  pct_settlements_multi_facility = round(nrow(multi) / nrow(settlements), 4),  # share of settlements that are multi-facility
  max_co_defendants            = max(settlements$n_facilities),       # largest number of facilities named in a single settlement
  n_multi_with_uniform_amount  = multi[n_distinct_amounts == 1, .N],  # multi-facility settlements where every named facility shows the same PENALTY_AMOUNT (the broadcast pattern)
  n_multi_with_differing_amounts = multi[n_distinct_amounts > 1, .N])  # multi-facility settlements where facilities show genuinely different amounts (the "72 differing" population revisited in CSV 6)
fwrite(settlement_structure, file.path(OUT, "settlement_structure.csv"))  # write CSV 5 (headline numbers)

co_defendant_dist <- settlements[n_facilities > 1, .N, by = n_facilities][order(n_facilities)]  # distribution of co-defendant counts across multi-facility settlements (how many settlements have 2 facilities, 3, ..., up to max_co_defendants)
fwrite(co_defendant_dist, file.path(OUT, "co_defendant_distribution.csv"))  # write co-defendant distribution (feeds Figure 3)

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
multi_ids  <- settlements[n_facilities > 1, ENF_IDENTIFIER]           # ENF_IDENTIFIERs of every multi-facility settlement, identified from the all-rows `settlements` table above
differ_ids <- settlements[n_facilities > 1 & n_distinct_amounts > 1, ENF_IDENTIFIER]  # subset further to the "differing amount" settlements

dollars_for <- function(ids) {                                        # given a set of ENF_IDENTIFIERs, compute two competing dollar totals across their (DUP==0) rows
  x <- d0[ENF_IDENTIFIER %in% ids, .(naive = sum(PENALTY_AMOUNT), distinct = sum(unique(PENALTY_AMOUNT))), by = ENF_IDENTIFIER]  # FLAG: "naive" sums PENALTY_AMOUNT across every facility row in the settlement -- for a uniform-amount, N-facility settlement this counts the true settlement dollar amount N times (the broadcast inflation the header quantifies at 35.2% of the all-time total). "distinct" instead sums only DISTINCT dollar values per settlement, which correctly collapses a broadcast uniform amount back to one copy, but ALSO collapses two facilities that coincidentally owe the exact same individual fine by chance -- so "distinct" is an approximation, not a guaranteed-correct de-broadcast, for genuinely-differing settlements with a coincidental tie
  data.table(n_settlements = length(ids), naive_sum = sum(x$naive), distinct_sum = sum(x$distinct))  # aggregate across all settlements in this population
}
settlement_dollars <- rbindlist(list(
  cbind(population = sprintf("all %d multi-facility", length(multi_ids)),  dollars_for(multi_ids)),   # label built from length(multi_ids), not hand-typed -- stays accurate on any data refresh
  cbind(population = sprintf("%d differing-amount", length(differ_ids)),   dollars_for(differ_ids))))
fwrite(settlement_dollars, file.path(OUT, "settlement_dollars_by_population.csv"))  # write settlement-dollars-by-population CSV

# per-settlement spread (max-min) for the 72 differing ones, DUP==0 basis
differ_detail <- d0[ENF_IDENTIFIER %in% differ_ids,
                    .(min_amt = min(PENALTY_AMOUNT), max_amt = max(PENALTY_AMOUNT),  # per-settlement min/max facility amount
                      naive = sum(PENALTY_AMOUNT), distinct = sum(unique(PENALTY_AMOUNT))), by = ENF_IDENTIFIER]  # same naive/distinct pair as dollars_for(), per settlement rather than aggregated
differ_detail[, spread := max_amt - min_amt]                          # dollar gap between the largest and smallest facility amount within the settlement
differ_detail[, trivial := spread <= 5]                               # $5 threshold distinguishes "rounding-level" differences from genuinely differing settlement amounts -- a defensible but arbitrary judgment call; documented, not changed
# is_texas: joined from each settlement's facility STATE (coordinates.csv.gz, facility-grain), NOT parsed from
# ENF_IDENTIFIER -- confirmed only ~85% of ENF_IDENTIFIERs are 2-letter-state-prefixed (the rest use numeric
# EPA-region prefixes, e.g. "01-2025-1018"), so a text-prefix match would miss Texas settlements filed under a
# region-numbered ID. A settlement is "is_texas" if ANY of its named facilities is in TX (settlements can span states).
fac_state   <- fread(file.path(DATASETS, "coordinates.csv.gz"), select = c("PGM_SYS_ID", "STATE"))
differ_ids_state <- merge(d0[ENF_IDENTIFIER %in% differ_ids, .(ENF_IDENTIFIER, PGM_SYS_ID)], fac_state, by = "PGM_SYS_ID", all.x = TRUE)
texas_by_settlement <- differ_ids_state[, .(is_texas = any(STATE == "TX", na.rm = TRUE)), by = ENF_IDENTIFIER]
differ_detail <- merge(differ_detail, texas_by_settlement, by = "ENF_IDENTIFIER", all.x = TRUE)
fwrite(differ_detail, file.path(OUT, "differing_settlements_detail.csv"))  # write per-settlement detail for the 72 differing-amount settlements

differ_summary <- differ_detail[, .(n_settlements = .N, naive_sum = sum(naive), distinct_sum = sum(distinct),  # roll the per-settlement detail up to trivial vs. genuinely-large groups
                                    n_texas = sum(is_texas)), by = trivial][order(-trivial)]  # count of Texas-flagged settlements per group; order so trivial=TRUE prints first
fwrite(differ_summary, file.path(OUT, "differing_settlements_trivial_vs_large.csv"))  # write CSV 6's trivial-vs-large summary

# =========================================================================================================
# FIGURES -- print-ready (300dpi), validated categorical palette, direct end-of-line labels
# =========================================================================================================
PAL <- c(blue = "#2a78d6", aqua = "#1baf7a", yellow = "#eda100", green = "#008300", violet = "#4a3aa7", red = "#e34948")  # validated categorical palette (dataviz skill), shared across the three figures below
INK <- "#0b0b0b"; INK_SECONDARY <- "#52514e"; GRID <- "#e1e0d9"; AXIS <- "#c3c2b7"  # text/gridline/axis colors for the print theme
theme_journal <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), panel.grid.major = element_line(color = GRID, linewidth = 0.3),  # drop minor gridlines, thin muted major gridlines
        axis.line = element_line(color = AXIS, linewidth = 0.3), axis.ticks = element_line(color = AXIS, linewidth = 0.3),  # thin muted axis line/ticks
        text = element_text(color = INK), axis.text = element_text(color = INK_SECONDARY),  # ink-colored body text, slightly muted axis labels
        plot.title = element_text(face = "bold", size = 12), plot.subtitle = element_text(color = INK_SECONDARY, size = 9.5),  # bold title, muted smaller subtitle
        plot.caption = element_text(color = INK_SECONDARY, size = 8, hjust = 0), legend.position = "none")  # left-aligned muted caption; no legend (direct end-of-line labels used instead where needed)
save_fig <- function(name, plot, w = 7.5, h = 4.5) ggsave(file.path(OUT_FIG, name), plot, width = w, height = h, dpi = 300)  # shared 300dpi print-ready save helper

# ---- FIGURE 1: penalty amount distribution (nonzero, dup==0), log10 x-axis given heavy right skew ---------
nz <- d0[PENALTY_AMOUNT > 0, PENALTY_AMOUNT]                          # nonzero penalty amounts, dup==0 basis -- same "exclude real zeros" convention as summarise_penalty() above
fig1 <- ggplot(data.table(amount = nz), aes(amount)) +
  geom_histogram(bins = 50, fill = PAL[["blue"]], color = "white", linewidth = 0.1) +  # 50-bin histogram, white bin borders for separation
  scale_x_log10(labels = label_dollar(scale_cut = cut_short_scale())) +  # log10 x-axis (heavy right skew per header) with abbreviated dollar labels (e.g. $1K, $1M)
  scale_y_continuous(labels = label_comma()) +                        # comma-formatted y-axis counts
  labs(title = "Penalty amount distribution (nonzero actions)",
       subtitle = sprintf("n = %s nonzero, DUP==0 actions; log10 x-axis (heavy right skew: median $%s, max $%s)",  # subtitle computed live from nz (n, median, max)
                          format(length(nz), big.mark = ","), format(round(median(nz)), big.mark = ","),
                          format(round(max(nz)), big.mark = ",")),
       x = "Penalty amount (log scale)", y = "Actions", caption = "Source: data/datasets/penalties.csv.gz (dataset 3).") +
  theme_journal
save_fig("pen_amount_distribution.png", fig1)                         # write Figure 1

# ---- FIGURE 2: total penalty dollars by year (naive, dup==0 -- see caption caveat) --------------------------
by_year_plot <- by_year[YEAR >= 1990 & YEAR <= 2025]                  # drop pre-1990 (sparse, per the caption below) for the plotted series; by_year itself (CSV 3) is unfiltered
fig2 <- ggplot(by_year_plot, aes(YEAR, total_penalty)) +
  geom_col(fill = PAL[["blue"]], width = 0.8) +                       # one bar per year, total $ height
  scale_x_continuous(breaks = seq(1990, 2025, 5)) +                   # 5-year axis ticks
  scale_y_continuous(labels = label_dollar(scale_cut = cut_short_scale())) +  # abbreviated dollar y-axis labels
  labs(title = "Total penalty dollars by year, 1990-2025",
       subtitle = "Naive sum (DUP==0, NOT settlement-broadcast-corrected) -- large multi-facility settlements can\ninflate a single year materially; see multi_facility_settlement_decision.md (35.2% of the all-time\ntotal is broadcast inflation, concentrated in a handful of large settlements)",  # restates the by_year naive-total caveat (flagged above at by_year's definition) directly in the figure itself
       x = NULL, y = "Total penalty ($)", caption = "Source: data/datasets/penalties.csv.gz (dataset 3). 1972-1989 omitted (sparse, <150 actions/year combined).") +
  theme_journal + theme(plot.subtitle = element_text(color = INK_SECONDARY, size = 8.3, lineheight = 1.15))  # slightly smaller/tighter subtitle text to fit the two-line caveat
save_fig("pen_total_by_year.png", fig2, w = 8, h = 4.8)                # write Figure 2 (wider than default to fit the 1990-2025 x-axis)

# ---- FIGURE 3: co-defendant count distribution (multi-facility settlements), log10 y given long tail --------
fig3 <- ggplot(co_defendant_dist, aes(n_facilities, N)) +
  geom_col(fill = PAL[["blue"]], width = 0.8) +                       # one bar per co-defendant count
  scale_x_continuous(breaks = c(2, 5, 10, 20, 50, 100, 117)) +        # hand-picked axis breaks; 117 is the observed max_co_defendants (matches settlement_structure)
  scale_y_log10(labels = label_comma()) +                             # log10 y-axis given the long right tail (most settlements have few co-defendants)
  labs(title = "Co-defendant count distribution, multi-facility settlements",
       subtitle = sprintf("n = %s multi-facility settlements; log10 y-axis; max %s co-defendants in one settlement",  # subtitle computed live from co_defendant_dist
                          format(sum(co_defendant_dist$N), big.mark = ","), format(max(co_defendant_dist$n_facilities))),
       x = "Facilities in the settlement", y = "Settlements (log scale)",
       caption = "Source: data/datasets/penalties.csv.gz (dataset 3).") +
  theme_journal
save_fig("pen_co_defendant_distribution.png", fig3)                   # write Figure 3

# ---- console summary ---------------------------------------------------------------------------------------
cat("data/datasets/penalties.csv.gz -- profile summary\n")            # section banner
cat("=====================================================\n\n")
cat(sprintf("%s actions | %s facilities | %s settlements | years %d-%d\n",  # headline counts line
            format(overview$n_actions, big.mark=","), format(overview$n_facilities, big.mark=","),
            format(overview$n_settlements, big.mark=","), overview$year_min, overview$year_max))
cat(sprintf("has_penalty: %.1f%% | total $ (all rows, INCLUDES broadcast/dup double-counting): $%s | total $ (dup==0): $%s\n",  # explicitly labels both totals per the FLAGs at overview's total_penalty_all_rows/total_penalty_dup0 above -- "all rows" is the double-counted upper bound, "dup==0" still includes broadcast (not corrected)
            100*overview$pct_has_penalty, format(round(overview$total_penalty_all_rows), big.mark=","),
            format(round(overview$total_penalty_dup0), big.mark=",")))
cat("\nPENALTY AMOUNT SUMMARY (nonzero)\n"); print(as.data.frame(summary_penalty), row.names = FALSE)  # CSV 2 to console
cat("\nBY YEAR (dup==0)\n"); print(as.data.frame(by_year), row.names = FALSE)  # CSV 3 to console
cat("\nCATEGORICAL FREQUENCIES (dup==0)\n"); print(as.data.frame(freq_categorical), row.names = FALSE)  # CSV 4 to console
cat("\nSETTLEMENT STRUCTURE\n"); print(as.data.frame(settlement_structure), row.names = FALSE)  # CSV 5 to console
cat("\nCO-DEFENDANT COUNT DISTRIBUTION (multi-facility settlements)\n")
print(as.data.frame(co_defendant_dist), row.names = FALSE)            # co-defendant distribution to console
cat("\nSETTLEMENT DOLLARS BY POPULATION (DUP==0 basis)\n"); print(as.data.frame(settlement_dollars), row.names = FALSE)  # CSV 6 population totals to console
cat("\nDIFFERING SETTLEMENTS: TRIVIAL (spread<=$5) VS GENUINELY LARGE\n")
print(as.data.frame(differ_summary), row.names = FALSE)               # CSV 6 trivial-vs-large summary to console

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# 1. (overview$total_penalty_all_rows, ~line 50) Sums PENALTY_AMOUNT over every row -- includes DUP>0
#    duplicate rows AND every co-defendant facility's own full copy of a multi-facility settlement amount.
#    Deliberate double-counted upper bound, labeled as such in the console summary; not a bug, but a reader
#    skimming overview.csv without that label could easily mistake it for a clean total.
# 2. (overview$total_penalty_dup0, ~line 51) Removes DUP>0 rows but does NOT correct multi-facility
#    broadcast -- each co-defendant facility still carries its own full copy of the settlement amount.
#    "dup==0" and "broadcast-corrected" are two different corrections; only CSV 6 addresses the latter.
#    Worth noting so dup0 isn't mistaken for the fully-corrected total.
# 3. (summarise_penalty(), ~line 62) Filters to PENALTY_AMOUNT > 0 before computing the five-number summary,
#    i.e. deliberately excludes real $0 penalties (0 is a genuine value in this dataset, not NA). Matches the
#    "nonzero rows only" section label, but means n_nonzero != nrow(d) -- a design choice, not a bug.
# 4. (by_year$total_penalty, ~line 73) The file's documented "naive" by-year total: DUP==0 removes event-key
#    duplicates but multi-facility settlements are still broadcast across co-defendant facilities, uninflated
#    total_penalty is NOT the corrected figure. Matches the header's stated convention and is restated in the
#    Figure 2 subtitle -- flagged here at the source so the two mentions are traceable to one decision.
# 5. (dollars_for(), ~line 122) "naive" sums PENALTY_AMOUNT across every facility row in a settlement, so a
#    uniform-amount N-facility settlement counts the true dollar amount N times (the 35.2% broadcast inflation
#    the header quantifies). "distinct" sums only distinct dollar values per settlement, which correctly
#    collapses a broadcast uniform amount, but would ALSO collapse two facilities that coincidentally owe the
#    exact same individual fine -- "distinct" is an approximation, not a guaranteed-correct de-broadcast.
# 6. RESOLVED 2026-07-28: population labels now built via sprintf("all %d multi-facility", length(multi_ids))
#    and sprintf("%d differing-amount", length(differ_ids)) instead of hand-typed "588"/"72" literals.
# 7. RESOLVED (same fix as #6).
# 8. (differ_detail$trivial, ~line 135) `spread <= 5` is a hand-picked $5 threshold separating "rounding-level"
#    differences from genuinely differing settlement amounts. A defensible judgment call, but arbitrary, and
#    it directly determines the trivial/large split reported in differ_summary. Reviewed 2026-07-28: left as-is.
# 9. RESOLVED 2026-07-28: is_texas no longer parses ENF_IDENTIFIER (confirmed only ~85% of IDs are
#    2-letter-state-prefixed; the rest use numeric EPA-region prefixes) -- now joined from each settlement's
#    facility STATE via coordinates.csv.gz (PGM_SYS_ID-keyed, facility-grain), TRUE if any named facility is TX.
