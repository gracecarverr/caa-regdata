> **Status:** draft — [ ] verified against the current script (Claude, 2026-07-30)

# `07_pipeline.R` — builds dataset 6, `pipeline.csv.gz` (facility × year, EPA ECHO CAA Compliance Pipeline)

## Purpose in the pipeline
> **TODO (Grace):** write the 1-2 sentence purpose blurb here — why this script exists and what depends on
> it. Starting material, from the script's own header comment:
> "DATASET 6: pipeline. Facility x year, built from EPA ECHO's 'CAA Compliance Pipeline'
> (docs/data_dictionary.md 'CAA Compliance Pipeline'). Every line below is commented per the user's explicit
> request for this script (the layer's usual house style is sparser -- see the other 04_datasets/*.R files).
> WHAT'S NEW HERE (not already in datasets 0/2/3) -- the raw pipeline row links, in a SINGLE record, the
> evaluation (inspection) that found a violation to the enforcement action it triggered -- a same-row chain
> no ICIS-Air table alone carries."

## Inputs & outputs
- **Input:** `data/processed/pipeline.csv.gz` — event grain, one row per linked evaluation→violation→
  enforcement-action record (raw source: EPA ECHO's CAA Compliance Pipeline download). Key fields used:
  `SOURCE_ID`, `EVAL_FLAG`/`EVAL_TYPE_DESC`/`EVAL_DATE`, `VIOL_FLAG`/`VIOL_TYPE`/`VIOL_START_DATE`,
  `EA_FLAG`/`EA_DATE`/`EA_PENALTY_AMT`. Also `data/processed/facilities.csv.gz` for `REGISTRY_ID`.
- **Output:** `data/datasets/pipeline.csv.gz` — facility × year, same 279,665 × 21-year (2005–2025) rectangle
  as datasets 0/1/2b, 1:1 joinable to `regulatory.csv.gz` on `(PGM_SYS_ID, YEAR)`.

Example — 5 rows from `data/datasets/pipeline.csv.gz` (sampled 2026-07-30, filtered to `PIPELINE_OBSERVED==1`
to show real values; the file is 99.5% `NA` rows otherwise):

| PGM_SYS_ID | YEAR | PIPELINE_OBSERVED | N_VIOL_PIPELINE | N_VIOL_HPV | N_VIOL_FRV | N_VIOL_WITH_EVAL | N_VIOL_WITH_EA | EA_PENALTY_AMT_SUM |
|---|---|---|---|---|---|---|---|---|
| 0900000006001R9490 | 2005 | 1 | 2 | 2 | 0 | 0 | 2 | 0 |
| 0900000006001R9992 | 2006 | 1 | 2 | 2 | 0 | 0 | 2 | 0 |
| 0900000006021R9001 | 2011 | 1 | 2 | 2 | 0 | 0 | 2 | 0 |
| 0900000006037R9200 | 2008 | 1 | 2 | 2 | 0 | 0 | 2 | 0 |
| 0900000006049R9994 | 2005 | 1 | 1 | 1 | 0 | 0 | 1 | 0 |

Full column list (14): `PGM_SYS_ID`, `REGISTRY_ID`, `YEAR`, `PIPELINE_OBSERVED`, `N_VIOL_PIPELINE`,
`N_VIOL_HPV`, `N_VIOL_FRV`, `N_VIOL_WITH_EVAL`, `N_VIOL_WITH_EA`, `N_VIOL_SELF_DISCLOSED`,
`N_VIOL_WITH_EA_PENALTY`, `EA_PENALTY_AMT_SUM`, `MEAN_EVAL_TO_VIOL_LAG_DAYS`, `MEAN_VIOL_TO_EA_LAG_DAYS`.

## At a glance
| | |
|---|---|
| **Input** | `data/processed/pipeline.csv.gz` (5.4 MB compressed, ~66,655 raw rows) + `facilities.csv.gz` |
| **Output** | `data/datasets/pipeline.csv.gz` — 5,872,965 rows × 14 cols, 19.4 MB compressed |
| **Runtime** | not measured directly; input is small but the output is the full 5.87M-row rectangle (`expand_grid` over 279,665 facilities × 21 years) — likely under 1-2 minutes |
| **Requires** | Only the cleaning layer (`data/processed/`) — no dependency on any other `03_datasets/` script's output, despite joining 1:1 to `regulatory.csv.gz` conceptually. |
| **Dependencies** | `readr`, `dplyr`, `tidyr` (`expand_grid`), `lubridate` (`mdy()`, `year()`) |

## Walkthrough
1. **Read** the cleaned pipeline asset, selecting only the eval/violation/enforcement-action columns needed.
2. **Parse dates** — `EVAL_DATE`, `VIOL_START_DATE`, `EA_DATE` via `mdy()`; derive `viol_year =
   year(viol_start_date)` — the row's anchor year (see PL2 gotcha for why this and not `SORT_DATE`).
3. **Drop placeholder rows** — any row with no `viol_year` (no `VIOL_START_DATE`) is an EPA linkage-helper
   row, not a real violation; filtered out (see PL1).
4. **Window filter** — restrict `viol_year` to `YEARS` (2005–2025), matching every other dataset's G1
   convention.
5. **Per-row derived flags** — `is_hpv`/`is_frv` (`VIOL_TYPE`), `has_eval`/`has_ea` (linkage flags),
   `self_disclosed` (NA-guarded, see PL5), `ea_penalty_amt`/`has_ea_penalty`, and the two lag measures
   (`eval_to_viol_lag`, `viol_to_ea_lag`), each only computed where both anchor dates exist and are correctly
   ordered.
6. **Assert** the remaining rows partition exactly into `{HPV, FRV}` — no third `VIOL_TYPE` value survives
   placeholder removal.
7. **Collapse to facility × year** (`group_by(SOURCE_ID, viol_year)`) — sums/means the per-row flags into the
   count and lag-day columns; `NaN` means (no eligible rows) coerced to `NA`.
8. **Build the full rectangle** — `expand_grid` every `PGM_SYS_ID` × `YEARS`, left-join the counts,
   `pipeline_observed = 1` iff a match exists, attach `REGISTRY_ID`.
9. **Invariants** (`stopifnot`) — grain unique; rectangle complete; zero-vs-NA consistency
   (`PIPELINE_OBSERVED` ⟺ counts non-NA); `N_VIOL_HPV + N_VIOL_FRV == N_VIOL_PIPELINE`; penalty flag/sum
   agreement; placeholder rows structurally absent; self-disclosed/linkage counts never `NA` on an observed
   row.
10. **Write + summary.**

## Notes & gotchas
- **PL1** (placeholder rows): "7,218 of 66,723 raw rows are EPA-system-generated placeholders, not real
  violations, identified by blank `VIOL_START_DATE` + `VIOL_ACTIVITY_ID` prefixed `9906`/`9913` +
  `VIOL_TYPE` blank or `'Linked to Viol. Below'` — matches the dictionary's note that these IDs 'did not have
  an actual violation activity identification number.' They have no date to anchor a year, so they are
  structurally excluded (asserted in-build) rather than filtered by a fragile heuristic. After exclusion,
  `VIOL_TYPE` partitions **exactly** into {HPV, FRV} — asserted." (The script's own header comment gives a
  slightly different live count, 7,193 of 66,655 — both are correct for their respective ICIS-AIR snapshot
  dates; this number drifts with each refresh, see PL3.)

- ⚠ **PL2 — quoted in full, this is the load-bearing "verified not assumed" example for this file:**
  > "Year anchor = `VIOL_START_DATE`, not the cleaned asset's own `date` (= `SORT_DATE`)... `SORT_DATE` is
  > EPA's own 'latest stage reached' display date — now permanently checked by
  > `code/diagnostics/16_pipeline_profile.R` (`pl2_sort_date_check.csv`): **0 exceptions across 66,699
  > non-blank rows** (2026-07-27), confirming `SORT_DATE = coalesce(EVAL_DATE, VIOL_START_DATE, EA_DATE)`.
  > ⚠ **Correction**: this priority order is the *opposite* of a previous, incorrect prose description here
  > ('EA_DATE if an EA is linked, else VIOL_START_DATE, else EVAL_DATE') — that ordering was never actually
  > tested against the data; empirically it gives a **58% mismatch rate**. The correct order was found by
  > testing every plausible permutation and keeping the one with 0 exceptions, not by trusting the
  > dictionary's prose. Using `SORT_DATE` instead of `VIOL_START_DATE` would misdate a violation into a later
  > year purely because it was eventually evaluated or enforced after the fact."

- **PL3** (universe): "Universe = the same 279,665-facility (as of 2026-07-27) × 2005–2025 rectangle as ds
  0/1/2b (G3/G4), so `pipeline` joins **1:1** to `regulatory.csv.gz` on `(PGM_SYS_ID, YEAR)` (verified:
  identical key vectors)... as of 2026-07-27 **all 20,222 of 20,222 (100%)** raw-file facilities match the
  ICIS universe — the full rectangle costs nothing either way."

- **PL4**: "`EA_PENALTY_AMT_SUM` is exposed per facility-year but flagged — do NOT sum alongside
  `penalties.csv.gz`'s `PENALTY_AMOUNT` without a dedup rule... Same P5 pattern as ds 3: both very likely
  trace to the same underlying enforcement-action dollars. Reconciling requires matching pipeline's
  `EA_ACTIVITY_ID`/`EA_FEA_ACTIVITY_ID` against ds 3's `ENF_IDENTIFIER`, which is deliberately left undone
  here."

- **PL5** (NA-guard, ⚠ silent-failure risk if missed): "`N_VIOL_SELF_DISCLOSED` guarded against `NA`
  propagation — `EVAL_TYPE_DESC` is blank (parses to `NA`) on the ~46% of rows with no linked evaluation, and
  an unguarded `== 'Self-Disclosure'` comparison produces `NA`, which then poisons `sum()` for the whole
  facility-year group under the zero-vs-NA rule. Fixed by gating on `has_eval & !is.na(EVAL_TYPE_DESC)`
  first... Caught by an independent post-build Python check (not the in-build `stopifnot`s, which didn't
  originally cover this column)."

- **PL6**: "`REGISTRY_ID` joined from `facilities.csv.gz`, not read from the raw file's own `REGISTRY_ID`
  column (which is present natively, unlike most other sources in this layer)... Matches G4 exactly and
  avoids a second, possibly stale, FRS snapshot disagreeing with the rest of the layer."

- **Three non-reconciling HPV/FRV definitions across this layer** (`docs/data_dictionary_derived.md` cross-
  file caveats): "`regulatory.N_HPV`/`N_FRV` (day-zero-date presence on a violation row), `hpv_spells`/
  `hpv_active` (`ENF_RESPONSE_POLICY_CODE == 'HPV'`), and `pipeline.N_VIOL_HPV`/`N_VIOL_FRV` (the raw ECHO
  pipeline's own `VIOL_TYPE` tag) answer closely related but distinct questions... neither is expected to
  reconcile exactly with `pipeline`." Don't treat this file's HPV/FRV split as identical to dataset 2's.

- **Verified by reading the script directly:** the placeholder-exclusion logic, the `VIOL_START_DATE` anchor
  (not `SORT_DATE`), the `self_disclosed` NA-guard, and all `stopifnot()` invariants (lines 129-150).
  **Inferred/not independently re-run this pass:** the PL2 permutation-testing result (0 exceptions / 58%
  mismatch) and the exact placeholder-row counts — quoted from the decisions doc's own verification, not
  re-derived here.
