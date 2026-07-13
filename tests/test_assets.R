# =========================================================================================================
# tests/test_assets.R -- light invariants for the clean assets. Run after a build:  Rscript tests/test_assets.R
#   Cleaners keep every column and every row, so we only assert the flags behave.
# =========================================================================================================
library(readr); library(dplyr)
CLEAN <- here::here("data/clean")

# event sources carry dup / dup_exact
events <- c("inspections","violations","formal_actions","informal_actions","certs","stacktests")
for (a in events) {
  d <- read_csv(file.path(CLEAN, paste0(a, ".csv.gz")),
                col_types = cols(dup = col_integer(), dup_exact = col_integer(), .default = col_character()),
                show_col_types = FALSE)
  stopifnot("has dup flags"           = all(c("dup","dup_exact") %in% names(d)))
  stopifnot("dup_exact implies dup>0"  = all(d$dup[d$dup_exact == 1L] > 0))
  cat(sprintf("  %-18s PASS | %d rows | %d cols | %d distinct events (dup==0)\n",
              a, nrow(d), ncol(d), sum(d$dup == 0)))
}
cat("all asset invariants passed\n")
