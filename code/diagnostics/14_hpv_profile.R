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
suppressPackageStartupMessages({library(data.table); library(ggplot2); library(scales)})
options(scipen = 999)

DATASETS <- here::here("data/datasets")
OUT      <- here::here("output/hpv_profile")
OUT_FIG  <- here::here("output/figures/datasets/hpv")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
dir.create(OUT_FIG, showWarnings = FALSE, recursive = TRUE)

sp <- fread(file.path(DATASETS, "hpv_spells.csv.gz"))
ha <- fread(file.path(DATASETS, "hpv_active.csv.gz"))

fwrite_rounded <- function(dt, file, prop_cols = NULL, num_cols = NULL) {
  d <- copy(dt)
  for (cc in intersect(prop_cols, names(d))) d[, (cc) := round(get(cc), 3)]
  for (cc in intersect(num_cols,  names(d))) d[, (cc) := round(get(cc), 2)]
  fwrite(d, file)
}

# =========================================================================================================
# PART A -- hpv_spells (dataset 2, spell-level)
# =========================================================================================================

# ---- CSV 1: overview + spell_status breakdown ------------------------------------------------------------
overview_spells <- data.table(
  n_spells = nrow(sp), n_facilities = uniqueN(sp$PGM_SYS_ID),
  dayzero_year_min = min(sp$DAYZERO_YEAR, na.rm = TRUE), dayzero_year_max = max(sp$DAYZERO_YEAR, na.rm = TRUE))
fwrite(overview_spells, file.path(OUT, "overview_spells.csv"))

status_breakdown <- sp[, .N, by = SPELL_STATUS][order(-N)]
status_breakdown[, pct := round(N / sum(N), 4)]
fwrite(status_breakdown, file.path(OUT, "spell_status_breakdown.csv"))

# ---- CSV 2: spell duration, closed spells only (spell_days is NA otherwise, by construction) --------------
closed_days <- sp[SPELL_STATUS == "closed", SPELL_DAYS]
spell_duration <- data.table(n_closed = length(closed_days), min = min(closed_days), p25 = quantile(closed_days, .25),
                             median = median(closed_days), p75 = quantile(closed_days, .75),
                             p90 = quantile(closed_days, .90), max = max(closed_days), mean = round(mean(closed_days), 1),
                             pct_over_1yr = round(mean(closed_days > 365), 4))
fwrite(spell_duration, file.path(OUT, "spell_duration_closed.csv"))

# ---- CSV 3: spells by day-zero year (time trend; note DAYZERO_YEAR is unscreened here, per H4 -- includes
#   the 218/2026 outliers the collapse layer screens out, see hpv_active section below) --------------------
by_dayzero_year <- sp[!is.na(DAYZERO_YEAR), .N, by = DAYZERO_YEAR][order(DAYZERO_YEAR)]
fwrite(by_dayzero_year, file.path(OUT, "spells_by_dayzero_year.csv"))

# ---- CSV 4: implicated program codes (PROGRAM_CODES is a whitespace-joined multi-value field per record).
#   NB: strsplit() must NOT be called inside `sp[i, j]` (bare, unwrapped in .()) -- data.table tries to
#   rectangularize the resulting ragged list and silently recycles/corrupts it (verified: inflated counts by
#   ~5x, e.g. CAATVP 143,323 vs the correct 25,555). Split on the plain vector instead.
prog_tokens <- strsplit(sp$PROGRAM_CODES[sp$PROGRAM_CODES != ""], "\\s+")
prog_freq <- data.table(program_code = unlist(prog_tokens))[, .N, by = program_code][order(-N)]
prog_freq[, pct_of_spells := round(N / nrow(sp), 4)]
fwrite(prog_freq, file.path(OUT, "program_code_frequency.csv"))

# ---- CSV 5: agency type + state frequency ------------------------------------------------------------------
agency_freq <- sp[, .N, by = AGENCY_TYPE_DESC][order(-N)]
agency_freq[, pct := round(N / sum(N), 4)]
fwrite(agency_freq, file.path(OUT, "agency_type_frequency.csv"))

state_freq <- sp[STATE_CODE != "", .(n_spells = .N, n_facilities = uniqueN(PGM_SYS_ID)), by = STATE_CODE][order(-n_spells)]
fwrite(state_freq, file.path(OUT, "state_frequency.csv"))

# ---- CSV 6: spells per facility (distribution) -- the H2 "not merged" decision means a facility can carry
#   many overlapping/sequential HPV spells; this shows how concentrated that is -----------------------------
spells_per_facility <- sp[, .N, by = PGM_SYS_ID][, .N, by = .(n_spells = N)][order(n_spells)]
fwrite(spells_per_facility, file.path(OUT, "spells_per_facility_distribution.csv"))
multi_spell_share <- sp[, .N, by = PGM_SYS_ID][, mean(N > 1)]

# =========================================================================================================
# PART B -- hpv_active (dataset 2b, facility x year)
# =========================================================================================================

# ---- CSV 7: overview + zero/NA breakdown -------------------------------------------------------------------
overview_active <- data.table(
  n_facility_years = nrow(ha), n_facilities = uniqueN(ha$PGM_SYS_ID),
  n_active   = sum(ha$HPV_ACTIVE == 1, na.rm = TRUE),
  n_inactive = sum(ha$HPV_ACTIVE == 0, na.rm = TRUE),
  n_na       = sum(is.na(ha$HPV_ACTIVE)),
  n_ever_active_facilities = uniqueN(ha[HPV_ACTIVE == 1, PGM_SYS_ID]))
fwrite(overview_active, file.path(OUT, "overview_active.csv"))

# ---- CSV 8: active rate by year (denominator = non-NA only, so the rate isn't diluted by structural NA) ----
by_year_active <- ha[!is.na(HPV_ACTIVE), .(n_known = .N, n_active = sum(HPV_ACTIVE == 1)), by = YEAR][order(YEAR)]
by_year_active[, pct_active := round(n_active / n_known, 4)]
fwrite(by_year_active, file.path(OUT, "active_rate_by_year.csv"))

# ---- CSV 9: "spell wins" cases -- HPV_ACTIVE==1 in a year the facility had NO other ICIS record that year
#   (H6's stated rationale in practice: 2,370 fac-yrs expected per the decision doc) --------------------------
reg_obs <- fread(file.path(DATASETS, "regulatory.csv.gz"), select = c("PGM_SYS_ID", "YEAR", "ICIS_OBSERVED"))
spell_wins <- merge(ha[HPV_ACTIVE == 1], reg_obs, by = c("PGM_SYS_ID", "YEAR"))
spell_wins_summary <- data.table(
  n_active_fac_years = nrow(spell_wins),
  n_active_icis_unobserved = spell_wins[ICIS_OBSERVED == 0, .N],
  pct_active_icis_unobserved = round(spell_wins[ICIS_OBSERVED == 0, .N] / nrow(spell_wins), 4))
fwrite(spell_wins_summary, file.path(OUT, "spell_wins_cases.csv"))

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

# ---- FIGURE 1: HPV-active rate over time, 2005-2025 ------------------------------------------------------
fig1 <- ggplot(by_year_active, aes(YEAR, pct_active)) +
  geom_line(color = PAL[["blue"]], linewidth = 0.9) + geom_point(color = PAL[["blue"]], size = 1.6) +
  scale_x_continuous(breaks = seq(min(by_year_active$YEAR), max(by_year_active$YEAR), 5)) +
  scale_y_continuous(labels = label_percent(), limits = c(0, NA)) +
  labs(title = "Share of facilities in HPV-active status, 2005-2025",
       subtitle = "Of facility-years with known status (HPV_ACTIVE non-NA); a steady ~4.5x decline, mechanism not\nfully explained by coverage-ramp or right-truncation caveats alone (see hpv_profile.md)",
       x = NULL, y = "Share HPV-active", caption = "Source: data/datasets/hpv_active.csv.gz (dataset 2b).") +
  theme_journal + theme(plot.subtitle = element_text(color = INK_SECONDARY, size = 8.7, lineheight = 1.1))
save_fig("hpv_active_rate_over_time.png", fig1)

# ---- FIGURE 2: closed-spell duration distribution (truncated at p99 for readability; long tail noted) -----
dur <- data.table(days = closed_days)
p99 <- quantile(closed_days, .99)
fig2 <- ggplot(dur, aes(days)) +
  geom_histogram(binwidth = 30, fill = PAL[["blue"]], color = "white", linewidth = 0.15, boundary = 0) +
  coord_cartesian(xlim = c(0, p99)) +
  scale_x_continuous(labels = label_comma()) + scale_y_continuous(labels = label_comma()) +
  labs(title = "HPV spell duration (closed spells)",
       subtitle = sprintf("n = %s closed spells; x-axis truncated at the 99th percentile (%s days); %.1f%% last over a year",
                          format(nrow(dur), big.mark = ","), format(round(p99), big.mark = ","), 100 * spell_duration$pct_over_1yr),
       x = "Days from day-zero to resolved (inclusive)", y = "Spells",
       caption = "Source: data/datasets/hpv_spells.csv.gz (dataset 2).") +
  theme_journal
save_fig("hpv_spell_duration.png", fig2)

# ---- FIGURE 3: program codes implicated (top 8, share of spells) -------------------------------------------
prog_top <- head(prog_freq[order(-N)], 8)
prog_top[, program_code := factor(program_code, levels = program_code)]
fig3 <- ggplot(prog_top, aes(program_code, pct_of_spells)) +
  geom_col(fill = PAL[["blue"]], width = 0.7) +
  scale_y_continuous(labels = label_percent()) +
  labs(title = "Programs implicated in HPV spells (top 8)",
       subtitle = "Share of spells whose PROGRAM_CODES includes this program (multi-value per spell; shares don't sum to 100%)",
       x = NULL, y = "Share of spells", caption = "Source: data/datasets/hpv_spells.csv.gz (dataset 2).") +
  theme_journal
save_fig("hpv_program_frequency.png", fig3)

# ---- console summary ---------------------------------------------------------------------------------------
cat("data/datasets/hpv_spells.csv.gz + hpv_active.csv.gz -- profile summary\n")
cat("==========================================================================\n\n")
cat("PART A -- HPV_SPELLS (spell-level, dataset 2)\n")
cat(sprintf("%s spells | %s facilities | day-zero years %s-%s\n",
            format(overview_spells$n_spells, big.mark=","), format(overview_spells$n_facilities, big.mark=","),
            overview_spells$dayzero_year_min, overview_spells$dayzero_year_max))
cat("\nSPELL_STATUS BREAKDOWN\n"); print(as.data.frame(status_breakdown), row.names = FALSE)
cat("\nSPELL DURATION (closed spells, days, inclusive)\n"); print(as.data.frame(spell_duration), row.names = FALSE)
cat(sprintf("\nSHARE OF FACILITIES WITH >1 SPELL: %.1f%%\n", 100 * multi_spell_share))
cat("\nTOP PROGRAM CODES IMPLICATED\n"); print(as.data.frame(head(prog_freq, 10)), row.names = FALSE)
cat("\nAGENCY TYPE FREQUENCY\n"); print(as.data.frame(agency_freq), row.names = FALSE)

cat("\n\nPART B -- HPV_ACTIVE (facility x year, dataset 2b)\n")
print(as.data.frame(overview_active), row.names = FALSE)
cat("\nACTIVE RATE BY YEAR (of known/non-NA)\n"); print(as.data.frame(by_year_active), row.names = FALSE)
cat("\nSPELL-WINS CASES (active in a year with no other ICIS record)\n")
print(as.data.frame(spell_wins_summary), row.names = FALSE)
