> **Status:** draft — [ ] verified against the current script (Claude, 2026-07-30)

# `08_emissions.R` — builds dataset 7, `emissions.csv.gz` (facility × year, combined pollutant report)

## Purpose in the pipeline
> **TODO (Grace):** write the 1-2 sentence purpose blurb here — why this script exists and what depends on
> it. Starting material, from the script's own header comment:
> "DATASET 7: emissions. Facility x year, built from the combined pollutant report
> (data/processed/emissions.csv.gz, from EIS/TRIS/E-GGRT/CAMDBS -- see docs/data_dictionary.md). ...WHAT'S
> NEW HERE -- ds 0's EMITS_* flags (regulatory.csv.gz) are booleans from ICIS-AIR_POLLUTANTS.csv (undated,
> 'ever permitted to emit'); nothing in this layer carries actual measured emission QUANTITIES. This dataset
> adds annual pounds for VOC/PM10/PM2.5/NOx/SO2/CO, a broader HAP total, and GHG (metric tons CO2e, kept in
> its own column/unit) -- a real magnitude axis, not a flag."

## Inputs & outputs
- **Input:** `data/processed/emissions.csv.gz` — raw grain `REPORTING_YEAR × REGISTRY_ID × PGM_SYS_ACRNM ×
  PGM_SYS_ID × POLLUTANT_NAME`, 10,411,871 rows, cross-program (EIS 90.1% / TRIS 7.7% / E-GGRT 1.9% / CAMDBS
  0.3%). Key fields: `REPORTING_YEAR`, `REGISTRY_ID`, `PGM_SYS_ACRNM`, `POLLUTANT_NAME`, `ANNUAL_EMISSION`,
  `NEI_TYPE`. Also `data/processed/facilities.csv.gz` for the `PGM_SYS_ID` ↔ `REGISTRY_ID` crosswalk.
- **Output:** `data/datasets/emissions.csv.gz` — facility × year, same 279,665 × 21-year rectangle as
  datasets 0/1/2b/6, 1:1 joinable to `regulatory.csv.gz`. Joined on `REGISTRY_ID` internally (not
  `PGM_SYS_ID` — see EM1), then broadcast onto `PGM_SYS_ID`.

Example — 5 rows from `data/datasets/emissions.csv.gz` (sampled 2026-07-30, filtered to
`EMISSIONS_OBSERVED==1`):

| PGM_SYS_ID | YEAR | EMISSIONS_OBSERVED | GHG_OBSERVED | VOC_LBS | PM10_LBS | HAP_LBS | GHG_MTCO2E | N_PGM_SYS_ID_SHARING_REGISTRY | IS_SHARED_REGISTRY |
|---|---|---|---|---|---|---|---|---|---|
| 01000000E000000013 | 2016 | 1 | 0 | 0 | 0 | 0 | NA | 1 | 0 |
| 01000000E000000013 | 2017 | 1 | 0 | 0 | 0 | 0 | NA | 1 | 0 |
| 01000000E000000013 | 2018 | 1 | 0 | 0 | 0 | 0 | NA | 1 | 0 |
| 01000000E000000013 | 2019 | 1 | 0 | 0 | 0 | 0 | NA | 1 | 0 |
| 01000000E000000013 | 2020 | 1 | 0 | 0 | 0 | 0 | NA | 1 | 0 |

(Note `GHG_MTCO2E` stays `NA` here even though `EMISSIONS_OBSERVED==1` — the two observability flags are
independent, see EM6.)

Full column list (15): `PGM_SYS_ID`, `REGISTRY_ID`, `YEAR`, `EMISSIONS_OBSERVED`, `GHG_OBSERVED`, `VOC_LBS`,
`PM10_LBS`, `PM25_LBS`, `NOX_LBS`, `SO2_LBS`, `CO_LBS`, `HAP_LBS`, `GHG_MTCO2E`,
`N_PGM_SYS_ID_SHARING_REGISTRY`, `IS_SHARED_REGISTRY`.

## At a glance
| | |
|---|---|
| **Input** | `data/processed/emissions.csv.gz` (150 MB compressed, 10,411,871 raw rows) + `facilities.csv.gz` |
| **Output** | `data/datasets/emissions.csv.gz` — 5,872,965 rows × 15 cols, 24.4 MB compressed |
| **Runtime** | not measured directly; by far the largest raw input in this layer (150 MB compressed / 10.4M rows) plus a many-to-many broadcast join — likely the slowest of the four scripts in this batch, probably several minutes |
| **Requires** | Only the cleaning layer (`data/processed/`) — no dependency on any other `03_datasets/` script's output. **Consumed by `02_operating.R`**, which is why `RUN_ALL.R`'s datasets-loop now runs `08_emissions.R` before `02_operating.R` (see the orchestration note in `code/03_datasets/README.md` and decision O6). |
| **Dependencies** | `readr`, `dplyr`, `tidyr` (`expand_grid`) |

## Walkthrough
1. **Define the pollutant map** — a named vector of exact canonical `POLLUTANT_NAME` strings for
   VOC/PM10/PM2.5/NOx/SO2/CO (see EM4 gotcha on why exact match, not substring).
2. **Read** the cleaned emissions asset, selecting `REPORTING_YEAR`, `REGISTRY_ID`, `PGM_SYS_ACRNM`,
   `POLLUTANT_NAME`, `ANNUAL_EMISSION`, `NEI_TYPE`.
3. **Window filter** — restrict to `YEARS` (2005–2025); real data only spans 2008–2024 (see EM7).
4. **Split pounds vs. GHG** — `pounds` = everything except `PGM_SYS_ACRNM == "E-GGRT"`; `ghg` = E-GGRT only
   (different unit, independent observability — EM6).
5. **Aggregate pounds** to `(REGISTRY_ID, year)` — exact-match sums for each of the six pollutant categories
   plus `hap_lbs` (every `NEI_TYPE == "HAP"` row, EM5), `emissions_observed = 1`.
6. **Aggregate GHG** to `(REGISTRY_ID, year)` — `ghg_mtco2e` sum, `ghg_observed = 1`.
7. **Combine** via `full_join` on `(REGISTRY_ID, year)` — either side can be missing for a given group.
8. **Build the facility crosswalk** — `PGM_SYS_ID` → `REGISTRY_ID` from `facilities.csv.gz`; compute
   `n_pgm_sys_id_sharing_registry` (fan-out count per `REGISTRY_ID`) and `is_shared_registry` (EM2).
9. **Broadcast** — `inner_join` the crosswalk to `registry_year` via `REGISTRY_ID`, deliberately
   `relationship = "many-to-many"` — this is the fan-out broadcast, not an accidental cartesian join (see
   EM2).
10. **Build the full rectangle** — `expand_grid` every `PGM_SYS_ID` × `YEARS`, left-join the broadcast data,
    coalesce `emissions_observed`/`ghg_observed` `NA → 0` (independently), attach `REGISTRY_ID` + fan-out
    columns.
11. **Invariants** (`stopifnot`) — grain unique; rectangle complete; zero-vs-NA consistency for both pounds
    and GHG columns independently; `IS_SHARED_REGISTRY` internally consistent with the fan-out count
    (structural check only, not pinned to a snapshot count — see EM2); fan-out survives the crosswalk → `em`
    join unchanged.
12. **Write + summary** — prints observed facility-year counts and the live shared-`REGISTRY_ID` fan-out
    count (explicitly not hardcoded, see EM2).

## Notes & gotchas
- **EM1** (join key): "Join key = `REGISTRY_ID` (FRS), not `PGM_SYS_ID`. Every other dataset in this layer
  joins on `PGM_SYS_ID`; this is the first that can't, because the raw rows are cross-program (`PGM_SYS_ACRNM`
  ∈ {EIS 90.1%, TRIS 7.7%, E-GGRT 1.9%, CAMDBS 0.3%}) and each program has its own facility-id scheme."

- ⚠ **EM2 — REGISTRY_ID fan-out, load-bearing, quoted in full:**
  > "`REGISTRY_ID` fan-out exposed, not resolved — `N_PGM_SYS_ID_SHARING_REGISTRY` / `IS_SHARED_REGISTRY`,
  > same pattern as ds 3's multi-facility settlements (P5). As of 2026-07-27: 8,658 REGISTRY_IDs map to >1
  > `PGM_SYS_ID` in `facilities.csv.gz` (max 150); 22,175 facilities (465,675 facility-years) carry
  > `IS_SHARED_REGISTRY==1`. **These exact counts are NOT fixed** — ICIS-AIR and FRS are EPA's live
  > current-bulk downloads with no archival checksum, so the fan-out shifts with every source refresh...
  > **originally also tried a hardcoded `stopifnot(... == 8632)` check** — dropped 2026-07-27 once a live
  > ICIS-AIR refresh made it stale... No principled way to split a reported quantity across co-mapped
  > facilities from this source alone; broadcasting identically and flagging lets the user decide... **Do not
  > sum `emissions` across facilities sharing a `REGISTRY_ID`** — it double-counts the same reported value."

- **EM3** (coverage): "Only ~19.4% of ICIS facility-rows (54,335 of 279,665, as of 2026-07-27) ever have
  emissions data... most emissions reporters (pure TRI/GHG/NEI filers) are outside the ICIS-Air CAA universe
  entirely."

- ⚠ **EM4 — exact-match pollutant matching, verified inflation risk, quoted in full:**
  > "Pollutant columns match a single canonical `POLLUTANT_NAME` string EXACTLY, never by substring/regex.
  > PM10 and PM2.5 each have a total... plus several component/speciation variants that are SUBSETS of that
  > total. **Verified the risk is real**: a naive substring match (`grepl('PM10', ...)`) inflates the true
  > PM10 total by **1.7×** (11.66B lbs vs. the correct 7.04B lbs, raw-file-wide); same 1.7× inflation for
  > PM2.5. VOC/NOx/SO2/CO have exactly one variant each, so exact match costs nothing there. A silent,
  > easy-to-miss double-count — caught only by deliberately comparing exact-match vs. substring-match totals
  > before committing to the design."

- **EM5** (`HAP_LBS`): "`HAP_LBS` sums every row with `NEI_TYPE == 'HAP'` (292 distinct pollutant names).
  Checked for a 'Total HAP' aggregate row first (would double-count against the individual HAPs it
  aggregates) — **none exists**, so the plain sum is safe."

- **EM6** (GHG independence — don't combine units): "`GHG_MTCO2E`/`GHG_OBSERVED` kept fully independent of
  `EMISSIONS_OBSERVED`/the pounds columns. `UNIT_OF_MEASURE` is `MTCO2e` for E-GGRT rows only (196,055 of
  10.4M), `Pounds` for everything else — never combinable. GHG reporting (E-GGRT) is also its own regulatory
  requirement, not a subset of EIS/TRI/CAMD air-toxics reporting, so a facility can be `GHG_OBSERVED` without
  being `EMISSIONS_OBSERVED` or vice versa." Pounds columns and `GHG_MTCO2E` are **different units on
  different columns** — do not sum or combine them.

- **EM7** (structurally uneven coverage): "EIS (90% of raw rows) has data ONLY in 2008, 2011, 2014, 2017,
  2020 (NEI's real triennial inventory cycle); TRIS/CAMDBS/E-GGRT report annually but only from 2015 on...
  Left as raw, undated gaps (same zero-vs-NA discipline as the rest of the layer) — interpolation is an
  analysis-time choice, not a build-time one."

- **EM8**: "Duplicate rows kept, not deduped (R3 precedent) — 11,774 of 10,397,173 `(year, REGISTRY_ID,
  PGM_SYS_ACRNM, PGM_SYS_ID, POLLUTANT_NAME)` groups have >1 row (1,984 byte-identical). All rows are summed
  as-is."

- **Cross-file caveat, same fan-out pattern as ds 3** (`docs/data_dictionary_derived.md`): "penalties.
  `N_SETTLEMENT_FACILITIES`/`IS_MULTI_FACILITY`... and emissions. `N_PGM_SYS_ID_SHARING_REGISTRY`/
  `IS_SHARED_REGISTRY`... both expose a many-to-one join as a flag rather than resolving it — the common
  warning in both cases is 'don't sum across the broadcast without deciding a rule first.'"

- **Verified by reading the script directly:** the exact-match pollutant map, the deliberate
  `relationship = "many-to-many"` broadcast join, the independent `emissions_observed`/`ghg_observed`
  coalesce, and all `stopifnot()` invariants including the "fan-out survives the join unchanged" check
  (lines 135-162). **Inferred/not independently re-run this pass:** the 1.7× substring-inflation figure, the
  8,658/22,175 fan-out counts (explicitly noted in the script and decisions doc as non-fixed, live-refresh
  quantities), and the EIS triennial-cycle coverage pattern — quoted from the decisions doc's own
  verification, not re-derived here.
