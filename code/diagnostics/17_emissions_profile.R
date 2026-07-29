# =========================================================================================================
# code/diagnostics/17_emissions_profile.R -- exploratory profiling of dataset 7 (emissions.csv.gz, facility x
#   year) and its row-level source (data/processed/emissions.csv.gz, the full cross-program extract). Purpose:
#   characterize both for a reader picking the project up cold. Companion to 11-16_*_profile.R (same
#   discipline, different datasets).
#
#   in : data/processed/emissions.csv.gz, data/processed/facilities.csv.gz, data/datasets/emissions.csv.gz
#   out: output/emissions_profile/*.csv
#        output/figures/datasets/emissions/emissions_{coverage_by_program_year,pollutant_totals,
#        ghg_over_time}.png
#
#   DISCIPLINE: emissions.csv.gz (dataset 7) mirrors ds 0's zero-vs-NA gate (EM6) -- EMISSIONS_OBSERVED and
#   GHG_OBSERVED are independent flags, NA is unknown, never a false 0. The row-level source (Part A) profiles
#   the FULL cross-program extract (not restricted to the ICIS-matched universe) to show what coverage looks
#   like before the EM3 restriction costs 80% of it. No numbers are hand-entered; every cell is computed here.
#   Hand-run (not part of RUN_ALL.R). No stochastic step.
#
#   FIGURE DESIGN: same print-ready convention as 13-16_*_profile.R (dataviz skill, validated categorical
#   palette, direct end-of-line labels in place of a legend, 300dpi).
# =========================================================================================================
suppressPackageStartupMessages({library(data.table); library(ggplot2); library(scales)})  # load quietly, no startup banners
options(scipen = 999)                                     # disable scientific notation in printed/cat numbers below

CLEAN    <- here::here("data/processed")                  # Part A source dir -- full cross-program extract lives here
DATASETS <- here::here("data/datasets")                   # Part B source dir -- the built, ICIS-matched dataset 7 lives here
OUT      <- here::here("output/emissions_profile")        # destination for this script's CSVs
OUT_FIG  <- here::here("output/figures/datasets/emissions")  # destination for this script's figures
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)   # create OUT if missing; silent if it already exists
dir.create(OUT_FIG, showWarnings = FALSE, recursive = TRUE)  # same for the figures dir

YEARS <- 2005:2025                                       # same analysis window as the dataset layer (G1)
POLLUTANT_MAP <- c(VOC = "Volatile organic compounds",              # same exact-match map as 08_emissions.R
                   PM10 = "Primary PM10 (filterables and condensibles)",
                   PM25 = "Primary PM2.5 (filterables and condensibles)",
                   NOX = "Nitrogen oxides", SO2 = "Sulfur dioxide", CO  = "Carbon monoxide")
# note: only these 6 criteria pollutants get exact-name totals below -- HAP (NEI_TYPE == "HAP") and GHG
# (PGM_SYS_ACRNM == "E-GGRT") are handled separately in their own units (lbs vs. lbs vs. metric tons CO2e);
# they are never summed together with this map's pollutants or with each other (see fig 2 subtitle below).

# =========================================================================================================
# PART A -- row-level source (data/processed/emissions.csv.gz), FULL cross-program extract, 2005-2025 window
# =========================================================================================================
raw <- fread(file.path(CLEAN, "emissions.csv.gz"), colClasses = c(REGISTRY_ID = "character"))  # force REGISTRY_ID to character (avoid leading-zero loss)
raw <- raw[REPORTING_YEAR %in% YEARS]                     # matches the layer's window convention (G1)
# FLAG: `raw` is the unrestricted, full cross-program extract for the rest of Part A (correct, per the
# header's intent to show pre-EM3-restriction coverage) -- everything below through icis_match_coverage
# (line ~96) reads from `raw`, not from the ICIS-matched dataset. Part B (line ~101 on) switches to `em`,
# the built dataset 7. Keep these two straight when reading output: Part A numbers are NOT what ends up in
# dataset 7, by design.

# ---- CSV 1: overview ----------------------------------------------------------------------------------------
overview_raw <- data.table(n_rows = nrow(raw), n_distinct_registry = uniqueN(raw$REGISTRY_ID),  # row count + distinct facility registry IDs, full extract
                           year_min = min(raw$REPORTING_YEAR), year_max = max(raw$REPORTING_YEAR))  # confirms the YEARS window took effect
fwrite(overview_raw, file.path(OUT, "overview_raw.csv"))  # write CSV 1

# ---- CSV 2: coverage by program x year -- the triennial EIS cycle + 2015 TRI/GHG/CAMD start -----------------
by_program_year <- dcast(raw[, .N, by = .(PGM_SYS_ACRNM, REPORTING_YEAR)],  # count raw ROWS per program per year (one row can be one pollutant record, not one facility-year)
                         REPORTING_YEAR ~ PGM_SYS_ACRNM, value.var = "N", fill = 0)[order(REPORTING_YEAR)]  # pivot wide (one column per program), fill 0 for program-years with no rows, sort by year
fwrite(by_program_year, file.path(OUT, "coverage_by_program_year.csv"))  # write CSV 2
# FLAG: these are raw ROW counts, not facility or facility-year counts -- a single facility-year can
# contribute many rows (one per pollutant/measure reported that year), so this table should not be read as
# a coverage RATE or as "number of facilities reporting." Figure 1 below labels its y-axis "Rows" for this
# reason; the denominator concern flagged in the task brief (facility-years vs. rows) is resolved correctly
# here, but only because the label says "Rows" -- don't repurpose this table for a facility-year coverage claim.

# ---- CSV 3: pollutant totals, raw-file-wide (exact POLLUTANT_NAME match, before the ICIS-match restriction) -
# NOTE: total_lbs sums ANNUAL_EMISSION across every row matching POLLUTANT_NAME regardless of PGM_SYS_ACRNM --
# i.e. across ALL reporting programs pooled together (EIS/TRIS/E-GGRT/CAMDBS). If the same physical emission
# event is reported by a facility under more than one program in the same year, this sum double-counts it.
# n_multiprogram_fac_years below reports the size of this population directly (confirmed 2026-07-28: ~0.5% of
# NOX/SO2 facility-years, 0% of VOC/PM10/PM25/CO) -- the dc_check below (CSV 4) validates a DIFFERENT risk
# (exact vs. naive substring name-matching) and does not catch this cross-program case.
pollutant_totals_raw <- rbindlist(lapply(names(POLLUTANT_MAP), function(nm) {  # one row per pollutant in POLLUTANT_MAP
  sub <- raw[POLLUTANT_NAME == POLLUTANT_MAP[[nm]]]        # exact-match rows for this pollutant, ALL programs pooled
  v <- sub$ANNUAL_EMISSION
  n_multi <- sub[, uniqueN(PGM_SYS_ACRNM), by = .(REGISTRY_ID, REPORTING_YEAR)][V1 > 1, .N]  # facility-years reported under >1 program -- the population double-counted by total_lbs below
  data.table(pollutant = nm, n_rows = length(v), n_positive = sum(v > 0, na.rm = TRUE),  # n_positive counts strictly-positive values (renamed from n_nonzero -- see NOTE below)
            total_lbs = sum(v, na.rm = TRUE), median_positive = median(v[v > 0], na.rm = TRUE),  # total_lbs sums ALL values incl. negatives; median_positive excludes them
            max = max(v, na.rm = TRUE), n_multiprogram_fac_years = n_multi)
}))
fwrite(pollutant_totals_raw, file.path(OUT, "pollutant_totals_raw.csv"))  # write CSV 3
# NOTE: n_positive/median_positive use `v > 0` (strictly positive) -- a negative ANNUAL_EMISSION value (EPA
# correction/revision rows do occur) is excluded from both, but its negative value is still included in
# total_lbs via sum(v, na.rm = TRUE). Renamed from n_nonzero/median_nonzero (2026-07-28) since "nonzero"
# previously implied `!= 0`, not `> 0` -- the columns always meant "positive" in practice.

hap_v <- raw[NEI_TYPE == "HAP", ANNUAL_EMISSION]           # all HAP-flagged rows, all programs pooled, raw-file-wide
n_hap_multi <- raw[NEI_TYPE == "HAP", uniqueN(PGM_SYS_ACRNM), by = .(REGISTRY_ID, REPORTING_YEAR)][V1 > 1, .N]  # same cross-program overlap check as pollutant_totals_raw above
hap_total_raw <- data.table(n_rows = length(hap_v), n_distinct_hap_names = uniqueN(raw[NEI_TYPE == "HAP", POLLUTANT_NAME]),  # count of rows + distinct HAP pollutant names
                            total_lbs = sum(hap_v, na.rm = TRUE), n_multiprogram_fac_years = n_hap_multi)  # summed lbs; n_multiprogram_fac_years reports the cross-program double-counting risk directly
fwrite(hap_total_raw, file.path(OUT, "hap_total_raw.csv"))  # write CSV 4 (HAP total); n_multiprogram_fac_years reports the same cross-program overlap risk as pollutant_totals_raw above, directly rather than only in a comment

ghg_v <- raw[PGM_SYS_ACRNM == "E-GGRT", ANNUAL_EMISSION]   # GHG rows restricted to the single program that reports them (E-GGRT) -- no cross-program pooling risk here
ghg_total_raw <- data.table(n_rows = length(ghg_v), n_distinct_registry = uniqueN(raw[PGM_SYS_ACRNM == "E-GGRT", REGISTRY_ID]),  # row count + distinct facilities reporting GHG
                           total_mtco2e = sum(ghg_v, na.rm = TRUE))  # summed metric tons CO2e -- a different unit from the lbs totals above, never combined with them
fwrite(ghg_total_raw, file.path(OUT, "ghg_total_raw.csv"))  # write CSV 5 (GHG total)

# ---- CSV 4: double-counting check -- exact-match vs naive substring-match totals (validates EM4) ------------
dc_check <- rbindlist(list(                                # this checks name-matching double-counting, NOT the cross-program pooling flagged above
  data.table(pollutant = "PM10", exact_total = raw[POLLUTANT_NAME == POLLUTANT_MAP[["PM10"]], sum(ANNUAL_EMISSION, na.rm = TRUE)],  # total using the exact POLLUTANT_NAME string
            naive_total = raw[grepl("PM10", POLLUTANT_NAME, ignore.case = TRUE), sum(ANNUAL_EMISSION, na.rm = TRUE)]),  # total using a naive substring match (would sweep in other PM10-named variants)
  data.table(pollutant = "PM2.5", exact_total = raw[POLLUTANT_NAME == POLLUTANT_MAP[["PM25"]], sum(ANNUAL_EMISSION, na.rm = TRUE)],  # same, exact PM2.5 name
            naive_total = raw[grepl("PM2.5|PMFINE", POLLUTANT_NAME, ignore.case = TRUE), sum(ANNUAL_EMISSION, na.rm = TRUE)])))  # naive match on PM2.5 or PMFINE substrings
dc_check[, inflation_factor := round(naive_total / exact_total, 2)]  # how many times larger the naive (over-matching) total is vs. the exact-match total actually used elsewhere
fwrite(dc_check, file.path(OUT, "double_count_check.csv"))  # write CSV 6
# FLAG: this table exists to justify the exact-match convention used everywhere else in this script (and in
# 08_emissions.R) -- inflation_factor > 1 confirms that a naive substring match would inflate the pollutant
# total by pulling in additional POLLUTANT_NAME variants that are not the same measure. It does not test or
# rule out the cross-program duplication flagged at pollutant_totals_raw/hap_total_raw above.

# ---- CSV 5: ICIS-match coverage (EM1-EM3) ---------------------------------------------------------------------
fac <- fread(file.path(CLEAN, "facilities.csv.gz"), select = c("PGM_SYS_ID", "REGISTRY_ID"), colClasses = "character")  # facility crosswalk, PGM_SYS_ID<->REGISTRY_ID
fac_nonblank <- fac[REGISTRY_ID != ""]                    # drop facility rows with no REGISTRY_ID (can't be matched to emissions data at all)
emis_reg <- unique(raw$REGISTRY_ID)                       # distinct REGISTRY_IDs present in the raw (unrestricted) emissions extract
match_facility_rows <- fac_nonblank[REGISTRY_ID %chin% emis_reg]  # facility rows whose REGISTRY_ID also appears in the raw emissions extract
dup_reg <- fac_nonblank[, .N, by = REGISTRY_ID][N > 1]    # REGISTRY_IDs shared by more than one PGM_SYS_ID (fan-out candidates, cf. EM2/IS_SHARED_REGISTRY in dataset 7)
icis_match_coverage <- data.table(
  n_distinct_registry_emissions = length(emis_reg),        # distinct REGISTRY_IDs in the raw extract (Part A universe)
  n_distinct_registry_facilities = uniqueN(fac_nonblank$REGISTRY_ID),  # distinct REGISTRY_IDs in the facility crosswalk
  n_registry_matched = uniqueN(match_facility_rows$REGISTRY_ID),  # of the emissions REGISTRY_IDs, how many resolve to at least one ICIS facility record
  n_facility_rows_matched = nrow(match_facility_rows), n_facility_rows_total = nrow(fac),  # facility-row-level (not REGISTRY_ID-level) match counts
  n_shared_registry_ids = nrow(dup_reg), max_multiplicity = max(dup_reg$N),  # how many REGISTRY_IDs map to >1 PGM_SYS_ID, and the worst fan-out
  n_shared_registry_with_emissions_data = sum(dup_reg$REGISTRY_ID %chin% emis_reg))  # of those shared REGISTRY_IDs, how many actually have emissions rows
icis_match_coverage[, `:=`(pct_registry_matched = round(n_registry_matched / n_distinct_registry_emissions, 4),  # THE headline "coverage before EM3 restriction" number
                          pct_facility_rows_matched = round(n_facility_rows_matched / n_facility_rows_total, 4))]
fwrite(icis_match_coverage, file.path(OUT, "icis_match_coverage.csv"))  # write CSV 7
# FLAG: pct_registry_matched is the number behind the header's claim that "the EM3 restriction costs 80% of
# it" -- it is the share of distinct REGISTRY_IDs in the raw, unrestricted extract that resolve to any
# facility record in the ICIS crosswalk. (1 - pct_registry_matched) is the fraction of raw-extract
# REGISTRY_IDs that never make it into dataset 7 at all. This is the single number that ties Part A's
# unrestricted coverage picture to Part B's much smaller ICIS-matched universe -- read it before interpreting
# any Part B stat as representative of "all emissions reporters."

# =========================================================================================================
# PART B -- emissions (dataset 7, facility x year, 5,863,431 rows)
# =========================================================================================================
em <- fread(file.path(DATASETS, "emissions.csv.gz"))       # switch source: the BUILT, ICIS-matched dataset 7 (not the raw extract used throughout Part A)

# ---- CSV 6: overview + observed/NA breakdown, both flags independently --------------------------------------
overview_ds <- data.table(n_facility_years = nrow(em), n_facilities = uniqueN(em$PGM_SYS_ID),  # dataset 7 grain is already facility x year
                          n_observed = sum(em$EMISSIONS_OBSERVED == 1), n_ever_observed_facilities = uniqueN(em[EMISSIONS_OBSERVED == 1, PGM_SYS_ID]),  # gated on EMISSIONS_OBSERVED only
                          n_ghg_observed = sum(em$GHG_OBSERVED == 1), n_ever_ghg_observed_facilities = uniqueN(em[GHG_OBSERVED == 1, PGM_SYS_ID]))  # gated on GHG_OBSERVED only -- kept independent of the line above, per DISCIPLINE
overview_ds[, `:=`(pct_observed = round(n_observed / n_facility_years, 4), pct_ghg_observed = round(n_ghg_observed / n_facility_years, 4))]  # both shares use the same denominator (n_facility_years), just different numerators
fwrite(overview_ds, file.path(OUT, "overview_dataset.csv"))  # write CSV 8

# ---- CSV 7: pollutant totals + observed facility-years, by year (built dataset, ICIS-matched universe) ------
obs <- em[EMISSIONS_OBSERVED == 1]                        # criteria-pollutant/HAP subset -- gated on EMISSIONS_OBSERVED, not GHG_OBSERVED
by_year_ds <- obs[, .(n_obs = .N, voc_lbs = sum(VOC_LBS), pm10_lbs = sum(PM10_LBS), pm25_lbs = sum(PM25_LBS),  # sums computed only over EMISSIONS_OBSERVED == 1 rows
                      nox_lbs = sum(NOX_LBS), so2_lbs = sum(SO2_LBS), co_lbs = sum(CO_LBS),
                      hap_lbs = sum(HAP_LBS)), by = YEAR][order(YEAR)]
ghg_by_year <- em[GHG_OBSERVED == 1, .(n_ghg_obs = .N, ghg_mtco2e = sum(GHG_MTCO2E)), by = YEAR][order(YEAR)]  # separately gated on GHG_OBSERVED -- correct, independent flag per DISCIPLINE
by_year_ds <- merge(by_year_ds, ghg_by_year, by = "YEAR", all = TRUE)  # outer join on YEAR; combines two DIFFERENT observed subsets into one row per year
fwrite(by_year_ds, file.path(OUT, "by_year_summary.csv"))  # write CSV 9
# FLAG: by_year_ds merges two blocks built on two different gating flags -- n_obs/*_lbs come from the
# EMISSIONS_OBSERVED == 1 subset, while n_ghg_obs/ghg_mtco2e come from the GHG_OBSERVED == 1 subset. A given
# year's row can have a large n_obs and a small (or NA, pre-2015) n_ghg_obs, or vice versa -- the two count
# columns are not the same denominator and should not be read as describing the same set of facility-years.
# all = TRUE means a year present in one subset but absent from the other gets NA in the missing columns
# rather than being silently dropped, which is the correct behavior here but worth knowing when reading NAs
# in the output CSV.

# ---- CSV 8: shared-REGISTRY_ID fan-out summary (EM2) --------------------------------------------------------
shared_summary <- data.table(
  n_facility_years_shared = sum(em$IS_SHARED_REGISTRY == 1, na.rm = TRUE),  # facility-years whose REGISTRY_ID maps to more than one PGM_SYS_ID
  n_facilities_shared = uniqueN(em[IS_SHARED_REGISTRY == 1, PGM_SYS_ID]),  # distinct facilities ever flagged as sharing a REGISTRY_ID
  max_n_sharing = max(em$N_PGM_SYS_ID_SHARING_REGISTRY, na.rm = TRUE))  # worst-case fan-out width in dataset 7
fwrite(shared_summary, file.path(OUT, "shared_registry_summary.csv"))  # write CSV 10

# =========================================================================================================
# FIGURES -- print-ready (300dpi), validated categorical palette, direct end-of-line labels
# =========================================================================================================
PAL <- c(blue = "#2a78d6", aqua = "#1baf7a", yellow = "#eda100", green = "#008300", violet = "#4a3aa7", red = "#e34948")  # validated categorical palette (dataviz skill)
INK <- "#0b0b0b"; INK_SECONDARY <- "#52514e"; GRID <- "#e1e0d9"; AXIS <- "#c3c2b7"  # text/gridline/axis colors, shared across figures
theme_journal <- theme_minimal(base_size = 11) +           # base theme: minimal, 11pt
  theme(panel.grid.minor = element_blank(), panel.grid.major = element_line(color = GRID, linewidth = 0.3),  # drop minor gridlines, thin muted major gridlines
        axis.line = element_line(color = AXIS, linewidth = 0.3), axis.ticks = element_line(color = AXIS, linewidth = 0.3),  # thin muted axis lines/ticks
        text = element_text(color = INK), axis.text = element_text(color = INK_SECONDARY),  # primary ink for text, secondary for axis labels
        plot.title = element_text(face = "bold", size = 12), plot.subtitle = element_text(color = INK_SECONDARY, size = 9.5),  # title/subtitle styling
        plot.caption = element_text(color = INK_SECONDARY, size = 8, hjust = 0), legend.position = "none")  # left-aligned caption, no legend (direct labels used instead)
save_fig <- function(name, plot, w = 7.5, h = 4.5) ggsave(file.path(OUT_FIG, name), plot, width = w, height = h, dpi = 300)  # 300dpi print-ready export helper

# ---- FIGURE 1: row coverage by program x year -- the triennial EIS cycle + 2015 TRI/GHG/CAMD start ----------
prog_long <- melt(by_program_year, id.vars = "REPORTING_YEAR", variable.name = "program", value.name = "n_rows")  # wide-to-long for one line per program
prog_lbl <- prog_long[REPORTING_YEAR == max(REPORTING_YEAR)]  # last-year values, used to place direct end-of-line labels
fig1 <- ggplot(prog_long, aes(REPORTING_YEAR, n_rows, color = program)) +  # x = year, y = row count, one color per program
  geom_line(linewidth = 0.9) + geom_point(size = 1.4) +    # line + point markers per program-year
  scale_color_manual(values = c(EIS = PAL[["violet"]], TRIS = PAL[["blue"]], `E-GGRT` = PAL[["aqua"]], CAMDBS = PAL[["yellow"]])) +  # fixed program->color mapping
  scale_x_continuous(breaks = seq(min(prog_long$REPORTING_YEAR), max(prog_long$REPORTING_YEAR), 4), expand = expansion(mult = c(0.02, 0.12))) +  # year axis breaks every 4 years, extra right margin for labels
  scale_y_continuous(labels = label_comma()) +              # comma-formatted row counts on y axis
  geom_text(data = prog_lbl, aes(label = program), hjust = 0, nudge_x = 0.3, size = 3.1, fontface = "bold") +  # direct end-of-line program labels instead of a legend
  labs(title = "Emissions rows by reporting program and year",
       subtitle = "EIS (NEI) reports only on its triennial inventory cycle (2008/2011/2014/2017/2020); TRIS/CAMDBS/E-GGRT report annually, but only from 2015 on",
       x = NULL, y = "Rows", caption = "Source: data/processed/emissions.csv.gz.") +  # explicit "Rows" y-label -- see FLAG at by_program_year above
  theme_journal
save_fig("emissions_coverage_by_program_year.png", fig1)   # write figure 1

# ---- FIGURE 2: pollutant totals (raw-file-wide, exact match) -- relative magnitudes --------------------------
pt <- copy(pollutant_totals_raw)[order(-total_lbs)]        # copy to avoid mutating pollutant_totals_raw; sort descending by total
pt[, pollutant := factor(pollutant, levels = pollutant)]   # lock factor level order to the sorted order (so bars plot in that order, not alphabetical)
fig2 <- ggplot(pt, aes(pollutant, total_lbs / 1e9)) +       # y axis rescaled to billions of lbs
  geom_col(fill = PAL[["blue"]], width = 0.7) +             # single-color bar chart (one series, no color mapping needed)
  scale_y_continuous(labels = label_comma()) +              # comma-formatted axis labels
  labs(title = "Total reported emissions by pollutant, 2005-2025 (raw-file-wide, exact-match)",
       subtitle = "Billions of pounds; VOC/PM10/PM2.5/NOx/SO2/CO only (HAP and GHG use different scales/units)",  # explicit unit-consistency note -- HAP/GHG deliberately excluded from this comparison
       x = NULL, y = "Billions of lbs", caption = "Source: data/processed/emissions.csv.gz.") +  # raw-file-wide source, per the cross-program pooling FLAG above
  theme_journal
save_fig("emissions_pollutant_totals.png", fig2)           # write figure 2

# ---- FIGURE 3: GHG (E-GGRT) reported emissions over time, ICIS-matched universe ------------------------------
fig3 <- ggplot(ghg_by_year, aes(YEAR, ghg_mtco2e / 1e6)) +  # y axis rescaled to millions of metric tons CO2e; source is Part B's ghg_by_year (dataset 7, GHG_OBSERVED == 1)
  geom_line(color = PAL[["aqua"]], linewidth = 0.9) + geom_point(color = PAL[["aqua"]], size = 1.4) +  # single-series line + points
  scale_x_continuous(breaks = seq(min(ghg_by_year$YEAR), max(ghg_by_year$YEAR), 2)) +  # year axis breaks every 2 years
  scale_y_continuous(labels = label_comma()) +              # comma-formatted axis labels
  labs(title = "Reported GHG emissions over time (dataset 7, ICIS-matched facilities)",
       subtitle = "Millions of metric tons CO2e; E-GGRT reports annually but only from 2015 on",
       x = NULL, y = "Million MTCO2e", caption = "Source: data/datasets/emissions.csv.gz (dataset 7).") +  # correctly cites dataset 7, not the raw extract
  theme_journal
save_fig("emissions_ghg_over_time.png", fig3)               # write figure 3

# ---- console summary -----------------------------------------------------------------------------------------
cat("data/processed/emissions.csv.gz + data/datasets/emissions.csv.gz -- profile summary\n")
cat("==========================================================================\n\n")
cat("PART A -- row-level source (full cross-program extract), 2005-2025\n")
print(as.data.frame(overview_raw), row.names = FALSE)      # CSV 1 to console
cat("\nCOVERAGE BY PROGRAM x YEAR\n"); print(as.data.frame(by_program_year), row.names = FALSE)  # CSV 2 to console
cat("\nPOLLUTANT TOTALS (raw-file-wide, exact match)\n"); print(as.data.frame(pollutant_totals_raw), row.names = FALSE)  # CSV 3 to console
cat("\nHAP TOTAL (raw-file-wide)\n"); print(as.data.frame(hap_total_raw), row.names = FALSE)  # CSV 4 to console
cat("\nGHG TOTAL (raw-file-wide)\n"); print(as.data.frame(ghg_total_raw), row.names = FALSE)  # CSV 5 to console
cat("\nDOUBLE-COUNT CHECK (validates EM4)\n"); print(as.data.frame(dc_check), row.names = FALSE)  # CSV 6 to console
cat("\nICIS-MATCH COVERAGE\n"); print(as.data.frame(icis_match_coverage), row.names = FALSE)  # CSV 7 to console

cat("\n\nPART B -- emissions (facility x year, dataset 7)\n")
print(as.data.frame(overview_ds), row.names = FALSE)       # CSV 8 to console
cat("\nSHARED-REGISTRY FAN-OUT\n"); print(as.data.frame(shared_summary), row.names = FALSE)  # CSV 10 to console
cat("\nBY-YEAR SUMMARY (head)\n"); print(as.data.frame(head(by_year_ds, 10)), row.names = FALSE)  # CSV 9 (first 10 rows) to console

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# 1.  (~line 42)  raw/em source split: confirmed correct -- Part A (through icis_match_coverage) reads the
#     unrestricted, full cross-program extract (`raw`); Part B (line ~101 on) switches to `em`, the built
#     ICIS-matched dataset 7. No accidental cross-use found, but flagged as the load-bearing check per the
#     task brief since a swap here would make the "80% coverage cost" comparison meaningless.
# 2.  (~line 51)  by_program_year / coverage_by_program_year.csv counts raw ROWS per program-year, not
#     facilities or facility-years -- correctly labeled "Rows" in figure 1, but easy to misread as a
#     facility-year coverage rate if reused elsewhere.
# 3.  RESOLVED 2026-07-28: pollutant_totals_raw now includes n_multiprogram_fac_years, an explicit count of
#     facility-years reported under >1 PGM_SYS_ACRNM for that pollutant -- confirmed ~0.5% of NOX/SO2
#     facility-years, 0% of VOC/PM10/PM25/CO. total_lbs itself is unchanged (still pools all programs, by
#     design for this raw-file-wide comparison table); the new column surfaces the double-counting risk
#     with a real number instead of leaving it as an unquantified caveat.
# 4.  RESOLVED 2026-07-28: renamed n_nonzero/median_nonzero to n_positive/median_positive -- the columns
#     always meant "positive" (`v > 0`) in practice, not "!= 0"; total_lbs still sums negative correction
#     values via na.rm = TRUE, unchanged.
# 5.  RESOLVED 2026-07-28: hap_total_raw now includes the same n_multiprogram_fac_years diagnostic as item 3.
# 6.  (~line 87)  dc_check / inflation_factor: clarifies that this table validates exact-vs-naive
#     POLLUTANT_NAME matching (EM4), a different double-counting risk from the cross-program pooling in
#     items 3 and 5 -- don't read a clean dc_check as clearing the cross-program risk too.
# 7.  (~line 96)  icis_match_coverage / pct_registry_matched: this is the specific number behind the
#     header's "EM3 restriction costs 80%" claim -- the share of distinct REGISTRY_IDs in the raw extract
#     that resolve to any ICIS facility record. (1 - pct_registry_matched) is what never makes it into
#     dataset 7.
# 8.  (~line 117) by_year_ds: merges a EMISSIONS_OBSERVED-gated block (n_obs, *_lbs) with a
#     GHG_OBSERVED-gated block (n_ghg_obs, ghg_mtco2e) via an outer join on YEAR -- the two count columns
#     describe different facility-year subsets and should not be treated as sharing a denominator; NAs from
#     the outer join reflect a year missing from one subset, not a data error.
