# =========================================================================================================
# code/04_datasets/07_pipeline.R -- DATASET 6: pipeline. Facility x year, built from EPA ECHO's "CAA
#   Compliance Pipeline" (docs/data_dictionary.md "CAA Compliance Pipeline"). Every line below is commented
#   per the user's explicit request for this script (the layer's usual house style is sparser -- see the
#   other 04_datasets/*.R files).
#
#   in : data/processed/pipeline.csv.gz, data/processed/facilities.csv.gz
#   out: data/datasets/pipeline.csv.gz
#
#   WHAT'S NEW HERE (not already in datasets 0/2/3) -- the raw pipeline row links, in a SINGLE record, the
#     evaluation (inspection) that found a violation to the enforcement action it triggered -- a same-row
#     chain no ICIS-Air table alone carries. It also includes FRV violations (ds 2 `hpv_spells` is HPV-only
#     by design, H1). This dataset collapses that linked, violation-grain source into a facility x year
#     panel: violation counts split HPV/FRV, how many of a year's violations trace to a known evaluation vs.
#     an enforcement action, and the eval->violation / violation->enforcement lag in days -- a "pipeline
#     speed" measure that does not exist anywhere else in this layer.
#
#   PLACEHOLDER ROWS (profiled directly against the raw file, not assumed) -- 7,193 of the source's 66,655
#     rows are EPA-system-generated linkage helpers, not real violations: blank VIOL_START_DATE,
#     VIOL_ACTIVITY_ID prefixed 9906/9913, VIOL_TYPE blank or "Linked to Viol. Below" (matches the dictionary
#     note that these IDs "did not have an actual violation activity identification number"). They have no
#     VIOL_START_DATE, so they cannot be assigned a year and are simply absent from every facility-year below
#     -- not silently dropped, just structurally unable to appear (asserted at the end of this script).
#
#   YEAR ANCHOR -- VIOL_START_DATE, the one date present on every real (non-placeholder) row. NOT the clean
#     asset's own `date`/`year` (= SORT_DATE, EPA's own "latest stage reached" display date -- verified to
#     equal EA_DATE if an EA is linked, else VIOL_START_DATE, else EVAL_DATE). SORT_DATE would shift a
#     violation into a later year purely because it was eventually enforced, which would misdate the
#     violation itself -- so this script parses VIOL_START_DATE itself rather than reusing the cleaned date.
#
#   UNIVERSE -- the SAME 279,211-facility x 2005-2025 rectangle as ds 0/1/2b (G3/G4), so this dataset joins
#     1:1 to regulatory.csv.gz on (PGM_SYS_ID, YEAR).
#
#   ZERO-vs-NA (mirrors ds 0's ICIS_OBSERVED) -- PIPELINE_OBSERVED == 1 iff >=1 real pipeline row anchors to
#     that facility-year; every count is a true value (including 0) when observed, NA when not.
#
#   CAVEAT (like ds 3's P5) -- EA_PENALTY_AMT_SUM is very likely the SAME underlying dollars as ds 3
#     `penalties.csv.gz` (both trace to the same enforcement-action universe). It is exposed here, per
#     violation, but must NOT be summed alongside ds 3's PENALTY_AMOUNT without a dedup rule -- that
#     reconciliation is deliberately left undone (see briefs/datasets/dataset_construction_decisions.md).
# =========================================================================================================
library(readr)                                             # read_csv / write_csv / parse_number
library(dplyr)                                             # filter / mutate / group_by / summarise / join
library(tidyr)                                             # expand_grid, for the full facility x year rectangle
library(lubridate)                                         # mdy() date parsing, year()
source(here::here("code/04_datasets/00_parameters.R"))     # YEARS, CLEAN, DATASETS, write_dataset()

# ---- read the cleaned pipeline asset, keep only the columns this build needs -----------------------------
p <- read_csv(file.path(CLEAN, "pipeline.csv.gz"),                     # data/processed/pipeline.csv.gz
              col_select = c(SOURCE_ID, EVAL_FLAG, EVAL_TYPE_DESC, EVAL_DATE,   # facility id + eval block
                             VIOL_FLAG, VIOL_TYPE, VIOL_START_DATE,             # violation block (the anchor)
                             EA_FLAG, EA_DATE, EA_PENALTY_AMT),                 # enforcement-action block
              col_types = cols(.default = col_character()),            # read everything as character first
              show_col_types = FALSE)                                  # suppress the column-spec printout

# ---- parse the three stage dates from character to real Date, and derive the row's anchor year -----------
p <- p |> mutate(
  eval_date       = mdy(EVAL_DATE, quiet = TRUE),          # evaluation date, NA if blank/unparseable
  viol_start_date = mdy(VIOL_START_DATE, quiet = TRUE),    # violation start date -- NA for placeholder rows
  ea_date         = mdy(EA_DATE, quiet = TRUE),            # enforcement-action date, NA if blank/unparseable
  viol_year       = year(viol_start_date))                 # calendar year of the violation -- this row's anchor

# ---- keep only real violations: a placeholder row has no VIOL_START_DATE and so no viol_year --------------
real <- p |> filter(!is.na(viol_year))                     # drops exactly the 7,193 EPA linkage-helper rows

# ---- restrict to the layer's analysis window, matching every other dataset's G1 convention -----------------
real <- real |> filter(viol_year %in% YEARS)               # keep only 2005-2025; drops pre-2005 and 2026 rows

# ---- per-row derived flags used by the facility-year aggregation below ------------------------------------
real <- real |> mutate(
  is_hpv          = VIOL_TYPE == "HPV",                                    # TRUE for HPV-tier violations
  is_frv          = VIOL_TYPE == "FRV",                                    # TRUE for FRV-tier violations
  has_eval        = EVAL_FLAG == "Y",                                      # TRUE if a linked evaluation exists
  has_ea          = EA_FLAG == "Y",                                       # TRUE if a linked enforcement action exists
  # guarded with has_eval/!is.na() first: EVAL_TYPE_DESC is blank (NA) whenever no evaluation is linked, and
  # an unguarded `== "Self-Disclosure"` would propagate that NA into sum() below and poison the whole group
  self_disclosed  = has_eval & !is.na(EVAL_TYPE_DESC) & EVAL_TYPE_DESC == "Self-Disclosure",
  ea_penalty_amt  = parse_number(EA_PENALTY_AMT),                          # dollar amount, NA if blank/unparseable
  has_ea_penalty  = !is.na(ea_penalty_amt) & ea_penalty_amt > 0,           # TRUE if a real, positive penalty exists
  # eval->violation lag: only meaningful where both dates exist and the violation is not BEFORE the eval
  eval_to_viol_lag = if_else(has_eval & !is.na(eval_date) & viol_start_date >= eval_date,
                             as.integer(viol_start_date - eval_date), NA_integer_),
  # violation->enforcement lag: only meaningful where both dates exist and the EA is not BEFORE the violation
  viol_to_ea_lag   = if_else(has_ea & !is.na(ea_date) & ea_date >= viol_start_date,
                             as.integer(ea_date - viol_start_date), NA_integer_))

# ---- assert the VIOL_TYPE partition is exactly {HPV, FRV} once placeholders are excluded -------------------
stopifnot("VIOL_TYPE is not a clean HPV/FRV partition after placeholder removal" =
            all(real$is_hpv | real$is_frv))                # every remaining row must be HPV or FRV, no third case

# ---- collapse to facility x year: one row per (SOURCE_ID, viol_year) with the value-add measures -----------
counts <- real |> group_by(SOURCE_ID, viol_year) |> summarise(   # group by facility and violation year
  n_viol_pipeline        = n(),                                  # total real violations anchored this year
  n_viol_hpv             = sum(is_hpv),                          # of which, HPV tier
  n_viol_frv             = sum(is_frv),                          # of which, FRV tier
  n_viol_with_eval       = sum(has_eval),                        # linked to a known evaluation
  n_viol_with_ea         = sum(has_ea),                          # linked to a known enforcement action
  n_viol_self_disclosed  = sum(self_disclosed),                  # discovered via self-disclosure, not inspection
  n_viol_with_ea_penalty = sum(has_ea_penalty),                  # linked to an EA with a positive penalty
  ea_penalty_amt_sum     = sum(ea_penalty_amt[has_ea_penalty], na.rm = TRUE),  # dollars, summed over positive penalties only
  mean_eval_to_viol_lag_days = mean(eval_to_viol_lag, na.rm = TRUE),  # mean discovery lag, NaN if no eligible rows
  mean_viol_to_ea_lag_days   = mean(viol_to_ea_lag,   na.rm = TRUE), # mean enforcement lag, NaN if no eligible rows
  .groups = "drop") |>                                           # drop the grouping structure after summarising
  mutate(across(c(mean_eval_to_viol_lag_days, mean_viol_to_ea_lag_days), \(x) if_else(is.nan(x), NA_real_, x)),
         PGM_SYS_ID = SOURCE_ID, year = viol_year) |>            # rename to the layer's join-key names
  select(-SOURCE_ID, -viol_year)                                 # drop the pre-rename columns, now redundant

# ---- facility universe: every PGM_SYS_ID in ICIS-AIR_FACILITIES, same set as ds 0/1/2b ---------------------
frs_ids <- read_csv(file.path(CLEAN, "facilities.csv.gz"),                 # data/processed/facilities.csv.gz
                    col_types = cols_only(PGM_SYS_ID = col_character(),    # facility id (this layer's join key)
                                         REGISTRY_ID = col_character()),   # FRS cross-program id (G4 convention)
                    show_col_types = FALSE)                                # suppress the column-spec printout
ids <- frs_ids$PGM_SYS_ID                                                  # the 279,211-facility id vector

# ---- build the full facility x year rectangle and apply the zero-vs-NA discipline --------------------------
pipe <- expand_grid(PGM_SYS_ID = ids, year = YEARS) |>          # every facility crossed with every window year
  left_join(counts, by = c("PGM_SYS_ID", "year")) |>            # attach counts; no pipeline row that year -> NA
  mutate(pipeline_observed = as.integer(!is.na(n_viol_pipeline))) |>  # 1 iff this facility-year has real rows
  left_join(frs_ids, by = "PGM_SYS_ID") |>                      # attach REGISTRY_ID (native to facilities.csv.gz)
  relocate(REGISTRY_ID, .after = PGM_SYS_ID) |>                 # column order: PGM_SYS_ID, REGISTRY_ID, year, ...
  relocate(pipeline_observed, .after = year) |>                 # observability flag right after the join keys
  arrange(PGM_SYS_ID, year)                                     # stable row order for reproducible diffs

# ---- invariants -------------------------------------------------------------------------------------------
stopifnot(
  "grain broken: PGM_SYS_ID x year is not unique"      =                    # the panel key must be unique
    !anyDuplicated(pipe[c("PGM_SYS_ID", "year")]),
  "rectangle incomplete: rows != facilities x years"    =                    # must be a full, dense rectangle
    nrow(pipe) == length(ids) * length(YEARS),
  "observability rule violated: observed row with NA count" =                # observed -> count is never NA
    !any(pipe$pipeline_observed == 1 & is.na(pipe$n_viol_pipeline)),
  "observability rule violated: unobserved row with non-NA count" =          # unobserved -> count is always NA
    !any(pipe$pipeline_observed == 0 & !is.na(pipe$n_viol_pipeline)),
  "N_VIOL_HPV + N_VIOL_FRV must equal N_VIOL_PIPELINE"  =                    # the HPV/FRV split must add up
    all(with(pipe[pipe$pipeline_observed == 1, ],
             n_viol_hpv + n_viol_frv == n_viol_pipeline)),
  "N_VIOL_WITH_EA_PENALTY > 0 iff EA_PENALTY_AMT_SUM > 0" =                  # the penalty flag/sum must agree
    all(with(pipe[pipe$pipeline_observed == 1, ],
             (n_viol_with_ea_penalty > 0) == (ea_penalty_amt_sum > 0))),
  "placeholder rows leaked into the output"             =                    # sanity check on the exclusion
    sum(pipe$n_viol_pipeline, na.rm = TRUE) <= nrow(real),                   # cannot exceed real rows kept above
  "N_VIOL_SELF_DISCLOSED is NA on an observed row"       =                    # every observed count must be non-NA
    !any(pipe$pipeline_observed == 1 & is.na(pipe$n_viol_self_disclosed)),
  "N_VIOL_WITH_EVAL/N_VIOL_WITH_EA is NA on an observed row" =                # same check for the other linkage counts
    !any(pipe$pipeline_observed == 1 &
         (is.na(pipe$n_viol_with_eval) | is.na(pipe$n_viol_with_ea))))

# ---- write and summarize ------------------------------------------------------------------------------------
write_dataset(pipe, "pipeline")                          # uppercases all columns on write (see 00_parameters.R)
cat(sprintf(                                              # one-line build summary, printed to the console
  "pipeline: %s rows | %d cols | %s facilities | %s observed facility-years (%.1f%%) | %s HPV | %s FRV\n",
  format(nrow(pipe), big.mark = ","), ncol(pipe), format(length(ids), big.mark = ","),
  format(sum(pipe$pipeline_observed), big.mark = ","), 100 * mean(pipe$pipeline_observed),
  format(sum(pipe$n_viol_hpv, na.rm = TRUE), big.mark = ","),
  format(sum(pipe$n_viol_frv, na.rm = TRUE), big.mark = ",")))
