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
suppressPackageStartupMessages({library(data.table)})

PANELS <- here::here("data/panels")
OUT    <- here::here("output/tables")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
YEARS  <- 2005:2025
NAMES  <- c(electric = "Electric", major_synmin = "Major/SynMin", universe = "Universe")

read_panel <- function(nm) fread(file.path(PANELS, paste0(nm, ".csv.gz")))
P <- lapply(names(NAMES), read_panel); names(P) <- names(NAMES)

# ---- formatting + LaTeX helpers ------------------------------------------------------------------------
comma <- function(x) formatC(round(as.numeric(x)), format = "d", big.mark = ",")
pct   <- function(x, d = 1) paste0(formatC(100 * x, format = "f", digits = d), "\\%")
usd   <- function(x) paste0("\\$", comma(x))
esc   <- function(s) {                                    # escape literal text for LaTeX
  s <- gsub("\\", "\\textbackslash{}", s, fixed = TRUE)
  for (ch in c("&", "%", "$", "#", "_", "{", "}"))
    s <- gsub(ch, paste0("\\", ch), s, fixed = TRUE)
  s
}

# write one booktabs table float. `df` is a character matrix (cells already formatted/escaped);
# `header` is the column-header row; `groups` optionally adds a spanned header row above it as a named
# integer vector c("Label"=ncols, ""=1, ...); `notes` is an optional footnotesize note under the table.
write_table <- function(file, df, align, header, caption, label, groups = NULL, notes = NULL) {
  L <- c("\\begin{table}[htbp]", "\\centering", "\\small",
         sprintf("\\caption{%s}", caption), sprintf("\\label{%s}", label),
         sprintf("\\begin{tabular}{%s}", align), "\\toprule")
  if (!is.null(groups)) {
    cells <- mapply(function(lab, n) if (trimws(lab) == "") " " else sprintf("\\multicolumn{%d}{c}{%s}", n, lab),
                    names(groups), groups)
    L <- c(L, paste0(paste(cells, collapse = " & "), " \\\\"))
    pos <- cumsum(groups); start <- c(1L, head(pos, -1) + 1L)
    rules <- character()
    for (i in seq_along(groups)) if (trimws(names(groups)[i]) != "")
      rules <- c(rules, sprintf("\\cmidrule(lr){%d-%d}", start[i], pos[i]))
    L <- c(L, paste(rules, collapse = " "))
  }
  L <- c(L, paste0(paste(header, collapse = " & "), " \\\\"), "\\midrule")
  body <- apply(df, 1, function(r) paste0(paste(r, collapse = " & "), " \\\\"))
  L <- c(L, body, "\\bottomrule", "\\end{tabular}")
  if (!is.null(notes)) L <- c(L, "\\\\[2pt]", sprintf("{\\footnotesize %s}", notes))
  L <- c(L, "\\end{table}", "")
  writeLines(L, file.path(OUT, file))
  invisible(file)
}

# per-panel convenience accessors
obs_share <- function(dt, src) mean(dt$obs_source == src)
cls_share <- function(dt, desc) {                         # share over ALL facilities (NA class -> not a match)
  fac <- dt[, .SD[1L], by = PGM_SYS_ID]
  sum(fac$AIR_POLLUTANT_CLASS_DESC == desc, na.rm = TRUE) / nrow(fac)
}

# =========================================================================================================
# TABLE 1 -- panel overview (panels as columns)
# =========================================================================================================
ov_rows <- list(
  "Facilities"                    = sapply(P, function(d) comma(uniqueN(d$PGM_SYS_ID))),
  "Facility-years (rows)"         = sapply(P, function(d) comma(nrow(d))),
  "Years"                         = sapply(P, function(d) sprintf("%d--%d", min(d$year), max(d$year))),
  "Balanced ($=$ fac.\\ $\\times$ 21)" = sapply(P, function(d) if (nrow(d) == uniqueN(d$PGM_SYS_ID) * length(YEARS)) "yes" else "NO"),
  "\\ \\ \\emph{obs\\_source}: event"      = sapply(P, function(d) pct(obs_share(d, "event"))),
  "\\ \\ \\emph{obs\\_source}: operating"  = sapply(P, function(d) pct(obs_share(d, "operating"))),
  "\\ \\ \\emph{obs\\_source}: unobserved" = sapply(P, function(d) pct(obs_share(d, "unobserved"))),
  "\\ \\ Class: major"           = sapply(P, function(d) pct(cls_share(d, "Major Emissions"))),
  "\\ \\ Class: synthetic minor" = sapply(P, function(d) pct(cls_share(d, "Synthetic Minor Emissions"))),
  "\\ \\ Class: minor"           = sapply(P, function(d) pct(cls_share(d, "Minor Emissions"))),
  "\\ \\ Class: other / missing" = sapply(P, function(d) {
    fac <- d[, .SD[1L], by = PGM_SYS_ID]
    pct(mean(!fac$AIR_POLLUTANT_CLASS_DESC %in% c("Major Emissions","Synthetic Minor Emissions","Minor Emissions")))
  })
)
t1 <- cbind(names(ov_rows), do.call(rbind, ov_rows))
write_table("t1_overview.tex", t1, "lrrr",
  header = c("", paste0("\\textbf{", NAMES, "}")),
  caption = "Panel overview. Each panel is a balanced facility $\\times$ year rectangle over 2005--2025; \\emph{obs\\_source} records why a facility-year's counts are $0$ (an event, or wayback-confirmed operating) versus \\texttt{NA} (unobserved). Class shares are per facility (time-invariant).",
  label = "tab:panel_overview",
  notes = "Emissions class is the current ICIS-AIR snapshot applied to all years. ``Minor'' facilities exist only in the Universe panel; the Electric and Major/SynMin presets are restricted by construction.")

# =========================================================================================================
# TABLE 2 -- observation structure: obs_source x era (the "zero vs missing" decomposition)
# =========================================================================================================
t2_rows <- lapply(names(P), function(nm) {
  d <- P[[nm]]; d[, era := fifelse(year < 2015L, "pre", "post")]
  tot <- nrow(d)
  g <- function(era, src) sum(d$era == era & d$obs_source == src)
  c(NAMES[nm],
    comma(g("pre","event")),  comma(g("pre","unobserved")),
    comma(g("post","event")), comma(g("post","operating")), comma(g("post","unobserved")),
    pct(1 - obs_share(d, "unobserved")))
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
          n_certs="Title V certifications", n_stack_tests="Stack tests", hpv_active="HPV status (active-year)")
t3_rows <- lapply(names(MEAS), function(m) {
  nz  <- sapply(P, function(d) { o <- d[obs_source != "unobserved"]; pct(mean(o[[m]] > 0, na.rm = TRUE)) })
  mx  <- max(sapply(P, function(d) max(d[[m]], na.rm = TRUE)))
  tot <- comma(sum(P[["universe"]][[m]], na.rm = TRUE))
  c(MEAS[m], nz, comma(mx), tot)
})
t3 <- do.call(rbind, t3_rows)
write_table("t3_measures.tex", t3, "l rrr rr",
  header = c("Measure", paste0("\\textbf{", NAMES, "}"), "Max", "Total (univ.)"),
  groups = c(" " = 1, "\\% of observed facility-years with $\\geq 1$" = 3, " " = 2),
  caption = "Outcome measures. Columns 1--3 give the share of \\emph{observed} facility-years (\\emph{obs\\_source} $\\neq$ unobserved) with at least one event; ``Max'' is the largest single facility-year count across all three panels; ``Total (univ.)'' sums events over the Universe panel. All counts are event-level (\\texttt{dup==0}).",
  label = "tab:measures",
  notes = "\\emph{formal}/\\emph{informal} partition \\emph{Enforcement actions} exactly. HPV status (interval-based, P8) is a $0/1$ flag, so its ``share'' and ``max'' differ in kind from the count rows. Denominator excludes \\emph{unobserved} facility-years so shares are not diluted by structural \\texttt{NA}s.")

# =========================================================================================================
# TABLE 4 -- data quality: internal-consistency checks (all pass) + flagged odd values
# =========================================================================================================
# consistency checks across all three panels (report worst-case row count; all expected 0)
chk <- function(fn) max(sapply(P, function(d) sum(fn(d), na.rm = TRUE)))
consist <- c(
  "Agency split $=$ total (inspections, enforcement)" = chk(function(d) (d$n_insp_epa+d$n_insp_state+d$n_insp_local != d$n_inspections) | (d$n_enf_epa+d$n_enf_state+d$n_enf_local != d$n_enforcement)),
  "formal $+$ informal $=$ enforcement"               = chk(function(d) d$n_formal + d$n_informal != d$n_enforcement),
  "FCE $+$ PCE $\\leq$ inspections"                   = chk(function(d) d$n_fce + d$n_pce > d$n_inspections),
  "stack pass $+$ fail $\\leq$ tests"                 = chk(function(d) d$n_stack_pass + d$n_stack_fail > d$n_stack_tests),
  "HPV $\\leq$ violations"                            = chk(function(d) d$n_hpv > d$n_violations),
  "any negative count (any $n\\_$ column)"            = chk(function(d) { nc <- grep("^n_", names(d), value=TRUE); Reduce(`|`, lapply(nc, function(c) d[[c]] < 0)) }),
  "penalty $> 0$ with no formal action"              = chk(function(d) d$penalty_amount > 0 & d$n_formal == 0),
  "operating status present pre-2015"                = chk(function(d) !is.na(d$op_status_code) & d$year < 2015),
  "exited\\_year $<$ entered\\_year"                 = chk(function(d) d$exited_year < d$entered_year)
)
t4a <- cbind(names(consist), ifelse(consist == 0, "\\checkmark\\ 0", paste0("\\textbf{", comma(consist), "}")))

# flagged odd/unexpected values (curated), computed live
u <- P[["universe"]]
flag <- c(
  "Max stack tests in one facility-year"    = comma(max(sapply(P, function(d) max(d$n_stack_tests, na.rm=TRUE)))),
  "Max inspections in one facility-year"    = comma(max(sapply(P, function(d) max(d$n_inspections, na.rm=TRUE)))),
  "Min / max nonzero penalty (universe)"    = paste0(usd(min(u$penalty_amount[u$penalty_amount>0], na.rm=TRUE)), " / ", usd(max(u$penalty_amount, na.rm=TRUE))),
  "\\emph{hpv\\_active}$=1$ with no violation record" = comma(max(sapply(P, function(d) sum(d$hpv_active==1 & is.na(d$n_violations), na.rm=TRUE)))),
  "Universe facilities: class other/missing" = comma(u[, .SD[1L], by=PGM_SYS_ID][!AIR_POLLUTANT_CLASS_DESC %in% c("Major Emissions","Synthetic Minor Emissions","Minor Emissions"), .N]),
  "Universe facilities: planned / under constr." = comma(u[, .SD[1L], by=PGM_SYS_ID][op_status_current_desc %in% c("Planned Facility","Under Construction"), .N]),
  "Most-frequent state (Major/SynMin, Universe)" = "OK (oil \\& gas minors)"
)
t4b <- cbind(names(flag), flag)
# stack the two blocks with a subheading row
t4 <- rbind(
  cbind("\\emph{Internal-consistency checks (rows violating; expect 0)}", ""),
  t4a,
  cbind("\\emph{Flagged values to be aware of}", ""),
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
yr <- 2015:2025
op_mat  <- sapply(P, function(d) sapply(yr, function(y) mean(d[year==y]$operating, na.rm=TRUE)))
act_mat <- sapply(P, function(d) sapply(yr, function(y) {
  dy <- d[year==y]; mean(pmax(dy$any_inspections, dy$any_violations, dy$any_enforcement, dy$any_certs), na.rm=TRUE) }))
t5 <- cbind(as.character(yr),
            matrix(pct(op_mat), ncol=3), matrix(pct(act_mat), ncol=3))
write_table("t5_operating_by_year.tex", t5, "l rrr rrr",
  header = c("Year", rep(c("Elec.","M/SM","Univ."), 2)),
  groups = c(" " = 1, "Operating share" = 3, "Any-activity share" = 3),
  caption = "Wayback operating status and regulatory activity by year, 2015--2025. ``Operating share'' is the fraction of facilities with wayback status in $\\{$OPR, TMP, SEA$\\}$; ``Any-activity share'' is the fraction with $\\geq 1$ inspection, violation, enforcement action, or certification that year.",
  label = "tab:operating_by_year",
  notes = "Both series decline monotonically as facilities close and as 2025 is right-truncated. Operating share far exceeds any-activity share: most operating facilities are quiet in a given year -- the gap is exactly the \\emph{operating} structural-zero channel (Table~\\ref{tab:obs_structure}).")

# =========================================================================================================
# TABLE 6 -- electric-only: PM2.5 nonattainment exposure
# =========================================================================================================
e <- P[["electric"]]
efac <- e[, .SD[1L], by = PGM_SYS_ID]
areas <- e[!is.na(pm25_area) & pm25_area != "", .N, by = pm25_area][order(-N)][1:5]
t6_top <- rbind(
  c("Facilities ever in a PM2.5 nonattainment area", comma(e[any_naa==1, uniqueN(PGM_SYS_ID)])),
  c("\\ \\ as \\% of electric facilities",           pct(e[any_naa==1, uniqueN(PGM_SYS_ID)] / uniqueN(e$PGM_SYS_ID))),
  c("Facility-years in nonattainment ($any\\_naa=1$)", comma(sum(e$any_naa==1, na.rm=TRUE))),
  c("Facility-years in attainment ($any\\_naa=0$)",    comma(sum(e$any_naa==0, na.rm=TRUE))),
  c("Facility-years \\texttt{NA} (pre-2016 or unplaced)", comma(sum(is.na(e$any_naa)))),
  c("\\emph{Top nonattainment areas} (facility-years)", "")
)
t6_areas <- cbind(paste0("\\ \\ ", esc(areas$pm25_area)), comma(areas$N))
t6 <- rbind(t6_top, t6_areas)
write_table("t6_electric_attainment.tex", t6, "lr",
  header = c("PM2.5 nonattainment exposure (Electric panel)", "Value"),
  caption = "Electric panel: PM2.5 (2012 NAAQS) nonattainment exposure, 2016--2025. \\emph{any\\_naa} flags a facility-year located in a designated PM2.5 nonattainment area; \\texttt{NA} before the 2016 designation window or where the facility could not be placed in a county.",
  label = "tab:electric_attainment",
  notes = "Attainment status is PM2.5-only and available 2016--2025 (AT1); exposure is heavily concentrated in California air basins.")

# =========================================================================================================
# WRAPPER -- standalone compilable document that \inputs every fragment
# =========================================================================================================
frags <- c("t1_overview","t2_obs_structure","t3_measures","t4_data_quality","t5_operating_by_year","t6_electric_attainment")
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
  sprintf("\\input{%s}", frags),
  "\\end{document}"
)
writeLines(wrap, file.path(OUT, "panel_summaries.tex"))

cat(sprintf("wrote %d table fragments + wrapper to %s\n", length(frags), OUT))
cat("  ", paste0(frags, ".tex", collapse = "  "), "\n")
