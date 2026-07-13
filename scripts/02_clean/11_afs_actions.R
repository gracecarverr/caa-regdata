# =========================================================================================================
# scripts/02_clean/11_afs_actions.R -- minimal: keep every column and every row of AFS actions (legacy AFS
#   system). Adds only dup_exact (byte-identical row).
# =========================================================================================================
library(readr); library(dplyr)

d <- read_csv(here::here("data/raw/afs_downloads/AFS_ACTIONS.csv"),
              col_types = cols(.default = col_character()), show_col_types = FALSE)
d$dup_exact <- as.integer(duplicated(d))

dir.create(here::here("data/clean"), showWarnings = FALSE, recursive = TRUE)
write_csv(d, here::here("data/clean/afs_actions.csv.gz"))
cat(sprintf("afs_actions: %d rows | %d columns\n", nrow(d), ncol(d)))
