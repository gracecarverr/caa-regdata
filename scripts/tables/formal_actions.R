# =========================================================================================================
# scripts/tables/formal_actions.R — ICIS-AIR_FORMAL_ACTIONS summary section.
# Ported from CAA_Project/data_docs/scripts/tables/table-formal-actions.R (verbatim stats + content).
# =========================================================================================================
library(here); library(readr); library(dplyr); library(lubridate)

build_formal_actions_section <- function() {
  fa <- read_csv(here("data/raw/ICIS-AIR_downloads/ICIS-AIR_FORMAL_ACTIONS.csv"), show_col_types = FALSE)
  n_obs <- nrow(fa); n_fac <- n_distinct(fa$PGM_SYS_ID)

  pct_miss <- function(x) paste0(round(sum(is.na(x)) / length(x) * 100, 1), "%")
  n_cats   <- function(x) n_distinct(x, na.rm = TRUE)
  top_vals <- function(df, var, n_top = 4) df |> filter(!is.na({{ var }})) |> count({{ var }}) |>
    arrange(desc(n)) |> slice_head(n = n_top) |> mutate(pct = n / nrow(df))

  atc <- fa |> count(ACTIVITY_TYPE_CODE, ACTIVITY_TYPE_DESC) |> mutate(pct = n / n_obs) |> arrange(desc(n))
  atc_miss <- pct_miss(fa$ACTIVITY_TYPE_CODE); atc_ncat <- n_cats(fa$ACTIVITY_TYPE_CODE)
  sef <- top_vals(fa, STATE_EPA_FLAG, 3); sef_miss <- pct_miss(fa$STATE_EPA_FLAG); sef_ncat <- n_cats(fa$STATE_EPA_FLAG)
  etc <- fa |> count(ENF_TYPE_CODE, ENF_TYPE_DESC) |> mutate(pct = n / n_obs) |> arrange(desc(n)) |> slice_head(n = 5)
  etc_miss <- pct_miss(fa$ENF_TYPE_CODE); etc_ncat <- n_cats(fa$ENF_TYPE_CODE)

  sed_yr <- year(mdy(fa$SETTLEMENT_ENTERED_DATE)); sed_n_miss <- sum(is.na(fa$SETTLEMENT_ENTERED_DATE)); sed_n <- sum(!is.na(sed_yr))
  sed <- list(min = min(sed_yr, na.rm = TRUE), p5 = as.integer(quantile(sed_yr, 0.05, na.rm = TRUE)),
              med = as.integer(median(sed_yr, na.rm = TRUE)), p95 = as.integer(quantile(sed_yr, 0.95, na.rm = TRUE)), max = max(sed_yr, na.rm = TRUE))

  pen_n <- sum(!is.na(fa$PENALTY_AMOUNT))
  pen_all <- list(min = min(fa$PENALTY_AMOUNT, na.rm = TRUE), p5 = quantile(fa$PENALTY_AMOUNT, 0.05, na.rm = TRUE),
                  med = median(fa$PENALTY_AMOUNT, na.rm = TRUE), p95 = quantile(fa$PENALTY_AMOUNT, 0.95, na.rm = TRUE), max = max(fa$PENALTY_AMOUNT, na.rm = TRUE))
  n_zero <- sum(fa$PENALTY_AMOUNT == 0, na.rm = TRUE)
  pen_nz <- fa |> filter(!is.na(PENALTY_AMOUNT), PENALTY_AMOUNT > 0); n_nonzero <- nrow(pen_nz)
  pen_nz_stats <- list(min = min(pen_nz$PENALTY_AMOUNT), p5 = quantile(pen_nz$PENALTY_AMOUNT, 0.05),
                       med = median(pen_nz$PENALTY_AMOUNT), p95 = quantile(pen_nz$PENALTY_AMOUNT, 0.95), max = max(pen_nz$PENALTY_AMOUNT))

  n_dup_act <- sum(duplicated(fa$ACTIVITY_ID)); n_dup_enf <- sum(duplicated(fa$ENF_IDENTIFIER))
  n_dup_all3 <- sum(duplicated(fa |> select(PGM_SYS_ID, ACTIVITY_ID, ENF_IDENTIFIER)))
  fpf <- fa |> group_by(PGM_SYS_ID) |> summarise(n = n(), .groups = "drop")
  n_multi <- sum(fpf$n > 1); max_act <- max(fpf$n); med_act <- as.integer(median(fpf$n))
  n_enf_multi <- fa |> group_by(ENF_IDENTIFIER) |> filter(n() > 1) |> ungroup() |> distinct(ENF_IDENTIFIER) |> nrow()

  crows <- c(
    cat_var("ACTIVITY_TYPE_CODE", "Whether the action is administrative (agency-issued) or judicial (court-filed).", atc_miss, atc_ncat,
            paste0(atc$ACTIVITY_TYPE_CODE, " - ", atc$ACTIVITY_TYPE_DESC), atc$n, atc$pct),
    cat_var("STATE_EPA_FLAG", "Which agency took the enforcement action.", sef_miss, sef_ncat, c("S - State","L - Local","E - EPA"), sef$n, sef$pct),
    cat_var("ENF_TYPE_CODE", "Specific type of enforcement action taken.", etc_miss, etc_ncat,
            paste0(etc$ENF_TYPE_CODE, " - ", etc$ENF_TYPE_DESC), etc$n, etc$pct)
  )
  nrows <- c(
    num_row("SETTLEMENT_ENTERED_DATE_YEAR", "Date the settlement or order was entered.",
            c(paste0(sed_n_miss, " (", round(sed_n_miss / n_obs * 100), "%)"), comma(sed_n), sed$min, sed$p5, sed$med, sed$p95, sed$max)),
    num_row("PENALTY_AMOUNT (all)", "Dollar amount of the assessed penalty. Includes $0 values.",
            c(pct_miss(fa$PENALTY_AMOUNT), comma(pen_n), dollar(pen_all$min), dollar(pen_all$p5), dollar(pen_all$med), dollar(pen_all$p95), dollar(pen_all$max))),
    num_row("PENALTY_AMOUNT (nonzero)", paste0("Penalties > $0 only. ", comma(n_zero), " actions (", round(n_zero / n_obs * 100, 1), "%) have $0 penalty."),
            c("N/A", comma(n_nonzero), dollar(pen_nz_stats$min), dollar(pen_nz_stats$p5), dollar(pen_nz_stats$med), dollar(pen_nz_stats$p95), dollar(pen_nz_stats$max)))
  )

  obs_line <- paste0("OBSERVATIONS: ", comma(n_obs), "  |  DISTINCT FACILITIES: ", comma(n_fac), "  |  TEMPORAL COVERAGE: ", sed$min, "–", sed$max)
  inv <- "IDENTIFIERS: PGM_SYS_ID, ACTIVITY_ID, ENF_IDENTIFIER"

  sec(
    h_head("formal_actions", "ICIS-Air Formal Actions", "ICIS-AIR_FORMAL_ACTIONS.csv",
      paste0("Formal enforcement actions taken against facilities for Clean Air Act violations. Includes administrative orders ",
             "(consent agreements, compliance orders) and judicial actions (civil lawsuits filed in court). Each row is one enforcement action event."),
      obs_line, inv),
    cat_table(crows),
    note(paste0("**", round(atc$pct[1] * 100), "% of formal actions are administrative (issued by the agency directly), only ",
      round(atc$pct[2] * 100), "% are judicial (filed in court). Administrative orders (", round(etc$pct[1] * 100),
      "%) are the dominant enforcement tool. EPA takes ", round(sef$pct[sef$STATE_EPA_FLAG == "E"] * 100),
      "% of formal actions — a much larger share than its 3% of compliance monitoring, reflecting EPA's role in escalated enforcement.")),
    note(paste0("**ENF_TYPE_CODE glossary: ", etc$ENF_TYPE_CODE[1], " = ", etc$ENF_TYPE_DESC[1], "; ", etc$ENF_TYPE_CODE[2], " = ", etc$ENF_TYPE_DESC[2],
      "; ", etc$ENF_TYPE_CODE[3], " = ", etc$ENF_TYPE_DESC[3], "; ", etc$ENF_TYPE_CODE[4], " = ", etc$ENF_TYPE_DESC[4], "; ",
      etc$ENF_TYPE_CODE[5], " = ", etc$ENF_TYPE_DESC[5], ".")),
    num_table(c("Variable","% Missing","N","Min","P5","Median","P95","Max"), nrows),
    note(paste0("**", round(n_zero / n_obs * 100, 1), "% of formal actions carry $0 penalty — these are compliance orders requiring corrective ",
      "action without a fine (primarily CAA 113A orders). Among nonzero penalties, the median is ", dollar(pen_nz_stats$med),
      " and the 95th percentile is ", dollar(pen_nz_stats$p95), ". The maximum ($", formatC(pen_nz_stats$max / 1e6, format = "f", digits = 1), "M) is an outlier.")),
    dupes(paste0("No exact duplicate rows. ACTIVITY_ID is not fully unique — ", comma(n_dup_act), " rows (", round(n_dup_act / n_obs * 100, 1),
      "%) share an ACTIVITY_ID with at least one other row. Of these, ", comma(n_dup_all3),
      " share all three IDs (PGM_SYS_ID + ACTIVITY_ID + ENF_IDENTIFIER) — same facility, same action, with differences in PENALTY_AMOUNT, ",
      "SETTLEMENT_ENTERED_DATE, or ENF_TYPE_CODE (e.g., multiple penalty entries or date corrections). The remaining ", comma(n_dup_act - n_dup_all3),
      " share an ACTIVITY_ID across different facilities — likely multi-facility enforcement actions (e.g., one civil suit covering multiple co-located sources). ",
      comma(n_multi), " facilities (", round(n_multi / n_fac * 100, 1), "%) have 2+ formal actions (max ", comma(max_act), "; median ", med_act, "). ",
      "ENF_IDENTIFIER has ", comma(n_enf_multi), " values appearing more than once (", comma(n_dup_enf),
      " rows), meaning some enforcement cases generate multiple action records — typically when a single case involves multiple enforcement provisions or legal authorities."))
  )
}
