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
library(readr); library(dplyr); library(tidyr); library(lubridate)
source(here::here("code/04_datasets/00_parameters.R"))
OUT <- here::here("output/hpv_spell_diagnostics"); dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

nz <- function(x) !is.na(x) & x != ""
h0 <- read_csv(file.path(CLEAN, "violations.csv.gz"),
               col_types = cols(PGM_SYS_ID = col_character(), .default = col_character()), show_col_types = FALSE) |>
  filter(ENF_RESPONSE_POLICY_CODE == "HPV") |>
  mutate(dz = mdy(HPV_DAYZERO_DATE, quiet = TRUE), rs = mdy(HPV_RESOLVED_DATE, quiet = TRUE))
n_startless <- sum(is.na(h0$dz))
h <- h0 |> filter(!is.na(dz)) |>                              # need an interval START
  mutate(closed   = !is.na(rs) & rs >= dz,                    # well-ordered closed spell
         end_cons = if_else(closed, rs, make_date(year(dz), 12L, 31L)),   # open/bad-order -> day-zero-year-only
         end_ext  = if_else(closed, rs, make_date(2025L, 12L, 31L)))      # open/bad-order -> window end

# ---- R1: day-zero calendar year only --------------------------------------------------------------------
r1 <- h |> transmute(PGM_SYS_ID, year = year(dz)) |> filter(year %in% YEARS) |>
  distinct() |> mutate(r1_dayzero_year = 1L)

# ---- overlap expander: (PGM_SYS_ID, year) any day of [start,end] lands in year Y -------------------------
overlap_years <- function(start, end, pid) {
  bind_rows(lapply(YEARS, function(Y) {
    ys <- make_date(Y, 1L, 1L); ye <- make_date(Y, 12L, 31L)
    hit <- start <= ye & end >= ys
    if (any(hit)) tibble(PGM_SYS_ID = pid[hit], year = Y) else NULL
  }))
}
r2 <- overlap_years(h$dz, h$end_cons, h$PGM_SYS_ID) |> distinct() |> mutate(r2_overlap = 1L)
r3 <- overlap_years(h$dz, h$end_ext,  h$PGM_SYS_ID) |> distinct() |> mutate(r3_overlap_open_extended = 1L)

# ---- R4: union > 30 days per facility-year (merge concurrent/adjacent intervals within the year) ---------
seg <- bind_rows(lapply(YEARS, function(Y) {
  ys <- make_date(Y, 1L, 1L); ye <- make_date(Y, 12L, 31L)
  hit <- h$dz <= ye & h$end_cons >= ys
  if (any(hit)) tibble(PGM_SYS_ID = h$PGM_SYS_ID[hit], year = Y,
                       ov_start = pmax(h$dz[hit], ys), ov_end = pmin(h$end_cons[hit], ye)) else NULL
}))
r4 <- seg |> arrange(PGM_SYS_ID, year, ov_start) |> group_by(PGM_SYS_ID, year) |>
  summarise(union_days = {                                    # merge sorted intervals; sum inclusive lengths
    s <- as.integer(ov_start); e <- as.integer(ov_end); cs <- s[1]; ce <- e[1]; tot <- 0L
    if (length(s) > 1) for (i in 2:length(s)) {
      if (s[i] <= ce + 1L) ce <- max(ce, e[i]) else { tot <- tot + (ce - cs + 1L); cs <- s[i]; ce <- e[i] } }
    tot + (ce - cs + 1L)
  }, .groups = "drop") |>
  filter(union_days > 30) |> transmute(PGM_SYS_ID, year, r4_union_30d = 1L)

# ---- combine (one row per facility-year flagged by ANY rule) --------------------------------------------
fy <- Reduce(\(x, y) full_join(x, y, by = c("PGM_SYS_ID", "year")), list(r1, r2, r3, r4)) |>
  mutate(across(starts_with("r"), \(x) coalesce(x, 0L))) |> arrange(PGM_SYS_ID, year)
write_csv(fy, file.path(OUT, "facility_year_rules.csv.gz"))

# ---- console comparison ---------------------------------------------------------------------------------
tot <- function(c) sprintf("%6d fac-yrs | %5d facilities", sum(fy[[c]]), n_distinct(fy$PGM_SYS_ID[fy[[c]] == 1]))
cat(sprintf("\nHPV facility-year mapping-rule comparison  (window %d-%d; %d start-less records excluded)\n",
            min(YEARS), max(YEARS), n_startless))
cat("  R1 dayzero_year          :", tot("r1_dayzero_year"), "\n")
cat("  R2 overlap               :", tot("r2_overlap"), "\n")
cat("  R3 overlap_open_extended :", tot("r3_overlap_open_extended"), "\n")
cat("  R4 union_30d             :", tot("r4_union_30d"), "\n")
cat("\n  isolating each decision axis (facility-years):\n")
cat("   duration     R2 & !R1 (years beyond day-zero year):", sum(fy$r2_overlap == 1 & fy$r1_dayzero_year == 0), "\n")
cat("   open-spell   R3 & !R2 (added by extending open spells):", sum(fy$r3_overlap_open_extended == 1 & fy$r2_overlap == 0), "\n")
cat("   30d-thresh   R2 & !R4 (brief-overlap years dropped):", sum(fy$r2_overlap == 1 & fy$r4_union_30d == 0), "\n")
cat("\n  fac-years flagged per year, by rule:\n")
by_year <- fy |> group_by(year) |>
  summarise(R1 = sum(r1_dayzero_year), R2 = sum(r2_overlap),
            R3 = sum(r3_overlap_open_extended), R4 = sum(r4_union_30d), .groups = "drop")
print(as.data.frame(by_year), row.names = FALSE)
