# =========================================================================================================
# scripts/04_panels/universe.R -- sample panel: every ever-active facility (contiguous US) x year, with the
#   regulatory-activity counts and facility attributes.
#   in : data/panels/spine.csv.gz  +  data/clean/{inspections,violations,formal_actions,informal_actions,certs}.csv.gz
#   out: data/panels/universe.csv.gz
#   Standalone: the panel recipe is spelled out inline (no shared helpers, no config).
# =========================================================================================================
library(readr); library(dplyr); library(tidyr)

CLEAN  <- here::here("data/clean"); PANELS <- here::here("data/panels")
YEARS  <- 2005:2025
# 48 contiguous states + DC (excludes AK, HI, and all territories)
CONUS  <- c("AL","AZ","AR","CA","CO","CT","DE","DC","FL","GA","ID","IL","IN","IA","KS","KY","LA","ME","MD",
            "MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH","OK","OR","PA","RI",
            "SC","SD","TN","TX","UT","VT","VA","WA","WV","WI","WY")
measures <- c("inspections", "violations", "formal_actions", "informal_actions", "certs")

# distinct events (dup == 0) per facility-year for one clean asset, restricted to YEARS -> n_<name>
count_events <- function(name) {
  read_csv(file.path(CLEAN, paste0(name, ".csv.gz")),
           col_select = c(PGM_SYS_ID, year, dup),
           col_types = cols(PGM_SYS_ID = col_character(), year = col_integer(), dup = col_integer()),
           show_col_types = FALSE) |>
    filter(dup == 0, year %in% YEARS) |>
    count(PGM_SYS_ID, year, name = paste0("n_", name))
}

# balanced facility x year panel of distinct-event counts for facility frame `facs`.
#   n_<measure>: 0 = facility-year observed (>=1 event of some measure) but none of THIS measure (true zero);
#                NA = facility-year not observed at all (cannot assert a zero).
facility_year_panel <- function(facs) {
  counts <- Reduce(\(x, y) full_join(x, y, by = c("PGM_SYS_ID", "year")), lapply(measures, count_events)) |>
    filter(PGM_SYS_ID %in% facs$PGM_SYS_ID) |>
    mutate(across(starts_with("n_"), \(x) as.integer(coalesce(x, 0L))))     # observed year, no event -> 0
  expand_grid(PGM_SYS_ID = facs$PGM_SYS_ID, year = YEARS) |>                # balanced rectangle
    left_join(counts, by = c("PGM_SYS_ID", "year")) |>                      # absent facility-years stay NA
    left_join(facs,   by = "PGM_SYS_ID") |>
    arrange(PGM_SYS_ID, year)
}

# facilities in scope: all ever-active facilities in the contiguous US (+ DC)
facs <- read_csv(file.path(PANELS, "spine.csv.gz"),
                 col_types = cols(PGM_SYS_ID = col_character(), .default = col_guess()),
                 show_col_types = FALSE) |>
  filter(STATE %in% CONUS)

panel <- facility_year_panel(facs)

dir.create(PANELS, showWarnings = FALSE, recursive = TRUE)
write_csv(panel, file.path(PANELS, "universe.csv.gz"))
cat(sprintf("universe panel: %d rows | %d facilities | %d-%d\n",
            nrow(panel), n_distinct(panel$PGM_SYS_ID), min(YEARS), max(YEARS)))
