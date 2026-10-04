# =========================================================================================================
# code/diagnostics/14_hpv_profile.R -- exploratory profiling of dataset 2 (hpv_spells.csv.gz, spell-level)
#   and dataset 2b (hpv_active.csv.gz, facility x year collapse). Purpose: characterize both for a reader
#   picking the project up cold. Companion to 11_operating_profile.R / 12_penalties_profile.R /
#   13_regulatory_profile.R (same discipline, different datasets).
#
#   in : data/datasets/{hpv_spells,hpv_active,regulatory}.csv.gz
#   out: output/hpv_profile/*.csv
#        output/figures/datasets/hpv/hpv_{active_rate_over_time,spell_duration,program_frequency}.png
#
#   DISCIPLINE: hpv_spells is spell-level, UNcollapsed (H2) -- a facility can have 0..N rows, so any
#   "per-facility" summary here is explicit about whether it's per-spell or per-facility. hpv_active mirrors
#   ds0's zero-vs-NA gate (H6): NA is unknown, never a false 0; every rate below reports the NA share.
#   No numbers are hand-entered; every cell is computed here. Hand-run (not part of RUN_ALL.R). No stochastic step.
#
#   FIGURE DESIGN: same print-ready convention as 13_regulatory_profile.R (dataviz skill, validated
#   categorical palette, direct end-of-line labels in place of a legend, 300dpi).
# =========================================================================================================
suppressPackageStartupMessages({library(data.table); library(ggplot2); library(scales)})  # load packages quietly
options(scipen = 999)  # disable scientific notation in console/printed output

DATASETS <- here::here("data/datasets")            # path to the derived datasets layer (dataset 2/2b live here)
OUT      <- here::here("output/hpv_profile")        # this script's CSV output directory
OUT_FIG  <- here::here("output/figures/datasets/hpv")  # this script's figure output directory
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)      # create CSV output dir if missing, silently
dir.create(OUT_FIG, showWarnings = FALSE, recursive = TRUE)  # create figure output dir if missing, silently

sp <- fread(file.path(DATASETS, "hpv_spells.csv.gz"))  # dataset 2: hpv_spells, spell-level (0..N rows per facility)
ha <- fread(file.path(DATASETS, "hpv_active.csv.gz"))  # dataset 2b: hpv_active, facility x year collapse

fwrite_rounded <- function(dt, file, prop_cols = NULL, num_cols = NULL) {  # helper: round before writing so CSVs aren't raw float precision
  d <- copy(dt)  # work on a copy so the caller's data.table isn't mutated by reference
  for (cc in intersect(prop_cols, names(d))) d[, (cc) := round(get(cc), 3)]  # round share/proportion columns to 3dp
  for (cc in intersect(num_cols,  names(d))) d[, (cc) := round(get(cc), 2)]  # round other numeric columns (means etc.) to 2dp
  fwrite(d, file)  # write the rounded copy
}

# =========================================================================================================
# PART A -- hpv_spells (dataset 2, spell-level)
# =========================================================================================================

# ---- CSV 1: overview + spell_status breakdown ------------------------------------------------------------
overview_spells <- data.table(  # one row: total spells, distinct facilities, day-zero year range
  n_spells = nrow(sp), n_facilities = uniqueN(sp$PGM_SYS_ID),  # raw counts -- n_facilities is a distinct count, not a rate, so no double-count risk here
  dayzero_year_min = min(sp$DAYZERO_YEAR, na.rm = TRUE), dayzero_year_max = max(sp$DAYZERO_YEAR, na.rm = TRUE))  # NA-safe min/max
fwrite(overview_spells, file.path(OUT, "overview_spells.csv"))  # write CSV 1

status_breakdown <- sp[, .N, by = SPELL_STATUS][order(-N)]  # spell counts by status (e.g. open/closed), spell-level, sorted descending
status_breakdown[, pct := round(N / sum(N), 4)]  # share of all spells in each status
fwrite(status_breakdown, file.path(OUT, "spell_status_breakdown.csv"))  # write

# ---- CSV 2: spell duration, closed spells only (spell_days is NA otherwise, by construction) --------------
closed_days <- sp[SPELL_STATUS == "closed", SPELL_DAYS]  # FLAG: excludes open/unresolved spells entirely -- the duration stats below describe resolved spells only, biased toward shorter durations (an open spell, once eventually resolved, could run longer than any closed spell observed so far; no censoring adjustment or fallback end date is applied, and this is a silent restriction unless the reader notices SPELL_STATUS=="closed")
spell_duration <- data.table(n_closed = length(closed_days), min = min(closed_days), p25 = quantile(closed_days, .25),  # five-number summary, closed spells only
                             median = median(closed_days), p75 = quantile(closed_days, .75),  # median, p75
                             p90 = quantile(closed_days, .90), max = max(closed_days), mean = round(mean(closed_days), 1),  # p90, max, mean
                             pct_over_1yr = round(mean(closed_days > 365), 4))  # share of closed spells lasting over a year
fwrite(spell_duration, file.path(OUT, "spell_duration_closed.csv"))  # write CSV 2

# ---- CSV 3: spells by day-zero year (time trend; note DAYZERO_YEAR is unscreened here, per H4 -- includes
#   the 218/2026 outliers the collapse layer screens out, see hpv_active section below) --------------------
by_dayzero_year <- sp[!is.na(DAYZERO_YEAR), .N, by = DAYZERO_YEAR][order(DAYZERO_YEAR)]  # kept unscreened (raw record-level diagnostic, not the construction layer) -- known outlier years like 218/2026 still appear
by_dayzero_year[, in_range := DAYZERO_YEAR >= 1970 & DAYZERO_YEAR <= 2025]  # mirrors DZ_MIN/DZ_MAX (H4 screen) in code/04_datasets/04_hpv_active.R -- flags rows the hpv_active collapse layer screens out, so a reader isn't misled by the raw year range without having to drop them from this file
fwrite(by_dayzero_year, file.path(OUT, "spells_by_dayzero_year.csv"))  # write CSV 3

# ---- CSV 4: implicated program codes (PROGRAM_CODES is a whitespace-joined multi-value field per record).
#   NB: strsplit() must NOT be called inside `sp[i, j]` (bare, unwrapped in .()) -- data.table tries to
#   rectangularize the resulting ragged list and silently recycles/corrupts it (verified: inflated counts by
#   ~5x, e.g. CAATVP 143,323 vs the correct 25,555). Split on the plain vector instead.
prog_tokens <- strsplit(sp$PROGRAM_CODES[sp$PROGRAM_CODES != ""], "\\s+")  # FLAG: deliberately split OUTSIDE sp[i,j] (on the plain character vector) -- see note above; refactoring this into a bare data.table j-expression would silently corrupt the counts (documented, verified regression)
prog_freq <- data.table(program_code = unlist(prog_tokens))[, .N, by = program_code][order(-N)]  # flatten all tokens across all spells, count frequency per program code
prog_freq[, pct_of_spells := round(N / nrow(sp), 4)]  # share of ALL spells (not of tokens) whose PROGRAM_CODES includes this code
fwrite(prog_freq, file.path(OUT, "program_code_frequency.csv"))  # write CSV 4

# ---- CSV 5: agency type + state frequency ------------------------------------------------------------------
agency_freq <- sp[, .N, by = AGENCY_TYPE_DESC][order(-N)]  # spell counts by reporting agency type (spell-level, not facility-level)
agency_freq[, pct := round(N / sum(N), 4)]  # share of spells per agency type
fwrite(agency_freq, file.path(OUT, "agency_type_frequency.csv"))  # write CSV 5a

state_freq <- sp[STATE_CODE != "", .(n_spells = .N, n_facilities = uniqueN(PGM_SYS_ID)), by = STATE_CODE][order(-n_spells)]  # spells + distinct facilities per state; blank STATE_CODE rows are dropped, not reported as their own bucket
fwrite(state_freq, file.path(OUT, "state_frequency.csv"))  # write CSV 5b

# ---- CSV 6: spells per facility (distribution) -- the H2 "not merged" decision means a facility can carry
#   many overlapping/sequential HPV spells; this shows how concentrated that is -----------------------------
spells_per_facility <- sp[, .N, by = PGM_SYS_ID][, .N, by = .(n_spells = N)][order(n_spells)]  # collapses to one row per facility FIRST (inner by=PGM_SYS_ID), then tabulates how many facilities have each spell count -- the correct pattern that avoids double-counting facilities with multiple spells (the risk the file header flags)
fwrite(spells_per_facility, file.path(OUT, "spells_per_facility_distribution.csv"))  # write CSV 6
multi_spell_share <- sp[, .N, by = PGM_SYS_ID][, mean(N > 1)]  # same collapse-first pattern: share of FACILITIES (not spells) with more than one HPV spell

# ---- CSV 6b: EARLIEST_FRV_DETERM_DATE coverage + ordering vs. HPV_DAYZERO_DATE ---------------------------
#   FRV (Federally Reportable Violation) is the tier below HPV; EARLIEST_FRV_DETERM_DATE, where present, is
#   carried through from the raw violations extract (see 03_hpv_spells.R) but is NOT used in spell_status/
#   spell_days construction -- this is a first look at how often it's populated and how it orders vs day-zero.
frv_coverage <- data.table(  # spell-level: how many/what share of spells have EARLIEST_FRV_DETERM_DATE populated
  n_spells = nrow(sp),  # denominator: all spells
  n_with_frv_date = sp[!is.na(EARLIEST_FRV_DETERM_DATE), .N],  # spells with a non-missing FRV date
  pct_with_frv_date = round(sp[!is.na(EARLIEST_FRV_DETERM_DATE), .N] / nrow(sp), 4))  # share of all spells
fwrite(frv_coverage, file.path(OUT, "frv_date_coverage.csv"))  # write CSV 6b-i

frv_present <- sp[!is.na(EARLIEST_FRV_DETERM_DATE) & !is.na(HPV_DAYZERO_DATE)]  # subset to spells with BOTH dates present, so ordering is well-defined
frv_present[, frv_vs_dayzero := fcase(  # classify each spell by whether FRV determination precedes, equals, or follows HPV day-zero
  EARLIEST_FRV_DETERM_DATE <  HPV_DAYZERO_DATE, "frv_before_dayzero",  # FRV flagged before the HPV day-zero date
  EARLIEST_FRV_DETERM_DATE == HPV_DAYZERO_DATE, "frv_equals_dayzero",  # same calendar date
  EARLIEST_FRV_DETERM_DATE >  HPV_DAYZERO_DATE, "frv_after_dayzero")]  # FRV flagged after day-zero
frv_ordering <- frv_present[, .N, by = frv_vs_dayzero][order(-N)]  # count spells in each ordering bucket
frv_ordering[, pct := round(N / sum(N), 4)]  # share of (both-dates-present) spells in each bucket
fwrite(frv_ordering, file.path(OUT, "frv_vs_dayzero_ordering.csv"))  # write CSV 6b-ii

frv_gap <- frv_present[frv_vs_dayzero == "frv_before_dayzero",  # restrict to spells where FRV precedes day-zero
                        as.integer(HPV_DAYZERO_DATE - EARLIEST_FRV_DETERM_DATE)]  # gap in days between FRV determination and day-zero
frv_gap_summary <- data.table(n = length(frv_gap), min = min(frv_gap), p25 = quantile(frv_gap, .25),  # five-number summary of that gap, days
                              median = median(frv_gap), p75 = quantile(frv_gap, .75),  # median, p75
                              p90 = quantile(frv_gap, .90), max = max(frv_gap), mean = round(mean(frv_gap), 1))  # p90, max, mean
fwrite(frv_gap_summary, file.path(OUT, "frv_before_dayzero_gap_days.csv"))  # write CSV 6b-iii

# =========================================================================================================
# PART B -- hpv_active (dataset 2b, facility x year)
# =========================================================================================================

# ---- CSV 7: overview + zero/NA breakdown -------------------------------------------------------------------
overview_active <- data.table(  # one row: hpv_active overview including the zero-vs-NA breakdown (H6 discipline)
  n_facility_years = nrow(ha), n_facilities = uniqueN(ha$PGM_SYS_ID),  # total rows in the facility x year table; distinct facilities
  n_active   = sum(ha$HPV_ACTIVE == 1, na.rm = TRUE),  # facility-years where HPV_ACTIVE is a real 1 (NA excluded via na.rm, not counted as inactive)
  n_inactive = sum(ha$HPV_ACTIVE == 0, na.rm = TRUE),  # facility-years where HPV_ACTIVE is a real 0
  n_na       = sum(is.na(ha$HPV_ACTIVE)),  # facility-years where HPV_ACTIVE is structurally unknown -- never treated as a false 0 (H6)
  n_ever_active_facilities = uniqueN(ha[HPV_ACTIVE == 1, PGM_SYS_ID]))  # distinct facilities with >=1 active facility-year (NA rows auto-excluded, since NA==1 is not TRUE)
fwrite(overview_active, file.path(OUT, "overview_active.csv"))  # write CSV 7

# ---- CSV 8: active rate by year (denominator = non-NA only, so the rate isn't diluted by structural NA) ----
n_by_year <- ha[, .N, by = YEAR]  # total facility-years per year, ALL rows (denominator for pct_na below)
by_year_active <- ha[!is.na(HPV_ACTIVE), .(n_known = .N, n_active = sum(HPV_ACTIVE == 1)), by = YEAR][order(YEAR)]  # restricted to the non-NA subset per H6
by_year_active <- merge(by_year_active, n_by_year, by = "YEAR")  # bring in the full-panel per-year total so NA share can be computed (n_known alone can't recover it)
by_year_active[, `:=`(n_na = N - n_known, pct_active = round(n_active / n_known, 4))]  # n_na fills the per-year gap the header claims every rate reports; active rate stays on the known-status denominator (H6)
by_year_active[, pct_na := round(n_na / N, 4)]
by_year_active[, N := NULL]  # drop the merge helper column, keep n_known/n_na/n_active/pct_active/pct_na
fwrite(by_year_active, file.path(OUT, "active_rate_by_year.csv"))  # write CSV 8

# ---- CSV 9: "spell wins" cases -- HPV_ACTIVE==1 in a year the facility had NO other ICIS record that year
#   (H6's stated rationale in practice: 2,370 fac-yrs expected per the decision doc) --------------------------
reg_obs <- fread(file.path(DATASETS, "regulatory.csv.gz"), select = c("PGM_SYS_ID", "YEAR", "ICIS_OBSERVED"))  # dataset 0, just the join keys + observed flag
active_ha  <- ha[HPV_ACTIVE == 1]
spell_wins <- merge(active_ha, reg_obs, by = c("PGM_SYS_ID", "YEAR"))  # inner join (merge()'s default) on facility+year
n_unmatched <- nrow(active_ha) - nrow(spell_wins)  # any HPV_ACTIVE==1 facility-year absent from regulatory.csv.gz (a spine mismatch) would silently drop out of the inner join above -- surfaced explicitly here instead of assumed away
cat(sprintf("  [check] spell_wins join: %d of %d HPV_ACTIVE==1 facility-years matched to regulatory.csv.gz (%d unmatched)\n",
            nrow(spell_wins), nrow(active_ha), n_unmatched))
if (n_unmatched > 0) warning(sprintf("14_hpv_profile.R: %d HPV_ACTIVE==1 facility-years had no regulatory.csv.gz match and were dropped from spell_wins_cases.csv -- investigate the spine mismatch before trusting n_active_fac_years", n_unmatched))
spell_wins_summary <- data.table(  # of active facility-years, how many had ICIS_OBSERVED==0 (no other ICIS record that year) -- the "spell wins" cases motivating H6
  n_active_fac_years = nrow(spell_wins),  # denominator: active facility-years that matched to regulatory
  n_active_icis_unobserved = spell_wins[ICIS_OBSERVED == 0, .N],  # of those, how many had no other ICIS record that year
  pct_active_icis_unobserved = round(spell_wins[ICIS_OBSERVED == 0, .N] / nrow(spell_wins), 4))  # share
fwrite(spell_wins_summary, file.path(OUT, "spell_wins_cases.csv"))  # write CSV 9

# =========================================================================================================
# FIGURES -- print-ready (300dpi), validated categorical palette, direct end-of-line labels
# =========================================================================================================
PAL <- c(blue = "#2a78d6", aqua = "#1baf7a", yellow = "#eda100", green = "#008300", violet = "#4a3aa7", red = "#e34948")  # validated categorical palette (dataviz skill), named by hue
INK <- "#0b0b0b"; INK_SECONDARY <- "#52514e"; GRID <- "#e1e0d9"; AXIS <- "#c3c2b7"  # text / gridline / axis-line colors for the print theme
theme_journal <- theme_minimal(base_size = 11) +  # base theme, print-ready variant
  theme(panel.grid.minor = element_blank(), panel.grid.major = element_line(color = GRID, linewidth = 0.3),  # drop minor gridlines; thin muted major gridlines
        axis.line = element_line(color = AXIS, linewidth = 0.3), axis.ticks = element_line(color = AXIS, linewidth = 0.3),  # thin muted axis lines/ticks
        text = element_text(color = INK), axis.text = element_text(color = INK_SECONDARY),  # body text vs. axis label ink color
        plot.title = element_text(face = "bold", size = 12), plot.subtitle = element_text(color = INK_SECONDARY, size = 9.5),  # title/subtitle styling
        plot.caption = element_text(color = INK_SECONDARY, size = 8, hjust = 0), legend.position = "none")  # caption styling; legends off (direct end-of-line labels used instead where needed)
save_fig <- function(name, plot, w = 7.5, h = 4.5) ggsave(file.path(OUT_FIG, name), plot, width = w, height = h, dpi = 300)  # helper: save a figure at 300dpi, default 7.5x4.5in

# ---- FIGURE 1: HPV-active rate over time, 2005-2025 ------------------------------------------------------
fig1 <- ggplot(by_year_active, aes(YEAR, pct_active)) +  # line chart of hpv-active share over time (see FLAG at by_year_active above re: no per-year NA share)
  geom_line(color = PAL[["blue"]], linewidth = 0.9) + geom_point(color = PAL[["blue"]], size = 1.6) +  # line + point markers, single blue series
  scale_x_continuous(breaks = seq(min(by_year_active$YEAR), max(by_year_active$YEAR), 5)) +  # x-axis tick every 5 years
  scale_y_continuous(labels = label_percent(), limits = c(0, NA)) +  # y-axis as percent, floor at 0
  labs(title = "Share of facilities in HPV-active status, 2005-2025",
       subtitle = "Of facility-years with known status (HPV_ACTIVE non-NA); a steady ~4.5x decline, mechanism not\nfully explained by coverage-ramp or right-truncation caveats alone (see hpv_profile.md)",
       x = NULL, y = "Share HPV-active", caption = "Source: data/datasets/hpv_active.csv.gz (dataset 2b).") +  # title/subtitle/axis/caption text
  theme_journal + theme(plot.subtitle = element_text(color = INK_SECONDARY, size = 8.7, lineheight = 1.1))  # apply theme, tighter subtitle for the two-line text
save_fig("hpv_active_rate_over_time.png", fig1)  # write PNG

# ---- FIGURE 2: closed-spell duration distribution (truncated at p99 for readability; long tail noted) -----
dur <- data.table(days = closed_days)  # wrap the closed-spell duration vector (see FLAG at closed_days above) for ggplot
p99 <- quantile(closed_days, .99)  # 99th percentile, used only to truncate the displayed x-axis
fig2 <- ggplot(dur, aes(days)) +  # histogram of closed-spell duration
  geom_histogram(binwidth = 30, fill = PAL[["blue"]], color = "white", linewidth = 0.15, boundary = 0) +  # 30-day bins, blue fill, white borders
  coord_cartesian(xlim = c(0, p99)) +  # truncate the DISPLAYED range at p99 -- underlying data/stats are not filtered, just the view
  scale_x_continuous(labels = label_comma()) + scale_y_continuous(labels = label_comma()) +  # comma-formatted axis labels
  labs(title = "HPV spell duration (closed spells)",
       subtitle = sprintf("n = %s closed spells; x-axis truncated at the 99th percentile (%s days); %.1f%% last over a year",
                          format(nrow(dur), big.mark = ","), format(round(p99), big.mark = ","), 100 * spell_duration$pct_over_1yr),
       x = "Days from day-zero to resolved (inclusive)", y = "Spells",
       caption = "Source: data/datasets/hpv_spells.csv.gz (dataset 2).") +  # title/subtitle (reports n, truncation point, %>1yr)/axis/caption
  theme_journal
save_fig("hpv_spell_duration.png", fig2)  # write PNG

# ---- FIGURE 3: program codes implicated (top 8, share of spells) -------------------------------------------
prog_top <- head(prog_freq[order(-N)], 8)  # top 8 program codes by spell count
prog_top[, program_code := factor(program_code, levels = program_code)]  # fix factor level order to the sorted order, so geom_col doesn't re-sort alphabetically
fig3 <- ggplot(prog_top, aes(program_code, pct_of_spells)) +  # bar chart, program code frequency
  geom_col(fill = PAL[["blue"]], width = 0.7) +  # bars, single blue series
  scale_y_continuous(labels = label_percent()) +  # y-axis as percent
  labs(title = "Programs implicated in HPV spells (top 8)",
       subtitle = "Share of spells whose PROGRAM_CODES includes this program (multi-value per spell; shares don't sum to 100%)",
       x = NULL, y = "Share of spells", caption = "Source: data/datasets/hpv_spells.csv.gz (dataset 2).") +  # title/subtitle (flags multi-value, non-additive shares)/axis/caption
  theme_journal
save_fig("hpv_program_frequency.png", fig3)  # write PNG

# ---- console summary ---------------------------------------------------------------------------------------
cat("data/datasets/hpv_spells.csv.gz + hpv_active.csv.gz -- profile summary\n")  # header banner
cat("==========================================================================\n\n")  # divider
cat("PART A -- HPV_SPELLS (spell-level, dataset 2)\n")  # Part A banner
cat(sprintf("%s spells | %s facilities | day-zero years %s-%s\n",
            format(overview_spells$n_spells, big.mark=","), format(overview_spells$n_facilities, big.mark=","),
            overview_spells$dayzero_year_min, overview_spells$dayzero_year_max))  # print spell/facility counts + day-zero year range
cat("\nSPELL_STATUS BREAKDOWN\n"); print(as.data.frame(status_breakdown), row.names = FALSE)  # print spell status breakdown table
cat("\nSPELL DURATION (closed spells, days, inclusive)\n"); print(as.data.frame(spell_duration), row.names = FALSE)  # print spell duration summary table
cat(sprintf("\nSHARE OF FACILITIES WITH >1 SPELL: %.1f%%\n", 100 * multi_spell_share))  # print facility-level multi-spell share
cat(sprintf("\nFRV DATE COVERAGE: %s / %s spells (%.1f%%) have EARLIEST_FRV_DETERM_DATE\n",
            format(frv_coverage$n_with_frv_date, big.mark=","), format(frv_coverage$n_spells, big.mark=","),
            100 * frv_coverage$pct_with_frv_date))  # print FRV date coverage stat
cat("\nFRV DATE vs. HPV_DAYZERO_DATE ORDERING (of spells with both dates)\n"); print(as.data.frame(frv_ordering), row.names = FALSE)  # print FRV vs day-zero ordering table
cat("\nGAP (days) WHERE FRV DATE PRECEDES DAY-ZERO\n"); print(as.data.frame(frv_gap_summary), row.names = FALSE)  # print FRV-before-dayzero gap summary table
cat("\nTOP PROGRAM CODES IMPLICATED\n"); print(as.data.frame(head(prog_freq, 10)), row.names = FALSE)  # print top 10 program codes
cat("\nAGENCY TYPE FREQUENCY\n"); print(as.data.frame(agency_freq), row.names = FALSE)  # print agency type frequency table

cat("\n\nPART B -- HPV_ACTIVE (facility x year, dataset 2b)\n")  # Part B banner
print(as.data.frame(overview_active), row.names = FALSE)  # print hpv_active overview (incl. n_na)
cat("\nACTIVE RATE BY YEAR (of known/non-NA)\n"); print(as.data.frame(by_year_active), row.names = FALSE)  # print active rate by year table (see FLAG above: no per-year NA share)
cat("\nSPELL-WINS CASES (active in a year with no other ICIS record)\n")  # spell-wins cases label
print(as.data.frame(spell_wins_summary), row.names = FALSE)  # print spell-wins summary table

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
#   1. (closed_days) Duration stats (CSV 2 / spell_duration_closed.csv, and FIGURE 2) are computed on CLOSED
#      spells only -- open/unresolved spells are excluded entirely rather than censored or given a documented
#      fallback end date. This biases the duration distribution toward shorter, resolved spells. Reviewed
#      2026-07-28: left as-is -- matches H3's decision that SPELL_DAYS is only defined for closed spells.
#   2. RESOLVED 2026-07-28: added an in_range column (DAYZERO_YEAR in [1970,2025], mirroring 04_hpv_active.R's
#      DZ_MIN/DZ_MAX H4 screen) to spells_by_dayzero_year.csv -- rows stay unfiltered (raw record-level
#      diagnostic) but a reader can now see/filter which years are implausible.
#   3. Line ~69 (prog_tokens): strsplit() is deliberately called on the plain character vector, OUTSIDE
#      sp[i, j]. This is load-bearing, not stylistic -- calling strsplit() inside a bare data.table j-expression
#      silently corrupts the multi-value program-code counts (verified regression: ~5x inflation, e.g. CAATVP
#      143,323 vs. the correct 25,555). A future refactor that "simplifies" this into one chained data.table
#      call would reintroduce the bug silently.
#   4. RESOLVED 2026-07-28: active_rate_by_year.csv now includes n_na/pct_na per year (computed against the
#      full per-year facility-year count, not just the non-NA subset), bringing the table in line with the
#      file header's claim that every rate reports its NA share.
#   5. RESOLVED 2026-07-28: added an explicit unmatched-row check around the spell_wins inner join -- prints
#      the match count every run and throws a warning() if any HPV_ACTIVE==1 facility-year fails to match
#      regulatory.csv.gz, instead of silently understating n_active_fac_years.
