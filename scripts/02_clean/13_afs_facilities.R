# =========================================================================================================
# scripts/02_clean/13_afs_facilities.R -- minimal: keep every column and every row of AFS facilities.
#   Adds only dup_exact (byte-identical row).
# =========================================================================================================
library(readr); library(dplyr)

d <- read_csv(here::here("data/raw/afs_downloads/AFS_FACILITIES.csv"),
              col_types = cols(.default = col_character()), show_col_types = FALSE)
d$dup_exact <- as.integer(duplicated(d))

dir.create(here::here("data/clean"), showWarnings = FALSE, recursive = TRUE)
write_csv(d, here::here("data/clean/afs_facilities.csv.gz"))
cat(sprintf("afs_facilities: %d rows | %d columns\n", nrow(d), ncol(d)))
