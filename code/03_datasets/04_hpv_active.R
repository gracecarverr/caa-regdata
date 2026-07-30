# =========================================================================================================
# code/03_datasets/04_hpv_active.R -- DATASET 2b: hpv_active. Facility x year. The directly-usable HPV status
#   flag, a deterministic R2 collapse of hpv_spells (dataset 2). Joins 1:1 to regulatory / operating.
#
#   in : data/datasets/hpv_spells.csv.gz, data/datasets/regulatory.csv.gz, data/processed/facilities.csv.gz
#   out: data/datasets/hpv_active.csv.gz
#
#   RULE R2 (chosen in diagnostic 09) -- a facility-year is HPV-active if the interval [day-zero, end] of ANY
#     spell overlaps it. end = resolved (closed spells); Dec-31 of the day-zero year (open / bad_order --
#     conservatively closed, NOT carried forward). missing_start spells have no interval -> excluded.
#
#   DAY-ZERO PLAUSIBILITY SCREEN (H4 says screening lives at the collapse, not in the spell table) -- a spell
#     is used only if its day-zero year is in [DZ_MIN, DZ_MAX] = [1970, 2025]. This targets clear typos: one
#     record (PGM_SYS_ID CAMDAM1489, ACTIVITY_ID 3602412694) has day-zero "11-05-0218" -- a mistyped 2018 --
#     which 03_hpv_spells.R's mdy() parses to YEAR 218. Unscreened, that spell would run 218->2021 and
#     spuriously flag this facility HPV-active for 2005-2017. In practice this record is NOT excluded via the
#     [1970,2025] range check at all -- see the CSV round-trip note just below, it's excluded via the
#     unparseable-date branch instead. Net effect on `cover`/`hpv_active` is identical either way (the spell
#     is dropped from `s`), but the mechanism isn't the range comparison the name of this section implies.
#     Day-zero years > 2025 start after the window and never overlap it regardless, so screening those out is
#     also inert for YEARS = 2005:2025 -- `dz <= ye` in the cover loop below would already exclude them (as
#     of 2026-07-27, 267 of the 268 currently-excluded spells are this inert >2025 case, 1 is CAMDAM1489).
#
#   ZERO-vs-NA (mirrors ds 0; the panel's rule) --
#     1  : an R2 spell covers the year (SPELL WINS even where ICIS_OBSERVED == 0 -- the spell interval is
#          direct evidence of HPV status in a year that may carry no new event).
#     0  : not covered, but the facility-year IS ICIS-observed (ICIS_OBSERVED == 1) -> a true "not in HPV status".
#     NA : not covered and NOT ICIS-observed -> unknown, same discipline as every ds 0 count.
# =========================================================================================================
library(readr); library(dplyr); library(tidyr); library(lubridate)
source(here::here("code/03_datasets/00_parameters.R"))

# ---- R2 spell -> covered facility-years -----------------------------------------------------------------
DZ_MIN <- 1970L; DZ_MAX <- 2025L                             # plausible day-zero year range (H4 screen)
                                                               # DZ_MAX again a hardcoded literal matching but
                                                               # not derived from max(YEARS) -- same drift risk
                                                               # noted for BEGIN_YEAR_MAX in 02_operating.R
# Dates read as CHARACTER and parsed with ymd() (the spell table stores ISO strings). CONFIRMED 2026-07-28:
#   for the year-218 case, this IS a silent CSV round-trip failure, not the plausibility screen. 03_hpv_spells.R's
#   mdy() parses "11-05-0218" to a Date with year 218; write_csv() serializes that Date as the string
#   "218-11-05" (3 digits, NOT zero-padded to 4); ymd("218-11-05") here then returns NA -- lubridate's ymd()
#   does not recognize a 3-digit year. So this record is excluded via the is.na(dz_year) branch of `keep`,
#   not via the dz_year >= DZ_MIN comparison the header comment above describes. Net effect on the output is
#   the same (the spell is dropped either way), but this is why dz_year is never actually seen < 1970 -- the
#   year-218 case shows up as unparseable instead. Verified directly: mdy("11-05-0218") |> as.character() ==
#   "218-11-05", and ymd("218-11-05") == NA.
s_all <- read_csv(file.path(DATASETS, "hpv_spells.csv.gz"),
                  col_select = c(PGM_SYS_ID, HPV_DAYZERO_DATE, HPV_RESOLVED_DATE, SPELL_STATUS),
                  # note the UPPERCASE column names -- hpv_spells.csv.gz was written by write_dataset() in
                  # 03_hpv_spells.R, which uppercases every column name on write (00_parameters.R)
                  col_types = cols(PGM_SYS_ID = col_character(), .default = col_character()),
                  show_col_types = FALSE) |>
  filter(SPELL_STATUS != "missing_start") |>                 # need an interval start
  mutate(dz = ymd(HPV_DAYZERO_DATE, quiet = TRUE), rs = ymd(HPV_RESOLVED_DATE, quiet = TRUE),
         dz_year = year(dz))
keep <- !is.na(s_all$dz_year) & s_all$dz_year >= DZ_MIN & s_all$dz_year <= DZ_MAX
cat(sprintf("day-zero screen [%d,%d]: %d of %d mappable spells excluded (implausible/unparseable day-zero year)\n",
            DZ_MIN, DZ_MAX, sum(!keep), length(keep)))
s <- s_all[keep, ] |>
  mutate(end_cons = if_else(SPELL_STATUS == "closed", rs,
                            make_date(dz_year, 12L, 31L)))    # open/bad_order -> day-zero-year-end

cover <- bind_rows(lapply(YEARS, function(Y) {                # for each panel year, which spells overlap it?
  ys <- make_date(Y, 1L, 1L); ye <- make_date(Y, 12L, 31L)
  hit <- s$dz <= ye & s$end_cons >= ys
  if (any(hit)) tibble(PGM_SYS_ID = s$PGM_SYS_ID[hit], year = Y) else NULL
})) |> distinct() |> mutate(covered = 1L)
  # distinct() is essential here: a facility with >1 spell overlapping the same year would otherwise produce
  # >1 (PGM_SYS_ID, year) row for that year -- distinct() collapses to one "covered" row per facility-year

# ---- rectangle (ds 0 universe) + zero-vs-NA -------------------------------------------------------------
frs_ids <- read_csv(file.path(CLEAN, "facilities.csv.gz"),
                    col_types = cols_only(PGM_SYS_ID = col_character(), REGISTRY_ID = col_character()),
                    show_col_types = FALSE)
ids <- frs_ids$PGM_SYS_ID
obs <- read_csv(file.path(DATASETS, "regulatory.csv.gz"),        # depends on 01_regulatory.R having already run
                col_select = c(PGM_SYS_ID, YEAR, ICIS_OBSERVED),
                col_types = cols(PGM_SYS_ID = col_character(), YEAR = col_integer(),
                                 ICIS_OBSERVED = col_integer()), show_col_types = FALSE) |>
  rename(year = YEAR, icis_observed = ICIS_OBSERVED)              # back to this file's internal lowercase convention

ha <- expand_grid(PGM_SYS_ID = ids, year = YEARS) |>              # balanced rectangle, same universe as ds 0
  left_join(cover, by = c("PGM_SYS_ID", "year")) |>
  left_join(obs,   by = c("PGM_SYS_ID", "year")) |>
  mutate(hpv_active = case_when(!is.na(covered)      ~ 1L,    # spell wins
                                icis_observed == 1L  ~ 0L,    # observed, no spell -> true zero
                                TRUE                 ~ NA_integer_)) |>  # unobserved -> unknown
  select(PGM_SYS_ID, year, hpv_active) |>
  left_join(frs_ids, by = "PGM_SYS_ID") |> relocate(REGISTRY_ID, .after = PGM_SYS_ID) |>
  arrange(PGM_SYS_ID, year)

# ---- invariants -----------------------------------------------------------------------------------------
covered_key <- paste(cover$PGM_SYS_ID, cover$year)
stopifnot(
  "grain broken: PGM_SYS_ID x year not unique"       = !anyDuplicated(ha[c("PGM_SYS_ID", "year")]),
  "rectangle incomplete: rows != facilities x years" = nrow(ha) == length(ids) * length(YEARS),
  "HPV_ACTIVE outside {0,1,NA}"                       = all(ha$hpv_active %in% c(0L, 1L) | is.na(ha$hpv_active)),
  "HPV_ACTIVE==1 but no covering spell"               =
    all(paste(ha$PGM_SYS_ID, ha$year)[which(ha$hpv_active == 1L)] %in% covered_key),
  "NA only where uncovered (covered year is never NA)"=
    !any(is.na(ha$hpv_active) & paste(ha$PGM_SYS_ID, ha$year) %in% covered_key))

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# 1. (DZ_MAX, ~line 29) A hardcoded literal matching but not derived from max(YEARS) -- same drift risk noted
#    for BEGIN_YEAR_MAX in 02_operating.R: the two would silently diverge if the analysis window is ever
#    extended without also updating this constant.
# 2. (CAMDAM1489 / ymd() round-trip, ~line 33) CONFIRMED 2026-07-28: the DAY-ZERO PLAUSIBILITY SCREEN section
#    above (line 12) describes this record as excluded by the [1970,2025] range check. It's actually excluded
#    via a silent CSV round-trip failure: 03_hpv_spells.R's mdy() parses "11-05-0218" to a Date with year 218,
#    write_csv() serializes it as "218-11-05" (3-digit year, not zero-padded), and ymd() here can't reparse a
#    3-digit year, so dz_year is NA rather than 218 -- excluded via is.na(dz_year), not dz_year < DZ_MIN. The
#    output (`cover`/`hpv_active`) is unaffected either way -- the spell is dropped from `s` regardless of
#    which branch of `keep` catches it -- but the mechanism the comments describe is wrong, and it's why
#    dz_year is never observed < 1970 despite this known bad record existing in the raw data.
# =========================================================================================================

write_dataset(ha, "hpv_active")                  # uppercases all columns on write (see 00_parameters.R)
cat(sprintf("hpv_active: %s rows | %s active (1) | %s not-active (0) | %s unknown (NA) | %s ever-active facilities\n",
            format(nrow(ha), big.mark = ","), format(sum(ha$hpv_active == 1, na.rm = TRUE), big.mark = ","),
            format(sum(ha$hpv_active == 0, na.rm = TRUE), big.mark = ","),
            format(sum(is.na(ha$hpv_active)), big.mark = ","),
            format(n_distinct(ha$PGM_SYS_ID[which(ha$hpv_active == 1L)]), big.mark = ",")))
