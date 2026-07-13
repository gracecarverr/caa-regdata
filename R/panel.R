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

# Attach PM2.5 (2012) nonattainment treatment to a facility x year panel (needs latitude/longitude columns).
#   Adds, from the attainment asset:
#     pm25_status = N (nonattainment) / M (maintenance) / NA (not inside a PM2.5 NAA, or outside coverage)
#     pm25_area   = NAA area name (NA if none)
#     naa_pm25    = 1 nonattainment / 0 maintenance-or-attainment /
#                   NA outside the PM2.5 coverage window or for an unplaceable facility (no coordinate).
#   Coverage window is read from the asset itself (PM2.5 2012 std only).
attach_pm25_attainment <- function(panel) {
  att   <- read_csv(file.path(CLEAN, "attainment.csv.gz"),
                    col_select = c(PGM_SYS_ID, year, status, area_name),
                    col_types = cols(PGM_SYS_ID = col_character(), year = col_integer(), .default = col_guess()),
                    show_col_types = FALSE)
  cover <- range(att$year)                                  # PM2.5 snapshot window
  panel |>
    left_join(transmute(att, PGM_SYS_ID, year, pm25_status = status, pm25_area = area_name),
              by = c("PGM_SYS_ID", "year")) |>
    mutate(naa_pm25 = if_else(!(year >= cover[1] & year <= cover[2]) | is.na(latitude) | is.na(longitude),
                              NA_integer_,
                              if_else(is.na(pm25_status), 0L, as.integer(pm25_status == "N"))))
}
