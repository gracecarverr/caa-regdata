# =========================================================================================================
# code/diagnostics/16_pipeline_profile.R -- exploratory profiling of dataset 6 (pipeline.csv.gz, facility x
#   year) and its row-level source (data/processed/pipeline.csv.gz, real violations only). Purpose:
#   characterize both for a reader picking the project up cold. Companion to 11_operating_profile.R /
#   12_penalties_profile.R / 13_regulatory_profile.R / 14_hpv_profile.R (same discipline, different datasets).
#
#   in : data/processed/pipeline.csv.gz, data/datasets/pipeline.csv.gz
#   out: output/pipeline_profile/*.csv (incl. pl2_sort_date_check.csv -- verifies SORT_DATE against every
#        plausible coalesce priority order empirically rather than trusting the dictionary's prose
#        description; added 2026-07-27 after an ad-hoc reproduction attempt got the priority order backwards)
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
suppressPackageStartupMessages({library(data.table); library(ggplot2); library(scales)})  # data.table (fread/fast agg), ggplot2 (figures), scales (axis formatters); suppress startup banners
options(scipen = 999)                                   # disable scientific notation in printed/written numbers (e.g. penalty dollar sums)

CLEAN    <- here::here("data/processed")                # row-level cleaned assets -- PART A reads pipeline.csv.gz from here
DATASETS <- here::here("data/datasets")                 # facility x year dataset layer -- PART B reads pipeline.csv.gz from here
OUT      <- here::here("output/pipeline_profile")       # where this script's CSV outputs land
OUT_FIG  <- here::here("output/figures/datasets/pipeline")  # where this script's figure PNGs land
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)     # create the CSV output dir if missing; silent if it already exists
dir.create(OUT_FIG, showWarnings = FALSE, recursive = TRUE) # create the figure output dir if missing; silent if it already exists

YEARS <- 2005:2025                                      # same analysis window as the dataset layer (G1)

# =========================================================================================================
# PART A -- row-level source (data/processed/pipeline.csv.gz), real (non-placeholder) violations only
# =========================================================================================================
raw <- fread(file.path(CLEAN, "pipeline.csv.gz"))       # read the full row-level source, INCLUDING placeholder rows (PL1) and out-of-window rows
# parse the four raw character date fields into real Date objects (ICIS-AIR's M/D/Y export format)
raw[, `:=`(eval_date = as.Date(EVAL_DATE, format = "%m/%d/%Y"),          # eval_date: linked evaluation/inspection date, NA if none linked or unparseable
           viol_date = as.Date(VIOL_START_DATE, format = "%m/%d/%Y"),    # viol_date: violation start date -- NA for placeholder rows (PL1) and unparseable dates
           ea_date   = as.Date(EA_DATE, format = "%m/%d/%Y"),            # ea_date: linked enforcement-action date, NA if none linked or unparseable
           sort_date = as.Date(SORT_DATE, format = "%m/%d/%Y"))]         # sort_date: EPA's own display-order date (PL2 check below verifies what it's built from)
raw[, viol_year := year(viol_date)]                      # calendar year of the violation start -- NA whenever viol_date is NA (placeholders + unparseable dates)
# confirmed this matches 07_pipeline.R's real-row filter: is.na(viol_year) there is equivalent to this
# script's is.na(viol_year) (same "%m/%d/%Y"/mdy() parsing of VIOL_START_DATE), so the placeholder exclusion
# below is the same 7,193-row (as of 07_pipeline.R's header) exclusion that dataset build applies
real <- raw[!is.na(viol_year) & viol_year %in% YEARS]   # drop placeholders (PL1) and out-of-window rows (G1)

# ---- CSV 1: overview + VIOL_TYPE breakdown ----------------------------------------------------------------
overview_raw <- data.table(n_rows_raw = nrow(raw), n_placeholder = raw[is.na(viol_year), .N],   # n_rows_raw: every row incl. placeholders + out-of-window; n_placeholder: rows with no parseable VIOL_START_DATE
                           n_real_in_window = nrow(real), n_facilities = uniqueN(real$SOURCE_ID))  # n_real_in_window: rows passing BOTH filters; n_facilities: distinct SOURCE_ID among them
# FLAG: n_placeholder here counts only rows with no parseable VIOL_START_DATE (is.na(viol_year)); the
# additional rows dropped for being outside the 2005-2025 window (viol_year %in% YEARS) are NOT broken out
# anywhere -- their count is only recoverable as n_rows_raw - n_placeholder - n_real_in_window, not labeled.
# Also: recomputing n_placeholder against the current data/processed/pipeline.csv.gz gives 7,218 (of 66,723
# raw rows), not the "7,193 (of 66,655)" figure quoted in this script's own header and in 07_pipeline.R's
# header -- the row-level source has been refreshed (2026-07-27 ICIS-AIR snapshot, per git history) since
# those header figures were written. This script computes its own count fresh every run (no hand-entry), so
# overview_raw.csv itself is correct; the stale prose count is a docs-drift risk for a reader cross-checking
# the printed CSV against the header.
fwrite(overview_raw, file.path(OUT, "overview_raw.csv"))  # write row-level overview

# ---- PL2 check: does SORT_DATE = coalesce(eval_date, viol_date, ea_date)? -----------------------------------
#   Tested every plausible priority order empirically (2026-07-27) rather than trust the dictionary's prose
#   description -- only this exact order gives 0 exceptions; EA_DATE-first (what an earlier pass assumed)
#   gives a 58% mismatch rate. Scope = all rows with a non-blank SORT_DATE (including placeholders, which can
#   still carry a SORT_DATE despite having no VIOL_START_DATE), matching how this check has always been run.
# FLAG: this scope choice matters -- because it's `raw` (not `real`) below, the checked rows include
# placeholder rows (no VIOL_START_DATE) that can still carry a SORT_DATE; a reader assuming PL2 was checked
# only on "real" violations would be looking at a different (smaller) universe than what was actually tested.
sort_nonblank <- raw[!is.na(sort_date)]                  # all rows (real + placeholder) with a non-blank SORT_DATE
sort_expected <- fcoalesce(sort_nonblank$eval_date, sort_nonblank$viol_date, sort_nonblank$ea_date)  # first non-NA of eval_date, viol_date, ea_date, in that priority order, row by row
pl2_check <- data.table(n_nonblank_sort_date = nrow(sort_nonblank),   # size of the checked scope defined above
                        # FLAG: na.rm = TRUE below silently excludes rows where sort_expected is itself NA --
                        # i.e. SORT_DATE is non-blank but eval_date, viol_date, AND ea_date are ALL NA, so
                        # there is nothing to compare SORT_DATE against. Such rows are neither counted as
                        # exceptions nor reported separately; if any existed they would inflate confidence in
                        # "0 exceptions" without being visible. Verified against the current snapshot: 0 such
                        # rows today (all 66,699 non-blank-SORT_DATE rows have at least one coalesce source),
                        # so this is a latent edge case, not an active one.
                        n_exceptions = sum(sort_nonblank$sort_date != sort_expected, na.rm = TRUE))  # count of rows where observed SORT_DATE disagrees with the coalesce prediction
fwrite(pl2_check, file.path(OUT, "pl2_sort_date_check.csv"))  # write the PL2 check result

viol_type_breakdown <- real[, .N, by = VIOL_TYPE][order(-N)]  # count of real violations by VIOL_TYPE (HPV/FRV -- the field this dataset's HPV/FRV split is built from), sorted descending
viol_type_breakdown[, pct := round(N / sum(N), 4)]        # each VIOL_TYPE's share of all real violations
fwrite(viol_type_breakdown, file.path(OUT, "viol_type_breakdown.csv"))  # write the VIOL_TYPE breakdown

# ---- CSV 2: linkage rates -- share of real violations tracing to a known evaluation / enforcement action --
linkage_rates <- data.table(                              # build a one-row table of linkage counts/rates
  n_real = nrow(real),                                     # denominator for every rate below -- all real (non-placeholder, in-window) violations
  n_with_eval = real[EVAL_FLAG == "Y", .N], pct_with_eval = round(real[EVAL_FLAG == "Y", .N] / nrow(real), 4),  # violations with a linked evaluation
  n_with_ea   = real[EA_FLAG == "Y", .N],   pct_with_ea   = round(real[EA_FLAG == "Y", .N] / nrow(real), 4),    # violations with a linked enforcement action
  n_self_disclosed = real[EVAL_FLAG == "Y" & EVAL_TYPE_DESC == "Self-Disclosure", .N])  # of those linked, how many were discovered via self-disclosure
linkage_rates[, pct_self_disclosed_of_eval := round(n_self_disclosed / n_with_eval, 4)]  # self-disclosure rate AMONG linked evaluations (denominator is n_with_eval, not nrow(real))
fwrite(linkage_rates, file.path(OUT, "linkage_rates.csv"))  # write linkage rates

# ---- CSV 3: EVAL_TYPE_DESC frequency (of the rows that carry a linked evaluation) --------------------------
eval_type_freq <- real[EVAL_FLAG == "Y" & EVAL_TYPE_DESC != "", .N, by = EVAL_TYPE_DESC][order(-N)]  # frequency table of evaluation type, restricted to rows with a real (non-blank) EVAL_TYPE_DESC
eval_type_freq[, pct := round(N / sum(N), 4)]              # each type's share of linked evaluations with a known type
fwrite(eval_type_freq, file.path(OUT, "eval_type_frequency.csv"))  # write EVAL_TYPE_DESC frequencies

# ---- CSV 4: EA_TYPE frequency (of the rows that carry a linked enforcement action) -------------------------
ea_type_freq <- real[EA_FLAG == "Y" & EA_TYPE != "", .N, by = EA_TYPE][order(-N)]  # frequency table of enforcement-action type, restricted to rows with a real (non-blank) EA_TYPE
ea_type_freq[, pct := round(N / sum(N), 4)]                # each type's share of linked enforcement actions with a known type
fwrite(ea_type_freq, file.path(OUT, "ea_type_frequency.csv"))  # write EA_TYPE frequencies

# ---- CSV 5: eval->violation lag (days), only rows with both dates and a non-negative lag -------------------
# FLAG: the viol_date >= eval_date guard below recodes any row where the violation is dated BEFORE its own
# linked evaluation to NA -- silently dropped from the lag distribution, not counted as a negative lag or
# reported separately. This matches 07_pipeline.R's own eval_to_viol_lag convention exactly (same guard), but
# it is a real exclusion: on the current snapshot, ~1,487 of ~23,018 EVAL_FLAG=="Y" rows with a parseable
# eval_date have viol_date < eval_date (~6.5%) and are dropped this way. eval_to_viol_lag_days.csv below
# reports only survivors (n = count that passed the guard); the exclusion count itself is nowhere in the output.
real[, eval_to_viol_lag := fifelse(EVAL_FLAG == "Y" & !is.na(eval_date) & viol_date >= eval_date,   # lag only defined where EVAL_FLAG=="Y", eval_date known, and the violation isn't dated before the eval
                                   as.integer(viol_date - eval_date), NA_integer_)]                  # integer day count when the guard holds, else NA
etv <- real[!is.na(eval_to_viol_lag), eval_to_viol_lag]    # vector of valid (non-NA) eval->violation lags
eval_to_viol_lag_summary <- data.table(n = length(etv), min = min(etv), p25 = quantile(etv, .25),   # n (survivors), min, 25th pctile...
                                       median = median(etv), p75 = quantile(etv, .75), p90 = quantile(etv, .90),  # ...median, 75th and 90th pctiles...
                                       max = max(etv), mean = round(mean(etv), 1))                   # ...max, and mean (rounded to 1 decimal)
fwrite(eval_to_viol_lag_summary, file.path(OUT, "eval_to_viol_lag_days.csv"))  # write eval->violation lag summary

# ---- CSV 6: violation->enforcement lag (days), only rows with both dates and a non-negative lag ------------
# FLAG: same silent-exclusion pattern as eval_to_viol_lag above, mirroring 07_pipeline.R's viol_to_ea_lag
# guard -- rows where the enforcement action predates the violation (ea_date < viol_date) are recoded NA and
# dropped from every stat below. On the current snapshot ~3,192 of ~40,113 EA_FLAG=="Y" rows with a parseable
# ea_date (~8%) are excluded this way; this feeds directly into FIGURE 3's histogram and the "n = ..." count
# in its subtitle, and the exclusion count is not reported anywhere in the output.
real[, viol_to_ea_lag := fifelse(EA_FLAG == "Y" & !is.na(ea_date) & ea_date >= viol_date,   # lag only defined where EA_FLAG=="Y", ea_date known, and the EA isn't dated before the violation
                                 as.integer(ea_date - viol_date), NA_integer_)]              # integer day count when the guard holds, else NA
vte <- real[!is.na(viol_to_ea_lag), viol_to_ea_lag]        # vector of valid (non-NA) violation->enforcement lags -- reused by FIGURE 3 below
viol_to_ea_lag_summary <- data.table(n = length(vte), min = min(vte), p25 = quantile(vte, .25),    # n (survivors), min, 25th pctile...
                                     median = median(vte), p75 = quantile(vte, .75), p90 = quantile(vte, .90),  # ...median, 75th and 90th pctiles...
                                     max = max(vte), mean = round(mean(vte), 1))                    # ...max, and mean (rounded to 1 decimal)
fwrite(viol_to_ea_lag_summary, file.path(OUT, "viol_to_ea_lag_days.csv"))  # write violation->enforcement lag summary

# ---- CSV 7: EA_PENALTY_AMT among real violations with a positive linked penalty ----------------------------
real[, ea_penalty := suppressWarnings(as.numeric(EA_PENALTY_AMT))]  # coerce to numeric (fread already auto-detects this column numeric; suppressWarnings guards any stray non-numeric value)
pen <- real[!is.na(ea_penalty) & ea_penalty > 0, ea_penalty]  # only rows with a real, strictly positive penalty amount (matches 07_pipeline.R's has_ea_penalty definition)
penalty_summary <- data.table(n_with_penalty = length(pen), pct_of_real = round(length(pen) / nrow(real), 4),  # count and share (of ALL real violations, not just linked-EA ones) with a positive penalty
                              min = min(pen), median = median(pen), p90 = quantile(pen, .90), max = max(pen),  # distribution of the positive penalty amounts
                              total = sum(pen))                                                                # total dollars summed across positive penalties
fwrite(penalty_summary, file.path(OUT, "ea_penalty_among_real_violations.csv"))  # write penalty summary

# =========================================================================================================
# PART B -- pipeline (dataset 6, facility x year, 5,863,431 rows)
# =========================================================================================================
pf <- fread(file.path(DATASETS, "pipeline.csv.gz"))       # read dataset 6: the facility x year pipeline dataset (full 2005-2025 rectangle)

# ---- CSV 8: overview + observed/NA breakdown ---------------------------------------------------------------
overview_ds <- data.table(n_facility_years = nrow(pf), n_facilities = uniqueN(pf$PGM_SYS_ID),  # n_facility_years: full rectangle size; n_facilities: distinct facilities in it
                          n_observed = sum(pf$PIPELINE_OBSERVED == 1), n_unobserved = sum(pf$PIPELINE_OBSERVED == 0),  # PIPELINE_OBSERVED zero-vs-NA gate (PL3): observed means >=1 real pipeline row anchors this facility-year
                          n_ever_observed_facilities = uniqueN(pf[PIPELINE_OBSERVED == 1, PGM_SYS_ID]))  # distinct facilities with at least one observed year
overview_ds[, pct_observed := round(n_observed / n_facility_years, 4)]  # share of the full rectangle that is observed -- this IS the NA-share the header's discipline requires reporting
fwrite(overview_ds, file.path(OUT, "overview_dataset.csv"))  # write dataset overview

# ---- CSV 9: observed facility-years and HPV/FRV split, by year (trend) --------------------------------------
obs <- pf[PIPELINE_OBSERVED == 1]                          # restrict to the observed subset -- every rate below is computed on this, per the PL3 zero-vs-NA discipline
# FLAG: N_VIOL_HPV / N_VIOL_FRV below come from dataset 6's own build (07_pipeline.R), which classifies
# HPV/FRV from the pipeline source's VIOL_TYPE field (VIOL_TYPE == "HPV" / "FRV") -- a DIFFERENT field, on a
# different source table, than dataset 2 (hpv_spells)'s HPV convention, which uses
# ENF_RESPONSE_POLICY_CODE == "HPV" on violations.csv.gz (see 03_hpv_spells.R). The two "HPV" flags are not
# guaranteed to agree facility-year by facility-year; a reader should not assume this pipeline HPV share and
# dataset 2/2b's HPV status are the same underlying classification just because they share a name.
by_year <- obs[, .(n_obs = .N, n_hpv = sum(N_VIOL_HPV), n_frv = sum(N_VIOL_FRV),   # per year: n observed facility-years, summed HPV/FRV violation counts...
                   n_with_eval = sum(N_VIOL_WITH_EVAL), n_with_ea = sum(N_VIOL_WITH_EA)), by = YEAR][order(YEAR)]  # ...and summed counts linked to a known eval / enforcement action; sorted by year
by_year[, `:=`(pct_hpv = round(n_hpv / (n_hpv + n_frv), 4),                         # HPV share of (HPV+FRV) violations that year...
              pct_viol_with_eval = round(n_with_eval / (n_hpv + n_frv), 4),         # ...share of that year's violations linked to a known evaluation...
              pct_viol_with_ea   = round(n_with_ea   / (n_hpv + n_frv), 4))]        # ...and share linked to a known enforcement action (same HPV+FRV denominator throughout)
fwrite(by_year, file.path(OUT, "by_year_summary.csv"))     # write the by-year trend table -- feeds FIGURE 1 and FIGURE 2 below

# ---- CSV 10: self-disclosure and penalty prevalence, dataset-wide (observed facility-years only) ------------
prevalence <- data.table(                                  # build a one-row, dataset-wide prevalence table
  n_viol_total = sum(obs$N_VIOL_PIPELINE), n_self_disclosed = sum(obs$N_VIOL_SELF_DISCLOSED),  # all real violations across observed facility-years; of which, discovered via self-disclosure
  n_with_ea_penalty = sum(obs$N_VIOL_WITH_EA_PENALTY), ea_penalty_amt_sum = sum(obs$EA_PENALTY_AMT_SUM))  # violations linked to an EA with a positive penalty; total dollars across the dataset
prevalence[, `:=`(pct_self_disclosed = round(n_self_disclosed / n_viol_total, 4),   # self-disclosure rate among all real violations...
                  pct_with_ea_penalty = round(n_with_ea_penalty / n_viol_total, 4))]  # ...and positive-EA-penalty rate among all real violations
fwrite(prevalence, file.path(OUT, "prevalence_summary.csv"))  # write prevalence summary

# =========================================================================================================
# FIGURES -- print-ready (300dpi), validated categorical palette, direct end-of-line labels
# =========================================================================================================
PAL <- c(blue = "#2a78d6", aqua = "#1baf7a", yellow = "#eda100", green = "#008300", violet = "#4a3aa7", red = "#e34948")  # validated categorical palette (dataviz skill), reused across all figures
INK <- "#0b0b0b"; INK_SECONDARY <- "#52514e"; GRID <- "#e1e0d9"; AXIS <- "#c3c2b7"  # ink/gridline/axis colors for the print-ready theme
theme_journal <- theme_minimal(base_size = 11) +           # base ggplot theme, built on theme_minimal()
  theme(panel.grid.minor = element_blank(), panel.grid.major = element_line(color = GRID, linewidth = 0.3),  # drop minor gridlines; thin muted major gridlines
        axis.line = element_line(color = AXIS, linewidth = 0.3), axis.ticks = element_line(color = AXIS, linewidth = 0.3),  # thin muted axis line and ticks
        text = element_text(color = INK), axis.text = element_text(color = INK_SECONDARY),  # body text in ink, axis labels in softer secondary ink
        plot.title = element_text(face = "bold", size = 12), plot.subtitle = element_text(color = INK_SECONDARY, size = 9.5),  # bold title, muted smaller subtitle
        plot.caption = element_text(color = INK_SECONDARY, size = 8, hjust = 0), legend.position = "none")  # left-aligned muted caption; no legend (direct labels used instead)
save_fig <- function(name, plot, w = 7.5, h = 4.5) ggsave(file.path(OUT_FIG, name), plot, width = w, height = h, dpi = 300)  # helper: save a figure to OUT_FIG at print resolution

# ---- FIGURE 1: linkage rate over time -- share of violations tracing to a known eval / enforcement action --
lr_long <- rbind(by_year[, .(YEAR, pct = pct_viol_with_eval, series = "linked to a known evaluation")],   # long-format series 1: eval-linkage rate...
                 by_year[, .(YEAR, pct = pct_viol_with_ea,   series = "linked to an enforcement action")])  # ...series 2: EA-linkage rate, stacked into one plotting frame
lbl <- lr_long[YEAR == max(YEAR)]                          # last year's row per series, used to place the direct end-of-line label
fig1 <- ggplot(lr_long, aes(YEAR, pct, color = series)) +  # base plot: year on x, share on y, colored by series
  geom_line(linewidth = 0.9) + geom_point(size = 1.4) +    # line + point markers per series
  scale_color_manual(values = c("linked to a known evaluation" = PAL[["blue"]],       # explicit color mapping: eval-linkage in blue...
                                "linked to an enforcement action" = PAL[["red"]])) +   # ...EA-linkage in red
  scale_x_continuous(breaks = seq(min(lr_long$YEAR), max(lr_long$YEAR), 5), expand = expansion(mult = c(0.02, 0.14))) +  # x ticks every 5 years; extra right padding for end-of-line labels
  scale_y_continuous(labels = label_percent(), limits = c(0, NA)) +  # y-axis as percent, floor at 0
  geom_text(data = lbl, aes(label = series), hjust = 0, nudge_x = 0.4, size = 3.1, fontface = "bold") +  # direct end-of-line labels replacing a legend (dataviz relief rule)
  labs(title = "Share of pipeline violations linked to an evaluation or enforcement action, 2005-2025",  # title
       subtitle = "Of observed facility-years' violations (dataset 6, PIPELINE_OBSERVED==1)",            # subtitle clarifies the denominator (observed facility-years only)
       x = NULL, y = "Share of violations", caption = "Source: data/datasets/pipeline.csv.gz (dataset 6).") +  # no x label; y label; source caption
  theme_journal                                            # apply the shared print theme
save_fig("pipeline_linkage_rate_over_time.png", fig1)      # write FIGURE 1

# ---- FIGURE 2: HPV vs FRV share of pipeline violations over time -------------------------------------------
fig2 <- ggplot(by_year, aes(YEAR, pct_hpv)) +               # base plot: year on x, HPV share on y
  geom_line(color = PAL[["violet"]], linewidth = 0.9) + geom_point(color = PAL[["violet"]], size = 1.4) +  # single-series line + point markers in violet
  scale_x_continuous(breaks = seq(min(by_year$YEAR), max(by_year$YEAR), 5)) +  # x ticks every 5 years
  scale_y_continuous(labels = label_percent(), limits = c(0, NA)) +  # y-axis as percent, floor at 0
  labs(title = "HPV share of pipeline violations, 2005-2025",  # title
       subtitle = "Remainder is FRV (Federally Reportable Violation) -- the tier hpv_spells (dataset 2) excludes",  # subtitle notes FRV is the complement -- but see the FLAG above CSV 9 (~L124): this VIOL_TYPE-based split differs in source field from dataset 2's ENF_RESPONSE_POLICY_CODE-based HPV convention
       x = NULL, y = "Share HPV (of HPV + FRV)", caption = "Source: data/datasets/pipeline.csv.gz (dataset 6).") +  # no x label; y label; source caption
  theme_journal                                            # apply the shared print theme
save_fig("pipeline_hpv_frv_share_over_time.png", fig2)     # write FIGURE 2

# ---- FIGURE 3: violation->enforcement lag distribution (truncated at p99 for readability) -------------------
p99 <- quantile(vte, .99)                                  # 99th percentile of the (already lag-guard-filtered) lag vector, used to set the x-axis truncation
fig3 <- ggplot(data.table(days = vte), aes(days)) +         # base plot: histogram of the lag-in-days vector
  geom_histogram(binwidth = 15, fill = PAL[["blue"]], color = "white", linewidth = 0.15, boundary = 0) +  # 15-day bins, blue fill with thin white borders, bin edges anchored at 0
  coord_cartesian(xlim = c(0, p99)) +                       # zoom displayed x-range to [0, p99] without discarding data (bars beyond p99 are just off-frame)
  scale_x_continuous(labels = label_comma()) + scale_y_continuous(labels = label_comma()) +  # comma-formatted axis labels on both axes
  labs(title = "Violation-to-enforcement-action lag (days)",  # title
       subtitle = sprintf("n = %s violations with a linked EA and a non-negative lag; x-axis truncated at the 99th pctile (%s days)",  # "non-negative lag" here is the FLAG above (~L94): the survivor count AFTER negative-lag rows were silently dropped
                          format(length(vte), big.mark = ","), format(round(p99), big.mark = ",")),  # format n and p99 with thousands separators
       x = "Days from violation start to enforcement action", y = "Violations",  # axis labels
       caption = "Source: data/processed/pipeline.csv.gz, real (non-placeholder) rows.") +  # source caption
  theme_journal                                            # apply the shared print theme
save_fig("pipeline_viol_to_ea_lag_distribution.png", fig3)  # write FIGURE 3

# ---- console summary -----------------------------------------------------------------------------------------
cat("data/processed/pipeline.csv.gz + data/datasets/pipeline.csv.gz -- profile summary\n")  # header banner
cat("==========================================================================\n\n")       # underline
cat("PART A -- row-level source, real (non-placeholder) violations, 2005-2025\n")            # PART A section label
print(as.data.frame(overview_raw), row.names = FALSE)      # print row-level overview
cat("\nPL2 CHECK -- SORT_DATE = coalesce(EVAL_DATE, VIOL_START_DATE, EA_DATE)?\n")            # PL2 section label
print(as.data.frame(pl2_check), row.names = FALSE)          # print PL2 check result
cat("\nVIOL_TYPE BREAKDOWN\n"); print(as.data.frame(viol_type_breakdown), row.names = FALSE)  # print VIOL_TYPE breakdown
cat("\nLINKAGE RATES\n"); print(as.data.frame(linkage_rates), row.names = FALSE)              # print linkage rates
cat("\nTOP EVAL_TYPE_DESC\n"); print(as.data.frame(head(eval_type_freq, 8)), row.names = FALSE)  # print top 8 EVAL_TYPE_DESC
cat("\nTOP EA_TYPE\n"); print(as.data.frame(head(ea_type_freq, 8)), row.names = FALSE)        # print top 8 EA_TYPE
cat("\nEVAL->VIOLATION LAG (days)\n"); print(as.data.frame(eval_to_viol_lag_summary), row.names = FALSE)  # print eval->violation lag summary
cat("\nVIOLATION->EA LAG (days)\n"); print(as.data.frame(viol_to_ea_lag_summary), row.names = FALSE)      # print violation->EA lag summary
cat("\nEA PENALTY AMONG REAL VIOLATIONS\n"); print(as.data.frame(penalty_summary), row.names = FALSE)     # print penalty summary

cat("\n\nPART B -- pipeline (facility x year, dataset 6)\n")  # PART B section label
print(as.data.frame(overview_ds), row.names = FALSE)        # print dataset overview
cat("\nPREVALENCE (observed facility-years)\n"); print(as.data.frame(prevalence), row.names = FALSE)      # print prevalence summary
cat("\nBY-YEAR SUMMARY (head)\n"); print(as.data.frame(head(by_year, 10)), row.names = FALSE)              # print first 10 rows of the by-year trend table

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# 1. ~L46-48 (overview_raw / n_placeholder): the header's "7,193 placeholder rows (of 66,655)" figure is
#    stale -- recomputing against the current data/processed/pipeline.csv.gz gives 7,218 placeholder rows of
#    66,723 total, reflecting a data refresh (2026-07-27 ICIS-AIR snapshot) since that count was written. The
#    script itself computes fresh, so its output is correct; the header prose is what's out of date. Also,
#    the ~2,308 rows dropped for being out-of-window (not placeholders) are not broken out anywhere in
#    overview_raw.csv, only recoverable by subtraction.
# 2. ~L53-55 (PL2 check scope): the sort_nonblank scope is built from `raw` (includes placeholder rows), not
#    `real` -- a deliberate, documented choice ("matching how this check has always been run") but a
#    different universe than Part A's other checks; worth a reader's notice.
# 3. ~L57-58 (pl2_check n_exceptions): na.rm = TRUE silently excludes rows where SORT_DATE is present but
#    eval_date/viol_date/ea_date are ALL NA (nothing to compare against) -- such rows would neither count as
#    an exception nor be reported separately. Verified 0 such rows exist in the current snapshot, so this is
#    a latent, not active, risk.
# 4. ~L85-86 (eval_to_viol_lag): rows where the violation predates its own linked evaluation are recoded NA
#    and silently dropped from the lag distribution -- ~1,487 of ~23,018 EVAL_FLAG=="Y" rows (~6.5%) on the
#    current snapshot. Matches 07_pipeline.R's convention, but the exclusion count is not reported anywhere.
# 5. ~L94-95 (viol_to_ea_lag): same pattern -- rows where the enforcement action predates the violation are
#    recoded NA and dropped -- ~3,192 of ~40,113 EA_FLAG=="Y" rows (~8%) on the current snapshot, feeding
#    directly into FIGURE 3's histogram and its "n = ..." subtitle count without the exclusion being reported.
# 6. ~L123-125 (CSV 9 / by_year HPV-FRV split) and ~L175 (FIGURE 2 subtitle): this dataset's HPV/FRV split
#    comes from the pipeline source's own VIOL_TYPE field (VIOL_TYPE == "HPV"/"FRV", per 07_pipeline.R), a
#    DIFFERENT field on a different source table than dataset 2 (hpv_spells)'s HPV convention
#    (ENF_RESPONSE_POLICY_CODE == "HPV" on violations.csv.gz, per 03_hpv_spells.R). The two "HPV" labels are
#    not guaranteed to agree facility-year by facility-year.
