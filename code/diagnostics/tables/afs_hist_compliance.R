# =========================================================================================================
# code/diagnostics/tables/afs_hist_compliance.R — legacy AFS_AIR_PRG_HIST_COMPLIANCE summary section (~10.2M rows).
# Ported from CAA_Project/data_docs/scripts/tables/table-afs-hist-compliance.R (verbatim stats + content).
# =========================================================================================================
library(here); library(readr); library(dplyr)

build_afs_hist_compliance_section <- function() {
  hist <- read_csv(here("data/raw/afs_downloads/AFS_AIR_PRG_HIST_COMPLIANCE.csv"), show_col_types = FALSE)
  n_obs <- nrow(hist); n_fac <- n_distinct(hist$AFS_ID)

  pct_miss <- function(x) paste0(round(sum(is.na(x)) / length(x) * 100, 1), "%")
  n_cats   <- function(x) n_distinct(x, na.rm = TRUE)

  apc <- hist |> filter(!is.na(AIR_PROGRAM_CODE)) |> count(AIR_PROGRAM_CODE) |> arrange(desc(n)) |> slice_head(n = 6) |> mutate(pct = n / n_obs)
  apc_miss <- pct_miss(hist$AIR_PROGRAM_CODE); apc_ncat <- n_cats(hist$AIR_PROGRAM_CODE)
  hcs <- hist |> filter(!is.na(HISTORICAL_COMPLIANCE_STATUS)) |> count(HISTORICAL_COMPLIANCE_STATUS) |> arrange(desc(n)) |> mutate(pct = n / n_obs)
  hcs_miss <- pct_miss(hist$HISTORICAL_COMPLIANCE_STATUS); hcs_ncat <- n_cats(hist$HISTORICAL_COMPLIANCE_STATUS)

  hcd_num <- as.numeric(hist$HISTORICAL_COMPLIANCE_DATE); hcd_n <- sum(!is.na(hcd_num))
  hcd_stats <- list(min = min(hcd_num, na.rm = TRUE), p5 = as.integer(quantile(hcd_num, 0.05, na.rm = TRUE)),
                    med = as.integer(median(hcd_num, na.rm = TRUE)), p95 = as.integer(quantile(hcd_num, 0.95, na.rm = TRUE)), max = max(hcd_num, na.rm = TRUE))

  n_exact_dup <- sum(duplicated(hist))
  fac_recs <- hist |> group_by(AFS_ID) |> summarise(n_rec = n(), .groups = "drop")
  max_per_fac <- max(fac_recs$n_rec); median_per_fac <- median(fac_recs$n_rec)
  n_fac_prog <- n_distinct(hist |> select(AFS_ID, AIR_PROGRAM_CODE))
  fac_prog_recs <- hist |> group_by(AFS_ID, AIR_PROGRAM_CODE) |> summarise(n_rec = n(), .groups = "drop")
  max_per_fp <- max(fac_prog_recs$n_rec); median_per_fp <- median(fac_prog_recs$n_rec)

  apc_code_labels <- c("0"="SIP","1"="FIP (SIP under federal jurisdiction)","3"="Non-federally reportable","4"="CFC Tracking","6"="PSD","7"="NSR",
    "8"="NESHAP (Part 61)","9"="NSPS","A"="Acid Precipitation","F"="FESOP (non-Title V)","I"="Native American","M"="MACT (Part 63 NESHAPS)",
    "T"="TIP (Tribal Implementation Plan)","V"="Title V")
  apc_descs <- ifelse(as.character(apc$AIR_PROGRAM_CODE) %in% names(apc_code_labels),
    paste0(apc$AIR_PROGRAM_CODE, " - ", apc_code_labels[as.character(apc$AIR_PROGRAM_CODE)]), paste0("Code: ", apc$AIR_PROGRAM_CODE))
  hcs_labels <- c("0"="0 - Unknown","1"="1 - In Violation, No Schedule","2"="2 - In Compliance, Source Test","3"="3 - In Compliance, Inspection",
    "4"="4 - In Compliance, Certification","5"="5 - Meeting Compliance Schedule","6"="6 - In Violation, Not Meeting Schedule","7"="7 - In Violation, Unknown re Schedule",
    "8"="8 - No Applicable State Regulation","9"="9 - In Compliance, Shut Down","D"="D - HPV Violation (auto)","E"="E - FRV Violation (auto)",
    "F"="F - HPV On Schedule (auto)","G"="G - FRV On Schedule (auto)","H"="H - In Compliance (auto)","M"="M - In Compliance, CEMs",
    "A"="A - Unknown re Procedural Compliance","B"="B - In Violation re Both Emissions and Procedural Compliance","C"="C - In Compliance With Procedural Requirements",
    "P"="P - Present, See Other Program(s)","U"="U - Unknown by Evaluation Calculation","W"="W - In Violation re Procedural Compliance",
    "Y"="Y - Unknown re Both Emissions and Procedural Compliance")
  hcs_descs <- ifelse(as.character(hcs$HISTORICAL_COMPLIANCE_STATUS) %in% names(hcs_labels),
    hcs_labels[as.character(hcs$HISTORICAL_COMPLIANCE_STATUS)], paste0("Status code: ", hcs$HISTORICAL_COMPLIANCE_STATUS))

  crows <- c(
    cat_var("AIR_PROGRAM_CODE", "Which CAA air program the facility is subject to (legacy AFS codes).", apc_miss, apc_ncat, apc_descs, apc$n, apc$pct),
    cat_var("HISTORICAL_COMPLIANCE_STATUS", "Compliance status at the given date.", hcs_miss, hcs_ncat, hcs_descs, hcs$n, hcs$pct)
  )
  nrows <- num_row("HISTORICAL_COMPLIANCE_DATE", "Raw numeric code (appears to be YYMM — see footnote).",
                   c(pct_miss(hist$HISTORICAL_COMPLIANCE_DATE), comma(hcd_n), hcd_stats$min, hcd_stats$p5, hcd_stats$med, hcd_stats$p95, hcd_stats$max))

  obs_line <- paste0("OBSERVATIONS: ", comma(n_obs), "  |  DISTINCT FACILITIES (AFS_ID): ", comma(n_fac))
  inv <- "IDENTIFIERS: AFS_ID, AIR_PROGRAM_CODE, HISTORICAL_COMPLIANCE_DATE"

  sec(
    h_head("afs_hist_compliance", "AFS Historical Compliance", "AFS_AIR_PRG_HIST_COMPLIANCE.csv",
      paste0("Monthly compliance status snapshots from the legacy AFS system. Each row records one facility-program's compliance status ",
             "at a point in time. This is the historical tracking data that ICIS-Air's current Programs table lacks."),
      obs_line, inv),
    cat_table(crows),
    note(paste0("AIR_PROGRAM_CODE values are legacy AFS codes (e.g., '0', 'V', 'M') that may not directly correspond to the ICIS-Air PROGRAM_CODE values. ",
      "HISTORICAL_COMPLIANCE_STATUS values are single-character codes (both letters and digits) — cross-reference with AFS documentation to decode them ",
      "(e.g., '3', '9', 'C', 'P' may represent different compliance outcomes). We report the raw codes as-is.")),
    num_table(c("Variable","% Missing","N","Min","P5","Median","P95","Max"), nrows),
    note(paste0("HISTORICAL_COMPLIANCE_DATE contains numeric codes, not standard dates. Based on observed values (e.g., 1302, 9801), the format APPEARS to be YYMM — ",
      "where '1302' would mean February 2013 and '9801' would mean January 1998. However, this is an inference from the data values, not confirmed by documentation. ",
      "Verify against AFS data dictionaries before interpreting.")),
    dupes(paste0("(& STRUCTURE) Exact duplicate rows: ", comma(n_exact_dup), " (", round(n_exact_dup / n_obs * 100, 1), "% of all rows). ",
      "Records per facility (AFS_ID): median = ", comma(median_per_fac), ", max = ", comma(max_per_fac), ". Each facility can have many monthly snapshots across multiple programs. ",
      "Distinct facility-program combinations (AFS_ID x AIR_PROGRAM_CODE): ", comma(n_fac_prog), ". Records per facility-program combination: median = ",
      comma(median_per_fp), ", max = ", comma(max_per_fp), ". This tells you how many months of compliance history are available per enrollment — the core time-series depth of this dataset.")),
    note(paste0("This dataset enables tracking compliance changes over time for individual facilities — something ICIS-Air's current Programs snapshot table cannot do. ",
      "By following a facility-program pair across HISTORICAL_COMPLIANCE_DATE values, you can observe when a facility went in or out of compliance and for how long. ",
      "This is the longitudinal backbone of any compliance trend analysis."))
  )
}
