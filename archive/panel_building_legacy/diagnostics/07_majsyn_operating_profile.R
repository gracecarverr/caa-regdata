# =========================================================================================================
# code/diagnostics/07_majsyn_operating_profile.R -- descriptive profile of the major_synmin panel under
#   the OPERATING filter, 2015-2025. Purpose: characterize the analysis sample for a reader picking the
#   project up cold -- where the facilities are, how the panel is shaped, how the count measures are
#   distributed, and how Major differs from Synthetic Minor.
#
#   in : data/panels/major_synmin.csv.gz
#   out: output/figures/majsyn_operating/*.png   (10 figures)
#        output/majsyn_operating/*.csv           (every plotted number, for traceability)
#
#   SAMPLE: year %in% 2015:2025 & operating == 1L. The wayback operating-status reconstruction (F7/B.7)
#   exists only for 2015-2025, so this is the widest window where `operating` is defined. Filtering on
#   operating==1 also drops every obs_source=="unobserved" row by construction -- so within this sample
#   a 0 count is a TRUE zero, never a structural NA. (Asserted below.)
#
#   DISCIPLINE (do not "fix" away):
#     * n_* counts are ALL-ROW, not deduped (2026-07-17 revision). Duplicate load is surfaced by the
#       n_*_dup companions, which are carried in the CSVs so event-distinct counts (n_x - n_x_dup) are
#       recoverable. certs in particular run ~81% duplicate.
#     * AIR_POLLUTANT_CLASS_DESC, NAICS/SIC and coordinates are the CURRENT ICIS/FRS snapshot (F2/F3)
#       applied to all years -- they are time-invariant here, not measured per year.
#     * The ragged panel is PARTLY ARTIFACT: exit_source=="dropout" is a disappearance from the snapshot,
#       which may be an extract artifact rather than a real closure (F7). Fig 3 is deliberately NOT
#       captioned as entry/exit.
#     * penalty_amount is NA-when-none, so its distribution is over the nonzero subset only.
#     * Facilities with NA coordinates are unmappable and are dropped from figs 1-2 ONLY, with the
#       dropped count printed on the figure.
#   Hand-run (not part of RUN_ALL.R). No stochastic step, so no seed is required.
# =========================================================================================================
suppressPackageStartupMessages({                                     # load packages without the usual startup banners
  library(data.table); library(ggplot2); library(scales); library(patchwork)  # data.table: fast joins/aggregation; ggplot2/scales: figures; patchwork: combine subplots
})
options(scipen = 999)                                                # disable scientific notation in printed output (display only, no effect on stored values)

PANEL   <- here::here("data/panels/major_synmin.csv.gz")             # input panel path
OUT_FIG <- here::here("output/figures/majsyn_operating")             # figure output dir
OUT_CSV <- here::here("output/majsyn_operating")                     # csv output dir (traceability companions to the figures)
dir.create(OUT_FIG, showWarnings = FALSE, recursive = TRUE)          # create if missing; silent if it already exists
dir.create(OUT_CSV, showWarnings = FALSE, recursive = TRUE)          # create if missing; silent if it already exists

YEARS <- 2015:2025                                                   # analysis window -- matches the OPERATING sample definition in the header (wayback status only covers 2015-2025)
theme_set(theme_minimal(base_size = 11))                             # global default ggplot theme for every figure below
# bg="white" is load-bearing: the map figures use theme_void(), whose plot.background is blank, which
# writes a TRANSPARENT png -- black-on-transparent titles and facet strips then read as invisible in most
# viewers. Forcing an opaque canvas at save time fixes every figure at once.
save_fig <- function(name, plot, w = 9, h = 6)                       # shared "write this ggplot to OUT_FIG" helper
  ggsave(file.path(OUT_FIG, name), plot, width = w, height = h, dpi = 150, bg = "white")  # fixed dpi/background for every figure in this script

# Major / Synthetic Minor is the split running through every figure. Fixed factor order + fixed colours
# so the two classes read identically across the whole set.
CLASS_LEV <- c("Major", "Synthetic Minor")                           # canonical factor level order, reused for every class-coloured figure
CLASS_COL <- c(Major = "#b2182b", `Synthetic Minor` = "#2166ac")     # fixed hex colours keyed to the same two levels, so colour mapping never drifts across figures

# ---------------------------------------------------------------------------------------------------------
# LOAD + FILTER
# ---------------------------------------------------------------------------------------------------------
d <- fread(PANEL)                                                    # read the full major_synmin panel, all years, before any filtering
d <- d[year %in% YEARS & operating == 1L]                            # FLAG: this is THE gate -- restricting to 2015-2025 & operating==1 is what (per header) guarantees obs_source != "unobserved" within `d`, which is what makes every n_* count from here on a true 0 rather than a structural NA; every downstream figure/CSV in this script depends on this filter being correct

# short class label
d[, class := factor(fifelse(AIR_POLLUTANT_CLASS_DESC == "Major Emissions", "Major", "Synthetic Minor"),  # FLAG: binary split by negation -- anything NOT exactly "Major Emissions" (not just the expected "Synthetic Minor Emissions") is folded into "Synthetic Minor" here; relies on this panel already being restricted upstream to just those two classes, which is checked only indirectly below (class must be non-NA), never checked against the actual "Synthetic Minor Emissions" label
                    levels = CLASS_LEV)]                              # fix the display factor order to CLASS_LEV

# The sample claim above, asserted rather than trusted. If any of these fire the filter has drifted and
# the figures should not be believed -- fail loudly instead of silently re-baselining.
stopifnot(
  !anyNA(d$class),                                                   # class assignment above produced no NA, i.e. AIR_POLLUTANT_CLASS_DESC was never missing/unexpected
  all(d$obs_source != "unobserved"),          # operating==1 => observed, by construction
  nrow(d) == 382262L,                                                 # FLAG: hard-coded row-count canary -- if the upstream panel legitimately changes (new snapshot, revised extract), this literal must be deliberately re-derived, not just bumped to whatever nrow(d) happens to be now, or the check stops guarding anything
  uniqueN(d$PGM_SYS_ID) == 40324L                                     # FLAG: hard-coded facility-count canary, same caveat as above
)
cat(sprintf("sample: %s facility-years, %s facilities, %d states, %d-%d\n",  # console readout confirming the asserted sample size
            comma(nrow(d)), comma(uniqueN(d$PGM_SYS_ID)), uniqueN(d$STATE), min(d$year), max(d$year)))

# facility-level table: attributes are time-invariant (F2/F3), so one row per facility is the right grain
# for the map and the industry mix. Taking the LAST observed year keeps the most recent snapshot row.
setorder(d, PGM_SYS_ID, year)                                        # sort so .SD[.N] below reliably picks each facility's latest year
fac <- d[, .SD[.N], by = PGM_SYS_ID,                                  # FLAG: "time-invariant" is asserted in the comment above, not verified here -- if STATE, NAICS_CODES, class, or coord_gross_error ever actually varied within a facility across years, this would silently keep only the latest year's value with no check that it was constant
         .SDcols = c("class", "latitude", "longitude", "STATE", "NAICS_CODES", "coord_gross_error")]

# the six headline count measures, used by figs 5-7
KEY_MEAS <- c(n_inspections = "Inspections", n_violations = "Violations", n_hpv = "HPV",  # named vector: column name -> display label, doubles as the fixed facet/legend order below
              n_enforcement = "Enforcement", n_certs = "Certifications", n_stack_tests = "Stack tests")

# ---------------------------------------------------------------------------------------------------------
# CSV 0 -- sample overview (the numbers every figure is conditioned on)
# ---------------------------------------------------------------------------------------------------------
overview <- d[, .(facility_years = .N, facilities = uniqueN(PGM_SYS_ID),   # facility-year count and distinct facility count, by class
                  share_event = mean(obs_source == "event"),               # share of rows with any recorded activity
                  share_operating_only = mean(obs_source == "operating")), by = class]  # share of rows with zero activity (operating, nothing recorded)
overview <- rbind(overview,
                  d[, .(class = "All", facility_years = .N, facilities = uniqueN(PGM_SYS_ID),  # append an unstratified "All" row pooling both classes
                        share_event = mean(obs_source == "event"),
                        share_operating_only = mean(obs_source == "operating"))])
fwrite(overview[, lapply(.SD, function(x) if (is.numeric(x)) round(x, 4) else x)],  # round numeric columns for the csv, leave the class label column untouched
       file.path(OUT_CSV, "sample_overview.csv"))

# =========================================================================================================
# FIG 1 -- facility point map
# =========================================================================================================
states <- as.data.table(map_data("state"))                           # US state polygon outlines for the map background
fac_geo  <- fac[!is.na(latitude) & !is.na(longitude)]                # per header: facilities with NA coordinates are unmappable, dropped from figs 1-2 ONLY
n_nocoord <- nrow(fac) - nrow(fac_geo)                                # count of facilities excluded from the map, for the subtitle

# CONUS frame. Coordinates are FRS (F3) and a small number are gross errors (coord_gross_error) -- those
# are NOT dropped, only clipped out of view by the frame, so the count on the figure stays honest.
map_base <- function()                                                # shared map layers reused by figs 1 and 2
  list(geom_polygon(data = states, aes(long, lat, group = group),     # state outline polygons
                    fill = "grey96", colour = "grey70", linewidth = .2, inherit.aes = FALSE),
       coord_quickmap(xlim = c(-125, -66), ylim = c(24, 50)),         # FLAG: CONUS-only frame clips out AK/HI/PR/territories from the VIEW -- points there aren't dropped from the data, just outside the visible window, which matters when comparing a facility count read off the figure to the "mapped" count in map_coverage.csv below
       theme_void(base_size = 11),                                    # blank map background/theme
       theme(legend.position = "none", strip.text = element_text(size = 11, face = "bold")))  # no legend on the base layer; legends are added per-figure where needed

g_map <- ggplot(fac_geo, aes(longitude, latitude, colour = class)) +  # base ggplot: one point per mappable facility, coloured by class
  map_base() +                                                        # state outlines + CONUS frame + void theme
  geom_point(size = .25, alpha = .25) +                                # small, semi-transparent points so overlap density still shows
  scale_colour_manual(values = CLASS_COL) +                            # fixed Major/SynMin colours
  facet_wrap(~ class) +                                                # one panel per class
  labs(title = "Operating major / synthetic-minor facilities, 2015-2025",
       subtitle = sprintf(
         "one dot per facility (n = %s mapped; %s of %s have no FRS coordinate and are not shown)",
         comma(nrow(fac_geo)), comma(n_nocoord), comma(nrow(fac))))     # subtitle reports the mapped count and the dropped-for-no-coordinate count
save_fig("map_facilities.png", g_map, w = 12, h = 5)                   # write the figure

fwrite(fac[, .(facilities = .N, mapped = sum(!is.na(latitude)),        # FLAG: "mapped" here means "has non-NA FRS coordinates", not "falls inside the CONUS xlim/ylim actually drawn" in map_base() above -- a facility with valid but out-of-CONUS coordinates (AK/HI/PR) would count as mapped in this csv yet not appear in map_facilities.png, so this csv and the figure are not perfectly reconciled
               no_coord = sum(is.na(latitude)),
               gross_error = sum(coord_gross_error, na.rm = TRUE)), by = class],  # gross_error facilities ARE included in "mapped" (lat/long non-NA), just visually unreliable
       file.path(OUT_CSV, "map_coverage.csv"))                         # write per-class map coverage csv

# =========================================================================================================
# FIG 2 -- same geography as binned density (fig 1 saturates in TX / OH / CA)
# =========================================================================================================
# geom_bin2d, not geom_hex: hex binning needs the `hexbin` package, which is not installed here, and
# square bins carry the same information without adding a dependency.
g_hex <- ggplot(fac_geo, aes(longitude, latitude)) +                   # base ggplot over all mappable facilities, not split into class panels within one plot object
  map_base() +                                                          # shared map layers
  geom_bin2d(bins = 45) +                                               # 2-D bin counts instead of individual points; bin count is a display choice, not computed
  scale_fill_gradient(low = "#deebf7", high = "#08306b", trans = "log10",  # log10 fill scale so a few saturated bins don't wash out the rest
                      name = "facilities", labels = comma) +
  facet_wrap(~ class) +                                                 # one panel per class
  theme(legend.position = "right") +                                    # show the fill legend here (map_base()'s theme hides legends by default)
  labs(title = "Facility density, operating major / synthetic-minor facilities",
       subtitle = "binned counts, log10 fill scale -- readable where the point map saturates")
save_fig("map_facilities_density.png", g_hex, w = 12, h = 5)            # write the figure

# =========================================================================================================
# FIG 3 -- panel shape: facilities per year, and the ragged-panel year-count distribution
# =========================================================================================================
per_year <- d[, .(facilities = uniqueN(PGM_SYS_ID)), by = .(class, year)][order(class, year)]  # distinct facility count per class-year
fwrite(per_year, file.path(OUT_CSV, "facilities_per_year.csv"))          # write facilities-per-year csv

g3a <- ggplot(per_year, aes(year, facilities, colour = class)) +         # line+point trend of facility count by class over time
  geom_line(linewidth = .8) + geom_point(size = 1.2) +                    # line plus point markers
  scale_colour_manual(values = CLASS_COL) +                               # fixed colours
  scale_x_continuous(breaks = YEARS) + scale_y_continuous(labels = comma, limits = c(0, NA)) +  # x break per sample year; y forced to start at 0
  labs(title = "Operating facilities per year", x = NULL, y = "facilities", colour = NULL) +
  theme(legend.position = "bottom", axis.text.x = element_text(angle = 45, hjust = 1))  # legend + rotated x labels

yrs_obs <- d[, .(n_years = .N), by = .(PGM_SYS_ID, class)][, .N, by = .(class, n_years)]  # for each facility, count years observed (1-11); then tabulate facility counts by that year-count, per class
fwrite(yrs_obs[order(class, n_years)], file.path(OUT_CSV, "years_observed_per_facility.csv"))  # write the years-observed distribution csv

g3b <- ggplot(yrs_obs, aes(factor(n_years), N, fill = class)) +           # bar chart of facility count by (discrete) years-observed bucket, class side by side
  geom_col(position = position_dodge(preserve = "single")) +               # dodge bars so a bucket with only one class present doesn't stretch to full width
  scale_fill_manual(values = CLASS_COL) +                                  # fixed colours
  scale_y_continuous(labels = comma) +                                     # comma-formatted y axis
  labs(title = "Years each facility is observed operating",
       subtitle = paste("the panel is unbalanced; 11 = present in every snapshot year.",  # FLAG: "11" is hard-coded rather than derived from length(YEARS) -- if the YEARS window (defined near the top of the file) ever changes, this label goes stale silently
                        "NOT an entry/exit chart -- a facility can leave the sample\nbecause it closed",
                        "OR because it dropped out of the ICIS extract (exit_source == 'dropout'),",
                        "which may be an artifact (F7)."),                 # reiterates the header's "partly artifact" caveat -- deliberately not read as entry/exit
       x = "years observed", y = "facilities", fill = NULL) +
  theme(legend.position = "bottom", plot.subtitle = element_text(size = 8))  # smaller subtitle font to fit the long caveat text

save_fig("panel_shape.png", g3a / g3b, w = 9, h = 9)                       # stack g3a over g3b into one figure via patchwork's `/` operator

# =========================================================================================================
# FIG 4 -- the EXTENSIVE MARGIN: share of operating facility-years with any recorded activity
# ---------------------------------------------------------------------------------------------------------
# READ THIS BEFORE INTERPRETING (see N16). Inside the operating filter, obs_source is NOT an observation
# channel -- it is a deterministic function of the counts: obs_source=="event" <=> (any n_* > 0), verified
# with no off-diagonal (225,837 event rows all nonzero, 156,425 operating rows all zero). So this figure
# plots the EXTENSIVE MARGIN OF THE OUTCOME, not who was watched. The Major/SynMin gap here is mostly
# Title V certs (91.0% of Major event-years vs 12.9% of SynMin, tracking enrollment 91.6% vs 3.3%), not a
# measurement asymmetry. Do NOT condition on obs_source to "clean" a class coefficient -- that selects on
# y > 0 and biases it. Model the extensive margin as an outcome (hurdle) if it is of interest.
# =========================================================================================================
obs_yr <- d[, .(share_event = mean(obs_source == "event"), n = .N), by = .(class, year)][order(class, year)]  # share of facility-years with any recorded activity, by class-year -- see the extensive-margin caveat above
fwrite(obs_yr, file.path(OUT_CSV, "obs_source_by_year.csv"))              # write obs_source-by-year csv

g_obs <- ggplot(obs_yr, aes(year, share_event, colour = class)) +          # trend of the extensive margin by class
  geom_line(linewidth = .8) + geom_point(size = 1.2) +                      # line plus point markers
  scale_colour_manual(values = CLASS_COL) +                                 # fixed colours
  scale_y_continuous(labels = percent_format(accuracy = 1), limits = c(0, 1)) +  # percent y axis, full 0-100% range
  scale_x_continuous(breaks = YEARS) +                                      # x break per sample year
  labs(title = "Extensive margin: operating facility-years with any recorded activity",
       subtitle = paste("the complement is a TRUE ZERO (known open, zero events), not a missing value.",
                        "This is a function of the counts, NOT\na measure of who was observed --",
                        "do not condition on it (N16). The gap is mostly Title V certs."),
       x = NULL, y = "% with any activity", colour = NULL) +
  theme(legend.position = "bottom", axis.text.x = element_text(angle = 45, hjust = 1))
save_fig("obs_source_composition.png", g_obs)                              # write the figure

# =========================================================================================================
# FIG 5/6 -- distribution of the six key count measures
# =========================================================================================================
key_long <- melt(d[, c("class", "year", names(KEY_MEAS)), with = FALSE],   # reshape the six count columns from wide to long, one row per facility-year-measure
                 id.vars = c("class", "year"), variable.name = "measure", value.name = "count")
key_long[, measure := factor(KEY_MEAS[as.character(measure)], levels = unname(KEY_MEAS))]  # map raw column name to display label, fix factor/facet order
stopifnot(!anyNA(key_long$count))          # every row here is observed, so no count may be NA

DUP_NOTE <- paste("counts are ALL rows -- nothing deduped; certs carry ~81% duplicate load",  # reusable subtitle fragment reiterating the all-row/not-deduped discipline (reused across figs 5-7)
                  "(see the _dup columns in summary_counts.csv)")

g_dist <- ggplot(key_long, aes(x = count, fill = class)) +                  # overlaid histograms of count, by class
  geom_histogram(bins = 30, position = "identity", alpha = .55, colour = NA) +  # identity position + transparency so both classes' bars are visible where they overlap
  scale_fill_manual(values = CLASS_COL) +                                    # fixed colours
  scale_x_continuous(trans = "log1p", breaks = c(0, 1, 3, 10, 30, 100, 300)) +  # log1p x scale so the zero-heavy right-skewed counts stay legible
  scale_y_continuous(labels = label_number(scale_cut = cut_short_scale())) +  # short-scale y labels (e.g. "1K")
  facet_wrap(~ measure, scales = "free_y") +                                  # one panel per measure, independent y scales
  labs(title = "Distribution of key measures, operating facility-years 2015-2025",
       subtitle = paste0("x on log1p scale. ", DUP_NOTE),                     # subtitle reiterates the dup-load caveat
       x = "count in a facility-year", y = "facility-years", fill = NULL) +
  theme(legend.position = "bottom", plot.subtitle = element_text(size = 8))
save_fig("dist_counts.png", g_dist, w = 10, h = 6.5)                          # write the figure

g_ecdf <- ggplot(key_long, aes(x = count, colour = class)) +                  # empirical CDF of count, by class
  stat_ecdf(linewidth = .7) +                                                  # ECDF step lines
  scale_colour_manual(values = CLASS_COL) +                                    # fixed colours
  scale_x_continuous(trans = "log1p", breaks = c(0, 1, 3, 10, 30, 100)) +       # log1p x scale, matching g_dist
  scale_y_continuous(labels = percent_format(accuracy = 1)) +                  # percent y axis
  facet_wrap(~ measure, scales = "free_x") +                                    # one panel per measure, independent x scales
  labs(title = "ECDF of key measures, operating facility-years 2015-2025",
       subtitle = paste0("the intercept at x=0 is the zero mass. ", DUP_NOTE),  # the ECDF's value at x=0 is exactly the zero share for that measure
       x = "count in a facility-year (log1p)", y = "cumulative share", colour = NULL) +
  theme(legend.position = "bottom", plot.subtitle = element_text(size = 8))
save_fig("ecdf_counts.png", g_ecdf, w = 10, h = 6.5)                            # write the figure

# five-number summaries + zero share, carrying the _dup companions so event-distinct counts are recoverable
summ <- rbindlist(lapply(names(KEY_MEAS), function(m) {                        # build one summary row per measure, pooled across class ("All")
  dupc <- paste0(m, "_dup")                                                     # matching duplicate-count column name for this measure
  x <- d[[m]]                                                                   # raw values for this measure across the whole sample
  data.table(measure = KEY_MEAS[m], class = "All", n = length(x),
             mean = mean(x), sd = sd(x), p50 = median(x), p90 = quantile(x, .9),  # FLAG: mean/sd/p50/p90/p99/max/total below are all computed on `x`, the ALL-ROW (duplicate-inflated) counts per the header's discipline note -- e.g. reported "mean" for n_certs is inflated by the ~81% duplicate load, not just `total`; there is no deduped mean/median/p90 anywhere in this table, only `total_dup` isolates the duplicate contribution
             p99 = quantile(x, .99), max = max(x), share_zero = mean(x == 0),
             total = sum(x), total_dup = if (dupc %in% names(d)) sum(d[[dupc]]) else NA_real_)  # separately sum the duplicate-only companion column, when it exists
}))
summ_by <- rbindlist(lapply(names(KEY_MEAS), function(m) {                       # same summary, computed within each class (same all-row/dup-inflation caveat applies here too)
  dupc <- paste0(m, "_dup")                                                       # matching duplicate-count column name
  d[, {
    x <- get(m)                                                                    # this class's raw values for the measure
    .(measure = KEY_MEAS[m], n = .N, mean = mean(x), sd = sd(x), p50 = median(x),
      p90 = quantile(x, .9), p99 = quantile(x, .99), max = max(x), share_zero = mean(x == 0),
      total = sum(x), total_dup = if (dupc %in% names(.SD)) sum(get(dupc)) else NA_real_)
  }, by = class]
}))
setcolorder(summ_by, c("measure", "class"))                                       # reorder columns for readability before stacking
out_summ <- rbind(summ, summ_by, use.names = TRUE)                                # stack the pooled "All" row and the per-class rows into one table
num <- setdiff(names(out_summ), c("measure", "class"))                            # identify the numeric columns to round
out_summ[, (num) := lapply(.SD, function(x) round(x, 4)), .SDcols = num]          # round in place -- data.table `:=` mutates out_summ directly
fwrite(out_summ, file.path(OUT_CSV, "summary_counts.csv"))                        # write summary_counts.csv

# =========================================================================================================
# FIG 7 -- activity over time (mean events per operating facility-year)
# =========================================================================================================
act <- key_long[, .(mean_count = mean(count)), by = .(class, year, measure)]        # FLAG: mean(count) here is again over the all-row (not deduped) counts -- same dup-load caveat as the summary table above; if the duplicate rate itself trends over time for a given class/measure, that would confound the apparent time trend, not just the level
fwrite(act[order(measure, class, year)], file.path(OUT_CSV, "activity_over_time.csv"))  # write activity-over-time csv

g_act <- ggplot(act, aes(year, mean_count, colour = class)) +                        # trend of mean count per facility-year, by class
  geom_line(linewidth = .8) +                                                          # line only (no point markers, unlike figs 3/4)
  scale_colour_manual(values = CLASS_COL) +                                            # fixed colours
  facet_wrap(~ measure, scales = "free_y") +                                            # one panel per measure, independent y scales
  scale_x_continuous(breaks = seq(2015, 2025, 2)) +                                     # x breaks every 2 years
  labs(title = "Mean events per operating facility-year",
       subtitle = paste0("denominator is all operating facility-years (zeros included). ", DUP_NOTE),  # denominator note -- consistent with the extensive-margin discipline in fig 4
       x = NULL, y = "mean count", colour = NULL) +
  theme(legend.position = "bottom", plot.subtitle = element_text(size = 8))
save_fig("activity_over_time.png", g_act, w = 10, h = 6)                                # write the figure

# =========================================================================================================
# FIG 8 -- program enrollment (the YEAR-VARYING prog_*_active flags, not the static prog_* profile)
# =========================================================================================================
PROG <- c(prog_sip_active = "SIP", prog_titlev_active = "Title V", prog_nsps_active = "NSPS",  # named vector: year-varying active-flag column -> display label
          prog_mact_active = "MACT", prog_neshap_active = "NESHAP", prog_fesop_active = "FESOP",
          prog_nsr_active = "NSR", prog_psd_active = "PSD")
prog <- melt(d[, c("class", names(PROG)), with = FALSE], id.vars = "class",             # reshape the eight active-flag columns to long
             variable.name = "program", value.name = "active")
prog <- prog[!is.na(active), .(share = mean(active), n = .N), by = .(class, program)]   # FLAG: rows with NA active are dropped before computing the share -- so the denominator `n` is facility-years where that program flag was actually evaluated, not all operating facility-years, and `n` differs by program; share is checkable against `n` in the csv, but easy to misread at face value without checking it
prog[, program := factor(PROG[as.character(program)], levels = unname(PROG))]           # map to display label, fix factor order
fwrite(prog[order(program, class)], file.path(OUT_CSV, "program_enrollment.csv"))        # write program enrollment csv

g_prog <- ggplot(prog, aes(reorder(program, share), share, fill = class)) +               # bars ordered by enrollment share
  geom_col(position = position_dodge(width = .8), width = .75) +                           # dodged bars, class side by side
  coord_flip() +                                                                            # horizontal bars for label readability
  scale_fill_manual(values = CLASS_COL) +                                                   # fixed colours
  scale_y_continuous(labels = percent_format(accuracy = 1)) +                               # percent axis
  labs(title = "Program enrollment among operating facility-years, 2015-2025",
       subtitle = paste("year-varying prog_*_active flags from the wayback snapshots.",
                        "Title V is close to definitional for Major and near-absent for Synthetic Minor."),
       x = NULL, y = "% of operating facility-years enrolled", fill = NULL) +
  theme(legend.position = "bottom", plot.subtitle = element_text(size = 8))
save_fig("program_enrollment.png", g_prog, w = 9, h = 5.5)                                   # write the figure

# =========================================================================================================
# FIG 9 -- HPV status over time, and the nonzero penalty distribution
# =========================================================================================================
hpv <- d[!is.na(hpv_active), .(share_hpv = mean(hpv_active), n = .N), by = .(class, year)]    # share in HPV status among facility-years where hpv_active is non-missing, by class-year
fwrite(hpv[order(class, year)], file.path(OUT_CSV, "hpv_by_year.csv"))                          # write hpv-by-year csv

g9a <- ggplot(hpv, aes(year, share_hpv, colour = class)) +                                       # trend of HPV share by class
  geom_line(linewidth = .8) + geom_point(size = 1.2) +                                             # line plus point markers
  scale_colour_manual(values = CLASS_COL) +                                                        # fixed colours
  scale_y_continuous(labels = percent_format(accuracy = .1), limits = c(0, NA)) +                  # finer percent precision, y starts at 0
  scale_x_continuous(breaks = YEARS) +                                                              # x break per sample year
  labs(title = "Share of operating facility-years in high-priority-violator status",
       subtitle = "interval-derived hpv_active (P8); this flag alone keeps the dup==0 rule",         # hpv_active is unaffected by the duplicate-load issue that afflicts the n_* counts
       x = NULL, y = "% in HPV status", colour = NULL) +
  theme(legend.position = "bottom", axis.text.x = element_text(angle = 45, hjust = 1),
        plot.subtitle = element_text(size = 8))

pen <- d[!is.na(penalty_amount) & penalty_amount > 0, .(class, penalty_amount)]                    # per header: penalty_amount is NA-when-none, so restrict to the positive/nonzero subset (excludes both NA and any non-positive rows)
fwrite(pen[, .(n_facility_years = .N, total = sum(penalty_amount), median = median(penalty_amount),  # FLAG: total/median/p90/max here are computed over ALL formal rows for a facility-year (not deduped) -- the plot subtitle below notes this and that penalty_amount_dup holds the duplicate dollars separately, but that dup companion is not subtracted anywhere in this csv, only mentioned in the figure text
                p90 = quantile(penalty_amount, .9), max = max(penalty_amount)), by = class],
       file.path(OUT_CSV, "penalty_summary.csv"))                                                   # write penalty summary csv

g9b <- ggplot(pen, aes(penalty_amount, fill = class)) +                                              # overlaid histograms of nonzero penalty amounts, by class
  geom_histogram(bins = 40, position = "identity", alpha = .55, colour = NA) +                         # identity position + transparency
  scale_fill_manual(values = CLASS_COL) +                                                              # fixed colours
  scale_x_log10(labels = label_dollar(scale_cut = cut_short_scale())) +                                # log10 dollar x axis (penalties are heavy-tailed)
  scale_y_continuous(labels = comma) +                                                                  # comma y axis
  labs(title = "Nonzero facility-year penalties",
       subtitle = sprintf(paste("n = %s facility-years with positive penalty dollars; max = %s.",
                                "penalty_amount is NA-when-none, so zeros are\nabsent by construction,",
                                "and it sums ALL formal rows (penalty_amount_dup holds the duplicate $)."),
                          comma(nrow(pen)), dollar(max(pen$penalty_amount))),
       x = "penalty amount (log scale)", y = "facility-years", fill = NULL) +
  theme(legend.position = "bottom", plot.subtitle = element_text(size = 8))

save_fig("hpv_and_penalties.png", g9a / g9b, w = 9, h = 9)                                            # stack g9a over g9b via patchwork

# =========================================================================================================
# FIG 10 -- industry mix (NAICS 2-digit sectors, facility grain)
# =========================================================================================================
# NAICS_CODES is a possibly multi-valued delimited string (CC7) -- take the FIRST code as the facility's
# primary sector rather than exploding the grain.
fac[, naics2 := substr(trimws(tstrsplit(NAICS_CODES, "[^0-9]")[[1]]), 1, 2)]                          # FLAG: mutates `fac` in place via data.table `:=`; takes the FIRST delimited NAICS code as the facility's primary sector and its first two digits -- any secondary listed NAICS codes are silently ignored, which could matter if a facility's secondary industry differs systematically by class
SECTOR <- c("11" = "Agriculture", "21" = "Mining & extraction", "22" = "Utilities",                   # NAICS 2-digit -> broad sector label crosswalk (standard groupings; 31/32/33 -> Manufacturing, 44/45 -> Retail trade, 48/49 -> Transport & warehousing)
            "23" = "Construction", "31" = "Manufacturing", "32" = "Manufacturing",
            "33" = "Manufacturing", "42" = "Wholesale trade", "44" = "Retail trade",
            "45" = "Retail trade", "48" = "Transport & warehousing", "49" = "Transport & warehousing",
            "51" = "Information", "52" = "Finance & insurance", "53" = "Real estate",
            "54" = "Professional services", "55" = "Management of companies",
            "56" = "Admin & waste services", "61" = "Education", "62" = "Health care",
            "71" = "Arts & recreation", "72" = "Accommodation & food", "81" = "Other services",
            "92" = "Public administration")
fac[, sector := fifelse(is.na(naics2) | naics2 == "", "No NAICS code",                                # FLAG: two distinct "unknown" buckets here -- facilities with no NAICS code at all get "No NAICS code"; facilities WITH a 2-digit code that isn't in the SECTOR crosswalk get "Other / unclassified" via fcoalesce's NA fallback. Not interchangeable, unlike the fold-everything-into-one-residual pattern seen elsewhere in this project -- worth knowing when reading industry_mix.csv
                        fcoalesce(SECTOR[naics2], "Other / unclassified"))]

ind <- fac[, .N, by = .(class, sector)]                                                                # facility count by class-sector
top <- ind[, .(tot = sum(N)), by = sector][order(-tot)][1:12, sector]                                  # FLAG: hard-coded top-12 cutoff for the figure -- a display choice, not a computed/documented threshold; sectors ranked 13+ are dropped from the PLOT only
ind <- ind[sector %in% top]                                                                             # filter the plotting data down to the top-12 sectors
fwrite(fac[, .N, by = .(class, sector)][order(-N)], file.path(OUT_CSV, "industry_mix.csv"))            # csv keeps the FULL sector breakdown (not just top 12) -- top-12 is a figure-only restriction

g_ind <- ggplot(ind, aes(reorder(sector, N, sum), N, fill = class)) +                                   # bars ordered by total facility count
  geom_col(width = .75) +                                                                                # stacked bars (no dodge/position specified -> default stack)
  coord_flip() +                                                                                          # horizontal bars for sector-label readability
  scale_fill_manual(values = CLASS_COL) +                                                                 # fixed colours
  scale_y_continuous(labels = comma) +                                                                    # comma axis
  labs(title = "Industry mix of operating facilities, top 12 sectors",
       subtitle = paste("NAICS 2-digit of the FIRST listed code, current ICIS snapshot applied to all",
                        "years (F2). One row per facility, not per facility-year."),
       x = NULL, y = "facilities", fill = NULL) +
  theme(legend.position = "bottom", plot.subtitle = element_text(size = 8))
save_fig("industry_mix.png", g_ind, w = 9, h = 6)                                                        # write the figure

# =========================================================================================================
# FIG 11 -- Major / Synthetic Minor composition BY STATE
# ---------------------------------------------------------------------------------------------------------
# Added after the point map (fig 1) showed Texas essentially devoid of synthetic minors while its Major
# coverage looked normal. That is not an industrial fact -- it is a state classification/reporting artifact,
# and it is large: the synthetic-minor share of operating facilities runs from 3.7% (TX) to 94.9% (VT).
# Surfaced, NOT corrected: the Major/SynMin contrast in every other figure here is partly a comparison
# across state reporting regimes, which matters for any design that pools states.
# =========================================================================================================
st <- dcast(fac[, .N, by = .(STATE, class)], STATE ~ class, value.var = "N", fill = 0L)                 # facility counts by state x class, reshaped wide; fill=0L means a state with none of one class gets 0, not NA
setnames(st, CLASS_LEV, c("major", "synmin"))                                                            # rename the two class columns to lowercase for readability
st[, `:=`(total = major + synmin, synmin_share = synmin / (major + synmin))]                             # total facilities per state and the synthetic-minor share
setorder(st, -synmin_share)                                                                               # sort descending by synmin share for the csv/plot ranking
fwrite(st[, .(STATE, major, synmin, total, synmin_share = round(synmin_share, 4))],                      # write the FULL per-state composition (all states, unfiltered)
       file.path(OUT_CSV, "class_composition_by_state.csv"))

st_plot <- st[total >= 100]                     # suppress tiny states where the share is noise
g_st <- ggplot(st_plot, aes(reorder(STATE, synmin_share), synmin_share)) +                                # bars per state, ordered by synmin share
  geom_col(fill = CLASS_COL[["Synthetic Minor"]], width = .75) +                                            # single-colour bars using the SynMin palette colour
  geom_hline(yintercept = fac[, mean(class == "Synthetic Minor")],                                           # dashed reference line at the national synthetic-minor share (facility grain), computed fresh from `fac`
             linetype = "dashed", colour = "grey30") +
  coord_flip() +                                                                                              # horizontal bars for state-label readability
  scale_y_continuous(labels = percent_format(accuracy = 1), limits = c(0, 1)) +                               # percent y axis, full 0-100% range
  labs(title = "Synthetic-minor share of operating facilities, by state",
       subtitle = paste("states with >=100 operating facilities; dashed line = national share.",           # FLAG: the "TX 3.7% to VT 94.9%" figures below (and in the header block above) are typed as literal text, not computed inline from `st` here -- if the underlying data changes, these labels will NOT auto-update and must be manually re-derived and re-typed
                        "The spread (TX 3.7% to VT 94.9%) is a state\nclassification/reporting artifact,",
                        "not an industrial one -- the Major/SynMin split is confounded with state regime."),
       x = NULL, y = "% synthetic minor") +
  theme(plot.subtitle = element_text(size = 8), axis.text.y = element_text(size = 7))
save_fig("class_composition_by_state.png", g_st, w = 8, h = 9)                                                # write the figure

cat(sprintf("wrote %d PNG figures to %s\n", length(list.files(OUT_FIG, "\\.png$")), OUT_FIG))                 # console confirmation of figure count written
cat(sprintf("wrote %d CSV tabulations to %s\n", length(list.files(OUT_CSV, "\\.csv$")), OUT_CSV))              # console confirmation of csv count written

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# 1.  ~line 58  (d <- d[year %in% YEARS & operating == 1L]): this filter is the sole gate that makes every
#     n_* count in the rest of the script a true 0 rather than a structural NA (obs_source != "unobserved"
#     is only guaranteed inside it). Everything downstream depends on this filter being correct.
# 2.  ~line 61  (class := fifelse(AIR_POLLUTANT_CLASS_DESC == "Major Emissions", "Major", "Synthetic Minor")):
#     binary split by negation -- anything not exactly "Major Emissions" is folded into "Synthetic Minor",
#     not verified against the actual "Synthetic Minor Emissions" label; relies on the panel already being
#     restricted to just these two classes upstream.
# 3.  ~line 69-70 (stopifnot nrow(d) == 382262L, uniqueN(d$PGM_SYS_ID) == 40324L): hard-coded canary values
#     that must be deliberately re-derived (not just bumped) if the upstream panel legitimately changes.
# 4.  ~line 78-79 (fac <- d[, .SD[.N], by = PGM_SYS_ID, ...]): "time-invariant" attributes (STATE,
#     NAICS_CODES, class, coord_gross_error) are taken from each facility's last-observed row without any
#     check that they are actually constant across that facility's years.
# 5.  ~line 110 (coord_quickmap(xlim = c(-125, -66), ylim = c(24, 50))): CONUS-only frame clips AK/HI/PR out
#     of the visible map, relevant when comparing a facility count read off the figure to map_coverage.csv.
# 6.  ~line 124 (map_coverage.csv "mapped" column): counts facilities with non-NA FRS coordinates, not
#     facilities that actually fall inside the CONUS xlim/ylim drawn in the figure -- the csv and the figure
#     are not perfectly reconciled for out-of-CONUS facilities.
# 7.  ~line 167 (g3b subtitle "11 = present in every snapshot year"): "11" is a hard-coded literal, not
#     derived from the YEARS window -- would go stale silently if the analysis window changes.
# 8.  ~line 242-245 (summ: mean/sd/p50/p90/p99/max/total): computed on the ALL-ROW, duplicate-inflated
#     counts per the file's own stated discipline -- only `total_dup` isolates the duplicate contribution;
#     there is no deduped mean/median/p90 anywhere in this table (same issue repeats in summ_by).
# 9.  ~line 265 (act <- key_long[, .(mean_count = mean(count)), ...]) FIG 7: mean is likewise over
#     duplicate-inflated counts; if the duplicate rate itself trends over time, the plotted time trend is
#     confounded with changing duplicate load, not just level.
# 10. ~line 287 (prog <- prog[!is.na(active), ...]): denominator `n` for each class-program share is
#     facility-years where that flag was actually evaluated, which differs by program -- easy to misread
#     `share` at face value without checking the accompanying `n`.
# 11. ~line 321 (penalty_summary.csv total/median/p90/max): sums/summarizes ALL formal rows for a
#     facility-year (not deduped); penalty_amount_dup is mentioned only in the figure subtitle text, not
#     subtracted or reported in this csv.
# 12. ~line 345 (fac[, naics2 := ...]): mutates `fac` in place via data.table `:=`; takes only the FIRST
#     listed NAICS code as the facility's primary sector, silently discarding any secondary codes.
# 13. ~line 355 (fac[, sector := fifelse(...)]): two distinct "unknown" buckets ("No NAICS code" vs.
#     "Other / unclassified") that look similar but are not interchangeable -- worth knowing when reading
#     industry_mix.csv.
# 14. ~line 359 (top <- ind[...][1:12, sector]): hard-coded "top 12" sectors is an arbitrary display cutoff,
#     not a computed/documented threshold; the csv retains the full breakdown, only the figure is truncated.
# 15. ~line 391 (st_plot <- st[total >= 100]): hard-coded facility-count threshold (100) for state inclusion
#     in the figure; already noted inline as noise suppression, flagged here for visibility -- states below
#     the cutoff remain in the csv but are dropped from the plot.
# 16. ~line 399 (g_st subtitle "TX 3.7% to VT 94.9%"): these percentages (and the matching ones in the file
#     header) are typed as literal text, not computed inline from `st` in this script -- will not auto-update
#     if the underlying data changes.
# =========================================================================================================
