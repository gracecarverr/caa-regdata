# =========================================================================================================
# scripts/02_clean/16_emissions.R -- minimal: keep every column and every row of the combined emissions
#   report (POLL_RPT_COMBINED_EMISSIONS). REPORTING_YEAR is already present; adds only dup_exact.
# =========================================================================================================
library(readr); library(dplyr)

d <- read_csv(here::here("data/raw/POLL_RPT_COMBINED_EMISSIONS.csv"),
              col_types = cols(.default = col_character()), show_col_types = FALSE)
d$dup_exact <- as.integer(duplicated(d))

dir.create(here::here("data/clean"), showWarnings = FALSE, recursive = TRUE)
write_csv(d, here::here("data/clean/emissions.csv.gz"))
cat(sprintf("emissions: %d rows | %d columns\n", nrow(d), ncol(d)))
