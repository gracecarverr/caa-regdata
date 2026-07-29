# =========================================================================================================
# code/04_panel_building/03_build_functions.R -- the shared facility x year panel recipe, now built by
#   READING the already-built datasets layer instead of re-aggregating raw event assets. Requires (in scope
#   when build_panel() runs): YEARS (defined in 03_build_parameters.R, = 2015:2025 for this pipeline --
#   NOT the repo-wide 2005:2025, since both target panels are continuity-screened over 2015-2025 anyway).
#
#   This is a from-scratch rewrite, NOT the old code/03_panel_building/03_build_functions.R renamed -- see
#   archive/panel_building_legacy/README.md for the original (data/processed/-based) version and why it was
#   archived rather than converted in place. Nearly everything that file computed by hand (per-source event
#   aggregation, dedup-load flags, HPV interval collapse, wayback status attachment, the known-operating-
#   zero fill) is now a straight READ from a dataset that already computed it once, upstream:
#     - all N_* event counts + PENALTY_AMOUNT/_DUP                -> regulatory.csv.gz (dataset 0)
#     - HPV_ACTIVE (interval-based status, R2 collapse)            -> hpv_active.csv.gz (dataset 2b)
#     - year-varying wayback status + PROG_*_ACTIVE + ACTIVE/ACTIVE_BROAD/ICIS_OBSERVED/EMISSIONS_OBSERVED/
#       GHG_OBSERVED                                                -> operating.csv.gz (dataset 1)
#   The ONE piece of real logic that survives from the archived pipeline is the known-operating-zero fill
#   (OBS_SOURCE) -- combining "did ICIS record an event this year" with "do we otherwise have positive
#   evidence the facility was active this year" is still this panel's own job, nobody upstream does it.
# =========================================================================================================
library(readr); library(dplyr); library(tidyr)
DATASETS <- here::here("data/datasets")

# ---- the full count/detail block, straight from dataset 0 -------------------------------------------------
# Every column here already carries dataset 0's own zero-vs-NA discipline (ICIS_OBSERVED == 1 -> every count
# a real value; == 0 -> every count NA) and its own dup-load flags (N_*_DUP / N_*_DUP_EXACT) -- nothing to
# recompute. ICIS_OBSERVED itself is read from operating.csv.gz below instead (both files carry an identical
# passthrough copy, decision O6) so it lives alongside ACTIVE/ACTIVE_BROAD/EMISSIONS_OBSERVED/GHG_OBSERVED
# in one place rather than needing a `.x`/`.y` disambiguation after the join.
COUNT_COLS <- c(
  "N_INSPECTIONS","N_FCE","N_PCE","N_INSP_EPA","N_INSP_STATE","N_INSP_LOCAL",
  "N_INSPECTIONS_DUP","N_INSPECTIONS_DUP_EXACT",
  "N_VIOLATIONS","N_HPV","N_FRV","N_VIOL_SIP","N_VIOL_TITLEV","N_VIOL_NSPS","N_VIOL_MACT","N_VIOL_FESOP",
  "N_VIOL_EPA","N_VIOL_STATE","N_VIOL_LOCAL",
  "N_ENFORCEMENT","N_FORMAL","N_INFORMAL","N_PENALTY_ACTION","N_WARNING_LETTER","N_ADMIN_NP",
  "N_CIVIL_JUDICIAL","N_NOV","N_ADMIN_ORDER","N_ENF_EPA","N_ENF_STATE","N_ENF_LOCAL",
  "N_ENFORCEMENT_DUP","N_ENFORCEMENT_DUP_EXACT","N_FORMAL_DUP","N_FORMAL_DUP_EXACT",
  "N_INFORMAL_DUP","N_INFORMAL_DUP_EXACT","N_PENALTIES","N_PENALTIES_DUP",
  "N_CERTS","N_CERTS_DEVIATION","N_CERTS_DUP","N_CERTS_DUP_EXACT",
  "N_STACK_TESTS","N_STACK_PASS","N_STACK_FAIL")

read_counts <- function(ids, years) {
  read_csv(file.path(DATASETS, "regulatory.csv.gz"),
           col_select = c("PGM_SYS_ID", "YEAR", all_of(COUNT_COLS), "PENALTY_AMOUNT", "PENALTY_AMOUNT_DUP"),
           # explicit col_double() for every count column, NOT col_guess() -- 01_regulatory.R's own header
           # notes these are written as doubles (coalesce(x, 0) promotes n()/sum(logical) integers to double
           # on write), and col_guess() on this large a file threw a spurious "parsing issues" warning that
           # problems() then reported zero actual rows for -- a readr/vroom quirk on big lazily-parsed
           # files, not a real data defect, but explicit typing removes the ambiguity (and the warning)
           # entirely rather than trusting a guess to land on the same answer every time.
           col_types = cols(PGM_SYS_ID = col_character(), YEAR = col_integer(),
                            .default = col_double()),
           show_col_types = FALSE) |>
    filter(PGM_SYS_ID %in% ids, YEAR %in% years)
}

# ---- year-varying wayback + activity-evidence block, straight from dataset 1 ------------------------------
WAYBACK_COLS <- c("OP_STATUS_CODE", "OPERATING",
                  "PROG_SIP_ACTIVE","PROG_TITLEV_ACTIVE","PROG_NSPS_ACTIVE","PROG_MACT_ACTIVE",
                  "PROG_NESHAP_ACTIVE","PROG_FESOP_ACTIVE","PROG_NSR_ACTIVE","PROG_PSD_ACTIVE")
ACTIVITY_COLS <- c("ICIS_OBSERVED", "EMISSIONS_OBSERVED", "GHG_OBSERVED", "ACTIVE", "ACTIVE_BROAD")

read_wayback <- function(ids, years) {
  read_csv(file.path(DATASETS, "operating.csv.gz"),
           col_select = c("PGM_SYS_ID", "YEAR", all_of(WAYBACK_COLS), all_of(ACTIVITY_COLS)),
           # every column typed explicitly -- no col_guess() anywhere in this pipeline (see read_counts()
           # above and 00_spine.R's attrs/op_facility reads for the concrete bugs guessing caused: a
           # mostly-NA column's first-sampled rows land on col_logical(), silently discarding every real
           # value later in the file with no error). OP_STATUS_CODE is the only character column here.
           col_types = cols(PGM_SYS_ID = col_character(), YEAR = col_integer(),
                            OP_STATUS_CODE = col_character(), .default = col_integer()),
           show_col_types = FALSE) |>
    filter(PGM_SYS_ID %in% ids, YEAR %in% years)
}

# ---- HPV status, straight from dataset 2b (already the R2 interval collapse) ------------------------------
# NOTE: no HPV_ACTIVE_1MO here (the >30-days-in-status variant) -- deliberately dropped, per project
# decision, since dataset 2b never shipped it and recomputing it independently in this pipeline was
# explicitly ruled out to avoid a THIRD implementation of the same interval-overlap logic living in yet
# another file (the panel-layer one is archived; a dataset-layer one was considered and declined).
read_hpv <- function(ids, years) {
  read_csv(file.path(DATASETS, "hpv_active.csv.gz"),
           col_select = c("PGM_SYS_ID", "YEAR", "HPV_ACTIVE"),
           col_types = cols(PGM_SYS_ID = col_character(), YEAR = col_integer(), HPV_ACTIVE = col_integer()),
           show_col_types = FALSE) |>
    filter(PGM_SYS_ID %in% ids, YEAR %in% years)
}

# ---- known-operating-zero fill + OBS_SOURCE ----------------------------------------------------------------
# A facility-year with ACTIVE_BROAD == 1 (confirmed active via wayback, ICIS, OR emissions/GHG evidence that
# specific year) but no ICIS event of its own is a TRUE structural zero for every ICIS-sourced count, not an
# unknown -- fill NA -> 0 across COUNT_COLS (+ HPV_ACTIVE) for those rows. OBS_SOURCE records why:
#   "event"     = ICIS_OBSERVED == 1 (an ICIS event of some kind this year -- counts are real, not filled)
#   "operating" = ICIS_OBSERVED == 0 but ACTIVE_BROAD == 1 (no ICIS event, but confirmed active some other way)
#   "unobserved"= neither (ACTIVE_BROAD is 0 or NA that year -- no confirmed activity, counts stay NA)
# case_when() checks ICIS_OBSERVED first, so the two branches are mutually exclusive by construction (and by
# the dataset layer's own invariant: ICIS_OBSERVED == 1 always implies ACTIVE_BROAD == 1, verified when
# ACTIVE_BROAD was built -- the "event" branch can never wrongly fall through to "operating").
# This is a FAITHFUL reproduction of the archived pipeline's semantics, not a behavior change: that pipeline
# also treated a wayback `operating` value of NA identically to 0 (neither triggered its zero-fill) -- here,
# ACTIVE_BROAD's own 0-vs-NA distinction collapses the same way into the same two-outcome fill decision.
FILL_COLS <- c(COUNT_COLS, "HPV_ACTIVE")   # PENALTY_AMOUNT/_DUP are DELIBERATELY EXCLUDED (unchanged
                                            # convention): a known-active, zero-ICIS-event facility-year
                                            # should read NA for PENALTY_AMOUNT (no confirmed formal action),
                                            # not 0 -- same as the datasets layer's own R4/O6-era decision.

code_obs_source <- function(panel) {
  panel <- panel |> mutate(
    OBS_SOURCE = case_when(
      ICIS_OBSERVED == 1  ~ "event",
      ACTIVE_BROAD == 1   ~ "operating",
      TRUE                ~ "unobserved"))
  fill <- panel$OBS_SOURCE == "operating"
  panel[fill, FILL_COLS] <- lapply(panel[fill, FILL_COLS], \(x) coalesce(x, 0L))
  panel
}

# ---- build_panel: the full facility x year panel for a facility frame `facs` -------------------------------
#   facs  : a filtered slice of the spine (one row per facility; supplies ids + attributes).
#   years : the panel window (2015:2025 for both panels this pipeline ships).
#   Balanced PGM_SYS_ID x years rectangle (every source shares this exact universe/window already, per O1/
#   O6/H6, so a left_join from expand_grid is sufficient -- no full_join-across-sources reconciliation like
#   the archived pipeline needed when aggregating five separately-covered raw event tables).
build_panel <- function(facs, years) {
  ids <- facs$PGM_SYS_ID
  panel <- expand_grid(PGM_SYS_ID = ids, YEAR = years) |>
    left_join(read_counts(ids, years),   by = c("PGM_SYS_ID", "YEAR")) |>
    left_join(read_wayback(ids, years),  by = c("PGM_SYS_ID", "YEAR")) |>
    left_join(read_hpv(ids, years),      by = c("PGM_SYS_ID", "YEAR"))
  for (m in c("INSPECTIONS", "VIOLATIONS", "ENFORCEMENT", "CERTS"))
    panel[[paste0("ANY_", m)]] <- as.integer(panel[[paste0("N_", m)]] > 0)
    # NA > 0 is NA, as.integer(NA) is NA -- ANY_* correctly stays NA for unobserved rows, never a silent 0
  panel <- panel |> code_obs_source() |>
    left_join(facs, by = "PGM_SYS_ID") |>          # attach static facility attributes (spine, one row/facility)
    arrange(PGM_SYS_ID, YEAR)
  panel
}

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# 1. (read_counts, ~line 30 -- RESOLVED, documented for the record) During initial testing this session,
#    read_counts() used `.default = col_guess()` and threw a "parsing issues" warning on the full-size
#    regulatory.csv.gz read, but `problems()` on the returned tibble reported zero rows -- misleadingly
#    looking like a benign readr/vroom quirk. Investigated anyway (per this project's "flag issues, don't
#    silently accept" discipline): col_guess() had actually typed PENALTY_AMOUNT/PENALTY_AMOUNT_DUP as
#    col_logical(), because both are NA in ~99.6% of rows and the sampled rows readr guesses from happened
#    to be all-NA. Every real dollar figure later in the file was then silently discarded as an unparseable
#    "logical" value -- no error, no problems() entry, just quiet data loss that would have shipped in this
#    panel's PENALTY_AMOUNT column as all-NA. Fixed by typing every column explicitly (col_double() for the
#    count/dollar block) instead of guessing. The same root cause was found and fixed in
#    code/04_panel_building/00_spine.R's op_facility read (EXITED_YEAR/EXIT_SOURCE, also mostly-NA columns
#    guessed as col_logical()) -- see that file's own inline comments. No other col_guess() calls remain
#    anywhere in this pipeline as of this fix.
# =========================================================================================================
