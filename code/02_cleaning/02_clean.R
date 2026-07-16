# =========================================================================================================
# 02_clean.R -- driver for the cleaning stage. Turns every raw source table into a bare-bones "clean" asset
#   in data/processed/ (keep all columns, keep all rows; add only date/year/dup/dup_exact where relevant).
#
#   Run order:
#     1. the 16 regular sources, described as data in 02_cleaning_parameters.R (executed via clean_one())
#     2. the 3 bespoke Wayback operating-status cleaners in wayback/ (17 -> 18 -> 18 depends on 17's output)
#
#   Standalone:  Rscript code/02_cleaning/02_clean.R      (assumes data/raw/ is already populated)
#   Or sourced by code/RUN_ALL.R.
# =========================================================================================================
source(here::here("code/02_cleaning/02_cleaning_functions.R"))
source(here::here("code/02_cleaning/02_cleaning_parameters.R"))

# 1. regular sources ------------------------------------------------------------------------------------
for (spec in CLEAN_SPECS) clean_one(spec)

# 2. Wayback operating-status history (order matters: 17 builds status, 18 collapses it into spells) ------
for (f in sort(list.files(here::here("code/02_cleaning/wayback"),
                          pattern = "^[0-9].*[.]R$", full.names = TRUE))) {
  cat(" -", basename(f), "\n"); source(f)
}
