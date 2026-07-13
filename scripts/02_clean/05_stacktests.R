# =========================================================================================================
# scripts/02_clean/05_stacktests.R -- clean ICIS-Air stack tests into the `stacktests` asset.
#   in : data/raw/ICIS-AIR_downloads/ICIS-AIR_STACK_TESTS.csv
#   out: data/clean/stacktests.csv.gz  (one row per raw record; distinct tests = filter(dup == 0))
#
#   One row per stack test; `status` records Pass / Fail / Pending / etc. Date = ACTUAL_END_DATE.
#   Stack-test pollutant detail is not carried (POLLUTANT_DESCS is effectively empty in the source).
#   NO deduplication: all rows kept, duplicates flagged.
# =========================================================================================================
source(here::here("R/clean.R"))

src <- file.path(RAW, "ICIS-AIR_downloads", "ICIS-AIR_STACK_TESTS.csv")
d <- read_csv(src,
  col_select = c(PGM_SYS_ID, ACTIVITY_ID, STATE_EPA_FLAG, ACTUAL_END_DATE, AIR_STACK_TEST_STATUS_DESC),
  col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  mutate(date = mdy(ACTUAL_END_DATE, quiet = TRUE), year = year(date))

n_in <- nrow(d)
d <- d |> filter(!is.na(PGM_SYS_ID), PGM_SYS_ID != "", !is.na(year))
cat(sprintf("  dropped %d of %d rows (%.1f%%) with no PGM_SYS_ID or unparseable date\n",
            n_in - nrow(d), n_in, 100 * (n_in - nrow(d)) / n_in))

d <- d |>
  transmute(PGM_SYS_ID, activity_id = ACTIVITY_ID, date, year,
            status = AIR_STACK_TEST_STATUS_DESC, agency = STATE_EPA_FLAG) |>
  add_dup_flags(c("PGM_SYS_ID", "activity_id"))

write_asset(d, "stacktests", dict = c(
  PGM_SYS_ID  = "ICIS-Air facility (program-system) id",
  activity_id = "distinct stack-test id (the event id)",
  date        = "stack-test date (ACTUAL_END_DATE, parsed)",
  year        = "stack-test calendar year",
  status      = "test result (AIR_STACK_TEST_STATUS_DESC: Pass / Fail / Pending / ...)",
  agency      = "agency flag (STATE_EPA_FLAG)",
  dup         = "occurrence index within (PGM_SYS_ID, activity_id); 0 = first row",
  dup_exact   = "1 if byte-identical (on kept columns) to an earlier row"
))
