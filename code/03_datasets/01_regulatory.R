# =========================================================================================================
# code/04_datasets/01_regulatory.R -- DATASET 0: the regulatory dataset. Facility x year, built from the
#   raw ICIS-Air download and NOTHING ELSE. Every column here is either an ICIS event count or an ICIS
#   facility characteristic; no wayback status, no FRS coordinates, no AFS. Those live in other datasets
#   and merge on PGM_SYS_ID (+ year).
#
#   in : data/processed/{inspections,violations,formal_actions,informal_actions,certs,stacktests}.csv.gz
#        data/processed/{facilities,pollutants,programs}.csv.gz
#   out: data/datasets/regulatory.csv.gz
#
#   UNIVERSE -- every PGM_SYS_ID in ICIS-AIR_FACILITIES (279,665), with NO ever-active screen. 52.2% of these
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
source(here::here("code/04_datasets/00_parameters.R"))     # YEARS, CLEAN, DATASETS, write_dataset()

rd <- function(name, cols)                                    # read one clean asset, keep needed columns
  read_csv(file.path(CLEAN, paste0(name, ".csv.gz")), col_select = all_of(cols),
           col_types = cols(PGM_SYS_ID = col_character(), year = col_integer(),
                            dup = col_integer(), .default = col_character()), show_col_types = FALSE)
           # dup_exact stays character (.default) -- compared as the string "1" below, same convention as
           # code/03_panel_building/03_build_functions.R's identically-named rd() helper (independently
           # duplicated in each file rather than shared -- see the general architecture note at the end)

FACILITY_TYPE <- c(POF = "Privately owned", COR = "Corporation", CNG = "County government",
                   CTG = "Municipality", FDF = "Federal facility", STF = "State facility",
                   DIS = "District", NON = "Non-government", GOC = "GOCO (government-owned, contractor-operated)",
                   IND = "Individual", MXO = "Mixed ownership (public/private)",
                   MWD = "Municipal or water district", SDT = "School district", TRB = "Tribal government",
                   UNK = "Unknown")
                   # same lookup as 03_panel_building/00_spine.R -- all 15 official ICIS-Air codes (see that
                   # file's header comment for the source citation and the 558-facility gap this closed)

# ---- facility characteristics (ICIS only) ---------------------------------------------------------------
# Current-snapshot attributes. ICIS carries no history for these, so they are time-invariant by construction
# and applied to all years -- an industry reclassification or ownership change is NOT visible (see README).
attrs <- read_csv(file.path(CLEAN, "facilities.csv.gz"),
                  col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  select(PGM_SYS_ID, REGISTRY_ID, FACILITY_NAME, STREET_ADDRESS, CITY, COUNTY_NAME, STATE, ZIP_CODE,
         EPA_REGION, NAICS_CODES, SIC_CODES, FACILITY_TYPE_CODE, AIR_POLLUTANT_CLASS_DESC,
         op_status_current_desc = AIR_OPERATING_STATUS_DESC) |>
  mutate(facility_type = unname(FACILITY_TYPE[FACILITY_TYPE_CODE]), .after = FACILITY_TYPE_CODE)
ids <- attrs$PGM_SYS_ID                                # the FULL ICIS-AIR_FACILITIES universe -- no ever-active filter
stopifnot("facilities: PGM_SYS_ID is not unique -- the facility grain is broken" = !anyDuplicated(ids))

# emitted-pollutant profile: ever-reported, undated (ICIS gives no start/end) -> time-invariant flags.
source(here::here("code/04_datasets/hap_list_112b.R"))   # HAP_112B, HAP_COMPOUND_CLASS_PATTERNS
  # moved here from code/03_panel_building/ (now archived, see archive/panel_building_legacy/) --
  # this is the only remaining consumer of the HAP list going forward, since the new panel-building
  # pipeline (code/04_panel_building/) consumes EMITS_HAP from regulatory.csv.gz instead of
  # recomputing it itself
hap_cas <- HAP_112B$cas_number[!HAP_112B$is_compound_class]     # real CAS numbers on the current CAA
                                                                 # 112(b) list -- exact join key, not text
hap_class_regex <- paste(HAP_COMPOUND_CLASS_PATTERNS, collapse = "|")  # one combined pattern for the 17
                                                                 # CAS-"0" compound classes (no CAS to join on)

pollutants_raw <- read_csv(file.path(CLEAN, "pollutants.csv.gz"),
                  col_types = cols(.default = col_character()), show_col_types = FALSE)

emits <- pollutants_raw |>
  group_by(PGM_SYS_ID) |> summarise(
    # note: NOT filtered to `ids` first (unlike attrs/ids above) -- harmless, since the eventual left_join
    # below is FROM the ids-restricted rectangle, so any pollutant rows for facilities outside `ids` are
    # simply never matched; just wasted aggregation work on rows that can't affect the output
    # (?<!NON-) excludes POLLUTANT_CODE 300000310 "NON-VOLATILE ORGANIC COMPOUNDS" -- the opposite category,
    # which otherwise matches "VOLATILE ORGANIC" as a plain substring (found 2026-07-28, 49 facilities/54 rows)
    emits_voc = as.integer(any(grepl("(?<!NON-)VOLATILE ORGANIC", POLLUTANT_DESC, ignore.case = TRUE, perl = TRUE))),
    emits_pm  = as.integer(any(grepl("PARTICULATE MATTER", POLLUTANT_DESC, ignore.case = TRUE))),
    emits_co  = as.integer(any(grepl("carbon monoxide", POLLUTANT_DESC, ignore.case = TRUE))),
    emits_nox = as.integer(any(grepl("NITROGEN OXIDES", POLLUTANT_DESC, ignore.case = TRUE))),
    emits_so2 = as.integer(any(grepl("sulfur dioxide", POLLUTANT_DESC, ignore.case = TRUE))),
    # emits_hap: the UNION of three signals, not a replacement of the old rule -- checked empirically
    # (2026-07-28, see 00_spine.R's identical fix for the full derivation) that each catches facilities the
    # others miss:
    #  (1) umbrella-phrase match ("HAZARDOUS AIR POLLUTANT" in POLLUTANT_DESC) -- what the old rule used
    #      alone. Means something specific and real: ICIS lets a facility report an aggregate "TOTAL
    #      HAZARDOUS AIR POLLUTANTS (HAPS)" figure (no CAS -- a summary record, not a substance) instead
    #      of, or in addition to, itemizing individual HAP species.
    #  (2) CAS-number match against the official CAA 112(b) list (HAP_112B, hap_list_112b.R) -- catches
    #      facilities that itemize a named HAP species without ever reporting the (1) aggregate total.
    #      This is the coverage gap the old umbrella-only rule had.
    #  (3) name match against the 17 compound-class entries that have no single CAS to join on.
    # See dataset_construction_decisions.md for the full before/after facility counts.
    emits_hap = as.integer(any(grepl("HAZARDOUS AIR POLLUTANT", POLLUTANT_DESC, ignore.case = TRUE)) ||
                             any(trimws(CHEMICAL_ABSTRACT_SERVICE_NMBR) %in% hap_cas) ||
                             any(grepl(hap_class_regex, POLLUTANT_DESC, ignore.case = TRUE))),
    .groups = "drop")

# coverage diagnostic: how much of the raw pollutant record still falls outside all six categories after
# the emits_hap fix, so any residual gap is visible in the run log rather than silent
uncovered <- !(grepl("(?<!NON-)VOLATILE ORGANIC|PARTICULATE MATTER|NITROGEN OXIDES|carbon monoxide|sulfur dioxide|HAZARDOUS AIR POLLUTANT",
                     pollutants_raw$POLLUTANT_DESC, ignore.case = TRUE, perl = TRUE) |
               trimws(pollutants_raw$CHEMICAL_ABSTRACT_SERVICE_NMBR) %in% hap_cas |
               grepl(hap_class_regex, pollutants_raw$POLLUTANT_DESC, ignore.case = TRUE))
cat(sprintf("pollutants coverage: %d / %d rows (%.1f%%) match none of the six emits_* categories\n",
            sum(uncovered), length(uncovered), 100 * mean(uncovered)))

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
  v <- rd("violations", c("PGM_SYS_ID","year","dup","HPV_DAYZERO_DATE","PROGRAM_CODES","AGENCY_TYPE_DESC")) |>
    filter(year %in% YEARS)
  stopifnot("violations: unexpected dup>0 rows -- counts would silently inflate" = all(v$dup == 0))
  v |> mutate(hpv = !is.na(HPV_DAYZERO_DATE) & HPV_DAYZERO_DATE != "") |>
    group_by(PGM_SYS_ID, year) |> summarise(
      n_violations  = n(),
      n_hpv         = sum(hpv), n_frv = sum(!hpv),
      # program flags keyed on PROGRAM_CODES (space-delimited, \b-bounded), not PROGRAM_DESCS text -- a text
      # match on "New Source Performance Standards" also matched CAANSPSM's DESC ("...(Non-Major)"), an
      # accidental hit that happened to land on the same grouping progs() above makes deliberately
      # (CAANSPS + CAANSPSM); coded explicitly here so that agreement holds by design, not by phrasing luck.
      n_viol_sip    = sum(grepl("\\bCAASIP\\b", PROGRAM_CODES)),
      n_viol_titlev = sum(grepl("\\bCAATVP\\b", PROGRAM_CODES)),
      n_viol_nsps   = sum(grepl("\\bCAANSPS\\b|\\bCAANSPSM\\b", PROGRAM_CODES)),
      n_viol_mact   = sum(grepl("\\bCAAMACT\\b", PROGRAM_CODES)),
      n_viol_fesop  = sum(grepl("\\bCAAFESOP\\b", PROGRAM_CODES)),
      n_viol_epa    = sum(AGENCY_TYPE_DESC %in% c("U.S. EPA", "Other Federal")),
      n_viol_state  = sum(AGENCY_TYPE_DESC %in% c("State", "State Contractor", "Other - State")),
      n_viol_local  = sum(AGENCY_TYPE_DESC %in% c("Local", "County", "Tribal")), .groups = "drop")
}

# Enforcement: formal + informal pooled. penalty_amount is the facility-year DOLLAR sum over all formal rows;
#   the action-level detail (and the multi-facility settlement key) is dataset 3.
agg_enforcement <- function() {
  base     <- c("PGM_SYS_ID","year","dup","dup_exact","STATE_EPA_FLAG","ENF_TYPE_CODE","ENF_TYPE_DESC")
  formal   <- rd("formal_actions", c(base, "PENALTY_AMOUNT")) |> filter(year %in% YEARS) |>
                mutate(kind = "formal", penalty = parse_number(PENALTY_AMOUNT)) |> select(-PENALTY_AMOUNT)
  informal <- rd("informal_actions", base) |> filter(year %in% YEARS) |>
                mutate(kind = "informal", penalty = NA_real_)
  bind_rows(formal, informal) |> group_by(PGM_SYS_ID, year) |> summarise(
      n_enforcement    = n(),
      n_formal         = sum(kind == "formal"), n_informal = sum(kind == "informal"),
      # ENF_TYPE_CODE prefix, not exact ENF_TYPE_DESC match -- the DESC-exact version missed the 112(r)/MRR
      # expedited-settlement variants of the same 113D1 penalty action (codes 113D1E, 113D1E1, 113D1E2,
      # 113D1E3, each with its own suffixed DESC text): ~3% of the true 113D1 family (201/6,881 rows) was
      # silently dropped. No other ENF_TYPE_CODE starts with "113D1" (113D and 113DWD are distinct actions).
      n_penalty_action = sum(grepl("^113D1", ENF_TYPE_CODE)),
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
      # dollars: sum over ALL formal rows; _dup isolates the inflation from event-key duplicates. Both go
      # through the blanket coalesce(x, 0) below like every other COUNT_COLS measure, then get explicitly
      # recoded 0 -> NA further down (PENALTY_AMOUNT/_dup override, ~line 250) -- see that comment for why.
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
  # note: literal `0`, not `0L` -- integer count columns from n()/sum(logical) get silently promoted to
  # double here (same values, different storage type; invisible once round-tripped through write_csv, but an
  # inconsistency with 03_panel_building's equivalent step, which explicitly wraps in as.integer())

cat("building the facility x year rectangle...\n")
reg <- expand_grid(PGM_SYS_ID = ids, year = YEARS) |>          # balanced rectangle: every ICIS facility x every panel year
  left_join(counts, by = c("PGM_SYS_ID", "year")) |>                    # no record at all -> all NA
  mutate(icis_observed = as.integer(!is.na(n_inspections)), .after = year) |>
         # n_inspections used as the observability proxy; equally valid to use any other COUNT_COLS member,
         # since a `counts` row (if present at all) has EVERY count column non-NA after the coalesce above
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

# penalty_amount/_dup: NA whenever the facility-year had NO formal action at all, OR its formal action(s)
# summed to exactly $0 -- both collapse into NA (project decision, 2026-07-28; see
# dataset_construction_decisions.md). At this point both columns are 0 for every case except a genuinely
# unobserved facility-year (already NA from the rectangle join): "no formal action" (whether the year had
# other events or none at all) and "1+ formal actions all recorded $0" are indistinguishable from each other
# under the blanket COUNT_COLS coalesce above, so recoding literal 0 -> NA collapses them together as intended.
# Matches code/03_panel_building/03_build_functions.R's attach_penalty(), reversed the same day -- the two
# layers briefly agreed on the OPPOSITE convention (0 = true zero) as of 2026-07-27.
reg <- reg |> mutate(
  penalty_amount     = if_else(!is.na(penalty_amount)     & penalty_amount     == 0, NA_real_, penalty_amount),
  penalty_amount_dup = if_else(!is.na(penalty_amount_dup) & penalty_amount_dup == 0, NA_real_, penalty_amount_dup))

# ---- invariants -----------------------------------------------------------------------------------------
stopifnot(                                              # hard assertions -- any failure halts the build rather
                                                          # than shipping a dataset that violates its own contract
  "grain broken: PGM_SYS_ID x year is not unique"     = !anyDuplicated(reg[c("PGM_SYS_ID","year")]),
  "rectangle incomplete: rows != facilities x years"  = nrow(reg) == length(ids) * length(YEARS),
  "observability rule violated: observed row with NA count" =
    !any(reg$icis_observed == 1 & is.na(reg$n_violations)),
  "observability rule violated: unobserved row with non-NA count" =
    !any(reg$icis_observed == 0 & !is.na(reg$n_violations)))

# =========================================================================================================
# FLAGGED ISSUES
# =========================================================================================================
# (none currently -- the penalty_amount zero-vs-NA cross-file disagreement previously flagged here was
#  resolved 2026-07-28: both this file and 03_panel_building/03_build_functions.R now collapse "no formal
#  action" and "formal action worth exactly $0" into NA. See the override right after PROFILE_COLS above.)
# =========================================================================================================

write_dataset(reg, "regulatory")                 # uppercases all columns on write (see 00_parameters.R)
cat(sprintf("regulatory: %s rows | %d cols | %s facilities | %s observed facility-years (%.1f%%)\n",
            format(nrow(reg), big.mark = ","), ncol(reg), format(length(ids), big.mark = ","),
            format(sum(reg$icis_observed), big.mark = ","), 100 * mean(reg$icis_observed)))
