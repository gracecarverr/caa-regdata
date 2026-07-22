# =========================================================================================================
# code/diagnostics/build_panels_page.R \u2014 assembles docs/panels.html, the site's "Panels" page: the
#   findings-summary narrative (briefs/panel/panel_findings_summary.md, used as-is) plus a set of summary-stat
#   tables computed live from output/panel_profile/*.csv (produced by the hand-run 06_panel_profile.R \u2014
#   NOT part of RUN_ALL.R, matching that script's own convention). No number here is retyped; every cell is
#   read from the CSVs and formatted at render time.
#   Depends on: output/panel_profile/*.csv existing (run `Rscript code/diagnostics/06_panel_profile.R` first).
#   briefs/panel/panel_findings_summary.md + output/panel_profile/*.csv -> docs/panels.html
# =========================================================================================================
library(here)
library(commonmark)
source(here("code", "diagnostics", "tables", "_html.R"))
source(here("code", "diagnostics", "site_shell.R"))

PROF <- here("output", "panel_profile")
if (!dir.exists(PROF)) stop("output/panel_profile/ not found -- run code/diagnostics/06_panel_profile.R first.")

overview   <- read.csv(file.path(PROF, "panel_overview.csv"),      stringsAsFactors = FALSE)
freq_cat   <- read.csv(file.path(PROF, "freq_categorical.csv"),    stringsAsFactors = FALSE)
counts     <- read.csv(file.path(PROF, "summary_counts.csv"),      stringsAsFactors = FALSE)
dup        <- read.csv(file.path(PROF, "summary_duplication.csv"), stringsAsFactors = FALSE)
penalty    <- read.csv(file.path(PROF, "summary_penalty.csv"),     stringsAsFactors = FALSE)
coverage   <- read.csv(file.path(PROF, "coverage_by_year.csv"),    stringsAsFactors = FALSE)
electric_a <- read.csv(file.path(PROF, "electric_attainment.csv"), stringsAsFactors = FALSE)
states     <- read.csv(file.path(PROF, "state_counts.csv"),        stringsAsFactors = FALSE)

PANELS <- c("Universe", "Major/SynMin", "Electric")

# ---- table-building helpers ------------------------------------------------------------------------------
dollar_abbrev <- function(x) {
  x <- as.numeric(x)
  if (is.na(x)) return("\u2014")
  if (abs(x) >= 1e9) return(sprintf("$%.3fB", x / 1e9))
  if (abs(x) >= 1e6) return(sprintf("$%.1fM", x / 1e6))
  dollar(x)
}
pct_or_dash <- function(x) if (is.na(x) || !nzchar(trimws(x))) "\u2014" else pct1(x)

th_row <- function(labels) paste0("<tr>", paste0("<th>", esc(labels), "</th>", collapse = ""), "</tr>")
td_row <- function(cells)  paste0("<tr>", paste0("<td>", esc(cells),  "</td>", collapse = ""), "</tr>")
stat_table <- function(caption, headers, row_html) paste0(
  "<table class='stat-table'><caption>", esc(caption), "</caption>",
  th_row(headers), paste0(row_html, collapse = ""), "</table>")

get_pct <- function(df, panel, variable, level) {
  v <- df$pct[df$panel == panel & df$variable == variable & df$level == level]
  if (length(v) == 0) 0 else v[1]
}
get_stat <- function(df, panel, measure, col) {
  v <- df[[col]][df$panel == panel & df$measure == measure]
  if (length(v) == 0) NA else v[1]
}
get_cov <- function(panel, yr, col) {
  v <- coverage[[col]][coverage$panel == panel & coverage$year == yr]
  if (length(v) == 0) NA else v[1]
}

# ---- Table 1: panel overview ------------------------------------------------------------------------------
ov_row <- function(label, values) td_row(c(label, values))
t1_rows <- c(
  ov_row("Facilities",               sapply(PANELS, function(p) comma(overview$n_facilities[overview$panel == p]))),
  ov_row("Facility-years (rows)",    sapply(PANELS, function(p) comma(overview$n_facility_years[overview$panel == p]))),
  ov_row("Years",                    sapply(PANELS, function(p) paste0(overview$year_min[overview$panel == p], "\u2013", overview$year_max[overview$panel == p]))),
  ov_row("Balanced (= fac. \u00D7 years)", sapply(PANELS, function(p) ifelse(overview$balanced[overview$panel == p], "yes", "no"))),
  ov_row("obs_source: event",        sapply(PANELS, function(p) pct1(overview$share_event[overview$panel == p]))),
  ov_row("obs_source: operating",    sapply(PANELS, function(p) pct1(overview$share_operating[overview$panel == p]))),
  ov_row("obs_source: unobserved",   sapply(PANELS, function(p) pct1(overview$share_unobserved[overview$panel == p]))),
  ov_row("Class: major",             sapply(PANELS, function(p) pct1(get_pct(freq_cat, p, "AIR_POLLUTANT_CLASS_DESC", "Major Emissions")))),
  ov_row("Class: synthetic minor",   sapply(PANELS, function(p) pct1(get_pct(freq_cat, p, "AIR_POLLUTANT_CLASS_DESC", "Synthetic Minor Emissions")))),
  ov_row("Class: minor",             sapply(PANELS, function(p) pct1(get_pct(freq_cat, p, "AIR_POLLUTANT_CLASS_DESC", "Minor Emissions")))),
  ov_row("Class: other / missing",   sapply(PANELS, function(p) {
    maj <- get_pct(freq_cat, p, "AIR_POLLUTANT_CLASS_DESC", "Major Emissions")
    sm  <- get_pct(freq_cat, p, "AIR_POLLUTANT_CLASS_DESC", "Synthetic Minor Emissions")
    mn  <- get_pct(freq_cat, p, "AIR_POLLUTANT_CLASS_DESC", "Minor Emissions")
    pct1(max(0, 1 - maj - sm - mn))
  }))
)
table1 <- stat_table("Panel overview", c("", PANELS), t1_rows)

# ---- Table 2: key outcome measures (mean per observed facility-year) --------------------------------------
measure_labels <- c(n_inspections = "Inspections", n_violations = "Violations",
                     n_enforcement = "Enforcement actions", n_certs = "Title V certifications",
                     n_stack_tests = "Stack tests")
t2_rows <- vapply(names(measure_labels), function(m) {
  cells <- sapply(PANELS, function(p) {
    mean_v <- get_stat(counts, p, m, "mean")
    sprintf("%.2f", mean_v)
  })
  td_row(c(measure_labels[[m]], cells))
}, character(1))
table2 <- stat_table("Key outcome measures \u2014 mean per observed facility-year",
                      c("", PANELS), t2_rows)

# ---- Table 3: duplicate load (share of rows that are event-key duplicates) --------------------------------
family_labels <- c(certs = "Title V certifications", informal = "Informal enforcement",
                    enforcement = "Enforcement (pooled)", formal = "Formal enforcement",
                    inspections = "Inspections")
t3_rows <- vapply(names(family_labels), function(fam) {
  cells <- sapply(PANELS, function(p) {
    v <- dup$dup_share[dup$panel == p & dup$family == fam]
    if (length(v) == 0) "\u2014" else pct1(v[1])
  })
  td_row(c(family_labels[[fam]], cells))
}, character(1))
table3 <- stat_table("Duplicate load \u2014 share of raw rows that are event-key duplicates (not deduped in the panel)",
                      c("", PANELS), t3_rows)

# ---- Table 4: penalties -----------------------------------------------------------------------------------
t4_rows <- c(
  td_row(c("Facility-years w/ penalty", sapply(PANELS, function(p) comma(penalty$n_nonzero[penalty$panel == p])))),
  td_row(c("Total",                     sapply(PANELS, function(p) dollar_abbrev(penalty$total[penalty$panel == p])))),
  td_row(c("Mean",                      sapply(PANELS, function(p) dollar(penalty$mean[penalty$panel == p])))),
  td_row(c("Max",                       sapply(PANELS, function(p) dollar_abbrev(penalty$max[penalty$panel == p])))),
  td_row(c("Duplicate $ (share of total)", sapply(PANELS, function(p) paste0(
    dollar_abbrev(penalty$dup_total[penalty$panel == p]), " (", pct1(penalty$dup_share[penalty$panel == p]), ")"))))
)
table4 <- stat_table("Penalties \u2014 formal actions only", c("", PANELS), t4_rows)

# ---- Table 5: operating status & observation coverage by year, 2005-2025 ----------------------------------
years <- sort(unique(coverage$year))
t5_rows <- vapply(years, function(yr) {
  op  <- sapply(PANELS, function(p) pct_or_dash(get_cov(p, yr, "pct_operating")))
  obs <- sapply(PANELS, function(p) { v <- get_cov(p, yr, "pct_observed"); if (is.na(v)) "\u2014" else pct1(v) })
  td_row(c(as.character(yr), op, obs))
}, character(1))
table5 <- stat_table(
  "Operating status & observation coverage by year",
  c("Year", paste(PANELS, "\u2014 operating share"), paste(PANELS, "\u2014 % observed")),
  t5_rows)
table5_note <- paste(
  "\"Operating share\" = share of facilities in wayback-confirmed operating status that year (2015\u20132025",
  "only \u2014 no wayback snapshot exists pre-2015). \"% observed\" = share of facility-years that are not",
  "obs_source == unobserved (i.e. an event landed, or \u2014 2015\u20132025 only \u2014 the facility was",
  "confirmed operating), available across the full 2005\u20132025 window.")

# ---- Table 6: electric panel PM2.5 (2012) nonattainment exposure, 2016-2025 --------------------------------
ea <- setNames(electric_a$value, electric_a$item)
t6_rows <- c(
  td_row(c("Facilities ever in a PM2.5 nonattainment area", comma(ea[["facilities_ever_nonattainment"]]))),
  td_row(c("  as % of electric facilities", pct1(as.numeric(ea[["share_electric_facilities"]])))),
  td_row(c("Facility-years in nonattainment (any_naa = 1)", comma(ea[["facility_years_nonattainment"]]))),
  td_row(c("Facility-years in attainment (any_naa = 0)", comma(ea[["facility_years_attainment"]]))),
  td_row(c("Facility-years NA (pre-2016 or unplaced)", comma(ea[["facility_years_na"]])))
)
table6 <- stat_table("Electric panel: PM2.5 (2012 NAAQS) nonattainment exposure, 2016\u20132025",
                      c("", "Value"), t6_rows)

area_rows <- grep("^area:", names(ea), value = TRUE)
t6b_rows <- vapply(area_rows, function(k) td_row(c(sub("^area:", "", k), comma(ea[[k]]))), character(1))
table6b <- stat_table("Top nonattainment areas by electric facility-years", c("Area", "Facility-years"), t6b_rows)

# ---- Table 7: top states by facility count (bonus) ---------------------------------------------------------
top_states <- function(panel, n = 5) {
  d <- states[states$panel == panel, ]
  d <- d[order(-d$n_facilities), ][seq_len(min(n, nrow(d))), ]
  paste0(d$STATE, " (", comma(d$n_facilities), ")")
}
n_top <- 5
t7_rows <- vapply(seq_len(n_top), function(i) td_row(c(
  as.character(i), top_states("Universe")[i], top_states("Major/SynMin")[i], top_states("Electric")[i]
)), character(1))
table7 <- stat_table("Top 5 states by facility count", c("Rank", PANELS), t7_rows)

# ---- narrative: briefs/panel/panel_findings_summary.md (used as-is; hero supplies the page title) ----------------
md_lines <- enc2utf8(readLines(here("briefs", "panel_findings_summary.md"), warn = FALSE, encoding = "UTF-8"))
while (length(md_lines) && !nzchar(trimws(md_lines[1]))) md_lines <- md_lines[-1]
if (length(md_lines) && grepl("^# ", md_lines[1])) md_lines <- md_lines[-1]
narrative_html <- commonmark::markdown_html(paste(md_lines, collapse = "\n"), extensions = TRUE)

body <- paste0(
  hero(
    title   = "Panels",
    desc    = paste(
      "Facility \u00D7 year panels built for empirical work on enforcement and compliance: construction",
      "decisions, coverage, and summary statistics across the Universe, Major/Synthetic Minor, and",
      "Electric panels."),
    eyebrow = "Facility \u00D7 Year Panels"
  ),
  page_main(
    "<div class='prose'>",
    narrative_html,
    "<h2>Summary-Statistics Tables</h2>",
    "<p class='table-note'>Computed live from <code>output/panel_profile/*.csv</code> ",
    "(<code>code/diagnostics/06_panel_profile.R</code>) \u2014 every cell below is read from those files, not ",
    "retyped.</p>",
    table1,
    table2,
    table3,
    table4,
    table5,
    "<p class='table-note'>", table5_note, "</p>",
    table6,
    table6b,
    table7,
    "</div>"
  )
)

html <- site_shell(
  title       = "Panels",
  description = "Facility x year panel construction and summary statistics for the CAA regulatory data: Universe, Major/Synthetic Minor, and Electric panels.",
  active      = "panels",
  body_html   = body,
  script      = "code/diagnostics/build_panels_page.R"
)

OUT <- here("docs", "panels.html")
writeLines(html, OUT, useBytes = TRUE)
cat("wrote", OUT, "\n")
