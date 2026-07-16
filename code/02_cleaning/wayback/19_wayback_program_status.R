# =========================================================================================================
# code/02_cleaning/wayback/19_wayback_program_status.R -- HISTORICAL program status from the ICIS-AIR WAYBACK
#   snapshots (2015-2025). The raw PROGRAMS table has an unreliable BEGIN_DATE and NO program-close date;
#   we instead reconstruct a facility x year "is this program active?" series from snapshot PRESENCE +
#   operating status. Covers the 8 program groups already flagged in the spine.
#   in : data/raw/ICIS_AIR_WAYBACK/ICIS-AIR_downloads_{2015..2025}/{ICIS-AIR_FACILITIES,ICIS-AIR_PROGRAMS}.csv
#   out: data/processed/wayback_program_status.csv.gz
#        PGM_SYS_ID, year, prog_{sip,titlev,nsps,mact,neshap,fesop,nsr,psd}_active
#
#   prog_X_active in a given snapshot year = 1 iff the facility carries >=1 program in group X whose status is
#   NOT Permanently-Closed (CLS); 0 if the facility is present in that snapshot but the group is absent/closed.
#   BEGIN_DATE is deliberately IGNORED (unreliable per project decision) -- snapshot presence is the truth.
#   Interior gaps (facility absent from a middle snapshot) are LOCF-filled within the facility's observed span,
#   mirroring 17_wayback_facility_status.R. Values at the leading/trailing edge are not extrapolated.
# =========================================================================================================
library(readr); library(dplyr); library(tidyr); library(data.table)

RAW  <- here::here("data/raw/ICIS_AIR_WAYBACK")
SNAP_YEARS <- 2015:2025

# program_code -> group (matches the prog_* flags built in code/03_panel_building/00_spine.R)
GROUPS <- list(
  sip    = "CAASIP",  titlev = "CAATVP", nsps = c("CAANSPS", "CAANSPSM"), mact = "CAAMACT",
  neshap = "CAANESH", fesop  = "CAAFESOP", nsr = "CAANSR", psd  = "CAAPSD")
code2group <- stack(GROUPS) |> transmute(PROGRAM_CODE = values, grp = as.character(ind))
GRP_COLS <- paste0("prog_", names(GROUPS), "_active")

read_csv_snap <- function(y, file, cols)
  suppressWarnings(read_csv(file.path(RAW, sprintf("ICIS-AIR_downloads_%d", y), file),
                            col_select = all_of(cols), col_types = cols(.default = col_character()),
                            show_col_types = FALSE)) |> mutate(year = y)

# (1) facility PRESENCE per real snapshot year (the observed facility-year grid)
present <- bind_rows(lapply(SNAP_YEARS, read_csv_snap, file = "ICIS-AIR_FACILITIES.csv",
                            cols = c("PGM_SYS_ID"))) |>
  filter(!is.na(PGM_SYS_ID)) |> distinct(PGM_SYS_ID, year)

# (2) active program groups per real snapshot year (status != CLS), mapped to the 8 groups
active <- bind_rows(lapply(SNAP_YEARS, read_csv_snap, file = "ICIS-AIR_PROGRAMS.csv",
                           cols = c("PGM_SYS_ID", "PROGRAM_CODE", "AIR_OPERATING_STATUS_CODE"))) |>
  filter(!is.na(PGM_SYS_ID)) |>
  inner_join(code2group, by = "PROGRAM_CODE") |>                       # keep only the 8 groups
  filter(is.na(AIR_OPERATING_STATUS_CODE) | AIR_OPERATING_STATUS_CODE != "CLS") |>
  distinct(PGM_SYS_ID, year, grp) |>
  mutate(active = 1L) |>
  pivot_wider(names_from = grp, values_from = active, names_glue = "prog_{grp}_active", values_fill = 0L)

# (3) join active flags onto the presence grid; present-but-absent group -> observed 0
wide <- present |> left_join(active, by = c("PGM_SYS_ID", "year"))
for (g in GRP_COLS) if (is.null(wide[[g]])) wide[[g]] <- 0L        # ensure all 8 columns exist
wide <- wide |> mutate(across(all_of(GRP_COLS), \(x) as.integer(coalesce(x, 0L))))

# (4) LOCF-fill interior gaps within each facility's observed span (mirrors 17_), vectorized via data.table
dt   <- as.data.table(wide)
span <- dt[, .(first = min(year), last = max(year)), by = PGM_SYS_ID]
grid <- span[rep(seq_len(.N), last - first + 1L)]
grid[, year := first + sequence(span[, last - first + 1L]) - 1L][, c("first","last") := NULL]
full <- dt[grid, on = c("PGM_SYS_ID","year")]                    # gap years -> NA in the 8 flag columns
setorder(full, PGM_SYS_ID, year)
full[, (GRP_COLS) := lapply(.SD, nafill, type = "locf"), by = PGM_SYS_ID, .SDcols = GRP_COLS]  # min year present -> no leading NA
prog <- as_tibble(full) |> select(PGM_SYS_ID, year, all_of(GRP_COLS)) |> arrange(PGM_SYS_ID, year)

dir.create(here::here("data/processed"), showWarnings = FALSE, recursive = TRUE)
write_csv(prog, here::here("data/processed/wayback_program_status.csv.gz"))
cat(sprintf("wayback_program_status: %d facility-years | %d facilities | %d-%d\n",
            nrow(prog), n_distinct(prog$PGM_SYS_ID), min(prog$year), max(prog$year)))
cat("  active shares:", paste(sprintf("%s=%.3f", names(GROUPS), sapply(GRP_COLS, \(g) mean(prog[[g]], na.rm=TRUE))), collapse=" "), "\n")
