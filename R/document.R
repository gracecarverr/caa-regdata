# =========================================================================================================
# R/document.R -- helpers that turn clean assets into documentation inputs (used by scripts/03_document.R).
#   Everything the docs site shows is GENERATED from data/clean/, so it can never drift from the data.
# =========================================================================================================

# Names of all built assets (from the clean/ directory).
list_assets <- function() sub("[.]csv[.]gz$", "", list.files(CLEAN, pattern = "[.]csv[.]gz$"))

# Collect every asset's registered dictionary (written by write_asset) into one table for docs/dictionary.qmd.
collect_dictionary <- function() {
  files <- list.files(CLEAN, pattern = "[.]dict[.]rds$", full.names = TRUE)
  if (!length(files)) return(tibble::tibble(asset = character(), column = character(), definition = character()))
  dplyr::bind_rows(lapply(files, readRDS))
}

# One-line, type-aware summary of a column (for the distributions table).
col_summary <- function(x) {
  nona <- x[!is.na(x)]
  if (!length(nona)) return("(all missing)")
  if (inherits(x, "Date"))
    return(sprintf("%s to %s", min(nona), max(nona)))
  if (is.numeric(x))
    return(sprintf("min %s / median %s / max %s",
                   format(min(nona)), format(stats::median(nona)), format(max(nona))))
  tt <- sort(table(nona), decreasing = TRUE)                       # character: top few values
  paste(sprintf("%s (%d)", names(tt)[seq_len(min(3, length(tt)))],
                as.integer(tt)[seq_len(min(3, length(tt)))]), collapse = "; ")
}

# Per-column distribution table for one asset, saved under docs/_generated/ for the Quarto site to read.
variable_distributions <- function(asset) {
  df  <- readr::read_csv(file.path(CLEAN, paste0(asset, ".csv.gz")), show_col_types = FALSE)
  out <- dplyr::bind_rows(lapply(names(df), function(col) {
    x <- df[[col]]
    tibble::tibble(column = col, type = class(x)[1], n = length(x),
                   missing = sum(is.na(x)), pct_missing = round(100 * mean(is.na(x)), 1),
                   distinct = dplyr::n_distinct(x), summary = col_summary(x))
  }))
  gen <- here::here("docs/_generated"); dir.create(gen, showWarnings = FALSE, recursive = TRUE)
  saveRDS(out, file.path(gen, sprintf("dist_%s.rds", asset)))
  invisible(out)
}
