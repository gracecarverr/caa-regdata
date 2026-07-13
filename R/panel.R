# =========================================================================================================
# R/panel.R -- the configurable facility x year panel builder (used by scripts/04_build_panels.R).
#   Reads clean assets from data/clean/, applies sample filters, attaches outcome measures, and returns
#   a facility x year panel. Canonical counts are event-level (dup == 0); no deduplication upstream.
# =========================================================================================================

# TODO (panels phase): port build_panel() into this clean structure.
#   build_panel(years = YEARS, sample = list(), outcomes = ..., treatment = NULL,
#               balance = FALSE, detail = FALSE, write_as = NULL)
build_panel <- function(...) {
  stop("build_panel() not implemented yet -- see Roadmap in README.md")
}
