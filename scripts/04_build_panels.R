# =========================================================================================================
# scripts/04_build_panels.R -- build the shipped sample panels from the clean assets.
#   Thin: calls build_panel() (R/panel.R) with a few documented sample definitions and writes them to
#   data/panels/. Each shipped panel gets a codebook the docs site can display.
# =========================================================================================================
source(here::here("R/panel.R"))

# TODO (panels phase), e.g.:
#   build_panel(sample = list(state = CONUS), balance = TRUE, detail = TRUE, write_as = "universe")
#   build_panel(sample = list(class = c("Major Emissions","Synthetic Minor Emissions"), state = CONUS),
#               balance = TRUE, detail = TRUE, write_as = "major_synmin")
cat("04_build_panels.R -- stub. See README > Roadmap.\n")
