# =========================================================================================================
# scripts/02_clean/10_program_subparts.R -- minimal: keep every column and every row of ICIS-Air program
#   subparts. Adds only dup_exact (byte-identical row).
# =========================================================================================================
library(readr); library(dplyr)

d <- read_csv(here::here("data/raw/ICIS-AIR_downloads/ICIS-AIR_PROGRAM_SUBPARTS.csv"),
              col_types = cols(.default = col_character()), show_col_types = FALSE)
d$dup_exact <- as.integer(duplicated(d))

dir.create(here::here("data/clean"), showWarnings = FALSE, recursive = TRUE)
write_csv(d, here::here("data/clean/program_subparts.csv.gz"))
cat(sprintf("program_subparts: %d rows | %d columns\n", nrow(d), ncol(d)))
