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
# Everything sourced anywhere in code/ (cleaning, spine, attainment, panels, diagnostics).
REQUIRED_PKGS <- c(
  "here",       # project-root-relative paths
  "readr",      # CSV read/write
  "dplyr",      # data manipulation
  "tidyr",      # reshaping (pivot/expand_grid)
  "lubridate",  # date parsing
  "data.table", # fast grouped ops (wayback LOCF, panel summaries)
  "sf",         # spatial join (facility coordinate -> county / attainment area)
  "ggplot2",    # figures (diagnostics/06_panel_profile)
  "scales"      # axis label formatting for figures
)

missing_pkgs <- REQUIRED_PKGS[!vapply(REQUIRED_PKGS, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs)) {
  stop("Missing required package(s): ", paste(missing_pkgs, collapse = ", "),
       "\n  Install with renv::restore() (preferred, uses the pinned versions) or ",
       "install.packages(c(", paste(sprintf('\"%s\"', missing_pkgs), collapse = ", "), ")).",
       call. = FALSE)
}

# ---- 2. deterministic / quiet options ------------------------------------------------------------------
options(
  readr.show_col_types = FALSE,   # never guess-and-warn about column types (we read raw as character)
  stringsAsFactors     = FALSE,
  scipen               = 999      # no scientific notation in written IDs/counts
)
# The pipeline has no stochastic step (point-in-polygon and dup flagging are deterministic), so no seed is
# required. If you add sampling/bootstrapping, set a seed explicitly in that script (project rule).

# ---- 3. record the session for reproducibility ---------------------------------------------------------
local({
  out <- here::here("output")
  dir.create(out, showWarnings = FALSE, recursive = TRUE)
  writeLines(capture.output(sessionInfo()), file.path(out, "sessionInfo.txt"))
})

cat("00_setup: environment OK (", length(REQUIRED_PKGS), " packages present); session recorded to output/sessionInfo.txt\n", sep = "")
