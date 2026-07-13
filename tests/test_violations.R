# =========================================================================================================
# tests/test_violations.R -- invariants for the violations asset. Run after a build:
#   Rscript tests/test_violations.R
# =========================================================================================================
source(here::here("R/setup.R"))

v <- readr::read_csv(file.path(CLEAN, "violations.csv.gz"),
  col_types = cols(PGM_SYS_ID = col_character(), comp_determination_uid = col_character(),
                   year = col_integer(), hpv = col_integer(), dup = col_integer(),
                   dup_exact = col_integer(), .default = col_guess()), show_col_types = FALSE)

req <- c("PGM_SYS_ID","comp_determination_uid","date","year","hpv","hpv_dayzero_date",
         "hpv_resolved_date","program","pollutant","agency","dup","dup_exact")
stopifnot("all required columns present"        = all(req %in% names(v)))
stopifnot("keys non-missing"                    = !any(is.na(v$PGM_SYS_ID)) && all(v$PGM_SYS_ID != "") && !any(is.na(v$year)))
stopifnot("hpv is 0/1"                          = all(v$hpv %in% c(0L, 1L)))
stopifnot("dup==0 reconstructs distinct events" = sum(v$dup == 0) == nrow(dplyr::distinct(v, PGM_SYS_ID, comp_determination_uid)))
stopifnot("dup_exact implies dup>0"             = all(v$dup[v$dup_exact == 1L] > 0))

cat(sprintf("violations test: PASS | %d rows | %d events (dup==0) | %d HPV | %.1f%% dup rows\n",
            nrow(v), sum(v$dup == 0), sum(v$hpv[v$dup == 0]), 100 * mean(v$dup > 0)))
