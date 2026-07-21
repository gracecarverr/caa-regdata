# =========================================================================================================
# code/04_datasets/01_regulatory.R -- DATASET 0: the regulatory dataset. Facility x year, built from the
#   raw ICIS-Air download and NOTHING ELSE. Every column here is either an ICIS event count or an ICIS
#   facility characteristic; no wayback status, no FRS coordinates, no Green Book attainment, no AFS. Those
#   live in datasets 1-5 and merge on PGM_SYS_ID (+ year).
#
#   in : data/processed/{inspections,violations,formal_actions,informal_actions,certs,stacktests}.csv.gz
#        data/processed/{facilities,pollutants,programs}.csv.gz
#   out: data/datasets/regulatory.csv.gz
#
#   UNIVERSE -- every PGM_SYS_ID in ICIS-AIR_FACILITIES (279,211), with NO ever-active screen. 51% of these
#     facilities have zero events in the window; they are kept deliberately (mostly operating minor sources --
#     the never-inspected population), and are all-NA here until dataset 1 supplies operating status.
#
#   ZERO-vs-NA (the load-bearing rule; see README) -- a facility-year is `icis_observed == 1` iff ICIS holds
#     >=1 row for it across ANY of the six event assets. That is within-ICIS evidence that the facility was in
#     the system and being tracked that year, so a count of 0 for some OTHER measure is a TRUE zero.
#     With NO record of any type, ICIS says nothing either way -> every count is NA (unknown, not zero).
#     We do NOT use operating status to code zeros -- that inference is dataset 1's job, kept out on purpose.
#
#   COUNT SEMANTICS -- every n_* counts ALL rows; nothing is deduped. Duplicate load is SURFACED via
#     n_*_dup (event-key repeats, dup>0) and n_*_dup_exact (byte-identical, dup_exact==1) for the families
#     that carry duplicates (inspections, enforcement incl. formal/informal, certs). Event-distinct =
#     count - dup. Violations and stack tests carry zero dups (asserted below).
# =========================================================================================================
library(readr); library(dplyr); library(tidyr)
source(here::here("code/04_datasets/00_parameters.R"))

rd <- function(name, cols)                                    # read one clean asset, keep needed columns
  read_csv(file.path(CLEAN, paste0(name, ".csv.gz")), col_select = all_of(cols),
           col_types = cols(PGM_SYS_ID = col_character(), year = col_integer(),
                            dup = col_integer(), .default = col_character()), show_col_types = FALSE)

FACILITY_TYPE <- c(POF = "Privately owned", COR = "Corporation", CNG = "County government",
                   CTG = "City government", FDF = "Federal facility", STF = "State facility",
                   DIS = "District", NON = "Non-classified")

# ---- facility characteristics (ICIS only) ---------------------------------------------------------------
# Current-snapshot attributes. ICIS carries no history for these, so they are time-invariant by construction
# and applied to all years -- an industry reclassification or ownership change is NOT visible (see README).
attrs <- read_csv(file.path(CLEAN, "facilities.csv.gz"),
                  col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  select(PGM_SYS_ID, REGISTRY_ID, FACILITY_NAME, STREET_ADDRESS, CITY, COUNTY_NAME, STATE, ZIP_CODE,
         EPA_REGION, NAICS_CODES, SIC_CODES, FACILITY_TYPE_CODE, AIR_POLLUTANT_CLASS_DESC,
         op_status_current_desc = AIR_OPERATING_STATUS_DESC) |>
  mutate(facility_type = unname(FACILITY_TYPE[FACILITY_TYPE_CODE]), .after = FACILITY_TYPE_CODE)
ids <- attrs$PGM_SYS_ID
stopifnot("facilities: PGM_SYS_ID is not unique -- the facility grain is broken" = !anyDuplicated(ids))

# emitted-pollutant profile: ever-reported, undated (ICIS gives no start/end) -> time-invariant flags.
emits <- read_csv(file.path(CLEAN, "pollutants.csv.gz"),
                  col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  group_by(PGM_SYS_ID) |> summarise(
    emits_voc = as.integer(any(grepl("VOLATILE ORGANIC", POLLUTANT_DESC, ignore.case = TRUE))),
    emits_pm  = as.integer(any(grepl("PARTICULATE MATTER", POLLUTANT_DESC, ignore.case = TRUE))),
    emits_co  = as.integer(any(grepl("carbon monoxide", POLLUTANT_DESC, ignore.case = TRUE))),
    emits_nox = as.integer(any(grepl("NITROGEN OXIDES", POLLUTANT_DESC, ignore.case = TRUE))),
    emits_so2 = as.integer(any(grepl("sulfur dioxide", POLLUTANT_DESC, ignore.case = TRUE))),
    emits_hap = as.integer(any(grepl("HAZARDOUS AIR POLLUTANT", POLLUTANT_DESC, ignore.case = TRUE))),
    .groups = "drop")

# program enrollment: EVER-enrolled and undated here. NB `program_begin_year` deliberately does NOT live in
# this dataset -- BEGIN_DATE is a facility-lifecycle proxy, so it belongs with the operating evidence (ds 1).
progs <- read_csv(file.path(CLEAN, "programs.csv.gz"),
                  col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  group_by(PGM_SYS_ID) |> summarise(
    prog_sip    = as.integer(any(PROGRAM_CODE == "CAASIP")),
    prog_titlev = as.integer(any(PROGRAM_CODE == "CAATVP")),
    prog_nsps   = as.integer(any(PROGRAM_CODE %in% c("CAANSPS", "CAANSPSM"))),
    prog_mact   = as.integer(any(PROGRAM_CODE == "CAAMACT")),
    prog_neshap = as.integer(any(PROGRAM_CODE == "CAANESH")),
    prog_fesop  = as.integer(any(PROGRAM_CODE == "CAAFESOP")),
    prog_nsr    = as.integer(any(PROGRAM_CODE == "CAANSR")),
    prog_psd    = as.integer(any(PROGRAM_CODE == "CAAPSD")),
    # prog_gact/prog_cfc (CAAGACTM/CAACFC) deliberately excluded per decision (2026-07-21) -- dropped to
    # match the 8-group allowlist now used in dataset 1's PROG_*_ACTIVE (O3). n_programs still counts every
    # PROGRAM_CODE including these two -- that column's scope is unchanged, only the per-program flags here.
    n_programs  = n_distinct(PROGRAM_CODE), .groups = "drop")

# ---- per-source facility-year aggregators ---------------------------------------------------------------
agg_inspections <- function() {
  rd("inspections", c("PGM_SYS_ID","year","dup","dup_exact","COMP_MONITOR_TYPE_DESC","STATE_EPA_FLAG")) |>
    filter(year %in% YEARS) |>
    group_by(PGM_SYS_ID, year) |> summarise(
      n_inspections = n(),
      n_fce         = sum(grepl("^FCE", COMP_MONITOR_TYPE_DESC)),
      n_pce         = sum(grepl("^PCE", COMP_MONITOR_TYPE_DESC)),
      n_insp_epa    = sum(STATE_EPA_FLAG == "E"),
      n_insp_state  = sum(STATE_EPA_FLAG == "S"),
      n_insp_local  = sum(STATE_EPA_FLAG == "L"),
      n_inspections_dup       = sum(dup > 0),
      n_inspections_dup_exact = sum(dup_exact == "1"), .groups = "drop")
}

agg_violations <- function() {
  v <- rd("violations", c("PGM_SYS_ID","year","dup","HPV_DAYZERO_DATE","PROGRAM_DESCS","AGENCY_TYPE_DESC")) |>
    filter(year %in% YEARS)
  stopifnot("violations: unexpected dup>0 rows -- counts would silently inflate" = all(v$dup == 0))
  v |> mutate(hpv = !is.na(HPV_DAYZERO_DATE) & HPV_DAYZERO_DATE != "") |>
    group_by(PGM_SYS_ID, year) |> summarise(
      n_violations  = n(),
      n_hpv         = sum(hpv), n_frv = sum(!hpv),
      n_viol_sip    = sum(grepl("State Implementation Plan", PROGRAM_DESCS)),
      n_viol_titlev = sum(grepl("Title V Permits", PROGRAM_DESCS)),
      n_viol_nsps   = sum(grepl("New Source Performance Standards", PROGRAM_DESCS)),
      n_viol_mact   = sum(grepl("MACT Standards", PROGRAM_DESCS)),
      n_viol_fesop  = sum(grepl("Federally-Enforceable State Operating Permit", PROGRAM_DESCS)),
      n_viol_epa    = sum(AGENCY_TYPE_DESC %in% c("U.S. EPA", "Other Federal")),
      n_viol_state  = sum(AGENCY_TYPE_DESC %in% c("State", "State Contractor", "Other - State")),
      n_viol_local  = sum(AGENCY_TYPE_DESC %in% c("Local", "County", "Tribal")), .groups = "drop")
}

# Enforcement: formal + informal pooled. penalty_amount is the facility-year DOLLAR sum over all formal rows;
#   the action-level detail (and the multi-facility settlement key) is dataset 3.
agg_enforcement <- function() {
  base     <- c("PGM_SYS_ID","year","dup","dup_exact","STATE_EPA_FLAG","ENF_TYPE_DESC")
  formal   <- rd("formal_actions", c(base, "PENALTY_AMOUNT")) |> filter(year %in% YEARS) |>
                mutate(kind = "formal", penalty = parse_number(PENALTY_AMOUNT)) |> select(-PENALTY_AMOUNT)
  informal <- rd("informal_actions", base) |> filter(year %in% YEARS) |>
                mutate(kind = "informal", penalty = NA_real_)
  bind_rows(formal, informal) |> group_by(PGM_SYS_ID, year) |> summarise(
      n_enforcement    = n(),
      n_formal         = sum(kind == "formal"), n_informal = sum(kind == "informal"),
      n_penalty_action = sum(ENF_TYPE_DESC == "CAA 113D1 Action For Penalty"),
      n_penalties      = sum(penalty > 0, na.rm = TRUE),
      n_penalties_dup  = sum(penalty > 0 & dup > 0, na.rm = TRUE),
      n_warning_letter = sum(ENF_TYPE_DESC == "Warning Letter"),
      n_admin_np       = sum(ENF_TYPE_DESC == "CAA 113A Admin Compliance Order (Non-Penalty)"),
      n_civil_judicial = sum(ENF_TYPE_DESC == "Civil Judicial Action"),
      n_nov            = sum(ENF_TYPE_DESC == "Notice of Violation"),
      n_admin_order    = sum(ENF_TYPE_DESC == "Administrative Order"),
      n_enf_epa        = sum(STATE_EPA_FLAG == "E"),
      n_enf_state      = sum(STATE_EPA_FLAG == "S"),
      n_enf_local      = sum(STATE_EPA_FLAG == "L"),
      n_enforcement_dup       = sum(dup > 0),
      n_enforcement_dup_exact = sum(dup_exact == "1"),
      n_formal_dup            = sum(kind == "formal"   & dup > 0),
      n_formal_dup_exact      = sum(kind == "formal"   & dup_exact == "1"),
      n_informal_dup          = sum(kind == "informal" & dup > 0),
      n_informal_dup_exact    = sum(kind == "informal" & dup_exact == "1"),
      # dollars: sum over ALL formal rows; _dup isolates the inflation from event-key duplicates.
      penalty_amount     = sum(penalty, na.rm = TRUE),
      penalty_amount_dup = sum(penalty[dup > 0], na.rm = TRUE), .groups = "drop")
}

agg_certs <- function() {
  rd("certs", c("PGM_SYS_ID","year","dup","dup_exact","FACILITY_RPT_DEVIATION_FLAG")) |>
    filter(year %in% YEARS) |>
    group_by(PGM_SYS_ID, year) |> summarise(
      n_certs           = n(),
      n_certs_deviation = sum(FACILITY_RPT_DEVIATION_FLAG == "Y", na.rm = TRUE),
      n_certs_dup       = sum(dup > 0),
      n_certs_dup_exact = sum(dup_exact == "1"), .groups = "drop")
}

agg_stacktests <- function() {
  s <- rd("stacktests", c("PGM_SYS_ID","year","dup","AIR_STACK_TEST_STATUS_DESC")) |> filter(year %in% YEARS)
  stopifnot("stacktests: unexpected dup>0 rows -- counts would silently inflate" = all(s$dup == 0))
  s |> group_by(PGM_SYS_ID, year) |> summarise(
      n_stack_tests = n(),
      n_stack_pass  = sum(AIR_STACK_TEST_STATUS_DESC == "Pass", na.rm = TRUE),
      n_stack_fail  = sum(AIR_STACK_TEST_STATUS_DESC == "Fail", na.rm = TRUE), .groups = "drop")
}

# ---- assemble -------------------------------------------------------------------------------------------
cat("aggregating ICIS event assets...\n")
counts <- Reduce(\(x, y) full_join(x, y, by = c("PGM_SYS_ID", "year")),
                 list(agg_inspections(), agg_violations(), agg_enforcement(),
                      agg_certs(), agg_stacktests())) |>
  filter(PGM_SYS_ID %in% ids)            # drop event rows whose facility is absent from ICIS-AIR_FACILITIES

# A row in `counts` == >=1 ICIS record of SOME type that facility-year == the observability rule.
COUNT_COLS <- setdiff(names(counts), c("PGM_SYS_ID", "year"))
counts[COUNT_COLS] <- lapply(counts[COUNT_COLS], \(x) coalesce(x, 0))   # observed, other measure absent -> 0

cat("building the facility x year rectangle...\n")
reg <- expand_grid(PGM_SYS_ID = ids, year = YEARS) |>
  left_join(counts, by = c("PGM_SYS_ID", "year")) |>                    # no record at all -> all NA
  mutate(icis_observed = as.integer(!is.na(n_inspections)), .after = year) |>
  left_join(attrs, by = "PGM_SYS_ID") |>
  left_join(emits, by = "PGM_SYS_ID") |>
  left_join(progs, by = "PGM_SYS_ID")

# A facility with no pollutant/program record has an ABSENT profile -> flags coalesce to 0 (time-invariant).
# n_programs is EXCLUDED: n_distinct(PROGRAM_CODE) is >=1 for any facility present in programs.csv.gz, so a
#   count of 0 never arises legitimately. A facility with no program association stays NA -- "not associated
#   with any program", distinct from the prog_* flags' "not enrolled in THIS program". So n_programs is
#   NA-able facility metadata, never 0.
PROFILE_COLS <- c(grep("^emits_", names(reg), value = TRUE),
                  grep("^prog_",  names(reg), value = TRUE))
reg <- reg |> mutate(across(all_of(PROFILE_COLS), \(x) as.integer(coalesce(x, 0L)))) |>
  arrange(PGM_SYS_ID, year)

# ---- invariants -----------------------------------------------------------------------------------------
stopifnot(
  "grain broken: PGM_SYS_ID x year is not unique"     = !anyDuplicated(reg[c("PGM_SYS_ID","year")]),
  "rectangle incomplete: rows != facilities x years"  = nrow(reg) == length(ids) * length(YEARS),
  "observability rule violated: observed row with NA count" =
    !any(reg$icis_observed == 1 & is.na(reg$n_violations)),
  "observability rule violated: unobserved row with non-NA count" =
    !any(reg$icis_observed == 0 & !is.na(reg$n_violations)))

write_dataset(reg, "regulatory")                 # uppercases all columns on write (see 00_parameters.R)
cat(sprintf("regulatory: %s rows | %d cols | %s facilities | %s observed facility-years (%.1f%%)\n",
            format(nrow(reg), big.mark = ","), ncol(reg), format(length(ids), big.mark = ","),
            format(sum(reg$icis_observed), big.mark = ","), 100 * mean(reg$icis_observed)))
