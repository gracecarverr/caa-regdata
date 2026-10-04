# =========================================================================================================
# code/diagnostics/05_panel_summaries.R -- summary tabulations for the three built panels (electric,
#   major_synmin, universe). Emits booktabs LaTeX table fragments (one \input-able .tex per table) + a
#   compilable wrapper. Purpose: characterize each panel, summarize the key measures, surface odd values.
#   in : data/panels/{electric,major_synmin,universe}.csv.gz
#   out: output/tables/*.tex  (fragments) + output/tables/panel_summaries.tex (standalone wrapper)
#   NOTE: no numbers are hand-entered -- every cell is computed here from the panels, so the tables are
#   fully reproducible (rebuild the panels, re-run this). No TeX engine is required to GENERATE the .tex;
#   compile the wrapper with pdflatex/xelatex on a machine that has the `booktabs` package.
# =========================================================================================================
suppressPackageStartupMessages({library(data.table)})               # data.table only; quietly (suppress the load-time banner)

PANELS <- here::here("data/panels")                                  # source dir for the three built panels
OUT    <- here::here("output/tables")                                 # destination dir for .tex fragments + wrapper
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)               # create OUT if missing; no warning if it already exists
YEARS  <- 2005:2025                                                   # the panel's nominal year range, used below to check "balanced"
NAMES  <- c(electric = "Electric", major_synmin = "Major/SynMin", universe = "Universe")  # panel key -> display label, also fixes column order everywhere below

read_panel <- function(nm) fread(file.path(PANELS, paste0(nm, ".csv.gz")))  # read one panel by its short name (electric/major_synmin/universe)
P <- lapply(names(NAMES), read_panel); names(P) <- names(NAMES)       # P is a named list of the 3 panels, keyed the same as NAMES so downstream code can index by name

# ---- formatting + LaTeX helpers ------------------------------------------------------------------------
comma <- function(x) formatC(round(as.numeric(x)), format = "d", big.mark = ",")  # integer-format with thousands separator; round() first so e.g. 999.6 -> "1,000" not truncated to 999
pct   <- function(x, d = 1) paste0(formatC(100 * x, format = "f", digits = d), "\\%")  # proportion -> "NN.N\%" LaTeX string; caller must pass a 0-1 share, not already *100
usd   <- function(x) paste0("\\$", comma(x))                          # dollar-format via comma(); inherits comma()'s rounding to whole dollars

# write one booktabs table float. `df` is a character matrix (cells already formatted/escaped);
# `header` is the column-header row; `groups` optionally adds a spanned header row above it as a named
# integer vector c("Label"=ncols, ""=1, ...); `notes` is an optional footnotesize note under the table.
write_table <- function(file, df, align, header, caption, label, groups = NULL, notes = NULL) {
  L <- c("\\begin{table}[htbp]", "\\centering", "\\small",            # LaTeX table float preamble
         sprintf("\\caption{%s}", caption), sprintf("\\label{%s}", label),  # caption/label are passed through verbatim -- not escaped (see FLAG above)
         sprintf("\\begin{tabular}{%s}", align), "\\toprule")
  if (!is.null(groups)) {                                             # optional spanned group-header row (e.g. "2005-2014" over 2 columns)
    cells <- mapply(function(lab, n) if (trimws(lab) == "") " " else sprintf("\\multicolumn{%d}{c}{%s}", n, lab),
                    names(groups), groups)                            # build one \multicolumn cell per group; blank-label groups render as a bare space (no spanning rule)
    L <- c(L, paste0(paste(cells, collapse = " & "), " \\\\"))        # join the group cells into one LaTeX row
    pos <- cumsum(groups); start <- c(1L, head(pos, -1) + 1L)         # column index ranges each group spans, from the group widths in `groups`
    rules <- character()
    for (i in seq_along(groups)) if (trimws(names(groups)[i]) != "")  # only draw a \cmidrule under groups that have a visible label
      rules <- c(rules, sprintf("\\cmidrule(lr){%d-%d}", start[i], pos[i]))
    L <- c(L, paste(rules, collapse = " "))                           # append the cmidrule row (may be empty string if no labeled groups)
  }
  L <- c(L, paste0(paste(header, collapse = " & "), " \\\\"), "\\midrule")  # column-header row + rule under it
  body <- apply(df, 1, function(r) paste0(paste(r, collapse = " & "), " \\\\"))  # one LaTeX row per matrix row of `df`
  L <- c(L, body, "\\bottomrule", "\\end{tabular}")
  if (!is.null(notes)) L <- c(L, "\\\\[2pt]", sprintf("{\\footnotesize %s}", notes))  # optional footnote line below the table
  L <- c(L, "\\end{table}", "")                                       # trailing blank line for readability when \input elsewhere
  writeLines(L, file.path(OUT, file))                                 # write the .tex fragment to disk
  invisible(file)                                                     # return the filename invisibly (caller doesn't currently use the return value)
}

# per-panel convenience accessors
obs_share <- function(dt, src) mean(dt$obs_source == src)             # share of facility-year rows with a given obs_source value; NA obs_source would silently drop out of both numerator and denominator via ==, but obs_source is expected to always be non-NA
cls_share <- function(dt, desc) {                         # share over ALL facilities (NA class -> not a match)
  fac <- dt[, .SD[1L], by = PGM_SYS_ID]                                # collapse to one row per facility (first observed row) -- class is treated as time-invariant, using whatever value happens to be on the FIRST row per facility
  sum(fac$AIR_POLLUTANT_CLASS_DESC == desc, na.rm = TRUE) / nrow(fac)  # FLAG: denominator is nrow(fac) (ALL facilities, including those with NA class), but the numerator's na.rm=TRUE drops NA-class facilities from the sum -- so this correctly treats NA as "not a match" rather than propagating NA, consistent with the comment, but it's easy to misread as an observed-subset share
}
# FLAG: cls_share() takes "whatever AIR_POLLUTANT_CLASS_DESC value sits on the first row per PGM_SYS_ID"
# rather than checking it's actually constant across a facility's years. If a facility's classification
# ever changes across years in the source panel, this picks the earliest year's value silently -- matches
# the header note below ("current ICIS-AIR snapshot applied to all years") which implies it SHOULD be
# constant, but this function doesn't verify that invariant, it just assumes it.

# =========================================================================================================
# TABLE 1 -- panel overview (panels as columns)
# =========================================================================================================
ov_rows <- list(
  "Facilities"                    = sapply(P, function(d) comma(uniqueN(d$PGM_SYS_ID))),  # distinct facility count per panel
  "Facility-years (rows)"         = sapply(P, function(d) comma(nrow(d))),                # raw row count per panel
  "Years"                         = sapply(P, function(d) sprintf("%d--%d", min(d$year), max(d$year))),  # observed year range (from the data, not from the YEARS constant)
  "Balanced ($=$ fac.\\ $\\times$ 21)" = sapply(P, function(d) if (nrow(d) == uniqueN(d$PGM_SYS_ID) * length(YEARS)) "yes" else "NO"),  # sanity check: is the panel a full facility x year rectangle over the 21-year YEARS window (2005-2025)?
  "\\ \\ \\emph{obs\\_source}: event"      = sapply(P, function(d) pct(obs_share(d, "event"))),       # share of rows where the zero/positive count came from an observed regulatory event
  "\\ \\ \\emph{obs\\_source}: operating"  = sapply(P, function(d) pct(obs_share(d, "operating"))),   # share of rows where the zero came from a wayback-confirmed "facility was operating, no event" structural zero
  "\\ \\ \\emph{obs\\_source}: unobserved" = sapply(P, function(d) pct(obs_share(d, "unobserved"))),  # share of rows with no basis for a zero at all -- these carry NA counts, not zeros
  "\\ \\ Class: major"           = sapply(P, function(d) pct(cls_share(d, "Major Emissions"))),           # facility-level share by pollutant classification (see cls_share FLAG above)
  "\\ \\ Class: synthetic minor" = sapply(P, function(d) pct(cls_share(d, "Synthetic Minor Emissions"))),
  "\\ \\ Class: minor"           = sapply(P, function(d) pct(cls_share(d, "Minor Emissions"))),
  "\\ \\ Class: other / missing" = sapply(P, function(d) {
    fac <- d[, .SD[1L], by = PGM_SYS_ID]                              # same first-row-per-facility collapse as cls_share(), duplicated here rather than reusing the helper
    pct(mean(!fac$AIR_POLLUTANT_CLASS_DESC %in% c("Major Emissions","Synthetic Minor Emissions","Minor Emissions")))  # NA %in% anything is FALSE, so !FALSE is TRUE -- NA class IS counted as "other/missing" here, unlike cls_share() which drops NA via na.rm; the two class-share computations use different NA conventions but they're complementary (this is designed to be the residual bucket) so they still sum to ~100%
  })
)
t1 <- cbind(names(ov_rows), do.call(rbind, ov_rows))                  # row-label column + one column per panel, stacked into a character matrix
write_table("t1_overview.tex", t1, "lrrr",
  header = c("", paste0("\\textbf{", NAMES, "}")),
  caption = "Panel overview. Each panel is a balanced facility $\\times$ year rectangle over 2005--2025; \\emph{obs\\_source} records why a facility-year's counts are $0$ (an event, or wayback-confirmed operating) versus \\texttt{NA} (unobserved). Class shares are per facility (time-invariant).",
  label = "tab:panel_overview",
  notes = "Emissions class is the current ICIS-AIR snapshot applied to all years. ``Minor'' facilities exist only in the Universe panel; the Electric and Major/SynMin presets are restricted by construction.")

# =========================================================================================================
# TABLE 2 -- observation structure: obs_source x era (the "zero vs missing" decomposition)
# =========================================================================================================
t2_rows <- lapply(names(P), function(nm) {
  d <- copy(P[[nm]]); d[, era := fifelse(year < 2015L, "pre", "post")]  # copy() first -- `:=` on a list element mutates by reference; without it, P's panels would permanently gain this column
  g <- function(era, src) sum(d$era == era & d$obs_source == src)     # count facility-years matching a given era x obs_source combination
  c(NAMES[nm],
    comma(g("pre","event")),  comma(g("pre","unobserved")),           # pre-2015: only "event" or "unobserved" are possible (no wayback operating channel pre-2015, per the note below)
    comma(g("post","event")), comma(g("post","operating")), comma(g("post","unobserved")),  # post-2015: all three obs_source values possible
    pct(1 - obs_share(d, "unobserved")))                               # overall (both eras combined) share observed = 1 - unobserved share
})
t2 <- do.call(rbind, t2_rows)
write_table("t2_obs_structure.tex", t2, "lrr rrr r",
  header = c("Panel", "event", "unobs.", "event", "operating", "unobs.", "\\% observed"),
  groups = c(" " = 1, "2005--2014 (pre-wayback)" = 2, "2015--2025 (wayback)" = 3, " " = 1),
  caption = "Observation structure: facility-years by \\emph{obs\\_source} within each era. Before 2015 no wayback snapshot exists, so a facility-year is only ever \\emph{event} (an observed regulatory event) or \\emph{unobserved} (\\texttt{NA}); the wayback \\emph{operating} zero channel is available only 2015--2025. ``\\% observed'' $=$ share of facility-years that are not \\emph{unobserved}.",
  label = "tab:obs_structure",
  notes = "The \\emph{operating} channel recovers wayback-confirmed structural zeros (facility in service, no event) that would otherwise be \\texttt{NA}; it is what raises ``\\% observed'' above the event-only share and is unavailable pre-2015 by construction (W3).")

# =========================================================================================================
# TABLE 3 -- outcome measures: nonzero share (of OBSERVED facility-years) by measure x panel + max/total
# =========================================================================================================
MEAS <- c(n_inspections="Inspections", n_violations="Violations", n_hpv="HPV determinations",
          n_enforcement="Enforcement actions", n_formal="\\ \\ formal", n_informal="\\ \\ informal",
          n_certs="Title V certifications", n_stack_tests="Stack tests", hpv_active="HPV status (active-year)")  # measure column name -> display label, also fixes row order below
t3_rows <- lapply(names(MEAS), function(m) {
  nz  <- sapply(P, function(d) { o <- d[obs_source != "unobserved"]; pct(mean(o[[m]] > 0, na.rm = TRUE)) })  # restrict to observed rows first, THEN take the nonzero share within that subset -- denominator is observed facility-years, not all facility-years
  mx  <- max(sapply(P, function(d) max(d[[m]], na.rm = TRUE)))        # largest single facility-year value for this measure, across all 3 panels (not per-panel)
  tot <- comma(sum(P[["universe"]][[m]], na.rm = TRUE))               # total events, universe panel only (the superset panel, so this is the grand total)
  c(MEAS[m], nz, comma(mx), tot)
})
t3 <- do.call(rbind, t3_rows)
write_table("t3_measures.tex", t3, "l rrr rr",
  header = c("Measure", paste0("\\textbf{", NAMES, "}"), "Max", "Total (univ.)"),
  groups = c(" " = 1, "\\% of observed facility-years with $\\geq 1$" = 3, " " = 2),
  caption = "Outcome measures. Columns 1--3 give the share of \\emph{observed} facility-years (\\emph{obs\\_source} $\\neq$ unobserved) with at least one event; ``Max'' is the largest single facility-year count across all three panels; ``Total (univ.)'' sums events over the Universe panel. All counts include every row (no deduplication); duplicate load is reported separately in the \\texttt{\\_dup} / \\texttt{\\_dup\\_exact} columns.",
  label = "tab:measures",
  notes = "\\emph{formal}/\\emph{informal} partition \\emph{Enforcement actions} exactly. HPV status (interval-based, P8) is a $0/1$ flag, so its ``share'' and ``max'' differ in kind from the count rows. Denominator excludes \\emph{unobserved} facility-years so shares are not diluted by structural \\texttt{NA}s.")

# =========================================================================================================
# TABLE 4 -- data quality: internal-consistency checks (all pass) + flagged odd values
# =========================================================================================================
# consistency checks across all three panels (report worst-case row count; all expected 0)
chk <- function(fn) max(sapply(P, function(d) sum(fn(d), na.rm = TRUE)))  # apply a row-level TRUE/FALSE check `fn` to each panel, sum the violations, and report the WORST (max) count across the 3 panels -- a passing check anywhere doesn't hide a failing check elsewhere, since max() surfaces the worst panel
mismatch <- function(a, b) xor(is.na(a), is.na(b)) | (!is.na(a) & !is.na(b) & a != b)  # NA-aware equality check: NA on exactly one side is itself a violation (partial data), not silently dropped by chk()'s na.rm; both-NA is not a mismatch (consistently unobserved)
consist <- c(
  "Agency split $=$ total (inspections, enforcement)" = chk(function(d) mismatch(d$n_insp_epa+d$n_insp_state+d$n_insp_local, d$n_inspections) | mismatch(d$n_enf_epa+d$n_enf_state+d$n_enf_local, d$n_enforcement)),
  "formal $+$ informal $=$ enforcement"               = chk(function(d) mismatch(d$n_formal + d$n_informal, d$n_enforcement)),
  "FCE $+$ PCE $\\leq$ inspections"                   = chk(function(d) d$n_fce + d$n_pce > d$n_inspections),
  "stack pass $+$ fail $\\leq$ tests"                 = chk(function(d) d$n_stack_pass + d$n_stack_fail > d$n_stack_tests),
  "HPV $\\leq$ violations"                            = chk(function(d) d$n_hpv > d$n_violations),
  "any negative count (any $n\\_$ column)"            = chk(function(d) { nc <- grep("^n_", names(d), value=TRUE); Reduce(`|`, lapply(nc, function(c) d[[c]] < 0)) }),  # scans EVERY column whose name starts with "n_", so this automatically covers new n_* columns added later without needing an update here
  "penalty $> 0$ with no formal action"              = chk(function(d) d$penalty_amount > 0 & d$n_formal == 0),
  "operating status present pre-2015"                = chk(function(d) !is.na(d$op_status_code) & d$year < 2015),   # should always be 0 given the wayback-only-post-2015 discipline noted in Table 2 -- a nonzero value here would mean the "no operating status pre-2015" invariant this whole panel design relies on has been violated
  "exited\\_year $<$ entered\\_year"                 = chk(function(d) d$exited_year < d$entered_year)
)
t4a <- cbind(names(consist), ifelse(consist == 0, "\\checkmark\\ 0", paste0("\\textbf{", comma(consist), "}")))  # bold-flag any nonzero (failing) check in the rendered table

# flagged odd/unexpected values (curated), computed live
u <- P[["universe"]]                                                  # universe panel is the superset, used as the reference for the "flagged values" block below
flag <- c(
  "Max stack tests in one facility-year"    = comma(max(sapply(P, function(d) max(d$n_stack_tests, na.rm=TRUE)))),
  "Max inspections in one facility-year"    = comma(max(sapply(P, function(d) max(d$n_inspections, na.rm=TRUE)))),
  "Min / max nonzero penalty (universe)"    = paste0(usd(min(u$penalty_amount[u$penalty_amount>0], na.rm=TRUE)), " / ", usd(max(u$penalty_amount, na.rm=TRUE))),  # min is restricted to STRICTLY positive penalties (excludes 0/NA) so the "min" isn't trivially 0
  "\\emph{hpv\\_active}$=1$ with no violation record" = comma(max(sapply(P, function(d) sum(d$hpv_active==1 & is.na(d$n_violations), na.rm=TRUE)))),  # counted and explained (not "fixed") in the notes below -- an intentional, documented pattern, not a bug
  "Universe facilities: class other/missing" = comma(u[, .SD[1L], by=PGM_SYS_ID][!AIR_POLLUTANT_CLASS_DESC %in% c("Major Emissions","Synthetic Minor Emissions","Minor Emissions"), .N]),  # first-row-per-facility collapse again (3rd occurrence of this pattern in the file); NA class is included in "other/missing" here via the same %in%-negation logic as Table 1's residual row
  "Universe facilities: planned / under constr." = comma(u[, .SD[1L], by=PGM_SYS_ID][op_status_current_desc %in% c("Planned Facility","Under Construction"), .N]),
  "Most-frequent state (Major/SynMin, Universe)" = paste0(sapply(P[c("major_synmin","universe")], function(d) {
    fac <- d[, .SD[1L], by = PGM_SYS_ID]                              # one row per facility (STATE is time-invariant), same collapse pattern as cls_share()
    tbl <- sort(table(fac$STATE), decreasing = TRUE)                  # facility counts by state, most-frequent first
    names(tbl)[1]                                                     # top state abbreviation, computed live from the current panel
  }), collapse = " / ")
)
t4b <- cbind(names(flag), flag)
# stack the two blocks with a subheading row
t4 <- rbind(
  cbind("\\emph{Internal-consistency checks (rows violating; expect 0)}", ""),  # subheading row: label in col 1, blank value in col 2
  t4a,
  cbind("\\emph{Flagged values to be aware of}", ""),                 # second subheading row
  t4b
)
write_table("t4_data_quality.tex", t4, "lr",
  header = c("Check / flag", "Value"),
  caption = "Data-quality audit. Top block: internal-consistency checks run across all three panels; the value is the worst-case number of violating facility-years (all expected to be $0$). Bottom block: values that are correct but unexpected, worth knowing before use.",
  label = "tab:data_quality",
  notes = "\\emph{hpv\\_active} with no violation record is \\emph{expected} (N6): interval HPV status carries across years with no new determination, so a spell-year reads $1$ where the recorded-year violation count is \\texttt{NA}. The stack-test and inspection maxima are extreme but not impossible (large multi-unit sources); inspect before using as covariates. \\$1 penalties are nominal/placeholder amounts.")

# =========================================================================================================
# TABLE 5 -- operating status & activity by year (wayback window, all three panels)
# =========================================================================================================
yr <- 2015:2025                                                       # wayback-only window (see Table 2 discipline: operating status doesn't exist pre-2015)
op_mat  <- sapply(P, function(d) sapply(yr, function(y) mean(d[year==y]$operating, na.rm=TRUE)))  # panel x year matrix of mean(operating); na.rm=TRUE means years/panels with all-NA operating would silently average over 0 rows -> NaN, not an error
act_mat <- sapply(P, function(d) sapply(yr, function(y) {
  dy <- d[year==y]; mean(pmax(dy$any_inspections, dy$any_violations, dy$any_enforcement, dy$any_certs, na.rm=TRUE), na.rm=TRUE) }))  # "any activity" = elementwise max across the four any_* 0/1 flags; na.rm=TRUE inside pmax() resolves a row via any known 1 even if another flag is NA -- only rows where all four are NA stay NA
t5 <- cbind(as.character(yr),
            matrix(pct(op_mat), ncol=3), matrix(pct(act_mat), ncol=3))  # pct() is vectorized so this applies to the whole matrix at once, then matrix() reshapes back to panel columns -- relies on column-major fill order matching the original op_mat/act_mat layout
write_table("t5_operating_by_year.tex", t5, "l rrr rrr",
  header = c("Year", rep(c("Elec.","M/SM","Univ."), 2)),
  groups = c(" " = 1, "Operating share" = 3, "Any-activity share" = 3),
  caption = "Wayback operating status and regulatory activity by year, 2015--2025. ``Operating share'' is the fraction of facilities with wayback status in $\\{$OPR, TMP, SEA$\\}$; ``Any-activity share'' is the fraction with $\\geq 1$ inspection, violation, enforcement action, or certification that year.",
  label = "tab:operating_by_year",
  notes = "Both series decline monotonically as facilities close and as 2025 is right-truncated. Operating share far exceeds any-activity share: most operating facilities are quiet in a given year -- the gap is exactly the \\emph{operating} structural-zero channel (Table~\\ref{tab:obs_structure}).")

# =========================================================================================================
# WRAPPER -- standalone compilable document that \inputs every fragment
# =========================================================================================================
frags <- c("t1_overview","t2_obs_structure","t3_measures","t4_data_quality","t5_operating_by_year")  # fragment basenames, in the order they should appear in the wrapper document
wrap <- c(
  "% Auto-generated by code/diagnostics/05_panel_summaries.R -- do not hand-edit; re-run the script.",
  "\\documentclass[11pt]{article}",
  "\\usepackage[margin=1in]{geometry}",
  "\\usepackage{booktabs}",
  "\\usepackage{amsmath,amssymb}",
  "\\usepackage[T1]{fontenc}",
  "\\title{CAA regulatory panels: summary tabulations}",
  "\\author{Generated from \\texttt{code/diagnostics/05\\_panel\\_summaries.R}}",
  "\\date{\\today}",
  "\\begin{document}",
  "\\maketitle",
  sprintf("\\input{%s}", frags),                                      # vectorized sprintf -> one \input{...} line per fragment
  "\\end{document}"
)
writeLines(wrap, file.path(OUT, "panel_summaries.tex"))

cat(sprintf("wrote %d table fragments + wrapper to %s\n", length(frags), OUT))  # console summary of what was written
cat("  ", paste0(frags, ".tex", collapse = "  "), "\n")

# =========================================================================================================
# FLAGGED ISSUES -- reviewed and resolved 2026-07-28 (see git history for the pre-review version)
# =========================================================================================================
# 1. esc() -- RESOLVED: removed (dead code, never called).
# 2. (cls_share(), ~line 61) Takes the FIRST row per facility as that facility's classification without
#    verifying it's actually constant across years for that facility. Assumes the "current snapshot applied
#    to all years" invariant documented in Table 1's notes; doesn't check it. Left as-is (documentation only).
# 3. (Table 1, "Class: other / missing" row) Treats NA classification as "other/missing" (via
#    `!x %in% c(...)`, where NA %in% anything is FALSE), which is a DIFFERENT NA convention than cls_share()
#    (which drops NA via na.rm=TRUE). The two are complementary by design (they're meant to sum to ~100%)
#    but use opposite NA semantics -- worth knowing if either is reused elsewhere expecting the other's rule.
#    Left as-is (documentation only).
# 4. (Table 2 loop) RESOLVED: `d <- copy(P[[nm]])` before the `:=` so the mutation no longer leaks into P.
# 5. (Table 2 loop) RESOLVED: dead `tot <- nrow(d)` assignment removed.
# 6. (Table 3, `nz`) Nonzero share is computed on the observed-only subset (obs_source != "unobserved"),
#    consistent with the file's stated discipline -- flagged only because it's the kind of denominator choice
#    that materially changes the reported percentage if a future edit swaps in the full panel by mistake.
#    Left as-is (documentation only).
# 7. (Table 4 consistency checks) RESOLVED: added `mismatch()`, an NA-aware equality check -- NA on exactly
#    one side of the agency-split/formal+informal comparisons now counts as a violation instead of being
#    silently dropped by chk()'s na.rm=TRUE. Both-NA (consistently unobserved) is still not a violation.
# 8. (Table 4 "Most-frequent state" row) RESOLVED: replaced the hard-coded "OK (oil & gas minors)" literal
#    with a live computation of the most-frequent STATE per facility (first-row-per-facility collapse, same
#    pattern as cls_share()) for major_synmin and universe.
# 9. (Table 5, `act_mat`) RESOLVED: added na.rm=TRUE inside pmax() itself (previously only mean() had it) --
#    a facility-year with a known 1 among the four any_* flags now resolves to 1 even if another flag is NA;
#    only all-NA rows stay NA.
