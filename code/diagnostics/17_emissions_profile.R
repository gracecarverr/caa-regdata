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
suppressPackageStartupMessages({library(data.table); library(ggplot2); library(scales)})
options(scipen = 999)

CLEAN    <- here::here("data/processed")
DATASETS <- here::here("data/datasets")
OUT      <- here::here("output/emissions_profile")
OUT_FIG  <- here::here("output/figures/datasets/emissions")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
dir.create(OUT_FIG, showWarnings = FALSE, recursive = TRUE)

YEARS <- 2005:2025                                       # same analysis window as the dataset layer (G1)
POLLUTANT_MAP <- c(VOC = "Volatile organic compounds",              # same exact-match map as 08_emissions.R
                   PM10 = "Primary PM10 (filterables and condensibles)",
                   PM25 = "Primary PM2.5 (filterables and condensibles)",
                   NOX = "Nitrogen oxides", SO2 = "Sulfur dioxide", CO  = "Carbon monoxide")

# =========================================================================================================
# PART A -- row-level source (data/processed/emissions.csv.gz), FULL cross-program extract, 2005-2025 window
# =========================================================================================================
raw <- fread(file.path(CLEAN, "emissions.csv.gz"), colClasses = c(REGISTRY_ID = "character"))
raw <- raw[REPORTING_YEAR %in% YEARS]                     # matches the layer's window convention (G1)

# ---- CSV 1: overview ----------------------------------------------------------------------------------------
overview_raw <- data.table(n_rows = nrow(raw), n_distinct_registry = uniqueN(raw$REGISTRY_ID),
                           year_min = min(raw$REPORTING_YEAR), year_max = max(raw$REPORTING_YEAR))
fwrite(overview_raw, file.path(OUT, "overview_raw.csv"))

# ---- CSV 2: coverage by program x year -- the triennial EIS cycle + 2015 TRI/GHG/CAMD start -----------------
by_program_year <- dcast(raw[, .N, by = .(PGM_SYS_ACRNM, REPORTING_YEAR)],
                         REPORTING_YEAR ~ PGM_SYS_ACRNM, value.var = "N", fill = 0)[order(REPORTING_YEAR)]
fwrite(by_program_year, file.path(OUT, "coverage_by_program_year.csv"))

# ---- CSV 3: pollutant totals, raw-file-wide (exact POLLUTANT_NAME match, before the ICIS-match restriction) -
pollutant_totals_raw <- rbindlist(lapply(names(POLLUTANT_MAP), function(nm) {
  v <- raw[POLLUTANT_NAME == POLLUTANT_MAP[[nm]], ANNUAL_EMISSION]
  data.table(pollutant = nm, n_rows = length(v), n_nonzero = sum(v > 0, na.rm = TRUE),
            total_lbs = sum(v, na.rm = TRUE), median_nonzero = median(v[v > 0], na.rm = TRUE),
            max = max(v, na.rm = TRUE))
}))
fwrite(pollutant_totals_raw, file.path(OUT, "pollutant_totals_raw.csv"))

hap_v <- raw[NEI_TYPE == "HAP", ANNUAL_EMISSION]
hap_total_raw <- data.table(n_rows = length(hap_v), n_distinct_hap_names = uniqueN(raw[NEI_TYPE == "HAP", POLLUTANT_NAME]),
                            total_lbs = sum(hap_v, na.rm = TRUE))
fwrite(hap_total_raw, file.path(OUT, "hap_total_raw.csv"))

ghg_v <- raw[PGM_SYS_ACRNM == "E-GGRT", ANNUAL_EMISSION]
ghg_total_raw <- data.table(n_rows = length(ghg_v), n_distinct_registry = uniqueN(raw[PGM_SYS_ACRNM == "E-GGRT", REGISTRY_ID]),
                           total_mtco2e = sum(ghg_v, na.rm = TRUE))
fwrite(ghg_total_raw, file.path(OUT, "ghg_total_raw.csv"))

# ---- CSV 4: double-counting check -- exact-match vs naive substring-match totals (validates EM4) ------------
dc_check <- rbindlist(list(
  data.table(pollutant = "PM10", exact_total = raw[POLLUTANT_NAME == POLLUTANT_MAP[["PM10"]], sum(ANNUAL_EMISSION, na.rm = TRUE)],
            naive_total = raw[grepl("PM10", POLLUTANT_NAME, ignore.case = TRUE), sum(ANNUAL_EMISSION, na.rm = TRUE)]),
  data.table(pollutant = "PM2.5", exact_total = raw[POLLUTANT_NAME == POLLUTANT_MAP[["PM25"]], sum(ANNUAL_EMISSION, na.rm = TRUE)],
            naive_total = raw[grepl("PM2.5|PMFINE", POLLUTANT_NAME, ignore.case = TRUE), sum(ANNUAL_EMISSION, na.rm = TRUE)])))
dc_check[, inflation_factor := round(naive_total / exact_total, 2)]
fwrite(dc_check, file.path(OUT, "double_count_check.csv"))

# ---- CSV 5: ICIS-match coverage (EM1-EM3) ---------------------------------------------------------------------
fac <- fread(file.path(CLEAN, "facilities.csv.gz"), select = c("PGM_SYS_ID", "REGISTRY_ID"), colClasses = "character")
fac_nonblank <- fac[REGISTRY_ID != ""]
emis_reg <- unique(raw$REGISTRY_ID)
match_facility_rows <- fac_nonblank[REGISTRY_ID %chin% emis_reg]
dup_reg <- fac_nonblank[, .N, by = REGISTRY_ID][N > 1]
icis_match_coverage <- data.table(
  n_distinct_registry_emissions = length(emis_reg),
  n_distinct_registry_facilities = uniqueN(fac_nonblank$REGISTRY_ID),
  n_registry_matched = uniqueN(match_facility_rows$REGISTRY_ID),
  n_facility_rows_matched = nrow(match_facility_rows), n_facility_rows_total = nrow(fac),
  n_shared_registry_ids = nrow(dup_reg), max_multiplicity = max(dup_reg$N),
  n_shared_registry_with_emissions_data = sum(dup_reg$REGISTRY_ID %chin% emis_reg))
icis_match_coverage[, `:=`(pct_registry_matched = round(n_registry_matched / n_distinct_registry_emissions, 4),
                          pct_facility_rows_matched = round(n_facility_rows_matched / n_facility_rows_total, 4))]
fwrite(icis_match_coverage, file.path(OUT, "icis_match_coverage.csv"))

# =========================================================================================================
# PART B -- emissions (dataset 7, facility x year, 5,863,431 rows)
# =========================================================================================================
em <- fread(file.path(DATASETS, "emissions.csv.gz"))

# ---- CSV 6: overview + observed/NA breakdown, both flags independently --------------------------------------
overview_ds <- data.table(n_facility_years = nrow(em), n_facilities = uniqueN(em$PGM_SYS_ID),
                          n_observed = sum(em$EMISSIONS_OBSERVED == 1), n_ever_observed_facilities = uniqueN(em[EMISSIONS_OBSERVED == 1, PGM_SYS_ID]),
                          n_ghg_observed = sum(em$GHG_OBSERVED == 1), n_ever_ghg_observed_facilities = uniqueN(em[GHG_OBSERVED == 1, PGM_SYS_ID]))
overview_ds[, `:=`(pct_observed = round(n_observed / n_facility_years, 4), pct_ghg_observed = round(n_ghg_observed / n_facility_years, 4))]
fwrite(overview_ds, file.path(OUT, "overview_dataset.csv"))

# ---- CSV 7: pollutant totals + observed facility-years, by year (built dataset, ICIS-matched universe) ------
obs <- em[EMISSIONS_OBSERVED == 1]
by_year_ds <- obs[, .(n_obs = .N, voc_lbs = sum(VOC_LBS), pm10_lbs = sum(PM10_LBS), pm25_lbs = sum(PM25_LBS),
                      nox_lbs = sum(NOX_LBS), so2_lbs = sum(SO2_LBS), co_lbs = sum(CO_LBS),
                      hap_lbs = sum(HAP_LBS)), by = YEAR][order(YEAR)]
ghg_by_year <- em[GHG_OBSERVED == 1, .(n_ghg_obs = .N, ghg_mtco2e = sum(GHG_MTCO2E)), by = YEAR][order(YEAR)]
by_year_ds <- merge(by_year_ds, ghg_by_year, by = "YEAR", all = TRUE)
fwrite(by_year_ds, file.path(OUT, "by_year_summary.csv"))

# ---- CSV 8: shared-REGISTRY_ID fan-out summary (EM2) --------------------------------------------------------
shared_summary <- data.table(
  n_facility_years_shared = sum(em$IS_SHARED_REGISTRY == 1, na.rm = TRUE),
  n_facilities_shared = uniqueN(em[IS_SHARED_REGISTRY == 1, PGM_SYS_ID]),
  max_n_sharing = max(em$N_PGM_SYS_ID_SHARING_REGISTRY, na.rm = TRUE))
fwrite(shared_summary, file.path(OUT, "shared_registry_summary.csv"))

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

# ---- FIGURE 1: row coverage by program x year -- the triennial EIS cycle + 2015 TRI/GHG/CAMD start ----------
prog_long <- melt(by_program_year, id.vars = "REPORTING_YEAR", variable.name = "program", value.name = "n_rows")
prog_lbl <- prog_long[REPORTING_YEAR == max(REPORTING_YEAR)]
fig1 <- ggplot(prog_long, aes(REPORTING_YEAR, n_rows, color = program)) +
  geom_line(linewidth = 0.9) + geom_point(size = 1.4) +
  scale_color_manual(values = c(EIS = PAL[["violet"]], TRIS = PAL[["blue"]], `E-GGRT` = PAL[["aqua"]], CAMDBS = PAL[["yellow"]])) +
  scale_x_continuous(breaks = seq(min(prog_long$REPORTING_YEAR), max(prog_long$REPORTING_YEAR), 4), expand = expansion(mult = c(0.02, 0.12))) +
  scale_y_continuous(labels = label_comma()) +
  geom_text(data = prog_lbl, aes(label = program), hjust = 0, nudge_x = 0.3, size = 3.1, fontface = "bold") +
  labs(title = "Emissions rows by reporting program and year",
       subtitle = "EIS (NEI) reports only on its triennial inventory cycle (2008/2011/2014/2017/2020); TRIS/CAMDBS/E-GGRT report annually, but only from 2015 on",
       x = NULL, y = "Rows", caption = "Source: data/processed/emissions.csv.gz.") +
  theme_journal
save_fig("emissions_coverage_by_program_year.png", fig1)

# ---- FIGURE 2: pollutant totals (raw-file-wide, exact match) -- relative magnitudes --------------------------
pt <- copy(pollutant_totals_raw)[order(-total_lbs)]
pt[, pollutant := factor(pollutant, levels = pollutant)]
fig2 <- ggplot(pt, aes(pollutant, total_lbs / 1e9)) +
  geom_col(fill = PAL[["blue"]], width = 0.7) +
  scale_y_continuous(labels = label_comma()) +
  labs(title = "Total reported emissions by pollutant, 2005-2025 (raw-file-wide, exact-match)",
       subtitle = "Billions of pounds; VOC/PM10/PM2.5/NOx/SO2/CO only (HAP and GHG use different scales/units)",
       x = NULL, y = "Billions of lbs", caption = "Source: data/processed/emissions.csv.gz.") +
  theme_journal
save_fig("emissions_pollutant_totals.png", fig2)

# ---- FIGURE 3: GHG (E-GGRT) reported emissions over time, ICIS-matched universe ------------------------------
fig3 <- ggplot(ghg_by_year, aes(YEAR, ghg_mtco2e / 1e6)) +
  geom_line(color = PAL[["aqua"]], linewidth = 0.9) + geom_point(color = PAL[["aqua"]], size = 1.4) +
  scale_x_continuous(breaks = seq(min(ghg_by_year$YEAR), max(ghg_by_year$YEAR), 2)) +
  scale_y_continuous(labels = label_comma()) +
  labs(title = "Reported GHG emissions over time (dataset 7, ICIS-matched facilities)",
       subtitle = "Millions of metric tons CO2e; E-GGRT reports annually but only from 2015 on",
       x = NULL, y = "Million MTCO2e", caption = "Source: data/datasets/emissions.csv.gz (dataset 7).") +
  theme_journal
save_fig("emissions_ghg_over_time.png", fig3)

# ---- console summary -----------------------------------------------------------------------------------------
cat("data/processed/emissions.csv.gz + data/datasets/emissions.csv.gz -- profile summary\n")
cat("==========================================================================\n\n")
cat("PART A -- row-level source (full cross-program extract), 2005-2025\n")
print(as.data.frame(overview_raw), row.names = FALSE)
cat("\nCOVERAGE BY PROGRAM x YEAR\n"); print(as.data.frame(by_program_year), row.names = FALSE)
cat("\nPOLLUTANT TOTALS (raw-file-wide, exact match)\n"); print(as.data.frame(pollutant_totals_raw), row.names = FALSE)
cat("\nHAP TOTAL (raw-file-wide)\n"); print(as.data.frame(hap_total_raw), row.names = FALSE)
cat("\nGHG TOTAL (raw-file-wide)\n"); print(as.data.frame(ghg_total_raw), row.names = FALSE)
cat("\nDOUBLE-COUNT CHECK (validates EM4)\n"); print(as.data.frame(dc_check), row.names = FALSE)
cat("\nICIS-MATCH COVERAGE\n"); print(as.data.frame(icis_match_coverage), row.names = FALSE)

cat("\n\nPART B -- emissions (facility x year, dataset 7)\n")
print(as.data.frame(overview_ds), row.names = FALSE)
cat("\nSHARED-REGISTRY FAN-OUT\n"); print(as.data.frame(shared_summary), row.names = FALSE)
cat("\nBY-YEAR SUMMARY (head)\n"); print(as.data.frame(head(by_year_ds, 10)), row.names = FALSE)
