> **Status:** draft — [ ] verified against the current script (Claude, 2026-07-30)

# `03_hpv_spells.R` — builds dataset 2, `hpv_spells.csv.gz` (one row per HPV spell, UNcollapsed)

## Purpose in the pipeline
> **TODO (Grace):** write the 1-2 sentence purpose blurb here — why this script exists and what depends on
> it. Starting material, from the script's own header comment:
> "code/03_datasets/03_hpv_spells.R -- DATASET 2: hpv_spells. One row per HPV spell, UNcollapsed. The
> spell-level source of truth for High Priority Violation status. Dataset `hpv_active` (facility x year,
> built in 04_hpv_active.R) is a deterministic R2 collapse of THIS table; nothing here is lost."

## Inputs & outputs
- **Input:** `data/processed/violations.csv.gz` — the raw ICIS-Air violation-history extract, event-grain
  (one row per violation record), historical (spans the extract's full recorded date range). Plus
  `data/processed/facilities.csv.gz` (for the `REGISTRY_ID` join only — `violations.csv.gz` carries no FRS id
  natively).
- **Output:** `data/datasets/hpv_spells.csv.gz` — **spell grain**: one row per HPV violation record
  (`ENF_RESPONSE_POLICY_CODE == "HPV"`), UNcollapsed — a facility has 0..N rows. Does **not** join 1:1 to
  datasets 0/1; join on `PGM_SYS_ID` only (many-to-one).

Example — 3 rows from `data/datasets/hpv_spells.csv.gz` (sampled from the actual file on disk, 2026-07-30):

| PGM_SYS_ID | HPV_DAYZERO_DATE | HPV_RESOLVED_DATE | DAYZERO_YEAR | SPELL_STATUS | SPELL_DAYS | AGENCY_TYPE_DESC |
|---|---|---|---|---|---|---|
| 020000003402300024 | 1997-12-09 | 2000-08-16 | 1997 | closed | 982 | State |
| 040000000107340105 | 1998-06-30 | 1998-07-24 | 1998 | closed | 25 | U.S. EPA |
| 040000000107340133 | 1998-03-31 | 1998-04-30 | 1998 | closed | 31 | U.S. EPA |

Full column list (19): `PGM_SYS_ID`, `REGISTRY_ID`, `ACTIVITY_ID`, `COMP_DETERMINATION_UID`,
`HPV_DAYZERO_DATE`, `HPV_RESOLVED_DATE`, `DAYZERO_YEAR`, `RESOLVED_YEAR`, `SPELL_STATUS`, `SPELL_DAYS`,
`EARLIEST_FRV_DETERM_DATE`, `PROGRAM_CODES`, `PROGRAM_DESCS`, `POLLUTANT_CODES`, `POLLUTANT_DESCS`,
`AGENCY_TYPE_DESC`, `STATE_CODE`, `DUP`, `DUP_EXACT`.

## At a glance
| | |
|---|---|
| **Input** | `data/processed/violations.csv.gz` + `data/processed/facilities.csv.gz` |
| **Output** | `data/datasets/hpv_spells.csv.gz` — 44,777 spells × 19 cols (as of 2026-07-27), 15,656 facilities |
| **Runtime** | not measured; small relative to the other four scripts (single source table, filtered to `ENF_RESPONSE_POLICY_CODE == "HPV"` before any heavy processing) |
| **Requires** | nothing upstream in this layer (only `data/processed/`) |
| **Dependencies** | `readr`, `dplyr`, `lubridate`, `here` |

## Walkthrough
`COLS` pins the exact set of raw `violations.csv.gz` columns read in. `v` reads the file and immediately
`filter(ENF_RESPONSE_POLICY_CODE == "HPV")` — the enforcement-response *tier*, not a "has a day-zero date"
filter (H1). `frs_ids` reads `facilities.csv.gz` for the `REGISTRY_ID` join (same "ICIS facilities table, not
actual FRS data" naming caveat noted in `02_operating.R`). The `spells` pipeline parses `HPV_DAYZERO_DATE`/
`HPV_RESOLVED_DATE`/`EARLIEST_FRV_DETERM_DATE` with `mdy()` (no plausibility screen — H4), derives
`dayzero_year`/`resolved_year`, and classifies `spell_status` via `case_when` into one of four mutually
exclusive states: `missing_start` (no day-zero), `open` (day-zero, no resolved date), `bad_order` (resolved
before day-zero), or `closed` (both present, well-ordered) — see H3. `spell_days` is computed only for
`closed` spells, as an inclusive day count (`resolved − dayzero + 1`). The final `transmute()` selects the
output columns and the whole thing is arranged by `PGM_SYS_ID`, day-zero, resolved. Six `stopifnot()`
invariants close the build: row-grain uniqueness (`PGM_SYS_ID`, `ACTIVITY_ID`, `COMP_DETERMINATION_UID`,
day-zero), `spell_status` exhaustiveness, `spell_days` NA-iff-not-closed, closed `spell_days >= 1`,
`dayzero_year` NA-iff-`missing_start`, and a dup-free assertion (violations carry no duplicates, matching ds
0's own assertion). `write_dataset(spells, "hpv_spells")` writes the file with a status-breakdown summary
line.

## Notes & gotchas
- **H1** — "**HPV universe = `ENF_RESPONSE_POLICY_CODE == "HPV"`** (the enforcement-response tier), NOT
  day-zero presence. ... The tier below, **FRV** (Federally Reportable Violation), is excluded. Diagnostic 08
  ... confirms the two definitions still differ by only **33** records (every day-zero record is ENF-coded
  HPV; ENF adds 33 start-less ones ...). The FRV-side 'resolved date but no day-zero' count is **28,535** as
  of 2026-07-27 — a different object (N17), correctly out of scope."
- **H2** — "**Spell grain — one row per HPV record, UNcollapsed.** Overlapping/concurrent spells are NOT
  merged. ... Faithful source of truth; merging is a collapse-time choice. **43.1%** of closed spells overlap
  another spell of the same facility ... — union is deferred to `hpv_active`, not baked in here."
- **H3** — "**`SPELL_STATUS` ∈ {closed, open, bad_order, missing_start}** (mutually exclusive); **`SPELL_DAYS`**
  (inclusive) defined **only** for `closed`. ... **`closed` is the complement of the other three** — has both
  a day-zero and a resolved date ≥ day-zero. As of 2026-07-27: **closed** (40,515, 90.5%, the remainder);
  **open** (3,755, 8.4%) = day-zero, no resolved (persistent noncompliance — kept). **bad_order** (474, 1.1%)
  = resolved < day-zero. **missing_start** (33, unchanged) = no day-zero (23 have a resolved date, 10 have
  neither)."
- **H4** — "**Dates carried AS PARSED — no plausibility screen.** ... Source of truth stays faithful; a `218`
  day-zero record still survives (H7). Screening is a downstream / `hpv_active`-collapse decision, kept out
  of the spell table."
- **H5** — "**Facility-year mapping rule = R2** (interval overlap; open/bad-order conservatively closed on
  Dec-31 of the day-zero year). Feeds `hpv_active`. ... Diagnostic 09 quantified each lever over 2005–2025
  ...: **R1→R2 (duration) +19,588 fac-yrs** (was +19,378; day-zero-year-only *halves* coverage — rejected);
  **R2→R3 (extend open spells) +10,957** ... (an assumption about missing resolution dates — rejected as too
  strong); **R2→R4 (30-day threshold) −1,964** ... R2 chosen: faithful to spell duration without manufacturing
  an open-ended tail."
- ⚠ **In-script FLAGGED ISSUE #1 (latent, not currently triggered)**: the `spell_status` `case_when` tests
  `nz()` (non-blank raw string) rather than whether `mdy()` actually parsed the date. "0 rows affected either
  side as of the 2026-07-27 snapshot, independently verified" — a non-blank-but-unparseable
  `HPV_DAYZERO_DATE` would skip `missing_start` and fall through with a `NA` dayzero baked in; a
  non-blank-but-unparseable `HPV_RESOLVED_DATE` would fall through to `closed` with `NA` `spell_days` despite
  the status implying it should be defined. The `stopifnot()` invariant "closed spell_days must be >= 1"
  would catch this and halt the build if it ever happened — "a latent robustness gap with an effective safety
  net, not an active bug."
- Verified by reading the full script (`code/03_datasets/03_hpv_spells.R`, 118 lines) and sampling
  `data/datasets/hpv_spells.csv.gz` directly (`gzcat ... | head -4`). H1–H5 quotes pulled verbatim from
  `dataset_construction_decisions.md` Part D — not independently re-derived this pass.
