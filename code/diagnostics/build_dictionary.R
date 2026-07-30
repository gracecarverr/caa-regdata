# =========================================================================================================
# code/diagnostics/build_dictionary.R — assembles docs/dictionary.html, the site's "Dictionary" page: a
#   single browsable, cross-linked rendering of the two hand-maintained data-dictionary markdown files
#   (docs/data_dictionary.md for raw EPA source fields, docs/data_dictionary_derived.md for this repo's
#   computed/derived columns). Neither markdown file is edited by this script -- they stay the
#   hand-maintained source of truth (per docs/README.md); this script only re-parses their existing
#   headings into site_shell.R's doc_nav() sidebar + content-pane component, same pattern build_home.R and
#   build_databases_page.R already use, grouped (Raw · ICIS-Air / Raw · AFS / … / Derived · Datasets /
#   Derived · Panels) via doc_nav()'s new optional `group` field.
#   Every per-file pane also gets a "→" cross-link to the matching live section on raw_data.html (for raw
#   files) or databases.html (for the eight built datasets), where one exists -- see RAW_FILE_TO_ASSET and
#   DATABASES_SLUGS below for exactly which files that covers and why some don't.
#   docs/data_dictionary.md + docs/data_dictionary_derived.md -> docs/dictionary.html
# =========================================================================================================
library(here)
library(commonmark)
source(here("code", "diagnostics", "tables", "_html.R"))
source(here("code", "diagnostics", "site_shell.R"))

# same slugify() used (independently) by build_home.R and build_databases_page.R for their own doc_nav()
# ids -- not promoted to a shared helper because each build_*.R's split logic around it differs enough
# (this script also uses it to *reproduce* build_databases_page.R's slugs for cross-linking, see below).
slugify <- function(x) {
  x <- gsub("[^a-z0-9]+", "-", tolower(x))
  gsub("^-|-$", "", x)
}
md_html <- function(lines) commonmark::markdown_html(paste(lines, collapse = "\n"), extensions = TRUE)
# both dictionary files use a standalone "---" line only as a visual divider between "## " groups -- once
# those groups become real doc_nav() sections/dividers, the "---" itself would render as an unstyled <hr>
# (site_shell.R's .prose has no hr rule), so it's dropped here rather than adding a rule for one throwaway
# element.
strip_hr <- function(lines) lines[!grepl("^---+\\s*$", lines)]
# derived-layer headings carry a long descriptive suffix after " -- " (an em dash in the source file) or a
# parenthetical after " (" (e.g. "regulatory.csv.gz -- dataset 0, facility x year, ICIS-Air only", or
# "Facility filters (`PANEL_SPECS`)") -- fine as the pane's full <h2> heading (kept as `title`, untouched),
# but too long for doc_nav()'s 230px sidebar without wrapping badly. short_label() cuts a heading down to
# just the part before its first " --"/" (" for use as that pane's sidebar `label`; headings with neither
# delimiter (e.g. "Conventions used throughout", or almost every raw '### `FILE.csv`' heading) pass through
# unchanged.
short_label <- function(x) sub("\\s+[\u2014(].*$", "", x)

# ---- cross-link lookup tables ----------------------------------------------------------------------------
# RAW_FILE_TO_ASSET: raw CSV filename (exactly as it appears inside a "### `FILE.csv`" heading in
# data_dictionary.md) -> the asset slug build_site.R's TITLES vector uses for that file's raw_data.html
# anchor (build_site.R's h_head() emits `<h2 id='<asset>'>`). Hand-verified against every tables/*.R's
# h_head(id, title, csv, ...) call as of this writing. Not derived programmatically: sourcing all of
# tables/*.R here just to recover 16 id/csv pairs would also re-read the ~923MB raw emissions file
# (SKIP_SECTIONS exists in build_site.R for exactly this cost) for a build step that has no other reason to
# touch data/raw/ at all. Two raw files documented in data_dictionary.md have NO entry here on purpose --
# see FLAGGED ISSUES.
RAW_FILE_TO_ASSET <- c(
  "ICIS-AIR_FACILITIES.csv"         = "facilities",
  "ICIS-AIR_VIOLATION_HISTORY.csv"  = "violations",
  "ICIS-AIR_FCES_PCES.csv"          = "inspections",
  "ICIS-AIR_FORMAL_ACTIONS.csv"     = "formal_actions",
  "ICIS-AIR_INFORMAL_ACTIONS.csv"   = "informal_actions",
  "ICIS-AIR_TITLEV_CERTS.csv"       = "certs",
  "ICIS-AIR_STACK_TESTS.csv"        = "stacktests",
  "ICIS-AIR_POLLUTANTS.csv"         = "pollutants",
  "ICIS-AIR_PROGRAMS.csv"           = "programs",
  "ICIS-AIR_PROGRAM_SUBPARTS.csv"   = "program_subparts",
  "AFS_ACTIONS.csv"                 = "afs_actions",
  "AIR_PROGRAM.csv"                 = "afs_air_program",
  "AFS_FACILITIES.csv"              = "afs_facilities",
  "AFS_AIR_PRG_HIST_COMPLIANCE.csv" = "afs_hist_compliance",
  "AFS_HPV_HISTORY.csv"             = "afs_hpv",
  "POLL_RPT_COMBINED_EMISSIONS.csv" = "emissions"
)
# DATABASES_SLUGS: which data_dictionary_derived.md Part-1 "## `file.csv.gz` — …" sections have a matching
# pane on databases.html. A derived-file slug is computed below as its csv stem with "_" -> "-" (e.g.
# "hpv_spells" -> "hpv-spells"), which reproduces build_databases_page.R's own slugify() of its 8 short
# section titles exactly (slugify("HPV Spells") == "hpv-spells", etc. -- checked by hand against
# briefs/datasets/datasets_overview.md's eight "## " headers). Only 8 of the 9 files under data/datasets/
# are in this set: `wayback_only_facilities` (dataset 1b) has no databases.html section (it's a
# supplementary output, not one of the eight numbered datasets -- see build_databases_page.R's own hero
# copy), so it gets no cross-link.
DATABASES_SLUGS <- c("regulatory", "operating", "hpv-spells", "hpv-active",
                      "penalties", "coordinates", "pipeline", "emissions")

# ===========================================================================================================
# PART A -- docs/data_dictionary.md (raw source layer): "## " = source group (ICIS-Air / Air Emissions /
#   AFS / CAA Compliance Pipeline), "### " = one pane per raw file (or, once, a non-file appendix). Text
#   between a "## " heading and its first "### " (e.g. "Raw files in data/raw/ICIS-AIR_downloads/. All join
#   on PGM_SYS_ID.") documents the whole group, not any one file -- it's prepended to that group's FIRST
#   pane below rather than silently dropped, same "don't lose front matter" concern build_home.R/
#   build_databases_page.R handle by dropping only the H1 they know is redundant with hero().
# ===========================================================================================================
raw_path  <- here("docs", "data_dictionary.md")
raw_lines <- enc2utf8(readLines(raw_path, warn = FALSE, encoding = "UTF-8"))
if (length(raw_lines) && grepl("^# ", raw_lines[1])) raw_lines <- raw_lines[-1]   # drop the file's own H1 (hero() supplies the page title)
raw_lines <- strip_hr(raw_lines)
# no internal decision-code citations exist in this file today (it documents RAW EPA fields, verified
# against EPA's own published dictionaries -- no internal construction decisions apply) -- sanitized anyway
# as a light safety net in case that ever changes. No assert_no_internal_citations() here (unlike the
# derived-layer file below): this file's own appendices legitimately contain short backtick-quoted EPA
# action codes that collide with the citation-code shape (e.g. `C3`/`C7`/`PL3` as literal AFS resolution-
# type codes, not this repo's internal citations) -- a hard stop here would false-positive on real content.
raw_lines <- strsplit(strip_internal_citations(paste(raw_lines, collapse = "\n")), "\n")[[1]]

h2_idx <- grep("^## ", raw_lines)
if (length(h2_idx) == 0) stop("build_dictionary.R: no '## ' groups found in data_dictionary.md -- its heading structure may have changed.")
# everything before the first "## " (the Sources list + Scope/Conventions/Provenance blockquotes) is page
# front matter, not any one file's documentation -- rendered once above the sidebar, not as a pane.
raw_intro_html <- md_html(raw_lines[seq_len(h2_idx[1] - 1)])

h2_ends <- c(h2_idx[-1] - 1L, length(raw_lines))
raw_sections <- list()
for (gi in seq_along(h2_idx)) {
  group_title <- sub("^## +", "", raw_lines[h2_idx[gi]])
  group_lines <- raw_lines[(h2_idx[gi] + 1):h2_ends[gi]]
  h3_idx <- grep("^### ", group_lines)
  if (length(h3_idx) == 0) {
    # a "## " group with no "### " file headings underneath (e.g. "Grain and time-type, at a glance", a
    # cross-cutting summary table that isn't about any one source) doesn't fit the per-file pane pattern --
    # give it exactly one pane of its own, grouped under "Raw · Overview" alongside any other such
    # non-per-file group, rather than erroring (this used to stop() here; a genuinely EMPTY "## " group --
    # heading with zero body lines at all -- would still produce one pane with an empty body, which is
    # visibly obvious on the page rather than a silent failure, so still safe).
    raw_sections[[length(raw_sections) + 1]] <- list(
      id        = paste0("raw-", slugify(group_title)),
      title     = group_title,
      label     = short_label(group_title),
      group     = "Raw · Overview",
      body_html = md_html(group_lines)
    )
    next
  }
  group_intro <- if (h3_idx[1] > 1) group_lines[seq_len(h3_idx[1] - 1)] else character(0)
  h3_ends <- c(h3_idx[-1] - 1L, length(group_lines))
  for (fi in seq_along(h3_idx)) {
    raw_title  <- sub("^### +", "", group_lines[h3_idx[fi]])
    body_lines <- if (h3_idx[fi] < h3_ends[fi]) group_lines[(h3_idx[fi] + 1):h3_ends[fi]] else character(0)
    if (fi == 1) body_lines <- c(group_intro, "", body_lines)   # only the group's first pane carries the group-level intro text

    # a per-file heading is always exactly "`FILE.csv`" (backtick-quoted, nothing else on the line); the
    # one exception in this file is "### AFS pollutant codes (Appendix 1)", which regexec() below simply
    # won't match -- correctly leaving it with no raw_data.html cross-link (there is no per-appendix
    # section on that page to link to).
    m        <- regmatches(raw_title, regexec("^`([^`]+)`$", raw_title))[[1]]
    filename <- if (length(m) == 2) m[2] else NA_character_
    # RAW_FILE_TO_ASSET is a plain named character vector, not a list -- `[[` on a name that isn't present
    # errors ("subscript out of bounds") rather than returning NULL, so lookup goes through `%in% names()`
    # first and single-bracket indexing (which returns NA, not an error, for an absent name).
    asset    <- if (!is.na(filename) && filename %in% names(RAW_FILE_TO_ASSET)) unname(RAW_FILE_TO_ASSET[filename]) else NA_character_
    xref_html <- if (!is.na(asset)) sprintf(
      "<p class='dict-xref'><a href='raw_data.html#%s'>Variable coverage &amp; summary stats →</a></p>",
      asset) else ""

    clean_title <- gsub("`", "", raw_title)
    raw_sections[[length(raw_sections) + 1]] <- list(
      id        = paste0("raw-", slugify(raw_title)),
      title     = clean_title,
      label     = short_label(clean_title),
      group     = paste0("Raw · ", group_title),
      body_html = paste0(md_html(body_lines), xref_html)
    )
  }
}

# ===========================================================================================================
# PART B -- docs/data_dictionary_derived.md (derived layer): "# Part 1 …" / "# Part 2 …" are GROUP markers
#   (data/datasets/ vs data/panels/), not panes of their own; "## " under each is one pane. This file's
#   heading levels differ from data_dictionary.md's (H1 groups + H2 files, vs. data_dictionary.md's H2
#   groups + H3 files) because that's how the source file is actually written -- preserved as-is rather
#   than normalized, since renumbering headings in the hand-maintained .md is out of scope here.
#   A small state machine walks every H1/H2 heading in document order: an H1 sets `current_group` and
#   stashes its own body text as `pending_intro` (that text belongs to the group, not to any specific file,
#   same "## Conventions used throughout" (line ~21) precedes the very first "# Part 1" heading, so it has
#   no group yet -- current_group starts at "Derived · Overview" to give it a home instead of erroring.
# ===========================================================================================================
der_path  <- here("docs", "data_dictionary_derived.md")
der_lines <- enc2utf8(readLines(der_path, warn = FALSE, encoding = "UTF-8"))
if (length(der_lines) && grepl("^# ", der_lines[1])) der_lines <- der_lines[-1]
der_lines <- strip_hr(der_lines)

# ---- public-site sanitization: this file's per-field tables all end in a "Decision" column citing the
# internal construction-decision code(s) behind that field (R1-R9/O1-O8/H1-H7/P1-P5/C1-C5/PL1-PL5/EM1-EM6/
# PB1-PB8/G1-G4) -- exactly right for docs/data_dictionary_derived.md itself (the hand-maintained,
# never-edited-here source of truth, per docs/README.md), but internal-audience noise on the public page.
# Done here at render time, NOT by hand-editing that source file, so it keeps its full traceability.
# 1) strip_decision_column() drops the whole trailing "Decision" column (structural -- every one of this
#    file's 11 tables has it, verified by hand), 2) strip_internal_citations() (_html.R) regex-strips the
#    simple bare "(CODE)" citations and "Fixed/Revised YYYY-MM-DD (CODE)" changelog preambles left inline in
#    the "Definition & derivation" column, 3) DICTIONARY_TEXT_SUBS below handles the remainder -- composite
#    parentheticals/citations regex can't safely untangle (same exact-text-match approach build_panels_page.R
#    uses for panel_profile.md's organic prose), verified against this file's current (2026-07-29) wording.
der_lines <- strip_decision_column(der_lines)
der_text  <- strip_internal_citations(paste(der_lines, collapse = "\n"))
DICTIONARY_TEXT_SUBS <- list(
  # bracketed differently from every other changelog annotation in this file ("(**revised DATE, explicit
  # user decision — CODE**):" -- colon AFTER the closing paren, lowercase "revised") -- strip_internal_
  # citations()'s general changelog regex deliberately doesn't try to match this shape, so it needs its own
  # entry rather than silently mangling a pattern built for the far more common "**Fixed DATE (CODE):**" form.
  list(pat = "\\(\\*\\*revised 2026-07-29, explicit user decision — `PB2`\\*\\*\\):",
       rep = ":"),
  # strip_internal_citations()'s generic "Previously: " prefix reads fine for a past-tense continuation
  # ("was a grepl() match...") but is self-contradictory here, since the continuation is itself present-
  # tense ("now a four-way split") -- fixed up after the fact rather than special-cased in the shared
  # regex, since this is the one changelog instance across every page where the two tenses collide.
  list(pat = "Previously: now a four-way split\\.",
       rep = "This is now a four-way split."),
  list(pat = "For the \\*why\\* behind a specific choice[\\s\\S]*?not the full rationale\\.",
       rep = "This file gives the *what/how* for each column, not the full rationale behind every construction choice."),
  list(pat = "> \\*\\*Verified against code\\.\\*\\*[\\s\\S]*?once that lands\\.",
       rep = paste("> **Verified against code.** Checked directly against the build scripts and this repo's own",
                    "`.csv.gz` headers as of 2026-07-27; the panel layer (Part 2) will be re-verified once an",
                    "in-progress Wayback-snapshot refresh lands upstream.")),
  list(pat = "\\(2026-07-28: expanded from 8 to all 15 codes[\\s\\S]*?this closed\\)",
       rep = ""),
  list(pat = "; sample selection is left to the user\\. Full narrative: `dataset_construction_decisions\\.md`\\.",
       rep = "; sample selection is left to the user."),
  list(pat = "\\(the `O1a` population\\)",
       rep = ""),
  list(pat = "the pre-done version of the manual join `O1a` used to point users to\\.",
       rep = "the pre-done version of a manual join users previously had to do."),
  list(pat = "on `violations\\.csv\\.gz`, decision `H1`\\)",
       rep = "on `violations.csv.gz`)"),
  list(pat = "facility × year, R2 interval-overlap collapse of",
       rep = "facility × year, interval-overlap collapse of"),
  list(pat = "chosen over alternatives in diagnostic 09, `H5`\\)",
       rep = "chosen over alternatives in diagnostic 09)"),
  list(pat = "Per diagnostic `H1`, ",
       rep = ""),
  list(pat = "See `code/04_panel_building/README\\.md` and[\\s\\S]*?for the full \"why\\.\"",
       rep = "See `code/04_panel_building/README.md` for the full construction rationale."),
  list(pat = "\\(`operating\\.csv\\.gz`, dataset-layer decision `O6`\\)",
       rep = "(from `operating.csv.gz`)"),
  list(pat = "facility-level spell fields, `O4`\\)",
       rep = "facility-level spell fields)"),
  list(pat = "\\*\\*Removed from the panel, 2026-07-29 \\(explicit user decisions\\):\\*\\*",
       rep = "**Not included in this layer (explicit decisions):**"),
  list(pat = "carries,\\s*\\n?\\s*`R5`\\)",
       rep = "carries)"),
  list(pat = "the R2 interval-overlap collapse, `H5`/`H6`/`H7` zero-vs-NA discipline\\.",
       rep = "the same interval-overlap collapse and zero-vs-NA discipline used elsewhere in this layer."),
  list(pat = "the dataset layer's own `R4`\\s+convention",
       rep = "the dataset layer's own convention"),
  # 2 more, added with the 2026-07-30 OPERATING_IMPUTED entry -- inline "`O2`" mentions mid-sentence, not a
  # bare "(CODE)" parenthetical, so the auto-stripper's bare-parens regex doesn't catch them.
  list(pat = "The one exception to `O2`'s \"strictly raw\" rule\\s+—\\s+see `O2` for the full derivation",
       rep = "The one exception to this layer's \"strictly raw\" rule — see `dataset_construction_decisions.md` for the full derivation")
)
for (s in DICTIONARY_TEXT_SUBS) {
  if (!grepl(s$pat, der_text, perl = TRUE)) {
    warning(sprintf("build_dictionary.R: public-text substitution pattern did not match (data_dictionary_derived.md may have changed) -- pattern: %s", s$pat))
  }
  der_text <- gsub(s$pat, s$rep, der_text, perl = TRUE)
}
assert_no_internal_citations(der_text, "build_dictionary.R (data_dictionary_derived.md)")
der_lines <- strsplit(der_text, "\n")[[1]]

h_idx <- grep("^#{1,2} ", der_lines)
if (length(h_idx) == 0) stop("build_dictionary.R: no '# '/'## ' headings found in data_dictionary_derived.md -- its heading structure may have changed.")
h_level <- ifelse(grepl("^# ", der_lines[h_idx]), 1L, 2L)   # "# " (Part marker) vs "## " (file/topic pane) -- checked BEFORE the H1 is dropped below, since der_lines[1] was already removed above
h_end   <- c(h_idx[-1] - 1L, length(der_lines))

# front matter before "## Conventions used throughout" (the intro paragraph + "Verified against code" note)
der_intro_html <- md_html(der_lines[seq_len(h_idx[1] - 1)])

der_sections  <- list()
current_group <- "Derived · Overview"
pending_intro <- character(0)
for (i in seq_along(h_idx)) {
  title <- sub("^#{1,2} +", "", der_lines[h_idx[i]])
  body  <- if (h_idx[i] < h_end[i]) der_lines[(h_idx[i] + 1):h_end[i]] else character(0)

  if (h_level[i] == 1) {
    # "# Part 1 — `data/datasets/` …" / "# Part 2 — `data/panels/` …" -- matched on "Part 1"/"Part 2"
    # literally rather than counting occurrences, so a future re-titled-but-still-"Part 1"-prefixed
    # heading keeps working; anything else would be a genuinely new group this script doesn't know about.
    current_group <- if (grepl("Part 1", title)) "Derived · Datasets" else "Derived · Panels"
    pending_intro <- body   # this heading's own body (e.g. the "each dataset is built once over the full…" line) belongs to the group, held for its first pane below
    next
  }

  # a per-dataset heading is "`file.csv.gz` — description…"; anything else under Part 1/2 (Conventions,
  # Facility filters, Facility-level attributes, Year-varying block) is a topic pane, not a per-file one,
  # and gets no databases.html/panels.html per-section cross-link (see FLAGGED ISSUES for Part 2).
  m        <- regmatches(title, regexec("^`([^`]+\\.csv\\.gz)`", title))[[1]]
  is_file  <- length(m) == 2
  slug     <- if (is_file) gsub("_", "-", sub("\\.csv\\.gz$", "", m[2])) else NA_character_

  xref_html <- if (is_file && slug %in% DATABASES_SLUGS) {
    sprintf("<p class='dict-xref'><a href='databases.html#%s'>Construction decisions &amp; headline finding →</a></p>", slug)
  } else if (identical(current_group, "Derived · Panels") && length(pending_intro) > 0) {
    # Part 2 has no per-file structure to deep-link (see header note) -- instead, the ONE pane that
    # absorbs Part 2's group intro (the first one, "Facility filters") also gets a single general pointer
    # to panels.html. `length(pending_intro) > 0` is true only right after the "# Part 2" heading, so
    # later Part-2 panes (Facility-level attributes, Year-varying block) correctly get no duplicate link.
    "<p class='dict-xref'><a href='panels.html'>Panel coverage &amp; summary statistics →</a></p>"
  } else ""

  body_full <- if (length(pending_intro)) c(pending_intro, "", body) else body
  pending_intro <- character(0)   # consumed -- only the group's first pane gets it

  clean_title <- gsub("`", "", title)
  der_sections[[length(der_sections) + 1]] <- list(
    id        = paste0("derived-", slugify(title)),
    title     = clean_title,
    label     = short_label(clean_title),
    group     = current_group,
    body_html = paste0(md_html(body_full), xref_html)
  )
}

# ---- assemble -----------------------------------------------------------------------------------------
nav_html <- doc_nav(c(raw_sections, der_sections))

body <- paste0(
  hero(
    title   = "Data Dictionary",
    desc    = paste(
      "Every raw EPA source field this pipeline reads, and every column it computes or derives —",
      "one pane per file, cross-linked to the live summary statistics on Raw Data and to the",
      "construction notes on Datasets and Panels wherever a matching section exists."),
    eyebrow = "Field-Level Reference"
  ),
  page_main(
    "<div class='section-note'>Two layers, hand-maintained against EPA's published dictionaries and this ",
    "repo's build code, not generated: <b>raw source fields</b> (verbatim EPA definitions) feeding ",
    "<a href='raw_data.html'>Raw Data</a>, and <b>derived/computed columns</b> feeding ",
    "<a href='databases.html'>Datasets</a> and <a href='panels.html'>Panels</a>. This page only reformats ",
    "<code>docs/data_dictionary.md</code> and <code>docs/data_dictionary_derived.md</code> — they ",
    "remain the source of truth; edit them, not this page.</div>",
    "<div class='prose'>", raw_intro_html, der_intro_html, nav_html, "</div>"
  )
)

html <- site_shell(
  title       = "Dictionary",
  description = "Field-by-field reference for every raw EPA source and every derived column this pipeline builds, cross-linked to the live summary statistics and dataset pages.",
  active      = "dictionary",
  body_html   = body
)

OUT <- here("docs", "dictionary.html")
writeLines(html, OUT, useBytes = TRUE)
cat("wrote", OUT, "(", length(raw_sections) + length(der_sections), "panes )\n")

# ---- FLAGGED ISSUES -------------------------------------------------------------------------------------
# - RAW_FILE_TO_ASSET is a hand-maintained 16-entry mapping, not derived from build_site.R at build time
#   (see the comment above its definition for why). If a tables/*.R script's h_head() id or csv argument
#   ever changes, this mapping silently goes stale for that one file (its pane just loses its "Variable
#   coverage & summary stats" link -- it doesn't error), until this file is re-checked by hand.
# - Two data_dictionary.md "### " sections get no raw_data.html cross-link by design, not oversight:
#   `PIPELINE_CAA_00_COMPLETE.csv` (the CAA Compliance Pipeline group) has no per-source section on
#   raw_data.html at all (build_site.R's TITLES has no "pipeline" entry), and "AFS pollutant codes
#   (Appendix 1)" isn't a file, it's a shared code-list appendix.
# - Part 2 of the derived layer (`data/panels/`) isn't structured per-file the way Part 1 and the raw layer
#   are (its three "## " panes are Facility filters / Facility-level attributes / Year-varying block, not
#   one section per panel), so there's no way to deep-link a specific pane to a specific panels.html
#   section the way Part 1 links to databases.html -- only one general pointer to panels.html is attached,
#   on the first Part-2 pane.
# - Both dictionary .md files' own inline relative links (e.g. data_dictionary.md's Scope-note link to
#   `data_dictionary_derived.md`) are passed through by commonmark unchanged -- they still resolve (the raw
#   .md files are still shipped in docs/), just not to this page's prettier rendering of the same content.
#   Not rewritten here: correctly identifying and redirecting only the handful of cross-dictionary links,
#   without touching the many other relative links these files contain (to briefs/, code/, data/READMEs),
#   isn't worth the fragility for a cosmetic improvement.
