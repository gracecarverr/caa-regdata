# =========================================================================================================
# code/04_datasets/04_hpv_active.R -- DATASET 2b: hpv_active. Facility x year. The directly-usable HPV status
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
#     is used only if its day-zero year is in [DZ_MIN, DZ_MAX] = [1970, 2025]. This removes clear typos: one
#     record (CAMDAM1489) has day-zero "11-05-0218" -- a mistyped 2018 -> parses to YEAR 218. Unscreened, that
#     spell runs 218->2021 and spuriously flags this facility HPV-active for 2005-2017 (+13 fac-yrs). The
#     screen is EXPLICIT and reported below (not left to a silent CSV date round-trip, which would drop it by
#     accident). Day-zero years > 2025 start after the window and never overlap it regardless.
#
#   ZERO-vs-NA (mirrors ds 0; the panel's rule) --
#     1  : an R2 spell covers the year (SPELL WINS even where ICIS_OBSERVED == 0 -- the spell interval is
#          direct evidence of HPV status in a year that may carry no new event).
#     0  : not covered, but the facility-year IS ICIS-observed (ICIS_OBSERVED == 1) -> a true "not in HPV status".
#     NA : not covered and NOT ICIS-observed -> unknown, same discipline as every ds 0 count.
# =========================================================================================================
library(readr); library(dplyr); library(tidyr); library(lubridate)
source(here::here("code/04_datasets/00_parameters.R"))

# ---- R2 spell -> covered facility-years -----------------------------------------------------------------
DZ_MIN <- 1970L; DZ_MAX <- 2025L                             # plausible day-zero year range (H4 screen)
# Dates read as CHARACTER and parsed with ymd() (the spell table stores ISO strings). ymd recognizes the
#   mistyped year-218 date exactly as diagnostic 09's mdy did, so the plausibility screen -- not a silent
#   col_date() round-trip failure -- is what excludes it.
s_all <- read_csv(file.path(DATASETS, "hpv_spells.csv.gz"),
                  col_select = c(PGM_SYS_ID, HPV_DAYZERO_DATE, HPV_RESOLVED_DATE, SPELL_STATUS),
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

cover <- bind_rows(lapply(YEARS, function(Y) {
  ys <- make_date(Y, 1L, 1L); ye <- make_date(Y, 12L, 31L)
  hit <- s$dz <= ye & s$end_cons >= ys
  if (any(hit)) tibble(PGM_SYS_ID = s$PGM_SYS_ID[hit], year = Y) else NULL
})) |> distinct() |> mutate(covered = 1L)

# ---- rectangle (ds 0 universe) + zero-vs-NA -------------------------------------------------------------
frs_ids <- read_csv(file.path(CLEAN, "facilities.csv.gz"),
                    col_types = cols_only(PGM_SYS_ID = col_character(), REGISTRY_ID = col_character()),
                    show_col_types = FALSE)
ids <- frs_ids$PGM_SYS_ID
obs <- read_csv(file.path(DATASETS, "regulatory.csv.gz"),
                col_select = c(PGM_SYS_ID, YEAR, ICIS_OBSERVED),
                col_types = cols(PGM_SYS_ID = col_character(), YEAR = col_integer(),
                                 ICIS_OBSERVED = col_integer()), show_col_types = FALSE) |>
  rename(year = YEAR, icis_observed = ICIS_OBSERVED)

ha <- expand_grid(PGM_SYS_ID = ids, year = YEARS) |>
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

write_dataset(ha, "hpv_active")                  # uppercases all columns on write (see 00_parameters.R)
cat(sprintf("hpv_active: %s rows | %s active (1) | %s not-active (0) | %s unknown (NA) | %s ever-active facilities\n",
            format(nrow(ha), big.mark = ","), format(sum(ha$hpv_active == 1, na.rm = TRUE), big.mark = ","),
            format(sum(ha$hpv_active == 0, na.rm = TRUE), big.mark = ","),
            format(sum(is.na(ha$hpv_active)), big.mark = ","),
            format(n_distinct(ha$PGM_SYS_ID[which(ha$hpv_active == 1L)]), big.mark = ",")))
