# =========================================================================================================
# code/diagnostics/tables/afs_hpv.R — legacy AFS_HPV_HISTORY summary section.
# Ported from CAA_Project/data_docs/scripts/tables/table-afs-hpv.R (verbatim stats + content).
# =========================================================================================================
library(here); library(readr); library(dplyr); library(lubridate)

build_afs_hpv_section <- function() {
  hpv <- read_csv(here("data/raw/afs_downloads/AFS_HPV_HISTORY.csv"), show_col_types = FALSE)
  n_obs <- nrow(hpv); n_fac <- n_distinct(hpv$AFS_ID)

  pct_miss <- function(x) paste0(round(sum(is.na(x)) / length(x) * 100, 1), "%")
  n_cats   <- function(x) n_distinct(x, na.rm = TRUE)
  top_vals <- function(df, var, n_top = 4) df |> filter(!is.na({{ var }})) |> count({{ var }}) |>
    arrange(desc(n)) |> slice_head(n = n_top) |> mutate(pct = n / nrow(df))
  date_stats <- function(date_col) {
    yr <- year(mdy(date_col, quiet = TRUE)); n_miss <- sum(is.na(yr)); n_valid <- sum(!is.na(yr))
    list(n_miss = n_miss, miss_label = paste0(formatC(n_miss, format = "d", big.mark = ","), " (", round(n_miss / length(date_col) * 100, 1), "%)"),
         n = n_valid, min = min(yr, na.rm = TRUE), p5 = as.integer(quantile(yr, 0.05, na.rm = TRUE)),
         med = as.integer(median(yr, na.rm = TRUE)), p95 = as.integer(quantile(yr, 0.95, na.rm = TRUE)), max = max(yr, na.rm = TRUE))
  }

  dzt <- top_vals(hpv, HPV_DAYZERO_TYPE, 4); dzt_miss <- pct_miss(hpv$HPV_DAYZERO_TYPE); dzt_ncat <- n_cats(hpv$HPV_DAYZERO_TYPE)
  dzt_lookup <- hpv |> filter(!is.na(HPV_DAYZERO_TYPE)) |> distinct(HPV_DAYZERO_TYPE, HPV_DAYZERO_DESC) |> mutate(HPV_DAYZERO_DESC = trimws(HPV_DAYZERO_DESC))
  dzt_labels <- dzt |> left_join(dzt_lookup, by = "HPV_DAYZERO_TYPE") |> mutate(label = paste0(HPV_DAYZERO_TYPE, " - ", HPV_DAYZERO_DESC))
  rst <- top_vals(hpv, HPV_RESOLVED_TYPE, 4); rst_miss <- pct_miss(hpv$HPV_RESOLVED_TYPE); rst_ncat <- n_cats(hpv$HPV_RESOLVED_TYPE)
  rst_lookup <- hpv |> filter(!is.na(HPV_RESOLVED_TYPE)) |> distinct(HPV_RESOLVED_TYPE, HPV_RESOLVED_DESC) |> mutate(HPV_RESOLVED_DESC = trimws(HPV_RESOLVED_DESC))
  rst_labels <- rst |> left_join(rst_lookup, by = "HPV_RESOLVED_TYPE") |> mutate(label = paste0(HPV_RESOLVED_TYPE, " - ", HPV_RESOLVED_DESC))

  dz_date <- date_stats(hpv$HPV_DAYZERO_DATE); res_date <- date_stats(hpv$HPV_RESOLVED_DATE)
  dz_parsed <- mdy(hpv$HPV_DAYZERO_DATE, quiet = TRUE); res_parsed <- mdy(hpv$HPV_RESOLVED_DATE, quiet = TRUE)
  res_days <- as.numeric(difftime(res_parsed, dz_parsed, units = "days")); res_days_valid <- res_days[!is.na(res_days)]
  n_res_valid <- length(res_days_valid); n_res_miss <- n_obs - n_res_valid
  res_miss_label <- paste0(formatC(n_res_miss, format = "d", big.mark = ","), " (", round(n_res_miss / n_obs * 100, 1), "%)")
  res_min <- as.integer(min(res_days_valid, na.rm = TRUE)); res_p5 <- as.integer(quantile(res_days_valid, 0.05, na.rm = TRUE))
  res_med <- as.integer(median(res_days_valid, na.rm = TRUE)); res_p95 <- as.integer(quantile(res_days_valid, 0.95, na.rm = TRUE)); res_max <- as.integer(max(res_days_valid, na.rm = TRUE))
  temp_min <- min(c(dz_date$min, res_date$min)); temp_max <- max(c(dz_date$max, res_date$max))

  n_exact_dup <- sum(duplicated(hpv))
  hpv_per_fac <- hpv |> group_by(AFS_ID) |> summarise(n = n(), .groups = "drop")
  n_multi <- sum(hpv_per_fac$n > 1); max_hpv <- max(hpv_per_fac$n); med_hpv <- as.integer(median(hpv_per_fac$n))

  crows <- c(
    cat_var("HPV_DAYZERO_TYPE", "Code for how the HPV day-zero was established. Paired with HPV_DAYZERO_DESC.", dzt_miss, dzt_ncat, dzt_labels$label, dzt$n, dzt$pct),
    cat_var("HPV_RESOLVED_TYPE", "Code for how the HPV was resolved. Paired with HPV_RESOLVED_DESC.", rst_miss, rst_ncat, rst_labels$label, rst$n, rst$pct)
  )
  nrows <- c(
    num_row("HPV_DAYZERO_DATE", "Date the HPV was identified (day-zero). Parsed as year.",
            c(dz_date$miss_label, comma(dz_date$n), dz_date$min, dz_date$p5, dz_date$med, dz_date$p95, dz_date$max)),
    num_row("HPV_RESOLVED_DATE", "Date the HPV was resolved or closed. Parsed as year.",
            c(res_date$miss_label, comma(res_date$n), res_date$min, res_date$p5, res_date$med, res_date$p95, res_date$max)),
    num_row("Resolution Time (days)", "Days between HPV_DAYZERO_DATE and HPV_RESOLVED_DATE.",
            c(res_miss_label, comma(n_res_valid), comma(res_min), comma(res_p5), comma(res_med), comma(res_p95), comma(res_max)))
  )

  obs_line <- paste0("OBSERVATIONS: ", comma(n_obs), "  |  DISTINCT FACILITIES: ", comma(n_fac), "  |  TEMPORAL COVERAGE: ", temp_min, "–", temp_max)
  inv <- "IDENTIFIERS: AFS_ID"

  sec(
    h_head("afs_hpv", "AFS HPV History", "AFS_HPV_HISTORY.csv",
      paste0("High Priority Violation tracking from EPA's legacy AFS system. Each row links an HPV day-zero event ",
             "(when the violation was identified) to its resolution."),
      obs_line, inv),
    cat_table(crows),
    note(paste0("**HPV_DAYZERO_TYPE tells you who or what triggered the violation clock. The most common type is '", trimws(dzt_labels$label[1]), "' (",
      round(dzt$pct[1] * 100), "%). HPV_RESOLVED_TYPE shows how it was closed — '", trimws(rst_labels$label[1]), "' accounts for ", round(rst$pct[1] * 100), "% of resolutions.")),
    note(paste0("**HPV_RESOLVED_TYPE is ", rst_miss, " missing — rows without a resolved type represent HPVs that were still open or had incomplete records ",
      "when the AFS system was frozen in October 2014.")),
    num_table(c("Variable","% Missing","N","Min","P5","Median","P95","Max"), nrows),
    note(paste0("**Dates are from the legacy AFS system (frozen October 2014). Some entries may contain data-entry errors (e.g., very early years). ",
      "HPV_RESOLVED_DATE is missing for HPVs that were still unresolved when AFS was frozen.")),
    note(paste0("**Resolution time is computed only for rows where both dates parse successfully. Median resolution is reported in days alongside the 5th and 95th ",
      "percentiles to show the typical range. Negative values, if present, indicate data-entry errors.")),
    dupes(paste0("Exact duplicate rows: ", comma(n_exact_dup), ". AFS_ID is not unique — facilities can have multiple HPV events over time. ", comma(n_multi),
      " facilities have 2+ HPV records (max ", comma(max_hpv), "; median ", med_hpv, "). This is expected: a facility may accumulate multiple violations across different inspections or time periods."))
  )
}
