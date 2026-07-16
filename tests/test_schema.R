# =========================================================================================================
# tests/test_schema.R -- invariant checks that run against the clean assets.
#   Kept dependency-light (base stopifnot); run after a build, or wire into CI later.
#   Standalone: no shared helpers, no config.
# =========================================================================================================
library(readr); library(dplyr)
CLEAN <- here::here("data/processed")

# TODO (validate phase), per asset:
#   - required columns present; keys non-missing
#   - dup==0 row count matches the distinct-event count (dedup reconstruction)
#   - expected row-count ranges (guard against silent source changes)
#   - dup_exact implies dup > 0
cat("test_schema.R -- stub. See README > Roadmap.\n")
