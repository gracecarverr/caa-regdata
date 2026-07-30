> **Status:** draft — [ ] verified against the current script (Claude, 2026-07-30)

# `17_wayback_facility_status.R` — reconstructed facility-year operating status from Wayback snapshots

## Purpose in the pipeline
> **TODO (Grace):** write the 1-2 sentence purpose blurb here — why this script exists and what depends on
> it. Starting material, from the script's own header comment:
> "code/02_cleaning/wayback/17_wayback_facility_status.R -- HISTORICAL facility operating status from the
> ICIS-AIR WAYBACK snapshots (annual echo.epa.gov downloads captured Sep-Nov of each year, 2015-2025 EXCEPT
> 2018 -- see below). One snapshot = one panel year (the snapshot reflects the ~Q4 state of year Y).
> Reconstructs a facility x year status series that the single current-snapshot AIR_OPERATING_STATUS lacks.
> in : data/raw/ICIS_AIR_WAYBACK/ICIS-AIR_downloads_{2015..2025 except 2018}/ICIS-AIR_FACILITIES.csv
> out: data/processed/wayback_facility_status.csv.gz   (PGM_SYS_ID, year, op_status_code, op_status_desc, operating)
>
> operating = 1 iff status in {OPR, TMP, SEA} (Operating / Temporarily Closed / Seasonal are all 'in service'
> per project decision); 0 for CLS/PLN/CNS/NER/NED/NES/LDF; NA where code is missing."

## Inputs & outputs
- **Input:** `data/raw/ICIS_AIR_WAYBACK/ICIS-AIR_downloads_{2015..2025 except 2018}/ICIS-AIR_FACILITIES.csv`
  — one row per facility per annual Wayback snapshot; only `PGM_SYS_ID`, `AIR_OPERATING_STATUS_CODE`,
  `AIR_OPERATING_STATUS_DESC` are read.
- **Output:** `data/processed/wayback_facility_status.csv.gz` — one row per **facility × year**
  (2015–2025, with most 2018 rows still `NA` — see below). Key fields: `PGM_SYS_ID`, `year`, `op_status_code`,
  `op_status_desc`, `operating` (0/1/NA), `operating_imputed` (0/1, NEW 2026-07-30, never `NA`).

Example — real rows from `data/processed/wayback_facility_status.csv.gz`
(`gzcat data/processed/wayback_facility_status.csv.gz | ...`, sampled 2026-07-30):

Row showing the 2018 bridge-imputed case (facility confirmed `OPR` in both real 2017 and 2019 snapshots):

| PGM_SYS_ID | op_status_code | op_status_desc | year | operating | operating_imputed |
|---|---|---|---|---|---|
| 010000000901110001 | OPR | Operating | 2017 | 1 | 0 |
| 010000000901110001 | NA | NA | 2018 | 1 | **1** |
| 010000000901110001 | OPR | Operating | 2019 | 1 | 0 |

Row showing an ordinary explicit-NA gap (2018, non-qualifying — no matching real 2017/2019 pair for this
facility):

| PGM_SYS_ID | op_status_code | op_status_desc | year | operating | operating_imputed |
|---|---|---|---|---|---|
| 0100000009003E0010 | NA | NA | 2020 | NA | 0 |

(The second example's own NA-across-all-fields at year 2020 is a facility whose observed span doesn't happen
to cover a real 2020 snapshot — see LOCF/edge-censoring gotchas below for how to read ordinary NA rows.) File
has 2,797,699 facility-year rows on disk; of these, **229,679 (8.2%) are 2018 rows with `operating_imputed==1`**
(165,869 bridged to operating, 63,810 to non-operating) — see gotchas for the exact rule.

## At a glance
| | |
|---|---|
| **Input** | `ICIS-AIR_FACILITIES.csv` × 10 Wayback years (2015–2017, 2019–2025) |
| **Output** | `data/processed/wayback_facility_status.csv.gz` — 2,797,699 facility-year rows, ~9.1MB |
| **Runtime** | not measured directly; reads 10 CSVs (each ~230k–280k rows) plus a `data.table` densify/LOCF over ~250k facility spans — likely under a minute |
| **Requires** | `01_download.R` (Wayback snapshots staged); runs as the first of the 3 `wayback/` scripts within `02_clean.R`, before `18_` and `19_` |
| **Dependencies** | `readr`, `dplyr`, `data.table` |

## Walkthrough
1. **`read_snapshot(y)`** reads one year's `ICIS-AIR_FACILITIES.csv`, keeping only `PGM_SYS_ID` and the two
   operating-status columns, drops rows with no `PGM_SYS_ID`, and `distinct(PGM_SYS_ID, .keep_all = TRUE)`s
   to guarantee one row per facility per snapshot.
2. **Stack all 10 years** (`SNAP_YEARS <- setdiff(2015:2025, 2018)`) into one long `snaps` table, renaming to
   `op_status_code`/`op_status_desc`.
3. **Densify + LOCF via `data.table`**: for each facility, build the full year sequence from its first to
   last observed snapshot year (`span`/`grid`), right-join the real observations onto that grid (gap years
   become NA rows), then forward-fill (`locf()`, a `cummax`-based carry-forward that leaves leading NAs
   untouched) within each facility's span.
4. **Force 2018 back to NA** after the LOCF step, since 2018 has no real snapshot for *any* facility (unlike
   an ordinary sporadic per-facility gap) — see gotchas.
5. **Derive `operating`**: 1 if `op_status_code` is one of `OPERATING_CODES = c("OPR","TMP","SEA")`, 0 if it's
   a real code outside that set, NA if the code itself is NA.
6. **NEW 2026-07-30 — 2018 bridge imputation.** From `dt` (the pre-LOCF, pre-densify real-observation stack,
   step 2's output before step 3 densifies it), build per-facility `operating` values for the *real* 2017 and
   2019 snapshots specifically (not `full`/`status`, which mix in LOCF-carried values). Inner-join them, keep
   only facilities where both years agree (`op2017 == op2019`), and for every 2018 row belonging to one of
   those facilities, set `operating` to the shared value and `operating_imputed = 1L`. `op_status_code`/
   `op_status_desc` are left `NA` — see gotchas for why. Every other row gets `operating_imputed = 0L`.
7. Write to `data/processed/wayback_facility_status.csv.gz`.

## Notes & gotchas
- **"In service" = {OPR, TMP, SEA}.** Temporarily-closed and Seasonal are treated as operating (load-bearing
  convention, per `code/02_cleaning/wayback/README.md`).
- **Snapshot presence is the truth**, not the source begin/close dates.
- **LOCF fills interior gaps only.** Per the folder README: "A facility absent from a *middle* snapshot
  inherits its last observed status; leading/trailing edges are left `NA` and handled downstream."
- **2018 is explicit NA for MOST facilities, not LOCF-filled** — from the script's own header: "NO REAL 2018
  SNAPSHOT EXISTS... it was a mislabeled duplicate, not a real archived snapshot, and was removed from
  data/raw/ (2026-07-21)... 2018 is deliberately EXPLICIT NA (op_status_code, op_status_desc, operating), NOT
  LOCF-filled like an ordinary interior gap -- an ordinary gap means one facility happened to be missing from
  an otherwise-real snapshot; 2018 has no real snapshot for ANY facility, so there is no evidence to infer
  from and none is asserted by default." ⚠️ Treating an ordinary interior gap as if it were 2018 (or vice
  versa) would either silently manufacture evidence or silently withhold real LOCF-eligible evidence.
- ⚠️ **NEW 2026-07-30 — the one narrow exception: 2018 `operating`-only bridge imputation (`operating_imputed`
  column), an explicit `O2` exception, not a reversal of the "no imputation" rule generally.** Quoted from the
  script's own header: *"a facility with a REAL raw 2017 snapshot AND a REAL raw 2019 snapshot showing the
  SAME operating bucket... gets that shared value imputed into its 2018 row... Mismatched pairs... are NOT
  touched -- that transition-timing case is already handled deliberately by 18_wayback_facility_spells.R's
  '2017-op -> 2018-gap -> 2019-closed' exit-classification logic (W7)... 'Real raw' means present in that
  year's ACTUAL ICIS-AIR_FACILITIES.csv snapshot -- NOT an LOCF-carried value... op_status_code/op_status_desc
  are DELIBERATELY LEFT NA for imputed rows -- we only know the coarse in-service-vs-not bucket agreed on both
  sides, not which specific code applied in 2018, and fabricating one would silently overstate precision.
  This also matters downstream: 18_wayback_facility_spells.R's exit-transition classifier treats
  `!is.na(op_status_code)` as 'real evidence' -- keeping it NA here means an imputed row is invisible to that
  logic, so entry/exit spells are provably unaffected by this change."* Verified empirically this session, not
  just by proof: `wayback_facility_spells.csv.gz` was byte-identical before and after this change. **Why raw
  observations only, not LOCF-carried neighbors too:** checked directly before deciding — interior-gap LOCF
  is vanishingly rare (29 of 2,506,480 non-`NA` facility-years across 2015–2025, 0.001%; only 14 of ~229,000
  2017/2019 opr-opr/cls-cls-matching pairs involve an LOCF year at all), so raw-only costs nothing in coverage
  and avoids compounding one imputation inside another. Result: **229,679 of 2018's facility-year rows
  (8.2%)** get `operating_imputed==1` (165,869 bridged to operating, 63,810 to non-operating); every other
  2018 row (and every non-2018 row) has `operating_imputed==0`.
- **The `distinct(PGM_SYS_ID, .keep_all=TRUE)` dedup step is a near-total no-op on the raw data — verified
  this session, not just inferred.** Checked directly against `ICIS-AIR_FACILITIES.csv` for 5 sampled Wayback
  years (2015, 2019, 2021, 2023, 2025) via `readr::read_csv` + `duplicated()`: **0 duplicate `PGM_SYS_ID` rows
  found in any of the 5 years** (row counts 228,513 / 249,669 / 259,967 / 271,609 / 278,540, all fully
  distinct). The `distinct()` call is defensive/guarantees-the-invariant, not currently doing real
  deduplication work on this data.
- Verified by reading the script in full and by directly sampling `wayback_facility_status.csv.gz` and the 5
  raw Wayback `ICIS-AIR_FACILITIES.csv` files off disk this session. Did not re-run the script itself (output
  on disk matches what the current code would produce, per the reproducibility conventions this pipeline
  otherwise verifies against).
