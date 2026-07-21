# =========================================================================================================
# code/04_datasets/02_operating.R -- DATASET 1: the operating dataset. Facility x year. Reconstructed
#   operating evidence that dataset 0 (regulatory) deliberately holds out: year-varying operating status,
#   program-active flags, facility entry/exit spells, and the earliest program-enrollment year.
#
#   in : data/processed/{wayback_facility_status,wayback_program_status,wayback_facility_spells,
#                         facilities,programs}.csv.gz
#   out: data/datasets/operating.csv.gz
#
#   UNIVERSE + GRAIN -- the SAME 279,211-facility x 2005-2025 rectangle as dataset 0, so operating.csv.gz
#     joins 1:1 to regulatory.csv.gz on (PGM_SYS_ID, YEAR). Wayback covers a LARGER facility set (292,040):
#     the 15,301 wayback-only facilities absent from ICIS-AIR_FACILITIES are DROPPED here -- this dataset is
#     keyed to the ICIS universe. The 2,472 ICIS facilities with no wayback spell get NA spell fields.
#
#   STRICTLY RAW -- NO imputation (per construction decision O2). Wayback status is a 2015-2025 reconstruction;
#     for 2005-2014, and for any facility-year not present in a wayback snapshot, operating status and the
#     prog_*_active flags are NA (unknown), never a coded 0/1. Entry/exit spells are carried as-is (with their
#     left/right censoring flags) at the facility level; the user decides downstream whether to extend status
#     across gaps. This mirrors dataset 0's zero-vs-NA discipline: we do not manufacture certainty wayback
#     lacks. `operating` itself is the cleaning layer's whitelist flag (OPR/TMP/SEA), carried unchanged.
# =========================================================================================================
library(readr); library(dplyr); library(tidyr); library(lubridate)
source(here::here("code/04_datasets/00_parameters.R"))

# ---- universe (identical to dataset 0) ------------------------------------------------------------------
ids <- read_csv(file.path(CLEAN, "facilities.csv.gz"),
                col_types = cols_only(PGM_SYS_ID = col_character()), show_col_types = FALSE)$PGM_SYS_ID
stopifnot("facilities: PGM_SYS_ID is not unique -- the facility grain is broken" = !anyDuplicated(ids))

# ---- year-varying wayback layers (2015-2025) ------------------------------------------------------------
# Facility operating status. `operating` = cleaning-layer whitelist (1 iff code in {OPR,TMP,SEA}); carried as-is.
status <- read_csv(file.path(CLEAN, "wayback_facility_status.csv.gz"),
                   col_types = cols(PGM_SYS_ID = col_character(), year = col_integer(),
                                    operating = col_integer(), .default = col_character()),
                   show_col_types = FALSE) |>
  select(PGM_SYS_ID, year, op_status_code, op_status_desc, operating)

# Program-active flags, PROGRAM-SPECIFIC active rule (N11) -- answers a different question than `operating`.
# Pinned to an explicit 8-group allowlist (sip/titlev/nsps/mact/neshap/fesop/nsr/psd) -- NOT gact/cfc, per
# decision. wayback_program_status.csv.gz carries 10 groups (gact, cfc were added upstream); reading it
# without col_select would silently absorb whatever columns that file happens to have, which is exactly how
# this dataset picked up gact/cfc unintentionally when the file was regenerated (see O3 correction note).
PROG_GROUPS <- c("sip", "titlev", "nsps", "mact", "neshap", "fesop", "nsr", "psd")
progst <- read_csv(file.path(CLEAN, "wayback_program_status.csv.gz"),
                   col_select = all_of(c("PGM_SYS_ID", "year", paste0("prog_", PROG_GROUPS, "_active"))),
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

# Earliest program-enrollment year: min BEGIN_DATE year across a facility's programs. BEGIN_DATE has no
#   matching end date (F6/N7), so only the ONSET is datable. NA where the facility has no program record or no
#   parseable BEGIN_DATE.
#   ~2.3% of source BEGIN_DATE years are IMPLAUSIBLE (e.g. `218`; 3,056 facilities dated entirely >2025). Since
#   the field is a MIN, one garbage-low date poisons a facility's earliest year. Per decision O5 we ship BOTH:
#     earliest_program_begin_year      -- min over years SCREENED to [BEGIN_YEAR_MIN, BEGIN_YEAR_MAX]
#     earliest_program_begin_year_raw  -- min over ALL parseable years, garbage included (fully traceable)
#   The screen is a validity filter on malformed source values, not imputation; neither is clipped to YEARS.
BEGIN_YEAR_MIN <- 1970L        # Clean Air Act -- no air-program enrollment plausibly predates it
BEGIN_YEAR_MAX <- 2025L        # analysis-window end -- 2026-2028 begin years are extract-impossible errors
begin <- read_csv(file.path(CLEAN, "programs.csv.gz"),
                  col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  mutate(byr = year(mdy(BEGIN_DATE, quiet = TRUE))) |>
  group_by(PGM_SYS_ID) |>
  summarise(
    earliest_program_begin_year_raw =
      { v <- byr[!is.na(byr)]; if (length(v)) min(v) else NA_integer_ },
    earliest_program_begin_year =
      { v <- byr[!is.na(byr) & byr >= BEGIN_YEAR_MIN & byr <= BEGIN_YEAR_MAX]
        if (length(v)) min(v) else NA_integer_ }, .groups = "drop")

# ---- assemble the rectangle -----------------------------------------------------------------------------
cat("building the facility x year rectangle...\n")
op <- expand_grid(PGM_SYS_ID = ids, year = YEARS) |>
  left_join(status, by = c("PGM_SYS_ID", "year")) |>                    # NA outside 2015-2025 / uncovered
  mutate(wayback_observed = as.integer(!is.na(op_status_code)), .after = year) |>
  left_join(progst, by = c("PGM_SYS_ID", "year")) |>
  left_join(spells, by = "PGM_SYS_ID") |>                              # facility-level, broadcast
  left_join(begin,  by = "PGM_SYS_ID") |>
  arrange(PGM_SYS_ID, year)

# ---- invariants -----------------------------------------------------------------------------------------
whitelist <- c("OPR", "TMP", "SEA")
stopifnot(
  "grain broken: PGM_SYS_ID x year is not unique"    = !anyDuplicated(op[c("PGM_SYS_ID", "year")]),
  "rectangle incomplete: rows != facilities x years" = nrow(op) == length(ids) * length(YEARS),
  "wayback leaked before 2015: operating is non-NA"  = !any(!is.na(op$operating) & op$year < 2015),
  "wayback_observed disagrees with op_status_code"   =
    all(op$wayback_observed == as.integer(!is.na(op$op_status_code))),
  "operating flag != whitelist(op_status_code)"      =
    all(op$operating == as.integer(op$op_status_code %in% whitelist), na.rm = TRUE) &&
    !any(is.na(op$operating) & !is.na(op$op_status_code)),
  "earliest_program_begin_year has Inf (bad min)"    =
    !any(is.infinite(op$earliest_program_begin_year)) && !any(is.infinite(op$earliest_program_begin_year_raw)),
  "screened begin year escaped [1970,2025]"          =
    all(op$earliest_program_begin_year >= BEGIN_YEAR_MIN & op$earliest_program_begin_year <= BEGIN_YEAR_MAX, na.rm = TRUE),
  "screened begin year < raw (screen only removes)"  =
    all(op$earliest_program_begin_year >= op$earliest_program_begin_year_raw, na.rm = TRUE))

write_dataset(op, "operating")                   # uppercases all columns on write (see 00_parameters.R)
cat(sprintf("operating: %s rows | %d cols | %s facilities | %s wayback-observed facility-years (%.1f%%)\n",
            format(nrow(op), big.mark = ","), ncol(op), format(length(ids), big.mark = ","),
            format(sum(op$wayback_observed), big.mark = ","), 100 * mean(op$wayback_observed)))
