# =========================================================================================================
# code/diagnostics/build_panels_page.R -- assembles docs/panels.html, the site's "Panels" page: the
#   narrative brief (briefs/panel/panel_profile.md, used as-is) plus a set of summary-stat tables computed
#   LIVE from output/panel_profile/*.csv (produced by code/diagnostics/18_panel_profile.R). No number on
#   this page is retyped -- every cell below is read from those CSVs and formatted at render time.
#   This replaces the archived build_panels_page.R (archive/panel_building_legacy/diagnostics/), which
#   profiled the OLD three-panel (universe/major_synmin/electric) structure built from data/processed/.
#   This version profiles the two-panel structure (major_synmin_2015_2025, electric_2015_2025) from scratch,
#   matching 18_panel_profile.R's own schema one-for-one -- it is not a revival of the archived script.
#   docs/panels.html had been left un-regenerated since the 2026-07-28 archive (see
#   code/diagnostics/README.md's prior warning); this script ends that gap.
#   Depends on: output/panel_profile/*.csv existing (run `Rscript code/diagnostics/18_panel_profile.R`
#   first -- that script is hand-run, not part of RUN_ALL.R, matching every sibling profile script's own
#   convention; see that script's own header).
#   briefs/panel/panel_profile.md + output/panel_profile/*.csv -> docs/panels.html
# =========================================================================================================
library(here)
library(commonmark)                                                   # renders the narrative brief's markdown (incl. its GFM pipe tables) to HTML
source(here("code", "diagnostics", "tables", "_html.R"))               # esc()/comma()/pct1()/dollar() -- shared formatting primitives used by every page-builder on this site
source(here("code", "diagnostics", "site_shell.R"))                    # hero()/page_main()/site_shell() -- shared chrome + CSS (incl. .stat-table, reused as-is)

PROF <- here("output", "panel_profile")
if (!dir.exists(PROF)) stop("output/panel_profile/ not found -- run code/diagnostics/18_panel_profile.R first.")

# ---- read the profiler's CSVs -- every table below is built ONLY from these, nothing hand-typed -----------
overview   <- read.csv(file.path(PROF, "overview.csv"),              stringsAsFactors = FALSE)
coverage   <- read.csv(file.path(PROF, "coverage_by_year.csv"),      stringsAsFactors = FALSE)
counts     <- read.csv(file.path(PROF, "summary_counts.csv"),        stringsAsFactors = FALSE)
hpv_active <- read.csv(file.path(PROF, "hpv_active_by_year.csv"),    stringsAsFactors = FALSE)
penalty    <- read.csv(file.path(PROF, "penalty_summary.csv"),       stringsAsFactors = FALSE)
freq_cat   <- read.csv(file.path(PROF, "categorical_frequency.csv"), stringsAsFactors = FALSE)
coord_cov  <- read.csv(file.path(PROF, "coordinate_coverage.csv"),   stringsAsFactors = FALSE)
entry_exit <- read.csv(file.path(PROF, "entry_exit_summary.csv"),    stringsAsFactors = FALSE)

# panel key, as it literally appears in every CSV's `panel` column -> the display label used in every table
# header below. Order fixed here (major_synmin first -- the larger, less-restricted panel; electric second,
# its subset) to match 18_panel_profile.R's own PANEL_LEVELS and panel_profile.md's own table order.
PANEL_KEYS   <- c("major_synmin", "electric")
PANEL_LABELS <- c("Major/SynMin", "Electric")

# ---- table-building helpers (same shape as the archived build_panels_page.R, adapted to the new CSVs) ------
dollar_abbrev <- function(x) {                                        # abbreviate large dollar figures -- penalty totals run into the hundreds of millions/billions
  x <- as.numeric(x)
  if (is.na(x)) return("—")
  if (abs(x) >= 1e9) return(sprintf("$%.3fB", x / 1e9))
  if (abs(x) >= 1e6) return(sprintf("$%.1fM", x / 1e6))
  dollar(x)
}
th_row <- function(labels) paste0("<tr>", paste0("<th>", esc(labels), "</th>", collapse = ""), "</tr>")
td_row <- function(cells)  paste0("<tr>", paste0("<td>", esc(cells),  "</td>", collapse = ""), "</tr>")
stat_table <- function(caption, headers, row_html) paste0(
  "<table class='stat-table'><caption>", esc(caption), "</caption>",
  th_row(headers), paste0(row_html, collapse = ""), "</table>")

get_pct <- function(df, panel, variable, lvl) {                       # categorical_frequency.csv lookup: pct for one panel x variable x level cell; 0 if the level never appears for that panel (e.g. a level with 0 facilities)
  v <- df$pct[df$panel == panel & df$variable == variable & df$level == lvl]
  if (length(v) == 0) 0 else v[1]
}
get_mean <- function(panel, measure) {                                # summary_counts.csv's `mean` column for one panel x measure cell
  v <- counts$mean[counts$panel == panel & counts$measure == measure]
  if (length(v) == 0) NA else v[1]
}
get_field <- function(df, panel, col) {                               # generic one-row-per-panel lookup -- overview/penalty/coord_cov/entry_exit each have exactly one row per panel
  v <- df[[col]][df$panel == panel]
  if (length(v) == 0) NA else v[1]
}
top_n_states <- function(panel, n = 5) {                              # top-n states by facility count for one panel, from categorical_frequency's STATE rows (already sorted desc by n at write time, but re-sort defensively)
  d <- freq_cat[freq_cat$panel == panel & freq_cat$variable == "STATE", ]
  d <- d[order(-d$n), ][seq_len(min(n, nrow(d))), ]
  paste0(d$level, " (", pct1(d$pct), ")")
}

# =========================================================================================================
# Table 1 -- panel overview (overview.csv + categorical_frequency.csv's AIR_POLLUTANT_CLASS_DESC rows)
# =========================================================================================================
t1_rows <- c(
  td_row(c("Facilities",            sapply(PANEL_KEYS, function(p) comma(get_field(overview, p, "n_facilities"))))),
  td_row(c("Facility-years (rows)", sapply(PANEL_KEYS, function(p) comma(get_field(overview, p, "n_facility_years"))))),
  td_row(c("Years",                 sapply(PANEL_KEYS, function(p) paste0(get_field(overview, p, "year_min"), "–", get_field(overview, p, "year_max"))))),
  td_row(c("Balanced (= fac. × years)", sapply(PANEL_KEYS, function(p) ifelse(as.logical(get_field(overview, p, "balanced")), "yes", "no")))),
  td_row(c("Class: major",          sapply(PANEL_KEYS, function(p) pct1(get_pct(freq_cat, p, "AIR_POLLUTANT_CLASS_DESC", "Major Emissions"))))),
  td_row(c("Class: synthetic minor", sapply(PANEL_KEYS, function(p) pct1(get_pct(freq_cat, p, "AIR_POLLUTANT_CLASS_DESC", "Synthetic Minor Emissions")))))
)
table1 <- stat_table("Panel overview", c("", PANEL_LABELS), t1_rows)

# =========================================================================================================
# Table 2 -- key outcome measures, mean per ICIS-observed facility-year (summary_counts.csv, all 9 measures)
# =========================================================================================================
measure_labels <- c(N_INSPECTIONS = "Inspections", N_VIOLATIONS = "Violations",
                    N_HPV = "— of which HPV", N_ENFORCEMENT = "Enforcement (pooled)",
                    N_FORMAL = "— Formal", N_INFORMAL = "— Informal",
                    N_CERTS = "Title V certifications", N_STACK_TESTS = "Stack tests",
                    N_PENALTIES = "Penalty actions")
t2_rows <- vapply(names(measure_labels), function(m) {
  cells <- sapply(PANEL_KEYS, function(p) sprintf("%.2f", get_mean(p, m)))
  td_row(c(measure_labels[[m]], cells))
}, character(1))
table2 <- stat_table("Key outcome measures — mean per ICIS-observed facility-year", c("", PANEL_LABELS), t2_rows)

# =========================================================================================================
# Table 3 -- coverage by year: share of facility-years with an actual ICIS event (coverage_by_year.csv)
# =========================================================================================================
years <- sort(unique(coverage$YEAR))
t3_rows <- vapply(years, function(yr) {
  cells <- sapply(PANEL_KEYS, function(p) {
    v <- coverage$pct_event[coverage$panel == p & coverage$YEAR == yr]
    if (length(v) == 0) "—" else pct1(v[1])
  })
  td_row(c(as.character(yr), cells))
}, character(1))
table3 <- stat_table("Coverage by year — share of facility-years with an ICIS event", c("Year", PANEL_LABELS), t3_rows)
table3_note <- paste(
  "\"Share with an ICIS event\" = OBS_SOURCE == \"event\". The remainder splits between OBS_SOURCE ==",
  "\"operating\" (no ICIS event that year, but confirmed active another way) and \"unobserved\" (no",
  "confirmed activity that year — expected here, since each panel only requires a facility to be active",
  "in at least one of its 11 years, not every year).")

# =========================================================================================================
# Table 4 -- HPV-active rate by year (hpv_active_by_year.csv; H6 zero-vs-NA discipline)
# =========================================================================================================
t4_rows <- vapply(years, function(yr) {
  cells <- sapply(PANEL_KEYS, function(p) {
    v <- hpv_active$pct_active[hpv_active$panel == p & hpv_active$YEAR == yr]
    if (length(v) == 0) "—" else pct1(v[1])
  })
  td_row(c(as.character(yr), cells))
}, character(1))
table4 <- stat_table("HPV-active rate by year", c("Year", PANEL_LABELS), t4_rows)

# =========================================================================================================
# Table 5 -- penalties (penalty_summary.csv; NA-if-none-or-exactly-$0, per data/panels/README.md)
# =========================================================================================================
t5_rows <- c(
  td_row(c("Facility-years w/ penalty", sapply(PANEL_KEYS, function(p) comma(get_field(penalty, p, "n_nonna"))))),
  td_row(c("Facility-years, NA share",  sapply(PANEL_KEYS, function(p) pct1(get_field(penalty, p, "pct_na"))))),
  td_row(c("Median",                    sapply(PANEL_KEYS, function(p) dollar(get_field(penalty, p, "median"))))),
  td_row(c("P95",                       sapply(PANEL_KEYS, function(p) dollar_abbrev(get_field(penalty, p, "p95"))))),
  td_row(c("Max",                       sapply(PANEL_KEYS, function(p) dollar_abbrev(get_field(penalty, p, "max"))))),
  td_row(c("Mean",                      sapply(PANEL_KEYS, function(p) dollar(get_field(penalty, p, "mean"))))),
  td_row(c("Total",                     sapply(PANEL_KEYS, function(p) dollar_abbrev(get_field(penalty, p, "total")))))
)
table5 <- stat_table("Penalties — PENALTY_AMOUNT, non-NA facility-years", c("", PANEL_LABELS), t5_rows)
table5_note <- paste(
  "Penalty amounts show NA if no formal action occurred that facility-year, or if it summed to exactly $0",
  "(a documented, unresolved ambiguity in the underlying data); totals are naive -- no duplicate-row or",
  "multi-facility-settlement correction has been applied.")

# =========================================================================================================
# Table 6 -- coordinate coverage & geocoding quality (coordinate_coverage.csv, facility-level)
# =========================================================================================================
t6_rows <- c(
  td_row(c("Has coordinate",                    sapply(PANEL_KEYS, function(p) pct1(get_field(coord_cov, p, "pct_has_coordinate"))))),
  td_row(c("Gross error (of evaluable)",        sapply(PANEL_KEYS, function(p) pct1(get_field(coord_cov, p, "pct_gross_error"))))),
  td_row(c("Coord.-to-county distance, median",  sapply(PANEL_KEYS, function(p) sprintf("%.1f km", get_field(coord_cov, p, "dist_median_km"))))),
  td_row(c("Coord.-to-county distance, p95",     sapply(PANEL_KEYS, function(p) sprintf("%.1f km", get_field(coord_cov, p, "dist_p95_km"))))),
  td_row(c("Coord.-to-county distance, max",     sapply(PANEL_KEYS, function(p) sprintf("%.1f km", get_field(coord_cov, p, "dist_max_km")))))
)
table6 <- stat_table("Coordinate coverage & geocoding quality (facility-level)", c("", PANEL_LABELS), t6_rows)

# =========================================================================================================
# Table 7 -- entry/exit (entry_exit_summary.csv, facility-level). These fields are wayback's own entry/exit
#   spell record (facility-level, broadcast across all 11 rows) -- not a claim that every facility here is
#   active every year within the window (that's no longer guaranteed under the >=1-year eligibility rule;
#   see Table 3's note for within-window coverage instead).
# =========================================================================================================
t7_rows <- c(
  td_row(c("Confirmed exited",                     sapply(PANEL_KEYS, function(p) pct1(get_field(entry_exit, p, "pct_exited"))))),
  td_row(c("Entered-year, median",                 sapply(PANEL_KEYS, function(p) as.character(get_field(entry_exit, p, "entered_year_median")))))
)
table7 <- stat_table("Entry/exit (facility-level)", c("", PANEL_LABELS), t7_rows)

# =========================================================================================================
# Table 8 -- top 5 states by facility count (categorical_frequency.csv, variable == "STATE", per panel --
#   each panel ranked by its OWN top states, unlike panel_profile.md's Figure 5 which orders electric's bars
#   by major_synmin's ranking for direct visual comparison; this table has no such constraint)
# =========================================================================================================
n_top <- 5
t8_rows <- vapply(seq_len(n_top), function(i) td_row(c(
  as.character(i), sapply(PANEL_KEYS, function(p) top_n_states(p)[i])
)), character(1))
table8 <- stat_table("Top 5 states by facility count", c("Rank", PANEL_LABELS), t8_rows)

# ---- narrative: briefs/panel/panel_profile.md (front-matter dropped + internal citations rewritten for a
#   public audience below; hero supplies the page title) ----------------------------------------------------
md_lines <- enc2utf8(readLines(here("briefs", "panel", "panel_profile.md"), warn = FALSE, encoding = "UTF-8"))
while (length(md_lines) && !nzchar(trimws(md_lines[1]))) md_lines <- md_lines[-1]  # drop leading blank lines
if (length(md_lines) && grepl("^# ", md_lines[1])) md_lines <- md_lines[-1]        # drop the H1 -- hero() already supplies the page title

# drop the brief's own front-matter: two italic paragraphs of internal reproducibility bookkeeping (which
# script/CSVs/figures this traces to, when it was last regenerated) followed by a "---" rule -- internal-
# audience framing, not for a public page, same rationale/technique as build_home.R's front-matter strips
hr <- grep("^---$", md_lines)
if (length(hr)) md_lines <- md_lines[-seq_len(hr[1])]
while (length(md_lines) && !nzchar(trimws(md_lines[1]))) md_lines <- md_lines[-1]  # drop the blank line(s) left behind

# Replace internal file/script/dataset-identifier citations embedded in the brief's own analytical prose
# with plain-English equivalents, for a public audience. Done here at render time (NOT by hand-editing the
# source brief) so briefs/panel/panel_profile.md itself keeps its full traceability for a researcher
# returning to the project cold -- only the public HTML gets the citation-free wording. Each pattern is
# copied verbatim from the brief's current (2026-07-28) text; \\s+ stands in for the brief's own line-wrap
# points (a soft wrap in the source is just a space once rendered). If the brief's wording changes later,
# a pattern will simply stop matching (silently leaving that one citation in place) rather than mangling
# unrelated text -- the warning below catches that case so it doesn't go unnoticed.
narrative_text <- paste(md_lines, collapse = "\n")
PUBLIC_TEXT_SUBS <- list(
  list(pat = "\\| `major_synmin_2015_2025` \\|", rep = "| Major/Synthetic Minor |"),
  list(pat = "\\| `electric_2015_2025` \\|", rep = "| Electric |"),
  list(pat = paste0("`panel_facility_count_over_time\\.png`\\s+still\\s+shows\\s+flat\\s+lines\\s+across\\s+",
                     "2015–2025\\s+for\\s+both\\s+panels\\s+—"),
       rep = "Facility counts are flat lines across 2015–2025 for both panels,"),
  list(pat = paste0("—\\s+the same zero-vs-NA gate as the dataset layer\\s+",
                     "\\(`13_regulatory_profile\\.R`\\)\\."),
       rep = "— the same zero-vs-NA gate used at the dataset layer."),
  list(pat = paste0("`panel_count_distributions\\.png`\\s+shows\\s+the\\s+full\\s+ECDFs\\s+side\\s+by\\s+side\\s+",
                     "\\(pseudo-log x-axis\\)\\."),
       rep = "The full distributions (pseudo-log x-axis) show each panel's count-measure spread side by side."),
  list(pat = paste0("matches\\s+`hpv_profile\\.md`'s\\s+Figure\\s+1\\s+at\\s+the\\s+dataset\\s+layer\\."),
       rep = "matches the pattern already documented at the dataset layer."),
  list(pat = "carried over unchanged from\\s+`data/panels/README\\.md`\\)\\.",
       rep = "carried over unchanged from the underlying panel data)."),
  list(pat = "same caveat as\\s+`12_penalties_profile\\.R`'s\\s+`by_year\\.csv`\\);",
       rep = "same caveat noted at the dataset layer);"),
  list(pat = paste0("`panel_penalty_dist\\.png`\\s+shows\\s+both\\s+distributions\\s+on\\s+a\\s+shared\\s+",
                     "log10\\s+axis,\\s+faceted\\s+by\\s+panel\\."),
       rep = "Both distributions sit on a shared log10 axis when faceted by panel."),
  list(pat = paste0("`panel_state_composition\\.png`\\s+plots\\s+the\\s+top\\s+10\\s+states\\s+",
                     "\\(major_synmin's\\s+ranking,\\s+both\\s+panels'\\s+bars\\)\\s+for\\s+a\\s+direct\\s+visual\\s+",
                     "comparison\\s+—\\s+see\\s+the\\s+figure's\\s+own\\s+caveat\\s+",
                     "\\(\u00a7\\s+FLAGGED\\s+ISSUES\\s+in\\s+the\\s+script\\)\\s+that\\s+electric's"),
       rep = "The top 10 states (ranked by major_synmin, both panels shown) give a direct visual comparison — note that electric's"),
  list(pat = paste0("the\\s+full-universe\\s+dataset-4\\s+coordinate\\s+coverage\\s+rate\\s+",
                     "\\(84\\.5%,\\s+`coordinates_\\s*profile\\.md`\\)"),
       rep = "the full-universe coordinate coverage rate (84.5%)"),
  list(pat = "`code/04_panel_building/README\\.md`\\s+documents electric as major_synmin's filter",
       rep = "Electric is defined as major_synmin's filter"),
  list(pat = paste0("same caveat as the dataset-layer\\s+",
                     "`penalties_profile\\.md`/`multi_facility_settlement_decision\\.md`\\."),
       rep = "same caveat noted at the dataset layer.")
)
for (s in PUBLIC_TEXT_SUBS) {
  if (!grepl(s$pat, narrative_text, perl = TRUE)) {
    warning(sprintf("build_panels_page.R: public-text substitution pattern did not match (brief text may have changed) -- pattern: %s", s$pat))
  }
  narrative_text <- gsub(s$pat, s$rep, narrative_text, perl = TRUE)
}
md_lines <- strsplit(narrative_text, "\n")[[1]]

narrative_html <- commonmark::markdown_html(paste(md_lines, collapse = "\n"), extensions = TRUE)  # extensions=TRUE for GFM pipe tables (panel_profile.md has several)

body <- paste0(
  hero(
    title   = "Panels",
    desc    = paste(
      "Two facility × year panels for empirical work on enforcement and compliance, both spanning",
      "2015–2025 and screened to facilities active in at least one year of the window: a broad",
      "Major / Synthetic Minor panel and a narrower Electric utilities subset. Construction decisions,",
      "coverage, and summary statistics below."),
    eyebrow = "Facility × Year Panels"
  ),
  page_main(
    "<div class='prose'>",
    narrative_html,
    "<h2>Summary-Statistics Tables</h2>",
    "<p class='table-note'>Every figure below is computed directly from the underlying panel data — ",
    "nothing here is hand-entered.</p>",
    table1,
    table2,
    table3,
    "<p class='table-note'>", table3_note, "</p>",
    table4,
    table5,
    "<p class='table-note'>", table5_note, "</p>",
    table6,
    table7,
    table8,
    "</div>"
  )
)

html <- site_shell(
  title       = "Panels",
  description = "Facility x year panel construction and summary statistics for the CAA regulatory data: a broad Major/Synthetic Minor panel and a narrower Electric utilities subset, 2015-2025.",
  active      = "panels",
  body_html   = body
)

OUT <- here("docs", "panels.html")
writeLines(html, OUT, useBytes = TRUE)
cat("wrote", OUT, "\n")

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# 1. panel_comparison.csv (the electric-is-a-subset-of-major_synmin check) is NOT given its own table here --
#    it's a single fact (already stated in panel_profile.md's narrative, section 9), and a one-row table
#    seemed like needless duplication rather than a genuine summary. If a future reader wants it as its own
#    stat-table (e.g. to make it more skimmable without reading prose), it's a straightforward addition.
# 2. Table 3 ("Coverage by year") shows only pct_event, not pct_operating -- deliberate, since pct_unobserved
#    is always exactly 0 in these continuity-screened panels (PB4), so pct_operating = 1 - pct_event and a
#    second column would be redundant. This differs from the archived (three-panel) build_panels_page.R,
#    where a genuine, non-complementary "% observed" distinction existed for the universe panel.
# 3. Table 6's coordinate distances are shown in plain "%.1f km" rather than an abbreviated form -- no
#    distance-abbreviation convention exists elsewhere on this site (unlike dollar_abbrev() for penalties),
#    and the values here (0 to ~1,618 km) don't need one.
# 4. Table 8 ranks each panel by its OWN top-5 states independently -- this differs from panel_profile.md's
#    Figure 5 (output/figures/panels/panel_state_composition.png), which deliberately orders electric's bars
#    by major_synmin's top-10 ranking for a direct side-by-side visual comparison. Both are valid views of
#    the same categorical_frequency.csv; readers comparing this table to that figure should expect the
#    electric column here to surface some states the figure doesn't show (e.g. CA ranks #1 for electric by
#    its own count, and does appear in major_synmin's top 10 too, but a state high in electric's own ranking
#    that fell outside major_synmin's top 10 would show up here and not there).
# 5. (PUBLIC_TEXT_SUBS) The public-audience text substitutions applied to the narrative are matched against
#    an exact, hand-copied snapshot of panel_profile.md's current wording -- a future edit to that brief can
#    make a pattern stop matching. This fails SAFE (the one un-matched citation stays in the rendered page,
#    everything else still renders) and fails LOUD (a warning() names the exact pattern that didn't match),
#    but it does mean this list needs a human review pass whenever panel_profile.md's prose changes, not just
#    when its numbers do.
