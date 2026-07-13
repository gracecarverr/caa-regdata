# =========================================================================================================
# scripts/04_panels/major_synmin.R -- sample panel: major + synthetic-minor facilities (contiguous US) x
#   year, with the four regulatory-activity counts and facility attributes. The larger regulated sources.
#   out: data/panels/major_synmin.csv.gz
# =========================================================================================================
source(here::here("R/panel.R"))

measures <- c("inspections", "violations", "enforcement", "certs")

# facilities in scope: CONUS facilities in the Major or Synthetic Minor emissions class
facs <- read_csv(file.path(CLEAN, "facilities.csv.gz"),
                 col_types = cols(PGM_SYS_ID = col_character(), .default = col_guess()),
                 show_col_types = FALSE) |>
  filter(STATE %in% CONUS,
         AIR_POLLUTANT_CLASS_DESC %in% c("Major Emissions", "Synthetic Minor Emissions"))

panel <- facility_year_panel(facs, measures, YEARS)

write_csv(panel, file.path(PANELS, "major_synmin.csv.gz"))
cat(sprintf("major_synmin panel: %d rows | %d facilities | %d-%d\n",
            nrow(panel), n_distinct(panel$PGM_SYS_ID), min(YEARS), max(YEARS)))
