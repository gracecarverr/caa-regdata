# =========================================================================================================
# scripts/tables/pollutants.R — ICIS-AIR_POLLUTANTS summary section.
# Ported from CAA_Project/data_docs/scripts/tables/table-pollutants.R (verbatim stats + content).
# =========================================================================================================
library(here); library(readr); library(dplyr)

build_pollutants_section <- function() {
  pl <- read_csv(here("data/raw/ICIS-AIR_downloads/ICIS-AIR_POLLUTANTS.csv"), show_col_types = FALSE)
  n_obs <- nrow(pl); n_fac <- n_distinct(pl$PGM_SYS_ID)

  pct_miss <- function(x) paste0(round(sum(is.na(x)) / length(x) * 100, 1), "%")
  n_cats   <- function(x) n_distinct(x, na.rm = TRUE)
  top_vals <- function(df, var, n_top = 4) df |> filter(!is.na({{ var }})) |> count({{ var }}) |>
    arrange(desc(n)) |> slice_head(n = n_top) |> mutate(pct = n / nrow(df))

  pld <- top_vals(pl, POLLUTANT_DESC, 5); pld_miss <- pct_miss(pl$POLLUTANT_DESC)
  pld_ncat <- pl |> filter(!is.na(POLLUTANT_CODE), !is.na(POLLUTANT_DESC)) |> distinct(POLLUTANT_CODE, POLLUTANT_DESC) |> nrow()

  apc_all <- pl |> filter(!is.na(AIR_POLLUTANT_CLASS_CODE)) |> count(AIR_POLLUTANT_CLASS_CODE) |> arrange(desc(n))
  apc_top <- apc_all |> slice_head(n = 3) |> mutate(pct = n / nrow(pl))
  apc_other <- apc_all |> slice_tail(n = nrow(apc_all) - 3)
  apc <- bind_rows(apc_top, tibble(AIR_POLLUTANT_CLASS_CODE = "UNK/NAP/OTH", n = sum(apc_other$n), pct = sum(apc_other$n) / nrow(pl)))
  apc_miss <- pct_miss(pl$AIR_POLLUTANT_CLASS_CODE); apc_ncat <- n_cats(pl$AIR_POLLUTANT_CLASS_CODE)

  srs_miss <- pct_miss(pl$SRS_ID); srs_ncat <- n_cats(pl$SRS_ID); srs_n_nonmiss <- sum(!is.na(pl$SRS_ID))
  cas <- top_vals(pl, CHEMICAL_ABSTRACT_SERVICE_NMBR, 4); cas_miss <- pct_miss(pl$CHEMICAL_ABSTRACT_SERVICE_NMBR); cas_ncat <- n_cats(pl$CHEMICAL_ABSTRACT_SERVICE_NMBR)

  n_exact_dup <- sum(duplicated(pl))
  n_class_diff <- pl |> group_by(PGM_SYS_ID, POLLUTANT_CODE) |> filter(n() > 1, n_distinct(AIR_POLLUTANT_CLASS_CODE) > 1) |>
    ungroup() |> distinct(PGM_SYS_ID, POLLUTANT_CODE) |> nrow()

  cas_labels <- c("630080"="Carbon Monoxide (CO)","10102440"="Nitrogen Dioxide (NO2)","7446095"="Sulfur Dioxide (SO2)","50000"="Formaldehyde")
  cas_descs <- paste0(cas$CHEMICAL_ABSTRACT_SERVICE_NMBR, " - ", cas_labels[as.character(cas$CHEMICAL_ABSTRACT_SERVICE_NMBR)])

  crows <- c(
    cat_var("POLLUTANT_DESC", paste0("Name of the pollutant. ", pld_ncat, " distinct pollutants in the dataset."), pld_miss, pld_ncat,
            pld$POLLUTANT_DESC, pld$n, pld$pct),
    cat_var("AIR_POLLUTANT_CLASS_CODE", "Emissions classification of the facility associated with this pollutant record.", apc_miss, apc_ncat,
            c("MIN - Minor Emissions","SMI - Synthetic Minor","MAJ - Major Emissions","UNK/NAP/OTH - Other or Unknown"), apc$n, apc$pct),
    cat_var("SRS_ID", "EPA Substance Registry Services identifier for the pollutant.", srs_miss, srs_ncat,
            c("(Numeric IDs — no human-readable labels)", paste0(srs_ncat, " distinct values")),
            c(srs_n_nonmiss, srs_n_nonmiss), c(srs_n_nonmiss / n_obs, srs_n_nonmiss / n_obs)),
    cat_var("CHEMICAL_ABSTRACT_SERVICE_NMBR", "CAS Registry Number — standard chemical identifier used across databases.", cas_miss, cas_ncat,
            cas_descs, cas$n, cas$pct)
  )

  obs_line <- paste0("OBSERVATIONS: ", comma(n_obs), "  |  DISTINCT FACILITIES: ", comma(n_fac))
  inv <- "IDENTIFIERS: PGM_SYS_ID, POLLUTANT_CODE, SRS_ID  |  TEXT DECODE: AIR_POLLUTANT_CLASS_DESC (label for AIR_POLLUTANT_CLASS_CODE)"

  sec(
    h_head("pollutants", "ICIS-Air Pollutants", "ICIS-AIR_POLLUTANTS.csv",
      paste0("Each row is one facility-pollutant combination — which pollutants each regulated source is associated with. ",
             "A single facility can appear many times if it is linked to multiple pollutants."),
      obs_line, inv),
    cat_table(crows),
    note(paste0("**\"", pld$POLLUTANT_DESC[1], "\" is the most common pollutant entry (", round(pld$pct[1] * 100),
      "%) — it is a facility-level placeholder with no actual pollutant information. The next four are criteria pollutants ",
      "(VOCs, PM, CO, NOx), which together account for another ", round(sum(pld$pct[2:5]) * 100), "% of records.")),
    note(paste0("**SRS_ID (", srs_miss, " missing) and CAS Number (", cas_miss, " missing) are chemical registry identifiers. ",
      "Not all pollutant entries map to a specific chemical compound — entries like FACIL and VOCs are categories, not individual chemicals.")),
    dupes(paste0(comma(n_exact_dup), " exact duplicate rows (", round(n_exact_dup / n_obs * 100, 1),
      "%). Likely a data export artifact — same facility-pollutant record doubled. Users should deduplicate before analysis. ",
      "Beyond exact duplicates, ", comma(n_class_diff), " facility-pollutant pairs have multiple rows that differ only in ",
      "AIR_POLLUTANT_CLASS_CODE — the same facility lists the same pollutant under different emissions classifications (e.g., UNK and MIN). ",
      "This likely reflects reclassification events: a facility's emissions status changed but the old record was retained alongside the new one."))
  )
}
