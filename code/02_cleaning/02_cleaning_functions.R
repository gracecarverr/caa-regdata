# =========================================================================================================
# 02_cleaning_functions.R -- shared mechanics for the "minimal panel-prep" cleaners.
#
#   The cleaning layer is deliberately BARE BONES: every original column is kept and every row is kept
#   (nothing is dropped, deduplicated, or recoded). The only things added are the handful of columns a
#   facility x year panel needs downstream:
#     date       -- a source date column parsed to a real Date (only for "event" tables)
#     year       -- calendar year of that date
#     dup        -- 0-based occurrence index within a within-facility event key (0 = first row); NOT a
#                   deduplication -- it just labels repeats so the panel layer can choose how to collapse
#     dup_exact  -- 1 if the row is byte-identical to an EARLIER row (a true duplicate record)
#
#   Two regular shapes cover 16 of the 19 sources; they are described as data in 02_cleaning_parameters.R
#   and executed by clean_one() below. The 3 bespoke Wayback cleaners (operating-status history) live in
#   wayback/ and keep their own scripts. See 02_cleaning_functions_README.md for details.
# =========================================================================================================
library(readr); library(dplyr); library(lubridate)

# ---- read_raw ------------------------------------------------------------------------------------------
# Read a raw source table as ALL-CHARACTER (no type guessing) so nothing is silently coerced/lost.
#   relpath : path relative to data/raw/ (e.g. "ICIS-AIR_downloads/ICIS-AIR_FCES_PCES.csv")
read_raw <- function(relpath) {
  read_csv(here::here("data/raw", relpath),
           col_types = cols(.default = col_character()), show_col_types = FALSE)
}

# ---- dup_index -----------------------------------------------------------------------------------------
# 0-based occurrence index of each row within the group defined by `key` columns (first row in a group = 0).
# Columns are joined with "\r" (a separator that cannot appear inside a CSV field) to form the group key,
# matching the original per-script logic exactly.
dup_index <- function(d, key) {
  g <- do.call(paste, c(unname(as.list(d[key])), list(sep = "\r")))
  as.integer(ave(seq_len(nrow(d)), g, FUN = seq_along) - 1L)
}

# ---- write_clean ---------------------------------------------------------------------------------------
# Write a cleaned table to data/processed/<name>.csv.gz (creating the folder) and print a one-line summary.
write_clean <- function(d, name) {
  dir.create(here::here("data/processed"), showWarnings = FALSE, recursive = TRUE)
  write_csv(d, here::here("data/processed", paste0(name, ".csv.gz")))
  cat(sprintf("%s: %d rows | %d columns\n", name, nrow(d), ncol(d)))
  invisible(d)
}

# ---- clean_one -----------------------------------------------------------------------------------------
# Run one cleaning spec (see 02_cleaning_parameters.R). Order of operations is load-bearing and matches the
# original per-source scripts exactly:
#   1. read raw as character
#   2. if spec$date is a function: add `date` (its result) and `year` (calendar year of date)
#   3. add `dup_exact` = duplicated() over the frame AS IT STANDS (so it includes date/year when present)
#   4. if spec$key is given: add `dup` = within-key occurrence index
#   5. write to data/processed/<name>.csv.gz
clean_one <- function(spec) {
  d <- read_raw(spec$raw)
  if (!is.null(spec$date)) {
    d$date <- spec$date(d)
    d$year <- year(d$date)
  }
  d$dup_exact <- as.integer(duplicated(d))
  if (!is.null(spec$key)) d$dup <- dup_index(d, spec$key)
  write_clean(d, spec$name)
}
