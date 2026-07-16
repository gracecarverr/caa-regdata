# =========================================================================================================
# code/diagnostics/tables/afs_facilities.R — legacy AFS_FACILITIES summary section.
# Ported from CAA_Project/data_docs/scripts/tables/table-afs-facilities.R (verbatim stats + content).
# =========================================================================================================
library(here); library(readr); library(dplyr)

build_afs_facilities_section <- function() {
  fac <- read_csv(here("data/raw/afs_downloads/AFS_FACILITIES.csv"), show_col_types = FALSE)
  n_obs <- nrow(fac); n_fac <- n_distinct(fac$AFS_ID); n_plant <- n_distinct(fac$PLANT_ID)
  id_mapping <- fac |> group_by(PLANT_ID) |> summarise(n_afs = n_distinct(AFS_ID), .groups = "drop")
  plant_multi <- id_mapping |> filter(n_afs > 1) |> nrow(); id_one_to_one <- (plant_multi == 0)

  pct_miss <- function(x) paste0(round(sum(is.na(x)) / length(x) * 100, 1), "%")
  n_cats   <- function(x) n_distinct(x, na.rm = TRUE)
  top_vals <- function(df, var, n_top = 4) df |> filter(!is.na({{ var }})) |> count({{ var }}) |>
    arrange(desc(n)) |> slice_head(n = n_top) |> mutate(pct = n / nrow(df))
  all_vals <- function(df, var) df |> filter(!is.na({{ var }})) |> count({{ var }}) |> arrange(desc(n)) |> mutate(pct = n / n_obs)

  st <- top_vals(fac, STATE, 4);  st_miss <- pct_miss(fac$STATE);  st_ncat <- n_cats(fac$STATE)
  epa <- top_vals(fac, EPA_REGION, 4); epa_miss <- pct_miss(fac$EPA_REGION); epa_ncat <- n_cats(fac$EPA_REGION)
  ecc_all <- all_vals(fac, EPA_CLASSIFICATION_CODE); ecc_miss <- pct_miss(fac$EPA_CLASSIFICATION_CODE); ecc_ncat <- n_cats(fac$EPA_CLASSIFICATION_CODE)
  os_all <- all_vals(fac, OPERATING_STATUS); os_miss <- pct_miss(fac$OPERATING_STATUS); os_ncat <- n_cats(fac$OPERATING_STATUS)
  ecs <- top_vals(fac, EPA_COMPLIANCE_STATUS, 4); ecs_miss <- pct_miss(fac$EPA_COMPLIANCE_STATUS); ecs_ncat <- n_cats(fac$EPA_COMPLIANCE_STATUS)
  hpv_all <- all_vals(fac, CURRENT_HPV); hpv_miss <- pct_miss(fac$CURRENT_HPV); hpv_ncat <- n_cats(fac$CURRENT_HPV)
  fr_all <- all_vals(fac, FEDERALLY_REPORTABLE); fr_miss <- pct_miss(fac$FEDERALLY_REPORTABLE); fr_ncat <- n_cats(fac$FEDERALLY_REPORTABLE)
  sic <- top_vals(fac, PRIMARY_SIC_CODE, 4); sic_miss <- pct_miss(fac$PRIMARY_SIC_CODE); sic_ncat <- n_cats(fac$PRIMARY_SIC_CODE)
  sic2 <- top_vals(fac, SECONDARY_SIC_CODE, 4); sic2_miss <- pct_miss(fac$SECONDARY_SIC_CODE); sic2_ncat <- n_cats(fac$SECONDARY_SIC_CODE)
  nai <- top_vals(fac, NAICS_CODE, 4); nai_miss <- pct_miss(fac$NAICS_CODE); nai_ncat <- n_cats(fac$NAICS_CODE)
  scs <- top_vals(fac, STATE_COMPLIANCE_STATUS, 4); scs_miss <- pct_miss(fac$STATE_COMPLIANCE_STATUS); scs_ncat <- n_cats(fac$STATE_COMPLIANCE_STATUS)
  gov_all <- all_vals(fac, AFS_GOV_FACILITY_CODE); gov_miss <- pct_miss(fac$AFS_GOV_FACILITY_CODE); gov_ncat <- n_cats(fac$AFS_GOV_FACILITY_CODE)
  lcr <- top_vals(fac, LOCAL_CONTROL_REGION, 4); lcr_miss <- pct_miss(fac$LOCAL_CONTROL_REGION); lcr_ncat <- n_cats(fac$LOCAL_CONTROL_REGION)

  ft_miss <- c(PLANT_NAME = pct_miss(fac$PLANT_NAME), PLANT_STREET_ADDRESS = pct_miss(fac$PLANT_STREET_ADDRESS),
               PLANT_CITY = pct_miss(fac$PLANT_CITY), PLANT_COUNTY = pct_miss(fac$PLANT_COUNTY), ZIP_CODE = pct_miss(fac$ZIP_CODE))

  n_exact_dup <- sum(duplicated(fac))
  afs_dup_tbl <- fac |> group_by(AFS_ID) |> summarise(n = n(), .groups = "drop")
  n_afs_multi <- afs_dup_tbl |> filter(n > 1) |> nrow(); max_afs_dup <- max(afs_dup_tbl$n)
  state_dist <- fac |> filter(!is.na(STATE)) |> group_by(STATE) |> summarise(n = n(), .groups = "drop")
  max_state <- state_dist |> slice_max(n, n = 1); median_state <- median(state_dist$n)

  state_names <- c(AL="Alabama",AK="Alaska",AZ="Arizona",AR="Arkansas",CA="California",CO="Colorado",CT="Connecticut",
    DE="Delaware",FL="Florida",GA="Georgia",HI="Hawaii",ID="Idaho",IL="Illinois",IN="Indiana",IA="Iowa",KS="Kansas",
    KY="Kentucky",LA="Louisiana",ME="Maine",MD="Maryland",MA="Massachusetts",MI="Michigan",MN="Minnesota",MS="Mississippi",
    MO="Missouri",MT="Montana",NE="Nebraska",NV="Nevada",NH="New Hampshire",NJ="New Jersey",NM="New Mexico",NY="New York",
    NC="North Carolina",ND="North Dakota",OH="Ohio",OK="Oklahoma",OR="Oregon",PA="Pennsylvania",RI="Rhode Island",
    SC="South Carolina",SD="South Dakota",TN="Tennessee",TX="Texas",UT="Utah",VT="Vermont",VA="Virginia",WA="Washington",
    WV="West Virginia",WI="Wisconsin",WY="Wyoming",DC="District of Columbia",PR="Puerto Rico",VI="Virgin Islands",
    GU="Guam",AS="American Samoa",MP="Northern Mariana Islands")
  st_descs <- paste0(st$STATE, " - ", state_names[st$STATE])
  epa_labels <- c("01"="New England (CT, ME, MA, NH, RI, VT)","02"="NY/NJ (NY, NJ, PR, VI)","03"="Mid-Atlantic (DE, DC, MD, PA, VA, WV)",
    "04"="Southeast (AL, FL, GA, KY, MS, NC, SC, TN)","05"="Great Lakes (IL, IN, MI, MN, OH, WI)","06"="South Central (TX, NM, OK, AR, LA)",
    "07"="Central (IA, KS, MO, NE)","08"="Mountain (CO, MT, ND, SD, UT, WY)","09"="Pacific SW (AZ, CA, HI, NV, GU, AS)","10"="Pacific NW (AK, ID, OR, WA)")
  epa_descs <- ifelse(as.character(epa$EPA_REGION) %in% names(epa_labels), paste0(epa$EPA_REGION, " - ", epa_labels[as.character(epa$EPA_REGION)]), as.character(epa$EPA_REGION))
  ecc_labels <- c("A"="A - Major: actual/potential emissions above major source thresholds","A1"="A1 - Major: actual/potential controlled >100 tons/year",
    "A2"="A2 - Major: actual <100, potential uncontrolled >100 tons/year","B"="B - Minor: potential uncontrolled <100 tons/year",
    "SM"="SM - Synthetic minor: below all major thresholds via enforceable limits","C"="C - Unregulated pollutant: actual/potential controlled emissions >100 tons/year",
    "UK"="UK - Unknown","ND"="ND - Thresholds not defined")
  ecc_descs <- ifelse(ecc_all$EPA_CLASSIFICATION_CODE %in% names(ecc_labels), ecc_labels[ecc_all$EPA_CLASSIFICATION_CODE], as.character(ecc_all$EPA_CLASSIFICATION_CODE))
  os_labels <- c("O"="O - Operating","C"="C - Under Construction","P"="P - Planned","T"="T - Temporarily Closed","X"="X - Permanently Closed",
    "I"="I - Seasonal","D"="D - NESHAP Demolition","R"="R - NESHAP Renovation","S"="S - NESHAP Spraying","L"="L - Landfill")
  os_descs <- ifelse(os_all$OPERATING_STATUS %in% names(os_labels), os_labels[os_all$OPERATING_STATUS], as.character(os_all$OPERATING_STATUS))
  ecs_labels <- c("0"="0 - Unknown","1"="1 - In Violation, No Schedule","2"="2 - In Compliance, Source Test","3"="3 - In Compliance, Inspection",
    "4"="4 - In Compliance, Certification","5"="5 - Meeting Compliance Schedule","6"="6 - In Violation, Not Meeting Schedule","7"="7 - In Violation, Unknown re Schedule",
    "8"="8 - No Applicable State Regulation","9"="9 - In Compliance, Shut Down","D"="D - HPV Violation (auto)","E"="E - FRV Violation (auto)",
    "F"="F - HPV On Schedule (auto)","G"="G - FRV On Schedule (auto)","H"="H - In Compliance (auto)","M"="M - In Compliance, CEMs",
    "A"="A - Unknown re Procedural Compliance","B"="B - In Violation re Both Emissions and Procedural Compliance","C"="C - In Compliance With Procedural Requirements",
    "P"="P - Present, See Other Program(s)","U"="U - Unknown by Evaluation Calculation","W"="W - In Violation re Procedural Compliance",
    "Y"="Y - Unknown re Both Emissions and Procedural Compliance")
  ecs_descs <- ifelse(as.character(ecs$EPA_COMPLIANCE_STATUS) %in% names(ecs_labels), ecs_labels[as.character(ecs$EPA_COMPLIANCE_STATUS)], as.character(ecs$EPA_COMPLIANCE_STATUS))
  hpv_labels <- c("S"="S - Unaddressed, state/local lead","T"="T - Addressed, state lead","E"="E - Unaddressed, EPA lead","F"="F - Addressed, EPA lead",
    "B"="B - Unaddressed, shared lead","C"="C - Addressed, shared lead","X"="X - Unaddressed, lead unassigned")
  hpv_descs <- ifelse(hpv_all$CURRENT_HPV %in% names(hpv_labels), hpv_labels[hpv_all$CURRENT_HPV], as.character(hpv_all$CURRENT_HPV))
  scs_descs <- ifelse(as.character(scs$STATE_COMPLIANCE_STATUS) %in% names(ecs_labels), ecs_labels[as.character(scs$STATE_COMPLIANCE_STATUS)], as.character(scs$STATE_COMPLIANCE_STATUS))
  gov_labels <- c("0"="0 - Privately owned/operated","1"="1 - Federal","2"="2 - State","3"="3 - County","4"="4 - Municipality","5"="5 - District","6"="6 - Tribe")
  gov_descs <- ifelse(as.character(gov_all$AFS_GOV_FACILITY_CODE) %in% names(gov_labels), gov_labels[as.character(gov_all$AFS_GOV_FACILITY_CODE)], as.character(gov_all$AFS_GOV_FACILITY_CODE))

  crows <- c(
    cat_var("STATE", "U.S. state or territory where the facility is located.", st_miss, st_ncat, st_descs, st$n, st$pct),
    cat_var("EPA_REGION", "EPA administrative region (1-10) overseeing the facility.", epa_miss, epa_ncat, epa_descs, epa$n, epa$pct),
    cat_var("EPA_CLASSIFICATION_CODE", "Emissions classification (major/minor/synthetic minor).", ecc_miss, ecc_ncat, ecc_descs, ecc_all$n, ecc_all$pct),
    cat_var("OPERATING_STATUS", "Current operating status of the facility.", os_miss, os_ncat, os_descs, os_all$n, os_all$pct),
    cat_var("EPA_COMPLIANCE_STATUS", "EPA compliance status code for the facility.", ecs_miss, ecs_ncat, ecs_descs, ecs$n, ecs$pct),
    cat_var("CURRENT_HPV", "Current high priority violation status.", hpv_miss, hpv_ncat, hpv_descs, hpv_all$n, hpv_all$pct),
    cat_var("FEDERALLY_REPORTABLE", "Whether the facility must report to the federal EPA system.", fr_miss, fr_ncat, as.character(fr_all$FEDERALLY_REPORTABLE), fr_all$n, fr_all$pct),
    cat_var("PRIMARY_SIC_CODE", "Primary Standard Industrial Classification code for the facility.", sic_miss, sic_ncat, as.character(sic$PRIMARY_SIC_CODE), sic$n, sic$pct),
    cat_var("SECONDARY_SIC_CODE", "Secondary SIC code — a second industry where the facility spans two (blank for most).", sic2_miss, sic2_ncat, as.character(sic2$SECONDARY_SIC_CODE), sic2$n, sic2$pct),
    cat_var("NAICS_CODE", "Six-digit NAICS industry code (modern successor to SIC).", nai_miss, nai_ncat, as.character(nai$NAICS_CODE), nai$n, nai$pct),
    cat_var("STATE_COMPLIANCE_STATUS", "State agency compliance determination (same code set as EPA_COMPLIANCE_STATUS).", scs_miss, scs_ncat, scs_descs, scs$n, scs$pct),
    cat_var("AFS_GOV_FACILITY_CODE", "Government ownership level of the facility.", gov_miss, gov_ncat, gov_descs, gov_all$n, gov_all$pct),
    cat_var("LOCAL_CONTROL_REGION", "Two-character local control region code (meanings vary by state).", lcr_miss, lcr_ncat, as.character(lcr$LOCAL_CONTROL_REGION), lcr$n, lcr$pct)
  )

  ft_note <- paste0("FREE-TEXT / LOCATION FIELDS (not tabulated): PLANT_NAME (", ft_miss["PLANT_NAME"], " missing), PLANT_STREET_ADDRESS (",
    ft_miss["PLANT_STREET_ADDRESS"], " missing), PLANT_CITY (", ft_miss["PLANT_CITY"], " missing), PLANT_COUNTY (", ft_miss["PLANT_COUNTY"],
    " missing), ZIP_CODE (", ft_miss["ZIP_CODE"], " missing).")
  id_note <- if (id_one_to_one) paste0("PLANT_ID and AFS_ID have a 1:1 mapping — every PLANT_ID corresponds to exactly one AFS_ID. There are ",
      comma(n_plant), " distinct PLANT_IDs and ", comma(n_fac), " distinct AFS_IDs.") else
    paste0("PLANT_ID and AFS_ID are NOT 1:1. There are ", comma(n_plant), " distinct PLANT_IDs vs. ", comma(n_fac), " distinct AFS_IDs. ",
      comma(plant_multi), " PLANT_IDs map to more than one AFS_ID.")
  afs_dup_note <- if (n_afs_multi == 0) "AFS_ID is unique (one row per facility)." else
    paste0(comma(n_afs_multi), " AFS_IDs appear in more than one row (max ", max_afs_dup, " rows per AFS_ID).")

  obs_line <- paste0("OBSERVATIONS: ", comma(n_obs), "  |  DISTINCT FACILITIES (AFS_ID): ", comma(n_fac))
  inv <- "IDENTIFIERS: PLANT_ID, AFS_ID, STATE_NUMBER"

  sec(
    h_head("afs_facilities", "AFS Facilities", "AFS_FACILITIES.csv",
      paste0("Air Facility System (AFS) — EPA's legacy air quality compliance database, replaced by ICIS-Air in October 2014. ",
             "Each row is one regulated air pollution source."),
      obs_line, inv),
    cat_table(crows),
    note(ft_note),
    note(paste0("**IDENTIFIERS: ", id_note)),
    note(paste0("**Top PRIMARY_SIC_CODEs: ", paste0(sic$PRIMARY_SIC_CODE, " (n=", comma(sic$n), ")", collapse = ", "),
      ". SIC codes are 4-digit industry classifiers; look up at https://www.osha.gov/data/sic-manual.")),
    dupes(paste0("Exact duplicate rows: ", comma(n_exact_dup), ". ", afs_dup_note,
      " Facilities per state: max = ", comma(max_state$n), " (", max_state$STATE, "), median = ", comma(median_state), "."))
  )
}
