# =========================================================================================================
# scripts/02_clean/09_programs.R -- minimal: keep every column and every row of ICIS-Air programs.
#   Adds only dup_exact (byte-identical row).
# =========================================================================================================
library(readr); library(dplyr)

d <- read_csv(here::here("data/raw/ICIS-AIR_downloads/ICIS-AIR_PROGRAMS.csv"),
              col_types = cols(.default = col_character()), show_col_types = FALSE)
d$dup_exact <- as.integer(duplicated(d))

dir.create(here::here("data/clean"), showWarnings = FALSE, recursive = TRUE)
write_csv(d, here::here("data/clean/programs.csv.gz"))
cat(sprintf("programs: %d rows | %d columns\n", nrow(d), ncol(d)))
