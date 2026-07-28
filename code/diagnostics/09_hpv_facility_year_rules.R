# =========================================================================================================
# code/diagnostics/09_hpv_facility_year_rules.R -- DIAGNOSTIC companion to 08. Rule-comparison, not a deliverable.
#
#   Purpose: show how the facility-year HPV-active flag changes under different spell->year mapping rules, so
#   the mapping choice can be made by SEEING its effect on coverage rather than assumed. This applies candidate
#   interval rules to COMPARE them; it does NOT pick one or emit a deliverable dataset.
#
#   HPV universe: ENF_RESPONSE_POLICY_CODE == "HPV" (matches 08). Start-less HPV records (no parseable day-zero)
#     are UNMAPPABLE (no interval start) and excluded from every rule -- reported as a count. Window = YEARS.
#
#   Four rules (spell start = day-zero always; they differ on END and on how a year is credited):
#     R1 dayzero_year          -- credit ONLY the calendar year of day-zero (duration-agnostic).
#     R2 overlap               -- credit every year [dayzero, end_cons] overlaps. end_cons = resolved (closed &
#                                 well-ordered) else Dec-31 of the day-zero year (open / bad-order). = panel hpv_active.
#     R3 overlap_open_extended -- as R2 but end = Dec-31-2025 for open/bad-order (treat unresolved as ongoing).
#     R4 union_30d             -- R2's intervals, but credit a year only if >30 UNION days fall in it. = panel hpv_active_1mo.
#
#   in : data/processed/violations.csv.gz
#   out: output/hpv_spell_diagnostics/facility_year_rules.csv.gz  (one row per facility-year flagged by ANY rule;
#        columns r1_dayzero_year, r2_overlap, r3_overlap_open_extended, r4_union_30d) + console comparison.
# =========================================================================================================
library(readr); library(dplyr); library(tidyr); library(lubridate)  # readr I/O, dplyr/tidyr reshaping, lubridate date parsing + arithmetic
source(here::here("code/04_datasets/00_parameters.R"))  # provides CLEAN (processed-data path) and YEARS (2005:2025 analysis window)
OUT <- here::here("output/hpv_spell_diagnostics"); dir.create(OUT, showWarnings = FALSE, recursive = TRUE)  # this diagnostic's output dir; idempotent create

nz <- function(x) !is.na(x) & x != ""
# FLAG: nz() is defined but never called anywhere in this script (grep confirms zero other uses) -- vestigial,
# carried over from 08_hpv_spell_diagnostics.R's identical helper. No effect on any number produced below.
h0 <- read_csv(file.path(CLEAN, "violations.csv.gz"),
               col_types = cols(PGM_SYS_ID = col_character(), .default = col_character()), show_col_types = FALSE) |>  # force every column to character (avoid silent numeric-guessing on ID-like fields)
  filter(ENF_RESPONSE_POLICY_CODE == "HPV") |>                # HPV universe = enforcement-response tier (matches 08's filter)
  mutate(dz = mdy(HPV_DAYZERO_DATE, quiet = TRUE), rs = mdy(HPV_RESOLVED_DATE, quiet = TRUE))  # parse day-zero (spell start) and resolved (spell end) dates; unparseable strings -> NA
n_startless <- sum(is.na(h0$dz))                              # "no parseable day-zero" = blank OR unparseable HPV_DAYZERO_DATE; reported, excluded from every rule below
# FLAG: h is the single shared base that r1, r2, r3, and r4 ALL read from (never from h0 directly downstream)
# -- so the start-less exclusion on the next line is applied identically to every rule. That's what makes the
# four rules comparable; if any rule below had instead filtered h0 independently, the four could silently
# disagree on which records are in scope.
h <- h0 |> filter(!is.na(dz)) |>                              # need an interval START
  mutate(closed   = !is.na(rs) & rs >= dz,                    # well-ordered closed spell
         # FLAG: `closed` is FALSE both when rs is truly missing (never resolved) AND when HPV_RESOLVED_DATE
         # was present but unparseable by mdy() -- these two distinct situations (08 tracks them separately as
         # is_open vs resolved_unparseable) are bucketed together here under "open/bad-order" below. Also, a
         # bad-ordered record (resolved BEFORE day-zero -- a likely data-entry error) is silently given the same
         # Dec-31-of-day-zero-year treatment as a genuinely open spell, rather than being excluded or flagged
         # separately. Matches the header's stated design, but conflates data-quality issues with true open spells.
         end_cons = if_else(closed, rs, make_date(year(dz), 12L, 31L)),   # open/bad-order -> day-zero-year-only
         end_ext  = if_else(closed, rs, make_date(2025L, 12L, 31L)))      # open/bad-order -> window end
         # end_cons and end_ext share the exact same `closed` condition, so resolved (closed) intervals get an
         # IDENTICAL end date under R2 and R3 -- the only thing that differs between the two rules is which
         # fallback date (day-zero-year Dec-31 vs. 2025-12-31) an open/bad-order spell gets. That is by design:
         # it isolates the "how do we treat unresolved spells" axis cleanly (see R3 vs R2 contrast below).

# ---- R1: day-zero calendar year only --------------------------------------------------------------------
r1 <- h |> transmute(PGM_SYS_ID, year = year(dz)) |> filter(year %in% YEARS) |>  # keep facility + day-zero calendar year, restrict to the shared YEARS window (same window used by every rule)
  distinct() |> mutate(r1_dayzero_year = 1L)                  # dedupe (multiple HPV records can share a facility-year) and flag as R1-credited

# ---- overlap expander: (PGM_SYS_ID, year) any day of [start,end] lands in year Y -------------------------
overlap_years <- function(start, end, pid) {                  # start/end/pid: equal-length vectors, one HPV record each
  bind_rows(lapply(YEARS, function(Y) {                       # loop over every calendar year in the analysis window
    ys <- make_date(Y, 1L, 1L); ye <- make_date(Y, 12L, 31L)   # year Y's bounds, Jan 1 - Dec 31
    hit <- start <= ye & end >= ys                             # standard interval-overlap test: [start,end] intersects [ys,ye]
    if (any(hit)) tibble(PGM_SYS_ID = pid[hit], year = Y) else NULL  # emit one row per overlapping record; NULL (dropped) if none overlap year Y
  }))
}
r2 <- overlap_years(h$dz, h$end_cons, h$PGM_SYS_ID) |> distinct() |> mutate(r2_overlap = 1L)  # R2: overlap vs. end_cons (open/bad-order capped at day-zero year) -- = panel hpv_active per header
r3 <- overlap_years(h$dz, h$end_ext,  h$PGM_SYS_ID) |> distinct() |> mutate(r3_overlap_open_extended = 1L)  # R3: identical call, only end_cons -> end_ext swapped (confirms R2/R3 differ by exactly that one substitution)

# ---- R4: union > 30 days per facility-year (merge concurrent/adjacent intervals within the year) ---------
seg <- bind_rows(lapply(YEARS, function(Y) {                  # per-facility-year day-range segments, same YEARS window as R1-R3
  ys <- make_date(Y, 1L, 1L); ye <- make_date(Y, 12L, 31L)     # year Y bounds again
  hit <- h$dz <= ye & h$end_cons >= ys                         # overlap test using end_cons -- R4 shares R2's interval definition (not R3's extended one)
  if (any(hit)) tibble(PGM_SYS_ID = h$PGM_SYS_ID[hit], year = Y,
                       ov_start = pmax(h$dz[hit], ys), ov_end = pmin(h$end_cons[hit], ye)) else NULL  # clip each overlapping record's interval to [ys,ye] so segments never spill outside year Y
}))
r4 <- seg |> arrange(PGM_SYS_ID, year, ov_start) |> group_by(PGM_SYS_ID, year) |>  # sort segments chronologically within each facility-year (required for the sweep below), then group
  summarise(union_days = {                                    # merge sorted intervals; sum inclusive lengths
    # FLAG: this block is the crux of R4 -- it must compute a true UNION of possibly-overlapping day-ranges,
    # not just sum segment lengths, or overlapping HPV records for the same facility-year would double-count
    # shared days and inflate union_days (changing which facility-years cross the 30-day threshold). Verified
    # below: it's a standard sorted-interval-merge sweep, not a naive sum.
    s <- as.integer(ov_start); e <- as.integer(ov_end); cs <- s[1]; ce <- e[1]; tot <- 0L  # integer day-numbers; cs/ce = current merged run's [start,end], seeded with the first (sorted) segment
    if (length(s) > 1) for (i in 2:length(s)) {                # only sweep if more than one segment in this facility-year
      if (s[i] <= ce + 1L) ce <- max(ce, e[i]) else { tot <- tot + (ce - cs + 1L); cs <- s[i]; ce <- e[i] } }
      # s[i] <= ce+1L: next segment overlaps OR is adjacent (no day-gap) to the current run -> merge by
      # extending ce (max() also handles a segment fully contained inside the current run). Else: a real gap
      # exists -> close out the current run (add its inclusive day count ce-cs+1 to tot) and start a new run.
    tot + (ce - cs + 1L)                                       # add the final (still-open) run's length; also covers the single-segment case (loop body never executes)
  }, .groups = "drop") |>                                      # union_days = total UNIQUE days of HPV coverage in this facility-year
  filter(union_days > 30) |> transmute(PGM_SYS_ID, year, r4_union_30d = 1L)  # apply the >30-day threshold defining R4 (= panel hpv_active_1mo per header)

# ---- combine (one row per facility-year flagged by ANY rule) --------------------------------------------
fy <- Reduce(\(x, y) full_join(x, y, by = c("PGM_SYS_ID", "year")), list(r1, r2, r3, r4)) |>  # full_join (not inner_join) across all 4 rule tables -- keeps a facility-year even if only ONE rule flags it
  mutate(across(starts_with("r"), \(x) coalesce(x, 0L))) |> arrange(PGM_SYS_ID, year)  # full_join leaves NA where a rule didn't flag that facility-year -- recode NA -> 0 (not flagged), then sort
write_csv(fy, file.path(OUT, "facility_year_rules.csv.gz"))   # one row per facility-year flagged by >=1 rule; columns are the four 0/1 rule flags

# ---- console comparison ---------------------------------------------------------------------------------
tot <- function(c) sprintf("%6d fac-yrs | %5d facilities", sum(fy[[c]]), n_distinct(fy$PGM_SYS_ID[fy[[c]] == 1]))  # helper: total flagged facility-years + distinct facilities flagged, for a given rule column
cat(sprintf("\nHPV facility-year mapping-rule comparison  (window %d-%d; %d start-less records excluded)\n",
            min(YEARS), max(YEARS), n_startless))             # header line: shared YEARS window + the single start-less exclusion count applied to all 4 rules
cat("  R1 dayzero_year          :", tot("r1_dayzero_year"), "\n")             # R1 totals
cat("  R2 overlap               :", tot("r2_overlap"), "\n")                  # R2 totals
cat("  R3 overlap_open_extended :", tot("r3_overlap_open_extended"), "\n")    # R3 totals
cat("  R4 union_30d             :", tot("r4_union_30d"), "\n")                # R4 totals
cat("\n  isolating each decision axis (facility-years):\n")   # section: pairwise contrasts isolating exactly what each rule adds/removes relative to another
cat("   duration     R2 & !R1 (years beyond day-zero year):", sum(fy$r2_overlap == 1 & fy$r1_dayzero_year == 0), "\n")  # facility-years R2 credits that R1 (day-zero year only) misses -- the pure "duration" effect
cat("   open-spell   R3 & !R2 (added by extending open spells):", sum(fy$r3_overlap_open_extended == 1 & fy$r2_overlap == 0), "\n")  # facility-years added purely by extending open/bad-order spells to 2025 instead of day-zero year
cat("   30d-thresh   R2 & !R4 (brief-overlap years dropped):", sum(fy$r2_overlap == 1 & fy$r4_union_30d == 0), "\n")  # facility-years R2 counts on ANY overlap that R4's >30-union-day threshold screens back out
cat("\n  fac-years flagged per year, by rule:\n")              # section: annual time series of flagged facility-years, one column per rule
by_year <- fy |> group_by(year) |>                             # group facility-year rows by calendar year...
  summarise(R1 = sum(r1_dayzero_year), R2 = sum(r2_overlap),
            R3 = sum(r3_overlap_open_extended), R4 = sum(r4_union_30d), .groups = "drop")  # ...and sum each rule's 0/1 flag to get flagged-facility-year counts per year per rule
print(as.data.frame(by_year), row.names = FALSE)               # print the year x rule comparison table to console

# =========================================================================================================
# FLAGGED ISSUES
#   1. line ~31-38 (h <- h0 |> filter(!is.na(dz)) ...): confirmed all four rules (r1-r4) read from this one
#      shared, pre-filtered `h`, not from h0 -- start-less exclusion is applied identically to every rule.
#      This is what makes the four rules comparable (not a bug; a design invariant worth a reader noticing).
#   2. line ~33 (closed = !is.na(rs) & rs >= dz): `closed` is FALSE both for truly-open spells (rs missing)
#      and for spells with an unparseable HPV_RESOLVED_DATE -- 08 tracks these as separate flags, but here
#      they're bucketed together. Also, bad-ordered records (resolved BEFORE day-zero, likely a data error)
#      get the same Dec-31-of-day-zero-year treatment as genuinely open spells rather than being excluded or
#      called out separately. Matches the header's stated design, but conflates distinct data situations.
#   3. line ~34-38 (end_cons / end_ext): confirmed R2 and R3 share the same `closed` condition, so resolved
#      intervals are treated identically between the two rules -- the only difference is the open/bad-order
#      fallback date (day-zero-year Dec-31 vs. 2025-12-31). Confirms the two rules isolate that one axis cleanly.
#   4. line ~60-67 (union_days sweep in R4): confirmed this is a real sorted-interval merge (handles overlap,
#      containment, and adjacency via `s[i] <= ce + 1L`), not a naive sum of segment lengths -- overlapping
#      HPV records for the same facility-year are unioned, not double-counted. Worth flagging because a bug
#      here (double-counting) would have silently inflated union_days and shifted which facility-years cross
#      the >30-day threshold; verified correct as written.
#   5. line ~26 (nz <- function...): dead code -- defined but never called anywhere in this script (confirmed
#      via grep), left over from 08_hpv_spell_diagnostics.R. No effect on output.
# =========================================================================================================
