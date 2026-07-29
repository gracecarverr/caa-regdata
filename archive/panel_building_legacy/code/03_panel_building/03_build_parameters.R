# =========================================================================================================
# 03_build_parameters.R -- window, geography, and per-panel filters for the sample panels.
#
#   PANEL_SPECS lists the sample panels to build. Each is the SAME recipe (03_build_functions.R::build_panel)
#   run over a different facility filter. The driver 03_build.R applies each spec's `filter` to the spine,
#   calls build_panel(), and writes data/panels/<name>.csv.gz.
#
#   Fields:
#     name   -- output stem -> data/panels/<name>.csv.gz
#     filter -- function(spine) -> filtered spine rows (the facilities in scope)
# =========================================================================================================

YEARS <- 2005:2025   # panel window (assets keep all dated events; the window is applied here) -- see CC2

# 48 contiguous states + DC (excludes AK, HI, and all territories)
CONUS <- c("AL","AZ","AR","CA","CO","CT","DE","DC","FL","GA","ID","IL","IN","IA","KS","KY","LA","ME","MD",
           "MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH","OK","OR","PA","RI",
           "SC","SD","TN","TX","UT","VT","VA","WA","WV","WI","WY")
           # deliberate 48+DC scope for the sample panels (AK/HI/territories still exist in the spine itself,
           # they're just excluded HERE from every PANEL_SPECS filter below) -- note this is a genuinely
           # accurate CONUS restriction, unlike the inaccurate "CONUS shapefile" comment in coord_county_flag.R

# Emissions classes admitted by the major/synthetic-minor filter (and inherited by electric).
MAJOR_SYNMIN_CLASSES <- c("Major Emissions", "Synthetic Minor Emissions")

# Electric utilities among the major/synmin sources: NAICS 2211 OR SIC 4911.
#   NAICS regex allows the 4-digit code anywhere not preceded by a digit; SIC regex anchors the 4-digit code.
electric_filter <- function(s) dplyr::filter(s, STATE %in% CONUS,
                                             AIR_POLLUTANT_CLASS_DESC %in% MAJOR_SYNMIN_CLASSES,
                                             grepl("(^|[^0-9])2211", NAICS_CODES) |
                                             # matches any 6-digit NAICS code in the 2211xx (electric power)
                                             # subsector, wherever it appears in a possibly multi-code field --
                                             # left-bounded only (not followed by a digit boundary check) is
                                             # intentional here since every real NAICS leaf code under 2211 IS
                                             # a 4+ digit extension of "2211" (e.g. 221112, 221122), so a
                                             # trailing-digit match is always a true positive
                                             grepl("(^|[^0-9])4911([^0-9]|$)", SIC_CODES))
                                             # SIC 4911 (Electric Services) is itself a complete leaf code, so
                                             # this regex is bounded on BOTH sides -- asymmetric with the NAICS
                                             # regex above by design, not an oversight

PANEL_SPECS <- list(

  # every ever-active facility in the contiguous US (+ DC)
  list(name = "universe",
       filter = function(s) dplyr::filter(s, STATE %in% CONUS)),

  # the larger regulated sources: Major + Synthetic Minor emissions class
  list(name = "major_synmin",
       filter = function(s) dplyr::filter(s, STATE %in% CONUS,
                                          AIR_POLLUTANT_CLASS_DESC %in% MAJOR_SYNMIN_CLASSES)),

  # electric utilities
  list(name = "electric",
       filter = electric_filter)
)
