# =========================================================================================================
# scripts/02_clean/07_facilities.R -- minimal: keep every column and every row of ICIS-Air facilities.
#   Attribute table (one row per facility in the source); adds only dup_exact (byte-identical row).
#   The derived facility SPINE (coordinates, county, profiles) is built in the panel layer, not here.
# =========================================================================================================
library(readr); library(dplyr)

d <- read_csv(here::here("data/raw/ICIS-AIR_downloads/ICIS-AIR_FACILITIES.csv"),
              col_types = cols(.default = col_character()), show_col_types = FALSE)
d$dup_exact <- as.integer(duplicated(d))

dir.create(here::here("data/clean"), showWarnings = FALSE, recursive = TRUE)
write_csv(d, here::here("data/clean/facilities.csv.gz"))
cat(sprintf("facilities: %d rows | %d columns\n", nrow(d), ncol(d)))
