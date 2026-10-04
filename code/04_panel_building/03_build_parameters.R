# =========================================================================================================
# code/04_panel_building/03_build_parameters.R -- window + the two panel specs this pipeline ships.
#
#   PANEL_SPECS lists the two panels to build. Both start from 00_spine.R's `spine` (already CONUS +
#   Major/Synthetic-Minor class, with EVER_ACTIVE precomputed) -- electric adds the NAICS/SIC filter
#   on top. 03_build.R applies each spec's `filter`, calls build_panel(), and writes
#   data/panels/<name>.csv.gz.
#
#   This is a from-scratch rewrite, NOT the old code/03_panel_building/03_build_parameters.R renamed -- the
#   archived version (archive/panel_building_legacy/code/03_panel_building/03_build_parameters.R) shipped
#   THREE levels (universe/major_synmin/electric) with continuity as an optional add-on family; this
#   pipeline ships ONLY these two panels, per explicit project decision -- see
#   briefs/panel/panel_construction_decisions.md.
# =========================================================================================================

YEARS <- 2015:2025   # this pipeline's window -- NOT the repo-wide 2005:2025 (00_setup.R). Both panels are
                      # eligibility-screened over exactly this span (00_spine.R's SCREEN_YEARS), so
                      # there's no reason to carry a wider, mostly-irrelevant pre-2015 window here.

# Electric utilities among the major/synthetic-minor sources: NAICS 2211 OR SIC 4911. Identical regex logic
# to the archived pipeline's electric_filter (same underlying facts about the code formats haven't changed).
electric_filter <- function(s) dplyr::filter(s,
  grepl("(^|[^0-9])2211", NAICS_CODES) |
  # matches any 6-digit NAICS code in the 2211xx (electric power) subsector, wherever it appears in a
  # possibly multi-code field -- left-bounded only, since every real NAICS leaf code under 2211 is a 4+
  # digit extension of "2211" (e.g. 221112, 221122), so a trailing-digit match is always a true positive
  grepl("(^|[^0-9])4911([^0-9]|$)", SIC_CODES))
  # SIC 4911 (Electric Services) is itself a complete leaf code, so this regex is bounded on BOTH sides --
  # asymmetric with the NAICS regex above by design, not an oversight (same as the archived pipeline)

PANEL_SPECS <- list(

  # Major/Synthetic-Minor sources, active in at least one year 2015-2025 (ACTIVE_BROAD == 1 in >=1 of 11
  # years). `spine` is already CONUS + major/synmin-class filtered (00_spine.R) -- just apply the eligibility
  # screen.
  list(name = "major_synmin_2015_2025",
       filter = function(s) dplyr::filter(s, EVER_ACTIVE)),

  # Electric utilities within that same eligible major/synmin population.
  list(name = "electric_2015_2025",
       filter = function(s) electric_filter(dplyr::filter(s, EVER_ACTIVE)))
)

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# (none currently)
# =========================================================================================================
