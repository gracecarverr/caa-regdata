# =========================================================================================================
# code/diagnostics/build_site.R — assemble docs/raw_data.html (the site's "Raw Data" page) from the
#   per-source table scripts in code/diagnostics/tables/. Each tables/<asset>.R defines
#   build_<asset>_section() returning one <section> of HTML, built from data/raw with the same computations
#   + curated content as the old CAA_Project *_table.xlsx workbooks. This script sources them (in display
#   order), converts each section into a doc_nav() sidebar entry + content pane (see to_doc_pane() below),
#   and writes the page under the shared site shell (site_shell.R). GitHub Pages serves docs/ directly; no
#   build tool needed.
#   Reads data/raw directly (independent of cleaning/panels); a documentation step, not a data build.
# =========================================================================================================
library(here)
SRC <- here("code", "diagnostics", "tables")
source(file.path(SRC, "_html.R"))
source(here("code", "diagnostics", "site_shell.R"))

# display order + nav labels
TITLES <- c(
  facilities = "ICIS-Air Facilities", violations = "ICIS-Air Violations",
  inspections = "ICIS-Air Compliance Monitoring", formal_actions = "ICIS-Air Formal Actions",
  informal_actions = "ICIS-Air Informal Actions", certs = "ICIS-Air Title V Certifications",
  stacktests = "ICIS-Air Stack Tests", pollutants = "ICIS-Air Pollutants", programs = "ICIS-Air Programs",
  program_subparts = "ICIS-Air Program Subparts", afs_actions = "AFS Actions",
  afs_air_program = "AFS Air Program", afs_facilities = "AFS Facilities",
  afs_hist_compliance = "AFS Historical Compliance", afs_hpv = "AFS HPV History",
  emissions = "Combined Emissions Report")

order <- names(TITLES)
skip  <- strsplit(Sys.getenv("SKIP_SECTIONS"), ",")[[1]]   # e.g. SKIP_SECTIONS=emissions to omit the 923MB read
order <- setdiff(order, skip)
for (a in order) { f <- file.path(SRC, paste0(a, ".R")); if (file.exists(f)) source(f) }

built <- list()
for (a in order) {
  fn <- paste0("build_", a, "_section")
  if (exists(fn, mode = "function")) {
    message("  building ", a)
    built[[a]] <- get(fn)()
  }
}

# Convert each source's sec(h_head(...), ...) HTML into a doc_nav() section: {id, title, body_html}.
# h_head() always emits the section's one <h2 id='..'>title</h2> immediately after the opening <section> tag
# (verified across all 16 scripts) -- that <h2> is dropped here (not just left in place) because doc_nav()
# renders its own <h2> per pane from `title`; leaving the original in too would duplicate the heading.
to_doc_pane <- function(html) {
  m <- regmatches(html, regexec("^<section><h2 id='([^']*)'>([^<]*)</h2>", html))[[1]]
  if (length(m) < 3) stop("build_site.R: to_doc_pane() couldn't find the expected leading <h2 id='..'> -- a tables/*.R script's output shape may have changed.")
  id <- m[2]; title <- m[3]
  body_html <- sub("^<section><h2 id='[^']*'>[^<]*</h2>", "", html)
  body_html <- sub("</section>$", "", body_html)
  list(id = id, title = title, body_html = body_html)
}
nav_html <- doc_nav(lapply(built, to_doc_pane))

raw_data_body <- paste0(
  "<div class='raw-data'>",
  "<div class='section-note'>Per-source summary tables, computed directly from the raw EPA downloads. ",
  "Navy table headers are categorical (frequent values); burgundy headers are date/numeric distributions. ",
  "For column-by-column field definitions, see the <a href='dictionary.html'>Data Dictionary</a>.</div>",
  nav_html,
  "</div>")

html <- site_shell(
  title       = "Raw Data",
  description = "Per-source summary tables for the raw ICIS-Air, AFS, and emissions downloads: variable coverage, frequent values, and missingness.",
  active      = "raw_data",
  body_html   = paste0(
    hero(
      title   = "Raw Data",
      desc    = paste(
        "Per-source summary tables for all 16 raw ICIS-Air, AFS, and emissions files — variable",
        "coverage, frequent values, and missingness, computed directly from the raw downloads."),
      eyebrow = "Source Files"
    ),
    page_main(raw_data_body)
  )
)

OUT <- here("docs", "raw_data.html")
writeLines(html, OUT)
cat("wrote", OUT, "(", length(built), "of", length(order), "sections )\n")
