# =========================================================================================================
# scripts/02_clean/02_violations.R -- minimal panel-prep for ICIS-Air violation history.
#   BARE BONES: every original column kept, every row kept. Adds: date (first non-blank of the two
#   determination dates, parsed), year, dup (occurrence within PGM_SYS_ID + COMP_DETERMINATION_UID),
#   dup_exact (byte-identical row).
# =========================================================================================================
library(readr); library(dplyr); library(lubridate)

d <- read_csv(here::here("data/raw/ICIS-AIR_downloads/ICIS-AIR_VIOLATION_HISTORY.csv"),
              col_types = cols(.default = col_character()), show_col_types = FALSE)

d$date <- coalesce(mdy(d$EARLIEST_FRV_DETERM_DATE, quiet = TRUE), mdy(d$HPV_DAYZERO_DATE, quiet = TRUE))
d$year <- year(d$date)

d$dup_exact <- as.integer(duplicated(d))
d$dup <- as.integer(ave(seq_len(nrow(d)), paste(d$PGM_SYS_ID, d$COMP_DETERMINATION_UID, sep = "\r"),
                        FUN = seq_along) - 1L)

dir.create(here::here("data/clean"), showWarnings = FALSE, recursive = TRUE)
write_csv(d, here::here("data/clean/violations.csv.gz"))
cat(sprintf("violations: %d rows | %d columns\n", nrow(d), ncol(d)))
