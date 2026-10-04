# =========================================================================================================
# code/diagnostics/build_databases_page.R — assembles docs/databases.html, the site's "Datasets" page (nav
#   label renamed from "Databases"; see site_shell.R's NAV_ITEMS): what each of the eight datasets this
#   pipeline BUILDS (data/datasets/) contains, the decisions behind it, and its headline finding/caveat —
#   as a docs-site-style sidebar + content pane (site_shell.R's doc_nav()), one pane per dataset, same
#   pattern as build_home.R and build_site.R.
#   This replaces the page's old content (briefs/database_overviews.md, a description of the RAW EPA
#   source files transcribed from the project's Google Doc) -- that was redundant with the "Raw Data" page,
#   which already covers the raw sources with live-computed stat tables. briefs/database_overviews.md is
#   NOT deleted (still accurate as an internal reference) -- it just no longer has a public nav page.
#   briefs/datasets/datasets_overview.md -> docs/databases.html
# =========================================================================================================
library(here)
library(commonmark)
source(here("code", "diagnostics", "tables", "_html.R"))
source(here("code", "diagnostics", "site_shell.R"))

md_path <- here("briefs", "datasets", "datasets_overview.md")
lines   <- enc2utf8(readLines(md_path, warn = FALSE, encoding = "UTF-8"))

# drop the brief's own H1 (the hero supplies the page title)
if (length(lines) && grepl("^# ", lines[1])) lines <- lines[-1]

# strip internal decision-code citations ((R1), (O6), (H5)...) for a public audience -- done here at render
# time (NOT by hand-editing the source brief) so briefs/datasets/datasets_overview.md itself keeps its full
# traceability for a researcher returning to the project cold; only the public HTML drops the citations.
# Every instance here is a simple end-of-sentence "(CODE)" the brief's already-complete sentence doesn't
# need, so the shared regex sanitizer (_html.R) handles all of them with no further hand substitutions.
narrative_text <- strip_internal_citations(paste(lines, collapse = "\n"))
assert_no_internal_citations(narrative_text, "build_databases_page.R")
lines <- strsplit(narrative_text, "\n")[[1]]

# split into one chunk per top-level "## " section (title + its body, up to the next "## " or end of file)
# -- each chunk becomes its own sidebar entry + content pane (site_shell.R's doc_nav()), same
# split-then-slugify approach as build_home.R's institutional-overview sections.
slugify <- function(x) {
  x <- gsub("[^a-z0-9]+", "-", tolower(x))
  gsub("^-|-$", "", x)
}
h2_idx <- grep("^## ", lines)
if (length(h2_idx) == 0) stop("build_databases_page.R: no '## ' sections found in datasets_overview.md after stripping -- doc_nav split has nothing to split.")
section_ends <- c(h2_idx[-1] - 1L, length(lines))
dataset_sections <- Map(function(start, end) {
  title <- sub("^## +", "", lines[start])
  body  <- if (start < end) lines[(start + 1):end] else character(0)
  list(id = slugify(title), title = title,
       body_html = commonmark::markdown_html(paste(body, collapse = "\n"), extensions = TRUE))
}, h2_idx, section_ends)

nav_html <- doc_nav(dataset_sections)

body <- paste0(
  hero(
    title   = "Datasets",
    desc    = paste(
      "The eight datasets this pipeline builds — one row per facility × year (or, for Penalties and HPV",
      "Spells, one row per action/spell) — with the construction decisions behind each, its headline",
      "finding, and the one caveat that matters most before you use it."),
    eyebrow = "The Eight Datasets"
  ),
  page_main(
    "<div class='section-note'>These are the built datasets in <code>data/datasets/</code> — for the raw ",
    "EPA source files they're built from, see <a href='raw_data.html'>Raw Data</a>; for column-by-column ",
    "definitions of every field below, see the ",
    "<a href='dictionary.html'>Data Dictionary</a>.</div>",
    "<div class='prose'>", nav_html, "</div>"
  )
)

html <- site_shell(
  title       = "Datasets",
  description = "The eight datasets this pipeline builds from raw EPA data: what each contains, the construction decisions behind it, and its headline finding and caveat.",
  active      = "databases",
  body_html   = body
)

OUT <- here("docs", "databases.html")
writeLines(html, OUT, useBytes = TRUE)
cat("wrote", OUT, "\n")
