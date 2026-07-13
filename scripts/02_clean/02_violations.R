# =========================================================================================================
# scripts/02_clean/02_violations.R -- clean ICIS-Air VIOLATION HISTORY into the `violations` asset.
#   in : data/raw/ICIS-AIR_downloads/ICIS-AIR_VIOLATION_HISTORY.csv   (one row per raw determination record)
#   out: data/clean/violations.csv.gz  (one row per raw record; distinct determinations = filter(dup == 0))
#
#   Determination date = first non-blank of (EARLIEST_FRV_DETERM_DATE, HPV_DAYZERO_DATE). HPV spell endpoints
#   are kept as parsed Dates so a panel can derive time-in-HPV-status. NO deduplication: all rows kept,
#   duplicates flagged. Coverage of both date fields ramps up over the window -- early-year counts are a
#   reporting artifact, not a real decline (documented in docs/nuances.qmd).
# =========================================================================================================
source(here::here("R/clean.R"))

src <- file.path(RAW, "ICIS-AIR_downloads", "ICIS-AIR_VIOLATION_HISTORY.csv")
raw <- read_csv(src,
  col_select = c(PGM_SYS_ID, COMP_DETERMINATION_UID, EARLIEST_FRV_DETERM_DATE, HPV_DAYZERO_DATE,
                 HPV_RESOLVED_DATE, PROGRAM_DESCS, POLLUTANT_DESCS, AGENCY_TYPE_DESC),
  col_types = cols(.default = col_character()), show_col_types = FALSE)

raw$raw_date <- first_nonblank(raw, c("EARLIEST_FRV_DETERM_DATE", "HPV_DAYZERO_DATE"))

d <- raw |>
  mutate(date = mdy(raw_date, quiet = TRUE), year = year(date),
         hpv  = as.integer(!is.na(HPV_DAYZERO_DATE) & HPV_DAYZERO_DATE != ""),
         hpv_dayzero_date  = mdy(HPV_DAYZERO_DATE,  quiet = TRUE),
         hpv_resolved_date = mdy(HPV_RESOLVED_DATE, quiet = TRUE))

n_in <- nrow(d)
d <- d |> filter(!is.na(PGM_SYS_ID), PGM_SYS_ID != "", !is.na(year))   # drop unkeyable / undated (never impute)
cat(sprintf("  dropped %d of %d rows (%.1f%%) with no PGM_SYS_ID or unparseable date\n",
            n_in - nrow(d), n_in, 100 * (n_in - nrow(d)) / n_in))

d <- d |>
  transmute(PGM_SYS_ID, comp_determination_uid = COMP_DETERMINATION_UID, date, year, hpv,
            hpv_dayzero_date, hpv_resolved_date,
            program = PROGRAM_DESCS, pollutant = POLLUTANT_DESCS, agency = AGENCY_TYPE_DESC) |>
  add_dup_flags(c("PGM_SYS_ID", "comp_determination_uid"))

write_asset(d, "violations", dict = c(
  PGM_SYS_ID             = "ICIS-Air facility (program-system) id",
  comp_determination_uid = "distinct compliance-determination id (the event id)",
  date                   = "determination date: first non-blank of EARLIEST_FRV_DETERM_DATE / HPV_DAYZERO_DATE (parsed)",
  year                   = "determination calendar year",
  hpv                    = "1 if a High Priority Violation (HPV_DAYZERO_DATE present), else 0",
  hpv_dayzero_date       = "HPV clock start (parsed Date; NA for non-HPV)",
  hpv_resolved_date      = "HPV close (parsed Date; NA if unresolved)",
  program                = "regulatory program(s), delimited string (PROGRAM_DESCS)",
  pollutant              = "pollutant(s), delimited string (POLLUTANT_DESCS)",
  agency                 = "agency type (AGENCY_TYPE_DESC)",
  dup                    = "occurrence index within (PGM_SYS_ID, comp_determination_uid); 0 = first row -> filter for event level",
  dup_exact              = "1 if byte-identical (on kept columns) to an earlier row"
))
