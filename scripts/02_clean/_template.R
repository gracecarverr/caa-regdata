# =========================================================================================================
# scripts/02_clean/_template.R -- the pattern every cleaning script follows. COPY, don't source.
#   Real cleaners are number-prefixed so run_all.R runs them in dependency order, e.g.
#     01_inspections.R  02_violations.R  ...  09_facilities.R   (the spine runs LAST).
#   The leading "_" keeps this template from being picked up by run_all.R (^[0-9] pattern).
#
# Contract for a cleaning script:
#   - reads exactly ONE raw source from RAW
#   - parses / types / flags only; NO sample selection, aggregation, or cross-dataset joins
#   - keeps every row (no dedup); labels duplicates with add_dup_flags()
#   - drops only unkeyable / undated rows, and reports how many
#   - calls write_asset() with a dictionary covering EVERY output column
# =========================================================================================================
source(here::here("R/clean.R"))

# d <- read_csv(file.path(RAW, "<SOURCE_FILE>.csv"), col_types = cols(.default = col_character())) |>
#   mutate(date = mdy(<DATE_COL>, quiet = TRUE), year = year(date)) |>
#   filter(!is.na(PGM_SYS_ID), PGM_SYS_ID != "", !is.na(year)) |>
#   transmute(PGM_SYS_ID, <event_id> = <RAW_ID>, date, year, <kept fields...>) |>
#   add_dup_flags(c("PGM_SYS_ID", "<event_id>"))
#
# write_asset(d, "<asset_name>", dict = c(
#   PGM_SYS_ID = "ICIS-Air facility id",
#   <event_id> = "distinct-event id from the raw table",
#   date       = "event date (parsed)",
#   year       = "event calendar year",
#   dup        = "occurrence index within event id (0 = first row; filter dup==0 for event-level)",
#   dup_exact  = "1 if byte-identical to an earlier row"
# ))
