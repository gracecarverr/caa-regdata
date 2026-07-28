# =========================================================================================================
# code/04_datasets/03_hpv_spells.R -- DATASET 2: hpv_spells. One row per HPV spell, UNcollapsed.
#   The spell-level source of truth for High Priority Violation status. Dataset `hpv_active` (facility x year,
#   built in 04_hpv_active.R) is a deterministic R2 collapse of THIS table; nothing here is lost.
#
#   in : data/processed/violations.csv.gz
#   out: data/datasets/hpv_spells.csv.gz
#
#   HPV UNIVERSE -- ENF_RESPONSE_POLICY_CODE == "HPV" (the enforcement-response tier), NOT day-zero presence.
#     The tier below, FRV (Federally Reportable Violation), is excluded. Day-zero (HPV_DAYZERO_DATE) is the
#     spell START; a handful of HPV records lack it (spell_status == "missing_start") and are KEPT, flagged,
#     not dropped. See code/diagnostics/08_hpv_spell_diagnostics.R for the profile behind these choices.
#
#   SPELL_STATUS (mutually exclusive) -- closed: day-zero + resolved, well-ordered | open: day-zero, no
#     resolved | bad_order: resolved BEFORE day-zero | missing_start: no day-zero. spell_days (inclusive) is
#     defined ONLY for `closed`; NA otherwise. Dates are carried AS PARSED -- no plausibility screen here (a
#     `218`/`2026` day-zero stays); screening is a downstream / facility-year-collapse decision.
#
#   GRAIN -- spell-level: a facility has 0..N rows. Does NOT join 1:1 to datasets 0/1; join on PGM_SYS_ID.
# =========================================================================================================
library(readr); library(dplyr); library(lubridate)
source(here::here("code/04_datasets/00_parameters.R"))

COLS <- c("PGM_SYS_ID","ACTIVITY_ID","COMP_DETERMINATION_UID","ENF_RESPONSE_POLICY_CODE",
          "EARLIEST_FRV_DETERM_DATE","HPV_DAYZERO_DATE","HPV_RESOLVED_DATE",
          "PROGRAM_CODES","PROGRAM_DESCS","POLLUTANT_CODES","POLLUTANT_DESCS",
          "AGENCY_TYPE_DESC","STATE_CODE","dup","dup_exact")
v <- read_csv(file.path(CLEAN, "violations.csv.gz"), col_select = all_of(COLS),
              col_types = cols(PGM_SYS_ID = col_character(), dup = col_integer(),
                               dup_exact = col_integer(), .default = col_character()),
              show_col_types = FALSE) |>
  filter(ENF_RESPONSE_POLICY_CODE == "HPV")          # the enforcement-response TIER, not "has a day-zero date"

# FRS id (REGISTRY_ID), joined in alongside PGM_SYS_ID (violations.csv.gz carries no REGISTRY_ID natively).
frs_ids <- read_csv(file.path(CLEAN, "facilities.csv.gz"),
                    col_types = cols_only(PGM_SYS_ID = col_character(), REGISTRY_ID = col_character()),
                    show_col_types = FALSE)
                    # same "reads ICIS facilities.csv.gz, not actual FRS data" naming note as 02_operating.R
v <- v |> left_join(frs_ids, by = "PGM_SYS_ID")

nz <- function(x) !is.na(x) & x != ""                 # "non-blank raw string" check, applied to the RAW text
                                                        # columns below, not the parsed Date -- see REVIEW below
spells <- v |> mutate(
  hpv_dayzero_date        = mdy(HPV_DAYZERO_DATE, quiet = TRUE),
  hpv_resolved_date       = mdy(HPV_RESOLVED_DATE, quiet = TRUE),
  earliest_frv_determ_date = mdy(EARLIEST_FRV_DETERM_DATE, quiet = TRUE),
  dayzero_year  = year(hpv_dayzero_date),
  resolved_year = year(hpv_resolved_date),
  spell_status = case_when(
    !nz(HPV_DAYZERO_DATE)                                          ~ "missing_start",
    !nz(HPV_RESOLVED_DATE)                                         ~ "open",
    !is.na(hpv_resolved_date) & hpv_resolved_date < hpv_dayzero_date ~ "bad_order",
    TRUE                                                          ~ "closed"),
    # REVIEW(design, latent edge case -- 0 rows affected as of the 2026-07-27 snapshot, independently
    # verified): the first two branches test nz() on the RAW string, not on whether mdy() actually managed
    # to parse it. A HPV_DAYZERO_DATE that is non-blank but fails to parse (hpv_dayzero_date == NA) would
    # skip the "missing_start" branch and fall through to "open" or "closed" with a NA dayzero date baked in
    # -- e.g. a "closed" spell with spell_days == NA despite spell_status claiming spell_days should be
    # defined. In practice this doesn't happen today (mdy() is permissive enough to parse even garbage like
    # "11-05-0218" into a wrong-but-non-NA year 218, per the CAMDAM1489 case documented in 04_hpv_active.R),
    # and if it ever did, the stopifnot() invariants below would halt the build with an NA-comparison error
    # rather than silently shipping a bad row -- so this is a latent robustness gap with an effective safety
    # net, not an active bug.
  spell_days = if_else(spell_status == "closed",
                       as.integer(hpv_resolved_date - hpv_dayzero_date) + 1L, NA_integer_)) |>
                       # inclusive day count: e.g. dayzero==resolved gives 1 day, not 0
  transmute(PGM_SYS_ID, REGISTRY_ID, ACTIVITY_ID, COMP_DETERMINATION_UID,
            hpv_dayzero_date, hpv_resolved_date, dayzero_year, resolved_year,
            spell_status, spell_days, earliest_frv_determ_date,
            PROGRAM_CODES, PROGRAM_DESCS, POLLUTANT_CODES, POLLUTANT_DESCS,
            AGENCY_TYPE_DESC, STATE_CODE, dup, dup_exact) |>
  arrange(PGM_SYS_ID, hpv_dayzero_date, hpv_resolved_date)

# ---- invariants -----------------------------------------------------------------------------------------
stopifnot(
  "row grain broken: duplicate (PGM_SYS_ID, ACTIVITY_ID, COMP_DETERMINATION_UID, dayzero)" =
    !anyDuplicated(spells[c("PGM_SYS_ID","ACTIVITY_ID","COMP_DETERMINATION_UID","hpv_dayzero_date")]),
  "spell_status not exhaustive/exclusive" =
    all(spells$spell_status %in% c("closed","open","bad_order","missing_start")),
  "spell_days must be NA unless closed" =
    all(is.na(spells$spell_days) | spells$spell_status == "closed"),
  "closed spell_days must be >= 1" =
    all(spells$spell_days[spells$spell_status == "closed"] >= 1),
  "dayzero_year NA iff missing_start" =
    all(is.na(spells$dayzero_year) == (spells$spell_status == "missing_start")),
  "violations carry no dups (per ds0 assertion)" = all(spells$dup == 0))
  # six hard assertions -- also the safety net for the case_when edge case noted above: an NA slipping into
  # a "closed" row's spell_days would fail "closed spell_days must be >= 1" (NA >= 1 is NA, and stopifnot
  # treats a non-TRUE/NA result as a failure), halting the build rather than shipping a silently-wrong row

write_dataset(spells, "hpv_spells")              # uppercases all columns on write (see 00_parameters.R)
cat(sprintf("hpv_spells: %s spells | %d cols | %s facilities\n  status: %s\n",
            format(nrow(spells), big.mark = ","), ncol(spells),
            format(n_distinct(spells$PGM_SYS_ID), big.mark = ","),
            paste(names(table(spells$spell_status)), table(spells$spell_status), sep = "=", collapse = "  ")))
