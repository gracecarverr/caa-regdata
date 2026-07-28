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
library(readr); library(dplyr); library(lubridate)   # read/write_csv; coalesce(); mdy()/year() date helpers

# ---- read_raw ------------------------------------------------------------------------------------------
# Read a raw source table as ALL-CHARACTER (no type guessing) so nothing is silently coerced/lost.
#   relpath : path relative to data/raw/ (e.g. "ICIS-AIR_downloads/ICIS-AIR_FCES_PCES.csv")
read_raw <- function(relpath) {
  read_csv(here::here("data/raw", relpath),           # project-root-relative path into the immutable raw dir
           col_types = cols(.default = col_character()), show_col_types = FALSE)
           # every column forced to character regardless of readr's type guess -- e.g. a numeric-looking ID
           # column that has a leading zero somewhere is preserved instead of silently becoming numeric and
           # losing the zero
}

# ---- dup_index -----------------------------------------------------------------------------------------
# 0-based occurrence index of each row within the group defined by `key` columns (first row in a group = 0).
# Columns are joined with "\r" (a separator that cannot appear inside a CSV field) to form the group key,
# matching the original per-script logic exactly.
dup_index <- function(d, key) {
  g <- do.call(paste, c(unname(as.list(d[key])), list(sep = "\r")))
    # d[key]: subset to just the key columns (as a data.frame); as.list() -> one element per column;
    # unname() drops the list names so paste()'s own argument-name matching doesn't get confused by columns
    # literally named e.g. "sep"; do.call(paste, ...) pastes the key columns row-wise into one string per row,
    # using \r as separator since it cannot appear within a CSV field and so cannot cause an accidental
    # collision between different key-value combinations
  as.integer(ave(seq_len(nrow(d)), g, FUN = seq_along) - 1L)
    # ave() groups the row-index vector 1:n by g and applies seq_along to each group's subset (which, since
    # subsetting preserves original order, numbers each group's members 1,2,3,... in original row order) --
    # subtract 1 so the first occurrence of any key combination is 0, matching the "0-based" contract above.
    # NB: rows with NA in a key column paste to the literal string "NA" and are grouped together as if they
    # shared that key value -- a reasonable, if implicit, choice for treating missing keys as their own group.
}

# ---- write_clean ---------------------------------------------------------------------------------------
# Write a cleaned table to data/processed/<name>.csv.gz (creating the folder) and print a one-line summary.
write_clean <- function(d, name) {
  dir.create(here::here("data/processed"), showWarnings = FALSE, recursive = TRUE)  # ensure output dir exists
  write_csv(d, here::here("data/processed", paste0(name, ".csv.gz")))  # write_csv gzips automatically from
                                                                          # the .gz extension; overwrites any
                                                                          # existing file of the same name
  cat(sprintf("%s: %d rows | %d columns\n", name, nrow(d), ncol(d)))    # one-line console progress/sanity check
  invisible(d)                                        # return the cleaned frame invisibly (callers here ignore it)
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
  d <- read_raw(spec$raw)                             # step 1: raw, all-character read
  if (!is.null(spec$date)) {                           # step 2: only for "event" specs (those with a date fn)
    d$date <- spec$date(d)                             # apply this spec's date-parsing function to the frame
    d$year <- year(d$date)                             # calendar year of the parsed date (NA propagates if date is NA)
  }
  d$dup_exact <- as.integer(duplicated(d))
    # step 3: duplicated() flags the 2nd+ occurrence of a fully byte-identical row (including date/year, since
    # those columns already exist on `d` by this point) as TRUE/1; the first occurrence of any such row is 0
  if (!is.null(spec$key)) d$dup <- dup_index(d, spec$key)   # step 4: only for specs with a `key` -- see dup_index() above
  write_clean(d, spec$name)                            # step 5: write + print summary
}
