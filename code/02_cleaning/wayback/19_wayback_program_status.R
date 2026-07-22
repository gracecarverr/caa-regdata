# =========================================================================================================
# code/02_cleaning/wayback/19_wayback_program_status.R -- HISTORICAL program status from the ICIS-AIR WAYBACK
#   snapshots (2015-2025 EXCEPT 2018 -- no real snapshot exists, see 17_'s header note and
#   briefs/panel/panel_construction_decisions.md N18/W7; 2018 is explicit NA, NOT LOCF-filled, unlike an ordinary
#   interior gap -- no facility has a real 2018 snapshot to infer from).
#   The raw PROGRAMS table has an unreliable BEGIN_DATE and NO program-close date;
#   we instead reconstruct a facility x year "is this program active?" series from snapshot PRESENCE +
#   operating status. Covers the 10 program groups already flagged in the spine.
#   in : data/raw/ICIS_AIR_WAYBACK/ICIS-AIR_downloads_{2015..2025 except 2018}/{ICIS-AIR_FACILITIES,ICIS-AIR_PROGRAMS}.csv
#   out: data/processed/wayback_program_status.csv.gz
#        PGM_SYS_ID, year, prog_{sip,titlev,nsps,mact,gact,neshap,fesop,nsr,psd,cfc}_active
#
#   prog_X_active in a given snapshot year = 1 iff the facility carries >=1 program in group X whose status is
#   ACTIVE under a PROGRAM-SPECIFIC rule: operating programs (sip/titlev/nsps/mact/gact/neshap/fesop/cfc) are active only
#   for {OPR,TMP,SEA} (mirrors the 17_ operating whitelist); the preconstruction programs NSR & PSD are ALSO
#   active for {PLN,CNS} (planned / under-construction), since those permits attach before a source operates.
#   The rare NER/NED/NES/LDF is inactive (0) for every group -- these ARE a real, known status, just not one
#   any group is active under. 0 if the facility is present in that snapshot (with a real, known status) but
#   the group has no active row.
#
#   BLANK STATUS or CLS -> NA, not 0 (project decision 2026-07-21, W8). A facility's own
#   AIR_OPERATING_STATUS_CODE that year (from ICIS-AIR_FACILITIES.csv, the same field 17_ reads) gates this:
#   if it's blank, we have no real status evidence that year at all, so asserting "not enrolled" (0) for every
#   group would be manufacturing certainty from an incomplete record -- NA instead. If it's CLS (Permanently
#   Closed), mirrors the already-established W6 event-zero rule ("closed years stay NA... a shut plant can
#   still carry legacy enforcement") -- a closed facility's program enrollment isn't confidently "none," it's
#   simply not asserted. Every OTHER real status (OPR/TMP/SEA/PLN/CNS/NER/NED/NES/LDF) keeps a real 0/1 per the
#   program-specific rule above -- only blank and CLS become NA.
#   BEGIN_DATE is deliberately IGNORED (unreliable per project decision) -- snapshot presence is the truth.
#   Interior gaps (facility absent from a middle snapshot) are LOCF-filled within the facility's observed span,
#   mirroring 17_wayback_facility_status.R. Values at the leading/trailing edge are not extrapolated. The
#   blank/CLS override runs AFTER this LOCF step (same pattern as the 2018 override below) so it can't be
#   silently re-filled from a neighboring year. KNOWN RESIDUAL EDGE CASE: LOCF itself runs before the override,
#   so a genuinely-absent gap year immediately adjacent to a blank/CLS year can still inherit that year's
#   PRE-override computed value (0) rather than NA -- this requires both a roster-absence gap (~0.3% of
#   facility-programs, W4) AND it landing next to a blank/CLS year, a rare compound case, not fixed here.
# =========================================================================================================
library(readr); library(dplyr); library(tidyr); library(data.table)

RAW  <- here::here("data/raw/ICIS_AIR_WAYBACK")
SNAP_YEARS <- setdiff(2015:2025, 2018)   # no real 2018 snapshot exists -- see 17_'s header note

# program_code -> group (matches the prog_* flags built in code/03_panel_building/00_spine.R)
GROUPS <- list(
  sip    = "CAASIP",  titlev = "CAATVP", nsps = c("CAANSPS", "CAANSPSM"), mact = "CAAMACT",
  gact   = "CAAGACTM",                                     # Part 63 AREA sources (counterpart to mact)
  neshap = "CAANESH", fesop  = "CAAFESOP", nsr = "CAANSR", psd  = "CAAPSD",
  cfc    = "CAACFC")                                       # Title VI stratospheric ozone protection
code2group <- stack(GROUPS) |> transmute(PROGRAM_CODE = values, grp = as.character(ind))
GRP_COLS <- paste0("prog_", names(GROUPS), "_active")

# program-specific "active" rule (replaces the old status != CLS blacklist)
OPERATING_ACTIVE      <- c("OPR", "TMP", "SEA")   # mirrors the 17_ operating whitelist
PRECONSTRUCTION_GRPS  <- c("nsr", "psd")          # NSR/PSD permits attach before a source operates
PRECONSTRUCTION_EXTRA <- c("PLN", "CNS")          # ...so planned / under-construction are active for those too

read_csv_snap <- function(y, file, cols)
  suppressWarnings(read_csv(file.path(RAW, sprintf("ICIS-AIR_downloads_%d", y), file),
                            col_select = all_of(cols), col_types = cols(.default = col_character()),
                            show_col_types = FALSE)) |> mutate(year = y)

# (1) facility PRESENCE per real snapshot year (the observed facility-year grid), carrying the facility's OWN
#     operating-status field that year (same field 17_ reads) so blank/CLS years can be nulled out below (W8).
present_raw <- bind_rows(lapply(SNAP_YEARS, read_csv_snap, file = "ICIS-AIR_FACILITIES.csv",
                                cols = c("PGM_SYS_ID", "AIR_OPERATING_STATUS_CODE"))) |>
  filter(!is.na(PGM_SYS_ID)) |> distinct(PGM_SYS_ID, year, .keep_all = TRUE)
present <- present_raw |> select(PGM_SYS_ID, year)
# facility-years where the status is unknown (blank) or the facility is Permanently Closed -- W8
blank_or_closed <- present_raw |>
  filter(is.na(AIR_OPERATING_STATUS_CODE) | AIR_OPERATING_STATUS_CODE %in% c("", "CLS")) |>
  select(PGM_SYS_ID, year)

# (2) active program groups per real snapshot year (status != CLS), mapped to the 8 groups
active <- bind_rows(lapply(SNAP_YEARS, read_csv_snap, file = "ICIS-AIR_PROGRAMS.csv",
                           cols = c("PGM_SYS_ID", "PROGRAM_CODE", "AIR_OPERATING_STATUS_CODE"))) |>
  filter(!is.na(PGM_SYS_ID)) |>
  inner_join(code2group, by = "PROGRAM_CODE") |>                       # keep only the 10 groups
  filter(AIR_OPERATING_STATUS_CODE %in% OPERATING_ACTIVE |             # program-specific active rule
         (grp %in% PRECONSTRUCTION_GRPS & AIR_OPERATING_STATUS_CODE %in% PRECONSTRUCTION_EXTRA)) |>
  distinct(PGM_SYS_ID, year, grp) |>
  mutate(active = 1L) |>
  pivot_wider(names_from = grp, values_from = active, names_glue = "prog_{grp}_active", values_fill = 0L)

# (3) join active flags onto the presence grid; present-but-absent group -> observed 0
wide <- present |> left_join(active, by = c("PGM_SYS_ID", "year"))
for (g in GRP_COLS) if (is.null(wide[[g]])) wide[[g]] <- 0L        # ensure all 10 columns exist
wide <- wide |> mutate(across(all_of(GRP_COLS), \(x) as.integer(coalesce(x, 0L))))

# (4) LOCF-fill interior gaps within each facility's observed span (mirrors 17_), vectorized via data.table
dt   <- as.data.table(wide)
span <- dt[, .(first = min(year), last = max(year)), by = PGM_SYS_ID]
grid <- span[rep(seq_len(.N), last - first + 1L)]
grid[, year := first + sequence(span[, last - first + 1L]) - 1L][, c("first","last") := NULL]
full <- dt[grid, on = c("PGM_SYS_ID","year")]                    # gap years -> NA in the 8 flag columns
setorder(full, PGM_SYS_ID, year)
full[, (GRP_COLS) := lapply(.SD, nafill, type = "locf"), by = PGM_SYS_ID, .SDcols = GRP_COLS]  # min year present -> no leading NA
# 2018 has NO real snapshot for any facility (see 17_'s header note) -- force back to NA rather than
# LOCF-inferring it, unlike an ordinary sporadic per-facility gap in a real snapshot year.
full[year == 2018L, (GRP_COLS) := NA_integer_]
# blank status / CLS (Permanently Closed) -> NA, not a confident 0 (W8, see header note). Runs AFTER LOCF so
# these facility-years can't get silently re-filled from a neighboring year, same pattern as the 2018 override.
full[as.data.table(blank_or_closed), on = c("PGM_SYS_ID", "year"), (GRP_COLS) := NA_integer_]
prog <- as_tibble(full) |> select(PGM_SYS_ID, year, all_of(GRP_COLS)) |> arrange(PGM_SYS_ID, year)

dir.create(here::here("data/processed"), showWarnings = FALSE, recursive = TRUE)
write_csv(prog, here::here("data/processed/wayback_program_status.csv.gz"))
cat(sprintf("wayback_program_status: %d facility-years | %d facilities | %d-%d\n",
            nrow(prog), n_distinct(prog$PGM_SYS_ID), min(prog$year), max(prog$year)))
cat("  active shares:", paste(sprintf("%s=%.3f", names(GROUPS), sapply(GRP_COLS, \(g) mean(prog[[g]], na.rm=TRUE))), collapse=" "), "\n")
