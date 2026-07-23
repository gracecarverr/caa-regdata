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

status <- as_tibble(full) |>
  mutate(operating = if_else(is.na(op_status_code), NA_integer_,
                             as.integer(op_status_code %in% OPERATING_CODES))) |>
  arrange(PGM_SYS_ID, year)

dir.create(here::here("data/processed"), showWarnings = FALSE, recursive = TRUE)
write_csv(status, here::here("data/processed/wayback_facility_status.csv.gz"))
cat(sprintf("wayback_facility_status: %d facility-years | %d facilities | %d-%d | operating share %.3f\n",
            nrow(status), n_distinct(status$PGM_SYS_ID), min(status$year), max(status$year),
            mean(status$operating, na.rm = TRUE)))
