# =========================================================================================================
# scripts/02_clean/12_afs_air_program.R -- minimal: keep every column and every row of the AFS air-program
#   table. Adds only dup_exact (byte-identical row).
# =========================================================================================================
library(readr); library(dplyr)

d <- read_csv(here::here("data/raw/afs_downloads/AIR_PROGRAM.csv"),
              col_types = cols(.default = col_character()), show_col_types = FALSE)
d$dup_exact <- as.integer(duplicated(d))

dir.create(here::here("data/clean"), showWarnings = FALSE, recursive = TRUE)
write_csv(d, here::here("data/clean/afs_air_program.csv.gz"))
cat(sprintf("afs_air_program: %d rows | %d columns\n", nrow(d), ncol(d)))
