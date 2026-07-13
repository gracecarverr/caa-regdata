# =========================================================================================================
# scripts/02_clean/15_afs_hpv.R -- minimal: keep every column and every row of AFS HPV history.
#   Adds only dup_exact (byte-identical row).
# =========================================================================================================
library(readr); library(dplyr)

d <- read_csv(here::here("data/raw/afs_downloads/AFS_HPV_HISTORY.csv"),
              col_types = cols(.default = col_character()), show_col_types = FALSE)
d$dup_exact <- as.integer(duplicated(d))

dir.create(here::here("data/clean"), showWarnings = FALSE, recursive = TRUE)
write_csv(d, here::here("data/clean/afs_hpv.csv.gz"))
cat(sprintf("afs_hpv: %d rows | %d columns\n", nrow(d), ncol(d)))
