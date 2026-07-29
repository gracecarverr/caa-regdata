# =========================================================================================================
# code/04_datasets/05_penalties.R -- DATASET 3: penalties. One row per FORMAL ACTION (action-level).
#   The disaggregated penalty record behind ds 0's facility-year penalty_amount / n_penalties. Carries the
#   multi-facility settlement key so co-defendant broadcasting is visible and cross-facility summing is avoidable.
#
#   in : data/processed/formal_actions.csv.gz
#   out: data/datasets/penalties.csv.gz
#
#   GRAIN -- one row per formal-action record (105,946; ALL rows kept, dup>0 flagged not dropped, per the
#     layer convention). Joins on PGM_SYS_ID (+ YEAR for facility-year merges). NOT window-restricted: all
#     action years are kept (the eight-dataset design pushes sample/window filters downstream). Only FORMAL
#     actions carry penalties -- informal actions have no PENALTY_AMOUNT column and are out of scope here.
#
#   MULTI-FACILITY SETTLEMENTS (the load-bearing caveat, panel E4/F2) -- ENF_IDENTIFIER is the settlement key.
#     571 settlements (0.6%) span >1 co-defendant facility (up to 117), each facility a separate row. The
#     penalty is USUALLY one value repeated across co-defendants (507/571) but 64 settlements carry DIFFERING
#     per-facility amounts -- so it is NOT a clean broadcast. PENALTY_AMOUNT is kept AS RECORDED per row;
#     N_SETTLEMENT_FACILITIES + IS_MULTI_FACILITY expose the structure so the user chooses how to aggregate.
#     ==> Do NOT sum PENALTY_AMOUNT across facilities of one ENF_IDENTIFIER without deciding the broadcast rule.
# =========================================================================================================
library(readr); library(dplyr); library(lubridate)
source(here::here("code/04_datasets/00_parameters.R"))

COLS <- c("PGM_SYS_ID","ACTIVITY_ID","ENF_IDENTIFIER","ACTIVITY_TYPE_CODE","ACTIVITY_TYPE_DESC",
          "STATE_EPA_FLAG","ENF_TYPE_CODE","ENF_TYPE_DESC","SETTLEMENT_ENTERED_DATE","PENALTY_AMOUNT",
          "date","year","dup","dup_exact")
f <- read_csv(file.path(CLEAN, "formal_actions.csv.gz"), col_select = all_of(COLS),
              col_types = cols(PGM_SYS_ID = col_character(), ACTIVITY_ID = col_character(),
                               ENF_IDENTIFIER = col_character(), date = col_date(), year = col_integer(),
                               dup = col_integer(), dup_exact = col_integer(), .default = col_character()),
              show_col_types = FALSE)
              # PENALTY_AMOUNT is ALWAYS populated in the source (verified: 0 blank/NA rows, min value 0 --
              # even non-monetary action types like Warning Letters carry an explicit "0"), which is what
              # makes the "penalty_amount NA or negative" invariant below safe to assert unconditionally

pen <- f |>
  group_by(ENF_IDENTIFIER) |> mutate(n_settlement_facilities = n_distinct(PGM_SYS_ID)) |> ungroup() |>
    # count of distinct co-defendant facilities sharing this settlement's ENF_IDENTIFIER
  transmute(
    PGM_SYS_ID, ACTIVITY_ID, ENF_IDENTIFIER,
    settlement_entered_date = date, year,
    penalty_amount = parse_number(PENALTY_AMOUNT),
    has_penalty    = as.integer(parse_number(PENALTY_AMOUNT) > 0),
      # recomputes parse_number(PENALTY_AMOUNT) a second time rather than reusing the penalty_amount column
      # just defined above (dplyr's transmute() would allow referencing it) -- harmless duplication, same result
    enf_type_code = ENF_TYPE_CODE, enf_type_desc = ENF_TYPE_DESC,
    activity_type_code = ACTIVITY_TYPE_CODE, activity_type_desc = ACTIVITY_TYPE_DESC,
    state_epa_flag = STATE_EPA_FLAG,
    n_settlement_facilities, is_multi_facility = as.integer(n_settlement_facilities > 1),
    dup, dup_exact) |>
  arrange(PGM_SYS_ID, year, ENF_IDENTIFIER)

# ---- FRS id (REGISTRY_ID) --------------------------------------------------------------------------------
frs_ids <- read_csv(file.path(CLEAN, "facilities.csv.gz"),
                    col_types = cols_only(PGM_SYS_ID = col_character(), REGISTRY_ID = col_character()),
                    show_col_types = FALSE)
                    # same "reads ICIS facilities.csv.gz, not FRS_FACILITIES.csv" naming note as other files here
ids <- frs_ids$PGM_SYS_ID
pen <- pen |> left_join(frs_ids, by = "PGM_SYS_ID") |> relocate(REGISTRY_ID, .after = PGM_SYS_ID)

# ---- invariants -----------------------------------------------------------------------------------------
stopifnot(
  "row count != source formal_actions"          = nrow(pen) == nrow(f),           # every source row kept, none dropped/added
  "ENF_IDENTIFIER blank"                         = all(!is.na(pen$ENF_IDENTIFIER) & pen$ENF_IDENTIFIER != ""),
  "penalty_amount NA or negative"               = all(!is.na(pen$penalty_amount) & pen$penalty_amount >= 0),
  "has_penalty disagrees with penalty_amount>0" = all(pen$has_penalty == as.integer(pen$penalty_amount > 0)),
  "is_multi_facility disagrees with count"      = all(pen$is_multi_facility == as.integer(pen$n_settlement_facilities > 1)),
  "n_settlement_facilities < 1"                 = all(pen$n_settlement_facilities >= 1),
  "action facility not in ds0 universe"         = all(pen$PGM_SYS_ID %in% ids))

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# 1. (has_penalty, ~line 43) Recomputes parse_number(PENALTY_AMOUNT) a second time rather than reusing the
#    penalty_amount column just defined above (dplyr's transmute() would allow referencing it) -- harmless
#    duplication, same result.
# 2. (frs_ids, ~line 54) Same "reads ICIS facilities.csv.gz, not FRS_FACILITIES.csv" naming note as
#    02_operating.R and 03_hpv_spells.R.
# =========================================================================================================

write_dataset(pen, "penalties")                  # uppercases all columns on write (see 00_parameters.R)
cat(sprintf("penalties: %s actions | %d cols | %s facilities | years %d-%d\n",
            format(nrow(pen), big.mark = ","), ncol(pen), format(n_distinct(pen$PGM_SYS_ID), big.mark = ","),
            min(pen$year, na.rm = TRUE), max(pen$year, na.rm = TRUE)))
cat(sprintf("  with penalty>0: %s | total $%s | multi-facility actions: %s (%d settlements, max %d co-defendants)\n",
            format(sum(pen$has_penalty), big.mark = ","),
            format(round(sum(pen$penalty_amount)), big.mark = ","),
            format(sum(pen$is_multi_facility), big.mark = ","),
            n_distinct(pen$ENF_IDENTIFIER[pen$is_multi_facility == 1]), max(pen$n_settlement_facilities)))
