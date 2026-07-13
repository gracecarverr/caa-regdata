# =========================================================================================================
# R/clean.R -- reusable cleaning helpers + the asset "contract" (used by scripts/02_clean/*.R).
#   Cleaning scripts stay THIN: read one raw source, parse/type/flag, and write ONE documented asset.
#   No sample selection, no aggregation, no cross-dataset joins (those belong to the panel layer).
# =========================================================================================================
source(here::here("R/setup.R"))

# Write a clean asset to data/clean/ AND register its column dictionary, so documentation is generated
# from the same code that produces the data (never hand-maintained separately).
#   df    : the clean tibble
#   name  : asset name (file becomes data/clean/<name>.csv.gz)
#   dict  : named character vector  c(column = "one-line definition", ...)  covering EVERY column
write_asset <- function(df, name, dict) {
  missing <- setdiff(names(df), names(dict))
  if (length(missing)) stop("dictionary is missing columns: ", paste(missing, collapse = ", "))
  readr::write_csv(df, file.path(CLEAN, paste0(name, ".csv.gz")))
  saveRDS(tibble::tibble(asset = name, column = names(dict), definition = unname(dict)),
          file.path(CLEAN, paste0(name, ".dict.rds")))     # 03_document reads these
  cat(sprintf("asset %-14s %d rows | %d cols | %d events (dup==0)\n",
              name, nrow(df), ncol(df), if ("dup" %in% names(df)) sum(df$dup == 0) else nrow(df)))
  invisible(df)
}

# TODO (vertical slice): any shared parsing helpers that more than one cleaner needs live here.
