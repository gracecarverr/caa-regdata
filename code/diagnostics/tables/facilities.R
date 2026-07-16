# =========================================================================================================
# code/diagnostics/tables/facilities.R — ICIS-AIR_FACILITIES summary section for docs/index.html.
# Ported from CAA_Project/data_docs/scripts/tables/table-facilities.R: stat code + curated content are
# verbatim; only the output layer (openxlsx -> _html.R) changed. Returns one <section> string.
# =========================================================================================================
library(here); library(readr); library(dplyr)

build_facilities_section <- function() {
  fac <- read_csv(here("data/raw/ICIS-AIR_downloads/ICIS-AIR_FACILITIES.csv"), show_col_types = FALSE)
  n_obs <- nrow(fac)
  n_fac <- n_distinct(fac$PGM_SYS_ID)

  pct_miss <- function(x) paste0(round(sum(is.na(x)) / length(x) * 100, 1), "%")
  n_cats   <- function(x) n_distinct(x, na.rm = TRUE)
  top_vals <- function(df, var, n_top = 4) {
    df |> filter(!is.na({{ var }})) |> count({{ var }}) |> arrange(desc(n)) |>
      slice_head(n = n_top) |> mutate(pct = n / nrow(df))
  }

  # AIR_POLLUTANT_CLASS_CODE — top 3 individually, then sum remaining into "Other"
  apc_all <- fac |> filter(!is.na(AIR_POLLUTANT_CLASS_CODE)) |> count(AIR_POLLUTANT_CLASS_CODE) |> arrange(desc(n))
  apc_top <- apc_all |> slice_head(n = 3) |> mutate(pct = n / n_obs)
  apc_other <- apc_all |> slice_tail(n = nrow(apc_all) - 3)
  apc <- bind_rows(apc_top, tibble(AIR_POLLUTANT_CLASS_CODE = "UNK/NAP/OTH", n = sum(apc_other$n), pct = sum(apc_other$n) / n_obs))
  apc_miss <- pct_miss(fac$AIR_POLLUTANT_CLASS_CODE); apc_ncat <- n_cats(fac$AIR_POLLUTANT_CLASS_CODE)

  # AIR_OPERATING_STATUS_CODE — top 3 individually, then sum remaining into "Other"
  aos_all <- fac |> filter(!is.na(AIR_OPERATING_STATUS_CODE)) |> count(AIR_OPERATING_STATUS_CODE) |> arrange(desc(n))
  aos_top <- aos_all |> slice_head(n = 3) |> mutate(pct = n / n_obs)
  aos_other <- aos_all |> slice_tail(n = nrow(aos_all) - 3)
  aos <- bind_rows(aos_top, tibble(AIR_OPERATING_STATUS_CODE = "PLN/CNS/SEA", n = sum(aos_other$n), pct = sum(aos_other$n) / n_obs))
  aos_miss <- pct_miss(fac$AIR_OPERATING_STATUS_CODE); aos_ncat <- n_cats(fac$AIR_OPERATING_STATUS_CODE)

  # CURRENT_HPV — top 2 individually, then sum remaining into "Other"
  hpv_all <- fac |> filter(!is.na(CURRENT_HPV)) |> count(CURRENT_HPV) |> arrange(desc(n))
  hpv_top <- hpv_all |> slice_head(n = 2) |> mutate(pct = n / n_obs)
  hpv_other <- hpv_all |> slice_tail(n = nrow(hpv_all) - 2)
  hpv <- bind_rows(hpv_top, tibble(CURRENT_HPV = "Other HPV statuses", n = sum(hpv_other$n), pct = sum(hpv_other$n) / n_obs))
  hpv_miss <- pct_miss(fac$CURRENT_HPV); hpv_ncat <- n_cats(fac$CURRENT_HPV)

  # FACILITY_TYPE_CODE — top 3 individually, then sum remaining into "Other"
  ftc_all <- fac |> filter(!is.na(FACILITY_TYPE_CODE)) |> count(FACILITY_TYPE_CODE) |> arrange(desc(n))
  ftc_top <- ftc_all |> slice_head(n = 3) |> mutate(pct = n / n_obs)
  ftc_other <- ftc_all |> slice_tail(n = nrow(ftc_all) - 3)
  ftc <- bind_rows(ftc_top, tibble(FACILITY_TYPE_CODE = "Other", n = sum(ftc_other$n), pct = sum(ftc_other$n) / n_obs))
  ftc_miss <- pct_miss(fac$FACILITY_TYPE_CODE); ftc_ncat <- n_cats(fac$FACILITY_TYPE_CODE)

  # STATE — top 4 with names looked up from data
  st <- fac |> filter(!is.na(STATE)) |> count(STATE) |> arrange(desc(n)) |> slice_head(n = 4) |> mutate(pct = n / n_obs)
  st_miss <- pct_miss(fac$STATE); st_ncat <- n_cats(fac$STATE)

  epa <- top_vals(fac, EPA_REGION, 4); epa_miss <- pct_miss(fac$EPA_REGION); epa_ncat <- n_cats(fac$EPA_REGION)
  sic <- top_vals(fac, SIC_CODES, 4);  sic_miss <- pct_miss(fac$SIC_CODES);  sic_ncat <- n_cats(fac$SIC_CODES)
  nai <- top_vals(fac, NAICS_CODES, 4); nai_miss <- pct_miss(fac$NAICS_CODES); nai_ncat <- n_cats(fac$NAICS_CODES)
  lcr <- top_vals(fac, LOCAL_CONTROL_REGION_CODE, 4); lcr_miss <- pct_miss(fac$LOCAL_CONTROL_REGION_CODE); lcr_ncat <- n_cats(fac$LOCAL_CONTROL_REGION_CODE)

  ft_miss <- c(FACILITY_NAME = pct_miss(fac$FACILITY_NAME), STREET_ADDRESS = pct_miss(fac$STREET_ADDRESS),
               CITY = pct_miss(fac$CITY), COUNTY_NAME = pct_miss(fac$COUNTY_NAME), ZIP_CODE = pct_miss(fac$ZIP_CODE))

  # Duplicates
  n_reg_multi <- fac |> group_by(REGISTRY_ID) |> summarise(n = n(), .groups = "drop") |> filter(n > 1) |> nrow()

  # ---- curated value labels ----
  state_names <- c(AL="Alabama",AK="Alaska",AZ="Arizona",AR="Arkansas",CA="California",CO="Colorado",CT="Connecticut",
    DE="Delaware",FL="Florida",GA="Georgia",HI="Hawaii",ID="Idaho",IL="Illinois",IN="Indiana",IA="Iowa",KS="Kansas",
    KY="Kentucky",LA="Louisiana",ME="Maine",MD="Maryland",MA="Massachusetts",MI="Michigan",MN="Minnesota",MS="Mississippi",
    MO="Missouri",MT="Montana",NE="Nebraska",NV="Nevada",NH="New Hampshire",NJ="New Jersey",NM="New Mexico",NY="New York",
    NC="North Carolina",ND="North Dakota",OH="Ohio",OK="Oklahoma",OR="Oregon",PA="Pennsylvania",RI="Rhode Island",
    SC="South Carolina",SD="South Dakota",TN="Tennessee",TX="Texas",UT="Utah",VT="Vermont",VA="Virginia",WA="Washington",
    WV="West Virginia",WI="Wisconsin",WY="Wyoming",DC="District of Columbia",PR="Puerto Rico",VI="Virgin Islands",
    GU="Guam",AS="American Samoa",MP="Northern Mariana Islands")
  st_descs  <- paste0(st$STATE, " - ", state_names[st$STATE])
  epa_labels <- c("06"="South Central (TX, NM, OK, AR, LA)","05"="Great Lakes (IL, IN, MI, MN, OH, WI)",
                  "08"="Mountain (CO, MT, ND, SD, UT, WY)","03"="Mid-Atlantic (DE, DC, MD, PA, VA, WV)")
  epa_descs <- paste0(epa$EPA_REGION, " - ", epa_labels[epa$EPA_REGION])
  sic_labels <- c("1311"="Crude Petroleum & Natural Gas","7216"="Drycleaning Plants",
                  "5541"="Gasoline Service Stations","1321"="Natural Gas Liquids")
  sic_descs <- paste0(sic$SIC_CODES, " - ", sic_labels[sic$SIC_CODES])

  rows <- c(
    cat_var("AIR_POLLUTANT_CLASS_CODE", "Emissions classification based on potential to emit.", apc_miss, apc_ncat,
            c("MIN - Minor Emissions","SMI - Synthetic Minor Emissions","MAJ - Major Emissions","UNK/NAP/OTH - Other or Unknown"), apc$n, apc$pct),
    cat_var("AIR_OPERATING_STATUS_CODE", "Current operating status of the facility.", aos_miss, aos_ncat,
            c("OPR - Operating","CLS - Permanently Closed","TMP - Temporarily Closed","PLN/CNS/SEA - Other"), aos$n, aos$pct),
    cat_var("CURRENT_HPV", "Current high priority violation status.", hpv_miss, hpv_ncat,
            c("No Violation Identified","Violation w/in 1 Year","Other HPV statuses"), hpv$n, hpv$pct),
    cat_var("FACILITY_TYPE_CODE", "Ownership type of the facility.", ftc_miss, ftc_ncat,
            c("POF - Privately Owned Facility","NON - Non-Federal Government","COR - Corporation","Other types"), ftc$n, ftc$pct),
    cat_var("STATE", "U.S. state or territory where the facility is located.", st_miss, st_ncat, st_descs, st$n, st$pct),
    cat_var("EPA_REGION", "EPA administrative region (1-10) overseeing the facility.", epa_miss, epa_ncat, epa_descs, epa$n, epa$pct),
    cat_var("SIC_CODES", "Standard Industrial Classification code(s). Can list multiple codes per facility.", sic_miss, sic_ncat, sic_descs, sic$n, sic$pct),
    cat_var("NAICS_CODES", "North American Industry Classification System code(s). Can list multiple codes per facility.", nai_miss, nai_ncat,
            c("999999 - Unclassified","211111 - Crude Petroleum & Natural Gas Extraction","812320 - Drycleaning & Laundry Services","211112/211130 - Natural Gas Extraction"), nai$n, nai$pct),
    cat_var("LOCAL_CONTROL_REGION_CODE", "Local air quality management district. Only populated for states with local agencies.", lcr_miss, lcr_ncat,
            c("PLK - Polk County","ACH - Allegheny County Health","COA - City of Albuquerque (NM)","SCA - South Coast AQMD"), lcr$n, lcr$pct)
  )

  obs_line <- paste0("OBSERVATIONS: ", comma(n_obs), "  |  DISTINCT FACILITIES: ", comma(n_fac))
  inv <- paste0("IDENTIFIERS: PGM_SYS_ID, REGISTRY_ID  |  ",
    "LOCATION: STREET_ADDRESS, CITY, COUNTY_NAME, STATE, ZIP_CODE, EPA_REGION  |  ",
    "INDUSTRY: SIC_CODES, NAICS_CODES  |  ",
    "TEXT DECODES: AIR_POLLUTANT_CLASS_DESC, AIR_OPERATING_STATUS_DESC, LOCAL_CONTROL_REGION_NAME (labels for the matching _CODEs)")

  ft_note <- paste0("FREE-TEXT FIELDS (not tabulated): FACILITY_NAME (", ft_miss["FACILITY_NAME"], " missing), ",
    "STREET_ADDRESS (", ft_miss["STREET_ADDRESS"], " missing), CITY (", ft_miss["CITY"], " missing), ",
    "COUNTY_NAME (", ft_miss["COUNTY_NAME"], " missing), ZIP_CODE (", ft_miss["ZIP_CODE"], " missing).")

  sec(
    h_head("facilities", "ICIS-Air Facilities", "ICIS-AIR_FACILITIES.csv",
      paste0("The universe of stationary sources regulated under the Clean Air Act. ",
             "Each row is one facility, identified by a unique program system ID. ",
             "Includes location, industry codes, emissions classification, and operating status."),
      obs_line, inv),
    cat_table(rows),
    note(ft_note),
    note(paste0("**Major sources are facilities with potential to emit above regulatory thresholds ",
      "(e.g., 100 tons/year of a criteria pollutant). Synthetic minor sources have accepted enforceable ",
      "limits to stay below the major threshold. Minor sources are below the threshold without needing limits.")),
    note(paste0("**", round(hpv$pct[1] * 100, 1), "% of facilities have no current HPV. Only ~",
      round((1 - hpv$pct[1]) * 100), "% have an active high priority violation — these are the most serious ",
      "noncompliance cases tracked by EPA.")),
    note(paste0("**SIC_CODES (", sic_miss, " missing) are the legacy industry classification. NAICS_CODES replaced SIC ",
      "in 1997 but both are maintained. ", round(nai$pct[1] * 100, 1), "% of facilities have NAICS code 999999 ",
      "(Unclassified). LOCAL_CONTROL_REGION_CODE is ", lcr_miss, " missing — only populated in states with local air agencies.")),
    dupes(paste0("No exact duplicate rows. PGM_SYS_ID is unique (one row per facility). However, ",
      comma(n_reg_multi), " REGISTRY_IDs (", round(n_reg_multi / n_distinct(fac$REGISTRY_ID) * 100, 1),
      "%) map to multiple PGM_SYS_IDs — these are cases where the same physical location has multiple facility ",
      "records, likely due to ownership changes, permit restructuring, or separate program-system registrations at a single site."))
  )
}
