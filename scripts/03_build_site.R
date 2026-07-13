# =========================================================================================================
# scripts/03_build_site.R -- generate the static documentation site (docs/index.html) for GitHub Pages.
#   Standalone: reads every clean asset in data/clean/ and writes one HTML page with a summary table per
#   dataset -- EVERY column shown, styled like the old workbook tables (green categorical / orange
#   date-numeric). GitHub Pages serves docs/index.html directly; no build tool needed.
# =========================================================================================================
library(readr); library(dplyr); library(lubridate)
CLEAN <- here::here("data/clean"); OUT <- here::here("docs/index.html")

# nice titles + display order (any asset not listed still appears, alphabetically, after these)
TITLES <- c(
  inspections = "ICIS-Air Compliance Evaluations (FCE / PCE)", violations = "ICIS-Air Violations",
  formal_actions = "ICIS-Air Formal Actions", informal_actions = "ICIS-Air Informal Actions",
  certs = "ICIS-Air Title V Certifications", stacktests = "ICIS-Air Stack Tests",
  facilities = "ICIS-Air Facilities", pollutants = "ICIS-Air Pollutants", programs = "ICIS-Air Programs",
  program_subparts = "ICIS-Air Program Subparts", afs_actions = "AFS Actions",
  afs_air_program = "AFS Air Program", afs_facilities = "AFS Facilities",
  afs_hist_compliance = "AFS Historical Compliance", afs_hpv = "AFS HPV History",
  emissions = "Combined Emissions Report")

# ---- helpers --------------------------------------------------------------------------------------------
esc   <- function(x) { x <- as.character(x); x <- gsub("&","&amp;",x); x <- gsub("<","&lt;",x); gsub(">","&gt;",x) }
comma <- function(x) formatC(as.numeric(x), format = "d", big.mark = ",")
pm    <- function(x) sprintf("%.1f%%", 100 * mean(is.na(x) | x == ""))
as_dates <- function(x) suppressWarnings(parse_date_time(x, orders = c("mdy","ymd","dmy","Y"), quiet = TRUE))

classify <- function(x, name) {
  if (grepl("date", name, ignore.case = TRUE)) { d <- as_dates(x); if (sum(!is.na(d)) > 0) return("date") }
  num <- suppressWarnings(as.numeric(x)); nn <- !is.na(x) & x != ""
  if (sum(nn) > 0 && mean(!is.na(num[nn])) > 0.95 && dplyr::n_distinct(num, na.rm = TRUE) > 25) return("num")
  "cat"
}
qstat <- function(v) round(suppressWarnings(quantile(v, c(0,.05,.5,.95,1), na.rm = TRUE)))
topv  <- function(x, n, k = 4) {
  x <- x[!is.na(x) & x != ""]; t <- sort(table(x), decreasing = TRUE); m <- min(k, length(t))
  data.frame(val = names(t)[seq_len(m)], n = as.integer(t)[seq_len(m)], pct = as.integer(t)[seq_len(m)] / n)
}

# ---- one dataset section --------------------------------------------------------------------------------
section <- function(asset) {
  d <- read_csv(file.path(CLEAN, paste0(asset, ".csv.gz")),
                col_types = cols(.default = col_character()), show_col_types = FALSE)
  n <- nrow(d); title <- if (asset %in% names(TITLES)) TITLES[[asset]] else asset
  kind <- vapply(names(d), function(c) classify(d[[c]], c), character(1))

  idcol    <- intersect(c("PGM_SYS_ID","PLANT_ID","AFS_ID","REGISTRY_ID"), names(d))[1]
  datecols <- names(d)[kind == "date"]
  yrs <- if (length(datecols)) suppressWarnings(range(unlist(lapply(d[datecols], function(x) year(as_dates(x)))), na.rm = TRUE)) else c(Inf,-Inf)
  dupinfo <- if ("dup" %in% names(d)) sprintf("  &nbsp;|&nbsp;  DISTINCT (dup==0): %s (%.1f%% duplicate rows)",
                comma(sum(d$dup == "0")), 100 * mean(d$dup != "0")) else
             sprintf("  &nbsp;|&nbsp;  EXACT-DUPLICATE ROWS: %s", comma(sum(d$dup_exact == "1")))
  hdr <- paste0(
    "<h2 id='", asset, "'>", esc(title), "</h2>",
    "<p class='meta'>", esc(asset), ".csv.gz &nbsp;|&nbsp; OBSERVATIONS: ", comma(n),
      if (!is.na(idcol)) paste0(" &nbsp;|&nbsp; DISTINCT ", idcol, ": ", comma(dplyr::n_distinct(d[[idcol]]))) else "",
      if (all(is.finite(yrs))) paste0(" &nbsp;|&nbsp; TEMPORAL COVERAGE: ", yrs[1], "&ndash;", yrs[2]) else "",
      dupinfo, "</p>")

  # categorical table (green): every non-date, non-numeric column
  crows <- vapply(names(d)[kind == "cat"], function(c) {
    tv <- topv(d[[c]], n); k <- max(nrow(tv), 1)
    lead <- sprintf("<td rowspan='%d' class='var'>%s</td><td rowspan='%d'>%s</td><td rowspan='%d'>%s</td>",
                    k, esc(c), k, pm(d[[c]]), k, comma(dplyr::n_distinct(d[[c]][!is.na(d[[c]]) & d[[c]] != ""])))
    if (nrow(tv) == 0) return(paste0("<tr>", lead, "<td></td><td></td><td></td></tr>"))
    cells <- sprintf("<td class='l'>%s</td><td>%s</td><td>%s</td>", esc(tv$val), comma(tv$n), sprintf("%.0f%%", 100*tv$pct))
    paste0("<tr>", lead, cells[1], "</tr>", paste0("<tr>", cells[-1], "</tr>", collapse = ""))
  }, character(1))
  cat_tbl <- if (any(kind == "cat")) paste0(
    "<table class='cat'><tr><th>Variable</th><th>% Missing</th><th># Categories</th><th>Frequent Values</th><th>N</th><th>%</th></tr>",
    paste(crows, collapse = ""), "</table>") else ""

  # date / numeric table (orange): year distribution for dates, value distribution for numerics
  onum <- names(d)[kind %in% c("date","num")]
  nrows <- vapply(onum, function(c) {
    v <- if (kind[[c]] == "date") year(as_dates(d[[c]])) else suppressWarnings(as.numeric(d[[c]]))
    s <- qstat(v); lab <- if (kind[[c]] == "date") " (year)" else ""
    sprintf("<tr><td class='var'>%s%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>",
            esc(c), lab, pm(d[[c]]), comma(sum(!is.na(v))), s[1], s[2], s[3], s[4], s[5])
  }, character(1))
  num_tbl <- if (length(onum)) paste0(
    "<table class='num'><tr><th>Variable</th><th>% Missing</th><th>N</th><th>Min</th><th>P5</th><th>Median</th><th>P95</th><th>Max</th></tr>",
    paste(nrows, collapse = ""), "</table>") else ""

  paste0("<section>", hdr, cat_tbl, num_tbl, "</section>")
}

# ---- assemble -------------------------------------------------------------------------------------------
have   <- sub("[.]csv[.]gz$", "", list.files(CLEAN, pattern = "[.]csv[.]gz$"))
assets <- c(intersect(names(TITLES), have), sort(setdiff(have, names(TITLES))))
toc    <- paste0("<a href='#", assets, "'>", vapply(assets, function(a) esc(if (a %in% names(TITLES)) TITLES[[a]] else a), character(1)), "</a>", collapse = "")
body   <- paste(vapply(assets, section, character(1)), collapse = "\n")

css <- "
body{font-family:Calibri,'Segoe UI',system-ui,sans-serif;color:#1f2328;background:#fff;max-width:1100px;margin:0 auto;padding:2rem 1.2rem;}
h1{text-align:center;margin-bottom:.2rem;} .lead{text-align:center;color:#57606a;margin-top:0;}
nav{display:flex;flex-wrap:wrap;gap:.4rem .9rem;justify-content:center;margin:1.4rem 0 2rem;font-weight:bold;}
nav a{color:#0969da;text-decoration:none;} nav a:hover{text-decoration:underline;}
section{margin:2.4rem 0;padding-top:1rem;border-top:1px solid #e5e7eb;}
h2{margin-bottom:.2rem;} .meta{font-weight:bold;margin:.3rem 0 1rem;font-size:.9em;}
table{border-collapse:collapse;width:100%;margin:.6rem 0 1.2rem;font-size:.9em;}
th,td{border:1px solid #9aa0a6;padding:5px 8px;text-align:center;vertical-align:middle;}
td.l{text-align:left;} .var{font-weight:bold;text-align:left;}
table.cat th{background:#C6EFCE;} table.num th{background:#F4B084;}
"
html <- paste0("<!doctype html><html lang='en'><head><meta charset='utf-8'>",
  "<meta name='viewport' content='width=device-width,initial-scale=1'>",
  "<title>CAA Regulatory Data -- Summary Tables</title><style>", css, "</style></head><body>",
  "<h1>CAA Regulatory Data Infrastructure</h1>",
  "<p class='lead'>Summary table for every source. Green = categorical, orange = date / numeric. Every column is shown.</p>",
  "<nav>", toc, "</nav>", body,
  "<p style='text-align:center;color:#8a8f98;margin-top:3rem;font-size:.85em'>Generated by <code>scripts/03_build_site.R</code> from <code>data/clean/</code>.</p>",
  "</body></html>")
writeLines(html, OUT)
cat("wrote", OUT, "(", length(assets), "datasets )\n")
