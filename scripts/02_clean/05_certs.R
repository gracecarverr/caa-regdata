# =========================================================================================================
# scripts/02_clean/05_certs.R -- minimal panel-prep for ICIS-Air Title V certifications.
#   Every original column kept, every row kept. Adds: date (ACTUAL_END_DATE parsed), year,
#   dup (occurrence within PGM_SYS_ID + ACTIVITY_ID), dup_exact (byte-identical row).
# =========================================================================================================
library(readr); library(dplyr); library(lubridate)

d <- read_csv(here::here("data/raw/ICIS-AIR_downloads/ICIS-AIR_TITLEV_CERTS.csv"),
              col_types = cols(.default = col_character()), show_col_types = FALSE)

d$date <- mdy(d$ACTUAL_END_DATE, quiet = TRUE)
d$year <- year(d$date)

d$dup_exact <- as.integer(duplicated(d))
d$dup <- as.integer(ave(seq_len(nrow(d)), paste(d$PGM_SYS_ID, d$ACTIVITY_ID, sep = "\r"),
                        FUN = seq_along) - 1L)

dir.create(here::here("data/clean"), showWarnings = FALSE, recursive = TRUE)
write_csv(d, here::here("data/clean/certs.csv.gz"))
cat(sprintf("certs: %d rows | %d columns\n", nrow(d), ncol(d)))
