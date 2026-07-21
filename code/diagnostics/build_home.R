# =========================================================================================================
# code/diagnostics/build_home.R \u2014 assembles docs/index.html, the site's Home page: a hero, cards linking to
#   the other 3 pages, and the institutional-overview brief rendered as prose. The brief's own H1, its
#   "Valuable Links" section, and every "Data implication" blockquote are dropped (internal-audience /
#   working-notes framing not meant for a public page) \u2014 everything else is passed through commonmark
#   unedited, so no institutional fact or number is retyped by hand.
#   briefs/00_institutional_overview.md -> docs/index.html
# =========================================================================================================
library(here)
library(commonmark)
source(here("code", "diagnostics", "tables", "_html.R"))
source(here("code", "diagnostics", "site_shell.R"))

md_path <- here("briefs", "00_institutional_overview.md")
lines   <- enc2utf8(readLines(md_path, warn = FALSE, encoding = "UTF-8"))

# drop the brief's own H1 (the hero supplies the page title)
if (length(lines) && grepl("^# ", lines[1])) lines <- lines[-1]

# drop the "## Valuable Links" section (working-notes scratchpad, not for a public page)
vl_start <- grep("^## Valuable Links$", lines)
if (length(vl_start) == 1) {
  h2s     <- grep("^## ", lines)
  after   <- h2s[h2s > vl_start]
  vl_end  <- if (length(after)) after[1] - 1L else length(lines)
  lines   <- lines[-(vl_start:vl_end)]
}

# drop every "> **Data implication.**" blockquote block (every blockquote in this brief is one of these \u2014
# verified: `grep -n "^>"` on the source file matches nothing but Data-implication callouts)
lines <- lines[!grepl("^>", lines)]

overview_html <- commonmark::markdown_html(paste(lines, collapse = "\n"), extensions = TRUE)

body <- paste0(
  hero(
    title   = "CAA Regulatory Data Infrastructure",
    desc    = paste(
      "A reproducible pipeline of EPA enforcement, compliance, and permitting data on stationary sources",
      "of air pollution under the Clean Air Act \u2014 built for empirical research on regulation and",
      "compliance."),
    eyebrow = "Clean Air Act \u00B7 Stationary Sources"
  ),
  page_main(
    cards(
      card("Raw Data", paste(
        "Per-source summary tables for all 15 raw ICIS-Air, AFS, and emissions files \u2014 variable",
        "coverage, frequent values, and missingness, computed directly from the raw downloads."),
        "raw_data.html"),
      card("Databases", paste(
        "What each database contains, what's missing, and how the files join \u2014 ICIS-Air, AFS, the",
        "combined emissions dataset, and the compliance-and-enforcement pipeline."),
        "databases.html"),
      card("Panels", paste(
        "Facility \u00D7 year panels built for empirical work: construction decisions, coverage, and",
        "summary statistics across the Universe, Major/Synthetic Minor, and Electric panels."),
        "panels.html")
    ),
    "<div class='prose'>", overview_html, "</div>"
  )
)

html <- site_shell(
  title       = "Home",
  description = "A reproducible EPA Clean Air Act stationary-source regulatory data pipeline: raw data, database overviews, and facility-year panels.",
  active      = "home",
  body_html   = body,
  script      = "code/diagnostics/build_home.R"
)

OUT <- here("docs", "index.html")
writeLines(html, OUT, useBytes = TRUE)
cat("wrote", OUT, "\n")
