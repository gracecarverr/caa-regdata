# =========================================================================================================
# code/diagnostics/10_begin_year_proxy.R -- DIAGNOSTIC, not a deliverable. Evaluates whether
#   EARLIEST_PROGRAM_BEGIN_YEAR (facility-level min BEGIN_DATE year, dataset 1 / O5) is a usable PROXY for
#   operating status, mainly to extend coverage into 2005-2014 where the wayback-based OPERATING flag is NA
#   (wayback only covers 2015-2025). Currently this field feeds nothing else in the pipeline (grep-confirmed).
#
#   Proxy definition: proxy = 1{EARLIEST_PROGRAM_BEGIN_YEAR <= YEAR} -- onset-only, since BEGIN_DATE has no
#   matching close date. Ground truth = wayback OPERATING, available only where WAYBACK_OBSERVED == 1
#   (2015-2025). All comparisons here are descriptive/statistical agreement checks, not causal claims.
#
#   in : data/datasets/operating.csv.gz
#   out: output/begin_year_proxy/{coverage,agreement,lag,post_exit_false_positive}.csv + console summary
# =========================================================================================================
library(readr); library(dplyr); library(tidyr)

OUT <- here::here("output/begin_year_proxy"); dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

op <- read_csv(here::here("data/datasets/operating.csv.gz"),
               col_types = cols(PGM_SYS_ID = col_character(), EXIT_SOURCE = col_character(),
                                OP_STATUS_CODE = col_character(), OP_STATUS_DESC = col_character(),
                                .default = col_integer()), show_col_types = FALSE) |>
  mutate(proxy = as.integer(!is.na(EARLIEST_PROGRAM_BEGIN_YEAR) & EARLIEST_PROGRAM_BEGIN_YEAR <= YEAR))

# ---- 1. coverage: NA rates + the actual 2005-2014 upside being evaluated --------------------------------
n_fac <- n_distinct(op$PGM_SYS_ID)
cov <- tibble(
  metric = c("facilities, any raw begin-year", "facilities, screened begin-year",
             "facility-years 2005-2014 (pre-wayback)", "  ...currently NA under wayback (all of them)",
             "  ...would gain non-NA proxy if adopted"),
  n = c(n_distinct(op$PGM_SYS_ID[!is.na(op$EARLIEST_PROGRAM_BEGIN_YEAR_RAW)]),
        n_distinct(op$PGM_SYS_ID[!is.na(op$EARLIEST_PROGRAM_BEGIN_YEAR)]),
        sum(op$YEAR < 2015),
        sum(op$YEAR < 2015 & is.na(op$OPERATING)),
        sum(op$YEAR < 2015 & is.na(op$OPERATING) & !is.na(op$EARLIEST_PROGRAM_BEGIN_YEAR))),
  pct_of_facilities = round(100 * n / c(n_fac, n_fac, NA, NA, NA), 1))
write_csv(cov, file.path(OUT, "coverage.csv"))

# ---- 2. agreement vs ground truth, 2015-2025 overlap window ----------------------------------------------
gt <- op |> filter(WAYBACK_OBSERVED == 1, !is.na(EARLIEST_PROGRAM_BEGIN_YEAR))
tp <- sum(gt$proxy == 1 & gt$OPERATING == 1); fn <- sum(gt$proxy == 0 & gt$OPERATING == 1)
tn <- sum(gt$proxy == 0 & gt$OPERATING == 0); fp <- sum(gt$proxy == 1 & gt$OPERATING == 0)
agreement <- tibble(
  n_facility_years = nrow(gt),
  base_rate_operating = round(mean(gt$OPERATING), 4),
  sensitivity = round(tp / (tp + fn), 4),      # P(proxy=1 | actually operating)
  specificity = round(tn / (tn + fp), 4),      # P(proxy=0 | actually not operating)
  overall_agreement = round((tp + tn) / nrow(gt), 4),
  tp = tp, fn = fn, tn = tn, fp = fp)
write_csv(agreement, file.path(OUT, "agreement.csv"))

# ---- 3. lag: entered_year (wayback) vs earliest_program_begin_year, facility-level ------------------------
lag_df <- op |> filter(!is.na(ENTERED_YEAR), !is.na(EARLIEST_PROGRAM_BEGIN_YEAR)) |>
  distinct(PGM_SYS_ID, ENTERED_YEAR, EARLIEST_PROGRAM_BEGIN_YEAR) |>
  mutate(lag_years = ENTERED_YEAR - EARLIEST_PROGRAM_BEGIN_YEAR)
lag_summary <- lag_df |> summarise(
  n_facilities = n(), mean_lag = round(mean(lag_years), 2),
  q25 = quantile(lag_years, .25), median_lag = median(lag_years), q75 = quantile(lag_years, .75),
  pct_begin_after_entry = round(100 * mean(lag_years < 0), 1))   # begin-year AFTER observed entry -> proxy would lag reality
write_csv(lag_df, file.path(OUT, "lag_by_facility.csv"))
write_csv(lag_summary, file.path(OUT, "lag_summary.csv"))

# full lag histogram -- every distinct lag value, not just quantiles (2015 is the wayback floor, so any
#   facility with entered_year==2015 is left-censored -- its "true" lag could be understated; flagged separately)
lag_hist <- lag_df |> count(lag_years, name = "n_facilities") |>
  mutate(pct = round(100 * n_facilities / sum(n_facilities), 2)) |> arrange(lag_years)
write_csv(lag_hist, file.path(OUT, "lag_histogram.csv"))

lag_bucketed <- lag_df |> mutate(bucket = case_when(
    lag_years < 0  ~ "begin-year AFTER entry (proxy lags reality)",
    lag_years == 0 ~ "same year",
    lag_years == 1 ~ "1 year lead",
    lag_years %in% 2:5  ~ "2-5 years lead",
    lag_years %in% 6:10 ~ "6-10 years lead",
    TRUE ~ ">10 years lead")) |>
  count(bucket, name = "n_facilities") |> mutate(pct = round(100 * n_facilities / sum(n_facilities), 1)) |>
  arrange(match(bucket, c("begin-year AFTER entry (proxy lags reality)", "same year", "1 year lead",
                          "2-5 years lead", "6-10 years lead", ">10 years lead")))
write_csv(lag_bucketed, file.path(OUT, "lag_buckets.csv"))

# ---- 4. post-exit false positives: proxy has no close date, so it can't see an exit at all ----------------
post_exit <- op |> filter(!is.na(EXITED_YEAR), YEAR > EXITED_YEAR, !is.na(EARLIEST_PROGRAM_BEGIN_YEAR)) |>
  group_by(EXIT_SOURCE) |>
  summarise(n_facility_years = n(), n_facilities = n_distinct(PGM_SYS_ID),
            pct_proxy_false_positive = round(100 * mean(proxy == 1), 1), .groups = "drop") |>
  arrange(desc(n_facility_years))
write_csv(post_exit, file.path(OUT, "post_exit_false_positive.csv"))

# does the false-positive rate decay the longer a facility has been closed, or stay flat? (it should stay
#   ~flat -- proxy is a one-time ratchet with no mechanism to ever flip back to 0)
post_exit_by_gap <- op |> filter(!is.na(EXITED_YEAR), YEAR > EXITED_YEAR, !is.na(EARLIEST_PROGRAM_BEGIN_YEAR)) |>
  mutate(years_since_exit = YEAR - EXITED_YEAR) |>
  group_by(years_since_exit) |>
  summarise(n_facility_years = n(), pct_proxy_false_positive = round(100 * mean(proxy == 1), 1), .groups = "drop") |>
  arrange(years_since_exit)
write_csv(post_exit_by_gap, file.path(OUT, "post_exit_false_positive_by_gap.csv"))

# ---- 5. agreement broken out by year -- does the aggregate 2015-2025 number hide drift? --------------------
agreement_by_year <- gt |> group_by(YEAR) |>
  summarise(n = n(), base_rate_operating = round(mean(OPERATING), 3),
            sensitivity = round(sum(proxy == 1 & OPERATING == 1) / sum(OPERATING == 1), 3),
            specificity = round(sum(proxy == 0 & OPERATING == 0) / sum(OPERATING == 0), 3),
            overall_agreement = round(mean(proxy == OPERATING), 3), .groups = "drop")
write_csv(agreement_by_year, file.path(OUT, "agreement_by_year.csv"))

# ---- console summary ---------------------------------------------------------------------------------------
cat("EARLIEST_PROGRAM_BEGIN_YEAR as an operating-status proxy -- diagnostic summary\n")
cat("================================================================================\n\n")
cat("1. COVERAGE\n"); print(as.data.frame(cov), row.names = FALSE)
cat(sprintf("\n2. AGREEMENT vs wayback ground truth (2015-2025, n=%s facility-years)\n",
            format(agreement$n_facility_years, big.mark = ",")))
cat(sprintf("   base rate operating=1: %.1f%% | sensitivity: %.3f | specificity: %.3f | overall agreement: %.3f\n",
            100 * agreement$base_rate_operating, agreement$sensitivity, agreement$specificity, agreement$overall_agreement))
cat(sprintf("   confusion: TP=%s FN=%s TN=%s FP=%s\n",
            format(tp, big.mark=","), format(fn, big.mark=","), format(tn, big.mark=","), format(fp, big.mark=",")))
cat(sprintf("\n2b. AGREEMENT BY YEAR\n"))
print(as.data.frame(agreement_by_year), row.names = FALSE)
cat(sprintf("\n3. LAG (entered_year - begin_year), n=%s facilities\n", format(lag_summary$n_facilities, big.mark=",")))
cat(sprintf("   mean=%.2f | q25=%.0f | median=%.0f | q75=%.0f | begin-year AFTER observed entry: %.1f%%\n",
            lag_summary$mean_lag, lag_summary$q25, lag_summary$median_lag, lag_summary$q75, lag_summary$pct_begin_after_entry))
cat("\n3b. LAG BUCKETS\n"); print(as.data.frame(lag_bucketed), row.names = FALSE)
cat("\n3c. FULL LAG HISTOGRAM (every distinct lag value)\n"); print(as.data.frame(lag_hist), row.names = FALSE)
cat("\n4. POST-EXIT FALSE POSITIVES (proxy=1 in years strictly after a confirmed exit)\n")
print(as.data.frame(post_exit), row.names = FALSE)
cat("\n4b. POST-EXIT FALSE POSITIVE RATE BY YEARS-SINCE-EXIT (does it decay?)\n")
print(as.data.frame(post_exit_by_gap), row.names = FALSE)
