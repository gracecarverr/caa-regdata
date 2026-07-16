# =========================================================================================================
# code/diagnostics/tables/informal_actions.R — ICIS-AIR_INFORMAL_ACTIONS summary section.
# Ported from CAA_Project/data_docs/scripts/tables/table-informal-actions.R (verbatim stats + content).
# =========================================================================================================
library(here); library(readr); library(dplyr); library(lubridate)

build_informal_actions_section <- function() {
  inf <- read_csv(here("data/raw/ICIS-AIR_downloads/ICIS-AIR_INFORMAL_ACTIONS.csv"), show_col_types = FALSE)
  n_obs <- nrow(inf); n_fac <- n_distinct(inf$PGM_SYS_ID)

  pct_miss <- function(x) paste0(round(sum(is.na(x)) / length(x) * 100, 1), "%")
  n_cats   <- function(x) n_distinct(x, na.rm = TRUE)
  top_vals <- function(df, var, n_top = 4) df |> filter(!is.na({{ var }})) |> count({{ var }}) |>
    arrange(desc(n)) |> slice_head(n = n_top) |> mutate(pct = n / nrow(df))

  act <- inf |> count(ACTIVITY_TYPE_CODE, ACTIVITY_TYPE_DESC) |> mutate(pct = n / n_obs) |> arrange(desc(n))
  act_miss <- pct_miss(inf$ACTIVITY_TYPE_CODE); act_ncat <- n_cats(inf$ACTIVITY_TYPE_CODE)
  enf <- inf |> count(ENF_TYPE_CODE, ENF_TYPE_DESC) |> mutate(pct = n / n_obs) |> arrange(desc(n)) |> slice_head(n = 4)
  enf_miss <- pct_miss(inf$ENF_TYPE_CODE); enf_ncat <- n_cats(inf$ENF_TYPE_CODE)
  sef <- top_vals(inf, STATE_EPA_FLAG, 3); sef_miss <- pct_miss(inf$STATE_EPA_FLAG); sef_ncat <- n_cats(inf$STATE_EPA_FLAG)
  ofl <- top_vals(inf, OFFICIAL_FLG, 2); ofl_miss <- pct_miss(inf$OFFICIAL_FLG); ofl_ncat <- n_cats(inf$OFFICIAL_FLG)

  ad_yr <- year(mdy(inf$ACHIEVED_DATE)); ad_n_miss <- sum(is.na(inf$ACHIEVED_DATE)); ad_n <- sum(!is.na(ad_yr))
  ad <- list(min = min(ad_yr, na.rm = TRUE), p5 = as.integer(quantile(ad_yr, 0.05, na.rm = TRUE)),
             med = as.integer(median(ad_yr, na.rm = TRUE)), p95 = as.integer(quantile(ad_yr, 0.95, na.rm = TRUE)), max = max(ad_yr, na.rm = TRUE))
  n_junk_dates <- sum(!is.na(ad_yr) & (ad_yr < 1973 | ad_yr > 2027))

  n_exact_dup <- sum(duplicated(inf)); n_unique_rows <- nrow(distinct(inf)); inf_dedup <- distinct(inf)
  n_dup_enf <- sum(duplicated(inf_dedup$ENF_IDENTIFIER)); n_distinct_enf <- n_distinct(inf_dedup$ENF_IDENTIFIER)
  ipf <- inf_dedup |> group_by(PGM_SYS_ID) |> summarise(n = n(), .groups = "drop")
  n_fac_dedup <- nrow(ipf); n_multi <- sum(ipf$n > 1); max_act <- max(ipf$n); med_act <- as.integer(median(ipf$n))

  crows <- c(
    cat_var("ACTIVITY_TYPE_CODE", "Type of informal enforcement response taken.", act_miss, act_ncat,
            paste0(act$ACTIVITY_TYPE_CODE, " - ", act$ACTIVITY_TYPE_DESC), act$n, act$pct),
    cat_var("ENF_TYPE_CODE", "Specific enforcement mechanism used.", enf_miss, enf_ncat,
            paste0(enf$ENF_TYPE_CODE, " - ", enf$ENF_TYPE_DESC), enf$n, enf$pct),
    cat_var("STATE_EPA_FLAG", "Which agency issued the informal action.", sef_miss, sef_ncat, c("S - State","L - Local","E - EPA"), sef$n, sef$pct),
    cat_var("OFFICIAL_FLG", "Whether the action has been officially submitted and finalized in the EPA reporting system.", ofl_miss, ofl_ncat,
            c("Y - Yes","N - No"), ofl$n, ofl$pct)
  )
  nrows <- num_row("ACHIEVED_DATE_YEAR", "Date the informal action was completed or resolved.",
                   c(paste0(comma(ad_n_miss), " records (", round(ad_n_miss / n_obs * 100), "%)"), comma(ad_n), ad$min, ad$p5, ad$med, ad$p95, ad$max))

  obs_line <- paste0("OBSERVATIONS: ", comma(n_obs), "  |  DISTINCT FACILITIES: ", comma(n_fac), "  |  TEMPORAL COVERAGE: ", ad$min, "–", ad$max)
  inv <- "IDENTIFIERS: PGM_SYS_ID, ACTIVITY_ID, ENF_IDENTIFIER"

  sec(
    h_head("informal_actions", "ICIS-Air Informal Actions", "ICIS-AIR_INFORMAL_ACTIONS.csv",
      paste0("Informal enforcement actions — lower-severity responses to noncompliance that do not carry legally binding obligations. ",
             "Primarily Notices of Violation (NOVs), which formally notify a facility that it has been found out of compliance."),
      obs_line, inv),
    cat_table(crows),
    note(paste0("**", round(enf$pct[1] * 100), "% of informal actions are ", enf$ENF_TYPE_DESC[1],
      " (NOVs), which notify a facility it has been found in noncompliance. The remainder are warning letters and other minor responses.")),
    num_table(c("Variable","% Missing","N","Min","P5","Median","P95","Max"), nrows),
    note(paste0("**", n_junk_dates, " records have junk dates outside the 1973-2027 range. 95% of actions fall between ", ad$p5, " and ", ad$p95, ".")),
    dupes(paste0(comma(n_exact_dup), " exact duplicate rows (", round(n_exact_dup / n_obs * 100, 1),
      "% of the dataset). Every duplicate appears exactly twice — ", comma(n_unique_rows), " unique rows, ", comma(n_obs),
      " total. The duplicates share identical values across all columns (PGM_SYS_ID, ACTIVITY_ID, ENF_IDENTIFIER, and all other fields). ",
      "This is likely a bulk data export artifact — possibly from a system migration or a join that inadvertently doubled records. Users should deduplicate before analysis. ",
      "After deduplication, ", comma(n_multi), " facilities (", round(n_multi / n_fac_dedup * 100, 1), "%) have 2+ informal actions (max ", comma(max_act),
      "; median ", med_act, "). ENF_IDENTIFIER has ", comma(n_dup_enf), " duplicate values (", comma(n_distinct_enf),
      " distinct), meaning some enforcement actions appear under multiple ACTIVITY_IDs — possibly linking one enforcement response to multiple compliance events."))
  )
}
