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
suppressPackageStartupMessages({library(data.table); library(ggplot2); library(scales)})  # data.table/ggplot2/scales only; quietly (suppress load-time banners)
options(scipen = 999)                                                 # disable scientific notation in printed/console output

DATASETS <- here::here("data/datasets")                               # source dir for the built datasets layer (input)
OUT      <- here::here("output/coordinates_profile")                  # destination dir for this script's CSV outputs
OUT_FIG  <- here::here("output/figures/datasets/coordinates")         # destination dir for this script's figure outputs
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)               # create OUT if missing; no warning if it already exists
dir.create(OUT_FIG, showWarnings = FALSE, recursive = TRUE)           # create OUT_FIG if missing

# ID/FIPS-like columns that can carry a leading zero -- fread guesses these as numeric by default and
# silently drops the leading zero (e.g. "01001" -> 1001) unless forced to character. Confirmed: without
# this, ICIS_COUNTY_FIPS/COUNTY_FIPS read back as integer (e.g. "01001" -> 1001).
co <- fread(file.path(DATASETS, "coordinates.csv.gz"),                # read the coordinates dataset (one row per PGM_SYS_ID / facility)
           # FLAG: both the name-derived (ICIS_COUNTY_FIPS) and coordinate-derived (COUNTY_FIPS) FIPS columns
           # are forced to character here -- this is exactly what avoids the leading-zero-drop bug flagged in
           # 13_regulatory_profile.R for REGISTRY_ID/ZIP_CODE. The CSV4 agreement check below (line ~78)
           # depends on this: it compares these two columns with string equality, which only means what it
           # looks like it means if both sides are correctly zero-padded GEOID strings, not truncated integers.
           colClasses = list(character = c("REGISTRY_ID", "ICIS_COUNTY_FIPS", "COUNTY_FIPS")))

fwrite_rounded <- function(dt, file, prop_cols = NULL, num_cols = NULL) {  # helper: write a data.table to CSV after rounding proportion/numeric columns for readability
  # FLAG: this helper is defined but never actually called anywhere below in this script -- every CSV write
  # below uses plain fwrite() on a table where rounding (if any) was already done ad hoc with an inline
  # round() at the point of computation. That's inconsistent (some proportions rounded to 3dp, others 4dp,
  # by whatever the author typed at each call site) and, concretely, CSV2's median/p90/p99/max distance
  # values are NOT rounded at all -- see the FLAG at dist_summary below.
  d <- copy(dt)                                                        # work on a copy so the caller's table isn't mutated by reference
  for (cc in intersect(prop_cols, names(d))) d[, (cc) := round(get(cc), 3)]  # round proportion columns to 3 decimals (only those present in `d`)
  for (cc in intersect(num_cols,  names(d))) d[, (cc) := round(get(cc), 2)]  # round other numeric columns to 2 decimals
  fwrite(d, file)                                                      # write the rounded table to disk
}

# =========================================================================================================
# CSV 1 -- coverage funnel
# =========================================================================================================
funnel <- data.table(                                                 # one-row funnel: facility counts at each successive data-quality gate
  n_facilities         = nrow(co),                                    # total facilities in the dataset (denominator for every downstream rate)
  n_has_coordinate     = sum(co$HAS_COORDINATE),                      # facilities with a usable FRS coordinate (0/1 flag, never NA per the build-time invariant in 06_coordinates.R)
  n_county_fips_set    = sum(!is.na(co$COUNTY_FIPS)),                 # facilities where the coordinate's point-in-polygon join resolved to a county (subset of has_coordinate)
  n_checkable_vs_icis  = sum(!is.na(co$COORD_COUNTY_DIST_KM)),        # facilities checkable against the ICIS-claimed county (coordinate present AND ICIS county name resolved)
  n_gross_error        = sum(co$COORD_GROSS_ERROR, na.rm = TRUE))     # FLAG: na.rm=TRUE is required -- COORD_GROSS_ERROR is NA (not 0) for every uncheckable facility, so without na.rm this sum() would return NA rather than a real count; correctly implemented here, honoring the 0-vs-NA convention documented in the file header
fwrite(funnel, file.path(OUT, "coverage_funnel.csv"))                 # write CSV 1 (raw counts, no rounding needed)

# =========================================================================================================
# CSV 2 -- coord_county_dist_km five-number summary (checkable facilities only)
# =========================================================================================================
dist_km <- co[!is.na(COORD_COUNTY_DIST_KM), COORD_COUNTY_DIST_KM]     # restrict to checkable facilities only -- the HAS_COORDINATE gate propagates here via COORD_COUNTY_DIST_KM's own NA pattern
dist_summary <- data.table(n_checkable = length(dist_km), pct_zero = round(mean(dist_km == 0), 4),  # five-number summary computed on the FULL checkable distribution, not the p99-truncated version used later for FIGURE 2's plot
                           median = median(dist_km), p90 = quantile(dist_km, .90), p99 = quantile(dist_km, .99),  # FLAG: median/p90/p99 are NOT rounded (unlike pct_zero/pct_gross_error below) -- written to CSV at full floating-point precision; fwrite_rounded() above was apparently meant to standardize this but is never called
                           max = max(dist_km), pct_gross_error = round(mean(dist_km > 5), 4))  # FLAG: max likewise unrounded; pct_gross_error hardcodes ">5" instead of reading the stored COORD_GROSS_ERROR column (used correctly with na.rm=TRUE elsewhere in this file) or the GROSS_ERROR_KM constant in coord_county_flag.R -- currently guaranteed consistent only by a stopifnot invariant enforced at build time in 06_coordinates.R; would silently drift if that threshold ever changed without a matching edit here (and at the geom_vline/annotate/subtitle "5km" text in FIGURE 2 below)
fwrite(dist_summary, file.path(OUT, "coord_county_dist_summary.csv")) # write CSV 2

# =========================================================================================================
# CSV 3 -- coverage by state
# =========================================================================================================
by_state <- co[STATE != "", .(n_facilities = .N, pct_has_coordinate = round(mean(HAS_COORDINATE), 3),  # drop blank-STATE rows from the denominator; count facilities and coordinate-coverage rate per state
                              pct_gross_error = round(mean(COORD_GROSS_ERROR, na.rm = TRUE), 3)), by = STATE][order(-n_facilities)]  # na.rm=TRUE correctly excludes uncheckable facilities from this state-level gross-error rate rather than letting their NA drag mean() to NA; sorted by facility count descending
fwrite(by_state, file.path(OUT, "coverage_by_state.csv"))             # write CSV 3

# =========================================================================================================
# CSV 4 -- ICIS_COUNTY_FIPS coverage + agreement with COUNTY_FIPS (name-derived vs coordinate-derived FIPS)
# =========================================================================================================
both <- !is.na(co$ICIS_COUNTY_FIPS) & !is.na(co$COUNTY_FIPS)          # facilities where BOTH the name-derived and coordinate-derived FIPS resolved -- only these are comparable
icis_fips_summary <- data.table(                                      # build ICIS_COUNTY_FIPS coverage + agreement summary
  n_facilities        = nrow(co),                                     # denominator: all facilities
  n_icis_fips_set     = sum(!is.na(co$ICIS_COUNTY_FIPS)),             # facilities where ICIS (STATE, COUNTY_NAME) text resolved to exactly one GEOID
  n_county_fips_set   = sum(!is.na(co$COUNTY_FIPS)),                  # facilities where the coordinate's point-in-polygon join resolved to a county
  n_icis_only         = sum(!is.na(co$ICIS_COUNTY_FIPS) & is.na(co$COUNTY_FIPS)),  # ICIS name resolved but coordinate-derived county didn't (no coordinate, or point fell outside every polygon)
  n_both_set          = sum(both),                                    # facilities comparable on both sides
  n_agree             = sum(co$ICIS_COUNTY_FIPS[both] == co$COUNTY_FIPS[both]),  # FLAG: string-equality comparison of two independently-derived FIPS codes -- a disagreement here means either an ICIS county-name mislabel or a coordinate error, not necessarily a bug in this script; the two aren't distinguished. The comparison is a clean character-vs-character match (not integer) because of the colClasses fix above
  pct_agree           = round(mean(co$ICIS_COUNTY_FIPS[both] == co$COUNTY_FIPS[both]), 4))  # agreement rate among comparable facilities, rounded to 4dp
fwrite(icis_fips_summary, file.path(OUT, "icis_county_fips_summary.csv"))  # write CSV 4

# =========================================================================================================
# FIGURES -- print-ready (300dpi), validated categorical palette
# =========================================================================================================
PAL <- c(blue = "#2a78d6", aqua = "#1baf7a", yellow = "#eda100", green = "#008300", violet = "#4a3aa7", red = "#e34948")  # validated categorical palette (shared convention across the profile scripts, dataviz skill)
INK <- "#0b0b0b"; INK_SECONDARY <- "#52514e"; GRID <- "#e1e0d9"; AXIS <- "#c3c2b7"  # text/gridline/axis colors for the print theme below
theme_journal <- theme_minimal(base_size = 11) +                      # base print-ready theme, built on theme_minimal()
  theme(panel.grid.minor = element_blank(), panel.grid.major = element_line(color = GRID, linewidth = 0.3),  # drop minor gridlines; thin muted major gridlines
        axis.line = element_line(color = AXIS, linewidth = 0.3), axis.ticks = element_line(color = AXIS, linewidth = 0.3),  # thin muted axis line/ticks
        text = element_text(color = INK), axis.text = element_text(color = INK_SECONDARY),  # near-black body text, slightly lighter axis labels
        plot.title = element_text(face = "bold", size = 12), plot.subtitle = element_text(color = INK_SECONDARY, size = 9.5),  # bold title, muted subtitle
        plot.caption = element_text(color = INK_SECONDARY, size = 8, hjust = 0), legend.position = "none")  # left-aligned muted caption; no legend (direct end-of-line labels used instead where needed)
save_fig <- function(name, plot, w = 7.5, h = 4.5) ggsave(file.path(OUT_FIG, name), plot, width = w, height = h, dpi = 300)  # helper: save a ggplot object to OUT_FIG at print resolution (300dpi), default 7.5x4.5in

# ---- FIGURE 1: facility location map, contiguous US (99.5% of coordinates fall in this bbox; AK/HI/PR/
#   territories excluded from the PLOT only, not from the underlying data -- noted in the caption) ----------
conus <- co[!is.na(LATITUDE) & !is.na(LONGITUDE) &                    # subset to facilities with a coordinate that also falls inside the CONUS bounding box (plot-only restriction, per comment above)
           LATITUDE > 24 & LATITUDE < 50 & LONGITUDE > -125 & LONGITUDE < -66]  # FLAG: filters on raw LATITUDE/LONGITUDE non-missingness rather than the HAS_COORDINATE column directly -- the two are guaranteed identical only by a stopifnot invariant enforced upstream in 06_coordinates.R (not re-checked here); if that invariant were ever violated this figure's facility count would silently diverge from HAS_COORDINATE-based stats elsewhere in this file
fig1 <- ggplot(conus, aes(LONGITUDE, LATITUDE)) +                     # start figure 1: one point per facility, longitude on x / latitude on y
  geom_point(color = PAL[["blue"]], size = 0.15, alpha = 0.15) +      # tiny, highly transparent points so dense metro areas don't saturate to a solid blob
  coord_quickmap() +                                                  # approximate lat/lon aspect-ratio correction for a quick (non-projected) map
  labs(title = "ICIS-Air facility locations (contiguous US)",
       subtitle = sprintf("n = %s facilities with a coordinate falling in the contiguous-US bounding box (of %s total with any coordinate)",  # subtitle distinguishes "plotted" (CONUS bbox) from "all with any coordinate"
                          format(nrow(conus), big.mark = ","), format(sum(co$HAS_COORDINATE), big.mark = ",")),
       x = NULL, y = NULL,                                            # no axis titles (map is self-explanatory)
       caption = "Source: data/datasets/coordinates.csv.gz (dataset 4). AK/HI/PR/territories excluded from this plot, not from the data.") +  # caption reiterates the plot-only exclusion
  theme_journal +                                                     # shared print-ready theme (defined above)
  theme(axis.text = element_blank(), panel.grid.major = element_blank())  # strip lat/lon tick labels and gridlines -- a map doesn't need them
save_fig("coord_facility_map.png", fig1, w = 9, h = 5.5)              # write PNG at 300dpi, wider than default (map benefits from extra width)

# ---- FIGURE 2: coordinate-vs-ICIS-county distance distribution (checkable facilities, truncated at p99) ----
p99 <- quantile(dist_km, .99)                                         # 99th percentile of the checkable distance distribution (recomputed here for the plot; same population as dist_summary$p99 above)
# filter to the plotted range BEFORE computing bins -- computing a fixed bin COUNT over the full unfiltered
# range (max 2,317km) while only viewing 0-p99km via coord_cartesian put ~all mass in a single giant bin
# (verified: rendered as one solid block, not a histogram). Use a fixed binwidth on pre-filtered data instead.
dd <- data.table(dist = dist_km[dist_km > 0 & dist_km <= p99])        # FLAG: this truncation (nonzero, <= p99) is PLOT-ONLY -- dist_summary's median/p90/p99/max/pct_gross_error (CSV2, above) were already computed on the untruncated dist_km before this line, so nothing printed/written to CSV is biased by it; it affects only this histogram's visual range
fig2 <- ggplot(dd, aes(dist)) +                                       # start figure 2: histogram of coordinate-to-claimed-county distance
  geom_histogram(binwidth = p99 / 60, fill = PAL[["blue"]], color = "white", linewidth = 0.1, boundary = 0) +  # ~60 bins spanning the truncated range (see comment above for why binwidth is fixed on pre-filtered data)
  geom_vline(xintercept = 5, color = PAL[["red"]], linewidth = 0.6, linetype = "dashed") +  # FLAG: "5" is the gross-error threshold, hardcoded again here (see the pct_gross_error FLAG at dist_summary above) rather than read from GROSS_ERROR_KM in coord_county_flag.R
  annotate("text", x = 5, y = Inf, label = "  5km gross-error threshold", color = PAL[["red"]],  # label the threshold line directly on the plot
           hjust = 0, vjust = 1.5, size = 3.1, fontface = "bold") +
  scale_x_continuous(labels = label_comma()) + scale_y_continuous(labels = label_comma()) +  # thousands separators on both axes
  labs(title = "Coordinate-to-ICIS-county distance (nonzero, checkable facilities)",
       subtitle = sprintf("n = %s facilities with dist > 0 (of %s checkable, %s land exactly in the ICIS-claimed county);\nx-axis truncated at the 99th percentile (%.0f km); %.1f%% exceed the 5km gross-error threshold",  # subtitle numbers are drawn from the untruncated dist_km/dist_summary computed earlier, so it correctly describes the full checkable population even though the histogram itself is truncated
                          format(sum(dist_km > 0), big.mark = ","), format(length(dist_km), big.mark = ","),
                          format(sum(dist_km == 0), big.mark = ","), p99, 100 * dist_summary$pct_gross_error),
       x = "Distance (km)", y = "Facilities", caption = "Source: data/datasets/coordinates.csv.gz (dataset 4).") +
  theme_journal + theme(plot.subtitle = element_text(color = INK_SECONDARY, size = 8.3, lineheight = 1.15))  # shared theme + smaller/tighter subtitle text to fit the two-line sprintf above
save_fig("coord_county_dist_distribution.png", fig2)                  # write PNG at default size/dpi

# ---- FIGURE 3: coverage funnel (facility count at each successive data-quality gate) ------------------------
funnel_long <- data.table(                                            # reshape the one-row `funnel` (CSV1) into long form for a bar chart: one row per funnel stage
  stage = factor(c("All facilities", "Has coordinate", "County FIPS set", "Checkable vs ICIS county", "Gross error (>5km)"),  # stage labels, in funnel order
                levels = c("All facilities", "Has coordinate", "County FIPS set", "Checkable vs ICIS county", "Gross error (>5km)")),  # explicit factor levels so bars plot left-to-right in funnel order, not alphabetically
  n = c(funnel$n_facilities, funnel$n_has_coordinate, funnel$n_county_fips_set, funnel$n_checkable_vs_icis, funnel$n_gross_error))  # pull the matching counts from the CSV1 funnel table computed above
fig3 <- ggplot(funnel_long, aes(stage, n)) +                          # start figure 3: bar chart of facility count at each stage
  geom_col(fill = PAL[["blue"]], width = 0.7) +
  geom_text(aes(label = format(n, big.mark = ",")), vjust = -0.5, size = 3.2, color = INK) +  # print the count above each bar
  scale_y_continuous(labels = label_comma(), expand = expansion(mult = c(0, 0.12))) +  # thousands separator; extra headroom above the tallest bar for the count label
  labs(title = "Coordinate data-quality funnel",
       subtitle = "Facility count at each successive gate -- \"Gross error\" is a subset of \"Checkable\", not an additional filter",  # explicit disclaimer that the funnel isn't monotonically nested past "Checkable" -- "Gross error" is a rate WITHIN checkable, not a further exclusion
       x = NULL, y = "Facilities", caption = "Source: data/datasets/coordinates.csv.gz (dataset 4).") +
  theme_journal + theme(axis.text.x = element_text(size = 8.5))       # shrink x-axis stage labels so all five fit without overlapping
save_fig("coord_coverage_funnel.png", fig3, w = 8.5, h = 4.8)         # write PNG, wider than default to fit 5 stage labels

# ---- console summary ---------------------------------------------------------------------------------------
cat("data/datasets/coordinates.csv.gz -- profile summary\n")
cat("=======================================================\n\n")
print(as.data.frame(funnel), row.names = FALSE)                       # print CSV1 funnel table
cat(sprintf("\nhas_coordinate: %.1f%% | gross error (of checkable): %.1f%%\n",  # headline coverage stat + gross-error rate (matches dist_summary$pct_gross_error, computed on the checkable subset only)
            100 * mean(co$HAS_COORDINATE), 100 * dist_summary$pct_gross_error))
cat("\nCOORD_COUNTY_DIST_KM SUMMARY (checkable)\n"); print(as.data.frame(dist_summary), row.names = FALSE)  # print CSV2 distance summary
cat("\nICIS_COUNTY_FIPS SUMMARY (name-derived vs coordinate-derived FIPS)\n")
print(as.data.frame(icis_fips_summary), row.names = FALSE)            # print CSV4 FIPS agreement summary
cat("\nTOP 10 STATES BY FACILITY COUNT\n"); print(as.data.frame(head(by_state, 10)), row.names = FALSE)  # print top 10 rows of CSV3 (by_state, already sorted descending)
cat(sprintf("\n3 figures written to %s\n", OUT_FIG))

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# 1. (line ~32, fread colClasses) COUNTY_FIPS and ICIS_COUNTY_FIPS are correctly forced to character --
#    avoids the leading-zero-drop bug flagged in 13_regulatory_profile.R for REGISTRY_ID/ZIP_CODE. The CSV4
#    agreement comparison (line ~78) relies on this being done right.
# 2. (line ~34, fwrite_rounded()) Defined but never called anywhere in this script -- every CSV's rounding
#    is instead done ad hoc with inline round() calls at the point of computation (inconsistently: some
#    proportions rounded to 3dp, others 4dp). See #3 for the concrete consequence.
# 3. (line ~57-58, dist_summary) median/p90/p99/max are written to coord_county_dist_summary.csv at full
#    floating-point precision -- not rounded at all, unlike pct_zero/pct_gross_error in the same table.
# 4. (line ~58, pct_gross_error) Hardcodes ">5" rather than reading the stored COORD_GROSS_ERROR column
#    (used correctly with na.rm=TRUE elsewhere, e.g. lines ~49/~65) or the GROSS_ERROR_KM constant in
#    coord_county_flag.R. Currently consistent only because of a stopifnot invariant enforced at build time
#    in 06_coordinates.R -- would silently drift if that threshold ever changed without a matching edit here
#    and at every other hardcoded "5" in this file (FIGURE 2's geom_vline/annotate/subtitle, ~lines 119-124).
# 5. (line ~49, funnel$n_gross_error) Correctly uses na.rm=TRUE on COORD_GROSS_ERROR, honoring the 0-vs-NA
#    convention documented in the file header.
# 6. (line ~65, by_state$pct_gross_error) Same -- na.rm=TRUE used correctly on the stored column.
# 7. (line ~78, icis_fips n_agree/pct_agree) Disagreement between ICIS_COUNTY_FIPS (name-derived) and
#    COUNTY_FIPS (coordinate-derived) reflects either an ICIS mislabel or a coordinate error -- this script
#    doesn't attempt to distinguish the two, just reports the disagreement rate.
# 8. (line ~97-98, FIGURE1 `conus` filter) Filters on raw LATITUDE/LONGITUDE non-missingness rather than the
#    HAS_COORDINATE column directly; identical only by an upstream (06_coordinates.R) build-time invariant
#    not re-checked in this script.
# 9. (line ~116, `dd` truncation for FIGURE 2) Plot-only truncation to 0 < dist <= p99 -- confirmed not to
#    affect any printed/CSV statistic, all of which (dist_summary) were computed on the untruncated dist_km
#    above this line.
