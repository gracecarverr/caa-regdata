# =========================================================================================================
# code/diagnostics/afs_frs_match/afs_icis_crosswalk.R
#   Scopes whether the legacy AFS facility id (AFS_ID) can be linked to the modern ICIS-Air facility id
#   (PGM_SYS_ID), as a prerequisite for using AFS_AIR_PRG_HIST_COMPLIANCE's quarterly compliance-status
#   history (which includes an explicit "9 = In Compliance, Shut Down" code) as a pre-2015 operating-status
#   signal -- see briefs/panel/panel_open_questions.md D-A2 and briefs/datasets/begin_year_operating_proxy.md.
#
#   WHY A CROSSWALK IS NEEDED
#   AFS_ID (10-char state+county+plant, e.g. 0900100261) and ICIS-Air's PGM_SYS_ID (e.g.
#   0100000009003E0010) share no format -- a direct string match yields zero hits (data/raw/README.md
#   already flags this). EPA's own bridge is the Facility Registry Service (FRS): FRS_PROGRAM_LINKS.csv
#   carries every facility's id in every EPA program system, tagged by PGM_SYS_ACRNM. Air-program rows
#   (PGM_SYS_ACRNM == "AIR") whose PGM_SYS_ID is 18 characters long embed the legacy AFS_ID as their LAST
#   10 CHARACTERS (state + zero-padding + AFS_ID). Two hops:
#       AFS_ID --(hop 1, via FRS)--> REGISTRY_ID --(hop 2, direct)--> ICIS-Air PGM_SYS_ID
#
#   PROVENANCE -- this is a PORT, not a fresh derivation. The method (including the last-10-vs-strip-and-repad
#   comparison in step 2) was originally worked out in the predecessor project, CAA_Project's
#   data_docs/scripts/explore/10_frs-crosswalk.R, which found 69.6% end-to-end coverage on the FULL AFS
#   population, skewed toward missing CLOSED facilities. This script reproduces that result inside
#   caa-regdata (so the number is traceable from THIS repo, not only a sibling project -- reproducibility
#   rule) as an internal correctness check (step 5), then asks the two questions that actually matter for
#   this repo's use case (step 6): does the crosswalk reach (a) the current 279,211-facility ICIS-Air spine,
#   and (b) specifically the 171,324-facility pre-2015-begin-year population that begin_year_operating_proxy.md
#   already identified as needing a pre-2015 signal.
#
#   DISCIPLINE, carried over unchanged from the original script: name/address/zip candidate matches for
#   unmatched AFS records are written out as CANDIDATES ONLY, never added to the crosswalk. A shared name or
#   address does not prove the same physical facility -- any acceptance rule needs separate review.
#
#   in : data/raw/afs_downloads/AFS_FACILITIES.csv              (AFS_ID, OPERATING_STATUS, name/address)
#        data/raw/ICIS-AIR_downloads/ICIS-AIR_FACILITIES.csv    (PGM_SYS_ID, REGISTRY_ID, name/address -- RAW,
#                                                                 used only for baseline reproduction, step 5)
#        data/raw/frs/FRS_PROGRAM_LINKS.csv                     (PGM_SYS_ACRNM, PGM_SYS_ID, REGISTRY_ID)
#        data/raw/frs/FRS_FACILITIES.csv                        (REGISTRY_ID, name/address -- candidate search)
#        data/processed/facilities.csv.gz                       (the CURRENT 279,211-facility ICIS spine)
#        output/begin_year_proxy/pre2015_single_year_facilities.csv (the 171,324-facility pre-2015 population)
#   out: output/afs_frs_match/{hop1_length_distribution,hop1_extraction_method,crosswalk_coverage,
#                              unmatched_by_status,unmatched_by_state,candidate_summary,
#                              spine_restricted_coverage,pre2015_population_coverage}.csv
#   Hand-run diagnostic (not part of RUN_ALL.R). Deterministic candidate search except one seeded sample
#   (unmatched-substring check, step 4) -- fixed seed for reproducibility.
# =========================================================================================================
suppressPackageStartupMessages({library(readr); library(dplyr); library(tidyr)})

set.seed(1)
RAW <- here::here("data/raw")
OUT <- here::here("output/afs_frs_match"); dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

# ============================================================================================
# 1. LOAD INPUTS -- all ids as character (leading zeros are meaningful: 0900100261 != 900100261)
# ============================================================================================
cat("==== loading inputs ====\n")

afs <- read_csv(file.path(RAW, "afs_downloads/AFS_FACILITIES.csv"),
                col_types = cols(AFS_ID = col_character(), OPERATING_STATUS = col_character(),
                                 .default = col_character()), show_col_types = FALSE)
afs_ids <- unique(afs$AFS_ID)

icis_raw <- read_csv(file.path(RAW, "ICIS-AIR_downloads/ICIS-AIR_FACILITIES.csv"),
                     col_types = cols(PGM_SYS_ID = col_character(), REGISTRY_ID = col_character(),
                                      .default = col_character()), show_col_types = FALSE)

frs_links_path <- file.path(RAW, "frs/FRS_PROGRAM_LINKS.csv")
stopifnot("FRS_PROGRAM_LINKS.csv not staged -- see data/raw/README.md" = file.exists(frs_links_path))
frs <- read_csv(frs_links_path, col_select = c(PGM_SYS_ACRNM, PGM_SYS_ID, REGISTRY_ID),
                col_types = cols(.default = col_character()), show_col_types = FALSE)
air <- frs |> filter(PGM_SYS_ACRNM == "AIR")

cat("AFS facilities (unique AFS_ID):", length(afs_ids), "\n")
cat("ICIS-Air facilities (raw):     ", nrow(icis_raw), "\n")
cat("FRS rows tagged 'AIR':         ", nrow(air), "\n")

# ============================================================================================
# 2. HOP 1 -- extract AFS_ID from 18-character AIR ids (last 10 characters), with the
#    length-distribution and extraction-method diagnostics that justified this rule originally.
# ============================================================================================
cat("\n==== hop 1: FRS AIR id -> AFS_ID ====\n")

last10 <- function(x) substr(x, nchar(x) - 9L, nchar(x))
strip_derive <- function(x) {           # the REJECTED alternative, kept only for the comparison below
  b   <- sub("^[A-Za-z]{2}", "", x)
  b   <- sub("^0+", "", b)
  pad <- pmax(0L, 10L - nchar(b))
  paste0(strrep("0", pad), b)
}

len_dist <- air |> mutate(L = nchar(PGM_SYS_ID)) |> count(L, name = "n") |> arrange(desc(n))
write_csv(len_dist, file.path(OUT, "hop1_length_distribution.csv"))

cmp <- air |> mutate(m_last10 = last10(PGM_SYS_ID) %in% afs_ids, m_strip = strip_derive(PGM_SYS_ID) %in% afs_ids)
method_cmp <- tibble(
  method = c("last10", "strip_and_repad"),
  n_match = c(sum(cmp$m_last10), sum(cmp$m_strip)),
  n_total = nrow(cmp),
  pct_match = round(c(mean(cmp$m_last10), mean(cmp$m_strip)) * 100, 1))
write_csv(method_cmp, file.path(OUT, "hop1_extraction_method.csv"))
cat("last10 vs strip-and-repad match rate:", method_cmp$pct_match[1], "% vs", method_cmp$pct_match[2],
    "% -- using last10 (matches CAA_Project's finding: strip-and-repad is lower)\n")

air18 <- air |> filter(nchar(PGM_SYS_ID) == 18) |> mutate(afs_key = last10(PGM_SYS_ID))
afs_to_reg <- air18 |> filter(afs_key %in% afs_ids) |> distinct(AFS_ID = afs_key, REGISTRY_ID)

# ============================================================================================
# 3. HOP-1 COVERAGE -- link rate, ambiguity, and where the gap concentrates
# ============================================================================================
cat("\n==== hop 1 coverage ====\n")

linked_afs <- unique(afs_to_reg$AFS_ID)
cat("AFS facilities linked to a REGISTRY_ID:", length(linked_afs), "of", length(afs_ids),
    sprintf(" (%.1f%%)\n", 100 * length(linked_afs) / length(afs_ids)))

multi <- afs_to_reg |> count(AFS_ID, name = "n_reg") |> filter(n_reg > 1)
cat("AFS_IDs mapping to >1 REGISTRY_ID (ambiguous):", nrow(multi),
    sprintf(" (%.2f%% of linked)\n", 100 * nrow(multi) / length(linked_afs)))

unmatched <- setdiff(afs_ids, linked_afs)
samp <- sample(unmatched, min(2000L, length(unmatched)))
hits <- vapply(samp, function(a) any(grepl(a, air$PGM_SYS_ID, fixed = TRUE)), logical(1))
cat("Unmatched AFS facilities:", length(unmatched), "-- of", length(samp),
    "sampled, found as a substring anywhere in AIR ids:", sum(hits),
    sprintf(" (%.1f%%)\n", 100 * mean(hits)))

# ============================================================================================
# 4. HOP 2 -- REGISTRY_ID -> ICIS-Air PGM_SYS_ID (raw file; baseline reproduction only)
# ============================================================================================
cat("\n==== hop 2: REGISTRY_ID -> ICIS-Air (raw) ====\n")

reg_to_icis_raw <- icis_raw |> filter(!is.na(REGISTRY_ID)) |> distinct(REGISTRY_ID, ICIS_PGM_SYS_ID = PGM_SYS_ID)

crosswalk <- afs_to_reg |>
  left_join(reg_to_icis_raw, by = "REGISTRY_ID", relationship = "many-to-many") |>
  group_by(AFS_ID, REGISTRY_ID) |>
  summarise(n_icis_ids = n_distinct(ICIS_PGM_SYS_ID[!is.na(ICIS_PGM_SYS_ID)]),
            ICIS_PGM_SYS_ID = paste(sort(unique(ICIS_PGM_SYS_ID[!is.na(ICIS_PGM_SYS_ID)])), collapse = ";"),
            .groups = "drop")

afs_reaching_icis <- crosswalk |> filter(n_icis_ids > 0) |> summarise(n = n_distinct(AFS_ID)) |> pull(n)

# ============================================================================================
# 5. BASELINE REPRODUCTION -- must match CAA_Project's 10_frs-crosswalk.R run before trusting step 6
# ============================================================================================
cat("\n==== baseline reproduction (full AFS population, raw ICIS) ====\n")

coverage <- tibble(
  afs_facilities_total   = length(afs_ids),
  afs_linked_to_registry = length(linked_afs),
  pct_afs_linked         = round(100 * length(linked_afs) / length(afs_ids), 1),
  afs_ambiguous_multi_reg = nrow(multi),
  afs_with_any_icis_id   = afs_reaching_icis,
  pct_afs_reaching_icis  = round(100 * afs_reaching_icis / length(afs_ids), 1))
write_csv(coverage, file.path(OUT, "crosswalk_coverage.csv"))
cat("End-to-end:", coverage$afs_with_any_icis_id, "of", coverage$afs_facilities_total,
    sprintf(" (%.1f%%) -- CAA_Project's prior run: 164,880 of 236,734 (69.6%%)\n", coverage$pct_afs_reaching_icis))

match_status <- afs |> distinct(AFS_ID, OPERATING_STATUS) |> mutate(is_matched = AFS_ID %in% linked_afs) |>
  group_by(OPERATING_STATUS) |>
  summarise(afs_facilities = n(), matched = sum(is_matched), unmatched = sum(!is_matched),
            pct_matched = round(100 * mean(is_matched), 1), .groups = "drop") |> arrange(desc(afs_facilities))
write_csv(match_status, file.path(OUT, "unmatched_by_status.csv"))
cat("Match rate by OPERATING_STATUS (O=operating, X=closed):\n"); print(match_status, n = 20)

match_state <- afs |> distinct(AFS_ID, STATE) |> mutate(is_matched = AFS_ID %in% linked_afs) |>
  group_by(STATE) |>
  summarise(afs_facilities = n(), matched = sum(is_matched), unmatched = sum(!is_matched),
            pct_matched = round(100 * mean(is_matched), 1), .groups = "drop") |> arrange(desc(unmatched))
write_csv(match_state, file.path(OUT, "unmatched_by_state.csv"))

# ---- conservative exact-after-normalization candidate search for the unmatched group (evidence, not matches)
normalize_text <- function(x) { x <- toupper(trimws(x)); x <- gsub("[[:punct:]]+", " ", x)
  x <- gsub("[[:space:]]+", " ", x); x[x == ""] <- NA_character_; x }
normalize_zip5 <- function(x) { x <- gsub("[^0-9]", "", x); x <- substr(x, 1, 5); x[nchar(x) != 5] <- NA_character_; x }

unmatched_std <- afs |> filter(AFS_ID %in% unmatched) |>
  transmute(AFS_ID, name_std = normalize_text(PLANT_NAME), address_std = normalize_text(PLANT_STREET_ADDRESS),
            state_std = normalize_text(STATE), zip5 = normalize_zip5(ZIP_CODE))

frs_fac_path <- file.path(RAW, "frs/FRS_FACILITIES.csv")
stopifnot("FRS_FACILITIES.csv not staged" = file.exists(frs_fac_path))
frs_facilities <- read_csv(frs_fac_path, col_select = c(REGISTRY_ID, FAC_NAME, FAC_STREET, FAC_STATE, FAC_ZIP),
                           col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  filter(!is.na(REGISTRY_ID)) |> distinct(REGISTRY_ID, .keep_all = TRUE) |>
  transmute(REGISTRY_ID, name_std = normalize_text(FAC_NAME), address_std = normalize_text(FAC_STREET),
            state_std = normalize_text(FAC_STATE), zip5 = normalize_zip5(FAC_ZIP))

cand_name_zip <- unmatched_std |> filter(!is.na(name_std), !is.na(state_std), !is.na(zip5)) |>
  inner_join(frs_facilities |> filter(!is.na(name_std), !is.na(state_std), !is.na(zip5)),
             by = c("name_std", "state_std", "zip5"), relationship = "many-to-many") |>
  distinct(AFS_ID, REGISTRY_ID)
cand_addr_zip <- unmatched_std |> filter(!is.na(address_std), !is.na(state_std), !is.na(zip5)) |>
  inner_join(frs_facilities |> filter(!is.na(address_std), !is.na(state_std), !is.na(zip5)),
             by = c("address_std", "state_std", "zip5"), relationship = "many-to-many") |>
  distinct(AFS_ID, REGISTRY_ID)
any_candidate <- bind_rows(cand_name_zip, cand_addr_zip) |> distinct(AFS_ID, REGISTRY_ID)

candidate_summary <- tibble(
  measure = c("unmatched_afs_total", "with_any_exact_frs_candidate", "with_no_exact_frs_candidate"),
  n = c(n_distinct(unmatched_std$AFS_ID), n_distinct(any_candidate$AFS_ID),
        n_distinct(unmatched_std$AFS_ID) - n_distinct(any_candidate$AFS_ID))) |>
  mutate(pct_of_unmatched = round(100 * n / n[1], 1))
write_csv(candidate_summary, file.path(OUT, "candidate_summary.csv"))
cat("\nOf", candidate_summary$n[1], "unmatched, ", candidate_summary$n[2],
    sprintf(" (%.1f%%) have an exact name/address+state+zip5 candidate in FRS -- NOT added to the crosswalk.\n",
            candidate_summary$pct_of_unmatched[2]))

# ============================================================================================
# 6. REPO-SPECIFIC EXTENSION -- does the crosswalk reach the population we'd actually use it on?
#    (a) the current 279,211-facility ICIS spine (data/processed/facilities.csv.gz), not the raw file
#    (b) within that, the 171,324-facility pre-2015-begin-year population (output/begin_year_proxy/)
# ============================================================================================
cat("\n==== repo-specific extension: current spine + pre-2015-begin-year population ====\n")

spine <- read_csv(here::here("data/processed/facilities.csv.gz"),
                  col_types = cols_only(PGM_SYS_ID = col_character(), REGISTRY_ID = col_character()),
                  show_col_types = FALSE)
stopifnot("spine PGM_SYS_ID not unique" = !anyDuplicated(spine$PGM_SYS_ID))

# reverse direction: for each spine facility, is its REGISTRY_ID reachable from ANY linked AFS_ID?
reg_from_afs <- unique(afs_to_reg$REGISTRY_ID)
spine_reach <- spine |> mutate(afs_reachable = as.integer(!is.na(REGISTRY_ID) & REGISTRY_ID %in% reg_from_afs))

spine_coverage <- tibble(
  icis_spine_facilities = nrow(spine),
  reachable_from_afs     = sum(spine_reach$afs_reachable),
  pct_reachable          = round(100 * mean(spine_reach$afs_reachable), 1))
write_csv(spine_coverage, file.path(OUT, "spine_restricted_coverage.csv"))
cat("Current 279,211-facility spine reachable from AFS:", spine_coverage$reachable_from_afs, "of",
    spine_coverage$icis_spine_facilities, sprintf(" (%.1f%%)\n", spine_coverage$pct_reachable))

pre2015_path <- here::here("output/begin_year_proxy/pre2015_single_year_facilities.csv")
stopifnot("run code/diagnostics/10_begin_year_proxy.R first" = file.exists(pre2015_path))
pre2015 <- read_csv(pre2015_path, col_types = cols(PGM_SYS_ID = col_character(), .default = col_character()),
                    show_col_types = FALSE)

pre2015_reach <- pre2015 |> distinct(PGM_SYS_ID) |> left_join(spine_reach, by = "PGM_SYS_ID")
pre2015_coverage <- tibble(
  pre2015_begin_year_facilities = nrow(pre2015_reach),
  reachable_from_afs            = sum(pre2015_reach$afs_reachable, na.rm = TRUE),
  pct_reachable                 = round(100 * mean(pre2015_reach$afs_reachable, na.rm = TRUE), 1),
  not_in_spine_reach_table      = sum(is.na(pre2015_reach$afs_reachable)))
write_csv(pre2015_coverage, file.path(OUT, "pre2015_population_coverage.csv"))
cat("Pre-2015-begin-year population reachable from AFS:", pre2015_coverage$reachable_from_afs, "of",
    pre2015_coverage$pre2015_begin_year_facilities,
    sprintf(" (%.1f%%)\n", pre2015_coverage$pct_reachable))

cat("\n==== DONE -- outputs written to", OUT, "====\n")
