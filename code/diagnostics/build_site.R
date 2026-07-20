# =========================================================================================================
# code/diagnostics/build_site.R — assemble docs/raw_data.html (the site's "Raw Data" page) from the
#   per-source table scripts in code/diagnostics/tables/. Each tables/<asset>.R defines
#   build_<asset>_section() returning one <section> of HTML, built from data/raw with the same computations
#   + curated content as the old CAA_Project *_table.xlsx workbooks. This script sources them (in display
#   order), concatenates the sections, and writes the page under the shared site shell (site_shell.R).
#   GitHub Pages serves docs/ directly; no build tool needed.
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

toc  <- paste0("<a href='#", names(built), "'>", esc(unname(TITLES[names(built)])), "</a>", collapse = "")
body <- paste(unlist(built), collapse = "\n")

raw_data_body <- paste0(
  "<div class='raw-data'>",
  "<h1>CAA Regulatory Data Infrastructure</h1>",
  "<p class='lead'>Per-source summary tables, computed directly from <code>data/raw/</code>. ",
  "Green = categorical (frequent values); orange = date / numeric distributions.</p>",
  "<nav class='section-toc'>", toc, "</nav>", body,
  "</div>")

html <- site_shell(
  title       = "Raw Data",
  description = "Per-source summary tables for the raw ICIS-Air, AFS, and emissions downloads: variable coverage, frequent values, and missingness.",
  active      = "raw_data",
  body_html   = page_main(raw_data_body),
  script      = "code/diagnostics/build_site.R"
)

OUT <- here("docs", "raw_data.html")
writeLines(html, OUT)
cat("wrote", OUT, "(", length(built), "of", length(order), "sections )\n")
