# =========================================================================================================
# R/document.R -- helpers that turn clean assets into documentation inputs (used by scripts/03_document.R).
#   Everything the docs site shows is GENERATED from data/clean/, so it can never drift from the data.
# =========================================================================================================

# Collect every asset's registered dictionary (written by write_asset) into one table for docs/dictionary.qmd.
collect_dictionary <- function() {
  files <- list.files(CLEAN, pattern = "[.]dict[.]rds$", full.names = TRUE)
  if (!length(files)) return(tibble::tibble(asset = character(), column = character(), definition = character()))
  dplyr::bind_rows(lapply(files, readRDS))
}

# TODO (document phase):
#   variable_distributions(asset)  -> per-column summary stats + a small histogram/bar, for docs/distributions.qmd
#   (write outputs under docs/ so the .qmd files just read them)
