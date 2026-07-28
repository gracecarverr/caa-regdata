# =========================================================================================================
# code/diagnostics/08_hpv_spell_diagnostics.R -- DIAGNOSTIC, not a deliverable.
#
#   Purpose: a record-grain view of the raw HPV violation records, to inform how HPV SPELLS should be
#   constructed (dataset 2). It deliberately CONSTRUCTS NO SPELLS -- no interval merging, no open-spell end
#   assumption, no facility-year collapse. It keeps every HPV record as its own row (dups included) and only
#   FLAGS the structure that the construction rules will have to resolve: missing start, open vs resolved,
#   bad-ordered dates, unparseable dates, duplicate rows, and raw overlap between well-ordered closed intervals.
#
#   Grain    : one row per HPV `violations` record, where HPV := ENF_RESPONSE_POLICY_CODE == "HPV" (the
#              enforcement-response tier). This is the DEFINING filter, NOT day-zero presence. The tier below,
#              FRV (Federally Reportable Violation), is OUT of scope. Day-zero (HPV_DAYZERO_DATE) is the spell
#              START field, not the scope filter -- so HPV records that LACK a day-zero are "start-less" spells,
#              a decision input surfaced here (missing_start), not a silent exclusion.
#              dup>0 rows are KEPT -- the duplicate structure is itself a decision input.
#   in       : data/processed/violations.csv.gz
#   out      : output/hpv_spell_diagnostics/records.csv.gz   (record-level, all native cols + diagnostics)
#              + a console summary profiling the decision-relevant distributions.
#
#   NB lowercase derived column names on purpose -- this is a diagnostic, NOT part of the eight-dataset layer,
#   so it does not follow the UPPER_SNAKE_CASE dataset convention (G2). Native columns keep source casing.
# =========================================================================================================
library(readr); library(dplyr); library(lubridate)                    # readr for I/O, dplyr for the pipe chain, lubridate for mdy() date parsing
source(here::here("code/04_datasets/00_parameters.R"))                 # brings in CLEAN (data/processed path) and other shared build constants
OUT <- here::here("output/hpv_spell_diagnostics"); dir.create(OUT, showWarnings = FALSE, recursive = TRUE)  # this diagnostic's own output dir; silent if it already exists

v <- read_csv(file.path(CLEAN, "violations.csv.gz"),                   # cleaned violations extract, ALL enforcement-response tiers (not yet HPV-filtered)
              col_types = cols(PGM_SYS_ID = col_character(), year = col_integer(),  # force PGM_SYS_ID to stay character (leading zeros); year as integer
                               dup = col_integer(), dup_exact = col_integer(), .default = col_character()),  # dup/dup_exact as integer counts; everything else (incl. the raw date strings) read as character
              show_col_types = FALSE)                                  # suppress readr's inferred-column-spec printout

nz <- function(x) !is.na(x) & x != ""                        # non-blank helper
# FLAG: nz() is the load-bearing NA-safety primitive for the whole "missing_start" story below -- it treats
# NA and "" as blank and returns TRUE/FALSE only, NEVER NA. Because has_dayzero/has_resolved (built from nz())
# can never themselves be NA, missing_start/resolved_only/no_dates/is_open (built by boolean-combining them)
# are also always TRUE/FALSE -- none of them can silently become NA and get dropped by an NA-unsafe filter,
# join, or na.rm downstream. This is what lets missing_start be COUNTED rather than silently excluded, per
# the header's requirement.
hpv <- v |> filter(ENF_RESPONSE_POLICY_CODE == "HPV")        # HPV universe = enforcement-response tier (not day-zero)
# FLAG: this is THE defining filter for the entire script (see header, "DEFINING filter"). Every stat below
# reads from `hpv`, never from `v` again -- a stray reference back to `v`, or a swap to the FRV tier, would
# silently change every downstream count/percentage without erroring. Confirmed: `v` is not referenced again
# anywhere below this line.

# ---- record-level diagnostics (flags only; no spell construction) ---------------------------------------
hpv <- hpv |> mutate(                                          # add per-record diagnostic columns; still one row per raw HPV record (no collapsing)
  dayzero_dt   = mdy(HPV_DAYZERO_DATE, quiet = TRUE),           # parse day-zero string as M/D/Y; NA if blank or unparseable (quiet = no per-row warning spam)
  resolved_dt  = mdy(HPV_RESOLVED_DATE, quiet = TRUE),          # same parsing for the resolved-date string
  dayzero_year  = year(dayzero_dt),                             # calendar year of day-zero; NA propagates when dayzero_dt is NA
  resolved_year = year(resolved_dt),                            # calendar year of resolved date; NA propagates when resolved_dt is NA
  has_dayzero  = nz(HPV_DAYZERO_DATE),                          # TRUE iff the raw day-zero STRING is present and non-blank (independent of whether it later parses)
  has_resolved = nz(HPV_RESOLVED_DATE),                         # TRUE iff the raw resolved-date STRING is present and non-blank
  missing_start = !has_dayzero,                              # HPV-coded but no day-zero -> start-less spell
  # FLAG: this is the "start-less spell" surfaced by the header -- a genuine decision input for spell
  # construction, deliberately NOT filtered out here. missing_start is based on raw-string presence (has_dayzero),
  # not on parse success, so it is a strictly narrower category than "no usable dayzero_dt": a garbled but
  # non-blank date string (e.g. "218") is has_dayzero == TRUE and therefore missing_start == FALSE -- it shows
  # up instead in dayzero_unparseable below. A reader who wants "records with no usable start date at all"
  # must combine missing_start OR dayzero_unparseable, not read missing_start alone.
  resolved_only = !has_dayzero &  has_resolved,             #   ...end but no start
  no_dates      = !has_dayzero & !has_resolved,             #   ...neither date
  is_open       =  has_dayzero & !has_resolved,             # started, never a resolved date recorded
  dayzero_unparseable  = has_dayzero  & is.na(dayzero_dt),  # date present but unparseable (e.g. "218")
  resolved_unparseable = has_resolved & is.na(resolved_dt), # resolved-date string present but mdy() couldn't parse it
  both_parse   = !is.na(dayzero_dt) & !is.na(resolved_dt), # TRUE only when BOTH dates exist and parsed successfully
  bad_order    = both_parse & resolved_dt < dayzero_dt,      # resolved BEFORE dayzero
  # FLAG: NA-safety by construction, not by accident -- because `&` is evaluated left-to-right and both_parse
  # is FALSE (never NA) whenever either date is missing/unparseable, `resolved_dt < dayzero_dt` evaluating to
  # NA on those rows still collapses to bad_order == FALSE, not NA. Had this been written as a bare
  # `resolved_dt < dayzero_dt` without the both_parse gate, unparseable/missing-date rows would produce NA
  # here, and depending on how bad_order was later summarized (e.g. sum()/mean() without na.rm, or a %in%
  # filter), those problem rows could be silently excluded from the bad_order count instead of showing up
  # (correctly) in dayzero_unparseable/resolved_unparseable/missing_start instead.
  spell_days   = if_else(both_parse, as.integer(resolved_dt - dayzero_dt), NA_integer_),  # <0 == bad_order
  spans_calendar_years = both_parse & !bad_order & dayzero_year != resolved_year,  # well-ordered closed interval that crosses a Dec 31 boundary
  closed_interval = both_parse & !bad_order)                 # a proper [dayzero, resolved] we can reason on

# facility-level context + raw overlap among CLOSED intervals only (no assumption about open/start-less spells)
overlap_flag <- function(s, e) {                             # per facility: does interval i overlap any other?
  n <- length(s); if (n < 2) return(rep(FALSE, n))              # 0 or 1 interval can't overlap anything; guard also avoids indexing s[-i] on a length-1 vector
  vapply(seq_len(n), function(i) any(s[-i] <= e[i] & e[-i] >= s[i]), logical(1))  # standard pairwise interval-overlap test: some other interval starts before i ends AND ends after i starts
}
hpv <- hpv |> group_by(PGM_SYS_ID) |>                          # recompute per-facility context; three columns below are facility-level, broadcast back to every row
  mutate(n_hpv_records     = n(),                              # raw HPV record count per facility -- INCLUDES dup rows, start-less rows, bad-order rows (no filtering)
         n_closed_intervals = sum(closed_interval),            # count of well-ordered closed intervals per facility (the population the overlap check runs over)
         overlaps_another   = { f <- rep(FALSE, n()); ci <- which(closed_interval)  # default FALSE for every row in the facility; ci = positions that are closed intervals
           if (length(ci) > 1) f[ci] <- overlap_flag(as.integer(dayzero_dt[ci]), as.integer(resolved_dt[ci]))  # only closed-interval rows can be flagged; Date -> integer day-count for the comparison
           f }) |>                                              # return the per-row overlap vector as the mutate result
  ungroup() |>                                                  # drop the PGM_SYS_ID grouping before the final column drop + write
  select(-dayzero_dt, -resolved_dt, -both_parse, -closed_interval)   # drop internals; keep raw strings + years
# FLAG (two decisions bundled in the block above):
#   (1) overlaps_another is scoped to closed_interval rows ONLY (see header: "raw overlap between well-ordered
#       closed intervals"). A missing_start, is_open, or bad_order record is always FALSE here even if it might
#       genuinely overlap a neighboring closed spell -- that's intentional per the header's stated scope, but a
#       reader summarizing overlaps_another should not read it as "overlap among all HPV records at this facility."
#   (2) select() drops closed_interval (and both_parse/dayzero_dt/resolved_dt) from `hpv` itself, so it is also
#       gone from records.csv.gz. It's reconstructable downstream from has_dayzero/has_resolved/*_unparseable/
#       bad_order, but not read directly off the file -- worth knowing if someone later wants to audit exactly
#       which rows fed the overlap check.

write_csv(hpv, file.path(OUT, "records.csv.gz"))                # record-level output: every native violations column + all diagnostic flags above

# ---- console summary: the decision-relevant distributions -----------------------------------------------
n <- nrow(hpv); pc <- function(x) sprintf("%d (%.1f%%)", sum(x), 100 * mean(x))  # n = total HPV records (post-filter, dup rows included)
# FLAG: pc() calls sum()/mean() with no na.rm -- if any flag column passed to it ever contained NA, this would
# silently print "NA (NA%)" for that line instead of erroring. Every flag column built above (missing_start,
# resolved_only, no_dates, is_open, *_unparseable, bad_order, spans_calendar_years, overlaps_another) is
# non-NA by construction (see nz() FLAG and bad_order FLAG above), so this holds today -- but it is an implicit
# assumption a future added column must preserve.
cat(sprintf("\nHPV spell diagnostics (ENF_RESPONSE_POLICY_CODE == 'HPV') -- %s records | %s facilities  (dups kept)\n",
            format(n, big.mark = ","), format(n_distinct(hpv$PGM_SYS_ID), big.mark = ",")))  # header line: record/facility counts, explicit reminder that dups are kept
cat("  dup>0 (duplicate rows)      :", pc(hpv$dup > 0), " | dup_exact:", pc(hpv$dup_exact == 1), "\n")
# FLAG: no distinct()/deduplication step exists anywhere in this script (checked: none). dup>0 here is the
# true prevalence of duplicate rows in the KEPT data, not a residual measured after silently dropping dups --
# consistent with the header's "dup>0 rows are KEPT" requirement, but worth confirming for any reader who
# assumes a diagnostic script would dedup before profiling.
cat("  missing_start (no day-zero) :", pc(hpv$missing_start),
    "  [resolved_only:", pc(hpv$resolved_only), "| no_dates:", pc(hpv$no_dates), "]\n")
cat("  has resolved                :", pc(hpv$has_resolved), " | is_open (start, no end):", pc(hpv$is_open), "\n")
cat("  dayzero unparseable         :", pc(hpv$dayzero_unparseable), "\n")
cat("  resolved unparseable        :", pc(hpv$resolved_unparseable), "\n")
cat("  bad_order (resolved<dayzero):", pc(hpv$bad_order), "\n")
cat("  spans calendar years        :", pc(hpv$spans_calendar_years), "\n")
cat("  overlaps another (closed)   :", pc(hpv$overlaps_another), "\n")
cat(sprintf("  spell_days (closed, well-ordered): median %d | p90 %d | max %d\n",
            median(hpv$spell_days[hpv$spell_days >= 0], na.rm = TRUE),
            quantile(hpv$spell_days[hpv$spell_days >= 0], .9, na.rm = TRUE),
            max(hpv$spell_days[hpv$spell_days >= 0], na.rm = TRUE)))
# FLAG: hpv$spell_days >= 0 is NA (not FALSE) wherever spell_days itself is NA (i.e. !both_parse rows), and
# indexing a vector with a logical NA KEEPS an NA at that position rather than dropping the element -- so this
# subset still contains NAs for every non-closed-interval record. The result is correct only because
# na.rm = TRUE is passed to median()/quantile()/max() below, which then discards those NAs; the >= 0 filter
# by itself does NOT do the exclusion. Also note this restricts the summary to spell_days >= 0, i.e. well-
# ordered closed intervals only -- bad_order's negative spell_days are excluded from this median/p90/max, per
# the "(closed, well-ordered)" label.
cat("  records per facility        : median", median(table(hpv$PGM_SYS_ID)),
    "| max", max(table(hpv$PGM_SYS_ID)), "\n")                  # per-facility record counts over ALL kept rows (dups and problem records included, per header)
cat("\n  dayzero_year distribution (reporting ramp-up; NA == missing_start):\n")
print(table(hpv$dayzero_year, useNA = "ifany"))
# FLAG: useNA = "ifany" is what makes missing_start facility-records show up as an explicit NA row in this
# table instead of vanishing. table()'s default (useNA = "no") would silently drop every dayzero_year == NA
# record from the printed distribution -- i.e. would silently exclude exactly the "start-less spell" population
# the header says must be surfaced, not excluded. This is the correct, deliberate choice; flagged because the
# default would have reintroduced the exact silent-exclusion bug the rest of the script works to avoid.

# =========================================================================================================
# FLAGGED ISSUES
#   L32-38  nz() never returns NA (only TRUE/FALSE) -- the foundation that keeps missing_start/has_dayzero/
#           has_resolved always non-NA, so they can't be silently dropped by downstream NA-unsafe logic.
#   L45-48  `hpv <- v |> filter(ENF_RESPONSE_POLICY_CODE == "HPV")` is the single DEFINING filter for the
#           whole script; every stat reads from `hpv`, never `v`, from here on (confirmed no later reference
#           to `v`) -- a stray unfiltered reference or a tier swap (e.g. to FRV) would silently corrupt every
#           downstream number.
#   L56-62  missing_start is based on raw day-zero STRING presence (has_dayzero), not parse success -- a
#           garbled-but-nonblank date string is missing_start == FALSE and instead lands in
#           dayzero_unparseable; "no usable start date" = missing_start OR dayzero_unparseable, not either alone.
#   L69-77  bad_order's `both_parse &` gate is what keeps the comparison NA-safe -- without it, missing/
#           unparseable dates would produce NA in `resolved_dt < dayzero_dt` and risk being silently dropped
#           from the bad_order count by na.rm-style summarization instead of being counted (correctly) under
#           dayzero_unparseable/resolved_unparseable/missing_start.
#   L86-97  overlaps_another is scoped to closed_interval rows only (per header) -- missing_start/is_open/
#           bad_order records are always FALSE here even if they might genuinely overlap a neighboring spell;
#           and the select() below drops closed_interval/both_parse/dayzero_dt/resolved_dt from both `hpv` and
#           records.csv.gz, so the exact overlap-check population isn't directly visible in the output file
#           (it is reconstructable from the remaining flag columns).
#   L106-111 pc() calls sum()/mean() with no na.rm -- silently prints "NA (NA%)" if a flag column ever carried
#           NA; holds today only because every flag column is non-NA by construction (see nz()/bad_order flags).
#   L114-118 dup>0/dup_exact prevalence is measured with NO deduplication step anywhere in the script (verified:
#           no distinct() call) -- consistent with "dup>0 rows are KEPT," but worth confirming for any reader
#           who assumes a diagnostic would dedup before profiling.
#   L136-142 hpv$spell_days >= 0 indexing keeps NA entries (logical-NA indexing doesn't drop, it inserts NA);
#           the median/p90/max are correct only because na.rm = TRUE is passed downstream -- the >= 0 filter
#           itself does not perform the exclusion.
#   L150-155 print(table(hpv$dayzero_year, useNA = "ifany")) -- useNA = "ifany" is required to surface
#           missing_start records as an explicit NA row; the table() default (useNA = "no") would silently
#           drop them from the printed distribution, reintroducing the silent-exclusion the script otherwise
#           avoids.
# =========================================================================================================
