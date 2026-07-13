# =========================================================================================================
# scripts/02_clean/03_enforcement.R -- clean ICIS-Air FORMAL + INFORMAL actions into the `enforcement` asset.
#   in : data/raw/ICIS-AIR_downloads/ICIS-AIR_{FORMAL,INFORMAL}_ACTIONS.csv
#   out: data/clean/enforcement.csv.gz  (one row per raw record; distinct actions = filter(dup == 0))
#
#   Formal and informal actions are pooled into one measure, tagged by `kind`. Date: formal =
#   SETTLEMENT_ENTERED_DATE, informal = ACHIEVED_DATE. `penalty` is parsed from PENALTY_AMOUNT on FORMAL
#   actions only (informal actions carry no penalty). NO deduplication: all rows kept, duplicates flagged
#   within (kind, PGM_SYS_ID, ENF_IDENTIFIER). NB a multi-facility settlement repeats one penalty across
#   co-defendant facilities -- sum penalties over dup == 0 and do not sum across facilities for a total.
# =========================================================================================================
source(here::here("R/clean.R"))

read_enf <- function(file, datecol, kind) {
  d <- read_csv(file.path(RAW, "ICIS-AIR_downloads", file),
    col_select = any_of(c("PGM_SYS_ID", "ENF_IDENTIFIER", "STATE_EPA_FLAG", "ENF_TYPE_DESC", datecol, "PENALTY_AMOUNT")),
    col_types = cols(.default = col_character()), show_col_types = FALSE)
  d |> mutate(kind = kind, date = mdy(.data[[datecol]], quiet = TRUE), year = year(date),
              penalty = if ("PENALTY_AMOUNT" %in% names(d)) parse_number(PENALTY_AMOUNT) else NA_real_)
}

d <- bind_rows(read_enf("ICIS-AIR_FORMAL_ACTIONS.csv",   "SETTLEMENT_ENTERED_DATE", "formal"),
               read_enf("ICIS-AIR_INFORMAL_ACTIONS.csv", "ACHIEVED_DATE",           "informal"))

n_in <- nrow(d)
d <- d |> filter(!is.na(PGM_SYS_ID), PGM_SYS_ID != "", !is.na(year))
cat(sprintf("  dropped %d of %d rows (%.1f%%) with no PGM_SYS_ID or unparseable date\n",
            n_in - nrow(d), n_in, 100 * (n_in - nrow(d)) / n_in))

d <- d |>
  transmute(PGM_SYS_ID, enf_identifier = ENF_IDENTIFIER, date, year, kind,
            agency = STATE_EPA_FLAG, enf_type = ENF_TYPE_DESC, penalty) |>
  add_dup_flags(c("kind", "PGM_SYS_ID", "enf_identifier"))

write_asset(d, "enforcement", dict = c(
  PGM_SYS_ID     = "ICIS-Air facility (program-system) id",
  enf_identifier = "enforcement action id (the event id, within kind)",
  date           = "action date (formal: SETTLEMENT_ENTERED_DATE; informal: ACHIEVED_DATE; parsed)",
  year           = "action calendar year",
  kind           = "formal | informal",
  agency         = "lead agency flag (STATE_EPA_FLAG)",
  enf_type       = "action type (ENF_TYPE_DESC)",
  penalty        = "monetary penalty (PENALTY_AMOUNT; FORMAL actions only, else NA)",
  dup            = "occurrence index within (kind, PGM_SYS_ID, enf_identifier); 0 = first row",
  dup_exact      = "1 if byte-identical (on kept columns) to an earlier row"
))
