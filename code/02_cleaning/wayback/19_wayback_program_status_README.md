> **Status:** draft — [ ] verified against the current script (Claude, 2026-07-30)

# `19_wayback_program_status.R` — reconstructed facility-year program-enrollment status from Wayback snapshots

## Purpose in the pipeline
> **TODO (Grace):** write the 1-2 sentence purpose blurb here — why this script exists and what depends on
> it. Starting material, from the script's own header comment:
> "code/02_cleaning/wayback/19_wayback_program_status.R -- HISTORICAL program status from the ICIS-AIR
> WAYBACK snapshots (2015-2025 EXCEPT 2018 -- no real snapshot exists, see 17_'s header note...; 2018 is
> explicit NA, NOT LOCF-filled, unlike an ordinary interior gap -- no facility has a real 2018 snapshot to
> infer from). The raw PROGRAMS table has an unreliable BEGIN_DATE and NO program-close date; we instead
> reconstruct a facility x year 'is this program active?' series from snapshot PRESENCE + operating status.
> Covers the 10 program groups already flagged downstream (facility spine, code/03_panel_building/00_spine.R).
> in : data/raw/ICIS_AIR_WAYBACK/ICIS-AIR_downloads_{2015..2025 except 2018}/{ICIS-AIR_FACILITIES,ICIS-AIR_PROGRAMS}.csv
> out: data/processed/wayback_program_status.csv.gz
>      PGM_SYS_ID, year, prog_{sip,titlev,nsps,mact,gact,neshap,fesop,nsr,psd,cfc}_active
>
> prog_X_active in a given snapshot year = 1 iff the facility carries >=1 program in group X whose status is
> ACTIVE under a PROGRAM-SPECIFIC rule: operating programs (sip/titlev/nsps/mact/gact/neshap/fesop/cfc) are
> active only for {OPR,TMP,SEA} (mirrors the 17_ operating whitelist); the preconstruction programs NSR & PSD
> are ALSO active for {PLN,CNS} (planned / under-construction), since those permits attach before a source
> operates."

## Inputs & outputs
- **Input:** `data/raw/ICIS_AIR_WAYBACK/ICIS-AIR_downloads_{2015..2025 except 2018}/ICIS-AIR_FACILITIES.csv`
  (facility's own `PGM_SYS_ID` + `AIR_OPERATING_STATUS_CODE`, for the blank/CLS gate) and
  `.../ICIS-AIR_PROGRAMS.csv` (`PGM_SYS_ID`, `PROGRAM_CODE`, `AIR_OPERATING_STATUS_CODE` per program
  enrollment).
- **Output:** `data/processed/wayback_program_status.csv.gz` — one row per **facility × year**
  (2015–2025, 2018 explicit NA). Key fields: `PGM_SYS_ID`, `year`, and the 10 `prog_{sip,titlev,nsps,mact,
  gact,neshap,fesop,nsr,psd,cfc}_active` flags (0/1/NA).

Example — real rows from `data/processed/wayback_program_status.csv.gz`
(`gzcat data/processed/wayback_program_status.csv.gz | ...`, sampled 2026-07-30):

| PGM_SYS_ID | year | prog_sip_active | prog_titlev_active | prog_nsps_active | prog_mact_active | prog_nsr_active | prog_psd_active |
|---|---|---|---|---|---|---|---|
| 010000000901110001 | 2017 | 0 | 0 | 1 | 0 | 0 | 0 |
| 010000000901110001 | 2019 | 0 | 0 | 1 | 0 | 0 | 0 |
| 010000000901110001 | 2020 | 0 | 0 | 1 | 0 | 0 | 0 |

(Table trimmed to 6 of the 12 real columns for readability — full columns are `PGM_SYS_ID, year,
prog_sip_active, prog_titlev_active, prog_nsps_active, prog_mact_active, prog_gact_active,
prog_neshap_active, prog_fesop_active, prog_nsr_active, prog_psd_active, prog_cfc_active`. This facility is
active only in the NSPS group across the sampled years.) A 2018-gap / all-NA row also appears on disk for
facilities whose span crosses 2018 (e.g. `0100000009003E0010,2020,NA,NA,NA,...`). File has 2,797,699
facility-year rows on disk (same grain as `wayback_facility_status.csv.gz`).

## At a glance
| | |
|---|---|
| **Input** | `ICIS-AIR_FACILITIES.csv` + `ICIS-AIR_PROGRAMS.csv` × 10 Wayback years |
| **Output** | `data/processed/wayback_program_status.csv.gz` — 2,797,699 facility-year rows, ~9.1MB |
| **Runtime** | not measured directly; reads 20 CSVs (2 tables × 10 years) plus a `pivot_wider` and a `data.table` densify/LOCF over ~250k facility spans across 10 flag columns — likely a minute or two, the heaviest of the 3 wayback scripts |
| **Requires** | `01_download.R` (Wayback snapshots staged). Does **not** depend on `17_` or `18_`'s output directly (reads raw Wayback files itself) but runs third in `02_clean.R`'s wayback loop by filename order |
| **Dependencies** | `readr`, `dplyr`, `tidyr`, `data.table` |

## Walkthrough
1. **`GROUPS`/`code2group`**: hand-maintained map from raw `PROGRAM_CODE` values (e.g. `CAASIP`, `CAANSPSM`)
   to the 10 short group names used downstream (`sip`, `titlev`, `nsps`, …). Must stay aligned with the
   `prog_*` flags built in `code/03_panel_building/00_spine.R` (or its current-numbering equivalent).
2. **`present_raw`/`present`**: the observed facility × year grid from `ICIS-AIR_FACILITIES.csv` presence
   alone, carrying along the facility's own operating-status code that year (same field `17_` reads).
3. **`blank_or_closed`**: facility-years where that status is blank or `CLS` — flagged for the NA override
   applied later (W8, see gotchas).
4. **`active`**: from `ICIS-AIR_PROGRAMS.csv`, join each program row to its group via `code2group`, filter to
   rows meeting the program-specific active rule (`OPERATING_ACTIVE = {OPR,TMP,SEA}` for the 8 "operating"
   groups; NSR/PSD additionally accept `{PLN,CNS}`), then `pivot_wider` into one `prog_{grp}_active` column
   per group with `values_fill = 0L`.
5. **`wide`**: left-join `active` onto the full `present` grid — a facility present that year but with no
   active row for group X gets an observed `0` for that group (not NA), since presence itself is real
   evidence.
6. **Densify + LOCF via `data.table`**, mirroring `17_`: build each facility's full year span, right-join the
   real facility-years onto it (gap years → NA across all 10 flag columns), then `nafill(type="locf")` per
   facility.
7. **2018 override**: force all 10 flag columns back to NA for year 2018, same rationale as `17_`.
8. **Blank/CLS override**: force all 10 flag columns to NA wherever `blank_or_closed` — applied **after** the
   LOCF step specifically so these facility-years can't be silently re-filled from a neighboring year (see
   gotchas for the one residual edge case this doesn't close).
9. Write to `data/processed/wayback_program_status.csv.gz`.

## Notes & gotchas
- **The program-specific active rule** (quoted from the folder README): "operating programs
  (sip/titlev/nsps/mact/gact/neshap/fesop/cfc) are active only for {OPR,TMP,SEA} (mirrors the 17_ operating
  whitelist); the preconstruction programs NSR & PSD are ALSO active for {PLN,CNS}... since those permits
  attach before a source operates." `BEGIN_DATE` is deliberately ignored throughout — "unreliable per project
  decision" — snapshot presence is the only signal used.
- **N10 — a confident-looking `0` can have zero supporting record.** Quoted from
  `code/02_cleaning/wayback/README.md`: "`prog_*_active` can read a confident-looking `0` with zero
  supporting record (N10). A facility present in a year's snapshot but carrying no active row for program
  group X is coded `0` for that group — correct when the facility genuinely has other `PROGRAMS` rows that
  just don't include X, but as last measured **2.18%** of present facility-years have **zero** `PROGRAMS` rows
  at all, so *every* `prog_*_active` group reads `0` for them with nothing backing any of the ten flags —
  indistinguishable, from the column alone, from a facility genuinely enrolled in nothing." ⚠️
- **W8 — blank status or `CLS` reads NA, not a confident 0.** Quoted from the script header: "BLANK STATUS or
  CLS -> NA, not 0 (project decision 2026-07-21, W8). A facility's own AIR_OPERATING_STATUS_CODE that year...
  gates this: if it's blank, we have no real status evidence that year at all, so asserting 'not enrolled' (0)
  for every group would be manufacturing certainty from an incomplete record -- NA instead. If it's CLS
  (Permanently Closed), mirrors the already-established W6 event-zero rule ('closed years stay NA... a shut
  plant can still carry legacy enforcement') -- a closed facility's program enrollment isn't confidently
  'none,' it's simply not asserted. Every OTHER real status (OPR/TMP/SEA/PLN/CNS/NER/NED/NES/LDF) keeps a real
  0/1 per the program-specific rule above -- only blank and CLS become NA." ⚠️
- **Known residual edge case in the LOCF/override interaction** — from the script header: "LOCF itself runs
  before the override, so a genuinely-absent gap year immediately adjacent to a blank/CLS year can still
  inherit that year's PRE-override computed value (0) rather than NA -- this requires both a roster-absence
  gap (~0.3% of facility-programs, W4) AND it landing next to a blank/CLS year, a rare compound case, not
  fixed here." ⚠️ Rare but explicitly unfixed.
- **`prog_*_active` diverges from facility-level `operating` because the two are read from two different raw
  columns EPA does not keep synchronized — verified, not assumed.** Quoted from `data/processed/README.md`:
  "**Why this can disagree with facility-level `operating` (N11) — verified, not assumed:** the two are
  computed from **two different raw columns**. `operating` (`17_wayback_facility_status.R`) reads
  `AIR_OPERATING_STATUS_CODE` off `ICIS-AIR_FACILITIES.csv` — one row per facility. `prog_*_active`
  (`19_wayback_program_status.R`) reads the **same-named column on a different table**,
  `ICIS-AIR_PROGRAMS.csv` — one row per program enrollment, and ICIS lets that field carry its own value per
  enrollment, independently of the facility's own record. Direct comparison on the 2025 Wayback snapshot:
  **20,574 of 454,144 program rows (4.5%) disagree with their own facility's status the same year** (e.g.
  facility `OPR`, one of its program enrollments still `CLS`) — a real gap in how EPA keeps the two fields
  synchronized, not a data artifact either script introduces. **By design, each rule reports exactly what its
  own raw field says and neither is corrected against the other** — a closed program on an open facility is
  real information (e.g. that specific permit/program status ended) and should read that way, not get
  silently reconciled to match `operating`." ⚠️ Do not "fix" a `prog_*_active`/`operating` mismatch by
  reconciling one to the other — it's real underlying data, not a bug in either script.
  Downstream, `data/datasets/operating.csv.gz` carries only 8 of these 10 groups as `PROG_*_ACTIVE` flags
  (`gact`/`cfc` excluded to match an earlier schema — see decision `R6` in
  `briefs/datasets/dataset_construction_decisions.md`).
- Verified by reading the script in full and by directly sampling `wayback_program_status.csv.gz` off disk.
  The 4.5% disagreement figure and 2.18%/N10 figure are quoted from `data/processed/README.md`, not
  re-derived this session. Did not re-run the script.
