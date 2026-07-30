> **Status:** draft — [ ] verified against the current script (Claude, 2026-07-30)

# `05_penalties.R` — builds dataset 3, `penalties.csv.gz` (one row per formal enforcement action)

## Purpose in the pipeline
> **TODO (Grace):** write the 1-2 sentence purpose blurb here — why this script exists and what depends on
> it. Starting material, from the script's own header comment:
> "DATASET 3: penalties. One row per FORMAL ACTION (action-level). The disaggregated penalty record behind
> ds 0's facility-year penalty_amount / n_penalties. Carries the multi-facility settlement key so
> co-defendant broadcasting is visible and cross-facility summing is avoidable."

## Inputs & outputs
- **Input:** `data/processed/formal_actions.csv.gz` — event grain, one row per ICIS-Air formal enforcement
  action, historical, NOT window-restricted. Key fields used: `PGM_SYS_ID`, `ENF_IDENTIFIER`,
  `PENALTY_AMOUNT`, `ENF_TYPE_CODE`/`DESC`, `ACTIVITY_TYPE_CODE`/`DESC`, `STATE_EPA_FLAG`, `date`, `year`,
  `dup`, `dup_exact`. Also `data/processed/facilities.csv.gz` (`PGM_SYS_ID`, `REGISTRY_ID`) for the FRS
  cross-walk.
- **Output:** `data/datasets/penalties.csv.gz` — one row per formal-action record (105,946 rows, all kept,
  duplicates flagged not dropped). Joins on `PGM_SYS_ID` (+ `YEAR` for facility-year merges); `ENF_IDENTIFIER`
  is the settlement key grouping co-defendant rows.

Example — 5 rows from `data/datasets/penalties.csv.gz` (sampled 2026-07-30, filtered to `IS_MULTI_FACILITY==1`
to show the settlement structure that matters most here):

| PGM_SYS_ID | ENF_IDENTIFIER | YEAR | PENALTY_AMOUNT | HAS_PENALTY | ENF_TYPE_DESC | N_SETTLEMENT_FACILITIES | IS_MULTI_FACILITY |
|---|---|---|---|---|---|---|---|
| 03000PA000803774 | 03-2015-7007 | 2018 | 385000 | 1 | Civil Judicial Action | 23 | 1 |
| 03000WV00007 | 03-2021-7003 | 2026 | 3800000 | 1 | Civil Judicial Action | 14 | 1 |
| 04000EPAWALTON | 05-2020-5027 | 2020 | 0 | 0 | CAA 113A Admin Compliance Order (Non-Penalty) | 8 | 1 |
| 04000EPAWALTON | 05-2021-5013 | 2021 | 106000 | 1 | CAA 113D1 Action For Penalty | 7 | 1 |
| 0500000001055R5001 | 05-2018-5043 | 2022 | 1550000 | 1 | Civil Judicial Action | 27 | 1 |

Full column list (17): `PGM_SYS_ID`, `REGISTRY_ID`, `ACTIVITY_ID`, `ENF_IDENTIFIER`,
`SETTLEMENT_ENTERED_DATE`, `YEAR`, `PENALTY_AMOUNT`, `HAS_PENALTY`, `ENF_TYPE_CODE`, `ENF_TYPE_DESC`,
`ACTIVITY_TYPE_CODE`, `ACTIVITY_TYPE_DESC`, `STATE_EPA_FLAG`, `N_SETTLEMENT_FACILITIES`, `IS_MULTI_FACILITY`,
`DUP`, `DUP_EXACT`.

## At a glance
| | |
|---|---|
| **Input** | `data/processed/formal_actions.csv.gz` (2.7 MB compressed, 105,946 rows) + `data/processed/facilities.csv.gz` |
| **Output** | `data/datasets/penalties.csv.gz` — 105,946 rows × 17 cols, 2.0 MB compressed |
| **Runtime** | not measured directly; input is small (105,946 rows) — likely under 30 seconds |
| **Requires** | Only the cleaning layer (`data/processed/`) — no dependency on any other `03_datasets/` script's output. `00_parameters.R` is sourced for `YEARS`/paths/`write_dataset()`. |
| **Dependencies** | `readr`, `dplyr`, `lubridate` |

## Walkthrough
1. **Read** `formal_actions.csv.gz` with an explicit `col_select`/`col_types` — everything kept as character
   except `PGM_SYS_ID`, `ACTIVITY_ID`, `ENF_IDENTIFIER` (character), `date`/`year`/`dup`/`dup_exact` (typed).
2. **Settlement grouping** — `group_by(ENF_IDENTIFIER)` computes `n_settlement_facilities =
   n_distinct(PGM_SYS_ID)` per settlement, the count of co-defendant facilities sharing that settlement key.
3. **`transmute()` to the final column set** — renames/derives `penalty_amount` (`parse_number()`),
   `has_penalty` (>0 flag, recomputed independently — see gotcha below), `is_multi_facility`
   (`n_settlement_facilities > 1`), and carries through the enforcement-type/activity-type/agency fields and
   dup flags as-is.
4. **FRS id join** — reads `facilities.csv.gz` for `PGM_SYS_ID` → `REGISTRY_ID`, left-joins in, relocates
   `REGISTRY_ID` right after `PGM_SYS_ID` (layer convention G4).
5. **Invariants** (`stopifnot`) — row count matches source exactly (no rows dropped/added); `ENF_IDENTIFIER`
   never blank; `penalty_amount` never `NA`/negative; `has_penalty`/`is_multi_facility` internally consistent
   with their source columns; `n_settlement_facilities >= 1`; every action's `PGM_SYS_ID` is in the ds 0
   universe.
6. **Write + summary** — `write_dataset()` uppercases every column; console summary prints action/facility
   counts, total penalty dollars, and multi-facility settlement counts.

## Notes & gotchas
- ⚠ **P5 — the single most important caveat in this file, multi-facility settlement structure.** Quoted
  verbatim from `briefs/datasets/dataset_construction_decisions.md`:
  > "Multi-facility settlement structure EXPOSED, not resolved — `ENF_IDENTIFIER` (settlement key),
  > `N_SETTLEMENT_FACILITIES`, `IS_MULTI_FACILITY`; per-row penalty left faithful... ⚠ As of 2026-07-27
  > (`output/penalties_profile/settlement_structure.csv`, `12_penalties_profile.R`): **571 settlements**
  > span >1 facility (up to **117** co-defendants), each a separate row. The penalty is *usually* one value
  > repeated (**507 of 571**) but **64 settlements carry DIFFERING per-facility amounts** — so it is **not**
  > a clean broadcast, and neither 'take one value' nor 'sum' is universally right. Exposing the structure
  > lets the user pick per analysis. **Do NOT sum `PENALTY_AMOUNT` across a settlement's facilities without a
  > broadcast rule.** See `multi_facility_settlement_decision.md` §5 for a **separate, older** FRS-`REGISTRY_ID`
  > crosswalk sub-analysis — 552 of 588 settlements (a REGISTRY_ID-based count from an earlier profiling pass,
  > not re-run against the current 571-settlement `ENF_IDENTIFIER`-based count above) span genuinely distinct
  > `REGISTRY_ID`s — not independently re-verified in this pass, and not a second measurement of the same
  > 571."

  For the full quantitative analysis behind this, see `briefs/datasets/multi_facility_settlement_decision.md`
  in full — key numbers from it: naive per-row summing overstates the 571 multi-facility settlements' total
  by **$1,989,587,470 (35.7% of the entire dataset's penalty dollars)**; only **19 of the 64** differing-amount
  settlements (3.3% of all 571) genuinely need case-level judgment — the other 552 (96.7%) can be handled with
  a clean de-duplication-by-settlement rule. The brief documents this as an **open decision** (options a–e
  laid out, none chosen as of the brief's writing) — check its status before assuming which option was taken.

- **P1** (grain): "Grain = one row per `formal_actions.csv.gz` row; ALL rows kept, `dup>0` flagged not
  dropped... `ENF_IDENTIFIER` (not `ACTIVITY_ID`) is the field that groups co-defendant rows of one
  settlement (P5); `ACTIVITY_ID` is a violation-grain field used elsewhere in this layer (`hpv_spells`/
  `pipeline`), not the settlement key here."

- **P2** (scope): "Formal actions only... Only formal actions carry `PENALTY_AMOUNT`; informal has no penalty
  column. Penalties are the point of this dataset."

- **P3** (no window restriction): "NOT window-restricted — all action years (1972–2026) kept... Six-dataset
  design pushes sample/window filters downstream; `YEAR` is provided so the user clips as needed. 67,049 of
  105,946 actions fall in 2005–2025 (as of 2026-07-27)."

- **P4** (zero-vs-NA does NOT apply at this grain): "`PENALTY_AMOUNT` kept AS RECORDED per row (0 or
  positive, never `NA`); no zero-vs-NA discipline... Every row is an observed action with a recorded amount —
  the observability question doesn't arise at action grain." ⚠ This is the opposite convention from ds 0's
  `PENALTY_AMOUNT` (R4: `NA` when no confirmed positive penalty dollars) — don't conflate the two files'
  columns of the same name.

- **R4 (ds 0, for contrast)** from the same decisions doc, since this file's `PENALTY_AMOUNT` reconciles
  against it: "`PENALTY_AMOUNT` is `NA` whenever a facility-year had no formal action at all, OR its formal
  action(s) summed to exactly $0 — both collapse into `NA`, not just genuinely-unobserved years." Verified in
  the decisions doc: `penalties.csv.gz` reconciles exactly to ds 0's windowed `PENALTY_AMOUNT` sum, diff $0.

- Data dictionary confirms `ENF_IDENTIFIER` as "the **settlement key**" and repeats the P5 caveat verbatim in
  its own blockquote form (`docs/data_dictionary_derived.md`, `penalties.csv.gz` section).

- **Verified by reading the script directly:** the row-count invariant, the FRS join, the `has_penalty`
  double-computation (flagged in-file as `FLAGGED ISSUES` item 1 — "harmless duplication, same result"), and
  that `PENALTY_AMOUNT` is asserted `>= 0` and never `NA` at build time (`stopifnot` block, lines 62-69).
  **Inferred/not independently re-run this pass:** the exact $0 diff reconciliation against
  `regulatory.csv.gz` and the settlement dollar-impact figures in the P5 quote and the linked brief — both are
  quoted from the decisions doc's own verification sessions, not re-derived here.
