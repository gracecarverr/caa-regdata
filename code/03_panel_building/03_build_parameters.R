# =========================================================================================================
# 03_build_parameters.R -- window, geography, and per-panel filters for the sample panels.
#
#   PANEL_SPECS lists the sample panels to build. Each is the SAME recipe (03_build_functions.R::build_panel)
#   run over a different facility filter, with an optional attainment-treatment attach. The driver 03_build.R
#   applies each spec's `filter` to the spine, calls build_panel(), and writes data/panels/<name>.csv.gz.
#
#   Fields:
#     name      -- output stem -> data/panels/<name>.csv.gz
#     filter    -- function(spine) -> filtered spine rows (the facilities in scope)
#     treatment -- TRUE to attach the PM2.5 (2012) attainment treatment block (electric only)
# =========================================================================================================

YEARS <- 2005:2025   # panel window (assets keep all dated events; the window is applied here) -- see CC2

# 48 contiguous states + DC (excludes AK, HI, and all territories)
CONUS <- c("AL","AZ","AR","CA","CO","CT","DE","DC","FL","GA","ID","IL","IN","IA","KS","KY","LA","ME","MD",
           "MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH","OK","OR","PA","RI",
           "SC","SD","TN","TX","UT","VT","VA","WA","WV","WI","WY")

# Emissions classes admitted by the major/synthetic-minor filter (and inherited by electric).
MAJOR_SYNMIN_CLASSES <- c("Major Emissions", "Synthetic Minor Emissions")

PANEL_SPECS <- list(

  # every ever-active facility in the contiguous US (+ DC)
  list(name = "universe", treatment = FALSE,
       filter = function(s) dplyr::filter(s, STATE %in% CONUS)),

  # the larger regulated sources: Major + Synthetic Minor emissions class
  list(name = "major_synmin", treatment = FALSE,
       filter = function(s) dplyr::filter(s, STATE %in% CONUS,
                                          AIR_POLLUTANT_CLASS_DESC %in% MAJOR_SYNMIN_CLASSES)),

  # electric utilities among the major/synmin sources: NAICS 2211 OR SIC 4911. Gets PM2.5 treatment.
  #   NAICS regex allows the 4-digit code anywhere not preceded by a digit; SIC regex anchors the 4-digit code.
  list(name = "electric", treatment = TRUE,
       filter = function(s) dplyr::filter(s, STATE %in% CONUS,
                                          AIR_POLLUTANT_CLASS_DESC %in% MAJOR_SYNMIN_CLASSES,
                                          grepl("(^|[^0-9])2211", NAICS_CODES) |
                                          grepl("(^|[^0-9])4911([^0-9]|$)", SIC_CODES)))
)
