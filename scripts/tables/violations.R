# =========================================================================================================
# scripts/tables/violations.R — ICIS-AIR_VIOLATION_HISTORY summary section for docs/index.html.
# Ported from CAA_Project/data_docs/scripts/tables/table-violations.R (stats + curated content verbatim).
# =========================================================================================================
library(here); library(readr); library(dplyr); library(lubridate)

build_violations_section <- function() {
  viol <- read_csv(here("data/raw/ICIS-AIR_downloads/ICIS-AIR_VIOLATION_HISTORY.csv"), show_col_types = FALSE)
  n_obs <- nrow(viol); n_fac <- n_distinct(viol$PGM_SYS_ID)

  pct_miss <- function(x) paste0(round(sum(is.na(x)) / length(x) * 100, 1), "%")
  n_cats   <- function(x) n_distinct(x, na.rm = TRUE)
  top_vals <- function(df, var, n_top = 4) df |> filter(!is.na({{ var }})) |> count({{ var }}) |>
    arrange(desc(n)) |> slice_head(n = n_top) |> mutate(pct = n / nrow(df))
  date_stats <- function(date_col) {
    yr <- year(mdy(date_col)); n_miss <- sum(is.na(yr)); n_valid <- sum(!is.na(yr))
    list(n_miss = n_miss,
         miss_label = paste0(formatC(n_miss, format = "d", big.mark = ","), " (", round(n_miss / length(date_col) * 100, 1), "%)"),
         n = n_valid, min = min(yr, na.rm = TRUE), p5 = as.integer(quantile(yr, 0.05, na.rm = TRUE)),
         med = as.integer(median(yr, na.rm = TRUE)), p95 = as.integer(quantile(yr, 0.95, na.rm = TRUE)), max = max(yr, na.rm = TRUE))
  }

  # Categorical
  erp <- top_vals(viol, ENF_RESPONSE_POLICY_CODE, 2); erp_miss <- pct_miss(viol$ENF_RESPONSE_POLICY_CODE); erp_ncat <- n_cats(viol$ENF_RESPONSE_POLICY_CODE)
  atd_all <- viol |> filter(!is.na(AGENCY_TYPE_DESC)) |> count(AGENCY_TYPE_DESC) |> arrange(desc(n))
  atd_top <- atd_all |> slice_head(n = 3) |> mutate(pct = n / n_obs)
  atd_other <- atd_all |> slice_tail(n = nrow(atd_all) - 3)
  atd <- bind_rows(atd_top, tibble(AGENCY_TYPE_DESC = "Tribal/Other", n = sum(atd_other$n), pct = sum(atd_other$n) / n_obs))
  atd_miss <- pct_miss(viol$AGENCY_TYPE_DESC); atd_ncat <- n_cats(viol$AGENCY_TYPE_DESC)
  prc <- top_vals(viol, PROGRAM_CODES, 4);  prc_miss <- pct_miss(viol$PROGRAM_CODES);  prc_ncat <- n_cats(viol$PROGRAM_CODES)
  stc <- top_vals(viol, STATE_CODE, 4);     stc_miss <- pct_miss(viol$STATE_CODE);     stc_ncat <- n_cats(viol$STATE_CODE)
  alc <- top_vals(viol, AIR_LCON_CODE, 4);  alc_miss <- pct_miss(viol$AIR_LCON_CODE);  alc_ncat <- n_cats(viol$AIR_LCON_CODE)
  plc <- top_vals(viol, POLLUTANT_CODES, 4); plc_miss <- pct_miss(viol$POLLUTANT_CODES); plc_ncat <- n_cats(viol$POLLUTANT_CODES)

  # Dates
  frv <- date_stats(viol$EARLIEST_FRV_DETERM_DATE); hpv_dz <- date_stats(viol$HPV_DAYZERO_DATE)
  hpv_res <- date_stats(viol$HPV_RESOLVED_DATE); dscv <- date_stats(viol$DSCV_PATHWAY_DATE); nftc <- date_stats(viol$NFTC_PATHWAY_DATE)
  temp_min <- min(c(frv$min, hpv_dz$min, hpv_res$min, dscv$min, nftc$min))
  temp_max <- max(c(frv$max, hpv_dz$max, hpv_res$max, dscv$max, nftc$max))

  # Duplicates
  n_uniq_act <- n_distinct(viol$ACTIVITY_ID)
  vpf <- viol |> group_by(PGM_SYS_ID) |> summarise(n = n(), .groups = "drop")
  n_dup_pgm <- sum(duplicated(viol$PGM_SYS_ID)); n_multi <- sum(vpf$n > 1); max_viol <- max(vpf$n); med_viol <- as.integer(median(vpf$n))

  # ---- curated value labels ----
  prc_labels <- c("CAASIP"="State Implementation Plan","CAATVP"="Title V Permits","CAASIP CAATVP"="Both","CAANSPS"="New Source Performance Standards")
  prc_descs <- paste0(prc$PROGRAM_CODES, " - ", prc_labels[prc$PROGRAM_CODES])
  state_names <- c("CA"="California","PA"="Pennsylvania","TX"="Texas","OK"="Oklahoma","IL"="Illinois","NY"="New York","OH"="Ohio","LA"="Louisiana")
  stc_descs <- paste0(stc$STATE_CODE, " - ", state_names[stc$STATE_CODE])
  alc_labels <- c("SJV"="San Joaquin Valley (CA)","BAA"="Bay Area AQMD (CA)","SCA"="South Coast AQMD (CA)","PAM"="Pima County (AZ)")
  alc_descs <- paste0(alc$AIR_LCON_CODE, " - ", alc_labels[alc$AIR_LCON_CODE])
  plc_labels <- c("300000329"="FACIL (facility-level placeholder)","300000243"="VOCs","300000322"="Total Particulate Matter","300000328"="ADMIN (administrative)")
  plc_descs <- paste0(plc$POLLUTANT_CODES, " - ", plc_labels[plc$POLLUTANT_CODES])

  crows <- c(
    cat_var("ENF_RESPONSE_POLICY_CODE", "Severity classification. FRV = reportable but lower priority. HPV = most serious, triggers EPA tracking.", erp_miss, erp_ncat,
            c("FRV - Federally Reportable Violation","HPV - High Priority Violation"), erp$n, erp$pct),
    cat_var("AGENCY_TYPE_DESC", "Which level of government identified the violation.", atd_miss, atd_ncat,
            c("State","Local","U.S. EPA","Tribal/Other"), atd$n, atd$pct),
    cat_var("PROGRAM_CODES", "Which regulatory program(s) the violation falls under. Can list multiple programs.", prc_miss, prc_ncat, prc_descs, prc$n, prc$pct),
    cat_var("STATE_CODE", "State where the violation was identified.", stc_miss, stc_ncat, stc_descs, stc$n, stc$pct),
    cat_var("AIR_LCON_CODE", "Local control region code — the local air agency jurisdiction.", alc_miss, alc_ncat, alc_descs, alc$n, alc$pct),
    cat_var("POLLUTANT_CODES", "Pollutant code(s) associated with the violation. Can list multiple pollutants.", plc_miss, plc_ncat, plc_descs, plc$n, plc$pct)
  )

  # orange date table
  dv <- list(
    list(n="EARLIEST_FRV_DETERM_DATE", d="Date the violation was first formally determined.", s=frv),
    list(n="HPV_DAYZERO_DATE",         d="Date the HPV tracking clock started.",              s=hpv_dz),
    list(n="HPV_RESOLVED_DATE",        d="Date the HPV was resolved or closed.",              s=hpv_res),
    list(n="DSCV_PATHWAY_DATE",        d="Date the violation was discovered through the pathway process.", s=dscv),
    list(n="NFTC_PATHWAY_DATE",        d="Date the violation entered the no-further-tracking-required pathway.", s=nftc))
  nrows <- vapply(dv, function(v) num_row(v$n, v$d,
    c(v$s$miss_label, comma(v$s$n), v$s$min, v$s$p5, v$s$med, v$s$p95, v$s$max)), character(1))

  obs_line <- paste0("OBSERVATIONS: ", comma(n_obs), "  |  DISTINCT FACILITIES: ", comma(n_fac), "  |  TEMPORAL COVERAGE: ", temp_min, "–", temp_max)
  inv <- paste0("IDENTIFIERS: PGM_SYS_ID, ACTIVITY_ID, COMP_DETERMINATION_UID  |  ",
                "TEXT DECODES: PROGRAM_DESCS, POLLUTANT_DESCS (labels for PROGRAM_CODES, POLLUTANT_CODES)")

  sec(
    h_head("violations", "ICIS-Air Violations", "ICIS-AIR_VIOLATION_HISTORY.csv",
      paste0("Violations identified through compliance monitoring. Each record is a violation finding, ",
             "classified as either a Federally Reportable Violation (FRV) or a High Priority Violation (HPV). ",
             "HPVs are the most serious — they trigger EPA tracking and escalated oversight."),
      obs_line, inv),
    cat_table(crows),
    note(paste0("**HPVs (", round(erp$pct[erp$ENF_RESPONSE_POLICY_CODE == "HPV"] * 100), "%) are violations serious enough to warrant EPA ",
      "headquarters tracking. They include violations of applicable requirements, failure to report, and operating without a required permit. ",
      stc$STATE_CODE[1], " alone accounts for ", round(stc$pct[1] * 100), "% of all violation records.")),
    note(paste0("**AIR_LCON_CODE is ", alc_miss, " missing — only populated when a local agency has jurisdiction. ",
      round(plc$pct[1] * 100), "% of violations list FACIL as the pollutant code, a facility-level placeholder with no specific pollutant.")),
    num_table(c("Variable","% Missing","N","Min","P5","Median","P95","Max"), nrows),
    note(paste0("**Some date fields contain junk values (e.g., year ", frv$min, ", ", hpv_res$min, ", ", hpv_dz$min,
      ") — likely data entry errors. FRV determination dates are sparse before 2014 (AFS system was frozen Oct 2014). ",
      "HPV dates go back further because HPV history was migrated from the legacy system. ",
      round(hpv_dz$n_miss / n_obs * 100), "% of records have no HPV day-zero date because they are FRVs, not HPVs.")),
    note(paste0("**DSCV_PATHWAY_DATE (", round(dscv$n_miss / n_obs * 100), "% missing) and NFTC_PATHWAY_DATE (",
      round(nftc$n_miss / n_obs * 100), "% missing) track the violation's progress through EPA's enforcement response pathway. ",
      "Not all violations enter or complete the pathway.")),
    dupes(paste0("No exact duplicate rows. ACTIVITY_ID and COMP_DETERMINATION_UID are each fully unique (",
      comma(n_uniq_act), " distinct values). PGM_SYS_ID is not unique — ", comma(n_dup_pgm), " rows (",
      round(n_dup_pgm / n_obs * 100, 1), "%) share a facility with at least one other violation. ", comma(n_multi),
      " facilities have 2+ violations (max ", comma(max_viol), "; median ", med_viol,
      "). This is expected: repeat violators accumulate multiple records over time."))
  )
}
