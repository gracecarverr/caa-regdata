# =========================================================================================================
# code/diagnostics/tables/programs.R — ICIS-AIR_PROGRAMS (air-program enrollments) summary section.
# Ported from CAA_Project/data_docs/scripts/tables/table-programs.R (stats + curated content verbatim).
# =========================================================================================================
library(here); library(readr); library(dplyr); library(lubridate)

build_programs_section <- function() {
  prog <- read_csv(here("data/raw/ICIS-AIR_downloads/ICIS-AIR_PROGRAMS.csv"), show_col_types = FALSE)
  n_obs <- nrow(prog); n_fac <- n_distinct(prog$PGM_SYS_ID)

  pct_miss <- function(x) paste0(round(sum(is.na(x)) / length(x) * 100, 1), "%")
  n_cats   <- function(x) n_distinct(x, na.rm = TRUE)

  pc <- prog |> filter(!is.na(PROGRAM_CODE)) |> count(PROGRAM_CODE, PROGRAM_DESC) |> arrange(desc(n)) |> slice_head(n = 6) |> mutate(pct = n / n_obs)
  pc_miss <- pct_miss(prog$PROGRAM_CODE); pc_ncat <- n_cats(prog$PROGRAM_CODE)

  aos_all <- prog |> filter(!is.na(AIR_OPERATING_STATUS_CODE)) |> count(AIR_OPERATING_STATUS_CODE) |> arrange(desc(n))
  aos_top <- aos_all |> slice_head(n = 3) |> mutate(pct = n / n_obs)
  aos_other <- aos_all |> slice_tail(n = nrow(aos_all) - 3)
  aos <- bind_rows(aos_top, tibble(AIR_OPERATING_STATUS_CODE = "PLN/CNS/SEA", n = sum(aos_other$n), pct = sum(aos_other$n) / n_obs))
  aos_miss <- pct_miss(prog$AIR_OPERATING_STATUS_CODE); aos_ncat <- n_cats(prog$AIR_OPERATING_STATUS_CODE)

  bd_yr <- year(mdy(prog$BEGIN_DATE)); bd_n <- sum(!is.na(bd_yr))
  bd_stats <- list(min = min(bd_yr, na.rm = TRUE), p5 = as.integer(quantile(bd_yr, 0.05, na.rm = TRUE)),
                   med = as.integer(median(bd_yr, na.rm = TRUE)), p95 = as.integer(quantile(bd_yr, 0.95, na.rm = TRUE)), max = max(bd_yr, na.rm = TRUE))
  ud_yr <- year(mdy(prog$UPDATED_DATE)); ud_n <- sum(!is.na(ud_yr))
  ud_stats <- list(min = min(ud_yr, na.rm = TRUE), p5 = as.integer(quantile(ud_yr, 0.05, na.rm = TRUE)),
                   med = as.integer(median(ud_yr, na.rm = TRUE)), p95 = as.integer(quantile(ud_yr, 0.95, na.rm = TRUE)), max = max(ud_yr, na.rm = TRUE))

  n_dup_pgm_prog <- sum(duplicated(prog |> select(PGM_SYS_ID, PROGRAM_CODE)))
  fac_prog <- prog |> group_by(PGM_SYS_ID) |> summarise(n_prog = n(), .groups = "drop")
  n_multi <- sum(fac_prog$n_prog > 1); max_prog <- max(fac_prog$n_prog)
  n_dup_pgm <- sum(duplicated(prog$PGM_SYS_ID))

  crows <- c(
    cat_var("PROGRAM_CODE", "Which CAA regulatory program the facility is subject to.", pc_miss, pc_ncat,
            paste0(pc$PROGRAM_CODE, " - ", pc$PROGRAM_DESC), pc$n, pc$pct),
    cat_var("AIR_OPERATING_STATUS_CODE", "Operating status of the program enrollment.", aos_miss, aos_ncat,
            c("OPR - Operating","CLS - Permanently Closed","TMP - Temporarily Closed","PLN/CNS/SEA - Other"), aos$n, aos$pct)
  )
  nrows <- c(
    num_row("BEGIN_DATE_YEAR", "Date the program enrollment began.", c(pct_miss(prog$BEGIN_DATE), comma(bd_n), bd_stats$min, bd_stats$p5, bd_stats$med, bd_stats$p95, bd_stats$max)),
    num_row("UPDATED_DATE_YEAR", "Date the program record was last updated.", c(pct_miss(prog$UPDATED_DATE), comma(ud_n), ud_stats$min, ud_stats$p5, ud_stats$med, ud_stats$p95, ud_stats$max))
  )

  obs_line <- paste0("OBSERVATIONS: ", comma(n_obs), "  |  DISTINCT FACILITIES: ", comma(n_fac))
  inv <- "IDENTIFIERS: PGM_SYS_ID  |  DATES: BEGIN_DATE, UPDATED_DATE  |  TEXT DECODE: AIR_OPERATING_STATUS_DESC (label for AIR_OPERATING_STATUS_CODE)"

  sec(
    h_head("programs", "ICIS-Air Programs", "ICIS-AIR_PROGRAMS.csv",
      paste0("Each row is one facility-program combination. A single facility can be subject to multiple regulatory ",
             "programs (e.g., SIP + Title V + MACT). The median facility holds 1 program; major sources typically hold several."),
      obs_line, inv),
    cat_table(crows),
    note(paste0("**SIP (", round(pc$pct[1] * 100), "%) is the baseline — nearly every regulated source has one. Title V (",
      round(pc$pct[pc$PROGRAM_CODE == "CAATVP"] * 100), "%) applies almost exclusively to major sources. MACT and NSPS are ",
      "technology-based standards for specific industries and pollutants.")),
    num_table(c("Variable","% Missing","N","Min","P5","Median","P95","Max"), nrows),
    note(paste0("**BEGIN_DATE has junk values (e.g., year ", bd_stats$min, ") from data entry errors. 95% of program enrollments began between ",
      bd_stats$p5, " and ", bd_stats$p95, ". UPDATED_DATE ranges from ", ud_stats$min, " (ICIS system launch) to ", ud_stats$max, ".")),
    dupes(paste0("No exact duplicate rows. PGM_SYS_ID is not unique — ", comma(n_dup_pgm), " rows (", round(n_dup_pgm / n_obs * 100, 1),
      "%) share a PGM_SYS_ID with at least one other row. This is by design: a single facility can hold multiple program enrollments ",
      "(e.g., SIP + Title V + MACT). ", comma(n_multi), " facilities have 2+ programs (max ", max_prog, "). ", n_dup_pgm_prog,
      " row has a duplicate PGM_SYS_ID + PROGRAM_CODE combination (same facility enrolled in the same program twice)."))
  )
}
