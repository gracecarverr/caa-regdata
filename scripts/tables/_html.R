# =========================================================================================================
# scripts/tables/_html.R — HTML rendering primitives for the summary-table site (docs/index.html).
# These mirror the openxlsx primitives used by the old CAA_Project table-*.R workbooks so that each
# ported table script keeps its stat code + curated content verbatim and only swaps the output layer:
#   - green categorical table (#C6EFCE header) with merged Variable/%Missing/#Categories cells (rowspan)
#   - orange date/numeric table (#F4B084 header)
#   - header block, free-text/footnote notes, and a duplicates section.
# Each ported script returns one <section> string; scripts/03_build_site.R assembles the page.
# =========================================================================================================

esc   <- function(x) { x <- as.character(x); x <- gsub("&", "&amp;", x); x <- gsub("<", "&lt;", x); gsub(">", "&gt;", x) }
comma  <- function(x) formatC(round(as.numeric(x)), format = "d", big.mark = ",")  # matches numFmt "#,##0"
pct1   <- function(fr) sprintf("%.1f%%", 100 * as.numeric(fr))   # matches the old cell_pct numFmt "0.0%"
dollar <- function(x) paste0("$", formatC(round(as.numeric(x)), format = "d", big.mark = ","))  # numFmt "$#,##0"

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
