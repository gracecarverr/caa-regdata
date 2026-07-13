# =========================================================================================================
# scripts/03_document.R -- generate documentation inputs from the clean assets.
#   Writes the dictionary + per-variable distribution artifacts that the Quarto site (docs/) reads,
#   so documentation is always regenerated from the current data. Thin: calls R/document.R.
# =========================================================================================================
source(here::here("R/document.R"))

gen <- here::here("docs/_generated"); dir.create(gen, showWarnings = FALSE, recursive = TRUE)
saveRDS(collect_dictionary(), file.path(gen, "dictionary.rds"))    # combined data dictionary
for (a in list_assets()) { cat(" - distributions:", a, "\n"); variable_distributions(a) }
