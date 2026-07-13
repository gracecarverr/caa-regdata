# =========================================================================================================
# scripts/02_clean/01_inspections.R -- minimal panel-prep for ICIS-Air compliance evaluations (FCE/PCE).
#   in : data/raw/ICIS-AIR_downloads/ICIS-AIR_FCES_PCES.csv
#   out: data/clean/inspections.csv.gz
#
#   BARE BONES: every original column is kept and every row is kept (nothing dropped, including rows with
#   no PGM_SYS_ID). The only additions are what a facility x year panel needs:
#     date       -- ACTUAL_END_DATE parsed to a real Date
#     year       -- calendar year of that date
#     dup        -- occurrence index within (PGM_SYS_ID, ACTIVITY_ID); 0 = first row (no deduplication)
#     dup_exact  -- 1 if the row is byte-identical to an earlier row
# =========================================================================================================
library(readr); library(dplyr); library(lubridate)

d <- read_csv(here::here("data/raw/ICIS-AIR_downloads/ICIS-AIR_FCES_PCES.csv"),
              col_types = cols(.default = col_character()), show_col_types = FALSE)

d$date <- mdy(d$ACTUAL_END_DATE, quiet = TRUE)          # evaluation completion date, parsed
d$year <- year(d$date)

d$dup_exact <- as.integer(duplicated(d))               # byte-identical row (before the dup index is added)
key    <- paste(d$PGM_SYS_ID, d$ACTIVITY_ID, sep = "\r")
d$dup  <- as.integer(ave(seq_len(nrow(d)), key, FUN = seq_along) - 1L)

dir.create(here::here("data/clean"), showWarnings = FALSE, recursive = TRUE)
write_csv(d, here::here("data/clean/inspections.csv.gz"))
cat(sprintf("inspections: %d rows | %d columns (all original + date/year/dup/dup_exact)\n", nrow(d), ncol(d)))
