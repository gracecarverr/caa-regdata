# =========================================================================================================
# scripts/03_document.R -- generate documentation inputs from the clean assets.
#   Writes the dictionary + per-variable distribution artifacts that the Quarto site (docs/) reads,
#   so documentation is always regenerated from the current data. Thin: calls R/document.R.
# =========================================================================================================
source(here::here("R/document.R"))

# TODO (document phase):
#   dict <- collect_dictionary(); saveRDS(dict, here::here("docs/_generated/dictionary.rds"))
#   for (a in list_assets()) variable_distributions(a)
cat("03_document.R -- stub. See README > Roadmap.\n")
