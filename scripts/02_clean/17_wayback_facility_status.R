# =========================================================================================================
# scripts/02_clean/17_wayback_facility_status.R -- HISTORICAL facility operating status from the ICIS-AIR
#   WAYBACK snapshots (annual echo.epa.gov downloads captured Sep-Nov of each year, 2015-2025). One snapshot
#   = one panel year (the snapshot reflects the ~Q4 state of year Y). Reconstructs a facility x year status
#   series that the single current-snapshot AIR_OPERATING_STATUS lacks.
#   in : data/raw/ICIS_AIR_WAYBACK/ICIS-AIR_downloads_{2015..2025}/ICIS-AIR_FACILITIES.csv
#   out: data/clean/wayback_facility_status.csv.gz   (PGM_SYS_ID, year, op_status_code, op_status_desc, operating)
#
#   operating = 1 iff status in {OPR, TMP, SEA} (Operating / Temporarily Closed / Seasonal are all "in service"
#   per project decision); 0 for CLS/PLN/CNS/NER/NED/NES/LDF; NA where code is missing.
#   Interior gaps (facility absent from a MIDDLE snapshot but present before & after) are LOCF-filled within
#   the observed span [first_snap, last_snap]; ~0.3% of facility-programs, rarer for facilities. Years before
#   a facility's first snapshot or after its last are NOT emitted here (left/right edges handled downstream).
# =========================================================================================================
library(readr); library(dplyr); library(data.table)

RAW  <- here::here("data/raw/ICIS_AIR_WAYBACK")
SNAP_YEARS <- 2015:2025
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

status <- as_tibble(full) |>
  mutate(operating = if_else(is.na(op_status_code), NA_integer_,
                             as.integer(op_status_code %in% OPERATING_CODES))) |>
  arrange(PGM_SYS_ID, year)

dir.create(here::here("data/clean"), showWarnings = FALSE, recursive = TRUE)
write_csv(status, here::here("data/clean/wayback_facility_status.csv.gz"))
cat(sprintf("wayback_facility_status: %d facility-years | %d facilities | %d-%d | operating share %.3f\n",
            nrow(status), n_distinct(status$PGM_SYS_ID), min(status$year), max(status$year),
            mean(status$operating, na.rm = TRUE)))
