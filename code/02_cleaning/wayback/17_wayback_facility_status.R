# =========================================================================================================
# code/02_cleaning/wayback/17_wayback_facility_status.R -- HISTORICAL facility operating status from the ICIS-AIR
#   WAYBACK snapshots (annual echo.epa.gov downloads captured Sep-Nov of each year, 2015-2025 EXCEPT 2018 --
#   see below). One snapshot = one panel year (the snapshot reflects the ~Q4 state of year Y). Reconstructs a
#   facility x year status series that the single current-snapshot AIR_OPERATING_STATUS lacks.
#   in : data/raw/ICIS_AIR_WAYBACK/ICIS-AIR_downloads_{2015..2025 except 2018}/ICIS-AIR_FACILITIES.csv
#   out: data/processed/wayback_facility_status.csv.gz   (PGM_SYS_ID, year, op_status_code, op_status_desc, operating)
#
#   operating = 1 iff status in {OPR, TMP, SEA} (Operating / Temporarily Closed / Seasonal are all "in service"
#   per project decision); 0 for CLS/PLN/CNS/NER/NED/NES/LDF; NA where code is missing.
#
#   NO REAL 2018 SNAPSHOT EXISTS. The raw "2018" folder was byte-identical to 2019 across all 10 tables and
#   the Internet Archive has zero captures of the live ICIS-Air bulk download anywhere in the 2018 window --
#   it was a mislabeled duplicate, not a real archived snapshot, and was removed from data/raw/ (2026-07-21,
#   see the CAA_Project repo's briefs/panel/panel_construction_decisions.md N18/W7). 2018 is deliberately EXPLICIT NA (op_status_code,
#   op_status_desc, operating), NOT LOCF-filled like an ordinary interior gap -- an ordinary gap means one
#   facility happened to be missing from an otherwise-real snapshot; 2018 has no real snapshot for ANY
#   facility, so there is no evidence to infer from and none is asserted (per-project decision, matches the
#   W3 "no back-fill" treatment of pre-2015 years).
#   Interior gaps (facility absent from a MIDDLE snapshot but present before & after) are LOCF-filled within
#   the observed span [first_snap, last_snap]; ~0.3% of facility-programs, rarer for facilities. Years before
#   a facility's first snapshot or after its last are NOT emitted here (left/right edges handled downstream).
#
#   REVISED 2026-07-30 (explicit user decision, O2 exception): 2018's `operating` (NOT `op_status_code`/
#   `op_status_desc` -- see below) is now BRIDGE-IMPUTED for the one narrow case where 2017 and 2019 agree:
#   a facility with a REAL raw 2017 snapshot AND a REAL raw 2019 snapshot showing the SAME operating bucket
#   (both in-service {OPR,TMP,SEA}, or both not {CLS,PLN,CNS,NER,NED,NES,LDF}) gets that shared value imputed
#   into its 2018 row, flagged via the new `operating_imputed` column (1 for imputed rows, 0 everywhere else,
#   never NA). Mismatched pairs (e.g. operating in 2017, closed by 2019) are NOT touched -- that transition-
#   timing case is already handled deliberately by 18_wayback_facility_spells.R's "2017-op -> 2018-gap ->
#   2019-closed" exit-classification logic (W7), and this rule must not interfere with it.
#   "Real raw" means present in that year's ACTUAL ICIS-AIR_FACILITIES.csv snapshot -- NOT an LOCF-carried
#   value from an earlier year. Checked directly this session before deciding: interior-gap LOCF is
#   vanishingly rare (29 of 2,506,480 non-NA facility-years across the whole 2015-2025 window, 0.001%; only
#   14 of ~229,000 2017/2019 opr-opr/cls-cls-matching pairs involve an LOCF year at all) -- raw-only costs
#   essentially nothing and avoids compounding one imputation (LOCF) inside another (this bridge).
#   op_status_code/op_status_desc are DELIBERATELY LEFT NA for imputed rows -- we only know the coarse
#   in-service-vs-not bucket agreed on both sides, not which specific code applied in 2018, and fabricating
#   one would silently overstate precision. This also matters downstream: 18_wayback_facility_spells.R's
#   exit-transition classifier treats `!is.na(op_status_code)` as "real evidence" -- keeping it NA here means
#   an imputed row is invisible to that logic, so entry/exit spells are provably unaffected by this change
#   (verified this session by reading that script; also empirically diffed post-rebuild, see its README).
# =========================================================================================================
library(readr); library(dplyr); library(data.table)

RAW  <- here::here("data/raw/ICIS_AIR_WAYBACK")
SNAP_YEARS <- setdiff(2015:2025, 2018)   # no real 2018 snapshot exists -- see header note
OPERATING_CODES <- c("OPR", "TMP", "SEA")

read_snapshot <- function(y) {
  f <- file.path(RAW, sprintf("ICIS-AIR_downloads_%d", y), "ICIS-AIR_FACILITIES.csv")
  suppressWarnings(read_csv(f, col_select = c(PGM_SYS_ID, AIR_OPERATING_STATUS_CODE, AIR_OPERATING_STATUS_DESC),
                            col_types = cols(.default = col_character()), show_col_types = FALSE)) |>
    filter(!is.na(PGM_SYS_ID)) |>
    distinct(PGM_SYS_ID, .keep_all = TRUE) |>          # one row per facility per snapshot
    mutate(year = y)
}

snaps <- bind_rows(lapply(SNAP_YEARS, read_snapshot)) |>
  rename(op_status_code = AIR_OPERATING_STATUS_CODE, op_status_desc = AIR_OPERATING_STATUS_DESC)

# LOCF-fill interior gaps within each facility's observed span [first, last] (edges NOT extrapolated).
# data.table: densify each span with a vectorized sequence() then carry the last non-NA code forward.
dt   <- as.data.table(snaps)
span <- dt[, .(first = min(year), last = max(year)), by = PGM_SYS_ID]
grid <- span[rep(seq_len(.N), last - first + 1L)]
grid[, year := first + sequence(span[, last - first + 1L]) - 1L][, c("first","last") := NULL]
full <- dt[grid, on = c("PGM_SYS_ID","year")]                     # right-join: gap years -> NA rows
setorder(full, PGM_SYS_ID, year)
locf <- function(x) { i <- cummax(seq_along(x) * (!is.na(x))); x[ifelse(i == 0L, NA_integer_, i)] }  # leading NA stays NA
full[, `:=`(op_status_code = locf(op_status_code), op_status_desc = locf(op_status_desc)), by = PGM_SYS_ID]
# 2018 has NO real snapshot (unlike an ordinary sporadic per-facility gap) -- force it back to NA rather than
# LOCF-inferring it from 2017. Only touches rows that exist (facilities whose span crosses 2018); a facility
# with no span overlap never gets a 2018 row at all (same edge convention as pre-2015/post-2025).
full[year == 2018L, `:=`(op_status_code = NA_character_, op_status_desc = NA_character_)]

# ---- 2018 bridge imputation (operating bucket only; REAL raw 2017 & 2019 observations only) ---------------
# See the header note above for full rationale/verification. Built from `dt` -- the pre-LOCF, pre-densify
# stack (one row per facility per REAL snapshot year only) -- NOT `full`/`status` below, which mix in
# LOCF-carried and 2018-reset rows; using `dt` guarantees op2017/op2019 are always real observations, never
# an LOCF-carried value from an earlier year (per this session's raw-only decision).
op17 <- dt[year == 2017L, .(PGM_SYS_ID, op2017 = as.integer(op_status_code %in% OPERATING_CODES))]
op19 <- dt[year == 2019L, .(PGM_SYS_ID, op2019 = as.integer(op_status_code %in% OPERATING_CODES))]
bridge <- merge(op17, op19, by = "PGM_SYS_ID")[op2017 == op2019, .(PGM_SYS_ID, operating_bridge = op2017)]
  # only facilities with a REAL 2017 AND a REAL 2019 row survive the merge (inner join); of those, only
  # matching pairs (both operating, or both not) survive the op2017==op2019 filter -- mismatched pairs (a
  # real transition somewhere in [2017,2019]) are deliberately left out, per W7's existing handling of that
  # case (18_wayback_facility_spells.R).

status <- as_tibble(full) |>
  mutate(operating = if_else(is.na(op_status_code), NA_integer_,
                             as.integer(op_status_code %in% OPERATING_CODES))) |>
  left_join(bridge, by = "PGM_SYS_ID") |>
  mutate(
    # operating_imputed is 1 iff this is a 2018 row with no real snapshot (op_status_code NA, true for every
    # 2018 row at this point) AND the facility has a resolved bridge value -- 0 everywhere else, never NA.
    operating_imputed = as.integer(year == 2018L & is.na(op_status_code) & !is.na(operating_bridge)),
    operating          = if_else(operating_imputed == 1L, operating_bridge, operating)) |>
  select(-operating_bridge) |>
  arrange(PGM_SYS_ID, year)

stopifnot(
  "operating_imputed is NA somewhere (should always be a real 0/1)" = !anyNA(status$operating_imputed),
  "operating_imputed==1 row exists outside year 2018" =
    all(status$year[status$operating_imputed == 1L] == 2018L),
  "operating_imputed==1 row has a non-NA op_status_code (should never fabricate a specific code)" =
    all(is.na(status$op_status_code[status$operating_imputed == 1L])),
  "operating_imputed==1 row has NA operating (bridge should always resolve to a real 0/1)" =
    !anyNA(status$operating[status$operating_imputed == 1L]))

dir.create(here::here("data/processed"), showWarnings = FALSE, recursive = TRUE)
write_csv(status, here::here("data/processed/wayback_facility_status.csv.gz"))
cat(sprintf("wayback_facility_status: %d facility-years | %d facilities | %d-%d | operating share %.3f | %s 2018 rows bridge-imputed (opr-opr/cls-cls)\n",
            nrow(status), n_distinct(status$PGM_SYS_ID), min(status$year), max(status$year),
            mean(status$operating, na.rm = TRUE), format(sum(status$operating_imputed), big.mark = ",")))
