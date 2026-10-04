# =========================================================================================================
# code/diagnostics/10_begin_year_proxy.R -- DIAGNOSTIC, not a deliverable. Evaluates whether
#   EARLIEST_PROGRAM_BEGIN_YEAR (facility-level min BEGIN_DATE year, dataset 1 / O5) is a usable PROXY for
#   operating status, mainly to extend coverage into 2005-2014 where the wayback-based OPERATING flag is NA
#   (wayback only covers 2015-2025). Currently this field feeds nothing else in the pipeline (grep-confirmed).
#
#   Proxy definition: proxy = 1{EARLIEST_PROGRAM_BEGIN_YEAR <= YEAR} -- onset-only, since BEGIN_DATE has no
#   matching close date. Ground truth = wayback OPERATING, available only where WAYBACK_OBSERVED == 1
#   (2015-2025). All comparisons here are descriptive/statistical agreement checks, not causal claims.
#
#   in : data/datasets/operating.csv.gz
#   out: output/begin_year_proxy/{coverage,agreement,lag,post_exit_false_positive}.csv + console summary
# =========================================================================================================
library(readr); library(dplyr); library(tidyr); library(lubridate)  # readr I/O, dplyr pipes, tidyr helpers, lubridate mdy()/year()

OUT <- here::here("output/begin_year_proxy"); dir.create(OUT, showWarnings = FALSE, recursive = TRUE)  # output dir for this diagnostic; ok if it already exists

# load dataset 1 (operating.csv.gz): facility x year rectangle with wayback-based operating status/spells
# and the program begin-year fields under test
op <- read_csv(here::here("data/datasets/operating.csv.gz"),
               col_types = cols(PGM_SYS_ID = col_character(), EXIT_SOURCE = col_character(),   # force ID/code columns to character...
                                OP_STATUS_CODE = col_character(), OP_STATUS_DESC = col_character(),  # ...status code/desc too
                                .default = col_integer()), show_col_types = FALSE) |>  # everything else defaults to integer; suppress col-type message
  # FLAG: proxy definition is onset-only -- 1{begin_year <= YEAR} with no close-date term, so once a
  #   facility's proxy flips to 1 it can NEVER return to 0, even after a confirmed exit. This is a real
  #   design property (not a coding bug) but it mechanically guarantees false positives in every post-exit
  #   year (see section 4 below) and caps specificity/overall-agreement -- read those numbers with this in mind.
  mutate(proxy = as.integer(!is.na(EARLIEST_PROGRAM_BEGIN_YEAR) & EARLIEST_PROGRAM_BEGIN_YEAR <= YEAR))

# ---- 1. coverage: NA rates + the actual 2005-2014 upside being evaluated --------------------------------
n_fac <- n_distinct(op$PGM_SYS_ID)  # denominator for the facility-level pct_of_facilities column below
cov <- tibble(
  # five-row hand-built table; each `n` entry below lines up positionally with its `metric` label
  metric = c("facilities, any raw begin-year", "facilities, screened begin-year",  # label 1: any parseable raw begin-year; label 2: begin-year surviving the [1970,2025] validity screen (O5)
             "facility-years 2005-2014 (pre-wayback)", "  ...currently NA under wayback (all of them)",  # label 3: size of pre-wayback window; label 4: of those, how many have NA OPERATING today (all, by construction)
             "  ...would gain non-NA proxy if adopted"),  # label 5: of the NA rows, how many would get a non-NA value if the proxy were adopted
  n = c(n_distinct(op$PGM_SYS_ID[!is.na(op$EARLIEST_PROGRAM_BEGIN_YEAR_RAW)]),  # count for label 1
        n_distinct(op$PGM_SYS_ID[!is.na(op$EARLIEST_PROGRAM_BEGIN_YEAR)]),  # count for label 2
        sum(op$YEAR < 2015),  # count for label 3
        sum(op$YEAR < 2015 & is.na(op$OPERATING)),  # count for label 4 (should equal label 3 -- wayback never observes before 2015)
        sum(op$YEAR < 2015 & is.na(op$OPERATING) & !is.na(op$EARLIEST_PROGRAM_BEGIN_YEAR))),  # count for label 5
  pct_of_facilities = round(100 * n / c(n_fac, n_fac, NA, NA, NA), 1))  # % of facilities; NA for the facility-year rows (different denominator)
write_csv(cov, file.path(OUT, "coverage.csv"))  # write coverage.csv

# ---- 2. agreement vs ground truth, 2015-2025 overlap window ----------------------------------------------
gt <- op |> filter(WAYBACK_OBSERVED == 1, !is.na(EARLIEST_PROGRAM_BEGIN_YEAR))  # ground-truth-eligible subset: wayback-observed rows with a defined proxy -- correctly restricts every agreement calc below to where ground truth exists
tp <- sum(gt$proxy == 1 & gt$OPERATING == 1); fn <- sum(gt$proxy == 0 & gt$OPERATING == 1)  # TP: proxy=1 & truly operating; FN: proxy=0 but truly operating
tn <- sum(gt$proxy == 0 & gt$OPERATING == 0); fp <- sum(gt$proxy == 1 & gt$OPERATING == 0)  # TN: proxy=0 & truly not operating; FP: proxy=1 but truly not (structurally likely post-exit, see FLAG above)
agreement <- tibble(
  n_facility_years = nrow(gt),  # size of the ground-truth-eligible subset
  base_rate_operating = round(mean(gt$OPERATING), 4),  # share of gt rows truly operating -- context for reading sensitivity/specificity
  sensitivity = round(tp / (tp + fn), 4),      # P(proxy=1 | actually operating)
  specificity = round(tn / (tn + fp), 4),      # P(proxy=0 | actually not operating)
  overall_agreement = round((tp + tn) / nrow(gt), 4),  # FLAG: (TP+TN)/N naive accuracy -- blends pre- and post-exit years, so its ceiling is mechanically capped by the structural post-exit FP rate (section 4), not purely by proxy quality
  tp = tp, fn = fn, tn = tn, fp = fp)  # carry raw confusion counts through to the CSV for auditing
write_csv(agreement, file.path(OUT, "agreement.csv"))  # write agreement.csv

# ---- 3. lag: entered_year (wayback) vs earliest_program_begin_year, facility-level ------------------------
lag_df <- op |> filter(!is.na(ENTERED_YEAR), !is.na(EARLIEST_PROGRAM_BEGIN_YEAR)) |>  # facilities with both a wayback entry year and a screened begin-year (ENTERED_YEAR is itself wayback-derived, so no separate WAYBACK_OBSERVED filter needed here)
  distinct(PGM_SYS_ID, ENTERED_YEAR, EARLIEST_PROGRAM_BEGIN_YEAR) |>  # collapse to facility grain (both fields are facility-level, broadcast across YEAR in op)
  mutate(lag_years = ENTERED_YEAR - EARLIEST_PROGRAM_BEGIN_YEAR)  # positive = begin-year precedes observed entry (proxy "leads" reality); negative = begin-year after entry (proxy would lag reality)
lag_summary <- lag_df |> summarise(
  n_facilities = n(), mean_lag = round(mean(lag_years), 2),  # facility count and mean lag
  q25 = quantile(lag_years, .25), median_lag = median(lag_years), q75 = quantile(lag_years, .75),  # quartiles and median of the lag distribution
  pct_begin_after_entry = round(100 * mean(lag_years < 0), 1))   # begin-year AFTER observed entry -> proxy would lag reality
write_csv(lag_df, file.path(OUT, "lag_by_facility.csv"))  # write facility-level lag detail
write_csv(lag_summary, file.path(OUT, "lag_summary.csv"))  # write lag summary stats

# full lag histogram -- every distinct lag value, not just quantiles (2015 is the wayback floor, so any
#   facility with entered_year==2015 is left-censored -- its "true" lag could be understated; flagged separately)
lag_hist <- lag_df |> count(lag_years, name = "n_facilities") |>  # count facilities at each distinct lag value
  mutate(pct = round(100 * n_facilities / sum(n_facilities), 2)) |> arrange(lag_years)  # convert to % of facilities, sort ascending by lag
write_csv(lag_hist, file.path(OUT, "lag_histogram.csv"))  # write full histogram

lag_bucketed <- lag_df |> mutate(bucket = case_when(  # collapse lag_years into interpretable buckets
    lag_years < 0  ~ "begin-year AFTER entry (proxy lags reality)",  # negative-lag bucket
    lag_years == 0 ~ "same year",  # exact match
    lag_years == 1 ~ "1 year lead",  # begin-year one year ahead of entry
    lag_years %in% 2:5  ~ "2-5 years lead",  # moderate lead
    lag_years %in% 6:10 ~ "6-10 years lead",  # long lead
    TRUE ~ ">10 years lead")) |>  # catch-all: very long lead
  count(bucket, name = "n_facilities") |> mutate(pct = round(100 * n_facilities / sum(n_facilities), 1)) |>  # tally facilities per bucket, convert to %
  arrange(match(bucket, c("begin-year AFTER entry (proxy lags reality)", "same year", "1 year lead",  # reorder rows into the logical bucket sequence (not alphabetical)...
                          "2-5 years lead", "6-10 years lead", ">10 years lead")))  # ...rest of the explicit bucket-order vector
write_csv(lag_bucketed, file.path(OUT, "lag_buckets.csv"))  # write bucketed lag summary

# ---- 4. post-exit false positives: proxy has no close date, so it can't see an exit at all ----------------
# FLAG: uses EXITED_YEAR (a facility-level fact carried from wayback_facility_spells, constant across all
#   YEAR rows for that facility) rather than the per-row OPERATING/WAYBACK_OBSERVED columns -- so this is NOT
#   restricted to the 2015-2025 wayback-observed window and correctly extends to any YEAR after the known
#   exit, including years wayback didn't directly observe. Rows stay row-aligned throughout (op is one table,
#   not a join here), so proxy, YEAR, and EXITED_YEAR are always compared within the same facility-year --
#   no misalignment risk. Given the onset-only proxy (FLAG near the top), pct_proxy_false_positive below is
#   expected to run near 100% by construction whenever begin_year <= exited_year (the common case) -- that's
#   the mechanism the section header above already names, not a data-quality finding.
post_exit <- op |> filter(!is.na(EXITED_YEAR), YEAR > EXITED_YEAR, !is.na(EARLIEST_PROGRAM_BEGIN_YEAR)) |>
  group_by(EXIT_SOURCE) |>  # break out by how the exit was determined: cls (confirmed closure) | dropout (inferred, upper-bound) | other
  summarise(n_facility_years = n(), n_facilities = n_distinct(PGM_SYS_ID),  # facility-year and facility counts per exit-source group
            pct_proxy_false_positive = round(100 * mean(proxy == 1), 1), .groups = "drop") |>  # % of post-exit rows where proxy still reads "operating" -- see FLAG above
  arrange(desc(n_facility_years))  # largest exit-source group first
write_csv(post_exit, file.path(OUT, "post_exit_false_positive.csv"))  # write post-exit false-positive summary

# does the false-positive rate decay the longer a facility has been closed, or stay flat? (it should stay
#   ~flat -- proxy is a one-time ratchet with no mechanism to ever flip back to 0)
post_exit_by_gap <- op |> filter(!is.na(EXITED_YEAR), YEAR > EXITED_YEAR, !is.na(EARLIEST_PROGRAM_BEGIN_YEAR)) |>  # same post-exit universe as above (see FLAG at section 4)
  mutate(years_since_exit = YEAR - EXITED_YEAR) |>  # how many years after the confirmed/inferred exit this row falls
  group_by(years_since_exit) |>  # one group per integer gap
  summarise(n_facility_years = n(), pct_proxy_false_positive = round(100 * mean(proxy == 1), 1), .groups = "drop") |>  # count and FP rate at each gap
  arrange(years_since_exit)  # sort ascending by years since exit
write_csv(post_exit_by_gap, file.path(OUT, "post_exit_false_positive_by_gap.csv"))  # write false-positive-by-gap table

# ---- 5. agreement broken out by year -- does the aggregate 2015-2025 number hide drift? --------------------
agreement_by_year <- gt |> group_by(YEAR) |>  # reuses gt (wayback-observed, proxy-defined subset from section 2) -- correctly scoped to ground-truth-valid rows
  summarise(n = n(), base_rate_operating = round(mean(OPERATING), 3),  # facility-year count and true operating rate, per year
            sensitivity = round(sum(proxy == 1 & OPERATING == 1) / sum(OPERATING == 1), 3),  # per-year sensitivity: P(proxy=1 | truly operating)
            specificity = round(sum(proxy == 0 & OPERATING == 0) / sum(OPERATING == 0), 3),  # FLAG: per-year specificity: P(proxy=0 | truly not operating) -- expect this to erode over time as more facilities cross their exit year; that drift is the structural mechanism above, not a new data problem
            overall_agreement = round(mean(proxy == OPERATING), 3), .groups = "drop")  # per-year naive accuracy
write_csv(agreement_by_year, file.path(OUT, "agreement_by_year.csv"))  # write year-by-year agreement

# ---- 6. SINGLE-YEAR ANCHOR CHECK: for facilities whose begin-year predates 2015 (the wayback floor), how
#   corroborated is "this facility existed as of its begin-year" -- NOT "operating continuously since" --
#   by what wayback actually shows once it starts observing in 2015? This is the population where the proxy
#   would add genuinely NEW information (wayback has zero evidence before 2015 for anyone).
fac <- op |> distinct(PGM_SYS_ID, EARLIEST_PROGRAM_BEGIN_YEAR, LEFT_CENSORED, ENTERED_YEAR, EXITED_YEAR, EXIT_SOURCE)  # facility-level table: one row per facility
ever_wb <- op |> filter(WAYBACK_OBSERVED == 1) |> distinct(PGM_SYS_ID) |> mutate(ever_wayback_observed = TRUE)  # facilities seen in at least one real wayback snapshot, 2015-2025 (correctly gated on WAYBACK_OBSERVED)
fac <- fac |> left_join(ever_wb, by = "PGM_SYS_ID") |> mutate(ever_wayback_observed = coalesce(ever_wayback_observed, FALSE))  # left join leaves NA for facilities absent from ever_wb; coalesce to FALSE

pre2015 <- fac |> filter(!is.na(EARLIEST_PROGRAM_BEGIN_YEAR), EARLIEST_PROGRAM_BEGIN_YEAR < 2015) |>  # subset to facilities whose begin-year predates the wayback window
  mutate(corroboration = case_when(  # classify each facility by how well post-2015 wayback evidence corroborates the pre-2015 begin-year claim
    LEFT_CENSORED == 1                                  ~ "A: left-censored at 2015 (consistent -- earliest wayback evidence IS the window floor)",  # consistent: already operating when wayback observation starts
    !is.na(ENTERED_YEAR) & ENTERED_YEAR > 2015           ~ "B: first observed OPERATING after 2015 (gap between claimed begin-year and observed entry)",  # discrepancy: wayback didn't see it operating until later than claimed
    is.na(ENTERED_YEAR) & ever_wayback_observed          ~ "C: never observed operating, but present in wayback (e.g. already CLS by 2015 -- consistent with existing, then closing, pre-2015)",  # ambiguous but plausible
    is.na(ENTERED_YEAR) & !ever_wayback_observed         ~ "D: never appears in ANY real wayback snapshot 2015-2025 (no corroboration at all)",  # weakest case: zero wayback evidence either way
    TRUE ~ "other"))  # catch-all for rows outside A-D (e.g. ENTERED_YEAR==2015 without LEFT_CENSORED==1, or NA LEFT_CENSORED)
pre2015_corroboration <- pre2015 |> count(corroboration, name = "n_facilities") |>  # tally facilities per corroboration category
  mutate(pct = round(100 * n_facilities / sum(n_facilities), 1)) |> arrange(corroboration)  # convert to %, sort by category label (A-D order, alphabetical prefix)
n_other <- sum(pre2015$corroboration == "other")  # canary: A-D is exhaustive as of 2026-07-28 (0 facilities land here) -- print so a future refresh can't silently populate this bucket unnoticed
cat(sprintf("  [canary] pre2015 corroboration 'other' catch-all (outside A-D): %d facilities\n", n_other))
write_csv(pre2015_corroboration, file.path(OUT, "pre2015_single_year_corroboration.csv"))  # write category tallies
write_csv(pre2015 |> select(PGM_SYS_ID, EARLIEST_PROGRAM_BEGIN_YEAR, LEFT_CENSORED, ENTERED_YEAR,  # also write facility-level detail (not just tallies) for auditing individual cases
                            EXITED_YEAR, EXIT_SOURCE, ever_wayback_observed, corroboration),
          file.path(OUT, "pre2015_single_year_facilities.csv"))  # output path for the detail file

# for group B (the real discrepancy group), how big is the gap, and does it shrink for begin-years closer to 2015?
group_b_gap <- pre2015 |> filter(!is.na(ENTERED_YEAR), ENTERED_YEAR > 2015) |>  # isolate group B rows (re-expresses the same condition rather than filtering on corroboration == "B...")
  mutate(gap_years = ENTERED_YEAR - EARLIEST_PROGRAM_BEGIN_YEAR,  # size of the entry/begin-year gap for each group-B facility
         begin_year_bucket = case_when(  # bucket begin-year into coarse eras
           EARLIEST_PROGRAM_BEGIN_YEAR < 2000 ~ "<2000", EARLIEST_PROGRAM_BEGIN_YEAR < 2010 ~ "2000-2009",  # pre-2000 and 2000s buckets
           TRUE ~ "2010-2014")) |>  # catch-all: 2010-2014 (closest to the wayback floor)
  group_by(begin_year_bucket) |>  # one group per era
  summarise(n_facilities = n(), median_gap_years = median(gap_years), mean_gap_years = round(mean(gap_years), 1), .groups = "drop")  # facility count and gap summary per era
write_csv(group_b_gap, file.path(OUT, "pre2015_group_b_gap_by_begin_year.csv"))  # write group-B gap-by-era table

# ---- 7. WHICH PROGRAM TYPES tend to precede actual operation? EARLIEST_PROGRAM_BEGIN_YEAR is a facility-level
#   MIN across every program a facility carries -- it doesn't say which program set that date. Institutional
#   prior (N11, code/02_cleaning/wayback/19_wayback_program_status.R): NSR & PSD are PRECONSTRUCTION permits
#   that attach BEFORE a source operates (that's exactly why 19_ treats PLN/CNS as "active" only for those two
#   groups). Test this directly at the PROGRAM level (not the facility-level min used above) against wayback
#   ENTERED_YEAR: for each program group, take EACH facility's own earliest BEGIN_DATE within that group, and
#   compare it to when wayback actually observed the facility operating.
GROUPS <- list(sip = "CAASIP", titlev = "CAATVP", nsps = c("CAANSPS", "CAANSPSM"), mact = "CAAMACT",  # map each program group name to its underlying PROGRAM_CODE(s)
              gact = "CAAGACTM", neshap = "CAANESH", fesop = "CAAFESOP", nsr = "CAANSR", psd = "CAAPSD",
              cfc = "CAACFC")
code2group <- stack(GROUPS) |> transmute(PROGRAM_CODE = as.character(values), grp = as.character(ind))  # stack() unlists GROUPS into a long (value, group-name) table; rename for the join below

progs <- read_csv(here::here("data/processed/programs.csv.gz"),  # load the raw programs table (facility x program-enrollment record) at the PROGRAM level, not the pre-aggregated facility-level min used in operating.csv.gz
                  col_types = cols(.default = col_character()), show_col_types = FALSE) |>  # read everything as character (BEGIN_DATE parsed explicitly next)
  inner_join(code2group, by = "PROGRAM_CODE") |>  # keep only the 10 allowlisted program codes; inner join drops everything else
  mutate(begin_year = year(mdy(BEGIN_DATE, quiet = TRUE))) |>  # parse to Date then take calendar year; unparseable -> NA silently (quiet=TRUE)
  filter(!is.na(begin_year), begin_year >= 1970, begin_year <= 2025) |>            # same screen as O5
  group_by(PGM_SYS_ID, grp) |> summarise(prog_begin_year = min(begin_year), .groups = "drop")  # earliest begin-year per facility, PER PROGRAM GROUP (not collapsed across groups)

entered <- op |> distinct(PGM_SYS_ID, ENTERED_YEAR) |> filter(!is.na(ENTERED_YEAR))  # facility-level wayback entry year, restricted to facilities where it's actually observed

prog_lag <- progs |> inner_join(entered, by = "PGM_SYS_ID") |>  # keep only facility-program pairs where a wayback entry year also exists
  mutate(lag_years = ENTERED_YEAR - prog_begin_year)  # positive = this program's begin-year precedes observed entry (program-level lead)

prog_lag_by_group <- prog_lag |> group_by(grp) |>  # aggregate lag by program group
  summarise(n_facilities = n(), median_lag = median(lag_years), mean_lag = round(mean(lag_years), 2),  # facility-program count, median and mean lag per group
            pct_begin_before_entry = round(100 * mean(lag_years > 0), 1),   # program begins strictly before entry
            pct_begin_same_year    = round(100 * mean(lag_years == 0), 1),  # % where program begin-year equals observed entry year
            pct_begin_after_entry  = round(100 * mean(lag_years < 0), 1), .groups = "drop") |>  # % where program begin-year is after observed entry (program-level lag)
  arrange(desc(median_lag))  # largest-lead groups first -- expect NSR/PSD (preconstruction permits) near the top per the institutional prior above
write_csv(prog_lag_by_group, file.path(OUT, "program_type_lag_by_group.csv"))  # write per-group lag summary
write_csv(prog_lag, file.path(OUT, "program_type_lag_by_facility.csv"))  # write facility-program-level detail

# ---- console summary ---------------------------------------------------------------------------------------
cat("EARLIEST_PROGRAM_BEGIN_YEAR as an operating-status proxy -- diagnostic summary\n")  # console banner
cat("================================================================================\n\n")  # divider
cat("1. COVERAGE\n"); print(as.data.frame(cov), row.names = FALSE)  # print coverage table
cat(sprintf("\n2. AGREEMENT vs wayback ground truth (2015-2025, n=%s facility-years)\n",
            format(agreement$n_facility_years, big.mark = ",")))  # section header with formatted N
cat(sprintf("   base rate operating=1: %.1f%% | sensitivity: %.3f | specificity: %.3f | overall agreement: %.3f\n",
            100 * agreement$base_rate_operating, agreement$sensitivity, agreement$specificity, agreement$overall_agreement))  # print headline agreement stats
cat(sprintf("   confusion: TP=%s FN=%s TN=%s FP=%s\n",
            format(tp, big.mark=","), format(fn, big.mark=","), format(tn, big.mark=","), format(fp, big.mark=",")))  # print raw confusion counts
cat(sprintf("\n2b. AGREEMENT BY YEAR\n"))  # subsection header
print(as.data.frame(agreement_by_year), row.names = FALSE)  # print year-by-year agreement table
cat(sprintf("\n3. LAG (entered_year - begin_year), n=%s facilities\n", format(lag_summary$n_facilities, big.mark=",")))  # section header with facility count
cat(sprintf("   mean=%.2f | q25=%.0f | median=%.0f | q75=%.0f | begin-year AFTER observed entry: %.1f%%\n",
            lag_summary$mean_lag, lag_summary$q25, lag_summary$median_lag, lag_summary$q75, lag_summary$pct_begin_after_entry))  # print lag five-number summary
cat("\n3b. LAG BUCKETS\n"); print(as.data.frame(lag_bucketed), row.names = FALSE)  # print bucketed lag table
cat("\n3c. FULL LAG HISTOGRAM (every distinct lag value)\n"); print(as.data.frame(lag_hist), row.names = FALSE)  # print full histogram
cat("\n4. POST-EXIT FALSE POSITIVES (proxy=1 in years strictly after exit; EXIT_SOURCE: cls=confirmed closure, dropout=inferred)\n")  # wording matches what EXIT_SOURCE actually distinguishes -- the table below breaks out by EXIT_SOURCE
print(as.data.frame(post_exit), row.names = FALSE)  # print post-exit false-positive table by exit source
cat("\n4b. POST-EXIT FALSE POSITIVE RATE BY YEARS-SINCE-EXIT (does it decay?)\n")  # section header
print(as.data.frame(post_exit_by_gap), row.names = FALSE)  # print false-positive rate by gap
cat(sprintf("\n6. SINGLE-YEAR ANCHOR CHECK: facilities with begin-year < 2015, n=%s\n", format(nrow(pre2015), big.mark = ",")))  # section header with facility count (numbering skips "5" in the console labels -- section 5's content prints above under "2b"; nothing is missing)
print(as.data.frame(pre2015_corroboration), row.names = FALSE)  # print corroboration category tallies
cat("\n6b. GROUP B GAP (entered_year - begin_year) BY BEGIN-YEAR BUCKET\n")  # section header
print(as.data.frame(group_b_gap), row.names = FALSE)  # print group-B gap-by-era table
cat(sprintf("\n7. LAG BY PROGRAM TYPE (entered_year - program's own begin_year), n=%s facility-program pairs\n",
            format(nrow(prog_lag), big.mark = ",")))  # section header with facility-program pair count
print(as.data.frame(prog_lag_by_group), row.names = FALSE)  # print program-type lag table (last output)

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# 1. Line ~22 (mutate(proxy = ...)): proxy is onset-only -- 1{begin_year <= YEAR} with no close-date term.
#    Once true, proxy can never revert to 0, so post-exit years are structurally guaranteed false positives.
#    Not a bug, but every downstream agreement/specificity number should be read with this ceiling in mind.
# 2. Line ~47 (overall_agreement in `agreement` tibble): naive (TP+TN)/N accuracy blends pre- and post-exit
#    years, so its ceiling is mechanically set by the structural post-exit FP rate (section 4), not purely
#    by how good the proxy is at capturing genuine onset timing.
# 3. Line ~81 (post_exit <- op |> filter(...)): confirms the false-positive check is correctly row-aligned
#    (single table, not a join) and correctly uses the facility-level EXITED_YEAR fact rather than requiring
#    per-row WAYBACK_OBSERVED -- intentional design choice, noted so a reader doesn't mistake the missing
#    WAYBACK_OBSERVED filter here for an oversight.
# 4. Line ~101 (specificity in agreement_by_year): per-year specificity is expected to erode over time as
#    more facilities cross their exit year -- that's the same structural mechanism as flag 1, not a new or
#    independent data-quality signal, and shouldn't be read as the proxy "getting worse" over time.
# 5. RESOLVED 2026-07-28: added a `[canary]` console print of the "other" catch-all bucket's size (0 of
#    171,161 as of this pass -- A-D is exhaustive today) so a future data refresh can't silently populate it
#    unnoticed.
# 6. RESOLVED 2026-07-28: console banner reworded from "after a confirmed exit" to name both EXIT_SOURCE
#    values it actually covers (cls=confirmed closure, dropout=inferred), matching the table's own breakout.
