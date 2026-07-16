# =========================================================================================================
# 03_build_functions.R -- the shared facility x year panel recipe. All three sample panels (universe,
#   major_synmin, electric) are the SAME recipe run over a different facility filter (+ an optional
#   attainment-treatment attach for electric); this file holds that recipe once. The per-panel differences
#   live in 03_build_parameters.R, and 03_build.R drives them.
#
#   Requires (in scope when build_panel() runs): YEARS (defined in 03_build_parameters.R) and the cleaned
#   event assets in data/processed/ + the spine/attainment in data/panels/.
#
#   COUNT SEMANTICS (every n_* is EVENT-level, dup == 0, unless the name ends in _raw). obs_source records why
#   a facility-year's counts are 0 vs NA:
#     0   = OBSERVED but none of THIS measure -- a true zero. Observed via obs_source=="event" (>=1 event of
#           some measure) OR obs_source=="operating" (facility OPERATING in the wayback snapshot that year,
#           operating==1, even with zero events -- a known structural zero).
#     NA  = obs_source=="unobserved": no event AND not known-operating (incl. closed/CLS & pre-2015).
#   _raw columns count EVERY row incl. duplicate artifacts (n_certs_raw ~5x, n_enforcement_raw ~1.6x n_*).
#   Extracted verbatim from the former standalone panel scripts; see 03_build_functions_README.md.
# =========================================================================================================
library(readr); library(dplyr); library(tidyr); library(lubridate)

CLEAN  <- here::here("data/processed"); PANELS <- here::here("data/panels")

rd <- function(name, cols)                                    # read one clean asset, keep needed columns
  read_csv(file.path(CLEAN, paste0(name, ".csv.gz")), col_select = all_of(cols),
           col_types = cols(PGM_SYS_ID = col_character(), year = col_integer(),
                            dup = col_integer(), .default = col_character()), show_col_types = FALSE)

# ---- per-source facility-year aggregators (event-level unless noted) -------------------------------------
# Inspections: FCE/PCE monitor-type split (overlap; need not sum) + conducting-agency split (partition).
agg_inspections <- function(ids) {
  rd("inspections", c("PGM_SYS_ID","year","dup","COMP_MONITOR_TYPE_DESC","STATE_EPA_FLAG")) |>
    filter(PGM_SYS_ID %in% ids, year %in% YEARS, dup == 0) |>
    group_by(PGM_SYS_ID, year) |> summarise(
      n_inspections = n(),
      n_fce         = sum(grepl("^FCE", COMP_MONITOR_TYPE_DESC)),
      n_pce         = sum(grepl("^PCE", COMP_MONITOR_TYPE_DESC)),
      n_insp_epa    = sum(STATE_EPA_FLAG == "E"),
      n_insp_state  = sum(STATE_EPA_FLAG == "S"),
      n_insp_local  = sum(STATE_EPA_FLAG == "L"), .groups = "drop")
}

# Violations: HPV/FRV (high-priority = has an HPV day-zero date), program split (overlap), agency (partition).
agg_violations <- function(ids) {
  rd("violations", c("PGM_SYS_ID","year","dup","HPV_DAYZERO_DATE","PROGRAM_DESCS","AGENCY_TYPE_DESC")) |>
    filter(PGM_SYS_ID %in% ids, year %in% YEARS, dup == 0) |>
    mutate(hpv = !is.na(HPV_DAYZERO_DATE) & HPV_DAYZERO_DATE != "") |>
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

# Enforcement: formal + informal pooled. n_enforcement = distinct actions; n_enforcement_raw = all rows.
#   action-type buckets are EXACT ENF_TYPE_DESC matches (unmapped types dropped -> need not sum); agency partition.
agg_enforcement <- function(ids) {
  one <- function(name, kind) rd(name, c("PGM_SYS_ID","year","dup","STATE_EPA_FLAG","ENF_TYPE_DESC")) |>
    filter(PGM_SYS_ID %in% ids, year %in% YEARS) |> mutate(kind = kind)
  all <- bind_rows(one("formal_actions", "formal"), one("informal_actions", "informal"))
  raw <- count(all, PGM_SYS_ID, year, name = "n_enforcement_raw")
  all |> filter(dup == 0) |> group_by(PGM_SYS_ID, year) |> summarise(
      n_enforcement    = n(),
      n_formal         = sum(kind == "formal"), n_informal = sum(kind == "informal"),
      n_penalty_action = sum(ENF_TYPE_DESC == "CAA 113D1 Action For Penalty"),
      n_warning_letter = sum(ENF_TYPE_DESC == "Warning Letter"),
      n_admin_np       = sum(ENF_TYPE_DESC == "CAA 113A Admin Compliance Order (Non-Penalty)"),
      n_civil_judicial = sum(ENF_TYPE_DESC == "Civil Judicial Action"),
      n_nov            = sum(ENF_TYPE_DESC == "Notice of Violation"),
      n_admin_order    = sum(ENF_TYPE_DESC == "Administrative Order"),
      n_enf_epa        = sum(STATE_EPA_FLAG == "E"),
      n_enf_state      = sum(STATE_EPA_FLAG == "S"),
      n_enf_local      = sum(STATE_EPA_FLAG == "L"), .groups = "drop") |>
    full_join(raw, by = c("PGM_SYS_ID", "year"))
}

# Certifications: distinct certs + all-row raw + self-reported-deviation count.
agg_certs <- function(ids) {
  d   <- rd("certs", c("PGM_SYS_ID","year","dup","FACILITY_RPT_DEVIATION_FLAG")) |>
    filter(PGM_SYS_ID %in% ids, year %in% YEARS)
  raw <- count(d, PGM_SYS_ID, year, name = "n_certs_raw")
  d |> filter(dup == 0) |> group_by(PGM_SYS_ID, year) |> summarise(
      n_certs           = n(),
      n_certs_deviation = sum(FACILITY_RPT_DEVIATION_FLAG == "Y", na.rm = TRUE), .groups = "drop") |>
    full_join(raw, by = c("PGM_SYS_ID", "year"))
}

# Stack tests: distinct tests + Pass/Fail (Pending/Incomplete/N-A left uncounted -> need not sum).
agg_stacktests <- function(ids) {
  rd("stacktests", c("PGM_SYS_ID","year","dup","AIR_STACK_TEST_STATUS_DESC")) |>
    filter(PGM_SYS_ID %in% ids, year %in% YEARS, dup == 0) |>
    group_by(PGM_SYS_ID, year) |> summarise(
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
    mutate(dayzero = mdy(HPV_DAYZERO_DATE, quiet = TRUE), resolved = mdy(HPV_RESOLVED_DATE, quiet = TRUE)) |>
    filter(!is.na(dayzero)) |>
    mutate(spell_end = if_else(!is.na(resolved) & resolved >= dayzero, resolved,
                               make_date(year(dayzero), 12L, 31L)))
  seg <- lapply(YEARS, function(Y) {
    ys <- make_date(Y, 1L, 1L); ye <- make_date(Y, 12L, 31L)
    hit <- v$dayzero <= ye & v$spell_end >= ys
    if (!any(hit)) return(NULL)
    tibble(PGM_SYS_ID = v$PGM_SYS_ID[hit], year = Y,
           ov_start = pmax(v$dayzero[hit], ys), ov_end = pmin(v$spell_end[hit], ye))
  }) |> bind_rows()
  if (nrow(seg)) {
    hpv_year <- seg |> arrange(PGM_SYS_ID, year, ov_start) |> group_by(PGM_SYS_ID, year) |>
      summarise(union_days = {                          # merge sorted intervals, sum inclusive day-lengths
        s <- as.integer(ov_start); e <- as.integer(ov_end); cur_s <- s[1]; cur_e <- e[1]; tot <- 0L
        if (length(s) > 1) for (i in 2:length(s)) {
          if (s[i] <= cur_e + 1L) cur_e <- max(cur_e, e[i])
          else { tot <- tot + (cur_e - cur_s + 1L); cur_s <- s[i]; cur_e <- e[i] }
        }
        tot + (cur_e - cur_s + 1L)
      }, .groups = "drop") |>
      transmute(PGM_SYS_ID, year, hpv_active = 1L, hpv_active_1mo = as.integer(union_days > 30))
    panel <- left_join(panel, hpv_year, by = c("PGM_SYS_ID", "year"))
  } else { panel$hpv_active <- NA_integer_; panel$hpv_active_1mo <- NA_integer_ }
  in_spell <- !is.na(panel$hpv_active)                  # year overlapped by a spell -> status KNOWN (=1)
  panel$hpv_active[!in_spell] <- 0L; panel$hpv_active_1mo[!in_spell] <- 0L
  un <- is.na(panel$any_violations) & !in_spell         # unobserved facility-year & no spell -> unknown
  panel$hpv_active[un] <- NA_integer_; panel$hpv_active_1mo[un] <- NA_integer_
  panel
}

# ---- penalty: sum of FORMAL-action penalties per facility-year (dup==0); 0 / none / unobserved -> NA ----
#   NB per-facility amounts include broadcast multi-facility settlements -- do NOT sum across facilities.
attach_penalty <- function(panel, ids) {
  pen <- read_csv(file.path(CLEAN, "formal_actions.csv.gz"),
                  col_select = c(PGM_SYS_ID, year, dup, PENALTY_AMOUNT),
                  col_types = cols(PGM_SYS_ID = col_character(), year = col_integer(),
                                   dup = col_integer(), PENALTY_AMOUNT = col_character()),
                  show_col_types = FALSE) |>
    filter(dup == 0, PGM_SYS_ID %in% ids, year %in% YEARS) |>
    mutate(penalty = parse_number(PENALTY_AMOUNT)) |>
    group_by(PGM_SYS_ID, year) |> summarise(penalty_amount = sum(penalty, na.rm = TRUE), .groups = "drop")
  panel <- left_join(panel, pen, by = c("PGM_SYS_ID", "year"))
  panel$penalty_amount[is.na(panel$penalty_amount) | panel$penalty_amount == 0] <- NA_real_
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
}

# ---- treatment: PM2.5 (2012) nonattainment via the attainment asset (facility x year) ------------------
#   pm25_status = N (nonattainment) / M (maintenance) / NA (not in a PM2.5 NAA, or outside coverage)
#   pm25_area   = NAA area name (NA if none)
#   naa_pm25_2012 = 1 nonattainment / 0 maintenance-or-attainment / NA outside the PM2.5 coverage window or
#                   for an unplaceable facility (no coordinate).
#   any_naa     = naa_pm25_2012 (identical while PM2.5 is the only standard built).
#   ONLY attached for panels with treatment = TRUE (electric).
attach_pm25_attainment <- function(panel) {
  att   <- read_csv(file.path(PANELS, "attainment.csv.gz"),
                    col_select = c(PGM_SYS_ID, year, status, area_name),
                    col_types = cols(PGM_SYS_ID = col_character(), year = col_integer(), .default = col_guess()),
                    show_col_types = FALSE)
  cover <- range(att$year)                                                  # PM2.5 snapshot window
  panel |>
    left_join(transmute(att, PGM_SYS_ID, year, pm25_status = status, pm25_area = area_name),
              by = c("PGM_SYS_ID", "year")) |>
    mutate(naa_pm25_2012 = if_else(!(year >= cover[1] & year <= cover[2]) | is.na(latitude) | is.na(longitude),
                                   NA_integer_,
                                   if_else(is.na(pm25_status), 0L, as.integer(pm25_status == "N"))),
           any_naa = naa_pm25_2012)
}

# ---- column inventory ----------------------------------------------------------------------------------
# facility attributes come straight from the spine
ATTR_COLS  <- c("REGISTRY_ID","FACILITY_NAME","STREET_ADDRESS","CITY","COUNTY_NAME","county_fips","STATE",
                "ZIP_CODE","EPA_REGION","latitude","longitude","NAICS_CODES","SIC_CODES","FACILITY_TYPE_CODE",
                "facility_type","AIR_POLLUTANT_CLASS_DESC","op_status_current_desc",
                "entered_year","exited_year","exit_source","left_censored","right_censored",
                "emits_voc","emits_pm","emits_co","emits_nox","emits_so2","emits_hap",
                "prog_sip","prog_titlev","prog_nsps","prog_mact","prog_neshap","prog_fesop","prog_nsr","prog_psd","n_programs")
# year-varying wayback status block (2015-2025; NA elsewhere)
WAYBACK_COLS <- c("op_status_code","operating",
                  "prog_sip_active","prog_titlev_active","prog_nsps_active","prog_mact_active",
                  "prog_neshap_active","prog_fesop_active","prog_nsr_active","prog_psd_active")
# base panel columns (universe / major_synmin); electric appends TREATMENT_COLS
PANEL_COLS <- c("PGM_SYS_ID","year",
                "n_inspections","n_fce","n_pce","n_insp_epa","n_insp_state","n_insp_local",
                "n_violations","n_hpv","n_frv","n_viol_sip","n_viol_titlev","n_viol_nsps","n_viol_mact",
                "n_viol_fesop","n_viol_epa","n_viol_state","n_viol_local",
                "n_enforcement","n_enforcement_raw","n_formal","n_informal","n_penalty_action","n_warning_letter",
                "n_admin_np","n_civil_judicial","n_nov","n_admin_order","n_enf_epa","n_enf_state","n_enf_local",
                "n_certs","n_certs_raw","n_certs_deviation","n_stack_tests","n_stack_pass","n_stack_fail",
                "any_inspections","any_violations","any_enforcement","any_certs","obs_source",
                ATTR_COLS, WAYBACK_COLS, "hpv_active","hpv_active_1mo","penalty_amount")
TREATMENT_COLS <- c("pm25_status","pm25_area","naa_pm25_2012","any_naa")

# count/flag block that gets known-zero coding (all EVENT-derived measures + interval HPV flags; NOT penalty)
COUNT_COLS <- c("n_inspections","n_fce","n_pce","n_insp_epa","n_insp_state","n_insp_local",
                "n_violations","n_hpv","n_frv","n_viol_sip","n_viol_titlev","n_viol_nsps","n_viol_mact",
                "n_viol_fesop","n_viol_epa","n_viol_state","n_viol_local",
                "n_enforcement","n_enforcement_raw","n_formal","n_informal","n_penalty_action","n_warning_letter",
                "n_admin_np","n_civil_judicial","n_nov","n_admin_order","n_enf_epa","n_enf_state","n_enf_local",
                "n_certs","n_certs_raw","n_certs_deviation","n_stack_tests","n_stack_pass","n_stack_fail",
                "any_inspections","any_violations","any_enforcement","any_certs","hpv_active","hpv_active_1mo")

# ---- known-zero coding: a facility-year OPERATING in the wayback snapshot (operating==1) but with no events is
#   a TRUE structural zero, not "unobserved" -> fill NA->0 across COUNT_COLS for those rows. obs_source records
#   provenance: "event" (>=1 event, original semantics), "operating" (new wayback-based zeros), "unobserved" (NA).
#   Must run AFTER attach_wayback (needs `operating`) and after attach_hpv_status (so hpv_active exists).
code_known_zeros <- function(panel) {
  had_event <- !is.na(panel$n_inspections)                 # a count row existed => >=1 event of some measure
  op        <- !is.na(panel$operating) & panel$operating == 1L
  fill      <- op & !had_event                             # known-operating, zero-event -> structural zeros
  panel |>
    mutate(obs_source = if_else(had_event, "event", if_else(op, "operating", "unobserved")),
           across(all_of(COUNT_COLS), \(x) if_else(fill, coalesce(x, 0L), x)))
}

# ---- build_panel: the full facility x year panel for a facility frame `facs` --------------------------
#   facs      : a filtered slice of the spine (one row per facility; supplies ids + attributes).
#   treatment : FALSE (universe, major_synmin) or TRUE (electric -> attach PM2.5 attainment + 4 treatment cols).
#   Balanced PGM_SYS_ID x YEARS rectangle; unobserved facility-years -> NA, observed-no-event -> 0 (P3/P4).
build_panel <- function(facs, treatment = FALSE) {
  ids    <- facs$PGM_SYS_ID
  counts <- Reduce(\(x, y) full_join(x, y, by = c("PGM_SYS_ID", "year")),
                   list(agg_inspections(ids), agg_violations(ids), agg_enforcement(ids),
                        agg_certs(ids), agg_stacktests(ids)))
  cnt <- setdiff(names(counts), c("PGM_SYS_ID", "year"))
  counts[cnt] <- lapply(counts[cnt], \(x) as.integer(coalesce(x, 0L)))     # observed year, no event -> 0
  panel <- expand_grid(PGM_SYS_ID = ids, year = YEARS) |>                  # balanced rectangle
    left_join(counts, by = c("PGM_SYS_ID", "year"))                        # unobserved facility-years -> NA
  for (m in c("inspections", "violations", "enforcement", "certs"))        # any_* flags (NA-safe)
    panel[[paste0("any_", m)]] <- as.integer(panel[[paste0("n_", m)]] > 0)
  panel <- panel |> left_join(facs, by = "PGM_SYS_ID") |>
    attach_hpv_status(ids) |> attach_penalty(ids) |> attach_wayback(ids) |> code_known_zeros()
  cols <- PANEL_COLS
  if (treatment) { panel <- attach_pm25_attainment(panel); cols <- c(PANEL_COLS, TREATMENT_COLS) }
  panel |> select(all_of(cols)) |> arrange(PGM_SYS_ID, year)
}
