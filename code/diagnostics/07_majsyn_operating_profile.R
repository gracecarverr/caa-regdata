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
suppressPackageStartupMessages({
  library(data.table); library(ggplot2); library(scales); library(patchwork)
})
options(scipen = 999)

PANEL   <- here::here("data/panels/major_synmin.csv.gz")
OUT_FIG <- here::here("output/figures/majsyn_operating")
OUT_CSV <- here::here("output/majsyn_operating")
dir.create(OUT_FIG, showWarnings = FALSE, recursive = TRUE)
dir.create(OUT_CSV, showWarnings = FALSE, recursive = TRUE)

YEARS <- 2015:2025
theme_set(theme_minimal(base_size = 11))
# bg="white" is load-bearing: the map figures use theme_void(), whose plot.background is blank, which
# writes a TRANSPARENT png -- black-on-transparent titles and facet strips then read as invisible in most
# viewers. Forcing an opaque canvas at save time fixes every figure at once.
save_fig <- function(name, plot, w = 9, h = 6)
  ggsave(file.path(OUT_FIG, name), plot, width = w, height = h, dpi = 150, bg = "white")

# Major / Synthetic Minor is the split running through every figure. Fixed factor order + fixed colours
# so the two classes read identically across the whole set.
CLASS_LEV <- c("Major", "Synthetic Minor")
CLASS_COL <- c(Major = "#b2182b", `Synthetic Minor` = "#2166ac")

# ---------------------------------------------------------------------------------------------------------
# LOAD + FILTER
# ---------------------------------------------------------------------------------------------------------
d <- fread(PANEL)
d <- d[year %in% YEARS & operating == 1L]

# short class label
d[, class := factor(fifelse(AIR_POLLUTANT_CLASS_DESC == "Major Emissions", "Major", "Synthetic Minor"),
                    levels = CLASS_LEV)]

# The sample claim above, asserted rather than trusted. If any of these fire the filter has drifted and
# the figures should not be believed -- fail loudly instead of silently re-baselining.
stopifnot(
  !anyNA(d$class),
  all(d$obs_source != "unobserved"),          # operating==1 => observed, by construction
  nrow(d) == 382262L,
  uniqueN(d$PGM_SYS_ID) == 40324L
)
cat(sprintf("sample: %s facility-years, %s facilities, %d states, %d-%d\n",
            comma(nrow(d)), comma(uniqueN(d$PGM_SYS_ID)), uniqueN(d$STATE), min(d$year), max(d$year)))

# facility-level table: attributes are time-invariant (F2/F3), so one row per facility is the right grain
# for the map and the industry mix. Taking the LAST observed year keeps the most recent snapshot row.
setorder(d, PGM_SYS_ID, year)
fac <- d[, .SD[.N], by = PGM_SYS_ID,
         .SDcols = c("class", "latitude", "longitude", "STATE", "NAICS_CODES", "coord_gross_error")]

# the six headline count measures, used by figs 5-7
KEY_MEAS <- c(n_inspections = "Inspections", n_violations = "Violations", n_hpv = "HPV",
              n_enforcement = "Enforcement", n_certs = "Certifications", n_stack_tests = "Stack tests")

# ---------------------------------------------------------------------------------------------------------
# CSV 0 -- sample overview (the numbers every figure is conditioned on)
# ---------------------------------------------------------------------------------------------------------
overview <- d[, .(facility_years = .N, facilities = uniqueN(PGM_SYS_ID),
                  share_event = mean(obs_source == "event"),
                  share_operating_only = mean(obs_source == "operating")), by = class]
overview <- rbind(overview,
                  d[, .(class = "All", facility_years = .N, facilities = uniqueN(PGM_SYS_ID),
                        share_event = mean(obs_source == "event"),
                        share_operating_only = mean(obs_source == "operating"))])
fwrite(overview[, lapply(.SD, function(x) if (is.numeric(x)) round(x, 4) else x)],
       file.path(OUT_CSV, "sample_overview.csv"))

# =========================================================================================================
# FIG 1 -- facility point map
# =========================================================================================================
states <- as.data.table(map_data("state"))
fac_geo  <- fac[!is.na(latitude) & !is.na(longitude)]
n_nocoord <- nrow(fac) - nrow(fac_geo)

# CONUS frame. Coordinates are FRS (F3) and a small number are gross errors (coord_gross_error) -- those
# are NOT dropped, only clipped out of view by the frame, so the count on the figure stays honest.
map_base <- function()
  list(geom_polygon(data = states, aes(long, lat, group = group),
                    fill = "grey96", colour = "grey70", linewidth = .2, inherit.aes = FALSE),
       coord_quickmap(xlim = c(-125, -66), ylim = c(24, 50)),
       theme_void(base_size = 11),
       theme(legend.position = "none", strip.text = element_text(size = 11, face = "bold")))

g_map <- ggplot(fac_geo, aes(longitude, latitude, colour = class)) +
  map_base() +
  geom_point(size = .25, alpha = .25) +
  scale_colour_manual(values = CLASS_COL) +
  facet_wrap(~ class) +
  labs(title = "Operating major / synthetic-minor facilities, 2015-2025",
       subtitle = sprintf(
         "one dot per facility (n = %s mapped; %s of %s have no FRS coordinate and are not shown)",
         comma(nrow(fac_geo)), comma(n_nocoord), comma(nrow(fac))))
save_fig("map_facilities.png", g_map, w = 12, h = 5)

fwrite(fac[, .(facilities = .N, mapped = sum(!is.na(latitude)),
               no_coord = sum(is.na(latitude)),
               gross_error = sum(coord_gross_error, na.rm = TRUE)), by = class],
       file.path(OUT_CSV, "map_coverage.csv"))

# =========================================================================================================
# FIG 2 -- same geography as binned density (fig 1 saturates in TX / OH / CA)
# =========================================================================================================
# geom_bin2d, not geom_hex: hex binning needs the `hexbin` package, which is not installed here, and
# square bins carry the same information without adding a dependency.
g_hex <- ggplot(fac_geo, aes(longitude, latitude)) +
  map_base() +
  geom_bin2d(bins = 45) +
  scale_fill_gradient(low = "#deebf7", high = "#08306b", trans = "log10",
                      name = "facilities", labels = comma) +
  facet_wrap(~ class) +
  theme(legend.position = "right") +
  labs(title = "Facility density, operating major / synthetic-minor facilities",
       subtitle = "binned counts, log10 fill scale -- readable where the point map saturates")
save_fig("map_facilities_density.png", g_hex, w = 12, h = 5)

# =========================================================================================================
# FIG 3 -- panel shape: facilities per year, and the ragged-panel year-count distribution
# =========================================================================================================
per_year <- d[, .(facilities = uniqueN(PGM_SYS_ID)), by = .(class, year)][order(class, year)]
fwrite(per_year, file.path(OUT_CSV, "facilities_per_year.csv"))

g3a <- ggplot(per_year, aes(year, facilities, colour = class)) +
  geom_line(linewidth = .8) + geom_point(size = 1.2) +
  scale_colour_manual(values = CLASS_COL) +
  scale_x_continuous(breaks = YEARS) + scale_y_continuous(labels = comma, limits = c(0, NA)) +
  labs(title = "Operating facilities per year", x = NULL, y = "facilities", colour = NULL) +
  theme(legend.position = "bottom", axis.text.x = element_text(angle = 45, hjust = 1))

yrs_obs <- d[, .(n_years = .N), by = .(PGM_SYS_ID, class)][, .N, by = .(class, n_years)]
fwrite(yrs_obs[order(class, n_years)], file.path(OUT_CSV, "years_observed_per_facility.csv"))

g3b <- ggplot(yrs_obs, aes(factor(n_years), N, fill = class)) +
  geom_col(position = position_dodge(preserve = "single")) +
  scale_fill_manual(values = CLASS_COL) +
  scale_y_continuous(labels = comma) +
  labs(title = "Years each facility is observed operating",
       subtitle = paste("the panel is unbalanced; 11 = present in every snapshot year.",
                        "NOT an entry/exit chart -- a facility can leave the sample\nbecause it closed",
                        "OR because it dropped out of the ICIS extract (exit_source == 'dropout'),",
                        "which may be an artifact (F7)."),
       x = "years observed", y = "facilities", fill = NULL) +
  theme(legend.position = "bottom", plot.subtitle = element_text(size = 8))

save_fig("panel_shape.png", g3a / g3b, w = 9, h = 9)

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
obs_yr <- d[, .(share_event = mean(obs_source == "event"), n = .N), by = .(class, year)][order(class, year)]
fwrite(obs_yr, file.path(OUT_CSV, "obs_source_by_year.csv"))

g_obs <- ggplot(obs_yr, aes(year, share_event, colour = class)) +
  geom_line(linewidth = .8) + geom_point(size = 1.2) +
  scale_colour_manual(values = CLASS_COL) +
  scale_y_continuous(labels = percent_format(accuracy = 1), limits = c(0, 1)) +
  scale_x_continuous(breaks = YEARS) +
  labs(title = "Extensive margin: operating facility-years with any recorded activity",
       subtitle = paste("the complement is a TRUE ZERO (known open, zero events), not a missing value.",
                        "This is a function of the counts, NOT\na measure of who was observed --",
                        "do not condition on it (N16). The gap is mostly Title V certs."),
       x = NULL, y = "% with any activity", colour = NULL) +
  theme(legend.position = "bottom", axis.text.x = element_text(angle = 45, hjust = 1))
save_fig("obs_source_composition.png", g_obs)

# =========================================================================================================
# FIG 5/6 -- distribution of the six key count measures
# =========================================================================================================
key_long <- melt(d[, c("class", "year", names(KEY_MEAS)), with = FALSE],
                 id.vars = c("class", "year"), variable.name = "measure", value.name = "count")
key_long[, measure := factor(KEY_MEAS[as.character(measure)], levels = unname(KEY_MEAS))]
stopifnot(!anyNA(key_long$count))          # every row here is observed, so no count may be NA

DUP_NOTE <- paste("counts are ALL rows -- nothing deduped; certs carry ~81% duplicate load",
                  "(see the _dup columns in summary_counts.csv)")

g_dist <- ggplot(key_long, aes(x = count, fill = class)) +
  geom_histogram(bins = 30, position = "identity", alpha = .55, colour = NA) +
  scale_fill_manual(values = CLASS_COL) +
  scale_x_continuous(trans = "log1p", breaks = c(0, 1, 3, 10, 30, 100, 300)) +
  scale_y_continuous(labels = label_number(scale_cut = cut_short_scale())) +
  facet_wrap(~ measure, scales = "free_y") +
  labs(title = "Distribution of key measures, operating facility-years 2015-2025",
       subtitle = paste0("x on log1p scale. ", DUP_NOTE),
       x = "count in a facility-year", y = "facility-years", fill = NULL) +
  theme(legend.position = "bottom", plot.subtitle = element_text(size = 8))
save_fig("dist_counts.png", g_dist, w = 10, h = 6.5)

g_ecdf <- ggplot(key_long, aes(x = count, colour = class)) +
  stat_ecdf(linewidth = .7) +
  scale_colour_manual(values = CLASS_COL) +
  scale_x_continuous(trans = "log1p", breaks = c(0, 1, 3, 10, 30, 100)) +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  facet_wrap(~ measure, scales = "free_x") +
  labs(title = "ECDF of key measures, operating facility-years 2015-2025",
       subtitle = paste0("the intercept at x=0 is the zero mass. ", DUP_NOTE),
       x = "count in a facility-year (log1p)", y = "cumulative share", colour = NULL) +
  theme(legend.position = "bottom", plot.subtitle = element_text(size = 8))
save_fig("ecdf_counts.png", g_ecdf, w = 10, h = 6.5)

# five-number summaries + zero share, carrying the _dup companions so event-distinct counts are recoverable
summ <- rbindlist(lapply(names(KEY_MEAS), function(m) {
  dupc <- paste0(m, "_dup")
  x <- d[[m]]
  data.table(measure = KEY_MEAS[m], class = "All", n = length(x),
             mean = mean(x), sd = sd(x), p50 = median(x), p90 = quantile(x, .9),
             p99 = quantile(x, .99), max = max(x), share_zero = mean(x == 0),
             total = sum(x), total_dup = if (dupc %in% names(d)) sum(d[[dupc]]) else NA_real_)
}))
summ_by <- rbindlist(lapply(names(KEY_MEAS), function(m) {
  dupc <- paste0(m, "_dup")
  d[, {
    x <- get(m)
    .(measure = KEY_MEAS[m], n = .N, mean = mean(x), sd = sd(x), p50 = median(x),
      p90 = quantile(x, .9), p99 = quantile(x, .99), max = max(x), share_zero = mean(x == 0),
      total = sum(x), total_dup = if (dupc %in% names(.SD)) sum(get(dupc)) else NA_real_)
  }, by = class]
}))
setcolorder(summ_by, c("measure", "class"))
out_summ <- rbind(summ, summ_by, use.names = TRUE)
num <- setdiff(names(out_summ), c("measure", "class"))
out_summ[, (num) := lapply(.SD, function(x) round(x, 4)), .SDcols = num]
fwrite(out_summ, file.path(OUT_CSV, "summary_counts.csv"))

# =========================================================================================================
# FIG 7 -- activity over time (mean events per operating facility-year)
# =========================================================================================================
act <- key_long[, .(mean_count = mean(count)), by = .(class, year, measure)]
fwrite(act[order(measure, class, year)], file.path(OUT_CSV, "activity_over_time.csv"))

g_act <- ggplot(act, aes(year, mean_count, colour = class)) +
  geom_line(linewidth = .8) +
  scale_colour_manual(values = CLASS_COL) +
  facet_wrap(~ measure, scales = "free_y") +
  scale_x_continuous(breaks = seq(2015, 2025, 2)) +
  labs(title = "Mean events per operating facility-year",
       subtitle = paste0("denominator is all operating facility-years (zeros included). ", DUP_NOTE),
       x = NULL, y = "mean count", colour = NULL) +
  theme(legend.position = "bottom", plot.subtitle = element_text(size = 8))
save_fig("activity_over_time.png", g_act, w = 10, h = 6)

# =========================================================================================================
# FIG 8 -- program enrollment (the YEAR-VARYING prog_*_active flags, not the static prog_* profile)
# =========================================================================================================
PROG <- c(prog_sip_active = "SIP", prog_titlev_active = "Title V", prog_nsps_active = "NSPS",
          prog_mact_active = "MACT", prog_neshap_active = "NESHAP", prog_fesop_active = "FESOP",
          prog_nsr_active = "NSR", prog_psd_active = "PSD")
prog <- melt(d[, c("class", names(PROG)), with = FALSE], id.vars = "class",
             variable.name = "program", value.name = "active")
prog <- prog[!is.na(active), .(share = mean(active), n = .N), by = .(class, program)]
prog[, program := factor(PROG[as.character(program)], levels = unname(PROG))]
fwrite(prog[order(program, class)], file.path(OUT_CSV, "program_enrollment.csv"))

g_prog <- ggplot(prog, aes(reorder(program, share), share, fill = class)) +
  geom_col(position = position_dodge(width = .8), width = .75) +
  coord_flip() +
  scale_fill_manual(values = CLASS_COL) +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  labs(title = "Program enrollment among operating facility-years, 2015-2025",
       subtitle = paste("year-varying prog_*_active flags from the wayback snapshots.",
                        "Title V is close to definitional for Major and near-absent for Synthetic Minor."),
       x = NULL, y = "% of operating facility-years enrolled", fill = NULL) +
  theme(legend.position = "bottom", plot.subtitle = element_text(size = 8))
save_fig("program_enrollment.png", g_prog, w = 9, h = 5.5)

# =========================================================================================================
# FIG 9 -- HPV status over time, and the nonzero penalty distribution
# =========================================================================================================
hpv <- d[!is.na(hpv_active), .(share_hpv = mean(hpv_active), n = .N), by = .(class, year)]
fwrite(hpv[order(class, year)], file.path(OUT_CSV, "hpv_by_year.csv"))

g9a <- ggplot(hpv, aes(year, share_hpv, colour = class)) +
  geom_line(linewidth = .8) + geom_point(size = 1.2) +
  scale_colour_manual(values = CLASS_COL) +
  scale_y_continuous(labels = percent_format(accuracy = .1), limits = c(0, NA)) +
  scale_x_continuous(breaks = YEARS) +
  labs(title = "Share of operating facility-years in high-priority-violator status",
       subtitle = "interval-derived hpv_active (P8); this flag alone keeps the dup==0 rule",
       x = NULL, y = "% in HPV status", colour = NULL) +
  theme(legend.position = "bottom", axis.text.x = element_text(angle = 45, hjust = 1),
        plot.subtitle = element_text(size = 8))

pen <- d[!is.na(penalty_amount) & penalty_amount > 0, .(class, penalty_amount)]
fwrite(pen[, .(n_facility_years = .N, total = sum(penalty_amount), median = median(penalty_amount),
                p90 = quantile(penalty_amount, .9), max = max(penalty_amount)), by = class],
       file.path(OUT_CSV, "penalty_summary.csv"))

g9b <- ggplot(pen, aes(penalty_amount, fill = class)) +
  geom_histogram(bins = 40, position = "identity", alpha = .55, colour = NA) +
  scale_fill_manual(values = CLASS_COL) +
  scale_x_log10(labels = label_dollar(scale_cut = cut_short_scale())) +
  scale_y_continuous(labels = comma) +
  labs(title = "Nonzero facility-year penalties",
       subtitle = sprintf(paste("n = %s facility-years with positive penalty dollars; max = %s.",
                                "penalty_amount is NA-when-none, so zeros are\nabsent by construction,",
                                "and it sums ALL formal rows (penalty_amount_dup holds the duplicate $)."),
                          comma(nrow(pen)), dollar(max(pen$penalty_amount))),
       x = "penalty amount (log scale)", y = "facility-years", fill = NULL) +
  theme(legend.position = "bottom", plot.subtitle = element_text(size = 8))

save_fig("hpv_and_penalties.png", g9a / g9b, w = 9, h = 9)

# =========================================================================================================
# FIG 10 -- industry mix (NAICS 2-digit sectors, facility grain)
# =========================================================================================================
# NAICS_CODES is a possibly multi-valued delimited string (CC7) -- take the FIRST code as the facility's
# primary sector rather than exploding the grain.
fac[, naics2 := substr(trimws(tstrsplit(NAICS_CODES, "[^0-9]")[[1]]), 1, 2)]
SECTOR <- c("11" = "Agriculture", "21" = "Mining & extraction", "22" = "Utilities",
            "23" = "Construction", "31" = "Manufacturing", "32" = "Manufacturing",
            "33" = "Manufacturing", "42" = "Wholesale trade", "44" = "Retail trade",
            "45" = "Retail trade", "48" = "Transport & warehousing", "49" = "Transport & warehousing",
            "51" = "Information", "52" = "Finance & insurance", "53" = "Real estate",
            "54" = "Professional services", "55" = "Management of companies",
            "56" = "Admin & waste services", "61" = "Education", "62" = "Health care",
            "71" = "Arts & recreation", "72" = "Accommodation & food", "81" = "Other services",
            "92" = "Public administration")
fac[, sector := fifelse(is.na(naics2) | naics2 == "", "No NAICS code",
                        fcoalesce(SECTOR[naics2], "Other / unclassified"))]

ind <- fac[, .N, by = .(class, sector)]
top <- ind[, .(tot = sum(N)), by = sector][order(-tot)][1:12, sector]
ind <- ind[sector %in% top]
fwrite(fac[, .N, by = .(class, sector)][order(-N)], file.path(OUT_CSV, "industry_mix.csv"))

g_ind <- ggplot(ind, aes(reorder(sector, N, sum), N, fill = class)) +
  geom_col(width = .75) +
  coord_flip() +
  scale_fill_manual(values = CLASS_COL) +
  scale_y_continuous(labels = comma) +
  labs(title = "Industry mix of operating facilities, top 12 sectors",
       subtitle = paste("NAICS 2-digit of the FIRST listed code, current ICIS snapshot applied to all",
                        "years (F2). One row per facility, not per facility-year."),
       x = NULL, y = "facilities", fill = NULL) +
  theme(legend.position = "bottom", plot.subtitle = element_text(size = 8))
save_fig("industry_mix.png", g_ind, w = 9, h = 6)

# =========================================================================================================
# FIG 11 -- Major / Synthetic Minor composition BY STATE
# ---------------------------------------------------------------------------------------------------------
# Added after the point map (fig 1) showed Texas essentially devoid of synthetic minors while its Major
# coverage looked normal. That is not an industrial fact -- it is a state classification/reporting artifact,
# and it is large: the synthetic-minor share of operating facilities runs from 3.7% (TX) to 94.9% (VT).
# Surfaced, NOT corrected: the Major/SynMin contrast in every other figure here is partly a comparison
# across state reporting regimes, which matters for any design that pools states.
# =========================================================================================================
st <- dcast(fac[, .N, by = .(STATE, class)], STATE ~ class, value.var = "N", fill = 0L)
setnames(st, CLASS_LEV, c("major", "synmin"))
st[, `:=`(total = major + synmin, synmin_share = synmin / (major + synmin))]
setorder(st, -synmin_share)
fwrite(st[, .(STATE, major, synmin, total, synmin_share = round(synmin_share, 4))],
       file.path(OUT_CSV, "class_composition_by_state.csv"))

st_plot <- st[total >= 100]                     # suppress tiny states where the share is noise
g_st <- ggplot(st_plot, aes(reorder(STATE, synmin_share), synmin_share)) +
  geom_col(fill = CLASS_COL[["Synthetic Minor"]], width = .75) +
  geom_hline(yintercept = fac[, mean(class == "Synthetic Minor")],
             linetype = "dashed", colour = "grey30") +
  coord_flip() +
  scale_y_continuous(labels = percent_format(accuracy = 1), limits = c(0, 1)) +
  labs(title = "Synthetic-minor share of operating facilities, by state",
       subtitle = paste("states with >=100 operating facilities; dashed line = national share.",
                        "The spread (TX 3.7% to VT 94.9%) is a state\nclassification/reporting artifact,",
                        "not an industrial one -- the Major/SynMin split is confounded with state regime."),
       x = NULL, y = "% synthetic minor") +
  theme(plot.subtitle = element_text(size = 8), axis.text.y = element_text(size = 7))
save_fig("class_composition_by_state.png", g_st, w = 8, h = 9)

cat(sprintf("wrote %d PNG figures to %s\n", length(list.files(OUT_FIG, "\\.png$")), OUT_FIG))
cat(sprintf("wrote %d CSV tabulations to %s\n", length(list.files(OUT_CSV, "\\.csv$")), OUT_CSV))
