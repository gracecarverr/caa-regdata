# =========================================================================================================
# code/diagnostics/06b_panel_deep_stats.R -- panel-layer statistics that 06_panel_profile.R does not cover:
#   spine-level ever-active count (F1), reopen detection per panel (N9), coordinate-check gross/clean/NA
#   breakdown (N13), and the continuous-2015-2025 funnel (PR2). All four previously existed only as one-off
#   scratch computations behind panel_construction_decisions.md / panel_findings_summary.md -- added here as
#   a permanent, re-runnable script 2026-07-27 so those figures trace to a script, not an ad-hoc calculation.
#   Companion to 06_panel_profile.R (same discipline, different -- narrower, deeper -- set of stats).
#
#   in : data/panels/{spine,universe,major_synmin,electric}.csv.gz, data/processed/wayback_facility_status.csv.gz
#   out: output/panel_deep_stats/*.csv
#
#   Hand-run (not part of RUN_ALL.R). No stochastic step.
# =========================================================================================================
suppressPackageStartupMessages({library(data.table)})  # data.table only; suppress the load-time banner
options(scipen = 999)                                   # disable scientific notation in printed/console output

PANELS <- here::here("data/panels")                     # source dir for spine + the three built panels
CLEAN  <- here::here("data/processed")                  # source dir for the wayback facility-status history
OUT    <- here::here("output/panel_deep_stats")         # destination dir for this script's 4 output CSVs
dir.create(OUT, showWarnings = FALSE, recursive = TRUE) # create OUT if missing; silent if it already exists

# contiguous-US state/territory abbreviations (48 states + DC; excludes AK, HI, and all territories) --
# used throughout to restrict the national spine down to the panels' actual sampling frame
CONUS <- c("AL","AZ","AR","CA","CO","CT","DE","DC","FL","GA","ID","IL","IN","IA","KS","KY","LA","ME","MD",
           "MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH","OK","OR","PA","RI",
           "SC","SD","TN","TX","UT","VT","VA","WA","WV","WI","WY")
MAJOR_SYNMIN_CLASSES <- c("Major Emissions", "Synthetic Minor Emissions")  # the two classes that define the major_synmin panel

spine <- fread(file.path(PANELS, "spine.csv.gz"))       # one row per ever-active facility (filter already applied upstream in 00_spine.R)

# =========================================================================================================
# CSV 1 -- F1: spine ever-active facility count, before and after the contiguous-US filter
# =========================================================================================================
# FLAG: "ever-active" is not computed or verified here -- spine.csv.gz is already restricted to facilities
# with >=1 event across the 6 event assets in 2005-2025 (see 00_spine.R's "active universe" step). F1 simply
# counts rows of an input that is ever-active by upstream construction; it does not independently confirm it.
f1 <- data.table(n_spine_total = nrow(spine), n_spine_conus = spine[STATE %in% CONUS, .N])  # total spine rows vs. rows restricted to CONUS states
fwrite(f1, file.path(OUT, "f1_spine_ever_active.csv"))  # write CSV 1

# =========================================================================================================
# CSV 2 -- N13: coord_gross_error breakdown at the spine level (gross / clean / NA, with NA split into
#   no-coordinate vs. county-name-unresolvable)
# =========================================================================================================
# FLAG: unlike F1 (and unlike the three sample panels used everywhere else in this file), n_facilities here
# is the FULL NATIONAL spine -- no CONUS restriction. This breakdown describes coordinate quality for every
# ever-active facility nationwide, not for the (CONUS-only) universe/major_synmin/electric panel populations;
# a reader expecting this table's percentages to describe "the panels" would be reading a broader population.
n13 <- data.table(
  n_facilities = nrow(spine),                                    # denominator: ALL ever-active facilities, national (see FLAG above)
  n_gross      = spine[coord_gross_error == 1, .N],               # checkable AND >5km from ICIS-claimed county (see coord_county_flag.R)
  n_clean      = spine[coord_gross_error == 0, .N],               # checkable AND within 5km (or same county)
  n_na         = spine[is.na(coord_gross_error), .N],             # not checkable at all -- either no coordinate or an unresolvable county name
  n_na_no_coord      = spine[is.na(coord_gross_error) & is.na(latitude), .N],  # NA and no latitude at all -- the coordinate itself is missing
  # FLAG: "unresolvable" is inferred from !is.na(latitude) alone -- longitude isn't checked. If a facility has
  # latitude but a missing/unparseable longitude (both are read independently as as.numeric() in 00_spine.R,
  # so they can diverge), it would land here as "county-name-unresolvable" even though its coordinate pair is
  # actually incomplete, not merely unmatched to a county.
  n_na_unresolvable  = spine[is.na(coord_gross_error) & !is.na(latitude), .N])  # NA but has a latitude -- presumed county-name resolution failure
fwrite(n13, file.path(OUT, "n13_coord_check.csv"))       # write CSV 2

# =========================================================================================================
# Panel membership at the spine level (mirrors 03_build_parameters.R's PANEL_SPECS filters exactly -- must
# stay in sync with that file; a change there needs the same change here).
# =========================================================================================================
electric_filter <- function(s) s[STATE %in% CONUS & AIR_POLLUTANT_CLASS_DESC %in% MAJOR_SYNMIN_CLASSES &
                                 (grepl("(^|[^0-9])2211", NAICS_CODES) | grepl("(^|[^0-9])4911([^0-9]|$)", SIC_CODES))]
                                 # NAICS 2211 = Electric Power Generation/Transmission/Distribution; SIC 4911 = Electric Services
PANEL_IDS <- list(
  universe     = spine[STATE %in% CONUS, PGM_SYS_ID],                                              # all ever-active CONUS facilities
  major_synmin = spine[STATE %in% CONUS & AIR_POLLUTANT_CLASS_DESC %in% MAJOR_SYNMIN_CLASSES, PGM_SYS_ID],  # CONUS + major/synmin class only
  electric     = electric_filter(spine)$PGM_SYS_ID)                                                 # CONUS + major/synmin + electric-utility NAICS/SIC

# =========================================================================================================
# CSV 3 -- N9: reopen detection (operating -> CLS -> operating, 2015-2025 wayback snapshots), overall and
#   nested within each of the three sample panels
# =========================================================================================================
wb <- fread(file.path(CLEAN, "wayback_facility_status.csv.gz"),
           colClasses = list(character = "PGM_SYS_ID"))[order(PGM_SYS_ID, year)]  # load wayback status; force ID to character; sort by facility then year (order matters for the sequence build below)
# FLAG: !is.na(operating) DROPS unobserved years from the sequence entirely rather than keeping them as an
# explicit gap marker. The resulting `s` vector is ordered by calendar year but indexed only by POSITION among
# observed years -- a one-snapshot gap (a single missing wayback year) and a five-year gap collapse to the
# same "adjacent element" once the NAs are removed. has_reopen() below therefore detects "was operating, was
# later confirmed not-operating, was later confirmed operating again" with no minimum gap duration and no way
# to distinguish a momentary missing snapshot from a genuine multi-year closure.
reopen <- wb[, .(seq_op = list(operating[!is.na(operating)])), by = PGM_SYS_ID]  # per facility: ordered vector of observed 0/1 operating flags (NA years dropped, see FLAG above)
reopen[, has_reopen := sapply(seq_op, function(s) {
  if (length(s) < 3 || !any(s == 1)) return(FALSE)     # need >=3 observed points and at least one confirmed-operating point, else no reopen is possible
  first1 <- which(s == 1)[1]; last1 <- tail(which(s == 1), 1)  # position of the first and last confirmed-operating observation
  if (last1 <= first1 + 1) return(FALSE)               # first and last operating points are adjacent (or identical) -- no room for an intervening closure
  # FLAG: "0" here means "wayback code NOT in {OPR,TMP,SEA}" -- per 17_wayback_facility_status.R / 18_wayback_
  # facility_spells.R this covers CLS but also PLN, CNS, and other non-operating codes. The section header's
  # "operating -> CLS -> operating" is shorthand; the actual test is operating -> not-currently-operating
  # (any code) -> operating again, which is broader than literal CLS.
  any(s[(first1 + 1):(last1 - 1)] == 0)                # TRUE if any observation strictly between the first and last "1" reads as not-operating
})]
reopen_ids <- reopen[has_reopen == TRUE, PGM_SYS_ID]     # facility IDs with a detected reopen
n_ever_operating <- reopen[sapply(seq_op, function(s) any(s == 1)), .N]  # facilities with operating==1 at least once

# FLAG: n_denominator mixes two different populations across rows. For "all_ever_operating" it's
# n_ever_operating (only facilities that had a confirmed-operating wayback observation at least once -- the
# population actually eligible to register a reopen). For universe/major_synmin/electric it's
# length(PANEL_IDS$...) -- ALL facilities in that panel, including any with zero wayback "operating"
# observations (e.g. facilities absent from wayback, or active only pre-2015). Those non-eligible facilities
# dilute the panel-scoped "pct" rows relative to the "all_ever_operating" row, so the pct column is not on a
# consistent per-row basis even though it's presented as one column.
n9 <- data.table(
  scope = c("all_ever_operating", "universe", "major_synmin", "electric"),  # row labels, in output order
  n_reopen = c(length(reopen_ids),                                # all-scope reopen count
              sum(reopen_ids %in% PANEL_IDS$universe),             # reopen count restricted to the universe panel's facility IDs
              sum(reopen_ids %in% PANEL_IDS$major_synmin),         # reopen count restricted to the major_synmin panel
              sum(reopen_ids %in% PANEL_IDS$electric)),            # reopen count restricted to the electric panel
  n_denominator = c(n_ever_operating, length(PANEL_IDS$universe), length(PANEL_IDS$major_synmin), length(PANEL_IDS$electric)))  # see FLAG above -- denominators are NOT on a consistent basis across rows
n9[, pct := round(n_reopen / n_denominator, 4)]          # reopen rate per scope (inherits the denominator inconsistency flagged above)
fwrite(n9, file.path(OUT, "n9_reopen_detection.csv"))    # write CSV 3

# =========================================================================================================
# CSV 4 -- PR2: continuous-2015-2025 funnel (active every year 2015-2025 via any of the four core measures),
#   for each of the three sample panels
# =========================================================================================================
YEARS15 <- 2015:2025                                     # 11 years (2015 through 2025 inclusive) -- the wayback-covered window
cont_ids <- function(nm) {
  df <- fread(file.path(PANELS, paste0(nm, ".csv.gz")),
             colClasses = list(character = "PGM_SYS_ID"))[year %in% YEARS15]  # load one built panel, restrict rows to the 2015-2025 window
  # FLAG: `active` is built with `|` over four possibly-NA 0/1 flags, then summed with na.rm=TRUE below.
  # Under R's 3-valued logic, NA | TRUE = TRUE, but NA | FALSE = NA. This file's known-zero coding fills all
  # four any_* columns to 0 together for confirmed-operating/no-event rows, and leaves them NA together for
  # genuinely "unobserved" rows (obs_source == "unobserved") -- so a facility-year with all four any_* NA
  # yields active = NA, which na.rm=TRUE at the sum() step below then drops from n_active_years entirely. The
  # numeric effect is identical to a confirmed-zero-activity year: neither contributes to reaching the ==11
  # threshold. cont_ids() never restricts on obs_source, so "continuously active every year" cannot be told
  # apart from "active in every OBSERVED year, with any single missing wayback snapshot silently counted as a
  # failure" -- one unobserved year excludes a facility from n_continuous exactly as a confirmed-inactive year would.
  df[, active := (any_inspections == 1 | any_violations == 1 | any_enforcement == 1 | any_certs == 1)]  # 1 if any of the four core measures fired that facility-year
  df[, .(n_active_years = sum(active, na.rm = TRUE)), by = PGM_SYS_ID][n_active_years == length(YEARS15), PGM_SYS_ID]  # facility-level count of active years, kept only if active in all 11
}
pr2 <- data.table(panel = c("universe", "major_synmin", "electric"),
                  n_balanced   = sapply(c("universe", "major_synmin", "electric"), function(nm) length(PANEL_IDS[[nm]])),  # total facility count per panel (the balanced-panel population from spine)
                  n_continuous = sapply(c("universe", "major_synmin", "electric"), cont_ids) |> lengths())  # count of facilities passing the continuous-activity test per panel
fwrite(pr2, file.path(OUT, "pr2_continuous_funnel.csv"))  # write CSV 4

# =========================================================================================================
# console summary
# =========================================================================================================
cat("panel deep stats -- F1 / N9 / N13 / PR2\n")
cat("========================================\n\n")
cat("F1 -- spine ever-active facility count\n"); print(as.data.frame(f1), row.names = FALSE)  # print CSV 1 as a plain data frame
cat("\nN13 -- coord_gross_error breakdown (spine)\n"); print(as.data.frame(n13), row.names = FALSE)  # print CSV 2
cat("\nN9 -- reopen detection (operating -> CLS -> operating)\n"); print(as.data.frame(n9), row.names = FALSE)  # print CSV 3
cat("\nPR2 -- continuous 2015-2025 funnel\n"); print(as.data.frame(pr2), row.names = FALSE)  # print CSV 4

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# 1. (line ~39, f1) "Ever-active" is not computed or verified in this script -- spine.csv.gz already carries
#    that filter from 00_spine.R (>=1 event across 6 event assets, 2005-2025). F1 just counts rows of an
#    already-filtered input.
# 2. (line ~49, n13) n_facilities is the FULL NATIONAL spine, not CONUS-restricted, unlike every other
#    population used in this file (universe/major_synmin/electric are all CONUS-only). The coord-check
#    percentages describe a broader population than "the panels."
# 3. (line ~55, n_na_unresolvable) Classifies a row as "county-name-unresolvable" based on !is.na(latitude)
#    alone -- longitude isn't checked, so a facility with latitude present but longitude missing would be
#    miscounted here rather than as "no coordinate."
# 4. (line ~68, reopen) operating[!is.na(operating)] drops unobserved years entirely rather than marking them
#    as gaps, so the sequence used for reopen detection is ordered by calendar year but indexed by position
#    among observed years only. A one-year missing-snapshot gap and a five-year real closure both collapse to
#    "one non-operating element between two operating elements" -- reopen detection has no minimum gap
#    duration and cannot distinguish a data gap from a genuine closure.
# 5. (line ~78, has_reopen) The intervening "0" means "wayback code not in {OPR,TMP,SEA}," which includes CLS
#    but also PLN, CNS, and other non-operating codes (per 17_/18_wayback_*.R) -- broader than the section
#    header's "operating -> CLS -> operating" shorthand suggests.
# 6. (lines ~84-96, n9) n_denominator is not on a consistent basis across rows: "all_ever_operating" uses
#    n_ever_operating (facilities with >=1 confirmed-operating wayback observation -- the reopen-eligible
#    population), while universe/major_synmin/electric use the FULL panel facility count, including facilities
#    with zero wayback "operating" observations. The shared "pct" column therefore mixes two denominator
#    conventions.
# 7. (line ~112, cont_ids/active) `active` is built with `|` over four possibly-NA flags; na.rm=TRUE at the
#    subsequent sum() drops NA years (all-four-NA "unobserved" facility-years) the same way it drops confirmed
#    -zero years. cont_ids() never restricts on obs_source, so a facility missing a single wayback snapshot in
#    the 2015-2025 window is excluded from n_continuous identically to a facility confirmed inactive that year
#    -- "continuously active" and "continuously observed-and-active" are not distinguished.
