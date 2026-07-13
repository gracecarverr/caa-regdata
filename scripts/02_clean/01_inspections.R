# =========================================================================================================
# scripts/02_clean/01_inspections.R -- clean ICIS-Air FCE/PCE evaluations into the `inspections` asset.
#   in : data/raw/ICIS-AIR_downloads/ICIS-AIR_FCES_PCES.csv   (one row per compliance evaluation)
#   out: data/clean/inspections.csv.gz  (one row per raw record; distinct evaluations = filter(dup == 0))
#
#   Full (FCE) and partial (PCE) compliance evaluations are pooled into one "inspections" measure; the
#   `type` column preserves the full-vs-partial distinction. Date = ACTUAL_END_DATE (evaluation completion).
#   NO deduplication: all rows kept, duplicates flagged.
# =========================================================================================================
source(here::here("R/clean.R"))

src <- file.path(RAW, "ICIS-AIR_downloads", "ICIS-AIR_FCES_PCES.csv")
d <- read_csv(src,
  col_select = c(PGM_SYS_ID, ACTIVITY_ID, STATE_EPA_FLAG, ACTIVITY_TYPE_DESC, COMP_MONITOR_TYPE_DESC, ACTUAL_END_DATE),
  col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  mutate(date = mdy(ACTUAL_END_DATE, quiet = TRUE), year = year(date))

n_in <- nrow(d)
d <- d |> filter(!is.na(PGM_SYS_ID), PGM_SYS_ID != "", !is.na(year))
cat(sprintf("  dropped %d of %d rows (%.1f%%) with no PGM_SYS_ID or unparseable date\n",
            n_in - nrow(d), n_in, 100 * (n_in - nrow(d)) / n_in))

d <- d |>
  transmute(PGM_SYS_ID, activity_id = ACTIVITY_ID, date, year,
            type = ACTIVITY_TYPE_DESC, monitor_type = COMP_MONITOR_TYPE_DESC, agency = STATE_EPA_FLAG) |>
  add_dup_flags(c("PGM_SYS_ID", "activity_id"))

write_asset(d, "inspections", dict = c(
  PGM_SYS_ID   = "ICIS-Air facility (program-system) id",
  activity_id  = "distinct evaluation id (the event id)",
  date         = "evaluation completion date (ACTUAL_END_DATE, parsed)",
  year         = "evaluation calendar year",
  type         = "evaluation type (ACTIVITY_TYPE_DESC) -- full (FCE) vs partial (PCE) etc.",
  monitor_type = "compliance-monitoring type (COMP_MONITOR_TYPE_DESC)",
  agency       = "conducting agency flag (STATE_EPA_FLAG: E=EPA / S=State / L=Local)",
  dup          = "occurrence index within (PGM_SYS_ID, activity_id); 0 = first row",
  dup_exact    = "1 if byte-identical (on kept columns) to an earlier row"
))
