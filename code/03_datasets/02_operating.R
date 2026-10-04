# =========================================================================================================
# code/03_datasets/02_operating.R -- DATASET 1: the operating dataset. Facility x year. Reconstructed
#   operating evidence that dataset 0 (regulatory) deliberately holds out: year-varying operating status,
#   program-active flags, facility entry/exit spells, and the earliest program-enrollment year.
#
#   ALSO BUILDS (added this session, see briefs/datasets/dataset_construction_decisions.md for the full
#   rationale + probe counts):
#     (a) two YEAR-VARYING "how do we know this facility-year was real" indicators -- ACTIVE, ACTIVE_BROAD
#         -- appended as columns on this same operating.csv.gz rectangle. Per-year, not a facility-level
#         "ever" summary: each answers "in THIS specific year, do we have positive evidence this facility
#         was active," combining wayback + ICIS (+ emissions) signals at the (PGM_SYS_ID, year) grain.
#     (b) a small SEPARATE output, wayback_only_facilities.csv.gz, for the population Wayback has seen
#         operating at some point but that has since vanished from the current ICIS-AIR facility extract
#         entirely (O1a). Kept out of the main rectangle so the 1:1 join to regulatory.csv.gz stays exact.
#
#   in : data/processed/{wayback_facility_status,wayback_program_status,wayback_facility_spells,
#                         facilities,programs}.csv.gz
#        data/datasets/{regulatory,emissions}.csv.gz   (NEW -- for ACTIVE/ACTIVE_BROAD; both already built
#                         by the time this script runs, see RUN_ALL.R's datasets loop order)
#   out: data/datasets/operating.csv.gz
#        data/datasets/wayback_only_facilities.csv.gz  (NEW)
#
#   UNIVERSE + GRAIN -- the SAME 279,665-facility x 2005-2025 rectangle as dataset 0, so operating.csv.gz
#     joins 1:1 to regulatory.csv.gz on (PGM_SYS_ID, YEAR). Wayback covers a LARGER facility set (292,040):
#     the 15,302 wayback-only facilities absent from ICIS-AIR_FACILITIES are DROPPED from this rectangle
#     (kept intact, see (b) above) -- this main table stays keyed to the ICIS universe. The 2,927 ICIS
#     facilities with no wayback spell get NA spell fields.
#
#   STRICTLY RAW -- NO imputation (per construction decision O2). Wayback status is a 2015-2025 reconstruction;
#     for 2005-2014, and for any facility-year not present in a wayback snapshot, operating status and the
#     prog_*_active flags are NA (unknown), never a coded 0/1. Entry/exit spells are carried as-is (with their
#     left/right censoring flags) at the facility level; the user decides downstream whether to extend status
#     across gaps. This mirrors dataset 0's zero-vs-NA discipline: we do not manufacture certainty wayback
#     lacks. `operating` itself is the cleaning layer's whitelist flag (OPR/TMP/SEA), carried unchanged.
#
#   ACTIVE / ACTIVE_BROAD -- YEAR-VARYING (PGM_SYS_ID x year grain, same as every other column here), NOT a
#   facility-level "ever" summary. Each answers "in THIS year, do we have positive evidence the facility was
#   active," from increasingly broad evidence, and each keeps the 0-vs-NA discipline (0 = positive evidence
#   of non-activity from every signal checked THAT YEAR; NA = at least one signal had no way to say either
#   way that year):
#     (tier 1 is just the existing `operating` column above -- wayback's own per-year whitelist flag. No new
#     column needed for it; ACTIVE/ACTIVE_BROAD both build on top of it.)
#     ACTIVE        -- operating==1 OR ICIS_OBSERVED==1 THAT YEAR (from regulatory.csv.gz). Closes wayback's
#                      blind spot before 2015: ICIS_OBSERVED is the only one of these signals with full
#                      2005-2025 coverage (wayback is 2015-2025 only). ICIS_OBSERVED is never NA for any
#                      facility-year in regulatory.csv.gz's own rectangle (which shares this exact universe +
#                      window, O1), so ACTIVE is NA only in years where `operating` is NA (pre-2015, or a
#                      wayback coverage gap) AND ICIS_OBSERVED==0 that specific year -- i.e. neither signal
#                      has anything to say about that particular year. A probe this session (2026-07-28,
#                      whole-window / "ever" framing, drifts with any live ICIS-AIR refresh) found: of
#                      133,753 facilities with >=1 ICIS event somewhere in 2005-2025, 15,699 (11.7%, mostly
#                      11,029 active ONLY pre-2015) have NO wayback-confirmed operating year at all --
#                      exactly the population this per-year union recovers, year by year. Conversely wayback
#                      alone catches 92,080 facilities with zero ICIS events ever (never-inspected minor
#                      sources) -- recovered here too, for whichever years wayback shows them operating.
#     ACTIVE_BROAD  -- ACTIVE==1 OR EMISSIONS_OBSERVED==1 OR GHG_OBSERVED==1 THAT YEAR (from emissions.csv.gz).
#                      Both emissions flags are never NA for any facility-year in emissions.csv.gz's own
#                      rectangle (EM3), so this tier can only ever promote a NA ACTIVE up to 1 for that year,
#                      never introduce a new NA. Probe this session (whole-window framing): adds 15,889 more
#                      facilities beyond wayback+ICIS at least once somewhere in 2005-2025. Pipeline (dataset
#                      6) was checked too and added ZERO facilities beyond ICIS (it's derived from linked
#                      ICIS evaluations, so fully subsumed) -- not used as a tier.
#   Column names are the working recommendation from this session's design discussion, not load-bearing --
#   easy to rename later. Deliberately NOT called *_ACTIVE to avoid reading like the PROG_*_ACTIVE wayback
#   flags above, which answer a completely different question (program enrollment that year, not facility
#   existence/activity) -- see FLAGGED ISSUES #4.
# =========================================================================================================
library(readr); library(dplyr); library(tidyr); library(lubridate)
source(here::here("code/03_datasets/00_parameters.R"))

# ---- universe (identical to dataset 0) ------------------------------------------------------------------
frs_ids <- read_csv(file.path(CLEAN, "facilities.csv.gz"),
                    col_types = cols_only(PGM_SYS_ID = col_character(), REGISTRY_ID = col_character()),
                    show_col_types = FALSE)
                    # REVIEW(naming): despite the name, this reads the CLEANED ICIS "facilities" table (the
                    # same source 01_regulatory.R calls `attrs`), NOT FRS_FACILITIES.csv (the actual FRS
                    # source, used elsewhere for coordinates) -- `frs_ids` is a misleading name for what's
                    # really the ICIS facility-ID universe; easy to misread as "facilities present in FRS"
ids <- frs_ids$PGM_SYS_ID                              # the same 279,665-facility ICIS universe as dataset 0
stopifnot("facilities: PGM_SYS_ID is not unique -- the facility grain is broken" = !anyDuplicated(ids))

# ---- year-varying wayback layers (2015-2025) ------------------------------------------------------------
# Facility operating status. `operating` = cleaning-layer whitelist (1 iff code in {OPR,TMP,SEA}); carried as-is.
# `operating_imputed` (NEW 2026-07-30, O2 exception): 1 iff this row's `operating` was 2018-bridge-imputed
# from matching real 2017/2019 observations (17_wayback_facility_status.R), 0 otherwise, never NA -- explicit
# col_integer() rather than letting .default = col_character() catch it, matching this script's no-col_guess()
# discipline elsewhere in the file.
status <- read_csv(file.path(CLEAN, "wayback_facility_status.csv.gz"),
                   col_types = cols(PGM_SYS_ID = col_character(), year = col_integer(),
                                    operating = col_integer(), operating_imputed = col_integer(),
                                    .default = col_character()),
                   show_col_types = FALSE) |>
  select(PGM_SYS_ID, year, op_status_code, op_status_desc, operating, operating_imputed)
  # NOTE: `status` is read ONCE here and reused TWICE below -- once (implicitly restricted to `ids` via the
  # left_join into the main rectangle) to build operating.csv.gz, and again (restricted to the COMPLEMENT of
  # `ids`) further down to build wayback_only_facilities.csv.gz. Reading it once and slicing both ways avoids
  # a second, redundant read of the same 2015-2025 snapshot file.

# Program-active flags, PROGRAM-SPECIFIC active rule (N11) -- answers a different question than `operating`.
# Pinned to an explicit 8-group allowlist (sip/titlev/nsps/mact/neshap/fesop/nsr/psd) -- NOT gact/cfc, per
# decision. wayback_program_status.csv.gz carries 10 groups (gact, cfc were added upstream); reading it
# without col_select would silently absorb whatever columns that file happens to have, which is exactly how
# this dataset picked up gact/cfc unintentionally when the file was regenerated (see O3 correction note).
PROG_GROUPS <- c("sip", "titlev", "nsps", "mact", "neshap", "fesop", "nsr", "psd")
progst <- read_csv(file.path(CLEAN, "wayback_program_status.csv.gz"),
                   col_select = all_of(c("PGM_SYS_ID", "year", paste0("prog_", PROG_GROUPS, "_active"))),
                   # explicit col_select is the actual guardrail here -- it's what keeps gact/cfc out even
                   # though the source file still carries them, rather than relying on anyone remembering to
                   # filter them post-hoc
                   col_types = cols(PGM_SYS_ID = col_character(), year = col_integer(),
                                    .default = col_integer()), show_col_types = FALSE)

# ---- facility-level layers (time-invariant, broadcast to all years) -------------------------------------
# Entry/exit spells. exit_source: cls (confirmed closure) | dropout (last seen operating then vanished; an
#   UPPER bound on unexplained exits, N8) | other | NA (no exit observed). Left/right censored at window edges.
spells <- read_csv(file.path(CLEAN, "wayback_facility_spells.csv.gz"),
                   col_types = cols(PGM_SYS_ID = col_character(), entered_year = col_integer(),
                                    exited_year = col_integer(), exit_source = col_character(),
                                    left_censored = col_integer(), right_censored = col_integer()),
                   show_col_types = FALSE)
  # like `status` above, `spells` covers Wayback's full ~292,040-facility roster -- reused below (restricted
  # to the ICIS-universe complement) for wayback_only_facilities.csv.gz, no second read needed.

# Earliest program-enrollment year: min BEGIN_DATE year across a facility's programs. BEGIN_DATE has no
#   matching end date (F6/N7), so only the ONSET is datable. NA where the facility has no program record or no
#   parseable BEGIN_DATE.
#   ~2.63% of source BEGIN_DATE years are IMPLAUSIBLE (e.g. `218`; 4,088 facilities dated entirely >2025). Since
#   the field is a MIN, one garbage-low date poisons a facility's earliest year. Per decision O5 we ship BOTH:
#     earliest_program_begin_year      -- min over years SCREENED to [BEGIN_YEAR_MIN, BEGIN_YEAR_MAX]
#     earliest_program_begin_year_raw  -- min over ALL parseable years, garbage included (fully traceable)
#   The screen is a validity filter on malformed source values, not imputation; neither is clipped to YEARS.
BEGIN_YEAR_MIN <- 1970L        # Clean Air Act -- no air-program enrollment plausibly predates it
BEGIN_YEAR_MAX <- 2025L        # analysis-window end -- 2026-2028 begin years are extract-impossible errors
                                # REVIEW(design): a separate hardcoded literal from YEARS (00_parameters.R),
                                # not derived as max(YEARS) -- happens to match today, but the two would
                                # silently diverge if the analysis window is ever extended without also
                                # updating this constant
begin <- read_csv(file.path(CLEAN, "programs.csv.gz"),
                  col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  mutate(byr = year(mdy(BEGIN_DATE, quiet = TRUE))) |>  # parse to Date then take calendar year; unparseable -> NA
  group_by(PGM_SYS_ID) |>
  summarise(
    earliest_program_begin_year_raw =
      { v <- byr[!is.na(byr)]; if (length(v)) min(v) else NA_integer_ },   # unscreened min -- garbage included
    earliest_program_begin_year =
      { v <- byr[!is.na(byr) & byr >= BEGIN_YEAR_MIN & byr <= BEGIN_YEAR_MAX]
        if (length(v)) min(v) else NA_integer_ }, .groups = "drop")        # screened min -- validity-filtered

# ---- NEW: year-varying ACTIVE / ACTIVE_BROAD inputs ------------------------------------------------------
# ICIS_OBSERVED, per (PGM_SYS_ID, year), straight from dataset 0 -- NOT collapsed to a facility-level summary.
# regulatory.csv.gz shares this dataset's exact 279,665-facility x 2005-2025 rectangle (O1), so this join
# below is guaranteed to match every row in `op` -- no row in `op` should ever end up with icis_observed NA
# (checked explicitly in the invariants section further down).
icis_yr <- read_csv(file.path(DATASETS, "regulatory.csv.gz"),             # data/datasets/regulatory.csv.gz
                    col_select = c(PGM_SYS_ID, YEAR, ICIS_OBSERVED),        # only what's needed for ACTIVE
                    col_types = cols(PGM_SYS_ID = col_character(), YEAR = col_integer(),
                                     ICIS_OBSERVED = col_integer()), show_col_types = FALSE) |>
  rename(year = YEAR, icis_observed = ICIS_OBSERVED)                       # back to this file's lowercase convention

# EMISSIONS_OBSERVED / GHG_OBSERVED, per (PGM_SYS_ID, year), straight from dataset 7 (built BEFORE this
# script now -- see RUN_ALL.R's datasets loop order, changed this session specifically to make this read
# safe). Same "shares this dataset's exact rectangle" guarantee as icis_yr above (EM3).
em_yr <- read_csv(file.path(DATASETS, "emissions.csv.gz"),                # data/datasets/emissions.csv.gz
                  col_select = c(PGM_SYS_ID, YEAR, EMISSIONS_OBSERVED, GHG_OBSERVED),
                  col_types = cols(PGM_SYS_ID = col_character(), YEAR = col_integer(),
                                   EMISSIONS_OBSERVED = col_integer(), GHG_OBSERVED = col_integer()),
                  show_col_types = FALSE) |>
  rename(year = YEAR, emissions_observed = EMISSIONS_OBSERVED, ghg_observed = GHG_OBSERVED)

# ---- assemble the rectangle -----------------------------------------------------------------------------
cat("building the facility x year rectangle...\n")
op <- expand_grid(PGM_SYS_ID = ids, year = YEARS) |>
  left_join(status, by = c("PGM_SYS_ID", "year")) |>                    # NA outside 2015-2025 / uncovered
  mutate(wayback_observed = as.integer(!is.na(op_status_code)), .after = year,
         # `status`'s left_join leaves operating_imputed NA for years outside 2015-2025 (no match at all,
         # not "checked and 0") -- coalesced to 0 here since it's a "was THIS row bridge-imputed" flag, never
         # meaningfully NA (unlike operating/op_status_code, which stay genuinely NA pre-2015 by design, O2).
         operating_imputed = coalesce(operating_imputed, 0L)) |>
  left_join(progst, by = c("PGM_SYS_ID", "year")) |>
  left_join(spells, by = "PGM_SYS_ID") |>                              # facility-level, broadcast
  left_join(begin,  by = "PGM_SYS_ID") |>
  left_join(icis_yr, by = c("PGM_SYS_ID", "year")) |>                  # NEW: year-varying (see above)
  left_join(em_yr,   by = c("PGM_SYS_ID", "year")) |>                  # NEW: year-varying (see above)
  mutate(
    # ACTIVE: union of `operating` (wayback, this year) and `icis_observed` (ICIS, this year). `|` on logical-
    # like integers propagates NA the way we want: NA|1 = 1 (an ICIS event this year wins over an unknown
    # wayback status), NA|0 = NA (no ICIS event this year AND wayback has nothing to say -> genuinely unknown).
    active = case_when(
      operating == 1 | icis_observed == 1 ~ 1L,
      operating == 0 & icis_observed == 0 ~ 0L,
      TRUE                                ~ NA_integer_),
    # ACTIVE_BROAD: union of ACTIVE (just computed) and the two emissions signals, same year.
    active_broad = case_when(
      active == 1 | emissions_observed == 1 | ghg_observed == 1 ~ 1L,
      active == 0 & emissions_observed == 0 & ghg_observed == 0 ~ 0L,
      TRUE                                                      ~ NA_integer_)) |>
  left_join(frs_ids, by = "PGM_SYS_ID") |> relocate(REGISTRY_ID, .after = PGM_SYS_ID) |>
  arrange(PGM_SYS_ID, year)

# ---- invariants -----------------------------------------------------------------------------------------
whitelist <- c("OPR", "TMP", "SEA")
stopifnot(
  "grain broken: PGM_SYS_ID x year is not unique"    = !anyDuplicated(op[c("PGM_SYS_ID", "year")]),
  "rectangle incomplete: rows != facilities x years" = nrow(op) == length(ids) * length(YEARS),
  "wayback leaked before 2015: operating is non-NA"  = !any(!is.na(op$operating) & op$year < 2015),
  "wayback_observed disagrees with op_status_code"   =
    all(op$wayback_observed == as.integer(!is.na(op$op_status_code))),
  # REVISED 2026-07-30 (O2 exception): restricted to operating_imputed==0 rows -- a bridge-imputed row's
  # `operating` is, by construction, NOT derivable from its (NA) op_status_code, so it's correctly exempted
  # here rather than weakening the check for everyone else. The 3 new checks below cover imputed rows instead.
  "operating flag != whitelist(op_status_code) (non-imputed rows)" = {
    idx <- which(op$operating_imputed == 0L)
    all(op$operating[idx] == as.integer(op$op_status_code[idx] %in% whitelist), na.rm = TRUE) &&
      !any(is.na(op$operating[idx]) & !is.na(op$op_status_code[idx]))
  },
  "operating_imputed is NA somewhere (should always be a real 0/1)" = !anyNA(op$operating_imputed),
  "operating_imputed==1 row exists outside year 2018" =
    all(op$year[op$operating_imputed == 1L] == 2018L),
  "operating_imputed==1 row has a non-NA op_status_code (should never fabricate a specific code) or NA operating" = {
    idx <- which(op$operating_imputed == 1L)
    all(is.na(op$op_status_code[idx])) && !anyNA(op$operating[idx])
  },
  "earliest_program_begin_year has Inf (bad min)"    =
    !any(is.infinite(op$earliest_program_begin_year)) && !any(is.infinite(op$earliest_program_begin_year_raw)),
  "screened begin year escaped [1970,2025]"          =
    all(op$earliest_program_begin_year >= BEGIN_YEAR_MIN & op$earliest_program_begin_year <= BEGIN_YEAR_MAX, na.rm = TRUE),
  "screened begin year < raw (screen only removes)"  =
    all(op$earliest_program_begin_year >= op$earliest_program_begin_year_raw, na.rm = TRUE),
  # NEW: icis_observed / emissions_observed / ghg_observed must NEVER be NA anywhere in `op` -- both source
  # datasets share this exact (PGM_SYS_ID, year) universe (O1, EM3), so a join miss here would mean the two
  # layers' universes have silently drifted apart, not a normal "unobserved" case.
  "icis_observed is NA somewhere -- regulatory.csv.gz's universe no longer matches this dataset's" =
    !any(is.na(op$icis_observed)),
  "emissions_observed/ghg_observed is NA somewhere -- emissions.csv.gz's universe no longer matches" =
    !any(is.na(op$emissions_observed)) && !any(is.na(op$ghg_observed)),
  # NEW: ACTIVE / ACTIVE_BROAD must be a monotonic nesting, PER ROW (this is now a year-varying measure, so
  # the check is row-by-row, not facility-by-facility): operating==1 => active==1 => active_broad==1. Written
  # via which() (drops NA indices automatically) rather than a raw `==`/`!=` comparison across the whole
  # vector -- a plain `op$operating == 1 & op$active != 1` would itself evaluate to NA (not FALSE) on any row
  # where active is NA, and any(<vector with an NA, no TRUE>) returns NA, not FALSE, silently breaking the
  # whole stopifnot() with an unrelated "tier nesting broken" false alarm.
  "operating==1 but active!=1 in some row (tier nesting broken)" = {
    idx <- which(op$operating == 1)                                    # only real TRUE matches, NA dropped
    all(!is.na(op$active[idx])) && all(op$active[idx] == 1)
  },
  "active==1 but active_broad!=1 in some row (tier nesting broken)" = {
    idx <- which(op$active == 1)
    all(!is.na(op$active_broad[idx])) && all(op$active_broad[idx] == 1)
  },
  "operating==0 but active is NA in some row (a confirmed-0 tier collapsing to unknown at the next tier)" = {
    idx <- which(op$operating == 0)
    all(!is.na(op$active[idx]))
  })
    # this last check would only fail if the case_when logic above had a bug -- icis_observed is always a
    # real 0/1 for every row (see the two invariants just above), so operating==0 must always resolve active
    # to a real 0 or 1, never NA

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# 1. (frs_ids, ~line 26) Despite the name, this reads the CLEANED ICIS "facilities" table (the same source
#    01_regulatory.R calls `attrs`), NOT FRS_FACILITIES.csv (the actual FRS source, used in 06_coordinates.R)
#    -- a misleading name for what's really the ICIS facility-ID universe; easy to misread as "facilities
#    present in FRS". Same note applies to 03_hpv_spells.R and 05_penalties.R's identically-named reads.
# 2. (BEGIN_YEAR_MAX, ~line 76) A separate hardcoded literal from YEARS (00_parameters.R), not derived as
#    max(YEARS) -- happens to match today, but the two would silently diverge if the analysis window is ever
#    extended without also updating this constant. Same pattern as DZ_MAX in 04_hpv_active.R.
# 3. (icis_yr / em_yr, NEW) This script now reads data/datasets/regulatory.csv.gz and
#    data/datasets/emissions.csv.gz -- two NEW cross-dataset dependencies that didn't exist before this
#    session. RUN_ALL.R's datasets loop was changed from a plain 1:8 numeric sequence to an explicit ordered
#    vector to guarantee both build before this script runs. If this script is ever sourced standalone (not
#    via RUN_ALL.R) without those two files already present on disk, the reads above error with a plain
#    "file not found," not silently produce garbage -- the same tradeoff every other cross-dataset read in
#    this layer already makes (e.g. 04_hpv_active.R already depends on regulatory.csv.gz existing first).
# 4. (ACTIVE / ACTIVE_BROAD, NEW) Column names are this session's working recommendation, not a settled
#    convention -- flagged in case a future pass renames them. Deliberately avoided an *_ACTIVE suffix
#    pattern matching PROG_*_ACTIVE (a different, program-enrollment-specific concept already in this same
#    table) to reduce the chance of the two being confused.
# 5. (wayback_only_facilities.csv.gz, NEW, see below) Deliberately carries NO active/active_broad columns of
#    its own -- see that section's own comment for why.
# =========================================================================================================

write_dataset(op, "operating")                   # uppercases all columns on write (see 00_parameters.R)
cat(sprintf("operating: %s rows | %d cols | %s facilities | %s wayback-observed facility-years (%.1f%%)\n",
            format(nrow(op), big.mark = ","), ncol(op), format(length(ids), big.mark = ","),
            format(sum(op$wayback_observed), big.mark = ","), 100 * mean(op$wayback_observed)))
cat(sprintf("  ACTIVE=1: %s facility-years | ACTIVE_BROAD=1: %s facility-years (of %s total facility-years)\n",
            format(sum(op$active == 1, na.rm = TRUE), big.mark = ","),
            format(sum(op$active_broad == 1, na.rm = TRUE), big.mark = ","),
            format(nrow(op), big.mark = ",")))

# =========================================================================================================
# NEW: wayback_only_facilities.csv.gz -- the population Wayback has seen operating at some point that has
#   since vanished from the current ICIS-AIR facility extract entirely (O1a). Kept as a SEPARATE output
#   (not folded into `op` above) so operating.csv.gz's 1:1 join to regulatory.csv.gz stays exact -- these
#   facilities have NO regulatory.csv.gz counterpart to join to (confirmed 0/15,302 have any ICIS event
#   record at all, checked directly this session), so mixing them into the same rectangle would mean every
#   ICIS-sourced column is permanently NA for them, for a structurally different reason than the normal
#   "unobserved" NA everywhere else in this dataset (there, absence just means no evidence either way; here,
#   there is NO possible evidence, because these facilities aren't in the source ICIS extract at all).
# =========================================================================================================
cat("building wayback_only_facilities (roster-vanished population)...\n")

WAYBACK_YEARS <- 2015:2025          # Wayback's REAL coverage window -- deliberately narrower than this
                                      # layer's standard YEARS (2005:2025, G1). These facilities have ZERO
                                      # information of any kind before 2015 (no wayback snapshot existed yet,
                                      # and by definition no ICIS record either), so a 2005-2025 rectangle
                                      # would just be ten years of guaranteed-100%-NA padding -- a deliberate,
                                      # flagged exception to the layer-wide G1 window convention, not an
                                      # oversight.

wb_all_ids <- unique(status$PGM_SYS_ID)             # every facility Wayback has EVER captured a status row for
wb_only_ids <- setdiff(wb_all_ids, ids)              # ... minus the ones still on the CURRENT ICIS roster
                                                      # (`ids`, defined at the top of this script) -- the
                                                      # complement is the roster-vanished population (O1a)

wb_only <- expand_grid(PGM_SYS_ID = wb_only_ids, year = WAYBACK_YEARS) |>   # balanced rectangle over
                                                                             # Wayback's own coverage window
  left_join(status |> select(PGM_SYS_ID, year, op_status_code, op_status_desc, operating, operating_imputed),
           by = c("PGM_SYS_ID", "year")) |>          # same year-varying status block as the main table
  mutate(wayback_observed = as.integer(!is.na(op_status_code)), .after = year,
         # same reasoning as the main `op` rectangle above: `status` only carries rows within each facility's
         # OWN observed span (17_wayback_facility_status.R), but this rectangle spans the full 2015-2025
         # WAYBACK_YEARS regardless -- years outside a given facility's span left_join-miss and need the same
         # NA -> 0 coalesce (operating_imputed is a per-row "was this bridged" flag, never meaningfully NA).
         operating_imputed = coalesce(operating_imputed, 0L)) |>   # same pattern as `op` above
  left_join(spells, by = "PGM_SYS_ID") |>              # same facility-level spell block as the main table
  arrange(PGM_SYS_ID, year)
  # deliberately NO active/active_broad columns here -- ICIS_OBSERVED and EMISSIONS_OBSERVED/GHG_OBSERVED
  # are both structurally undefined for this population (they have no row in regulatory.csv.gz or
  # emissions.csv.gz to look up at all, not merely a 0), so any such column would either be all-NA
  # (uninformative) or wrongly implied to be a real 0 -- left out entirely rather than shipping a column
  # that can only ever be misread.

# ---- invariants (wayback_only_facilities) ----------------------------------------------------------------
stopifnot(
  "wayback_only: grain broken: PGM_SYS_ID x year is not unique" =
    !anyDuplicated(wb_only[c("PGM_SYS_ID", "year")]),
  "wayback_only: rectangle incomplete: rows != facilities x years" =
    nrow(wb_only) == length(wb_only_ids) * length(WAYBACK_YEARS),
  "wayback_only: a facility here IS present in the current ICIS roster (should be the exact complement)" =
    !any(wb_only$PGM_SYS_ID %in% ids),
  "wayback_only: wayback_observed disagrees with op_status_code" =
    all(wb_only$wayback_observed == as.integer(!is.na(wb_only$op_status_code))),
  # REVISED 2026-07-30 (O2 exception), same treatment as the main `op` rectangle above -- restricted to
  # operating_imputed==0 rows, with 3 companion checks for the imputed ones.
  "wayback_only: operating flag != whitelist(op_status_code) (non-imputed rows)" = {
    idx <- which(wb_only$operating_imputed == 0L)
    all(wb_only$operating[idx] == as.integer(wb_only$op_status_code[idx] %in% whitelist), na.rm = TRUE) &&
      !any(is.na(wb_only$operating[idx]) & !is.na(wb_only$op_status_code[idx]))
  },
  "wayback_only: operating_imputed is NA somewhere" = !anyNA(wb_only$operating_imputed),
  "wayback_only: operating_imputed==1 row exists outside year 2018" =
    all(wb_only$year[wb_only$operating_imputed == 1L] == 2018L),
  "wayback_only: operating_imputed==1 row has a non-NA op_status_code or NA operating" = {
    idx <- which(wb_only$operating_imputed == 1L)
    all(is.na(wb_only$op_status_code[idx])) && !anyNA(wb_only$operating[idx])
  })

write_dataset(wb_only, "wayback_only_facilities")   # uppercases all columns on write (see 00_parameters.R)
cat(sprintf("wayback_only_facilities: %s rows | %d cols | %s facilities (0 overlap with the ICIS roster) | %s wayback-observed facility-years\n",
            format(nrow(wb_only), big.mark = ","), ncol(wb_only), format(length(wb_only_ids), big.mark = ","),
            format(sum(wb_only$wayback_observed), big.mark = ",")))
