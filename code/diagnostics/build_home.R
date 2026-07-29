# =========================================================================================================
# code/diagnostics/build_home.R \u2014 assembles docs/index.html, the site's Home page: a hero, cards linking to
#   the other 3 pages, and the institutional-overview brief rendered as a docs-site-style sidebar + content
#   pane (site_shell.R's doc_nav(), one pane per top-level "## " section of the brief) rather than one long
#   scroll of prose \u2014 a reader shouldn't have to read the whole Clean Air Act primer to find the one section
#   they want. The brief's own H1, its "Valuable Links" section, and every "Data implication" blockquote are
#   dropped (internal-audience/working-notes framing not meant for a public page) \u2014 everything else is
#   passed through commonmark unedited within its own section, so no institutional fact or number is retyped
#   by hand.
#   briefs/institutional_overview.md -> docs/index.html
# =========================================================================================================
library(here)
library(commonmark)
source(here("code", "diagnostics", "tables", "_html.R"))
source(here("code", "diagnostics", "site_shell.R"))

md_path <- here("briefs", "institutional_overview.md")
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

# split what's left into one chunk per top-level "## " section (title + its body, up to the next "## " or
# end of file) -- each chunk becomes its own sidebar entry + content pane below (site_shell.R's doc_nav()),
# instead of one continuous prose block. "### " subsections (e.g. "Layers of CAA Regulation"'s two
# "### Layer N" blocks) stay nested INSIDE their parent "## " pane, rendered as ordinary sub-headings --
# only "## " sections get their own sidebar entry.
slugify <- function(x) {                              # "State Implementation Plans (SIPs)" -> "state-implementation-plans-sips"; used as this section's #hash / element id, so must be unique per page and URL-fragment-safe
  x <- gsub("[^a-z0-9]+", "-", tolower(x))
  gsub("^-|-$", "", x)
}
h2_idx <- grep("^## ", lines)
if (length(h2_idx) == 0) stop("build_home.R: no '## ' sections found in institutional_overview.md after stripping -- doc_nav split has nothing to split.")
section_ends <- c(h2_idx[-1] - 1L, length(lines))
overview_sections <- Map(function(start, end) {
  title <- sub("^## +", "", lines[start])
  body  <- if (start < end) lines[(start + 1):end] else character(0)
  list(id = slugify(title), title = title,
       body_html = commonmark::markdown_html(paste(body, collapse = "\n"), extensions = TRUE))
}, h2_idx, section_ends)

nav_html <- doc_nav(overview_sections)

body <- paste0(
  hero(
    title        = "CAA Regulatory Data Infrastructure",
    desc         = paste(
      "A reproducible pipeline of U.S. Environmental Protection Agency (EPA) enforcement, compliance, and",
      "permitting data on stationary sources of air pollution under the Clean Air Act \u2014 built for",
      "empirical research on regulation and compliance."),
    eyebrow      = "Clean Air Act \u00B7 Stationary Sources",
    bg_image     = "images/hero-smokestack.jpg",
    photo_credit = paste(
      "Photo: John Messina, March 1973 \u2014 EPA Documerica Project / U.S. National Archives.",
      "Public domain.")
  ),
  page_main(
    cards(
      card("Raw Data", paste(
        "Per-source summary tables for all 16 raw ICIS-Air, AFS, and emissions files \u2014 variable",
        "coverage, frequent values, and missingness, computed directly from the raw downloads."),
        "raw_data.html"),
      card("Databases", paste(
        "What each database contains, what's missing, and how the files join \u2014 ICIS-Air, AFS, the",
        "combined emissions dataset, and the compliance-and-enforcement pipeline."),
        "databases.html"),
      card("Panels", paste(
        "Two continuous facility \u00d7 year panels built for empirical work on enforcement and",
        "compliance, 2015\u20132025: construction decisions, coverage, and summary statistics."),
        "panels.html")
    ),
    "<div class='prose'>", nav_html, "</div>"
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
