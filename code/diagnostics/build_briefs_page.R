# =========================================================================================================
# code/diagnostics/build_briefs_page.R — assembles docs/briefs.html, the site's "Briefs" page: a numbered
#   card grid (mimicking the reference RCRA site's briefs.html) followed by a docs-site-style sidebar +
#   content pane (site_shell.R's doc_nav()), same pattern as build_home.R/build_databases_page.R/
#   build_panels_page.R. Twelve briefs, numbered 00-11:
#     00-08  briefs/institutional_overview.md's own "## " sections, split one-per-brief (moved here from
#            build_home.R, which used to render this content embedded on the Home page -- Home now just
#            links here instead, so this is the only place this content is rendered).
#     09-11  three new topic briefs (facility identifiers, the data systems, pollutant/source
#            classification) filling the gap this project had relative to the reference site's institutional
#            briefs -- each condensed from content already verified elsewhere in this repo (see each .md
#            file's own header comment for its source), not re-derived here.
#   Unlike build_home.R's old version of this split, "> Data implication" blockquotes are KEPT (not
#   stripped) -- ending each brief with its data implication is the point of this page, matching the
#   reference site's own "each ending in what it implies for the data" framing.
#   briefs/institutional_overview.md + briefs/facility_identifiers.md + briefs/data_systems.md +
#   briefs/pollutant_classification.md -> docs/briefs.html
# =========================================================================================================
library(here)
library(commonmark)
source(here("code", "diagnostics", "tables", "_html.R"))
source(here("code", "diagnostics", "site_shell.R"))

slugify <- function(x) {                               # matches build_home.R's/build_databases_page.R's own slugify -- must stay identical so #hash cross-references between briefs (e.g. pollutant_classification.md linking to "#naaqs") resolve to the ids this script actually emits
  x <- gsub("[^a-z0-9]+", "-", tolower(x))
  gsub("^-|-$", "", x)
}

md_section <- function(title, body_lines) list(
  id = slugify(title), title = title,
  body_html = commonmark::markdown_html(paste(body_lines, collapse = "\n"), extensions = TRUE))

# ---- 00-08: split briefs/institutional_overview.md by its own "## " headings --------------------------
ov_path  <- here("briefs", "institutional_overview.md")
ov_lines <- enc2utf8(readLines(ov_path, warn = FALSE, encoding = "UTF-8"))

if (length(ov_lines) && grepl("^# ", ov_lines[1])) ov_lines <- ov_lines[-1]   # drop the brief's own H1 (each pane's own "## " heading becomes doc_nav()'s <h2> instead)

# drop "## Valuable Links" (working-notes scratchpad) and "## See also" (a plain link list, not a topic)
for (heading in c("^## Valuable Links$", "^## See also$")) {
  start <- grep(heading, ov_lines)
  if (length(start) == 1) {
    h2s   <- grep("^## ", ov_lines)
    after <- h2s[h2s > start]
    end   <- if (length(after)) after[1] - 1L else length(ov_lines)
    ov_lines <- ov_lines[-(start:end)]
  }
}

# strip internal decision-doc citations ((Decision N11 in archive/panel_building_legacy/...md), etc.) for a
# public audience -- done here at render time (NOT by hand-editing the source brief) so
# briefs/institutional_overview.md itself keeps its full traceability. The two "Decision N##" citations here
# point at an archived directory not published under docs/, so they're dead links on the public page; each
# is a distinct enough sentence shape that they're handled as exact substitutions rather than a general regex.
ov_text <- strip_internal_citations(paste(ov_lines, collapse = "\n"))
BQ_LINK <- paste0("\\[`archive/panel_building_legacy/briefs/panel/panel_construction_decisions\\.md`\\]",
                   "\\(\\.\\./archive/panel_building_legacy/briefs/panel/panel_construction_decisions\\.md\\)")
BQ_GAP  <- "(?:\\s|>)*"   # whitespace/newlines AND the blockquote continuation marker ("> ") the source wraps onto its next line with
BRIEFS_TEXT_SUBS <- list(
  list(pat = paste0("\\(Decision N11 in", BQ_GAP, BQ_LINK, BQ_GAP,
                     "— this is an intentional divergence from `operating`, not a bug\\.\\)"),
       rep = "This is an intentional divergence from `operating`, not a bug."),
  list(pat = paste0("\\(Decision N12 in", BQ_GAP, BQ_LINK, "\\.\\)"),
       rep = "")
)
for (s in BRIEFS_TEXT_SUBS) {
  if (!grepl(s$pat, ov_text, perl = TRUE)) {
    warning(sprintf("build_briefs_page.R: public-text substitution pattern did not match (brief text may have changed) -- pattern: %s", s$pat))
  }
  ov_text <- gsub(s$pat, s$rep, ov_text, perl = TRUE)
}
assert_no_internal_citations(ov_text, "build_briefs_page.R")
ov_lines <- strsplit(ov_text, "\n")[[1]]

h2_idx <- grep("^## ", ov_lines)
if (length(h2_idx) == 0) stop("build_briefs_page.R: no '## ' sections found in institutional_overview.md after stripping -- nothing to split into briefs 00-08.")
section_ends <- c(h2_idx[-1] - 1L, length(ov_lines))
overview_sections <- Map(function(start, end) {
  title <- sub("^## +", "", ov_lines[start])
  body  <- if (start < end) ov_lines[(start + 1):end] else character(0)
  md_section(title, body)
}, h2_idx, section_ends)

# ---- 09-11: the three new standalone topic briefs -------------------------------------------------------
new_brief <- function(filename) {
  lines <- enc2utf8(readLines(here("briefs", filename), warn = FALSE, encoding = "UTF-8"))
  lines <- lines[!grepl("^<!--", lines)]        # drop the leading source-citation HTML comment (not page content)
  lines <- lines[!grepl("^     ", lines)]       # drop that comment's wrapped continuation lines (see each file's header)
  while (length(lines) && !nzchar(trimws(lines[1]))) lines <- lines[-1]   # drop the blank line(s) left between the stripped comment and the title
  if (length(lines) && grepl("^# ", lines[1])) { title <- sub("^# +", "", lines[1]); lines <- lines[-1] } else stop(paste0("build_briefs_page.R: ", filename, " has no leading '# ' title."))
  text <- strip_internal_citations(paste(lines, collapse = "\n"))
  assert_no_internal_citations(text, paste0("build_briefs_page.R (", filename, ")"))
  md_section(title, strsplit(text, "\n")[[1]])
}
new_sections <- lapply(c("facility_identifiers.md", "data_systems.md", "pollutant_classification.md"), new_brief)

all_sections <- c(overview_sections, new_sections)

# ---- landing grid: one numbered card per brief, teaser = section's first <p>...</p> ---------------------
first_p <- function(html) {
  m <- regmatches(html, regexec("<p>(.*?)</p>", html))[[1]]
  if (length(m) < 2) return("")
  gsub("<[^>]+>", "", m[2])   # strip any inline tags (links, emphasis) from the teaser -- plain text only, esc()'d by card()
}
brief_cards <- Map(function(s, i) card(
  title = s$title,
  desc  = first_p(s$body_html),
  href  = paste0("#", s$id),
  cta   = "Read →",
  badge = sprintf("Brief %02d", i - 1)
), all_sections, seq_along(all_sections))

nav_html <- doc_nav(all_sections)

body <- paste0(
  hero(
    title   = "Institutional Briefs",
    desc    = paste(
      "The data in this project are administrative records produced by a regulatory program, so a column",
      "only means what the rule behind it says it means. These briefs record those rules — the Clean Air",
      "Act's own structure, plus the data systems and identifiers that carry it into this project's",
      "files — each ending in what it implies for the data."),
    eyebrow = "Twelve Briefs"
  ),
  page_main(
    cards(paste(unlist(brief_cards), collapse = "")),
    "<div class='prose'>", nav_html, "</div>",
    "<p class='table-note'>Institutional facts are drawn from public EPA/CAA program materials and the ",
    "project's own source documentation; see each brief's markdown source in ",
    "<code><a href='https://github.com/gracecarverr/caa-regdata/tree/main/briefs' target='_blank' rel='noopener'>briefs/</a></code> ",
    "for its citation.</p>"
  )
)

html <- site_shell(
  title       = "Briefs",
  description = "Twelve institutional briefs on the Clean Air Act's regulatory structure and the EPA data systems this project draws on, each ending in what it implies for the data.",
  active      = "briefs",
  body_html   = body
)

OUT <- here("docs", "briefs.html")
writeLines(html, OUT, useBytes = TRUE)
cat("wrote", OUT, "(", length(all_sections), "briefs )\n")
