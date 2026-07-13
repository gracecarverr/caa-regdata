# =========================================================================================================
# scripts/04_panels/universe.R -- sample panel: every ever-active facility (contiguous US) x year, with the
#   four regulatory-activity counts and facility attributes.
#   out: data/panels/universe.csv.gz
# =========================================================================================================
source(here::here("R/panel.R"))

measures <- c("inspections", "violations", "enforcement", "certs")

# facilities in scope: all ever-active facilities in the contiguous US (+ DC)
facs <- read_csv(file.path(CLEAN, "facilities.csv.gz"),
                 col_types = cols(PGM_SYS_ID = col_character(), .default = col_guess()),
                 show_col_types = FALSE) |>
  filter(STATE %in% CONUS)

panel <- facility_year_panel(facs, measures, YEARS)

write_csv(panel, file.path(PANELS, "universe.csv.gz"))
cat(sprintf("universe panel: %d rows | %d facilities | %d-%d\n",
            nrow(panel), n_distinct(panel$PGM_SYS_ID), min(YEARS), max(YEARS)))
