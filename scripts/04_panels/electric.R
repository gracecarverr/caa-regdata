# =========================================================================================================
# scripts/04_panels/electric.R -- sample panel: electric utilities (contiguous US) x year, with the
#   activity counts, facility attributes, and PM2.5 (2012) nonattainment treatment attached.
#   in : data/panels/{spine,attainment}.csv.gz  +  data/clean/{inspections,violations,formal_actions,informal_actions,certs}.csv.gz
#   out: data/panels/electric.csv.gz
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

# attach PM2.5 (2012) nonattainment treatment (needs latitude/longitude columns on the panel).
#   pm25_status = N (nonattainment) / M (maintenance) / NA (not in a PM2.5 NAA, or outside coverage)
#   pm25_area   = NAA area name (NA if none)
#   naa_pm25    = 1 nonattainment / 0 maintenance-or-attainment /
#                 NA outside the PM2.5 coverage window or for an unplaceable facility (no coordinate).
attach_pm25_attainment <- function(panel) {
  att   <- read_csv(file.path(PANELS, "attainment.csv.gz"),
                    col_select = c(PGM_SYS_ID, year, status, area_name),
                    col_types = cols(PGM_SYS_ID = col_character(), year = col_integer(), .default = col_guess()),
                    show_col_types = FALSE)
  cover <- range(att$year)                                                  # PM2.5 snapshot window
  panel |>
    left_join(transmute(att, PGM_SYS_ID, year, pm25_status = status, pm25_area = area_name),
              by = c("PGM_SYS_ID", "year")) |>
    mutate(naa_pm25 = if_else(!(year >= cover[1] & year <= cover[2]) | is.na(latitude) | is.na(longitude),
                              NA_integer_,
                              if_else(is.na(pm25_status), 0L, as.integer(pm25_status == "N"))))
}

# facilities in scope: CONUS major / synthetic-minor electric utilities (NAICS 2211 or SIC 4911)
facs <- read_csv(file.path(PANELS, "spine.csv.gz"),
                 col_types = cols(PGM_SYS_ID = col_character(), .default = col_guess()),
                 show_col_types = FALSE) |>
  filter(STATE %in% CONUS,
         AIR_POLLUTANT_CLASS_DESC %in% c("Major Emissions", "Synthetic Minor Emissions"),
         grepl("(^|[^0-9])2211", NAICS_CODES) | grepl("(^|[^0-9])4911([^0-9]|$)", SIC_CODES))

panel <- facility_year_panel(facs) |> attach_pm25_attainment()

dir.create(PANELS, showWarnings = FALSE, recursive = TRUE)
write_csv(panel, file.path(PANELS, "electric.csv.gz"))
cat(sprintf("electric panel: %d rows | %d facilities | %d ever in a PM2.5 NAA\n",
            nrow(panel), n_distinct(panel$PGM_SYS_ID),
            n_distinct(panel$PGM_SYS_ID[!is.na(panel$pm25_status)])))
