# =========================================================================================================
# R/panel.R -- small helpers for the sample facility x year panels (scripts/04_panels/*.R).
#   Deliberately minimal and fixed-behavior (no toggles): the panel scripts are explicit recipes that
#   pick a set of facilities and call facility_year_panel(). Change the recipe, not a switch.
# =========================================================================================================
source(here::here("R/setup.R"))

# Distinct events (dup == 0) per facility-year for one clean asset, restricted to `years`.
#   Returns PGM_SYS_ID, year, n_<name>.
count_events <- function(name, years) {
  read_csv(file.path(CLEAN, paste0(name, ".csv.gz")),
           col_select = c(PGM_SYS_ID, year, dup),
           col_types = cols(PGM_SYS_ID = col_character(), year = col_integer(), dup = col_integer()),
           show_col_types = FALSE) |>
    filter(dup == 0, year %in% years) |>
    count(PGM_SYS_ID, year, name = paste0("n_", name))
}

# Balanced facility x year panel of distinct-event counts for a given facility frame `facs`.
#   n_<measure> = number of distinct events (dup == 0) that facility-year, for each measure.
#   Count meaning:
#     0  = facility-year was OBSERVED (>= 1 event of some measure) but none of THIS measure -- a true zero.
#     NA = facility-year was NOT observed at all -- we cannot assert a zero.
#   Facility attributes from `facs` are joined on. Rectangle = every facility in `facs` x every year.
facility_year_panel <- function(facs, measures, years) {
  # distinct-event counts per facility-year (observed facility-years only), one column per measure
  counts <- Reduce(\(x, y) full_join(x, y, by = c("PGM_SYS_ID", "year")),
                   lapply(measures, count_events, years = years)) |>
    filter(PGM_SYS_ID %in% facs$PGM_SYS_ID) |>
    mutate(across(starts_with("n_"), \(x) as.integer(coalesce(x, 0L))))   # observed year, no event -> 0

  # balanced frame; facility-years absent from `counts` stay NA (not observed)
  expand_grid(PGM_SYS_ID = facs$PGM_SYS_ID, year = years) |>
    left_join(counts, by = c("PGM_SYS_ID", "year")) |>
    left_join(facs,   by = "PGM_SYS_ID") |>
    arrange(PGM_SYS_ID, year)
}
