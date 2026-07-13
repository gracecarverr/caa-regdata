# =========================================================================================================
# scripts/02_clean/04_informal_actions.R -- minimal panel-prep for ICIS-Air INFORMAL enforcement actions.
#   Every original column kept, every row kept. Adds: date (ACHIEVED_DATE parsed), year,
#   dup (occurrence within PGM_SYS_ID + ENF_IDENTIFIER), dup_exact (byte-identical row).
# =========================================================================================================
library(readr); library(dplyr); library(lubridate)

d <- read_csv(here::here("data/raw/ICIS-AIR_downloads/ICIS-AIR_INFORMAL_ACTIONS.csv"),
              col_types = cols(.default = col_character()), show_col_types = FALSE)

d$date <- mdy(d$ACHIEVED_DATE, quiet = TRUE)
d$year <- year(d$date)

d$dup_exact <- as.integer(duplicated(d))
d$dup <- as.integer(ave(seq_len(nrow(d)), paste(d$PGM_SYS_ID, d$ENF_IDENTIFIER, sep = "\r"),
                        FUN = seq_along) - 1L)

dir.create(here::here("data/clean"), showWarnings = FALSE, recursive = TRUE)
write_csv(d, here::here("data/clean/informal_actions.csv.gz"))
cat(sprintf("informal_actions: %d rows | %d columns\n", nrow(d), ncol(d)))
