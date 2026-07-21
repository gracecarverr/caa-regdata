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
#   NB lowercase derived column names on purpose -- this is a diagnostic, NOT part of the six-dataset layer,
#   so it does not follow the UPPER_SNAKE_CASE dataset convention (G2). Native columns keep source casing.
# =========================================================================================================
library(readr); library(dplyr); library(lubridate)
source(here::here("code/04_datasets/00_parameters.R"))
OUT <- here::here("output/hpv_spell_diagnostics"); dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

v <- read_csv(file.path(CLEAN, "violations.csv.gz"),
              col_types = cols(PGM_SYS_ID = col_character(), year = col_integer(),
                               dup = col_integer(), dup_exact = col_integer(), .default = col_character()),
              show_col_types = FALSE)

nz <- function(x) !is.na(x) & x != ""                        # non-blank helper
hpv <- v |> filter(ENF_RESPONSE_POLICY_CODE == "HPV")        # HPV universe = enforcement-response tier (not day-zero)

# ---- record-level diagnostics (flags only; no spell construction) ---------------------------------------
hpv <- hpv |> mutate(
  dayzero_dt   = mdy(HPV_DAYZERO_DATE, quiet = TRUE),
  resolved_dt  = mdy(HPV_RESOLVED_DATE, quiet = TRUE),
  dayzero_year  = year(dayzero_dt),
  resolved_year = year(resolved_dt),
  has_dayzero  = nz(HPV_DAYZERO_DATE),
  has_resolved = nz(HPV_RESOLVED_DATE),
  missing_start = !has_dayzero,                              # HPV-coded but no day-zero -> start-less spell
  resolved_only = !has_dayzero &  has_resolved,             #   ...end but no start
  no_dates      = !has_dayzero & !has_resolved,             #   ...neither date
  is_open       =  has_dayzero & !has_resolved,             # started, never a resolved date recorded
  dayzero_unparseable  = has_dayzero  & is.na(dayzero_dt),  # date present but unparseable (e.g. "218")
  resolved_unparseable = has_resolved & is.na(resolved_dt),
  both_parse   = !is.na(dayzero_dt) & !is.na(resolved_dt),
  bad_order    = both_parse & resolved_dt < dayzero_dt,      # resolved BEFORE dayzero
  spell_days   = if_else(both_parse, as.integer(resolved_dt - dayzero_dt), NA_integer_),  # <0 == bad_order
  spans_calendar_years = both_parse & !bad_order & dayzero_year != resolved_year,
  closed_interval = both_parse & !bad_order)                 # a proper [dayzero, resolved] we can reason on

# facility-level context + raw overlap among CLOSED intervals only (no assumption about open/start-less spells)
overlap_flag <- function(s, e) {                             # per facility: does interval i overlap any other?
  n <- length(s); if (n < 2) return(rep(FALSE, n))
  vapply(seq_len(n), function(i) any(s[-i] <= e[i] & e[-i] >= s[i]), logical(1))
}
hpv <- hpv |> group_by(PGM_SYS_ID) |>
  mutate(n_hpv_records     = n(),
         n_closed_intervals = sum(closed_interval),
         overlaps_another   = { f <- rep(FALSE, n()); ci <- which(closed_interval)
           if (length(ci) > 1) f[ci] <- overlap_flag(as.integer(dayzero_dt[ci]), as.integer(resolved_dt[ci]))
           f }) |>
  ungroup() |>
  select(-dayzero_dt, -resolved_dt, -both_parse, -closed_interval)   # drop internals; keep raw strings + years

write_csv(hpv, file.path(OUT, "records.csv.gz"))

# ---- console summary: the decision-relevant distributions -----------------------------------------------
n <- nrow(hpv); pc <- function(x) sprintf("%d (%.1f%%)", sum(x), 100 * mean(x))
cat(sprintf("\nHPV spell diagnostics (ENF_RESPONSE_POLICY_CODE == 'HPV') -- %s records | %s facilities  (dups kept)\n",
            format(n, big.mark = ","), format(n_distinct(hpv$PGM_SYS_ID), big.mark = ",")))
cat("  dup>0 (duplicate rows)      :", pc(hpv$dup > 0), " | dup_exact:", pc(hpv$dup_exact == 1), "\n")
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
cat("  records per facility        : median", median(table(hpv$PGM_SYS_ID)),
    "| max", max(table(hpv$PGM_SYS_ID)), "\n")
cat("\n  dayzero_year distribution (reporting ramp-up; NA == missing_start):\n")
print(table(hpv$dayzero_year, useNA = "ifany"))
