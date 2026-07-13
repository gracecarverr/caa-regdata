# =========================================================================================================
# scripts/02_clean/14_afs_hist_compliance.R -- minimal: keep every column and every row of the AFS
#   historical-compliance table. Adds only dup_exact (byte-identical row).
# =========================================================================================================
library(readr); library(dplyr)

d <- read_csv(here::here("data/raw/afs_downloads/AFS_AIR_PRG_HIST_COMPLIANCE.csv"),
              col_types = cols(.default = col_character()), show_col_types = FALSE)
d$dup_exact <- as.integer(duplicated(d))

dir.create(here::here("data/clean"), showWarnings = FALSE, recursive = TRUE)
write_csv(d, here::here("data/clean/afs_hist_compliance.csv.gz"))
cat(sprintf("afs_hist_compliance: %d rows | %d columns\n", nrow(d), ncol(d)))
