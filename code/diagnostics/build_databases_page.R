# =========================================================================================================
# code/diagnostics/build_databases_page.R \u2014 assembles docs/databases.html, the site's "Databases" page:
#   what each database (ICIS-Air, AFS, Emissions, Pipeline) contains, what's missing, and how the files
#   join. Content is narrative, not computed \u2014 it renders briefs/database_overviews.md (transcribed
#   verbatim from the project's Google Doc) via commonmark. No numbers are retyped here.
#   briefs/database_overviews.md -> docs/databases.html
# =========================================================================================================
library(here)
library(commonmark)
source(here("code", "diagnostics", "tables", "_html.R"))
source(here("code", "diagnostics", "site_shell.R"))

md_path <- here("briefs", "database_overviews.md")
lines   <- enc2utf8(readLines(md_path, warn = FALSE, encoding = "UTF-8"))

# drop the leading HTML provenance comment (<!-- ... -->) and the brief's own H1 (the hero supplies the
# page title)
c_start <- grep("<!--", lines)
c_end   <- grep("-->", lines)
if (length(c_start) && length(c_end)) lines <- lines[-(c_start[1]:c_end[1])]
while (length(lines) && !nzchar(trimws(lines[1]))) lines <- lines[-1]
if (length(lines) && grepl("^# ", lines[1])) lines <- lines[-1]

databases_html <- commonmark::markdown_html(paste(lines, collapse = "\n"), extensions = TRUE)

body <- paste0(
  hero(
    title   = "Database Overviews",
    desc    = paste(
      "What each database contains, what's missing, and how the files join \u2014 ICIS-Air (current), AFS",
      "(legacy, frozen 2014), the combined emissions dataset, and the compliance-and-enforcement",
      "pipeline."),
    eyebrow = "Sources"
  ),
  page_main(
    "<div class='section-note'>For column-by-column definitions of every field, see the ",
    "<a href='data_dictionary.md'>full data dictionary</a>. For live-computed variable coverage and ",
    "frequent values per file, see <a href='raw_data.html'>Raw Data</a>.</div>",
    "<div class='prose'>", databases_html, "</div>"
  )
)

html <- site_shell(
  title       = "Databases",
  description = "What each CAA regulatory database (ICIS-Air, AFS, emissions, pipeline) contains, what's missing, and how the files join.",
  active      = "databases",
  body_html   = body,
  script      = "code/diagnostics/build_databases_page.R"
)

OUT <- here("docs", "databases.html")
writeLines(html, OUT, useBytes = TRUE)
cat("wrote", OUT, "\n")
