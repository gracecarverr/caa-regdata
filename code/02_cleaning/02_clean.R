# =========================================================================================================
# 02_clean.R -- driver for the cleaning stage. Turns every raw source table into a bare-bones "clean" asset
#   in data/processed/ (keep all columns, keep all rows; add only date/year/dup/dup_exact where relevant).
#
#   Run order:
#     1. the 17 regular sources, described as data in 02_cleaning_parameters.R (executed via clean_one())
#     2. the 3 bespoke Wayback operating-status cleaners in wayback/ (17 -> 18 -> 18 depends on 17's output)
#
#   Standalone:  Rscript code/02_cleaning/02_clean.R      (assumes data/raw/ is already populated)
#   Or sourced by code/RUN_ALL.R.
# =========================================================================================================
source(here::here("code/02_cleaning/02_cleaning_functions.R"))  # clean_one(), read_raw(), dup_index(), write_clean()
source(here::here("code/02_cleaning/02_cleaning_parameters.R")) # CLEAN_SPECS list (also relies on library()
                                                                  # calls already made by 02_cleaning_functions.R,
                                                                  # e.g. mdy()/coalesce() used inside its date fns)

# 1. regular sources ------------------------------------------------------------------------------------
for (spec in CLEAN_SPECS) clean_one(spec)              # one clean_one() call per spec; failures here (e.g. a
                                                          # raw file missing because 01_download.R wasn't run)
                                                          # will stop the whole loop with an uncaught error --
                                                          # no per-spec try/catch, so a bad source halts everything
                                                          # rather than silently skipping and finishing the rest

# 2. Wayback operating-status history (order matters: 17 builds status, 18 collapses it into spells) ------
for (f in sort(list.files(here::here("code/02_cleaning/wayback"),
                          pattern = "^[0-9].*[.]R$", full.names = TRUE))) {
  # lists only files in wayback/ that start with a digit and end in .R (i.e. 17_*.R, 18_*.R, 19_*.R -- skips
  # that folder's README.md); sort() relies on the two-digit numeric prefixes sorting correctly as plain
  # strings (17 < 18 < 19), which holds here but would break silently if a script numbered >=100 were ever
  # added (lexicographic "100" sorts before "17")
  cat(" -", basename(f), "\n"); source(f)               # progress line, then execute the script in this same
                                                          # environment (source(), not a subprocess) -- so each
                                                          # wayback script can see functions/specs from step 1
                                                          # and objects left behind by the previous wayback script
}
