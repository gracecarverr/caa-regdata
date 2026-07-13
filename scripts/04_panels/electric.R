# =========================================================================================================
# scripts/04_panels/electric.R -- sample panel: electric utilities (contiguous US) x year, with the four
#   activity counts, facility attributes, and PM2.5 (2012) nonattainment treatment attached.
#   out: data/panels/electric.csv.gz
# =========================================================================================================
source(here::here("R/panel.R"))

measures <- c("inspections", "violations", "enforcement", "certs")

# facilities in scope: CONUS major / synthetic-minor electric utilities (NAICS 2211 or SIC 4911)
facs <- read_csv(file.path(CLEAN, "facilities.csv.gz"),
                 col_types = cols(PGM_SYS_ID = col_character(), .default = col_guess()),
                 show_col_types = FALSE) |>
  filter(STATE %in% CONUS,
         AIR_POLLUTANT_CLASS_DESC %in% c("Major Emissions", "Synthetic Minor Emissions"),
         grepl("(^|[^0-9])2211", NAICS_CODES) | grepl("(^|[^0-9])4911([^0-9]|$)", SIC_CODES))

panel <- facility_year_panel(facs, measures, YEARS) |>
  attach_pm25_attainment()

write_csv(panel, file.path(PANELS, "electric.csv.gz"))
cat(sprintf("electric panel: %d rows | %d facilities | %d ever in a PM2.5 NAA\n",
            nrow(panel), n_distinct(panel$PGM_SYS_ID),
            n_distinct(panel$PGM_SYS_ID[!is.na(panel$pm25_status)])))
