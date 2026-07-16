# =========================================================================================================
# code/diagnostics/tables/inspections.R — ICIS-AIR_FCES_PCES (compliance monitoring) summary section.
# Ported from CAA_Project/data_docs/scripts/tables/table-compliance.R (stats + curated content verbatim).
# =========================================================================================================
library(here); library(readr); library(dplyr); library(lubridate)

build_inspections_section <- function() {
  comp <- read_csv(here("data/raw/ICIS-AIR_downloads/ICIS-AIR_FCES_PCES.csv"), show_col_types = FALSE)
  n_obs <- nrow(comp); n_fac <- n_distinct(comp$PGM_SYS_ID)

  pct_miss <- function(x) paste0(round(sum(is.na(x)) / length(x) * 100, 1), "%")
  n_cats   <- function(x) n_distinct(x, na.rm = TRUE)
  top_vals <- function(df, var, n_top = 4) df |> filter(!is.na({{ var }})) |> count({{ var }}) |>
    arrange(desc(n)) |> slice_head(n = n_top) |> mutate(pct = n / nrow(df))

  cmt <- top_vals(comp, COMP_MONITOR_TYPE_CODE, 4); cmt_miss <- pct_miss(comp$COMP_MONITOR_TYPE_CODE); cmt_ncat <- n_cats(comp$COMP_MONITOR_TYPE_CODE)
  sef <- top_vals(comp, STATE_EPA_FLAG, 3);         sef_miss <- pct_miss(comp$STATE_EPA_FLAG);         sef_ncat <- n_cats(comp$STATE_EPA_FLAG)
  apd <- top_vals(comp, ACTIVITY_PURPOSE_DESC, 4);  apd_miss <- pct_miss(comp$ACTIVITY_PURPOSE_DESC);  apd_ncat <- n_cats(comp$ACTIVITY_PURPOSE_DESC)
  atc <- comp |> count(ACTIVITY_TYPE_CODE, ACTIVITY_TYPE_DESC) |> mutate(pct = n / n_obs) |> arrange(desc(n))
  atc_miss <- pct_miss(comp$ACTIVITY_TYPE_CODE); atc_ncat <- n_cats(comp$ACTIVITY_TYPE_CODE)
  prc <- top_vals(comp, PROGRAM_CODES, 4); prc_miss <- pct_miss(comp$PROGRAM_CODES); prc_ncat <- n_cats(comp$PROGRAM_CODES)

  aed_yr <- year(mdy(comp$ACTUAL_END_DATE)); aed_n <- sum(!is.na(aed_yr))
  aed <- list(min = min(aed_yr, na.rm = TRUE), p5 = as.integer(quantile(aed_yr, 0.05, na.rm = TRUE)),
              med = as.integer(median(aed_yr, na.rm = TRUE)), p95 = as.integer(quantile(aed_yr, 0.95, na.rm = TRUE)), max = max(aed_yr, na.rm = TRUE))
  n_junk_dates <- sum(!is.na(aed_yr) & (aed_yr < 1972 | aed_yr > 2026))

  dup_act <- comp |> group_by(ACTIVITY_ID) |> summarise(n = n(), .groups = "drop") |> filter(n > 1)
  n_dup_act_ids <- nrow(dup_act); n_dup_act_rows <- sum(dup_act$n - 1)
  cpf <- comp |> group_by(PGM_SYS_ID) |> summarise(n = n(), .groups = "drop")
  n_multi <- sum(cpf$n > 1); max_insp <- max(cpf$n); med_insp <- as.integer(median(cpf$n))

  cmt_labels <- c("FOO"="FCE On-Site","PFF"="PCE Off-Site","PCE"="PCE On-Site","POR"="PCE Record/Report Review")
  cmt_descs <- paste0(cmt$COMP_MONITOR_TYPE_CODE, " - ", cmt_labels[cmt$COMP_MONITOR_TYPE_CODE])

  crows <- c(
    cat_var("COMP_MONITOR_TYPE_CODE", "Type of compliance evaluation conducted.", cmt_miss, cmt_ncat, cmt_descs, cmt$n, cmt$pct),
    cat_var("STATE_EPA_FLAG", "Which agency conducted the inspection.", sef_miss, sef_ncat, c("S - State","L - Local","E - EPA"), sef$n, sef$pct),
    cat_var("ACTIVITY_PURPOSE_DESC", "Reason for the monitoring activity.", apd_miss, apd_ncat, apd$ACTIVITY_PURPOSE_DESC, apd$n, apd$pct),
    cat_var("ACTIVITY_TYPE_CODE", "Type of compliance activity. All records in this table are inspections/evaluations.", atc_miss, atc_ncat,
            paste0(atc$ACTIVITY_TYPE_CODE, " - ", atc$ACTIVITY_TYPE_DESC), atc$n, atc$pct),
    cat_var("PROGRAM_CODES", "Regulatory program(s) inspected. Can list multiple programs. Optional field.", prc_miss, prc_ncat,
            c("CAASIP - State Implementation Plan","CAATVP - Title V Permits","CAASIP, CAATVP - Both SIP & Title V","CAANSPS, CAASIP - NSPS & SIP"), prc$n, prc$pct)
  )
  nrows <- num_row("ACTUAL_END_DATE_YEAR", "Date the inspection was completed.",
                   c(pct_miss(comp$ACTUAL_END_DATE), comma(aed_n), aed$min, aed$p5, aed$med, aed$p95, aed$max))

  obs_line <- paste0("OBSERVATIONS: ", comma(n_obs), "  |  DISTINCT FACILITIES: ", comma(n_fac), "  |  TEMPORAL COVERAGE: ", aed$min, "–", aed$max)
  inv <- "IDENTIFIERS: PGM_SYS_ID, ACTIVITY_ID  |  DATE: ACTUAL_END_DATE  |  TEXT DECODE: COMP_MONITOR_TYPE_DESC (label for COMP_MONITOR_TYPE_CODE)"

  sec(
    h_head("inspections", "ICIS-Air Compliance Monitoring", "ICIS-AIR_FCES_PCES.csv",
      paste0("Compliance monitoring activities — inspections and evaluations conducted at regulated facilities. ",
             "Full Compliance Evaluations (FCEs) are comprehensive on-site inspections. Partial Compliance Evaluations ",
             "(PCEs) cover a subset of requirements and can be on-site or off-site (document review)."),
      obs_line, inv),
    cat_table(crows),
    note(paste0("**States conduct ", round(sef$pct[1] * 100), "% of all compliance monitoring. EPA conducts only ",
      round(sef$pct[sef$STATE_EPA_FLAG == "E"] * 100), "%, primarily for oversight or targeted enforcement. FCEs (",
      round(cmt$pct[1] * 100), "%) are the most thorough inspection type — a full review of the facility's compliance with all applicable requirements.")),
    note(paste0("**ACTIVITY_TYPE_CODE is 100% ", atc$ACTIVITY_TYPE_CODE[1], " (", atc$ACTIVITY_TYPE_DESC[1],
      ") — this table only contains inspection records. PROGRAM_CODES is ", prc_miss, " missing and ACTIVITY_PURPOSE_DESC is ",
      apd_miss, " missing — these are optional reporting fields under EPA's Minimum Data Requirements.")),
    num_table(c("Variable","% Missing","N","Min","P5","Median","P95","Max"), nrows),
    note(paste0("**", n_junk_dates, " records have junk dates outside the 1972-2026 range. 95% of inspections fall between ", aed$p5, " and ", aed$p95, ".")),
    dupes(paste0("No exact duplicate rows. ", n_dup_act_ids, " ACTIVITY_IDs (", comma(n_dup_act_rows),
      " rows, <0.1%) appear more than once — these share the same inspection event ID but may differ in PROGRAM_CODES or ",
      "ACTIVITY_PURPOSE_DESC, likely reflecting a single inspection covering multiple programs. Most facilities have multiple inspections over time: ",
      comma(n_multi), " facilities (", round(n_multi / n_fac * 100, 1), "%) have 2+ records (max ", comma(max_insp), "; median ", med_insp, ")."))
  )
}
