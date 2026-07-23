# =========================================================================================================
# code/diagnostics/15_coordinates_profile.R -- exploratory profiling of dataset 4 (data/datasets/coordinates.csv.gz).
#   Purpose: characterize the coordinates dataset for a reader picking the project up cold -- coverage,
#   coordinate-vs-ICIS-county error, ICIS_COUNTY_FIPS (name-derived FIPS) coverage/agreement, facility
#   geography. Companion to 11_/12_/13_/14_profile.R (same discipline, different dataset).
#
#   in : data/datasets/coordinates.csv.gz
#   out: output/coordinates_profile/*.csv
#        output/figures/datasets/coordinates/coord_{facility_map,county_dist_distribution,coverage_funnel}.png
#
#   DISCIPLINE: HAS_COORDINATE gates everything downstream -- COUNTY_FIPS and the error diagnostics are NA
#   whenever a facility has no coordinate, and COORD_GROSS_ERROR is NA (not 0) whenever the coordinate isn't
#   checkable against an ICIS-claimed county (0 != NA is honored throughout). No numbers are hand-entered;
#   every cell/figure is computed here. Hand-run (not part of RUN_ALL.R). No stochastic step.
#
#   FIGURE DESIGN: same print-ready convention as 13_regulatory_profile.R (dataviz skill, validated
#   categorical palette, direct end-of-line labels in place of a legend, 300dpi).
# =========================================================================================================
suppressPackageStartupMessages({library(data.table); library(ggplot2); library(scales)})
options(scipen = 999)

DATASETS <- here::here("data/datasets")
OUT      <- here::here("output/coordinates_profile")
OUT_FIG  <- here::here("output/figures/datasets/coordinates")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
dir.create(OUT_FIG, showWarnings = FALSE, recursive = TRUE)

# ID/FIPS-like columns that can carry a leading zero -- fread guesses these as numeric by default and
# silently drops the leading zero (e.g. "01001" -> 1001) unless forced to character. Confirmed: without
# this, ICIS_COUNTY_FIPS/COUNTY_FIPS read back as integer (e.g. "01001" -> 1001).
co <- fread(file.path(DATASETS, "coordinates.csv.gz"),
           colClasses = list(character = c("REGISTRY_ID", "ICIS_COUNTY_FIPS", "COUNTY_FIPS")))

fwrite_rounded <- function(dt, file, prop_cols = NULL, num_cols = NULL) {
  d <- copy(dt)
  for (cc in intersect(prop_cols, names(d))) d[, (cc) := round(get(cc), 3)]
  for (cc in intersect(num_cols,  names(d))) d[, (cc) := round(get(cc), 2)]
  fwrite(d, file)
}

# =========================================================================================================
# CSV 1 -- coverage funnel
# =========================================================================================================
funnel <- data.table(
  n_facilities         = nrow(co),
  n_has_coordinate     = sum(co$HAS_COORDINATE),
  n_county_fips_set    = sum(!is.na(co$COUNTY_FIPS)),
  n_checkable_vs_icis  = sum(!is.na(co$COORD_COUNTY_DIST_KM)),
  n_gross_error        = sum(co$COORD_GROSS_ERROR, na.rm = TRUE))
fwrite(funnel, file.path(OUT, "coverage_funnel.csv"))

# =========================================================================================================
# CSV 2 -- coord_county_dist_km five-number summary (checkable facilities only)
# =========================================================================================================
dist_km <- co[!is.na(COORD_COUNTY_DIST_KM), COORD_COUNTY_DIST_KM]
dist_summary <- data.table(n_checkable = length(dist_km), pct_zero = round(mean(dist_km == 0), 4),
                           median = median(dist_km), p90 = quantile(dist_km, .90), p99 = quantile(dist_km, .99),
                           max = max(dist_km), pct_gross_error = round(mean(dist_km > 5), 4))
fwrite(dist_summary, file.path(OUT, "coord_county_dist_summary.csv"))

# =========================================================================================================
# CSV 3 -- coverage by state
# =========================================================================================================
by_state <- co[STATE != "", .(n_facilities = .N, pct_has_coordinate = round(mean(HAS_COORDINATE), 3),
                              pct_gross_error = round(mean(COORD_GROSS_ERROR, na.rm = TRUE), 3)), by = STATE][order(-n_facilities)]
fwrite(by_state, file.path(OUT, "coverage_by_state.csv"))

# =========================================================================================================
# CSV 4 -- ICIS_COUNTY_FIPS coverage + agreement with COUNTY_FIPS (name-derived vs coordinate-derived FIPS)
# =========================================================================================================
both <- !is.na(co$ICIS_COUNTY_FIPS) & !is.na(co$COUNTY_FIPS)
icis_fips_summary <- data.table(
  n_facilities        = nrow(co),
  n_icis_fips_set     = sum(!is.na(co$ICIS_COUNTY_FIPS)),
  n_county_fips_set   = sum(!is.na(co$COUNTY_FIPS)),
  n_icis_only         = sum(!is.na(co$ICIS_COUNTY_FIPS) & is.na(co$COUNTY_FIPS)),
  n_both_set          = sum(both),
  n_agree             = sum(co$ICIS_COUNTY_FIPS[both] == co$COUNTY_FIPS[both]),
  pct_agree           = round(mean(co$ICIS_COUNTY_FIPS[both] == co$COUNTY_FIPS[both]), 4))
fwrite(icis_fips_summary, file.path(OUT, "icis_county_fips_summary.csv"))

# =========================================================================================================
# FIGURES -- print-ready (300dpi), validated categorical palette
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

# ---- FIGURE 1: facility location map, contiguous US (99.5% of coordinates fall in this bbox; AK/HI/PR/
#   territories excluded from the PLOT only, not from the underlying data -- noted in the caption) ----------
conus <- co[!is.na(LATITUDE) & !is.na(LONGITUDE) &
           LATITUDE > 24 & LATITUDE < 50 & LONGITUDE > -125 & LONGITUDE < -66]
fig1 <- ggplot(conus, aes(LONGITUDE, LATITUDE)) +
  geom_point(color = PAL[["blue"]], size = 0.15, alpha = 0.15) +
  coord_quickmap() +
  labs(title = "ICIS-Air facility locations (contiguous US)",
       subtitle = sprintf("n = %s facilities with a coordinate falling in the contiguous-US bounding box (of %s total with any coordinate)",
                          format(nrow(conus), big.mark = ","), format(sum(co$HAS_COORDINATE), big.mark = ",")),
       x = NULL, y = NULL,
       caption = "Source: data/datasets/coordinates.csv.gz (dataset 4). AK/HI/PR/territories excluded from this plot, not from the data.") +
  theme_journal +
  theme(axis.text = element_blank(), panel.grid.major = element_blank())
save_fig("coord_facility_map.png", fig1, w = 9, h = 5.5)

# ---- FIGURE 2: coordinate-vs-ICIS-county distance distribution (checkable facilities, truncated at p99) ----
p99 <- quantile(dist_km, .99)
# filter to the plotted range BEFORE computing bins -- computing a fixed bin COUNT over the full unfiltered
# range (max 2,317km) while only viewing 0-p99km via coord_cartesian put ~all mass in a single giant bin
# (verified: rendered as one solid block, not a histogram). Use a fixed binwidth on pre-filtered data instead.
dd <- data.table(dist = dist_km[dist_km > 0 & dist_km <= p99])
fig2 <- ggplot(dd, aes(dist)) +
  geom_histogram(binwidth = p99 / 60, fill = PAL[["blue"]], color = "white", linewidth = 0.1, boundary = 0) +
  geom_vline(xintercept = 5, color = PAL[["red"]], linewidth = 0.6, linetype = "dashed") +
  annotate("text", x = 5, y = Inf, label = "  5km gross-error threshold", color = PAL[["red"]],
           hjust = 0, vjust = 1.5, size = 3.1, fontface = "bold") +
  scale_x_continuous(labels = label_comma()) + scale_y_continuous(labels = label_comma()) +
  labs(title = "Coordinate-to-ICIS-county distance (nonzero, checkable facilities)",
       subtitle = sprintf("n = %s facilities with dist > 0 (of %s checkable, %s land exactly in the ICIS-claimed county);\nx-axis truncated at the 99th percentile (%.0f km); %.1f%% exceed the 5km gross-error threshold",
                          format(sum(dist_km > 0), big.mark = ","), format(length(dist_km), big.mark = ","),
                          format(sum(dist_km == 0), big.mark = ","), p99, 100 * dist_summary$pct_gross_error),
       x = "Distance (km)", y = "Facilities", caption = "Source: data/datasets/coordinates.csv.gz (dataset 4).") +
  theme_journal + theme(plot.subtitle = element_text(color = INK_SECONDARY, size = 8.3, lineheight = 1.15))
save_fig("coord_county_dist_distribution.png", fig2)

# ---- FIGURE 3: coverage funnel (facility count at each successive data-quality gate) ------------------------
funnel_long <- data.table(
  stage = factor(c("All facilities", "Has coordinate", "County FIPS set", "Checkable vs ICIS county", "Gross error (>5km)"),
                levels = c("All facilities", "Has coordinate", "County FIPS set", "Checkable vs ICIS county", "Gross error (>5km)")),
  n = c(funnel$n_facilities, funnel$n_has_coordinate, funnel$n_county_fips_set, funnel$n_checkable_vs_icis, funnel$n_gross_error))
fig3 <- ggplot(funnel_long, aes(stage, n)) +
  geom_col(fill = PAL[["blue"]], width = 0.7) +
  geom_text(aes(label = format(n, big.mark = ",")), vjust = -0.5, size = 3.2, color = INK) +
  scale_y_continuous(labels = label_comma(), expand = expansion(mult = c(0, 0.12))) +
  labs(title = "Coordinate data-quality funnel",
       subtitle = "Facility count at each successive gate -- \"Gross error\" is a subset of \"Checkable\", not an additional filter",
       x = NULL, y = "Facilities", caption = "Source: data/datasets/coordinates.csv.gz (dataset 4).") +
  theme_journal + theme(axis.text.x = element_text(size = 8.5))
save_fig("coord_coverage_funnel.png", fig3, w = 8.5, h = 4.8)

# ---- console summary ---------------------------------------------------------------------------------------
cat("data/datasets/coordinates.csv.gz -- profile summary\n")
cat("=======================================================\n\n")
print(as.data.frame(funnel), row.names = FALSE)
cat(sprintf("\nhas_coordinate: %.1f%% | gross error (of checkable): %.1f%%\n",
            100 * mean(co$HAS_COORDINATE), 100 * dist_summary$pct_gross_error))
cat("\nCOORD_COUNTY_DIST_KM SUMMARY (checkable)\n"); print(as.data.frame(dist_summary), row.names = FALSE)
cat("\nICIS_COUNTY_FIPS SUMMARY (name-derived vs coordinate-derived FIPS)\n")
print(as.data.frame(icis_fips_summary), row.names = FALSE)
cat("\nTOP 10 STATES BY FACILITY COUNT\n"); print(as.data.frame(head(by_state, 10)), row.names = FALSE)
cat(sprintf("\n3 figures written to %s\n", OUT_FIG))
