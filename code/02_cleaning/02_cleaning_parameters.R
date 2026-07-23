# =========================================================================================================
# 02_cleaning_parameters.R -- per-source configuration for the regular (non-Wayback) cleaners.
#
#   Each entry of CLEAN_SPECS describes one raw source table and how the bare-bones cleaner should treat it.
#   The driver 02_clean.R loops over this list and calls clean_one() (02_cleaning_functions.R) on each.
#
#   Fields:
#     name  -- output stem; the cleaned asset is data/processed/<name>.csv.gz
#     raw   -- input path relative to data/raw/
#     date  -- OPTIONAL function(d) -> Date. Present only for "event" tables (a dated occurrence per row);
#              its result becomes the `date` column and drives `year`. Omit for attribute/lookup tables.
#     key   -- OPTIONAL character vector of columns defining a within-facility event key; presence adds the
#              0-based `dup` occurrence index. Omit for attribute tables (they get only `dup_exact`).
#
#   Every spec keeps ALL original columns and ALL rows -- see 02_cleaning_parameters_README.md and the
#   per-file READMEs in data/processed/ for column-level and institutional detail.
# =========================================================================================================

CLEAN_SPECS <- list(

  # ---- ICIS-Air EVENT tables (dated occurrences: date + year + dup + dup_exact) -------------------------
  # Compliance monitoring evaluations (Full/Partial Compliance Evaluations). date = evaluation completion.
  list(name = "inspections", raw = "ICIS-AIR_downloads/ICIS-AIR_FCES_PCES.csv",
       date = function(d) mdy(d$ACTUAL_END_DATE, quiet = TRUE),
       key  = c("PGM_SYS_ID", "ACTIVITY_ID")),

  # Violation history. date = first non-blank of the two determination dates (FRV determination, else HPV day-zero).
  list(name = "violations", raw = "ICIS-AIR_downloads/ICIS-AIR_VIOLATION_HISTORY.csv",
       date = function(d) coalesce(mdy(d$EARLIEST_FRV_DETERM_DATE, quiet = TRUE),
                                   mdy(d$HPV_DAYZERO_DATE,          quiet = TRUE)),
       key  = c("PGM_SYS_ID", "COMP_DETERMINATION_UID")),

  # Formal enforcement actions. date = settlement entered date.
  list(name = "formal_actions", raw = "ICIS-AIR_downloads/ICIS-AIR_FORMAL_ACTIONS.csv",
       date = function(d) mdy(d$SETTLEMENT_ENTERED_DATE, quiet = TRUE),
       key  = c("PGM_SYS_ID", "ENF_IDENTIFIER")),

  # Informal enforcement actions. date = achieved date.
  list(name = "informal_actions", raw = "ICIS-AIR_downloads/ICIS-AIR_INFORMAL_ACTIONS.csv",
       date = function(d) mdy(d$ACHIEVED_DATE, quiet = TRUE),
       key  = c("PGM_SYS_ID", "ENF_IDENTIFIER")),

  # Title V annual compliance certifications. date = certification period end (ACTUAL_END_DATE).
  list(name = "certs", raw = "ICIS-AIR_downloads/ICIS-AIR_TITLEV_CERTS.csv",
       date = function(d) mdy(d$ACTUAL_END_DATE, quiet = TRUE),
       key  = c("PGM_SYS_ID", "ACTIVITY_ID")),

  # Stack tests (emissions performance tests). date = test completion (ACTUAL_END_DATE).
  list(name = "stacktests", raw = "ICIS-AIR_downloads/ICIS-AIR_STACK_TESTS.csv",
       date = function(d) mdy(d$ACTUAL_END_DATE, quiet = TRUE),
       key  = c("PGM_SYS_ID", "ACTIVITY_ID")),

  # ---- ICIS-Air ATTRIBUTE / LOOKUP tables (one row per entity; dup_exact only) --------------------------
  # Facility attributes. The derived facility SPINE (coordinates, county, profiles) is built in the panel layer.
  list(name = "facilities",       raw = "ICIS-AIR_downloads/ICIS-AIR_FACILITIES.csv"),
  list(name = "pollutants",       raw = "ICIS-AIR_downloads/ICIS-AIR_POLLUTANTS.csv"),
  list(name = "programs",         raw = "ICIS-AIR_downloads/ICIS-AIR_PROGRAMS.csv"),
  list(name = "program_subparts", raw = "ICIS-AIR_downloads/ICIS-AIR_PROGRAM_SUBPARTS.csv"),

  # ---- AFS (legacy pre-2001 Air Facility System) ATTRIBUTE tables (dup_exact only) ----------------------
  list(name = "afs_actions",         raw = "afs_downloads/AFS_ACTIONS.csv"),
  list(name = "afs_air_program",     raw = "afs_downloads/AIR_PROGRAM.csv"),
  list(name = "afs_facilities",      raw = "afs_downloads/AFS_FACILITIES.csv"),
  list(name = "afs_hist_compliance", raw = "afs_downloads/AFS_AIR_PRG_HIST_COMPLIANCE.csv"),
  list(name = "afs_hpv",             raw = "afs_downloads/AFS_HPV_HISTORY.csv"),

  # ---- Emissions ----------------------------------------------------------------------------------------
  # Combined emissions report. REPORTING_YEAR is already present in the source, so no date parse is needed.
  list(name = "emissions", raw = "POLL_RPT_COMBINED_EMISSIONS.csv"),

  # ---- CAA Compliance Pipeline (ECHO) -------------------------------------------------------------------
  # One row per violation, optionally linked to the evaluation that found it and the enforcement action it
  # triggered (see docs/data_dictionary.md "CAA Compliance Pipeline"). date = SORT_DATE, EPA's own display-
  # order date (= EA_DATE if an EA is linked, else VIOL_START_DATE, else EVAL_DATE -- verified exact match on
  # every non-blank row). SORT_ORDER is a globally-unique row id, so `dup` is trivially 0 everywhere; kept
  # for convention consistency, and `dup_exact` still catches byte-identical rows. The dataset-layer builder
  # (code/04_datasets/07_pipeline.R) uses VIOL_START_DATE, not this date, as its facility-year anchor.
  list(name = "pipeline", raw = "PIPELINE_CAA_00_COMPLETE.csv",
       date = function(d) mdy(d$SORT_DATE, quiet = TRUE),
       key  = c("SOURCE_ID", "SORT_ORDER"))
)
