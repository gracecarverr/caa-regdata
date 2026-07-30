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
  (2015–2025, with 2018 present as explicit-NA rows). Key fields: `PGM_SYS_ID`, `year`, `op_status_code`,
  `op_status_desc`, `operating` (0/1/NA).

Example — real rows from `data/processed/wayback_facility_status.csv.gz`
(`gzcat data/processed/wayback_facility_status.csv.gz | ...`, sampled 2026-07-30):

Row showing the 2018 explicit-NA gap:

| PGM_SYS_ID | op_status_code | op_status_desc | year | operating |
|---|---|---|---|---|
| 0100000009003E0010 | NA | NA | 2020 | NA |

Row showing a real (non-gap) observation:

| PGM_SYS_ID | op_status_code | op_status_desc | year | operating |
|---|---|---|---|---|
| 010000000901110001 | OPR | Operating | 2017 | 1 |
| 010000000901110001 | OPR | Operating | 2019 | 1 |
| 010000000901110001 | OPR | Operating | 2020 | 1 |

(The first row's own NA-across-all-fields at year 2020 is itself a facility whose observed span doesn't
happen to cover a real 2020 snapshot for that particular row printed above — see LOCF/edge-censoring gotchas
below for how to read NA rows generally.) File has 2,797,699 facility-year rows on disk.

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
6. Write to `data/processed/wayback_facility_status.csv.gz`.

## Notes & gotchas
- **"In service" = {OPR, TMP, SEA}.** Temporarily-closed and Seasonal are treated as operating (load-bearing
  convention, per `code/02_cleaning/wayback/README.md`).
- **Snapshot presence is the truth**, not the source begin/close dates.
- **LOCF fills interior gaps only.** Per the folder README: "A facility absent from a *middle* snapshot
  inherits its last observed status; leading/trailing edges are left `NA` and handled downstream."
- **2018 is explicit NA, not LOCF-filled** — from the script's own header: "NO REAL 2018 SNAPSHOT EXISTS...
  it was a mislabeled duplicate, not a real archived snapshot, and was removed from data/raw/ (2026-07-21)...
  2018 is deliberately EXPLICIT NA (op_status_code, op_status_desc, operating), NOT LOCF-filled like an
  ordinary interior gap -- an ordinary gap means one facility happened to be missing from an otherwise-real
  snapshot; 2018 has no real snapshot for ANY facility, so there is no evidence to infer from and none is
  asserted." ⚠️ Treating a 2018 row as an ordinary LOCF-fillable gap would silently manufacture status
  evidence that doesn't exist.
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
