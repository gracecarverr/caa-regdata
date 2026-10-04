# =========================================================================================================
# code/diagnostics/06_panel_profile.R -- exploratory profiling of the three built panels (electric,
#   major_synmin, universe). Emits CSV tabulations (five-number summaries + frequencies + coverage) and
#   PNG figures (distributions, time series). Purpose: characterize each panel for a reader picking
#   the project up cold. Companion to 05_panel_summaries.R (which makes the paper-oriented LaTeX tables).
#
#   in : data/panels/{electric,major_synmin,universe}.csv.gz
#   out: output/panel_profile/*.csv  (tabulations, incl. summary_duplication.csv -- duplicate load)
#        output/figures/*.png        (figures)
#
#   DISCIPLINE (do not "fix" away): counts are only meaningful for OBSERVED facility-years
#   (obs_source in {event, operating}); unobserved years -- including ALL pre-2015 and closed
#   facilities -- are NA. Every count summary is computed on the observed subset AND reports the NA share,
#   so a structural NA is never read as a zero. Wayback columns (operating, op_status_code, prog_*_active)
#   are 2015-2025 only. penalty_amount codes 0/none as NA -> summarized over nonzero only. No numbers are
#   hand-entered; every cell is computed here.
#   Hand-run (not part of RUN_ALL.R). No stochastic step.
# =========================================================================================================
suppressPackageStartupMessages({
  library(data.table); library(ggplot2); library(scales)                # data.table for wrangling, ggplot2/scales for the figures
})
options(scipen = 999)  # write full-digit numbers in the CSVs, not scientific notation

PANELS  <- here::here("data/panels")                                    # source dir for the three built panels
OUT_CSV <- here::here("output/panel_profile")                           # destination dir for CSV tabulations
OUT_FIG <- here::here("output/figures")                                 # destination dir for PNG figures
dir.create(OUT_CSV, showWarnings = FALSE, recursive = TRUE)             # create OUT_CSV if missing; silent if it already exists
dir.create(OUT_FIG, showWarnings = FALSE, recursive = TRUE)             # create OUT_FIG if missing; silent if it already exists

YEARS  <- 2005:2025                                                     # nominal panel year range (21 years), used for the "balanced" rectangle check
WB_YRS <- 2015:2025                                    # wayback window (operating status available)
NAMES  <- c(electric = "Electric", major_synmin = "Major/SynMin", universe = "Universe")  # panel key -> display label, fixes column/facet order everywhere below
read_panel <- function(nm) fread(file.path(PANELS, paste0(nm, ".csv.gz")))  # read one panel by its short name
P <- lapply(names(NAMES), read_panel); names(P) <- names(NAMES)         # P: named list of the 3 panels, keyed like NAMES

# write a CSV with human-readable rounding: proportions/shares to 3 decimals, money/means to 2. Rounds a
# COPY so in-memory tables keep full precision for the figures. Blank cells are NA (e.g. pct_operating
# pre-2015, where wayback status does not exist) -- left as NA on purpose, never coerced to 0.
fwrite_rounded <- function(dt, file, prop_cols = NULL, num_cols = NULL) {
  d <- copy(dt)                                                         # copy so rounding never touches the caller's full-precision table
  for (cc in intersect(prop_cols, names(d))) d[, (cc) := round(get(cc), 3)]  # round share/proportion columns to 3dp, in place on the copy
  for (cc in intersect(num_cols,  names(d))) d[, (cc) := round(get(cc), 2)]  # round money/mean columns to 2dp, in place on the copy
  fwrite(d, file)                                                       # write the rounded copy to disk
}

# count measures (the n_* block) + the key subset used in figures. NB grep("^n_") now also picks up the
# duplicate-load indicators n_*_dup / n_*_dup_exact, so they get five-number summaries in summary_counts.csv
# automatically; summary_duplication.csv (below) adds the dup *shares* per family.
COUNT_COLS <- grep("^n_", names(P[["universe"]]), value = TRUE)           # 45 measures (incl. _dup / _dup_exact)
KEY_MEAS   <- c(n_inspections = "Inspections", n_violations = "Violations", n_hpv = "HPV",
                n_enforcement = "Enforcement", n_certs = "Certifications", n_stack_tests = "Stack tests")  # the 6 headline count measures shown in the distribution/ECDF figures
theme_set(theme_minimal(base_size = 11))                                # default ggplot theme for every figure below
save_fig <- function(name, plot, w = 9, h = 6)                          # write a ggplot object to OUT_FIG at a fixed dpi
  ggsave(file.path(OUT_FIG, name), plot, width = w, height = h, dpi = 150)

# observed subset: the only rows where a 0 count is a real 0 (not a structural NA)
observed <- function(d) d[obs_source != "unobserved"]
# FLAG: `observed()` compares obs_source with `!=`, which silently drops any row where obs_source itself is
# NA (NA != "unobserved" is NA, and data.table's `[` row filter treats NA as FALSE, so such a row would be
# excluded from BOTH the observed subset and any "unobserved" tally). This matches 05_panel_summaries.R's
# obs_share() caveat: obs_source is expected to always be non-NA by construction, but nothing here enforces
# or checks that invariant -- every downstream use of observed() (CSV2, CSV3b, key_long, FIG1/2) inherits it.

# =========================================================================================================
# CSV 1 -- panel overview
# =========================================================================================================
overview <- rbindlist(lapply(names(P), function(nm) {
  d <- P[[nm]]                                                          # one panel's full facility-year table
  data.table(
    panel            = NAMES[nm],                                      # display label for this panel
    n_facilities     = uniqueN(d$PGM_SYS_ID),                          # distinct facility count
    n_facility_years = nrow(d),                                        # raw row count (facility x year)
    year_min         = min(d$year), year_max = max(d$year),            # observed year range, read from the data
    balanced         = nrow(d) == uniqueN(d$PGM_SYS_ID) * length(YEARS),  # sanity check: full facility x year rectangle over YEARS
    share_event      = mean(d$obs_source == "event"),                  # share of ALL rows whose count came from an observed event
    share_operating  = mean(d$obs_source == "operating"),              # share of ALL rows whose zero came from a wayback-confirmed operating status
    share_unobserved = mean(d$obs_source == "unobserved"))             # share of ALL rows with no basis for a count at all (NA, not zero)
}))
fwrite_rounded(overview, file.path(OUT_CSV, "panel_overview.csv"),
               prop_cols = c("share_event", "share_operating", "share_unobserved"))

# =========================================================================================================
# CSV 2 -- five-number summaries (+ mean/sd, %zero, NA accounting) for every count measure, observed subset
# =========================================================================================================
summarise_measure <- function(d_all, m) {
  x_all <- d_all[[m]]                                                  # the raw column, ALL facility-years (observed + unobserved)
  x     <- observed(d_all)[[m]]                        # summarise over observed facility-years only
  x     <- x[!is.na(x)]                                                # drop any residual NA within the observed subset before the five-number summary
  data.table(
    n_obs = length(x), n_na = sum(is.na(x_all)), pct_na = mean(is.na(x_all)),
    # FLAG: n_na / pct_na are computed on x_all (ALL facility-years, observed + unobserved), while n_obs and
    # every stat below it are computed on x (observed subset, NA-dropped). This matches the file header's
    # stated discipline ("computed on the observed subset AND reports the NA share") -- pct_na is meant to
    # capture the full structural-NA picture, not just NA-within-observed -- but it means n_obs + n_na will
    # NOT sum to nrow(d_all) unless the observed subset has zero internal NAs. A reader skimming one row of
    # summary_counts.csv could easily misread pct_na as "% of the n_obs stats' own denominator that's NA"
    # rather than "% of all facility-years, most of which are the unobserved rows by construction."
    min = min(x), p25 = quantile(x, .25), median = median(x), p75 = quantile(x, .75), max = max(x),  # five-number summary over observed, non-NA values
    mean = mean(x), sd = sd(x), pct_zero = mean(x == 0), pct_nonzero = mean(x > 0))                  # mean/sd + zero/nonzero shares, same observed subset
}
summary_counts <- rbindlist(lapply(names(P), function(nm)
  rbindlist(lapply(COUNT_COLS, function(m)
    cbind(panel = NAMES[nm], measure = m, summarise_measure(P[[nm]], m))))))  # one row per panel x count measure
fwrite_rounded(summary_counts, file.path(OUT_CSV, "summary_counts.csv"),
               prop_cols = c("pct_na", "pct_zero", "pct_nonzero"), num_cols = c("mean", "sd"))

# =========================================================================================================
# CSV 3 -- penalty_amount: nonzero five-number summary + total (per panel). total now sums ALL formal rows;
#   dup_total / dup_share report the share of penalty dollars carried by event-key duplicate rows.
# =========================================================================================================
summary_penalty <- rbindlist(lapply(names(P), function(nm) {
  p <- P[[nm]]$penalty_amount; p <- p[!is.na(p) & p > 0]                # nonzero, non-NA penalties only (0/none is coded NA per header discipline)
  total     <- sum(p)                                                   # total penalty dollars, nonzero rows only
  dup_total <- sum(P[[nm]]$penalty_amount_dup, na.rm = TRUE)
  # FLAG: unlike summary_duplication (CSV 3b) below, this block never calls observed() -- `p` is filtered by
  # !is.na & >0 (relying on penalty_amount already being NA off the observed subset) and dup_total sums
  # penalty_amount_dup over ALL rows via na.rm=TRUE rather than an explicit observed-subset restriction. Both
  # are documented in their own header comments and likely agree in practice (if penalty_amount_dup is NA
  # wherever penalty_amount is), but the two "duplicate load" computations in this file use different
  # subsetting idioms for what's conceptually the same restriction.
  data.table(panel = NAMES[nm], n_nonzero = length(p),
             min = min(p), p25 = quantile(p, .25), median = median(p), p75 = quantile(p, .75),
             max = max(p), mean = mean(p), total = total,
             dup_total = dup_total, dup_share = if (total > 0) dup_total / total else NA_real_)         # guard div-by-zero if a panel has no nonzero penalties
}))
fwrite_rounded(summary_penalty, file.path(OUT_CSV, "summary_penalty.csv"),
               num_cols = c("mean", "total", "dup_total"), prop_cols = "dup_share")

# =========================================================================================================
# CSV 3b -- duplicate load: how much of each family's (all-row) count is duplicate. dup = event-key repeats,
#   dup_exact = byte-identical. Shares are Sum(dup) / Sum(count) over OBSERVED facility-years. Only the
#   families that carry duplicates have indicators; violations/stacktests have none by construction.
# =========================================================================================================
DUP_FAMILIES <- c(inspections = "n_inspections", enforcement = "n_enforcement",
                  formal = "n_formal", informal = "n_informal", certs = "n_certs")  # base count column per duplicate-tracked family
summary_duplication <- rbindlist(lapply(names(P), function(nm) {
  d <- observed(P[[nm]])                                                # explicit observed-subset restriction (contrast with summary_penalty above)
  rbindlist(lapply(names(DUP_FAMILIES), function(fam) {
    base <- DUP_FAMILIES[[fam]]                                         # base column name, e.g. "n_inspections"
    tot  <- sum(d[[base]], na.rm = TRUE)                                # total events in this family, observed subset
    dup  <- sum(d[[paste0(base, "_dup")]],       na.rm = TRUE)          # total event-key-duplicate events
    dex  <- sum(d[[paste0(base, "_dup_exact")]], na.rm = TRUE)          # total byte-identical-duplicate events
    data.table(panel = NAMES[nm], family = fam, n_rows = tot, n_dup = dup, n_dup_exact = dex,
               dup_share = if (tot > 0) dup / tot else NA_real_,        # guard div-by-zero
               dup_exact_share = if (tot > 0) dex / tot else NA_real_)  # guard div-by-zero
  }))
}))
fwrite_rounded(summary_duplication, file.path(OUT_CSV, "summary_duplication.csv"),
               prop_cols = c("dup_share", "dup_exact_share"))

# =========================================================================================================
# CSV 4 -- categorical frequency tables (long)
# =========================================================================================================
CAT_VARS <- c("obs_source", "AIR_POLLUTANT_CLASS_DESC", "op_status_current_desc",
              "facility_type", "EPA_REGION")
freq_cat <- rbindlist(lapply(names(P), function(nm) {
  d <- P[[nm]]                                                          # one panel's full facility-year table
  # frequencies are over facilities (time-invariant attributes), except obs_source which is per row
  rbindlist(lapply(CAT_VARS, function(v) {
    base <- if (v == "obs_source") d else d[, .SD[1L], by = PGM_SYS_ID]
    # FLAG: for the 4 non-obs_source vars, this takes the FIRST row per facility as that facility's value
    # rather than verifying it's constant across the facility's years. By pipeline construction
    # (code/03_panel_building/00_spine.R) these ARE attached as a single facility-level snapshot repeated
    # across all years -- AIR_POLLUTANT_CLASS_DESC, op_status_current_desc (explicitly the CURRENT snapshot,
    # not the year-varying wayback status), facility_type, and EPA_REGION should all be genuinely
    # time-invariant here -- but this function assumes that invariant rather than checking it, same caveat
    # as 05_panel_summaries.R's cls_share(). Also note the NA convention: a facility with NA for one of these
    # fields gets its own "NA" level row here (via .N by group), which differs from 05_panel_summaries.R's
    # Table 1 "other/missing" residual-bucket convention (`!x %in% known_values`) for the same underlying data.
    tb <- base[, .N, by = c(v)][order(-N)]                              # frequency count per level, most common first
    setnames(tb, v, "level")                                            # rename the variable column to a common "level" name across all CAT_VARS
    tb[, `:=`(panel = NAMES[nm], variable = v, level = as.character(level), pct = N / sum(N))]  # tag with panel/variable, coerce level to character, compute share within this panel x variable
    tb[, .(panel, variable, level, n = N, pct)]                         # reorder/select output columns
  }))
}))
fwrite_rounded(freq_cat, file.path(OUT_CSV, "freq_categorical.csv"), prop_cols = "pct")

# =========================================================================================================
# CSV 5 -- binary-flag prevalence (share == 1, with NA share). Wayback binaries over 2015-2025.
# =========================================================================================================
BIN_COLS <- c(grep("^any_", names(P[["universe"]]), value = TRUE),
              grep("^emits_", names(P[["universe"]]), value = TRUE),
              grep("^prog_", names(P[["universe"]]), value = TRUE),
              "operating", "hpv_active", "hpv_active_1mo")
BIN_COLS <- intersect(BIN_COLS, names(P[["universe"]]))                 # keep only columns that actually exist on this panel
wayback_bin <- function(b) b == "operating" || grepl("_active$", b)
# FLAG: this regex is meant to catch the wayback-only flags ("operating" and the prog_*_active columns
# listed in the file header), but grepl("_active$", b) ALSO matches "hpv_active" -- which is NOT a wayback
# column. hpv_active is derived from HPV interval spells over the FULL 2005-2025 panel
# (code/03_panel_building/03_build_functions.R:139-177) and is conspicuously absent from the header's list
# of wayback-restricted columns (operating, op_status_code, prog_*_active). The result: binary_prevalence.csv
# wrongly restricts hpv_active's share_1/pct_na to the 2015-2025 window and labels it "2015-2025" below
# (it should be computed and labeled over the full 2005-2025 panel), while its close sibling hpv_active_1mo
# escapes the bug only because its name ends in "_1mo" rather than "_active" -- an accidental, unexplained
# asymmetry between two flags that should be treated identically.
binary_prevalence <- rbindlist(lapply(names(P), function(nm) {
  d <- P[[nm]]                                                          # one panel's full facility-year table
  rbindlist(lapply(BIN_COLS, function(b) {
    dd <- if (wayback_bin(b)) d[year %in% WB_YRS] else d          # respect the wayback window
    x <- dd[[b]]                                                        # the flag column, restricted (or not) to the wayback window
    data.table(panel = NAMES[nm], flag = b, window = if (wayback_bin(b)) "2015-2025" else "2005-2025",  # window label mirrors (and inherits the bug of) wayback_bin() above
               n = length(x), share_1 = mean(x == 1, na.rm = TRUE), pct_na = mean(is.na(x)))
    # share_1's denominator is x with NA dropped via na.rm=TRUE -- an implicit stand-in for observed(), not
    # an explicit call to it (contrast with CSV2's summarise_measure, which explicitly restricts via
    # observed() first). Equivalent in practice only if unobserved facility-years are always NA on these
    # flags and observed ones never are.
  }))
}))
fwrite_rounded(binary_prevalence, file.path(OUT_CSV, "binary_prevalence.csv"),
               prop_cols = c("share_1", "pct_na"))

# =========================================================================================================
# CSV 6 -- coverage by year (per panel x year)
# =========================================================================================================
coverage_by_year <- rbindlist(lapply(names(P), function(nm) {
  d <- P[[nm]]                                                          # one panel's full facility-year table
  d[, .(
    panel          = NAMES[nm],                                        # display label for this panel
    n_facilities   = uniqueN(PGM_SYS_ID),                               # distinct facilities present in this year (balanced panel -> constant across years)
    pct_observed   = mean(obs_source != "unobserved"),                  # share of ALL facility-years this year that are observed
    pct_operating  = if (.BY$year %in% WB_YRS) mean(operating == 1, na.rm = TRUE) else NA_real_,
    # FLAG: pct_operating's denominator is ALL facility-years this year (NA dropped via na.rm), while
    # mean_insp/mean_viol/mean_enf just below explicitly restrict to the OBSERVED subset first. Both are
    # legitimate choices given what each flag means (operating status isn't gated by obs_source the way
    # event counts are), but the two kinds of columns sit side by side in the same output row with different
    # implicit bases -- worth knowing before comparing pct_operating directly against pct_observed or the
    # mean_* columns in the same row.
    mean_insp      = mean(n_inspections[obs_source != "unobserved"], na.rm = TRUE),  # mean inspections, observed facility-years only, this year
    mean_viol      = mean(n_violations[obs_source != "unobserved"], na.rm = TRUE),   # mean violations, observed facility-years only, this year
    mean_enf       = mean(n_enforcement[obs_source != "unobserved"], na.rm = TRUE)   # mean enforcement actions, observed facility-years only, this year
  ), by = year][order(year)]                                            # one row per year, in year order
}))
fwrite_rounded(coverage_by_year, file.path(OUT_CSV, "coverage_by_year.csv"),
               prop_cols = c("pct_observed", "pct_operating"),
               num_cols = c("mean_insp", "mean_viol", "mean_enf"))

# =========================================================================================================
# CSV 7 -- facilities & facility-years by state
# =========================================================================================================
state_counts <- rbindlist(lapply(names(P), function(nm) {
  d <- P[[nm]]                                                          # one panel's full facility-year table
  d[!is.na(STATE) & STATE != "", .(panel = NAMES[nm],                   # drop rows with missing/blank state before counting
     n_facilities = uniqueN(PGM_SYS_ID), n_facility_years = .N), by = STATE][order(-n_facilities)]  # facility + facility-year counts per state, most facilities first
}))
fwrite(state_counts, file.path(OUT_CSV, "state_counts.csv"))

# =========================================================================================================
# FIGURES
# =========================================================================================================
# long table of KEY_MEAS over observed facility-years, tagged by panel (reused by several figures)
key_long <- rbindlist(lapply(names(P), function(nm) {
  d <- observed(P[[nm]])                                                # observed subset only -- a structural NA must never enter these figures
  melt(d[, c("year", names(KEY_MEAS)), with = FALSE], id.vars = "year",  # keep only year + the 6 key measure columns, then reshape to long
       variable.name = "measure", value.name = "count")[!is.na(count)][, panel := NAMES[nm]]  # drop any residual NA count, tag rows with the panel label
}))
key_long[, measure := factor(KEY_MEAS[as.character(measure)], levels = unname(KEY_MEAS))]  # relabel measure codes to display names, fix facet order
key_long[, panel := factor(panel, levels = unname(NAMES))]              # fix panel order for consistent colouring/faceting

# --- FIG 1: per-panel distribution small-multiples (log1p x) --------------------------------------------
for (nm in names(P)) {
  g <- ggplot(key_long[panel == NAMES[nm]], aes(x = count)) +           # this panel's observed key-measure counts
    geom_histogram(bins = 30, fill = "#2c7fb8", colour = "white", linewidth = .1) +  # histogram of counts
    scale_x_continuous(trans = "log1p", breaks = c(0, 1, 3, 10, 30, 100, 300)) +     # log1p x-axis so 0 is visible alongside a long right tail
    scale_y_continuous(labels = label_number(scale_cut = cut_short_scale())) +       # abbreviated y-axis labels (e.g. "10k")
    facet_wrap(~ measure, scales = "free_y") +                          # one small-multiple panel per key measure, independent y-scales
    labs(title = paste0(NAMES[nm], " panel: distribution of key measures (observed facility-years)"),
         subtitle = "x on log1p scale; observed = obs_source in {event, operating}",
         x = "count in a facility-year", y = "facility-years")
  save_fig(paste0("dist_counts_", nm, ".png"), g)                       # one PNG per panel, e.g. dist_counts_electric.png
}

# --- FIG 2: ECDF of key measures, three panels overlaid -------------------------------------------------
g_ecdf <- ggplot(key_long, aes(x = count, colour = panel)) +            # all 3 panels overlaid, coloured by panel
  stat_ecdf(linewidth = .7) +                                           # empirical CDF curve per panel x measure
  scale_x_continuous(trans = "log1p", breaks = c(0, 1, 3, 10, 30, 100)) +  # log1p x-axis, same rationale as FIG 1
  facet_wrap(~ measure, scales = "free_x") +                            # one small-multiple per key measure, independent x-scales
  labs(title = "ECDF of key measures by panel (observed facility-years)",
       x = "count in a facility-year (log1p)", y = "cumulative share", colour = NULL) +
  theme(legend.position = "bottom")
save_fig("ecdf_key_measures.png", g_ecdf)

# --- FIG 3: coverage over time --------------------------------------------------------------------------
cov <- copy(coverage_by_year)[, panel := factor(panel, levels = unname(NAMES))]  # copy so factor-ordering doesn't touch the CSV-writing object above; fix panel order
g_cov <- ggplot(cov, aes(year, pct_observed, colour = panel)) +         # % observed facility-years by year, one line per panel
  geom_line(linewidth = .8) + geom_point(size = 1) +                    # line + point markers
  scale_y_continuous(labels = percent_format(accuracy = 1), limits = c(0, 1)) +  # y-axis as a percentage, fixed 0-100% range
  scale_x_continuous(breaks = seq(2005, 2025, 5)) +                     # x-axis tick marks every 5 years
  labs(title = "Share of facility-years observed, by year",
       subtitle = "observed = obs_source != unobserved; the operating (wayback) channel only exists from 2015",
       x = NULL, y = "% observed", colour = NULL) +
  theme(legend.position = "bottom")
save_fig("coverage_over_time.png", g_cov)

# --- FIG 4: activity over time (mean count per observed facility-year) ----------------------------------
act <- melt(cov, id.vars = c("panel", "year"),                          # reshape coverage_by_year's mean_* columns to long
            measure.vars = c("mean_insp", "mean_viol", "mean_enf"),
            variable.name = "measure", value.name = "mean_count")
act[, measure := c(mean_insp = "Inspections", mean_viol = "Violations",
                   mean_enf = "Enforcement")[as.character(measure)]]    # relabel measure codes to display names
g_act <- ggplot(act, aes(year, mean_count, colour = panel)) +           # mean count per observed facility-year by year, one line per panel
  geom_line(linewidth = .8) +
  facet_wrap(~ measure, scales = "free_y") +                            # one small-multiple per measure, independent y-scales
  scale_x_continuous(breaks = seq(2005, 2025, 5)) +                     # x-axis tick marks every 5 years
  labs(title = "Mean events per observed facility-year, by year",
       x = NULL, y = "mean count", colour = NULL) +
  theme(legend.position = "bottom")
save_fig("activity_over_time.png", g_act, w = 10, h = 4.5)

# --- FIG 5: operating share by year (wayback window) ----------------------------------------------------
op <- cov[year %in% WB_YRS]                                             # restrict to the wayback window (pct_operating is NA outside it anyway)
g_op <- ggplot(op, aes(year, pct_operating, colour = panel)) +          # % operating by year, one line per panel
  geom_line(linewidth = .8) + geom_point(size = 1) +                    # line + point markers
  scale_y_continuous(labels = percent_format(accuracy = 1)) +           # y-axis as a percentage
  scale_x_continuous(breaks = WB_YRS) +                                 # x-axis tick at every wayback year
  labs(title = "Operating share by year (wayback window, 2015-2025)",
       subtitle = "share with op_status in {OPR, TMP, SEA}",
       x = NULL, y = "% operating", colour = NULL) +
  theme(legend.position = "bottom", axis.text.x = element_text(angle = 45, hjust = 1))
save_fig("operating_over_time.png", g_op)

# --- FIG 6: nonzero penalty distribution (universe) -----------------------------------------------------
pen <- P[["universe"]]$penalty_amount; pen <- pen[!is.na(pen) & pen > 0]  # nonzero, non-NA penalties only, universe panel (same filter as summary_penalty above, duplicated rather than reused)
g_pen <- ggplot(data.table(penalty = pen), aes(x = penalty)) +          # histogram of nonzero penalty amounts
  geom_histogram(bins = 40, fill = "#d95f0e", colour = "white", linewidth = .1) +
  scale_x_log10(labels = label_dollar(scale_cut = cut_short_scale())) +  # log10 x-axis, dollar-formatted labels
  annotation_logticks(sides = "b") +                                    # log-tick marks on the bottom axis
  labs(title = "Nonzero facility-year penalties (Universe panel)",
       subtitle = sprintf("n = %s facility-years; max = %s", comma(length(pen)), dollar(max(pen))),  # n and max computed live from `pen`, not hand-entered
       x = "penalty amount (log scale)", y = "facility-years")
save_fig("penalty_dist.png", g_pen)

# --- FIG 7: correlation heatmap among count measures (observed, universe) -------------------------------
cm <- observed(P[["universe"]])[, ..COUNT_COLS]                         # observed subset, universe panel, all n_* count columns (incl. the _dup / _dup_exact indicators, per the CSV2 header note)
cm <- cm[, .SD, .SDcols = sapply(cm, function(c) sd(c, na.rm = TRUE) > 0)]  # drop constant cols
cor_mat <- cor(cm, use = "pairwise.complete.obs")                       # pairwise-complete correlation matrix across the remaining (non-constant) count columns
cor_dt <- as.data.table(as.table(cor_mat)); setnames(cor_dt, c("v1", "v2", "rho"))  # reshape the matrix to a long v1 x v2 x rho table
ord <- rownames(cor_mat)[hclust(as.dist(1 - cor_mat))$order]            # hierarchical-cluster ordering (on 1 - correlation distance) for a more readable heatmap
cor_dt[, `:=`(v1 = factor(v1, levels = ord), v2 = factor(v2, levels = ord))]  # apply the clustered ordering to both axes
g_cor <- ggplot(cor_dt, aes(v1, v2, fill = rho)) +                      # tile heatmap, one tile per variable pair
  geom_tile() +
  scale_fill_gradient2(low = "#2166ac", mid = "white", high = "#b2182b", midpoint = 0, limits = c(-1, 1)) +  # diverging fill, white at rho = 0
  labs(title = "Correlation among count measures (Universe, observed facility-years)", x = NULL, y = NULL) +
  theme_minimal(base_size = 8) +
  theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = .5), panel.grid = element_blank())  # rotate x labels to fit, drop gridlines
save_fig("count_correlations.png", g_cor, w = 10, h = 9)

cat(sprintf("wrote CSV tabulations to %s\n", OUT_CSV))                  # console summary of what was written
cat(sprintf("wrote PNG figures to %s\n", OUT_FIG))                      # console summary of what was written

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# 1. (observed(), ~line 57) `obs_source != "unobserved"` silently drops any row where obs_source itself is
#    NA (NA != "unobserved" is NA, treated as FALSE by data.table's row filter). Every downstream use of
#    observed() (CSV2, CSV3b, key_long, FIG1/FIG2) inherits this. obs_source is expected to always be
#    non-NA by construction, but nothing here checks that invariant.
# 2. (summarise_measure(), ~line 83) pct_na / n_na are computed over ALL facility-years (x_all), while n_obs
#    and every five-number-summary stat next to it are computed over the observed, non-NA subset (x). This
#    matches the file header's documented discipline, but the two halves of the same CSV row have different
#    denominators -- a reader could misread pct_na as "% NA within the observed subset" when it's really
#    "% NA (mostly unobserved rows) across all facility-years."
# 3. (summary_penalty, ~line 100) No explicit observed() restriction here (relies on the p>0/!is.na filter
#    and na.rm=TRUE on penalty_amount_dup), unlike summary_duplication (CSV 3b) a few blocks later, which
#    explicitly restricts to observed(P[[nm]]) before summing dup counts for the n_* families. Both
#    conventions are individually documented but differ from each other for what's conceptually the same
#    "duplicate share" computation.
# 4. (freq_cat, ~line 142) The .SD[1L]-per-facility collapse used for AIR_POLLUTANT_CLASS_DESC,
#    op_status_current_desc, facility_type, and EPA_REGION assumes those attributes are time-invariant
#    without verifying it. By construction (00_spine.R) they should be -- a single facility-level snapshot
#    joined to every year -- but this repeats the same unverified-invariant caveat 05_panel_summaries.R
#    flagged for cls_share(). Also, NA values here get their own "NA" frequency row, a different convention
#    from 05_panel_summaries.R's Table 1, which folds NA into an "other/missing" residual bucket instead.
# 5. (wayback_bin(), ~lines 159-166) REAL BUG: grepl("_active$", b) is meant to catch only the wayback
#    prog_*_active columns (plus "operating"), but it also matches "hpv_active" -- which is derived from HPV
#    interval spells over the FULL 2005-2025 panel (03_build_functions.R:139-177), not from wayback, and is
#    NOT in the file header's list of wayback-restricted columns. As a result, binary_prevalence.csv wrongly
#    restricts hpv_active's share_1/pct_na to the 2015-2025 window and mislabels its window as "2015-2025",
#    while the closely related hpv_active_1mo (name doesn't end in "_active") is correctly computed over the
#    full panel -- an unexplained, accidental asymmetry between two sibling flags.
# 6. (coverage_by_year, ~line 181) pct_operating's denominator is ALL facility-years that year (NA dropped
#    via na.rm=TRUE), while mean_insp / mean_viol / mean_enf in the same output row explicitly restrict to
#    the observed subset first. Each choice is defensible on its own terms, but a reader comparing columns
#    within one row of coverage_by_year.csv should know they don't share a common base.
