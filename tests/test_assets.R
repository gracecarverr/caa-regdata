# =========================================================================================================
# tests/test_assets.R -- cleaning-logic invariants for every clean asset. Run after a build:
#   Rscript tests/test_assets.R
# These assert properties that must hold regardless of the source snapshot (no hard-coded counts).
# =========================================================================================================
source(here::here("R/setup.R"))

# Event assets, keyed by the columns that define a distinct event.
event_specs <- list(
  inspections = c("PGM_SYS_ID", "activity_id"),
  violations  = c("PGM_SYS_ID", "comp_determination_uid"),
  enforcement = c("kind", "PGM_SYS_ID", "enf_identifier"),
  certs       = c("PGM_SYS_ID", "activity_id"),
  stacktests  = c("PGM_SYS_ID", "activity_id"))

check_event <- function(name, id_cols) {
  d <- readr::read_csv(file.path(CLEAN, paste0(name, ".csv.gz")),
    col_types = cols(PGM_SYS_ID = col_character(), year = col_integer(),
                     dup = col_integer(), dup_exact = col_integer(), .default = col_guess()),
    show_col_types = FALSE)
  stopifnot("required columns present" = all(c(id_cols, "year", "dup", "dup_exact") %in% names(d)))
  stopifnot("keys non-missing"         = !any(is.na(d$PGM_SYS_ID)) && all(d$PGM_SYS_ID != "") && !any(is.na(d$year)))
  stopifnot("dup==0 reconstructs distinct events" = sum(d$dup == 0) == nrow(dplyr::distinct(d[id_cols])))
  stopifnot("dup_exact implies dup>0"  = all(d$dup[d$dup_exact == 1L] > 0))
  cat(sprintf("  %-12s PASS | %d rows | %d events (dup==0) | %.1f%% dup rows\n",
              name, nrow(d), sum(d$dup == 0), 100 * mean(d$dup > 0)))
}

cat("event assets:\n")
for (a in names(event_specs)) check_event(a, event_specs[[a]])

# Facilities spine: one row per facility, no dup flags (that grain is definitional).
f <- readr::read_csv(file.path(CLEAN, "facilities.csv.gz"),
  col_types = cols(PGM_SYS_ID = col_character(), .default = col_guess()), show_col_types = FALSE)
stopifnot("spine has no dup flags"     = !("dup" %in% names(f)))
stopifnot("one row per facility"       = nrow(f) == dplyr::n_distinct(f$PGM_SYS_ID))
stopifnot("required spine columns"     = all(c("REGISTRY_ID","county_fips","AIR_POLLUTANT_CLASS_DESC",
                                               "prog_titlev","n_programs") %in% names(f)))
cat(sprintf("facilities   PASS | %d facilities (one row each) | %d columns\n", nrow(f), ncol(f)))

# Attainment: facility x year inside a PM2.5 NAA (treatment layer).
a <- readr::read_csv(file.path(CLEAN, "attainment.csv.gz"),
  col_types = cols(PGM_SYS_ID = col_character(), year = col_integer(), .default = col_guess()), show_col_types = FALSE)
stopifnot("attainment status is N/M"        = all(a$status %in% c("N", "M")))
stopifnot("attainment required columns"     = all(c("composid","area_name","status","imputed") %in% names(a)))
stopifnot("one row per facility-year-area"  = nrow(a) == nrow(dplyr::distinct(a, PGM_SYS_ID, year, composid)))
cat(sprintf("attainment   PASS | %d facility-years | %d facilities in a NAA | %d areas\n",
            nrow(a), dplyr::n_distinct(a$PGM_SYS_ID), dplyr::n_distinct(a$composid)))
cat("\nall asset invariants passed\n")
