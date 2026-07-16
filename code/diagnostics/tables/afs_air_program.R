# =========================================================================================================
# code/diagnostics/tables/afs_air_program.R — legacy AFS AIR_PROGRAM summary section.
# Ported from CAA_Project/data_docs/scripts/tables/table-afs-air-program.R (verbatim stats + content).
# =========================================================================================================
library(here); library(readr); library(dplyr)

build_afs_air_program_section <- function() {
  air <- read_csv(here("data/raw/afs_downloads/AIR_PROGRAM.csv"), show_col_types = FALSE)
  n_obs <- nrow(air); n_fac <- n_distinct(air$AFS_ID)

  pct_miss <- function(x) paste0(round(sum(is.na(x)) / length(x) * 100, 1), "%")
  n_cats   <- function(x) n_distinct(x, na.rm = TRUE)
  top_vals <- function(df, var, n_top = 4) df |> filter(!is.na({{ var }})) |> count({{ var }}) |>
    arrange(desc(n)) |> slice_head(n = n_top) |> mutate(pct = n / nrow(df))

  apc <- top_vals(air, AIR_PROGRAM_CODE, 6); apc_miss <- pct_miss(air$AIR_PROGRAM_CODE); apc_ncat <- n_cats(air$AIR_PROGRAM_CODE)
  aps_all <- air |> filter(!is.na(AIR_PROGRAM_STATUS)) |> count(AIR_PROGRAM_STATUS) |> arrange(desc(n)) |> mutate(pct = n / n_obs) |> slice_head(n = 5)
  aps_miss <- pct_miss(air$AIR_PROGRAM_STATUS); aps_ncat <- n_cats(air$AIR_PROGRAM_STATUS)
  ecc_all <- air |> filter(!is.na(EPA_CLASSIFICATION_CODE)) |> mutate(EPA_CLASSIFICATION_CODE = trimws(EPA_CLASSIFICATION_CODE)) |>
    count(EPA_CLASSIFICATION_CODE) |> arrange(desc(n)) |> mutate(pct = n / n_obs)
  ecc_miss <- pct_miss(air$EPA_CLASSIFICATION_CODE); ecc_ncat <- n_cats(air$EPA_CLASSIFICATION_CODE)
  ecs <- top_vals(air, EPA_COMPLIANCE_STATUS, 4); ecs_miss <- pct_miss(air$EPA_COMPLIANCE_STATUS); ecs_ncat <- n_cats(air$EPA_COMPLIANCE_STATUS)
  pcl <- top_vals(air, POLLUTANT_CLASSIFICATION, 4); pcl_miss <- pct_miss(air$POLLUTANT_CLASSIFICATION); pcl_ncat <- n_cats(air$POLLUTANT_CLASSIFICATION)
  pcd <- top_vals(air, POLLUTANT_CODE, 4); pcd_miss <- pct_miss(air$POLLUTANT_CODE); pcd_ncat <- n_cats(air$POLLUTANT_CODE)
  pcs <- top_vals(air, POLLUTANT_COMPLIANCE_STATUS, 4); pcs_miss <- pct_miss(air$POLLUTANT_COMPLIANCE_STATUS); pcs_ncat <- n_cats(air$POLLUTANT_COMPLIANCE_STATUS)

  n_exact_dup <- sum(duplicated(air))
  air_per_fac <- air |> group_by(AFS_ID) |> summarise(n = n(), .groups = "drop")
  n_multi <- sum(air_per_fac$n > 1); max_per_fac <- max(air_per_fac$n); med_per_fac <- as.integer(median(air_per_fac$n))

  apc_code_labels <- c("0"="SIP","1"="FIP (SIP under federal jurisdiction)","3"="Non-federally reportable","4"="CFC Tracking","6"="PSD","7"="NSR",
    "8"="NESHAP (Part 61)","9"="NSPS","A"="Acid Precipitation","F"="FESOP (non-Title V)","I"="Native American","M"="MACT (Part 63 NESHAPS)",
    "T"="TIP (Tribal Implementation Plan)","V"="Title V")
  apc_descs <- ifelse(as.character(apc$AIR_PROGRAM_CODE) %in% names(apc_code_labels),
    paste0(apc$AIR_PROGRAM_CODE, " - ", apc_code_labels[as.character(apc$AIR_PROGRAM_CODE)]), as.character(apc$AIR_PROGRAM_CODE))
  aps_labels <- c("O"="O - Operating","C"="C - Under Construction","P"="P - Planned","T"="T - Temporarily Closed","X"="X - Permanently Closed",
    "I"="I - Seasonal","D"="D - NESHAP Demolition","R"="R - NESHAP Renovation","S"="S - NESHAP Spraying","L"="L - Landfill")
  aps_descs <- ifelse(as.character(aps_all$AIR_PROGRAM_STATUS) %in% names(aps_labels), aps_labels[as.character(aps_all$AIR_PROGRAM_STATUS)], as.character(aps_all$AIR_PROGRAM_STATUS))
  ecc_labels <- c("A"="A - Major: actual/potential emissions above major source thresholds","A1"="A1 - Major: actual/potential controlled >100 tons/year",
    "A2"="A2 - Major: actual <100, potential uncontrolled >100 tons/year","B"="B - Minor: potential uncontrolled <100 tons/year",
    "SM"="SM - Synthetic minor: below all major thresholds via enforceable limits","C"="C - Unregulated pollutant: actual/potential controlled emissions >100 tons/year",
    "UK"="UK - Unknown","ND"="ND - Thresholds not defined")
  ecc_descs <- ifelse(ecc_all$EPA_CLASSIFICATION_CODE %in% names(ecc_labels), ecc_labels[ecc_all$EPA_CLASSIFICATION_CODE], as.character(ecc_all$EPA_CLASSIFICATION_CODE))
  ecs_labels <- c("0"="0 - Unknown","1"="1 - In Violation, No Schedule","2"="2 - In Compliance, Source Test","3"="3 - In Compliance, Inspection",
    "4"="4 - In Compliance, Certification","5"="5 - Meeting Compliance Schedule","6"="6 - In Violation, Not Meeting Schedule","7"="7 - In Violation, Unknown re Schedule",
    "8"="8 - No Applicable State Regulation","9"="9 - In Compliance, Shut Down","D"="D - HPV Violation (auto)","E"="E - FRV Violation (auto)",
    "F"="F - HPV On Schedule (auto)","G"="G - FRV On Schedule (auto)","H"="H - In Compliance (auto)","M"="M - In Compliance, CEMs",
    "A"="A - Unknown re Procedural Compliance","B"="B - In Violation re Both Emissions and Procedural Compliance","C"="C - In Compliance With Procedural Requirements",
    "P"="P - Present, See Other Program(s)","U"="U - Unknown by Evaluation Calculation","W"="W - In Violation re Procedural Compliance",
    "Y"="Y - Unknown re Both Emissions and Procedural Compliance")
  ecs_descs <- ifelse(as.character(ecs$EPA_COMPLIANCE_STATUS) %in% names(ecs_labels), ecs_labels[as.character(ecs$EPA_COMPLIANCE_STATUS)], as.character(ecs$EPA_COMPLIANCE_STATUS))
  pcl_labels <- c("A"="A - Major: above major source thresholds","A1"="A1 - Major: controlled >100 tons/year","A2"="A2 - Major: actual <100, potential >100 tons/year",
    "B"="B - Minor: potential uncontrolled <100 tons/year","SM"="SM - Synthetic minor","C"="C - Unregulated pollutant: actual/potential controlled emissions >100 tons/year",
    "UK"="UK - Unknown","ND"="ND - Thresholds not defined")
  pcl_descs <- ifelse(as.character(pcl$POLLUTANT_CLASSIFICATION) %in% names(pcl_labels), pcl_labels[as.character(pcl$POLLUTANT_CLASSIFICATION)], as.character(pcl$POLLUTANT_CLASSIFICATION))
  pcs_descs <- ifelse(as.character(pcs$POLLUTANT_COMPLIANCE_STATUS) %in% names(ecs_labels), ecs_labels[as.character(pcs$POLLUTANT_COMPLIANCE_STATUS)], as.character(pcs$POLLUTANT_COMPLIANCE_STATUS))

  crows <- c(
    cat_var("AIR_PROGRAM_CODE", "Code for the air program the facility is enrolled in (e.g., Title V, SIP, NESHAP).", apc_miss, apc_ncat, apc_descs, apc$n, apc$pct),
    cat_var("AIR_PROGRAM_STATUS", "Status of the facility's enrollment in the program.", aps_miss, aps_ncat, aps_descs, aps_all$n, aps_all$pct),
    cat_var("EPA_CLASSIFICATION_CODE", "EPA source classification.", ecc_miss, ecc_ncat, ecc_descs, ecc_all$n, ecc_all$pct),
    cat_var("EPA_COMPLIANCE_STATUS", "EPA compliance status code for the facility under this program.", ecs_miss, ecs_ncat, ecs_descs, ecs$n, ecs$pct),
    cat_var("POLLUTANT_CLASSIFICATION", "Emissions classification at the pollutant level (same codes as EPA_CLASSIFICATION_CODE).", pcl_miss, pcl_ncat, pcl_descs, pcl$n, pcl$pct),
    cat_var("POLLUTANT_CODE", "Code identifying the specific pollutant associated with this program enrollment.", pcd_miss, pcd_ncat, as.character(pcd$POLLUTANT_CODE), pcd$n, pcd$pct),
    cat_var("POLLUTANT_COMPLIANCE_STATUS", "Compliance status at the pollutant level (same codes as EPA_COMPLIANCE_STATUS).", pcs_miss, pcs_ncat, pcs_descs, pcs$n, pcs$pct)
  )

  obs_line <- paste0("OBSERVATIONS: ", comma(n_obs), "  |  DISTINCT FACILITIES: ", comma(n_fac))
  inv <- "IDENTIFIERS: AFS_ID, PLANT_ID, AIR_PROGRAM_CODE_SUBPARTS, CHEMICAL_ABSTRACT_SERVICE_NMBR"

  sec(
    h_head("afs_air_program", "AFS Air Programs", "AIR_PROGRAM.csv",
      paste0("Program enrollments from EPA's legacy AFS system. Each row links a facility to an air program with its classification, ",
             "compliance status, and associated pollutants."),
      obs_line, inv),
    cat_table(crows),
    note(paste0("**This dataset has ~1.1M rows because each row is a facility-program-pollutant combination. A single facility enrolled in multiple ",
      "programs with multiple pollutants generates many rows. AIR_PROGRAM_CODE '", apc$AIR_PROGRAM_CODE[1], "' is the most common program (",
      round(apc$pct[1] * 100), "% of rows).")),
    note(paste0("**POLLUTANT_CLASSIFICATION is ", pcl_miss, " missing — not all program rows have an associated pollutant. EPA_COMPLIANCE_STATUS encodes ",
      "compliance as a single character; '", ecs$EPA_COMPLIANCE_STATUS[1], "' is the most common code (", round(ecs$pct[1] * 100), "% of rows).")),
    dupes(paste0("Exact duplicate rows: ", comma(n_exact_dup), ". AFS_ID is not unique — each facility can be enrolled in multiple air programs and each program ",
      "can list multiple pollutants. ", comma(n_multi), " facilities have 2+ rows (max ", comma(max_per_fac), "; median ", med_per_fac,
      "). This is by design: the table is a many-to-many mapping of facilities to programs and pollutants."))
  )
}
