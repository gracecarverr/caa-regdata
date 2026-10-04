# =========================================================================================================
# code/diagnostics/tables/emissions.R — POLL_RPT_COMBINED_EMISSIONS summary section (~10.4M rows).
# Ported from CAA_Project/data_docs/scripts/tables/table-emissions.R (verbatim stats + content).
# Uses data.table::fread (not readr/dplyr) — the 880MB source file OOM'd this section under readr/dplyr's
# higher per-copy memory overhead on an 8GB machine; fread + in-place `:=` keeps peak memory well below that.
# na.strings = c("NA", "") matches readr::read_csv's default NA rule so missingness counts are unchanged.
# =========================================================================================================
library(here); library(data.table)

build_emissions_section <- function() {
  em <- fread(here("data/raw/POLL_RPT_COMBINED_EMISSIONS.csv"), na.strings = c("NA", ""))
  n_obs <- nrow(em); n_fac <- uniqueN(em$REGISTRY_ID, na.rm = TRUE); n_pgm <- uniqueN(em$PGM_SYS_ID, na.rm = TRUE)

  pct_miss <- function(x) paste0(round(sum(is.na(x)) / length(x) * 100, 1), "%")
  n_cats   <- function(x) uniqueN(x, na.rm = TRUE)
  count_col <- function(col, top_n = Inf) {
    agg <- em[!is.na(get(col)), .N, by = col]
    setnames(agg, "N", "n")
    setorderv(agg, "n", order = -1L)
    if (is.finite(top_n)) agg <- head(agg, top_n)
    agg[, pct := n / n_obs]
    agg
  }

  psa_all <- count_col("PGM_SYS_ACRNM");  psa_miss <- pct_miss(em$PGM_SYS_ACRNM);  psa_ncat <- n_cats(em$PGM_SYS_ACRNM)
  pol     <- count_col("POLLUTANT_NAME", top_n = 6); pol_miss <- pct_miss(em$POLLUTANT_NAME); pol_ncat <- n_cats(em$POLLUTANT_NAME)
  uom_all <- count_col("UNIT_OF_MEASURE"); uom_miss <- pct_miss(em$UNIT_OF_MEASURE); uom_ncat <- n_cats(em$UNIT_OF_MEASURE)
  nei_all <- count_col("NEI_TYPE");        nei_miss <- pct_miss(em$NEI_TYPE);        nei_ncat <- n_cats(em$NEI_TYPE)
  nhv_all <- count_col("NEI_HAP_VOC_FLAG"); nhv_miss <- pct_miss(em$NEI_HAP_VOC_FLAG); nhv_ncat <- n_cats(em$NEI_HAP_VOC_FLAG)

  ry_n <- sum(!is.na(em$REPORTING_YEAR))
  ry <- list(min = min(em$REPORTING_YEAR, na.rm = TRUE), p5 = as.integer(quantile(em$REPORTING_YEAR, 0.05, na.rm = TRUE)),
             med = as.integer(median(em$REPORTING_YEAR, na.rm = TRUE)), p95 = as.integer(quantile(em$REPORTING_YEAR, 0.95, na.rm = TRUE)), max = max(em$REPORTING_YEAR, na.rm = TRUE))
  ae_n <- sum(!is.na(em$ANNUAL_EMISSION)); ae_zeros <- sum(em$ANNUAL_EMISSION == 0, na.rm = TRUE); ae_negatives <- sum(em$ANNUAL_EMISSION < 0, na.rm = TRUE)
  ae <- list(min = min(em$ANNUAL_EMISSION, na.rm = TRUE), p5 = quantile(em$ANNUAL_EMISSION, 0.05, na.rm = TRUE),
             med = median(em$ANNUAL_EMISSION, na.rm = TRUE), p95 = quantile(em$ANNUAL_EMISSION, 0.95, na.rm = TRUE), max = max(em$ANNUAL_EMISSION, na.rm = TRUE))

  n_exact_dup <- sum(duplicated(em))
  rpf <- em[, .N, by = REGISTRY_ID]
  rpf_med <- as.integer(median(rpf$N)); rpf_max <- max(rpf$N); rpf_multi <- sum(rpf$N > 1)
  fpy <- em[, .N, by = .(REGISTRY_ID, POLLUTANT_NAME, REPORTING_YEAR)]
  fpy_dups <- fpy[N > 1]
  n_fpy_dup_combos <- nrow(fpy_dups); n_fpy_dup_rows <- sum(fpy_dups$N)
  pgm_shares <- count_col("PGM_SYS_ACRNM")[, pct := round(n / sum(n) * 100, 1)]

  crows <- c(
    cat_var("PGM_SYS_ACRNM", "Reporting program acronym (e.g., TRIS = TRI, EIS = NEI). Tells you the source system.", psa_miss, psa_ncat, psa_all$PGM_SYS_ACRNM, psa_all$n, psa_all$pct),
    cat_var("POLLUTANT_NAME", paste0("Name of the pollutant. ", pol_ncat, " distinct pollutants in the dataset."), pol_miss, pol_ncat, pol$POLLUTANT_NAME, pol$n, pol$pct),
    cat_var("UNIT_OF_MEASURE", "Unit for ANNUAL_EMISSION (e.g., Pounds, Tons).", uom_miss, uom_ncat, uom_all$UNIT_OF_MEASURE, uom_all$n, uom_all$pct),
    if (nrow(nei_all) > 0)
      cat_var("NEI_TYPE", "National Emissions Inventory type classification. Only populated for NEI records.", nei_miss, nei_ncat, nei_all$NEI_TYPE, nei_all$n, nei_all$pct)
    else cat_var("NEI_TYPE", "National Emissions Inventory type classification. Only populated for NEI records.", nei_miss, nei_ncat, "(all missing)", 0, 0),
    if (nrow(nhv_all) > 0)
      cat_var("NEI_HAP_VOC_FLAG", "Flags whether the pollutant is a HAP or VOC in the NEI system.", nhv_miss, nhv_ncat, nhv_all$NEI_HAP_VOC_FLAG, nhv_all$n, nhv_all$pct)
    else cat_var("NEI_HAP_VOC_FLAG", "Flags whether the pollutant is a HAP or VOC in the NEI system.", nhv_miss, nhv_ncat, "(all missing)", 0, 0)
  )
  nrows <- c(
    num_row("REPORTING_YEAR", "Year of the emissions report.", c(pct_miss(em$REPORTING_YEAR), comma(ry_n), ry$min, ry$p5, ry$med, ry$p95, ry$max)),
    num_row("ANNUAL_EMISSION", paste0("Annual emission quantity. ", comma(ae_zeros), " zeros, ", comma(ae_negatives), " negatives."),
            c(pct_miss(em$ANNUAL_EMISSION), comma(ae_n), comma(ae$min), comma(ae$p5), comma(ae$med), comma(ae$p95), comma(ae$max)))
  )

  obs_line <- paste0("OBSERVATIONS: ", comma(n_obs), "  |  DISTINCT FACILITIES (REGISTRY_ID): ", comma(n_fac), "  |  DISTINCT PGM_SYS_IDs: ", comma(n_pgm))
  inv <- "IDENTIFIERS: REGISTRY_ID, PGM_SYS_ID, PGM_SYS_ACRNM"

  sec(
    h_head("emissions", "Combined Emissions", "POLL_RPT_COMBINED_EMISSIONS.csv",
      paste0("Facility-level pollutant emissions from multiple EPA reporting programs (TRI, NEI, etc.). ",
             "Each row is one facility-pollutant-year observation. Links to FRS via REGISTRY_ID."),
      obs_line, inv),
    cat_table(crows),
    note(paste0("**Reporting programs represented: ", paste0(pgm_shares$PGM_SYS_ACRNM, " (", pgm_shares$pct, "%)", collapse = ", "),
      ". TRIS = Toxics Release Inventory, EIS = Emissions Inventory System (NEI).")),
    note(paste0("**ANNUAL_EMISSION values: ", comma(ae_zeros), " zeros (", round(ae_zeros / n_obs * 100, 1), "%), ", comma(ae_negatives), " negatives (",
      round(ae_negatives / n_obs * 100, 1), "%). Range: ", formatC(ae$min, format = "f", big.mark = ",", digits = 2), " to ",
      formatC(ae$max, format = "f", big.mark = ",", digits = 2), ". Units vary — see UNIT_OF_MEASURE.")),
    num_table(c("Variable","% Missing","N","Min","P5","Median","P95","Max"), nrows),
    dupes(paste0(comma(n_exact_dup), " exact duplicate rows (", round(n_exact_dup / n_obs * 100, 1), "% of all observations). ",
      "Records per facility (REGISTRY_ID): median ", rpf_med, ", max ", comma(rpf_max), ". ", comma(rpf_multi), " facilities (",
      round(rpf_multi / n_fac * 100, 1), "%) have multiple records — expected since each facility can report multiple pollutants across multiple years. ",
      comma(n_fpy_dup_combos), " facility-pollutant-year combinations appear more than once (", comma(n_fpy_dup_rows),
      " total rows). These may reflect reports from different programs (e.g., same pollutant reported to both TRI and NEI) or duplicate submissions."))
  )
}
