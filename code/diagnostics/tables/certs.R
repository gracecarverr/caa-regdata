# =========================================================================================================
# code/diagnostics/tables/certs.R — ICIS-AIR_TITLEV_CERTS summary section.
# Ported from CAA_Project/data_docs/scripts/tables/table-titlev-certs.R (verbatim stats + content).
# =========================================================================================================
library(here); library(readr); library(dplyr); library(lubridate)

build_certs_section <- function() {
  tv <- read_csv(here("data/raw/ICIS-AIR_downloads/ICIS-AIR_TITLEV_CERTS.csv"), show_col_types = FALSE)
  n_obs <- nrow(tv); n_fac <- n_distinct(tv$PGM_SYS_ID)

  pct_miss <- function(x) paste0(round(sum(is.na(x)) / length(x) * 100, 1), "%")
  n_cats   <- function(x) n_distinct(x, na.rm = TRUE)
  top_vals <- function(df, var, n_top = 4) df |> filter(!is.na({{ var }})) |> count({{ var }}) |>
    arrange(desc(n)) |> slice_head(n = n_top) |> mutate(pct = n / nrow(df))

  cmt <- tv |> count(COMP_MONITOR_TYPE_CODE, COMP_MONITOR_TYPE_DESC) |> mutate(pct = n / n_obs) |> arrange(desc(n))
  cmt_miss <- pct_miss(tv$COMP_MONITOR_TYPE_CODE); cmt_ncat <- n_cats(tv$COMP_MONITOR_TYPE_CODE)
  sef <- top_vals(tv, STATE_EPA_FLAG, 3); sef_miss <- pct_miss(tv$STATE_EPA_FLAG); sef_ncat <- n_cats(tv$STATE_EPA_FLAG)
  dev <- top_vals(tv, FACILITY_RPT_DEVIATION_FLAG, 2); dev_miss <- pct_miss(tv$FACILITY_RPT_DEVIATION_FLAG); dev_ncat <- n_cats(tv$FACILITY_RPT_DEVIATION_FLAG)

  aed_yr <- year(mdy(tv$ACTUAL_END_DATE)); aed_n_miss <- sum(is.na(tv$ACTUAL_END_DATE)); aed_n <- sum(!is.na(aed_yr))
  aed <- list(min = min(aed_yr, na.rm = TRUE), p5 = as.integer(quantile(aed_yr, 0.05, na.rm = TRUE)),
              med = as.integer(median(aed_yr, na.rm = TRUE)), p95 = as.integer(quantile(aed_yr, 0.95, na.rm = TRUE)), max = max(aed_yr, na.rm = TRUE))
  n_junk_dates <- sum(!is.na(aed_yr) & (aed_yr < 1990 | aed_yr > 2027))
  n_dev_yes <- sum(tv$FACILITY_RPT_DEVIATION_FLAG == "Y", na.rm = TRUE); n_dev_no <- sum(tv$FACILITY_RPT_DEVIATION_FLAG == "N", na.rm = TRUE)
  pct_dev <- round(n_dev_yes / (n_dev_yes + n_dev_no) * 100, 1)

  n_exact_dup <- sum(duplicated(tv)); n_dup_act <- sum(duplicated(tv$ACTIVITY_ID)); n_distinct_act <- n_distinct(tv$ACTIVITY_ID)
  fpf <- tv |> group_by(PGM_SYS_ID) |> summarise(n = n(), .groups = "drop")
  n_multi <- sum(fpf$n > 1); max_certs <- max(fpf$n); med_certs <- as.integer(median(fpf$n))
  certs_per_yr <- tv |> mutate(year = year(mdy(ACTUAL_END_DATE))) |> filter(!is.na(year), year >= 1990, year <= 2026) |>
    group_by(PGM_SYS_ID, year) |> summarise(n = n(), .groups = "drop")
  n_multi_per_yr <- sum(certs_per_yr$n > 1)

  crows <- c(
    cat_var("COMP_MONITOR_TYPE_CODE", "Type of compliance monitoring. All records are Title V ACC reviews.", cmt_miss, cmt_ncat,
            paste0(cmt$COMP_MONITOR_TYPE_CODE, " - ", cmt$COMP_MONITOR_TYPE_DESC), cmt$n, cmt$pct),
    cat_var("STATE_EPA_FLAG", "Which agency received and reviewed the certification.", sef_miss, sef_ncat, c("S - State","L - Local","E - EPA"), sef$n, sef$pct),
    cat_var("FACILITY_RPT_DEVIATION_FLAG", "Whether the facility reported any deviations from permit conditions in its certification.", dev_miss, dev_ncat,
            c("N - No deviations reported","Y - Deviations reported"), dev$n, dev$pct)
  )
  nrows <- num_row("ACTUAL_END_DATE_YEAR", "Date the certification was received or reviewed.",
                   c(paste0(comma(aed_n_miss), " records (", round(aed_n_miss / n_obs * 100, 1), "%)"), comma(aed_n), aed$min, aed$p5, aed$med, aed$p95, aed$max))

  obs_line <- paste0("OBSERVATIONS: ", comma(n_obs), "  |  DISTINCT FACILITIES: ", comma(n_fac), "  |  TEMPORAL COVERAGE: ", aed$min, "–", aed$max)
  inv <- "IDENTIFIERS: PGM_SYS_ID, ACTIVITY_ID  |  DATE: ACTUAL_END_DATE"

  sec(
    h_head("certs", "ICIS-Air Title V Certifications", "ICIS-AIR_TITLEV_CERTS.csv",
      paste0("Annual compliance certifications submitted by facilities holding Title V operating permits. Title V requires major sources ",
             "to certify their compliance status each year. Each row is one certification receipt/review event."),
      obs_line, inv),
    cat_table(crows),
    note(paste0("**COMP_MONITOR_TYPE_CODE is 100% TVA (Title V ACC Receipt/Review) — this table only contains certification records. ",
      "FACILITY_RPT_DEVIATION_FLAG is ", dev_miss, " missing. Among records with a value, ", pct_dev, "% report deviations from permit conditions.")),
    num_table(c("Variable","% Missing","N","Min","P5","Median","P95","Max"), nrows),
    note(paste0("**", n_junk_dates, " records have dates outside the 1990-2027 range. Title V was created by the 1990 CAA amendments, ",
      "so certifications before 1990 are data artifacts. 95% of certifications fall between ", aed$p5, " and ", aed$p95, ".")),
    dupes(paste0(comma(n_exact_dup), " exact duplicate rows (", round(n_exact_dup / n_obs * 100, 1), "%). ACTIVITY_ID has ", comma(n_dup_act),
      " duplicate values (", comma(n_distinct_act), " distinct). Multiple rows per ACTIVITY_ID likely reflect the same certification event ",
      "reviewed by different agencies or recorded under different flags. ", comma(n_multi), " facilities (", round(n_multi / n_fac * 100, 1),
      "%) have 2+ certification records (max ", comma(max_certs), "; median ", med_certs, "). This is expected — Title V requires annual certifications, ",
      "so a facility operating for 20 years should have ~20 records. ", comma(n_multi_per_yr), " facility-year combinations have more than one certification in the same year."))
  )
}
