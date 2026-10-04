# =========================================================================================================
# code/diagnostics/build_home.R \u2014 assembles docs/index.html, the site's Home page: a hero, and cards
#   linking to the other 4 pages (Briefs, Raw Data, Datasets, Panels). The institutional-overview brief
#   used to be embedded here as a docs-site-style sidebar + content pane; it's now split into its own
#   topic briefs and rendered on the Briefs page instead (code/diagnostics/build_briefs_page.R), alongside
#   the new facility-identifiers / data-systems / pollutant-classification briefs \u2014 Home just links there
#   now, rather than duplicating the same content on two pages.
# =========================================================================================================
library(here)
source(here("code", "diagnostics", "tables", "_html.R"))
source(here("code", "diagnostics", "site_shell.R"))

body <- paste0(
  hero(
    title        = "Stationary-source pollution, turned into research infrastructure.",
    desc         = paste(
      "A reproducible pipeline of U.S. Environmental Protection Agency (EPA) enforcement, compliance, and",
      "permitting data on stationary sources of air pollution under the Clean Air Act \u2014 built for",
      "empirical research on regulation and compliance."),
    bg_image     = "images/hero-smokestack.jpg",
    photo_credit = paste(
      "Photo: John Messina, March 1973 \u2014 EPA Documerica Project / U.S. National Archives.",
      "Public domain."),
    cta_buttons  = list(list(label = "View the code \u2197", href = "https://github.com/gracecarverr/caa-regdata"))
  ),
  page_main(
    cards(
      card("Institutional Briefs", paste(
        "Twelve briefs on the Clean Air Act's regulatory structure and the EPA data systems this",
        "pipeline draws on \u2014 each ending in what it implies for the data."),
        "briefs.html"),
      card("Raw Data", paste(
        "Per-source summary tables for all 16 raw ICIS-Air, AFS, and emissions files \u2014 variable",
        "coverage, frequent values, and missingness, computed directly from the raw downloads."),
        "raw_data.html"),
      card("Datasets", paste(
        "The eight datasets this pipeline builds from raw EPA data \u2014 construction decisions,",
        "headline findings, and the caveat that matters most for each one."),
        "databases.html"),
      card("Panels", paste(
        "Two continuous facility \u00d7 year panels built for empirical work on enforcement and",
        "compliance, 2015\u20132025: construction decisions, coverage, and summary statistics."),
        "panels.html")
    ),
    "<h2 class='sec-h2'>How the pipeline works</h2>",
    "<p class='sec-lede'>Four stages, run in order by <code>code/RUN_ALL.R</code>, each reading only the ",
    "previous stage's output.</p>",
    # descriptions transcribed from each stage's own README (code/0N_*/README.md) "Stage input/output" line
    # -- not re-derived here, so if a stage's inputs/outputs change, update this alongside that README.
    stage_grid(list(
      list(step = "01", title = "Download",
           desc = "Pull raw sources from EPA ECHO into data/raw/*."),
      list(step = "02", title = "Clean",
           desc = "Raw sources \u2192 bare-bones clean assets in data/processed/*.csv.gz."),
      list(step = "03", title = "Datasets",
           desc = "Build the eight deliverable datasets in data/datasets/*.csv.gz."),
      list(step = "04", title = "Panels",
           desc = "Build two facility \u00d7 year panels in data/panels/*.csv.gz.")
    )),
    "<h2 class='sec-h2'>Public EPA sources</h2>",
    "<p class='sec-lede'>Downloaded at run time by <code>code/01_data_download/01_download.R</code>. None ",
    "are redistributed here.</p>",
    # every URL below is copied verbatim from an existing verified reference elsewhere in this repo --
    # docs/data_dictionary.md's own "Sources" list (ICIS-Air/Air Emissions/CAA Pipeline/AFS), briefs/
    # database_overviews.md (FRS), and 01_download.R's own COUNTIES_URL constant (Census) -- not re-typed
    # from memory, and none is a landing page this script has independently verified live.
    cards(
      source_card("Core CAA Sources", list(
        list(name = "ICIS-Air", href = "https://echo.epa.gov/tools/data-downloads/icis-air-download-summary",
             desc = "Facility identification, compliance monitoring, and enforcement data for stationary air sources \u2014 the pipeline's primary source."),
        list(name = "Air Emissions", href = "https://echo.epa.gov/tools/data-downloads/air-emissions-download-summary",
             desc = "Facility-level pollutant emissions, combining NEI, GHGRP, TRI, and CAMD."),
        list(name = "CAA Compliance Pipeline", href = "https://echo.epa.gov/tools/data-downloads/caa-pipeline-download-summary",
             desc = "Violations pre-joined to their triggering evaluation and resulting enforcement action."),
        list(name = "AFS (Air Facility System, pre-2014)", href = "https://echo.epa.gov/system/files/AFS_Data_Download.pdf",
             desc = "Legacy facility, program, action, and HPV-history tables, frozen as of 2014 \u2014 ICIS-Air's predecessor.")
      )),
      source_card("Crosswalk", list(
        list(name = "FRS (Facility Registry Service)", href = "https://echo.epa.gov/tools/data-downloads/frs-download-summary",
             desc = "Cross-program facility registry \u2014 the source of this pipeline's facility coordinates."),
        list(name = "US Counties (Census TIGER)", href = "https://www2.census.gov/geo/tiger/GENZ2022/shp/cb_2022_us_county_500k.zip",
             desc = "County boundaries, used for the point-in-polygon coordinate-to-county match.")
      ))
    )
  )
)

html <- site_shell(
  title       = "Home",
  description = "A reproducible EPA Clean Air Act stationary-source regulatory data pipeline: raw data, database overviews, facility-year panels, and six deliverable datasets.",
  active      = "home",
  body_html   = body
)

OUT <- here("docs", "index.html")
writeLines(html, OUT, useBytes = TRUE)
cat("wrote", OUT, "\n")
