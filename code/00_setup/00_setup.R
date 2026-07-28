# =========================================================================================================
# 00_setup.R -- environment setup for the pipeline. Sourced first by code/RUN_ALL.R (and safe to source at
#   the top of any stage you run on its own). Does NOT touch data.
#
#   Responsibilities:
#     1. verify the R packages the pipeline needs are installed (fail early with a clear message)
#     2. set deterministic, quiet global options
#     3. record the session (package versions) to output/ for reproducibility
#
#   The pipeline pins packages with renv (see renv.lock); this script only *checks* and reports.
# =========================================================================================================

# ---- 1. required packages ------------------------------------------------------------------------------
# Everything sourced anywhere in code/ (cleaning, spine, panels, diagnostics).
REQUIRED_PKGS <- c(                # master list this script checks for; NOT attached via library() here --
  "here",       # project-root-relative paths          -- each downstream script does its own library() calls
  "readr",      # CSV read/write                       -- (see e.g. code/03_panel_building/03_build.R:12),
  "dplyr",      # data manipulation                     -- so this list is a preflight inventory, not a
  "tidyr",      # reshaping (pivot/expand_grid)          -- shared attach step. REVIEW(design): this list is
  "lubridate",  # date parsing                          -- maintained by hand and can silently drift out of
  "data.table", # fast grouped ops (wayback LOCF, panel summaries) -- sync with what scripts actually
  "sf",         # spatial join (facility coordinate -> county)      -- library() -- nothing fails loudly if a
  "ggplot2",    # figures (diagnostics/06_panel_profile) -- script starts using a new package here without
  "scales",     # axis label formatting for figures      -- also adding it to REQUIRED_PKGS; it would only
  "R.utils"     # lets data.table::fread() read .csv.gz directly (diagnostics/06_, 11_) -- surface downstream
)                                   # as a runtime "could not find function" error in whatever script uses it.

# R.utils is never library()'d or ::'d directly anywhere (it's an internal dependency data.table::fread()
# uses to read .csv.gz), so renv's static "implicit" snapshot scan (renv/settings.json) can't discover it
# from REQUIRED_PKGS alone -- this literal call exists purely so `renv::snapshot()` finds and pins it.
invisible(requireNamespace("R.utils", quietly = TRUE))  # loads the namespace as a side effect purely to give
                                                          # renv's dependency scanner something to detect; the
                                                          # return value (TRUE/FALSE) is deliberately discarded

# check each required package is installed (does NOT attach/library() it -- just confirms availability);
# vapply returns a logical(1) per package, negated so TRUE means "missing"
missing_pkgs <- REQUIRED_PKGS[!vapply(REQUIRED_PKGS, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs)) {                        # fail fast with an actionable message rather than letting
  stop("Missing required package(s): ", paste(missing_pkgs, collapse = ", "),  # a downstream script die later
       "\n  Install with renv::restore() (preferred, uses the pinned versions) or ",  # with a cryptic
       "install.packages(c(", paste(sprintf('\"%s\"', missing_pkgs), collapse = ", "), ")).",  # "could not
       call. = FALSE)                              # find function" error far from the real cause
}

# ---- 2. deterministic / quiet options ------------------------------------------------------------------
options(
  readr.show_col_types = FALSE,   # never guess-and-warn about column types (we read raw as character)
  stringsAsFactors     = FALSE,   # legacy option (default FALSE since R 4.0 anyway) -- explicit for clarity
                                   # on any R version / for readers unfamiliar with the 4.0 default change
  scipen               = 999      # no scientific notation in written IDs/counts
)
# The pipeline has no stochastic step (point-in-polygon and dup flagging are deterministic), so no seed is
# required. If you add sampling/bootstrapping, set a seed explicitly in that script (project rule).

# ---- 3. record the session for reproducibility ---------------------------------------------------------
local({                                                    # local() so `out` doesn't leak into the caller's
  out <- here::here("output")                              # global env -- output/ dir, project-root-relative
  dir.create(out, showWarnings = FALSE, recursive = TRUE)  # create if absent; silent if it already exists
  writeLines(capture.output(sessionInfo()), file.path(out, "sessionInfo.txt"))  # dump R version + attached/
})                                                          # loaded package versions to a plain-text file --
                                                             # REVIEW(design): this OVERWRITES on every run
                                                             # with no timestamp or run ID in the filename, so
                                                             # it only ever reflects the *last* run's session,
                                                             # not a per-run provenance trail (unlike MANIFEST.csv
                                                             # in 01_download.R, which appends one row per file)

cat("00_setup: environment OK (", length(REQUIRED_PKGS), " packages present); session recorded to output/sessionInfo.txt\n", sep = "")
# final confirmation line -- note the count reflects length(REQUIRED_PKGS), i.e. "all packages we checked for",
# not "all packages actually used by the pipeline" (see REVIEW(design) above on possible drift between the two)
