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
#   are 2015-2025 only; attainment (pm25_*, any_naa) is electric-only and 2016-2025. penalty_amount codes
#   0/none as NA -> summarized over nonzero only. No numbers are hand-entered; every cell is computed here.
#   Hand-run (not part of RUN_ALL.R). No stochastic step.
# =========================================================================================================
suppressPackageStartupMessages({
  library(data.table); library(ggplot2); library(scales)
})
options(scipen = 999)  # write full-digit numbers in the CSVs, not scientific notation

PANELS  <- here::here("data/panels")
OUT_CSV <- here::here("output/panel_profile")
OUT_FIG <- here::here("output/figures")
dir.create(OUT_CSV, showWarnings = FALSE, recursive = TRUE)
dir.create(OUT_FIG, showWarnings = FALSE, recursive = TRUE)

YEARS  <- 2005:2025
WB_YRS <- 2015:2025                                    # wayback window (operating status available)
NAMES  <- c(electric = "Electric", major_synmin = "Major/SynMin", universe = "Universe")
read_panel <- function(nm) fread(file.path(PANELS, paste0(nm, ".csv.gz")))
P <- lapply(names(NAMES), read_panel); names(P) <- names(NAMES)

# write a CSV with human-readable rounding: proportions/shares to 3 decimals, money/means to 2. Rounds a
# COPY so in-memory tables keep full precision for the figures. Blank cells are NA (e.g. pct_operating
# pre-2015, where wayback status does not exist) -- left as NA on purpose, never coerced to 0.
fwrite_rounded <- function(dt, file, prop_cols = NULL, num_cols = NULL) {
  d <- copy(dt)
  for (cc in intersect(prop_cols, names(d))) d[, (cc) := round(get(cc), 3)]
  for (cc in intersect(num_cols,  names(d))) d[, (cc) := round(get(cc), 2)]
  fwrite(d, file)
}

# count measures (the n_* block) + the key subset used in figures. NB grep("^n_") now also picks up the
# duplicate-load indicators n_*_dup / n_*_dup_exact, so they get five-number summaries in summary_counts.csv
# automatically; summary_duplication.csv (below) adds the dup *shares* per family.
COUNT_COLS <- grep("^n_", names(P[["universe"]]), value = TRUE)           # 45 measures (incl. _dup / _dup_exact)
KEY_MEAS   <- c(n_inspections = "Inspections", n_violations = "Violations", n_hpv = "HPV",
                n_enforcement = "Enforcement", n_certs = "Certifications", n_stack_tests = "Stack tests")
theme_set(theme_minimal(base_size = 11))
save_fig <- function(name, plot, w = 9, h = 6)
  ggsave(file.path(OUT_FIG, name), plot, width = w, height = h, dpi = 150)

# observed subset: the only rows where a 0 count is a real 0 (not a structural NA)
observed <- function(d) d[obs_source != "unobserved"]

# =========================================================================================================
# CSV 1 -- panel overview
# =========================================================================================================
overview <- rbindlist(lapply(names(P), function(nm) {
  d <- P[[nm]]
  data.table(
    panel            = NAMES[nm],
    n_facilities     = uniqueN(d$PGM_SYS_ID),
    n_facility_years = nrow(d),
    year_min         = min(d$year), year_max = max(d$year),
    balanced         = nrow(d) == uniqueN(d$PGM_SYS_ID) * length(YEARS),
    share_event      = mean(d$obs_source == "event"),
    share_operating  = mean(d$obs_source == "operating"),
    share_unobserved = mean(d$obs_source == "unobserved"))
}))
fwrite_rounded(overview, file.path(OUT_CSV, "panel_overview.csv"),
               prop_cols = c("share_event", "share_operating", "share_unobserved"))

# =========================================================================================================
# CSV 2 -- five-number summaries (+ mean/sd, %zero, NA accounting) for every count measure, observed subset
# =========================================================================================================
summarise_measure <- function(d_all, m) {
  x_all <- d_all[[m]]
  x     <- observed(d_all)[[m]]                        # summarise over observed facility-years only
  x     <- x[!is.na(x)]
  data.table(
    n_obs = length(x), n_na = sum(is.na(x_all)), pct_na = mean(is.na(x_all)),
    min = min(x), p25 = quantile(x, .25), median = median(x), p75 = quantile(x, .75), max = max(x),
    mean = mean(x), sd = sd(x), pct_zero = mean(x == 0), pct_nonzero = mean(x > 0))
}
summary_counts <- rbindlist(lapply(names(P), function(nm)
  rbindlist(lapply(COUNT_COLS, function(m)
    cbind(panel = NAMES[nm], measure = m, summarise_measure(P[[nm]], m))))))
fwrite_rounded(summary_counts, file.path(OUT_CSV, "summary_counts.csv"),
               prop_cols = c("pct_na", "pct_zero", "pct_nonzero"), num_cols = c("mean", "sd"))

# =========================================================================================================
# CSV 3 -- penalty_amount: nonzero five-number summary + total (per panel). total now sums ALL formal rows;
#   dup_total / dup_share report the share of penalty dollars carried by event-key duplicate rows.
# =========================================================================================================
summary_penalty <- rbindlist(lapply(names(P), function(nm) {
  p <- P[[nm]]$penalty_amount; p <- p[!is.na(p) & p > 0]
  total     <- sum(p)
  dup_total <- sum(P[[nm]]$penalty_amount_dup, na.rm = TRUE)
  data.table(panel = NAMES[nm], n_nonzero = length(p),
             min = min(p), p25 = quantile(p, .25), median = median(p), p75 = quantile(p, .75),
             max = max(p), mean = mean(p), total = total,
             dup_total = dup_total, dup_share = if (total > 0) dup_total / total else NA_real_)
}))
fwrite_rounded(summary_penalty, file.path(OUT_CSV, "summary_penalty.csv"),
               num_cols = c("mean", "total", "dup_total"), prop_cols = "dup_share")

# =========================================================================================================
# CSV 3b -- duplicate load: how much of each family's (all-row) count is duplicate. dup = event-key repeats,
#   dup_exact = byte-identical. Shares are Sum(dup) / Sum(count) over OBSERVED facility-years. Only the
#   families that carry duplicates have indicators; violations/stacktests have none by construction.
# =========================================================================================================
DUP_FAMILIES <- c(inspections = "n_inspections", enforcement = "n_enforcement",
                  formal = "n_formal", informal = "n_informal", certs = "n_certs")
summary_duplication <- rbindlist(lapply(names(P), function(nm) {
  d <- observed(P[[nm]])
  rbindlist(lapply(names(DUP_FAMILIES), function(fam) {
    base <- DUP_FAMILIES[[fam]]
    tot  <- sum(d[[base]], na.rm = TRUE)
    dup  <- sum(d[[paste0(base, "_dup")]],       na.rm = TRUE)
    dex  <- sum(d[[paste0(base, "_dup_exact")]], na.rm = TRUE)
    data.table(panel = NAMES[nm], family = fam, n_rows = tot, n_dup = dup, n_dup_exact = dex,
               dup_share = if (tot > 0) dup / tot else NA_real_,
               dup_exact_share = if (tot > 0) dex / tot else NA_real_)
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
  d <- P[[nm]]
  # frequencies are over facilities (time-invariant attributes), except obs_source which is per row
  rbindlist(lapply(CAT_VARS, function(v) {
    base <- if (v == "obs_source") d else d[, .SD[1L], by = PGM_SYS_ID]
    tb <- base[, .N, by = c(v)][order(-N)]
    setnames(tb, v, "level")
    tb[, `:=`(panel = NAMES[nm], variable = v, level = as.character(level), pct = N / sum(N))]
    tb[, .(panel, variable, level, n = N, pct)]
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
BIN_COLS <- intersect(BIN_COLS, names(P[["universe"]]))
wayback_bin <- function(b) b == "operating" || grepl("_active$", b)
binary_prevalence <- rbindlist(lapply(names(P), function(nm) {
  d <- P[[nm]]
  rbindlist(lapply(BIN_COLS, function(b) {
    dd <- if (wayback_bin(b)) d[year %in% WB_YRS] else d          # respect the wayback window
    x <- dd[[b]]
    data.table(panel = NAMES[nm], flag = b, window = if (wayback_bin(b)) "2015-2025" else "2005-2025",
               n = length(x), share_1 = mean(x == 1, na.rm = TRUE), pct_na = mean(is.na(x)))
  }))
}))
fwrite_rounded(binary_prevalence, file.path(OUT_CSV, "binary_prevalence.csv"),
               prop_cols = c("share_1", "pct_na"))

# =========================================================================================================
# CSV 6 -- coverage by year (per panel x year)
# =========================================================================================================
coverage_by_year <- rbindlist(lapply(names(P), function(nm) {
  d <- P[[nm]]
  d[, .(
    panel          = NAMES[nm],
    n_facilities   = uniqueN(PGM_SYS_ID),
    pct_observed   = mean(obs_source != "unobserved"),
    pct_operating  = if (.BY$year %in% WB_YRS) mean(operating == 1, na.rm = TRUE) else NA_real_,
    mean_insp      = mean(n_inspections[obs_source != "unobserved"], na.rm = TRUE),
    mean_viol      = mean(n_violations[obs_source != "unobserved"], na.rm = TRUE),
    mean_enf       = mean(n_enforcement[obs_source != "unobserved"], na.rm = TRUE)
  ), by = year][order(year)]
}))
fwrite_rounded(coverage_by_year, file.path(OUT_CSV, "coverage_by_year.csv"),
               prop_cols = c("pct_observed", "pct_operating"),
               num_cols = c("mean_insp", "mean_viol", "mean_enf"))

# =========================================================================================================
# CSV 7 -- facilities & facility-years by state
# =========================================================================================================
state_counts <- rbindlist(lapply(names(P), function(nm) {
  d <- P[[nm]]
  d[!is.na(STATE) & STATE != "", .(panel = NAMES[nm],
     n_facilities = uniqueN(PGM_SYS_ID), n_facility_years = .N), by = STATE][order(-n_facilities)]
}))
fwrite(state_counts, file.path(OUT_CSV, "state_counts.csv"))

# =========================================================================================================
# CSV 8 -- electric-only PM2.5 nonattainment exposure (2016-2025)
# =========================================================================================================
e <- P[["electric"]]
if ("any_naa" %in% names(e)) {
  areas <- e[!is.na(pm25_area) & pm25_area != "", .N, by = pm25_area][order(-N)]
  electric_attainment <- rbindlist(list(
    data.table(item = "facilities_ever_nonattainment",   value = as.character(e[any_naa == 1, uniqueN(PGM_SYS_ID)])),
    data.table(item = "share_electric_facilities",        value = sprintf("%.3f", e[any_naa == 1, uniqueN(PGM_SYS_ID)] / uniqueN(e$PGM_SYS_ID))),
    data.table(item = "facility_years_nonattainment",     value = as.character(sum(e$any_naa == 1, na.rm = TRUE))),
    data.table(item = "facility_years_attainment",        value = as.character(sum(e$any_naa == 0, na.rm = TRUE))),
    data.table(item = "facility_years_na",                value = as.character(sum(is.na(e$any_naa)))),
    rbindlist(lapply(seq_len(nrow(areas)), function(i)
      data.table(item = paste0("area:", areas$pm25_area[i]), value = as.character(areas$N[i]))))
  ))
  fwrite(electric_attainment, file.path(OUT_CSV, "electric_attainment.csv"))
}

# =========================================================================================================
# FIGURES
# =========================================================================================================
# long table of KEY_MEAS over observed facility-years, tagged by panel (reused by several figures)
key_long <- rbindlist(lapply(names(P), function(nm) {
  d <- observed(P[[nm]])
  melt(d[, c("year", names(KEY_MEAS)), with = FALSE], id.vars = "year",
       variable.name = "measure", value.name = "count")[!is.na(count)][, panel := NAMES[nm]]
}))
key_long[, measure := factor(KEY_MEAS[as.character(measure)], levels = unname(KEY_MEAS))]
key_long[, panel := factor(panel, levels = unname(NAMES))]

# --- FIG 1: per-panel distribution small-multiples (log1p x) --------------------------------------------
for (nm in names(P)) {
  g <- ggplot(key_long[panel == NAMES[nm]], aes(x = count)) +
    geom_histogram(bins = 30, fill = "#2c7fb8", colour = "white", linewidth = .1) +
    scale_x_continuous(trans = "log1p", breaks = c(0, 1, 3, 10, 30, 100, 300)) +
    scale_y_continuous(labels = label_number(scale_cut = cut_short_scale())) +
    facet_wrap(~ measure, scales = "free_y") +
    labs(title = paste0(NAMES[nm], " panel: distribution of key measures (observed facility-years)"),
         subtitle = "x on log1p scale; observed = obs_source in {event, operating}",
         x = "count in a facility-year", y = "facility-years")
  save_fig(paste0("dist_counts_", nm, ".png"), g)
}

# --- FIG 2: ECDF of key measures, three panels overlaid -------------------------------------------------
g_ecdf <- ggplot(key_long, aes(x = count, colour = panel)) +
  stat_ecdf(linewidth = .7) +
  scale_x_continuous(trans = "log1p", breaks = c(0, 1, 3, 10, 30, 100)) +
  facet_wrap(~ measure, scales = "free_x") +
  labs(title = "ECDF of key measures by panel (observed facility-years)",
       x = "count in a facility-year (log1p)", y = "cumulative share", colour = NULL) +
  theme(legend.position = "bottom")
save_fig("ecdf_key_measures.png", g_ecdf)

# --- FIG 3: coverage over time --------------------------------------------------------------------------
cov <- copy(coverage_by_year)[, panel := factor(panel, levels = unname(NAMES))]
g_cov <- ggplot(cov, aes(year, pct_observed, colour = panel)) +
  geom_line(linewidth = .8) + geom_point(size = 1) +
  scale_y_continuous(labels = percent_format(accuracy = 1), limits = c(0, 1)) +
  scale_x_continuous(breaks = seq(2005, 2025, 5)) +
  labs(title = "Share of facility-years observed, by year",
       subtitle = "observed = obs_source != unobserved; the operating (wayback) channel only exists from 2015",
       x = NULL, y = "% observed", colour = NULL) +
  theme(legend.position = "bottom")
save_fig("coverage_over_time.png", g_cov)

# --- FIG 4: activity over time (mean count per observed facility-year) ----------------------------------
act <- melt(cov, id.vars = c("panel", "year"),
            measure.vars = c("mean_insp", "mean_viol", "mean_enf"),
            variable.name = "measure", value.name = "mean_count")
act[, measure := c(mean_insp = "Inspections", mean_viol = "Violations",
                   mean_enf = "Enforcement")[as.character(measure)]]
g_act <- ggplot(act, aes(year, mean_count, colour = panel)) +
  geom_line(linewidth = .8) +
  facet_wrap(~ measure, scales = "free_y") +
  scale_x_continuous(breaks = seq(2005, 2025, 5)) +
  labs(title = "Mean events per observed facility-year, by year",
       x = NULL, y = "mean count", colour = NULL) +
  theme(legend.position = "bottom")
save_fig("activity_over_time.png", g_act, w = 10, h = 4.5)

# --- FIG 5: operating share by year (wayback window) ----------------------------------------------------
op <- cov[year %in% WB_YRS]
g_op <- ggplot(op, aes(year, pct_operating, colour = panel)) +
  geom_line(linewidth = .8) + geom_point(size = 1) +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  scale_x_continuous(breaks = WB_YRS) +
  labs(title = "Operating share by year (wayback window, 2015-2025)",
       subtitle = "share with op_status in {OPR, TMP, SEA}",
       x = NULL, y = "% operating", colour = NULL) +
  theme(legend.position = "bottom", axis.text.x = element_text(angle = 45, hjust = 1))
save_fig("operating_over_time.png", g_op)

# --- FIG 6: nonzero penalty distribution (universe) -----------------------------------------------------
pen <- P[["universe"]]$penalty_amount; pen <- pen[!is.na(pen) & pen > 0]
g_pen <- ggplot(data.table(penalty = pen), aes(x = penalty)) +
  geom_histogram(bins = 40, fill = "#d95f0e", colour = "white", linewidth = .1) +
  scale_x_log10(labels = label_dollar(scale_cut = cut_short_scale())) +
  annotation_logticks(sides = "b") +
  labs(title = "Nonzero facility-year penalties (Universe panel)",
       subtitle = sprintf("n = %s facility-years; max = %s", comma(length(pen)), dollar(max(pen))),
       x = "penalty amount (log scale)", y = "facility-years")
save_fig("penalty_dist.png", g_pen)

# --- FIG 7: correlation heatmap among count measures (observed, universe) -------------------------------
cm <- observed(P[["universe"]])[, ..COUNT_COLS]
cm <- cm[, .SD, .SDcols = sapply(cm, function(c) sd(c, na.rm = TRUE) > 0)]  # drop constant cols
cor_mat <- cor(cm, use = "pairwise.complete.obs")
cor_dt <- as.data.table(as.table(cor_mat)); setnames(cor_dt, c("v1", "v2", "rho"))
ord <- rownames(cor_mat)[hclust(as.dist(1 - cor_mat))$order]
cor_dt[, `:=`(v1 = factor(v1, levels = ord), v2 = factor(v2, levels = ord))]
g_cor <- ggplot(cor_dt, aes(v1, v2, fill = rho)) +
  geom_tile() +
  scale_fill_gradient2(low = "#2166ac", mid = "white", high = "#b2182b", midpoint = 0, limits = c(-1, 1)) +
  labs(title = "Correlation among count measures (Universe, observed facility-years)", x = NULL, y = NULL) +
  theme_minimal(base_size = 8) +
  theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = .5), panel.grid = element_blank())
save_fig("count_correlations.png", g_cor, w = 10, h = 9)

# --- FIG 8: electric PM2.5 nonattainment exposure over time ---------------------------------------------
if ("any_naa" %in% names(e)) {
  naa_yr <- e[!is.na(any_naa), .(share_naa = mean(any_naa == 1),
                                 n_naa = sum(any_naa == 1)), by = year][order(year)]
  g_naa <- ggplot(naa_yr, aes(year, share_naa)) +
    geom_col(fill = "#756bb1") +
    scale_y_continuous(labels = percent_format(accuracy = 1)) +
    scale_x_continuous(breaks = 2016:2025) +
    labs(title = "Electric panel: share of placed facility-years in PM2.5 nonattainment",
         subtitle = "PM2.5 (2012 NAAQS), 2016-2025; denominator excludes NA (uncovered/unplaced)",
         x = NULL, y = "% in nonattainment") +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  save_fig("electric_pm25_exposure.png", g_naa)
}

cat(sprintf("wrote CSV tabulations to %s\n", OUT_CSV))
cat(sprintf("wrote PNG figures to %s\n", OUT_FIG))
