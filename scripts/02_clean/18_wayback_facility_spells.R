# =========================================================================================================
# scripts/02_clean/18_wayback_facility_spells.R -- collapse the facility x year wayback status series into a
#   one-row-per-facility ENTRY/EXIT summary. The raw ICIS-AIR facility table has NO entry/exit dates; these
#   are RECONSTRUCTED from when a facility appears in / disappears from the annual snapshots (2015-2025) and
#   from observed operating->closed transitions.
#   in : data/clean/wayback_facility_status.csv.gz
#   out: data/clean/wayback_facility_spells.csv.gz
#        PGM_SYS_ID, entered_year, exited_year, exit_source, left_censored, right_censored
#
#   entered_year   = first snapshot year the facility is OPERATING (op in {OPR,TMP,SEA}); NA if never operating.
#   left_censored  = 1 if the facility is already present in the first snapshot (2015): true entry may predate
#                    the window and is unknown.
#   exited_year    = first year after which the facility is NEVER operating again (permanent exit). NA if the
#                    facility is still operating in the last snapshot (2025) -> right-censored.
#   exit_source    = "cls"     : exit confirmed by an observed Permanently-Closed (CLS) status;
#                    "other"   : exit via another non-operating code (PLN/CNS/NER/NED/NES/LDF);
#                    "dropout" : facility was last seen OPERATING then vanished from later snapshots (could be
#                                a real closure OR an ICIS extract artifact -- kept distinct on purpose);
#                    NA        : never exited within the window (right-censored) or never operating.
#   right_censored = 1 if operating in the last snapshot (2025): exit, if any, is after the window.
#   NOTE: exited_year is defined off the LAST operating year, so a close-then-reopen facility is treated as
#   still-in-service until its final operating year -- reopenings do not create a spurious early exit.
# =========================================================================================================
library(readr); library(dplyr)

st <- read_csv(here::here("data/clean/wayback_facility_status.csv.gz"),
               col_types = cols(PGM_SYS_ID = col_character(), year = col_integer(),
                                op_status_code = col_character(), op_status_desc = col_character(),
                                operating = col_integer()), show_col_types = FALSE)

FIRST_SNAP <- min(st$year)  # 2015
LAST_SNAP  <- max(st$year)  # 2025

# per-facility span (all rows) and operating window (operating rows only) -- fully vectorized, no rowwise
per_fac <- st |> group_by(PGM_SYS_ID) |>
  summarise(first_year = min(year), last_year = max(year), .groups = "drop")
op_win  <- st |> filter(operating == 1) |> group_by(PGM_SYS_ID) |>
  summarise(entered_year = min(year), last_op_year = max(year), .groups = "drop")

spells <- per_fac |> left_join(op_win, by = "PGM_SYS_ID") |>
  mutate(
    ever_op        = !is.na(entered_year),
    left_censored  = as.integer(ever_op & entered_year == FIRST_SNAP),
    right_censored = as.integer(ever_op & last_op_year == LAST_SNAP))

# exit classification: look at the status code in the first non-operating year that FOLLOWS the last op year.
exit_code <- st |>
  inner_join(spells |> filter(!is.na(last_op_year)) |> select(PGM_SYS_ID, last_op_year, last_year),
             by = "PGM_SYS_ID") |>
  filter(year > last_op_year) |>                       # years strictly after last operating year
  group_by(PGM_SYS_ID) |>
  slice_min(year, n = 1, with_ties = FALSE) |>         # first post-operating year
  ungroup() |>
  transmute(PGM_SYS_ID, exit_year_obs = year, exit_code = op_status_code)

spells <- spells |>
  left_join(exit_code, by = "PGM_SYS_ID") |>
  mutate(
    exited_year = case_when(
      right_censored == 1              ~ NA_integer_,          # still operating at window close
      !ever_op                          ~ NA_integer_,          # never operating in window
      !is.na(exit_year_obs)            ~ exit_year_obs,        # observed transition to non-operating
      last_op_year < last_year         ~ last_op_year,         # (defensive; shouldn't occur given above)
      TRUE                              ~ last_op_year),        # last seen operating then vanished (dropout)
    exit_source = case_when(
      is.na(exited_year)               ~ NA_character_,
      exit_code == "CLS"               ~ "cls",
      !is.na(exit_code)                ~ "other",
      TRUE                              ~ "dropout")) |>
  select(PGM_SYS_ID, entered_year, exited_year, exit_source, left_censored, right_censored) |>
  arrange(PGM_SYS_ID)

dir.create(here::here("data/clean"), showWarnings = FALSE, recursive = TRUE)
write_csv(spells, here::here("data/clean/wayback_facility_spells.csv.gz"))
cat(sprintf("wayback_facility_spells: %d facilities | entered non-NA %d | exited non-NA %d | dropout %d | left-cens %d | right-cens %d\n",
            nrow(spells), sum(!is.na(spells$entered_year)), sum(!is.na(spells$exited_year)),
            sum(spells$exit_source == "dropout", na.rm = TRUE),
            sum(spells$left_censored), sum(spells$right_censored)))
