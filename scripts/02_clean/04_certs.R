# =========================================================================================================
# scripts/02_clean/04_certs.R -- clean ICIS-Air Title V certifications into the `certs` asset.
#   in : data/raw/ICIS-AIR_downloads/ICIS-AIR_TITLEV_CERTS.csv
#   out: data/clean/certs.csv.gz  (one row per raw record; distinct certifications = filter(dup == 0))
#
#   The raw table carries ~5 rows per certification (one per program/pollutant), so it is heavily
#   duplicated at the certification grain. NO deduplication: every row is kept and flagged; filter
#   dup == 0 for one row per certification. Date = ACTUAL_END_DATE (certification date).
# =========================================================================================================
source(here::here("R/clean.R"))

src <- file.path(RAW, "ICIS-AIR_downloads", "ICIS-AIR_TITLEV_CERTS.csv")
d <- read_csv(src,
  col_select = c(PGM_SYS_ID, ACTIVITY_ID, STATE_EPA_FLAG, ACTUAL_END_DATE, FACILITY_RPT_DEVIATION_FLAG),
  col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  mutate(date = mdy(ACTUAL_END_DATE, quiet = TRUE), year = year(date))

n_in <- nrow(d)
d <- d |> filter(!is.na(PGM_SYS_ID), PGM_SYS_ID != "", !is.na(year))
cat(sprintf("  dropped %d of %d rows (%.1f%%) with no PGM_SYS_ID or unparseable date\n",
            n_in - nrow(d), n_in, 100 * (n_in - nrow(d)) / n_in))

d <- d |>
  transmute(PGM_SYS_ID, activity_id = ACTIVITY_ID, date, year,
            deviation_flag = FACILITY_RPT_DEVIATION_FLAG, agency = STATE_EPA_FLAG) |>
  add_dup_flags(c("PGM_SYS_ID", "activity_id"))

write_asset(d, "certs", dict = c(
  PGM_SYS_ID     = "ICIS-Air facility (program-system) id",
  activity_id    = "distinct certification id (the event id)",
  date           = "certification date (ACTUAL_END_DATE, parsed)",
  year           = "certification calendar year",
  deviation_flag = "facility-reported deviation flag (FACILITY_RPT_DEVIATION_FLAG; Y/N)",
  agency         = "agency flag (STATE_EPA_FLAG)",
  dup            = "occurrence index within (PGM_SYS_ID, activity_id); 0 = first row (one per certification)",
  dup_exact      = "1 if byte-identical (on kept columns) to an earlier row"
))
