# =========================================================================================================
# code/diagnostics/tables/afs_actions.R — legacy AFS_ACTIONS summary section.
# Ported from CAA_Project/data_docs/scripts/tables/table-afs-actions.R (verbatim stats + content).
# =========================================================================================================
library(here); library(readr); library(dplyr); library(lubridate)

build_afs_actions_section <- function() {
  aa <- read_csv(here("data/raw/afs_downloads/AFS_ACTIONS.csv"), show_col_types = FALSE)
  n_obs <- nrow(aa); n_fac <- n_distinct(aa$AFS_ID)

  pct_miss <- function(x) paste0(round(sum(is.na(x)) / length(x) * 100, 1), "%")
  n_cats   <- function(x) n_distinct(x, na.rm = TRUE)
  top_vals <- function(df, var, n_top = 4) df |> filter(!is.na({{ var }})) |> count({{ var }}) |>
    arrange(desc(n)) |> slice_head(n = n_top) |> mutate(pct = n / nrow(df))

  nat <- aa |> count(NATIONAL_ACTION_TYPE, NATIONAL_ACTION_DESC) |> mutate(pct = n / n_obs) |> arrange(desc(n)) |> slice_head(n = 4)
  nat_miss <- pct_miss(aa$NATIONAL_ACTION_TYPE); nat_ncat <- n_cats(aa$NATIONAL_ACTION_TYPE)
  rc <- top_vals(aa, RESULT_CODE, 4); rc_miss <- pct_miss(aa$RESULT_CODE); rc_ncat <- n_cats(aa$RESULT_CODE)
  apc <- top_vals(aa, ALL_AIR_PROGRAM_CODES, 4); apc_miss <- pct_miss(aa$ALL_AIR_PROGRAM_CODES); apc_ncat <- n_cats(aa$ALL_AIR_PROGRAM_CODES)
  pc <- top_vals(aa, POLLUTANT_CODE, 4); pc_miss <- pct_miss(aa$POLLUTANT_CODE); pc_ncat <- n_cats(aa$POLLUTANT_CODE)
  avpc <- top_vals(aa, ALL_VIOLATING_POLL_CODES, 4); avpc_miss <- pct_miss(aa$ALL_VIOLATING_POLL_CODES); avpc_ncat <- n_cats(aa$ALL_VIOLATING_POLL_CODES)
  avtc <- top_vals(aa, ALL_VIOLATION_TYPE_CODES, 4); avtc_miss <- pct_miss(aa$ALL_VIOLATION_TYPE_CODES); avtc_ncat <- n_cats(aa$ALL_VIOLATION_TYPE_CODES)

  da_yr <- year(ymd(aa$DATE_ACHIEVED)); da_n_miss <- sum(is.na(da_yr)); da_n <- sum(!is.na(da_yr))
  da_junk <- sum(!is.na(da_yr) & (da_yr < 1970 | da_yr > 2027))
  da <- list(min = min(da_yr, na.rm = TRUE), p5 = as.integer(quantile(da_yr, 0.05, na.rm = TRUE)),
             med = as.integer(median(da_yr, na.rm = TRUE)), p95 = as.integer(quantile(da_yr, 0.95, na.rm = TRUE)), max = max(da_yr, na.rm = TRUE))

  pen_miss <- sum(is.na(aa$PENALTY_AMOUNT)); pen_n <- sum(!is.na(aa$PENALTY_AMOUNT))
  pen_all <- list(min = min(aa$PENALTY_AMOUNT, na.rm = TRUE), p5 = quantile(aa$PENALTY_AMOUNT, 0.05, na.rm = TRUE),
                  med = median(aa$PENALTY_AMOUNT, na.rm = TRUE), p95 = quantile(aa$PENALTY_AMOUNT, 0.95, na.rm = TRUE), max = max(aa$PENALTY_AMOUNT, na.rm = TRUE))
  n_zero <- sum(aa$PENALTY_AMOUNT == 0, na.rm = TRUE)
  pen_nz <- aa |> filter(!is.na(PENALTY_AMOUNT), PENALTY_AMOUNT > 0); n_nonzero <- nrow(pen_nz)
  pen_nz_stats <- list(min = min(pen_nz$PENALTY_AMOUNT), p5 = quantile(pen_nz$PENALTY_AMOUNT, 0.05),
                       med = median(pen_nz$PENALTY_AMOUNT), p95 = quantile(pen_nz$PENALTY_AMOUNT, 0.95), max = max(pen_nz$PENALTY_AMOUNT))

  n_exact_dup <- sum(duplicated(aa))
  apf <- aa |> group_by(AFS_ID) |> summarise(n = n(), .groups = "drop"); max_act <- max(apf$n); med_act <- as.integer(median(apf$n))
  n_dup_anu1 <- sum(duplicated(aa |> select(AFS_ID, ANU1))); n_distinct_anu1 <- n_distinct(aa$ANU1)

  rc_labels <- c("PP"="PP - Stack test passed","FF"="FF - Stack test failed","99"="99 - Pending","MC"="MC - In compliance","MV"="MV - In violation",
    "MU"="MU - Unknown compliance status","FR"="FR - Federally reportable violation","01"="01 - Action achieved","02"="02 - Not achieved")
  rc_descs <- ifelse(rc$RESULT_CODE %in% names(rc_labels), rc_labels[rc$RESULT_CODE], rc$RESULT_CODE)
  apc_code_labels <- c("0"="SIP","1"="FIP (SIP under federal jurisdiction)","3"="Non-federally reportable","4"="CFC Tracking","6"="PSD","7"="NSR",
    "8"="NESHAP (Part 61)","9"="NSPS","A"="Acid Precipitation","F"="FESOP (non-Title V)","I"="Native American","M"="MACT (Part 63 NESHAPS)",
    "T"="TIP (Tribal Implementation Plan)","V"="Title V")
  apc_descs <- sapply(apc$ALL_AIR_PROGRAM_CODES, function(raw) {
    codes <- trimws(strsplit(raw, ",")[[1]])
    labeled <- sapply(codes, function(c) if (c %in% names(apc_code_labels)) apc_code_labels[c] else c, USE.NAMES = FALSE)
    paste0(raw, " (", paste(labeled, collapse = " + "), ")")
  }, USE.NAMES = FALSE)

  crows <- c(
    cat_var("NATIONAL_ACTION_TYPE", "Code for the type of enforcement or compliance action taken.", nat_miss, nat_ncat,
            paste0(nat$NATIONAL_ACTION_TYPE, " - ", trimws(nat$NATIONAL_ACTION_DESC)), nat$n, nat$pct),
    cat_var("RESULT_CODE", "Outcome or compliance result of the action.", rc_miss, rc_ncat, rc_descs, rc$n, rc$pct),
    cat_var("ALL_AIR_PROGRAM_CODES", "Air program codes associated with the action. May contain multiple codes per row.", apc_miss, apc_ncat, apc_descs, apc$n, apc$pct),
    cat_var("POLLUTANT_CODE", "Pollutant associated with the action.", pc_miss, pc_ncat, as.character(pc$POLLUTANT_CODE), pc$n, pc$pct),
    cat_var("ALL_VIOLATING_POLL_CODES", "Pollutant(s) involved in the violation. Space-delimited; may contain multiple codes per row.", avpc_miss, avpc_ncat, as.character(avpc$ALL_VIOLATING_POLL_CODES), avpc$n, avpc$pct),
    cat_var("ALL_VIOLATION_TYPE_CODES", "Three-character violation type codes associated with the action.", avtc_miss, avtc_ncat, as.character(avtc$ALL_VIOLATION_TYPE_CODES), avtc$n, avtc$pct)
  )
  nrows <- c(
    num_row("DATE_ACHIEVED_YEAR", "Date the action was achieved/completed. Parsed from YYYYMMDD format.",
            c(paste0(comma(da_n_miss), " (", round(da_n_miss / n_obs * 100, 1), "%)"), comma(da_n), da$min, da$p5, da$med, da$p95, da$max)),
    num_row("PENALTY_AMOUNT (all)", "Dollar amount of the assessed penalty. Includes $0 values.",
            c(pct_miss(aa$PENALTY_AMOUNT), comma(pen_n), dollar(pen_all$min), dollar(pen_all$p5), dollar(pen_all$med), dollar(pen_all$p95), dollar(pen_all$max))),
    num_row("PENALTY_AMOUNT (nonzero)", paste0("Penalties > $0 only. ", comma(n_zero), " actions (", round(n_zero / n_obs * 100, 1), "%) have $0 penalty."),
            c("N/A", comma(n_nonzero), dollar(pen_nz_stats$min), dollar(pen_nz_stats$p5), dollar(pen_nz_stats$med), dollar(pen_nz_stats$p95), dollar(pen_nz_stats$max)))
  )

  obs_line <- paste0("OBSERVATIONS: ", comma(n_obs), "  |  DISTINCT FACILITIES (AFS_ID): ", comma(n_fac), "  |  TEMPORAL COVERAGE: ", da$min, "–", da$max)
  inv <- "IDENTIFIERS: PLANT_ID, AFS_ID, ANU1  |  METADATA: KEY_ACTION_NUMBERS, CREATION_DATE, DATE_RECORD_IS_UPDATED, REGIONAL_DATA_ELEMENT_8"

  sec(
    h_head("afs_actions", "AFS Actions", "AFS_ACTIONS.csv",
      paste0("Enforcement actions from EPA's legacy Air Facility System (AFS). Includes both formal and informal actions, penalties, ",
             "and compliance outcomes. AFS was replaced by ICIS-Air in October 2014."),
      obs_line, inv),
    cat_table(crows),
    note(paste0("**Top action types: ", trimws(nat$NATIONAL_ACTION_DESC[1]), " (", nat$NATIONAL_ACTION_TYPE[1], ") accounts for ",
      round(nat$pct[1] * 100, 1), "% of all actions. The top 4 action types together account for ", round(sum(nat$pct) * 100, 1),
      "% of the dataset. NATIONAL_ACTION_TYPE has ", nat_ncat, " distinct codes total.")),
    note(paste0("**RESULT_CODE: Only PP, FF, 99, MC, MV, MU, FR, 01, and 02 are defined in the available AFS documentation. ",
      "Numeric codes like 30, 04, 25, 21 appear frequently on inspection/evaluation actions but their meanings are not in the downloaded data dictionary. ",
      "The full code list may be in the AFS Data Download PDF (echo.epa.gov/system/files/AFS_Data_Download.pdf).")),
    note("**ALL_AIR_PROGRAM_CODES contains comma-separated lists of program codes per row. Values shown above are the most common raw combinations, expanded with documented labels."),
    num_table(c("Variable","% Missing","N","Min","P5","Median","P95","Max"), nrows),
    note(paste0("**DATE_ACHIEVED: ", comma(da_junk), " dates fall outside a plausible range (before 1970 or after 2027) and may be data entry errors. ",
      comma(da_n_miss), " rows (", round(da_n_miss / n_obs * 100, 1), "%) have no date recorded.")),
    note(paste0("**", round(n_zero / n_obs * 100, 1), "% of actions carry $0 penalty — most actions are inspections or compliance reviews, not penalty assessments. ",
      "Among nonzero penalties, the median is ", dollar(pen_nz_stats$med), " and the 95th percentile is ", dollar(pen_nz_stats$p95), ". ", comma(pen_miss),
      " rows have PENALTY_AMOUNT missing (distinct from $0, which is explicitly recorded).")),
    dupes(paste0(comma(n_exact_dup), " exact duplicate rows (all 16 columns identical). Actions per facility: median ", med_act, ", max ", comma(max_act),
      ". Facilities with the highest counts likely have long compliance histories spanning AFS's operational period (pre-2014). ",
      "ANU1 appears to be an action sequence number within each facility. There are ", comma(n_distinct_anu1), " distinct ANU1 values. ", comma(n_dup_anu1),
      " rows share an (AFS_ID, ANU1) pair with another row (", round(n_dup_anu1 / n_obs * 100, 1), "%), meaning the combination is ",
      ifelse(n_dup_anu1 == 0, "unique and can serve as a row identifier.", "not fully unique — some actions share the same facility and sequence number.")))
  )
}
