# =========================================================================================================
# scripts/tables/program_subparts.R — ICIS-AIR_PROGRAM_SUBPARTS summary section.
# Ported from CAA_Project/data_docs/scripts/tables/table-program-subparts.R (verbatim stats + content).
# =========================================================================================================
library(here); library(readr); library(dplyr)

build_program_subparts_section <- function() {
  sp <- read_csv(here("data/raw/ICIS-AIR_downloads/ICIS-AIR_PROGRAM_SUBPARTS.csv"), show_col_types = FALSE)
  n_obs <- nrow(sp); n_fac <- n_distinct(sp$PGM_SYS_ID)

  pct_miss <- function(x) paste0(round(sum(is.na(x)) / length(x) * 100, 1), "%")
  n_cats   <- function(x) n_distinct(x, na.rm = TRUE)

  pc <- sp |> count(PROGRAM_CODE, PROGRAM_DESC) |> mutate(pct = n / n_obs) |> arrange(desc(n))
  pc_miss <- pct_miss(sp$PROGRAM_CODE); pc_ncat <- n_cats(sp$PROGRAM_CODE)
  sub_top <- sp |> count(AIR_PROGRAM_SUBPART_CODE, AIR_PROGRAM_SUBPART_DESC) |> mutate(pct = n / n_obs) |> arrange(desc(n)) |> slice_head(n = 6)
  sub_miss <- pct_miss(sp$AIR_PROGRAM_SUBPART_CODE); sub_ncat <- n_cats(sp$AIR_PROGRAM_SUBPART_CODE)

  n_exact_dup <- sum(duplicated(sp))
  n_dup_combo <- sum(duplicated(sp |> select(PGM_SYS_ID, PROGRAM_CODE, AIR_PROGRAM_SUBPART_CODE)))
  fpf <- sp |> group_by(PGM_SYS_ID) |> summarise(n = n(), .groups = "drop")
  n_multi <- sum(fpf$n > 1); max_sub <- max(fpf$n); med_sub <- as.integer(median(fpf$n))
  spp <- sp |> group_by(PROGRAM_CODE) |> summarise(n_subparts = n_distinct(AIR_PROGRAM_SUBPART_CODE), .groups = "drop") |> arrange(desc(n_subparts))

  crows <- c(
    cat_var("PROGRAM_CODE", "Which regulatory program the subpart falls under.", pc_miss, pc_ncat,
            paste0(pc$PROGRAM_CODE, " - ", pc$PROGRAM_DESC), pc$n, pc$pct),
    cat_var("AIR_PROGRAM_SUBPART_CODE", paste0("Specific regulatory subpart. ", sub_ncat, " distinct subparts in the dataset."),
            sub_miss, sub_ncat, sub_top$AIR_PROGRAM_SUBPART_DESC, sub_top$n, sub_top$pct)
  )

  obs_line <- paste0("OBSERVATIONS: ", comma(n_obs), "  |  DISTINCT FACILITIES: ", comma(n_fac))
  inv <- "IDENTIFIERS: PGM_SYS_ID, PROGRAM_CODE, AIR_PROGRAM_SUBPART_CODE"

  sec(
    h_head("program_subparts", "ICIS-Air Program Subparts", "ICIS-AIR_PROGRAM_SUBPARTS.csv",
      paste0("Each row links a facility's program enrollment to a specific regulatory subpart. Subparts are the detailed ",
             "rules within NSPS (Part 60), MACT (Part 63), and NESHAP (Part 61) that apply to specific source categories or industrial processes."),
      obs_line, inv),
    cat_table(crows),
    note(paste0("**NSPS (", round(pc$pct[pc$PROGRAM_CODE == "CAANSPS"] * 100, 1), "%) and MACT (",
      round(pc$pct[pc$PROGRAM_CODE == "CAAMACT"] * 100, 1), "%) account for ",
      round((pc$pct[pc$PROGRAM_CODE == "CAANSPS"] + pc$pct[pc$PROGRAM_CODE == "CAAMACT"]) * 100, 1),
      "% of all subpart records. These are the two technology-based standard programs with the most detailed subpart structure.")),
    note(paste0("**The most common subpart is MACT Subpart ZZZZ (Stationary Reciprocating Internal Combustion Engines), covering ",
      comma(sub_top$n[1]), " facility-subpart records (", round(sub_top$pct[1] * 100, 1), "%). NSPS Subparts JJJJ and IIII ",
      "(spark ignition and compression ignition engines) are the next most common — engines are ubiquitous across industrial facilities.")),
    dupes(paste0(comma(n_exact_dup), " exact duplicate rows (", round(n_exact_dup / n_obs * 100, 1), "%). ", comma(n_dup_combo),
      " rows share the same PGM_SYS_ID + PROGRAM_CODE + AIR_PROGRAM_SUBPART_CODE combination with at least one other row. ",
      comma(n_multi), " facilities (", round(n_multi / n_fac * 100, 1), "%) are subject to 2+ subparts (max ", max_sub, "; median ", med_sub,
      "). This is expected — a facility with multiple emission points or processes will be subject to multiple NSPS or MACT subparts. NSPS alone has ",
      spp$n_subparts[spp$PROGRAM_CODE == "CAANSPS"], " distinct subparts; MACT has ", spp$n_subparts[spp$PROGRAM_CODE == "CAAMACT"], "."))
  )
}
