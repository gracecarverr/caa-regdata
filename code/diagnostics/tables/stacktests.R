# =========================================================================================================
# code/diagnostics/tables/stacktests.R — ICIS-AIR_STACK_TESTS summary section.
# Ported from CAA_Project/data_docs/scripts/tables/table-stack-tests.R (verbatim stats + content).
# =========================================================================================================
library(here); library(readr); library(dplyr); library(lubridate)

build_stacktests_section <- function() {
  st <- read_csv(here("data/raw/ICIS-AIR_downloads/ICIS-AIR_STACK_TESTS.csv"), show_col_types = FALSE)
  n_obs <- nrow(st); n_fac <- n_distinct(st$PGM_SYS_ID)

  pct_miss <- function(x) paste0(round(sum(is.na(x)) / length(x) * 100, 1), "%")
  n_cats   <- function(x) n_distinct(x, na.rm = TRUE)
  top_vals <- function(df, var, n_top = 4) df |> filter(!is.na({{ var }})) |> count({{ var }}) |>
    arrange(desc(n)) |> slice_head(n = n_top) |> mutate(pct = n / nrow(df))

  ast <- top_vals(st, AIR_STACK_TEST_STATUS_CODE, 4); ast_miss <- pct_miss(st$AIR_STACK_TEST_STATUS_CODE); ast_ncat <- n_cats(st$AIR_STACK_TEST_STATUS_CODE)
  sef <- top_vals(st, STATE_EPA_FLAG, 3); sef_miss <- pct_miss(st$STATE_EPA_FLAG); sef_ncat <- n_cats(st$STATE_EPA_FLAG)
  cmt <- st |> count(COMP_MONITOR_TYPE_CODE, COMP_MONITOR_TYPE_DESC) |> mutate(pct = n / n_obs) |> arrange(desc(n))
  cmt_miss <- pct_miss(st$COMP_MONITOR_TYPE_CODE); cmt_ncat <- n_cats(st$COMP_MONITOR_TYPE_CODE)
  plc <- top_vals(st, POLLUTANT_CODES, 4); plc_miss <- pct_miss(st$POLLUTANT_CODES); plc_ncat <- n_cats(st$POLLUTANT_CODES)
  pld_miss <- pct_miss(st$POLLUTANT_DESCS); pld_ncat <- n_cats(st$POLLUTANT_DESCS)

  aed_yr <- year(mdy(st$ACTUAL_END_DATE)); aed_n_miss <- sum(is.na(st$ACTUAL_END_DATE)); aed_n <- sum(!is.na(aed_yr))
  aed <- list(min = min(aed_yr, na.rm = TRUE), p5 = as.integer(quantile(aed_yr, 0.05, na.rm = TRUE)),
              med = as.integer(median(aed_yr, na.rm = TRUE)), p95 = as.integer(quantile(aed_yr, 0.95, na.rm = TRUE)), max = max(aed_yr, na.rm = TRUE))

  n_uniq_act <- n_distinct(st$ACTIVITY_ID)
  spf <- st |> group_by(PGM_SYS_ID) |> summarise(n = n(), .groups = "drop")
  n_multi <- sum(spf$n > 1); max_test <- max(spf$n); med_test <- as.integer(median(spf$n))

  ast_labels <- c("PSS"="Pass","FAI"="Fail","PEN"="Pending","INC"="Incomplete")
  ast_descs <- paste0(ast$AIR_STACK_TEST_STATUS_CODE, " - ", ast_labels[ast$AIR_STACK_TEST_STATUS_CODE])

  crows <- c(
    cat_var("AIR_STACK_TEST_STATUS_CODE", "Result of the stack test.", ast_miss, ast_ncat, ast_descs, ast$n, ast$pct),
    cat_var("STATE_EPA_FLAG", "Which agency conducted or oversaw the test.", sef_miss, sef_ncat, c("S - State","L - Local","E - EPA"), sef$n, sef$pct),
    cat_var("COMP_MONITOR_TYPE_CODE", "Type of compliance monitoring activity. All records are stack tests.", cmt_miss, cmt_ncat,
            paste0(cmt$COMP_MONITOR_TYPE_CODE, " - ", cmt$COMP_MONITOR_TYPE_DESC), cmt$n, cmt$pct),
    cat_var("POLLUTANT_CODES", "Pollutant(s) tested in the stack test. Uses pollutant names, not numeric codes.", plc_miss, plc_ncat,
            plc$POLLUTANT_CODES, plc$n, plc$pct),
    cat_var("POLLUTANT_DESCS", "Pollutant description field. Entirely unpopulated in this dataset.", pld_miss, pld_ncat,
            c("(All values missing)"), c(n_obs), c(1.000))
  )
  nrows <- num_row("ACTUAL_END_DATE_YEAR", "Date the stack test was completed.",
                   c(paste0(aed_n_miss, " records (", round(aed_n_miss / n_obs * 100), "%)"), comma(aed_n), aed$min, aed$p5, aed$med, aed$p95, aed$max))

  obs_line <- paste0("OBSERVATIONS: ", comma(n_obs), "  |  DISTINCT FACILITIES: ", comma(n_fac), "  |  TEMPORAL COVERAGE: ", aed$min, "–", aed$max)
  inv <- "IDENTIFIERS: PGM_SYS_ID, ACTIVITY_ID  |  DATE: ACTUAL_END_DATE  |  TEXT DECODE: AIR_STACK_TEST_STATUS_DESC (label for AIR_STACK_TEST_STATUS_CODE)"

  sec(
    h_head("stacktests", "ICIS-Air Stack Tests", "ICIS-AIR_STACK_TESTS.csv",
      paste0("Stack test results — emissions tests conducted at facility smokestacks or vents to measure whether actual emissions ",
             "comply with permitted limits. Each row is one test event."),
      obs_line, inv),
    cat_table(crows),
    note(paste0("**", round(ast$pct[1] * 100), "% of stack tests pass. The ", round(ast$pct[ast$AIR_STACK_TEST_STATUS_CODE == "FAI"] * 100, 1),
      "% failure rate is concentrated at major sources (71% of failures), consistent with the pattern that major sources face more intensive regulatory scrutiny.")),
    note(paste0("**COMP_MONITOR_TYPE_CODE is 100% ", cmt$COMP_MONITOR_TYPE_CODE[1], " — this table only contains stack test records. ",
      "POLLUTANT_DESCS is entirely empty. POLLUTANT_CODES is ", plc_miss, " missing — an optional field under EPA's Minimum Data Requirements.")),
    num_table(c("Variable","% Missing","N","Min","P5","Median","P95","Max"), nrows),
    note(paste0("**95% of stack tests fall between ", aed$p5, " and ", aed$p95, ".")),
    dupes(paste0("No exact duplicate rows. ACTIVITY_ID is fully unique (", comma(n_uniq_act), " distinct values). PGM_SYS_ID is not unique — ",
      comma(n_multi), " facilities (", round(n_multi / n_fac * 100, 1), "%) have 2+ stack tests (max ", comma(max_test), "; median ", med_test,
      "). Multiple tests per facility are expected: facilities are tested periodically, and each test of a different pollutant or emission point generates a separate record."))
  )
}
