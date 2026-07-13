# =========================================================================================================
# R/setup.R -- shared configuration, paths, constants, and generic helpers.
#   Sourced by run_all.R and by every pipeline script. Reads config.yml. Loads no data.
# =========================================================================================================
suppressPackageStartupMessages({
  library(here)      # project-root-relative paths (anchored on the repo root)
  library(yaml)      # read config.yml
  library(readr); library(dplyr); library(tidyr); library(lubridate)
})

# ---- config -------------------------------------------------------------------------------------------
CONFIG <- yaml::read_yaml(here::here("config.yml"))
YEARS  <- CONFIG$window$start:CONFIG$window$end

RAW    <- here::here(CONFIG$paths$raw)
CLEAN  <- here::here(CONFIG$paths$clean)
PANELS <- here::here(CONFIG$paths$panels)
for (d in c(RAW, CLEAN, PANELS)) dir.create(d, showWarnings = FALSE, recursive = TRUE)

# 48 contiguous states + DC (excludes AK, HI, and all territories).
CONUS <- c("AL","AZ","AR","CA","CO","CT","DE","DC","FL","GA","ID","IL","IN","IA","KS","KY","LA","ME","MD",
           "MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH","OK","OR","PA","RI",
           "SC","SD","TN","TX","UT","VT","VA","WA","WV","WI","WY")

# ---- generic helpers (dataset-agnostic infrastructure) ------------------------------------------------
# Row-wise first non-blank value across candidate columns (NA if all blank).
first_nonblank <- function(df, cols) {
  out <- rep(NA_character_, nrow(df))
  for (col in cols) { take <- is.na(out) & !is.na(df[[col]]) & df[[col]] != ""; out[take] <- df[[col]][take] }
  out
}

# Duplicate flags (NO deduplication -- every row kept; duplicates are labelled).
#   dup       = occurrence index within the event-id group `id_cols`, in file order
#               (0 = first row of that id; 1,2,... = repeats). filter(dup == 0) = one row per event.
#   dup_exact = 1 if the row is byte-identical (on all kept columns) to an earlier row.
add_dup_flags <- function(df, id_cols) {
  key <- do.call(paste, c(as.list(df[id_cols]), sep = "\r"))
  df$dup       <- as.integer(stats::ave(seq_len(nrow(df)), key, FUN = seq_along) - 1L)
  df$dup_exact <- as.integer(duplicated(df[setdiff(names(df), "dup")]))
  df
}
