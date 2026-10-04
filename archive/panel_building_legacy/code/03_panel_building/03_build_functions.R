# =========================================================================================================
# 03_build_functions.R -- the shared facility x year panel recipe. All three sample panels (universe,
#   major_synmin, electric) are the SAME recipe run over a different facility filter; this file holds that
#   recipe once. The per-panel differences live in 03_build_parameters.R, and 03_build.R drives them.
#
#   Requires (in scope when build_panel() runs): YEARS (defined in 03_build_parameters.R) and the cleaned
#   event assets in data/processed/ + the spine in data/panels/.
#
#   COUNT SEMANTICS (every n_* counts ALL rows -- NO dedup). Duplicate load is surfaced, never removed:
#   for the families that actually carry duplicates (inspections, enforcement incl. formal/informal, certs)
#   two indicators accompany the headline count -- n_*_dup (event-key repeats, dup>0) and n_*_dup_exact
#   (byte-identical repeats, dup_exact==1). Distinct = count - dup. Violations & stacktests have zero dups
#   (asserted in their aggregators). penalty_amount sums ALL formal rows; penalty_amount_dup gives the dollar
#   inflation from event-key dups. EXCEPTION: the HPV interval flag (hpv_active) keeps the dup==0 filter --
#   it is a status flag, not a count, and duplicate spell rows carry the same interval (output-identical).
#   obs_source records why a facility-year's counts are 0 vs NA:
#     0   = OBSERVED but none of THIS measure -- a true zero. Observed via obs_source=="event" (>=1 event of
#           some measure) OR obs_source=="operating" (facility OPERATING in the wayback snapshot that year,
#           operating==1, even with zero events -- a known structural zero).
#     NA  = obs_source=="unobserved": no event AND not known-operating (incl. closed/CLS & pre-2015).
#   Extracted from the former standalone panel scripts, then de-deduplicated; see 03_build_functions_README.md.
# =========================================================================================================
library(readr); library(dplyr); library(tidyr); library(lubridate)

CLEAN  <- here::here("data/processed")

rd <- function(name, cols)                                    # read one clean asset, keep needed columns
  read_csv(file.path(CLEAN, paste0(name, ".csv.gz")), col_select = all_of(cols),
           col_types = cols(PGM_SYS_ID = col_character(), year = col_integer(),
                            dup = col_integer(), .default = col_character()), show_col_types = FALSE)
           # dup_exact is NOT listed explicitly, so it falls under .default = col_character() -- it's compared
           # against the string "1" (not the integer 1) everywhere below; consistent, but easy to break if a
           # future edit adds dup_exact to the explicit col_types list as an integer without updating the comparisons

# ---- per-source facility-year aggregators (event-level unless noted) -------------------------------------
# Inspections: FCE/PCE monitor-type split (overlap; need not sum) + conducting-agency split (partition).
#   All rows counted; n_inspections_dup / _dup_exact report the duplicate load.
agg_inspections <- function(ids) {
  rd("inspections", c("PGM_SYS_ID","year","dup","dup_exact","COMP_MONITOR_TYPE_DESC","STATE_EPA_FLAG")) |>
    filter(PGM_SYS_ID %in% ids, year %in% YEARS) |>    # restrict to this panel's facilities and the panel window
    group_by(PGM_SYS_ID, year) |> summarise(
      n_inspections = n(),                             # every row counted, dups included
      n_fce         = sum(grepl("^FCE", COMP_MONITOR_TYPE_DESC)),   # Full Compliance Evaluations
      n_pce         = sum(grepl("^PCE", COMP_MONITOR_TYPE_DESC)),   # Partial Compliance Evaluations (FCE/PCE overlap possible)
      n_insp_epa    = sum(STATE_EPA_FLAG == "E"),       # conducting-agency partition: EPA
      n_insp_state  = sum(STATE_EPA_FLAG == "S"),       # ...state
      n_insp_local  = sum(STATE_EPA_FLAG == "L"),       # ...local
      n_inspections_dup       = sum(dup > 0),           # event-key repeats (2nd+ occurrence within a key)
      n_inspections_dup_exact = sum(dup_exact == "1"), .groups = "drop")  # byte-identical repeats (string compare, see rd() above)
}

# Violations: HPV/FRV (high-priority = has an HPV day-zero date), program split (overlap), agency (partition).
agg_violations <- function(ids) {
  v <- rd("violations", c("PGM_SYS_ID","year","dup","HPV_DAYZERO_DATE","PROGRAM_CODES","AGENCY_TYPE_DESC")) |>
    filter(PGM_SYS_ID %in% ids, year %in% YEARS)
  stopifnot("violations: unexpected dup>0 rows -- counts would silently inflate; add a dup indicator (see build plan)" = all(v$dup == 0))
    # hard assertion, not a silent check -- if a future data refresh introduces event-key duplicates in
    # violations (which this aggregator does NOT report a dup count for, unlike inspections/enforcement/certs),
    # the whole panel build halts here rather than quietly under-reporting the duplicate load
  v |> mutate(hpv = !is.na(HPV_DAYZERO_DATE) & HPV_DAYZERO_DATE != "") |>   # high-priority violation = has a day-zero date
    group_by(PGM_SYS_ID, year) |> summarise(
      n_violations  = n(),
      n_hpv         = sum(hpv), n_frv = sum(!hpv),      # HPV vs "regular" (formal reportable violation) split, partitions n_violations
      # program flags keyed on PROGRAM_CODES (space-delimited, \b-bounded), not PROGRAM_DESCS text -- fixed
      # 2026-07-28 (see code/04_datasets/01_regulatory.R's identical fix): a text match on "New Source
      # Performance Standards" also matched CAANSPSM's DESC ("...(Non-Major)"), an accidental hit that happened
      # to land on the same grouping n_programs' prog_nsps already makes deliberately (CAANSPS + CAANSPSM) --
      # coded explicitly here so that agreement holds by design, not by phrasing luck.
      n_viol_sip    = sum(grepl("\\bCAASIP\\b", PROGRAM_CODES)),      # program-type flags, overlap possible
      n_viol_titlev = sum(grepl("\\bCAATVP\\b", PROGRAM_CODES)),
      n_viol_nsps   = sum(grepl("\\bCAANSPS\\b|\\bCAANSPSM\\b", PROGRAM_CODES)),
      n_viol_mact   = sum(grepl("\\bCAAMACT\\b", PROGRAM_CODES)),
      n_viol_fesop  = sum(grepl("\\bCAAFESOP\\b", PROGRAM_CODES)),
      n_viol_epa    = sum(AGENCY_TYPE_DESC %in% c("U.S. EPA", "Other Federal")),    # agency partition
      n_viol_state  = sum(AGENCY_TYPE_DESC %in% c("State", "State Contractor", "Other - State")),
      n_viol_local  = sum(AGENCY_TYPE_DESC %in% c("Local", "County", "Tribal")), .groups = "drop")
}

# Enforcement: formal + informal pooled. n_enforcement counts ALL rows; n_enforcement_dup / _dup_exact (and the
#   formal/informal splits) report the duplicate load. action-type buckets are EXACT ENF_TYPE_DESC matches
#   (unmapped types dropped -> need not sum); agency partition. n_penalties = count of formal rows carrying a
#   positive $ penalty (the count companion to penalty_amount's dollar sum -- see attach_penalty); PENALTY_AMOUNT
#   is read for formal only (informal has no such column). NB unlike penalty_amount (NA when none), n_penalties
#   is a COUNT_COL: observed facility-year with no penalty -> 0, unobserved -> NA (zero-vs-missing invariant).
agg_enforcement <- function(ids) {
  one <- function(name, kind, cols) rd(name, cols) |>
    filter(PGM_SYS_ID %in% ids, year %in% YEARS) |> mutate(kind = kind)   # tag each row formal/informal before pooling
  base     <- c("PGM_SYS_ID","year","dup","dup_exact","STATE_EPA_FLAG","ENF_TYPE_CODE","ENF_TYPE_DESC")
  formal   <- one("formal_actions",   "formal",   c(base, "PENALTY_AMOUNT")) |>
                mutate(penalty = parse_number(PENALTY_AMOUNT)) |> select(-PENALTY_AMOUNT)
                # parse_number() strips $ and , from a formatted currency string; malformed/blank -> NA
  informal <- one("informal_actions", "informal", base) |> mutate(penalty = NA_real_)   # informal actions carry no penalty field
  all <- bind_rows(formal, informal)                    # pooled formal+informal rows, one `kind` column distinguishes them
  all |> group_by(PGM_SYS_ID, year) |> summarise(
      n_enforcement    = n(),                            # every formal+informal row, dups included
      n_formal         = sum(kind == "formal"), n_informal = sum(kind == "informal"),
      # ENF_TYPE_CODE prefix, not exact ENF_TYPE_DESC match -- fixed 2026-07-28 (see
      # code/04_datasets/01_regulatory.R's identical fix): the DESC-exact version missed the 112(r)/MRR
      # expedited-settlement variants of the same 113D1 penalty action (codes 113D1E/113D1E1/113D1E2/113D1E3,
      # each with its own suffixed DESC text) -- ~3% of the true 113D1 family silently dropped. No other
      # ENF_TYPE_CODE starts with "113D1" (113D and 113DWD are distinct, unrelated actions).
      n_penalty_action = sum(grepl("^113D1", ENF_TYPE_CODE)),
      n_penalties      = sum(penalty > 0, na.rm = TRUE),           # formal rows with a positive $ penalty
      n_penalties_dup  = sum(penalty > 0 & dup > 0, na.rm = TRUE), # of those, event-key duplicates (dup>0)
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
      n_informal_dup_exact    = sum(kind == "informal" & dup_exact == "1"), .groups = "drop")
}

# Certifications: all rows counted; n_certs_dup / _dup_exact report the (heavy) duplicate load; self-reported-
#   deviation count. NB certs are ~81% event-key duplicates -- n_certs_dup will dominate n_certs.
agg_certs <- function(ids) {
  rd("certs", c("PGM_SYS_ID","year","dup","dup_exact","FACILITY_RPT_DEVIATION_FLAG")) |>
    filter(PGM_SYS_ID %in% ids, year %in% YEARS) |>
    group_by(PGM_SYS_ID, year) |> summarise(
      n_certs           = n(),
      n_certs_deviation = sum(FACILITY_RPT_DEVIATION_FLAG == "Y", na.rm = TRUE),
      n_certs_dup       = sum(dup > 0),
      n_certs_dup_exact = sum(dup_exact == "1"), .groups = "drop")
}

# Stack tests: all rows counted + Pass/Fail (Pending/Incomplete/N-A left uncounted -> need not sum).
agg_stacktests <- function(ids) {
  s <- rd("stacktests", c("PGM_SYS_ID","year","dup","AIR_STACK_TEST_STATUS_DESC")) |>
    filter(PGM_SYS_ID %in% ids, year %in% YEARS)
  stopifnot("stacktests: unexpected dup>0 rows -- counts would silently inflate; add a dup indicator (see build plan)" = all(s$dup == 0))
    # same defensive assertion pattern as agg_violations above
  s |> group_by(PGM_SYS_ID, year) |> summarise(
      n_stack_tests = n(),
      n_stack_pass  = sum(AIR_STACK_TEST_STATUS_DESC == "Pass", na.rm = TRUE),
      n_stack_fail  = sum(AIR_STACK_TEST_STATUS_DESC == "Fail", na.rm = TRUE), .groups = "drop")
}

# ---- HPV status (interval): in High-Priority-Violation status during the year? --------------------------
#   Built from the HPV SPELL [dayzero, spell_end], NOT the recorded-year count n_hpv. spell_end =
#   HPV_RESOLVED_DATE when resolved & valid; OPEN spells (unresolved) and bad-order rows (resolved < dayzero)
#   are DAY-ZERO-YEAR-ONLY (spell_end = Dec 31 of the day-zero year). Per facility-year we take the UNION of
#   overlap days across concurrent spells: hpv_active = any overlap; hpv_active_1mo = union > 30 days.
#   CAVEAT: HPV day-zero reporting ramps up over the window, so early-year 0s may reflect under-reporting.
attach_hpv_status <- function(panel, ids) {
  v <- rd("violations", c("PGM_SYS_ID","dup","HPV_DAYZERO_DATE","HPV_RESOLVED_DATE")) |>
    filter(dup == 0, PGM_SYS_ID %in% ids, !is.na(HPV_DAYZERO_DATE), HPV_DAYZERO_DATE != "") |>
    # dup == 0 filter here (unlike the count aggregators above) -- see file header EXCEPTION note: duplicate
    # spell rows would just describe the same interval twice, so dedup avoids double-counting overlap segments
    mutate(dayzero = mdy(HPV_DAYZERO_DATE, quiet = TRUE), resolved = mdy(HPV_RESOLVED_DATE, quiet = TRUE)) |>
    filter(!is.na(dayzero)) |>                          # a spell needs a valid start; unparseable day-zero dates are dropped
    mutate(spell_end = if_else(!is.na(resolved) & resolved >= dayzero, resolved,
                               make_date(year(dayzero), 12L, 31L)))
    # resolved date used ONLY if present and chronologically sane (>= dayzero); otherwise treat the spell as
    # open through the end of its day-zero year (a conservative single-year placeholder, not a claim the
    # violation actually resolved by Dec 31)
  seg <- lapply(YEARS, function(Y) {                    # for each panel year, find which spells overlap it
    ys <- make_date(Y, 1L, 1L); ye <- make_date(Y, 12L, 31L)
    hit <- v$dayzero <= ye & v$spell_end >= ys           # standard interval-overlap test
    if (!any(hit)) return(NULL)
    tibble(PGM_SYS_ID = v$PGM_SYS_ID[hit], year = Y,
           ov_start = pmax(v$dayzero[hit], ys), ov_end = pmin(v$spell_end[hit], ye))   # clip the spell to this year's bounds
  }) |> bind_rows()
  if (nrow(seg)) {
    hpv_year <- seg |> arrange(PGM_SYS_ID, year, ov_start) |> group_by(PGM_SYS_ID, year) |>
      # sorted by ov_start WITHIN each (facility, year) group -- required for the sequential merge below to be correct
      summarise(union_days = {                          # merge sorted intervals, sum inclusive day-lengths
        s <- as.integer(ov_start); e <- as.integer(ov_end); cur_s <- s[1]; cur_e <- e[1]; tot <- 0L
        if (length(s) > 1) for (i in 2:length(s)) {
          if (s[i] <= cur_e + 1L) cur_e <- max(cur_e, e[i])   # overlapping or adjacent (1-day gap) -- extend current run
          else { tot <- tot + (cur_e - cur_s + 1L); cur_s <- s[i]; cur_e <- e[i] }   # gap -- close current run, start a new one
        }
        tot + (cur_e - cur_s + 1L)                       # add the final (still-open) run's length
      }, .groups = "drop") |>
      transmute(PGM_SYS_ID, year, hpv_active = 1L, hpv_active_1mo = as.integer(union_days > 30))
    panel <- left_join(panel, hpv_year, by = c("PGM_SYS_ID", "year"))   # rows with no overlapping spell get NA here
  } else { panel$hpv_active <- NA_integer_; panel$hpv_active_1mo <- NA_integer_ }   # degenerate case: zero spells anywhere
  in_spell <- !is.na(panel$hpv_active)                  # year overlapped by a spell -> status KNOWN (=1)
  panel$hpv_active[!in_spell] <- 0L; panel$hpv_active_1mo[!in_spell] <- 0L   # provisionally: no known spell -> 0
  un <- is.na(panel$any_violations) & !in_spell         # unobserved facility-year & no spell -> unknown
  panel$hpv_active[un] <- NA_integer_; panel$hpv_active_1mo[un] <- NA_integer_   # ...override those specific rows back to NA
  panel
}

# ---- penalty: sum of FORMAL-action penalties per facility-year over ALL rows (no dedup) --------------------
#   penalty_amount = sum over every formal row; NA if the facility-year had NO formal action at all, OR if its
#                    formal action(s) summed to exactly $0 -- both collapse into NA. REVERSED 2026-07-28 (user
#                    decision; see briefs/panel/panel_construction_decisions.md): from 2026-07-27 to 2026-07-28
#                    this function instead coded 0 as a true zero (observed-but-no-dollars) and disagreed with
#                    the pre-2026-07-27 convention; reverted back per explicit instruction that "no formal
#                    action" and "formal action worth exactly $0" should NOT be distinguished from each other --
#                    both read as "no confirmed positive penalty dollars." Brought back in line with
#                    04_datasets/01_regulatory.R's identical reversal the same day. Consequence: penalty_amount
#                    is NO LONGER in COUNT_COLS below, so code_known_zeros()'s known-operating-zero fill does
#                    NOT touch it -- a known-operating, zero-event facility-year still reads NA here, not 0.
#   penalty_amount_dup = dollars contributed by event-key duplicate rows (dup>0) -- the inflation from not
#                        deduping. Same NA-collapse applied. (dup_exact dollars are 0: formal_actions has no
#                        byte-identical rows.)
#   NB per-facility amounts include broadcast multi-facility settlements -- do NOT sum across facilities.
attach_penalty <- function(panel, ids) {
  pen <- read_csv(file.path(CLEAN, "formal_actions.csv.gz"),
                  col_select = c(PGM_SYS_ID, year, dup, PENALTY_AMOUNT),
                  col_types = cols(PGM_SYS_ID = col_character(), year = col_integer(),
                                   dup = col_integer(), PENALTY_AMOUNT = col_character()),
                  show_col_types = FALSE) |>
    filter(PGM_SYS_ID %in% ids, year %in% YEARS) |>
    mutate(penalty = parse_number(PENALTY_AMOUNT)) |>
    group_by(PGM_SYS_ID, year) |> summarise(
      penalty_amount     = sum(penalty, na.rm = TRUE),   # total $ across ALL formal rows (dups included)
      penalty_amount_dup = sum(penalty[dup > 0], na.rm = TRUE), .groups = "drop")  # portion from event-key dup rows only
  panel <- left_join(panel, pen, by = c("PGM_SYS_ID", "year"))
  # `pen` only has a row when >=1 formal action exists, so penalty_amount is already NA here for every
  # facility-year without one (including known-operating zero-event years and years with only non-formal
  # events); explicitly zero out the remaining case -- formal action(s) that summed to exactly $0 -- so both
  # collapse into NA the same way.
  panel$penalty_amount[!is.na(panel$penalty_amount) & panel$penalty_amount == 0] <- NA_real_
  panel$penalty_amount_dup[!is.na(panel$penalty_amount_dup) & panel$penalty_amount_dup == 0] <- NA_real_
  panel
}

# ---- historical operating status + program-active flags from the ICIS-AIR wayback snapshots -------------
#   Year-varying (facility x year), 2015-2025 only; pre-2015 and unobserved facility-years stay NA (we cannot
#   assert a status where no snapshot exists). op_status_code = raw ICIS code; operating = code in {OPR,TMP,SEA}.
attach_wayback <- function(panel, ids) {
  fs <- read_csv(file.path(CLEAN, "wayback_facility_status.csv.gz"),
                 col_select = c(PGM_SYS_ID, year, op_status_code, operating),
                 col_types = cols(PGM_SYS_ID = col_character(), year = col_integer(),
                                  op_status_code = col_character(), operating = col_integer()),
                 show_col_types = FALSE) |> filter(PGM_SYS_ID %in% ids, year %in% YEARS)
  ps <- read_csv(file.path(CLEAN, "wayback_program_status.csv.gz"),
                 col_types = cols(PGM_SYS_ID = col_character(), year = col_integer(), .default = col_integer()),
                 show_col_types = FALSE) |> filter(PGM_SYS_ID %in% ids, year %in% YEARS)
  panel |> left_join(fs, by = c("PGM_SYS_ID","year")) |> left_join(ps, by = c("PGM_SYS_ID","year"))
    # both left_joins: facility-years with no wayback snapshot (pre-2015, or the facility just isn't in that
    # year's captured snapshot) simply get NA in every wayback-derived column, per the file's own contract
}

# ---- column inventory ----------------------------------------------------------------------------------
# facility attributes come straight from the spine
ATTR_COLS  <- c("REGISTRY_ID","FACILITY_NAME","STREET_ADDRESS","CITY","COUNTY_NAME","county_fips",
                "coord_no_county_match","coord_county_dist_km","coord_gross_error","STATE",
                "ZIP_CODE","EPA_REGION","latitude","longitude","NAICS_CODES","SIC_CODES","FACILITY_TYPE_CODE",
                "facility_type","AIR_POLLUTANT_CLASS_DESC","op_status_current_desc",
                "entered_year","exited_year","exit_source","left_censored","right_censored",
                "emits_voc","emits_pm","emits_co","emits_nox","emits_so2","emits_hap",
                "prog_sip","prog_titlev","prog_nsps","prog_mact","prog_gact","prog_neshap","prog_fesop",
                "prog_nsr","prog_psd","prog_cfc",
                "n_programs","program_begin_year")
# year-varying wayback status block (2015-2025; NA elsewhere)
WAYBACK_COLS <- c("op_status_code","operating",
                  "prog_sip_active","prog_titlev_active","prog_nsps_active","prog_mact_active",
                  "prog_gact_active","prog_neshap_active","prog_fesop_active","prog_nsr_active",
                  "prog_psd_active","prog_cfc_active")
# panel columns (all three sample panels share this same set)
PANEL_COLS <- c("PGM_SYS_ID","year",
                "n_inspections","n_fce","n_pce","n_insp_epa","n_insp_state","n_insp_local",
                "n_inspections_dup","n_inspections_dup_exact",
                "n_violations","n_hpv","n_frv","n_viol_sip","n_viol_titlev","n_viol_nsps","n_viol_mact",
                "n_viol_fesop","n_viol_epa","n_viol_state","n_viol_local",
                "n_enforcement","n_formal","n_informal","n_penalty_action","n_warning_letter",
                "n_admin_np","n_civil_judicial","n_nov","n_admin_order","n_enf_epa","n_enf_state","n_enf_local",
                "n_enforcement_dup","n_enforcement_dup_exact","n_formal_dup","n_formal_dup_exact",
                "n_informal_dup","n_informal_dup_exact","n_penalties","n_penalties_dup",
                "n_certs","n_certs_deviation","n_certs_dup","n_certs_dup_exact","n_stack_tests","n_stack_pass","n_stack_fail",
                "any_inspections","any_violations","any_enforcement","any_certs","obs_source",
                ATTR_COLS, WAYBACK_COLS, "hpv_active","hpv_active_1mo","penalty_amount","penalty_amount_dup")

# count/flag block that gets known-zero coding (all EVENT-derived measures incl. n_penalties/_dup + interval HPV
#   flags). penalty_amount/_dup are DELIBERATELY EXCLUDED (reversed 2026-07-28 -- see attach_penalty() above):
#   a known-operating, zero-event facility-year should read NA for penalty_amount (no confirmed formal action),
#   not 0, so it must not go through this fill.
COUNT_COLS <- c("n_inspections","n_fce","n_pce","n_insp_epa","n_insp_state","n_insp_local",
                "n_inspections_dup","n_inspections_dup_exact",
                "n_violations","n_hpv","n_frv","n_viol_sip","n_viol_titlev","n_viol_nsps","n_viol_mact",
                "n_viol_fesop","n_viol_epa","n_viol_state","n_viol_local",
                "n_enforcement","n_formal","n_informal","n_penalty_action","n_warning_letter",
                "n_admin_np","n_civil_judicial","n_nov","n_admin_order","n_enf_epa","n_enf_state","n_enf_local",
                "n_enforcement_dup","n_enforcement_dup_exact","n_formal_dup","n_formal_dup_exact",
                "n_informal_dup","n_informal_dup_exact","n_penalties","n_penalties_dup",
                "n_certs","n_certs_deviation","n_certs_dup","n_certs_dup_exact","n_stack_tests","n_stack_pass","n_stack_fail",
                "any_inspections","any_violations","any_enforcement","any_certs","hpv_active","hpv_active_1mo")

# ---- known-zero coding: a facility-year OPERATING in the wayback snapshot (operating==1) but with no events is
#   a TRUE structural zero, not "unobserved" -> fill NA->0 across COUNT_COLS for those rows. obs_source records
#   provenance: "event" (>=1 event, original semantics), "operating" (new wayback-based zeros), "unobserved" (NA).
#   Must run AFTER attach_wayback (needs `operating`) and after attach_hpv_status (so hpv_active exists).
code_known_zeros <- function(panel) {
  had_event <- !is.na(panel$n_inspections)                 # a count row existed => >=1 event of some measure
                                                             # (correct even for a facility-year whose only event
                                                             # was e.g. a violation: the full_join in build_panel
                                                             # below creates a row with n_inspections coalesced
                                                             # to 0, not NA, for that facility-year -- see build_panel)
  op        <- !is.na(panel$operating) & panel$operating == 1L
  fill      <- op & !had_event                             # known-operating, zero-event -> structural zeros
  panel |>
    mutate(obs_source = if_else(had_event, "event", if_else(op, "operating", "unobserved")),
           across(all_of(COUNT_COLS), \(x) if_else(fill, coalesce(x, 0L), x)))
           # only the `fill` rows get NA replaced with 0; rows already 0/positive, or genuinely unobserved
           # rows outside `fill`, pass through unchanged (unobserved rows correctly STAY NA here)
}

# ---- build_panel: the full facility x year panel for a facility frame `facs` --------------------------
#   facs : a filtered slice of the spine (one row per facility; supplies ids + attributes).
#   Balanced PGM_SYS_ID x YEARS rectangle; unobserved facility-years -> NA, observed-no-event -> 0 (P3/P4).
build_panel <- function(facs) {
  ids    <- facs$PGM_SYS_ID
  counts <- Reduce(\(x, y) full_join(x, y, by = c("PGM_SYS_ID", "year")),
                   list(agg_inspections(ids), agg_violations(ids), agg_enforcement(ids),
                        agg_certs(ids), agg_stacktests(ids)))
                   # full_join (not left/inner): a facility-year is kept if ANY of the 5 event families has a
                   # row for it, even if the others don't -- this is what makes had_event above correct
  cnt <- setdiff(names(counts), c("PGM_SYS_ID", "year"))
  counts[cnt] <- lapply(counts[cnt], \(x) as.integer(coalesce(x, 0L)))     # observed year, no event -> 0
  panel <- expand_grid(PGM_SYS_ID = ids, year = YEARS) |>                  # balanced rectangle: every facility x every panel year
    left_join(counts, by = c("PGM_SYS_ID", "year"))                        # unobserved facility-years -> NA
  for (m in c("inspections", "violations", "enforcement", "certs"))        # any_* flags (NA-safe)
    panel[[paste0("any_", m)]] <- as.integer(panel[[paste0("n_", m)]] > 0)
    # NA > 0 evaluates to NA, and as.integer(NA) is NA -- so any_* correctly stays NA for unobserved rows
    # rather than silently becoming 0 or FALSE
  panel <- panel |> left_join(facs, by = "PGM_SYS_ID") |>                  # attach static facility attributes
    attach_hpv_status(ids) |> attach_penalty(ids) |> attach_wayback(ids) |> code_known_zeros()
    # order is load-bearing per the file header: HPV needs any_violations (set above); wayback must run before
    # code_known_zeros (needs `operating`); code_known_zeros must run last (needs hpv_active + operating both present)
  panel |> select(all_of(PANEL_COLS)) |> arrange(PGM_SYS_ID, year)
}
