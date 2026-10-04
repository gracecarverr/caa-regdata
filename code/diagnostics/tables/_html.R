# =========================================================================================================
# code/diagnostics/tables/_html.R — HTML rendering primitives for the summary-table site (docs/index.html).
# These mirror the openxlsx primitives used by the old CAA_Project table-*.R workbooks so that each
# ported table script keeps its stat code + curated content verbatim and only swaps the output layer:
#   - green categorical table (#C6EFCE header) with merged Variable/%Missing/#Categories cells (rowspan)
#   - orange date/numeric table (#F4B084 header)
#   - header block, free-text/footnote notes, and a duplicates section.
# Each ported script returns one <section> string; code/diagnostics/build_site.R assembles the page.
# =========================================================================================================

esc   <- function(x) { x <- as.character(x); x <- gsub("&", "&amp;", x); x <- gsub("<", "&lt;", x); gsub(">", "&gt;", x) }
comma  <- function(x) format(round(as.numeric(x)), big.mark = ",", scientific = FALSE, trim = TRUE)  # matches numFmt "#,##0"; formatC(format="d") silently returns NA above ~2^31 (int32 overflow), which ANNUAL_EMISSION's max exceeds
pct1   <- function(fr) sprintf("%.1f%%", 100 * as.numeric(fr))   # matches the old cell_pct numFmt "0.0%"
dollar <- function(x) paste0("$", format(round(as.numeric(x)), big.mark = ",", scientific = FALSE, trim = TRUE))  # numFmt "$#,##0"

# ---- section wrapper + header block ---------------------------------------------------------------------
sec <- function(...) paste0("<section>", paste0(..., collapse = ""), "</section>")

# id: anchor; title: "ICIS-Air Facilities"; csv: source filename; desc: one-line description;
# obs_line: "OBSERVATIONS: ...  DISTINCT ...  TEMPORAL COVERAGE: ..."; inventory: field-grouping line (optional).
h_head <- function(id, title, csv, desc, obs_line, inventory = NULL) paste0(
  "<h2 id='", id, "'>", esc(title), "</h2>",
  "<p class='src'>", esc(csv), "</p>",
  "<p class='desc'>", esc(desc), "</p>",
  "<p class='obs'>", esc(obs_line), "</p>",
  if (!is.null(inventory)) paste0("<p class='inv'>", esc(inventory), "</p>") else "")

# ---- green categorical table ---------------------------------------------------------------------------
# Mirrors old write_variable(): col 1 = var_name (bold) + var_desc, merged (rowspan) over its value rows;
# %Missing and #Categories merged too; then one row per frequent value: label (left), N (#,##0), % (0.0%).
# ns: integer counts; pcts: fractions in [0,1]; pct_missing: preformatted string e.g. "12.3%".
cat_var <- function(var_name, var_desc, pct_missing, n_cats, descs, ns, pcts) {
  k <- max(length(descs), 1L)
  lead <- paste0(
    "<td rowspan='", k, "' class='var'><b>", esc(var_name), "</b>",
      if (nzchar(var_desc)) paste0("<br><span class='vd'>", esc(var_desc), "</span>") else "", "</td>",
    "<td rowspan='", k, "'>", esc(pct_missing), "</td>",
    "<td rowspan='", k, "'>", esc(n_cats), "</td>")
  if (length(descs) == 0) return(paste0("<tr>", lead, "<td></td><td></td><td></td></tr>"))
  cells <- paste0("<td class='l'>", esc(descs), "</td><td>", comma(ns), "</td><td>", pct1(pcts), "</td>")
  paste0("<tr>", lead, cells[1], "</tr>", paste0("<tr>", cells[-1], "</tr>", collapse = ""))
}
cat_table <- function(rows) paste0(
  "<table class='cat'><tr><th>Variable</th><th>% Missing</th><th># Categories</th>",
  "<th>Frequent Values</th><th>N</th><th>%</th></tr>", paste0(rows, collapse = ""), "</table>")

# ---- orange date / numeric table -----------------------------------------------------------------------
# headers: character vector of column labels (e.g. Variable,% Missing,N,Min,P5,Median,P95,Max).
# num_row(name, desc, cells): cells is a preformatted character vector aligned to headers[-1].
num_row <- function(name, desc, cells) paste0(
  "<tr><td class='var'><b>", esc(name), "</b>",
    if (!is.null(desc) && nzchar(desc)) paste0("<br><span class='vd'>", esc(desc), "</span>") else "", "</td>",
  paste0("<td>", esc(cells), "</td>", collapse = ""), "</tr>")
num_table <- function(headers, rows) paste0(
  "<table class='num'><tr>", paste0("<th>", esc(headers), "</th>", collapse = ""), "</tr>",
  paste0(rows, collapse = ""), "</table>")

# ---- notes / footnotes / duplicates --------------------------------------------------------------------
note  <- function(text) paste0("<p class='note'>", esc(text), "</p>")
dupes <- function(text) paste0("<p class='dupes'><b>DUPLICATES</b><br>", esc(text), "</p>")

# ---- public-site citation sanitizer ----------------------------------------------------------------------
# Every build_*.R page builder that injects prose verbatim from an internal source (briefs/*.md,
# docs/data_dictionary*.md) uses this to strip that source's internal decision-code citations
# (`R1`, `O6`, `H5`, `PB2`, ... -- pointers into dataset_construction_decisions.md/panel_construction_
# decisions.md) and changelog-style "Fixed/Revised YYYY-MM-DD" annotations before rendering, so the public
# HTML reads as a public reference rather than an internal traceability log. The SOURCE .md files themselves
# are never touched -- they keep full citations for a researcher returning to the project cold; only the
# rendered page is sanitized. Mirrors the exact-text PUBLIC_TEXT_SUBS approach build_panels_page.R already
# used for organic prose it can't safely regex (composite parentheticals, filename citations) -- callers
# should still apply their own hand-checked substitutions for those after calling this.
CITATION_CODE <- "\\b(?:PL|EM|PB|R|O|H|P|C|G)[0-9]{1,2}[a-z]?\\b"   # every family used across both construction-decisions logs

strip_internal_citations <- function(text) {
  one   <- paste0("`?", CITATION_CODE, "`?")
  group <- paste0(one, "(?:\\s*[/,]\\s*", one, ")*")   # "R1", "`H6`", "O1a/O7", "`PB2`/`PB4`"

  # changelog preambles: "**Fixed 2026-07-28 (`R9`):**" / "**Revised 2026-07-29 (`PB2`/`PB4`):**" -- note
  # the colon sits INSIDE the closing "**" in the source ("...):**"), so it is matched before, not after,
  # the trailing \\*{0,2}. "(**revised 2026-07-29, explicit user decision — `PB2`**):" (colon AFTER the
  # closing paren instead) is different-enough bracketing that it is left to a caller's own exact
  # substitution rather than this general pattern.
  text <- gsub(paste0("\\*{0,2}(?:Fixed|Revised|Corrected) \\d{4}-\\d{2}-\\d{2}",
                       "(?:\\s*(?:\u2014|-)\\s*", one, "|\\s*\\(", group, "(?: addendum)?\\))",
                       ":?\\*{0,2}\\s*"),
               "Previously: ", text, perl = TRUE)

  # a bare "(NEW YYYY-MM-DD)" build-date tag, or a ", NEW YYYY-MM-DD" heading suffix
  text <- gsub("\\s?\\(NEW \\d{4}-\\d{2}-\\d{2}\\)", "", text, perl = TRUE)
  text <- gsub(",?\\s*NEW \\d{4}-\\d{2}-\\d{2}", "", text, perl = TRUE)

  # bare pure-citation parens: "(R1)" "(`H6`)" "(O1a/O7)" "(`PB2`/`PB4`)" "(decision `G2`)"
  text <- gsub(paste0("\\s?\\((?:decision )?", group, "\\)"), "", text, perl = TRUE)

  # "(aligns w/ `O3`)"-style asides directly following a stripped/bare code
  text <- gsub("\\s?\\(aligns w/ `?[A-Za-z0-9]+`?\\)", "", text, perl = TRUE)

  # em-dash/hyphen-attached trailing bare citation immediately before a closing paren: "... session — `PB1`)."
  text <- gsub(paste0("\\s?[\u2014-]\\s?", one, "(?=\\))"), "", text, perl = TRUE)

  gsub("[ \t]{2,}", " ", text)
}

# tables whose header's LAST column is "Decision" (docs/data_dictionary_derived.md's convention -- every
# per-field table there ends in a Decision column citing the code(s) behind that field) get that whole
# column dropped: header, divider, and every data row. Safe because it only ever touches the LAST
# pipe-delimited cell of a table confirmed (by hand, against every table in that file) to have one.
strip_decision_column <- function(lines) {
  header_idx <- grep("\\|\\s*Decision\\s*\\|\\s*$", lines)
  in_table <- rep(FALSE, length(lines))
  for (h in header_idx) {
    i <- h
    while (i <= length(lines) && grepl("^\\s*\\|.*\\|\\s*$", lines[i])) {
      in_table[i] <- TRUE
      i <- i + 1
    }
  }
  lines[in_table] <- gsub("\\s*\\|[^|]*\\|\\s*$", "|", lines[in_table], perl = TRUE)
  lines
}

# verification net: called after a page's narrative text is fully assembled (post-sanitize, post-
# PUBLIC_TEXT_SUBS/DICTIONARY_TEXT_SUBS) -- stop()s loud if any citation-code-shaped token survived, rather
# than silently shipping one to the public page (stronger than the "warn but continue" convention used for
# an individual unmatched PUBLIC_TEXT_SUBS pattern, appropriate given how many instances these pages carry).
assert_no_internal_citations <- function(text, page) {
  hits <- regmatches(text, gregexpr(CITATION_CODE, text, perl = TRUE))[[1]]
  if (length(hits)) {
    stop(sprintf("%s: %d internal citation-code token(s) survived sanitization: %s",
                 page, length(hits), paste(unique(hits), collapse = ", ")))
  }
}
