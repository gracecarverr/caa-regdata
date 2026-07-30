> **Status:** draft — [ ] verified against the current script (Claude, 2026-07-30)

# `02_operating.R` — builds dataset 1, `operating.csv.gz`, AND dataset 1b, `wayback_only_facilities.csv.gz`

**This script has two outputs**, both written at the end of the file: the main `operating.csv.gz` rectangle
(joins 1:1 to `regulatory.csv.gz`) and a small supplementary `wayback_only_facilities.csv.gz` for facilities
Wayback has seen that the current ICIS roster hasn't (dataset 1b).

## Purpose in the pipeline
> **TODO (Grace):** write the 1-2 sentence purpose blurb here — why this script exists and what depends on
> it. Starting material, from the script's own header comment:
> "code/03_datasets/02_operating.R -- DATASET 1: the operating dataset. Facility x year. Reconstructed
> operating evidence that dataset 0 (regulatory) deliberately holds out: year-varying operating status,
> program-active flags, facility entry/exit spells, and the earliest program-enrollment year. ALSO BUILDS
> (added this session...): (a) two YEAR-VARYING 'how do we know this facility-year was real' indicators --
> ACTIVE, ACTIVE_BROAD ... (b) a small SEPARATE output, wayback_only_facilities.csv.gz, for the population
> Wayback has seen operating at some point but that has since vanished from the current ICIS-AIR facility
> extract entirely (O1a)."

## Inputs & outputs
- **Input:** `data/processed/{wayback_facility_status,wayback_program_status,wayback_facility_spells,
  facilities,programs}.csv.gz` — the Wayback reconstruction is **historical**, built from 11 archived annual
  Internet Archive captures (2015–2025), one facility × year row per snapshot. **Plus (NEW, cross-dataset)**
  `data/datasets/{regulatory,emissions}.csv.gz` — both must already exist on disk (`RUN_ALL.R`'s datasets
  loop was reordered specifically to guarantee this; see the folder README).
- **Output 1 (dataset 1):** `data/datasets/operating.csv.gz` — facility × year, one row per
  `(PGM_SYS_ID, YEAR)`; same 279,665 × 21-year rectangle as `regulatory.csv.gz`, joins 1:1 to it.
- **Output 2 (dataset 1b):** `data/datasets/wayback_only_facilities.csv.gz` — facility × year, 2015–2025
  only; the ~15,302 facilities Wayback has captured that are absent from the current ICIS-AIR extract
  entirely. Does **not** join to `regulatory.csv.gz`/`operating.csv.gz`.

Example — 2 rows from `data/datasets/operating.csv.gz` (sampled from the actual file on disk, 2026-07-30,
filtered to a facility with `ACTIVE==1` and real Wayback status so the columns aren't all-`NA`):

| PGM_SYS_ID | YEAR | WAYBACK_OBSERVED | OP_STATUS_CODE | OPERATING | ICIS_OBSERVED | ACTIVE | ACTIVE_BROAD |
|---|---|---|---|---|---|---|---|
| 010000000901110001 | 2017 | 1 | OPR | 1 | 1 | 1 | 1 |
| 010000000901110001 | 2019 | 1 | OPR | 1 | 0 | 1 | 1 |

Other columns in `operating.csv.gz` (27 total): `REGISTRY_ID`, `OP_STATUS_DESC`, the eight `PROG_*_ACTIVE`
flags (`PROG_SIP/TITLEV/NSPS/MACT/NESHAP/FESOP/NSR/PSD_ACTIVE`), `ENTERED_YEAR`, `EXITED_YEAR`,
`EXIT_SOURCE`, `LEFT_CENSORED`, `RIGHT_CENSORED`, `EARLIEST_PROGRAM_BEGIN_YEAR_RAW`,
`EARLIEST_PROGRAM_BEGIN_YEAR`, `EMISSIONS_OBSERVED`, `GHG_OBSERVED`.

Example — 3 rows from `data/datasets/wayback_only_facilities.csv.gz` (sampled from disk, 2026-07-30):

| PGM_SYS_ID | YEAR | WAYBACK_OBSERVED | OP_STATUS_CODE | OPERATING | ENTERED_YEAR | EXIT_SOURCE |
|---|---|---|---|---|---|---|
| 01000000E000000030 | 2015 | 0 | NA | NA | NA | NA |
| 01000000E000000030 | 2016 | 0 | NA | NA | NA | NA |
| 01000000E000000030 | 2017 | 0 | NA | NA | NA | NA |

Full column list (11): `PGM_SYS_ID`, `YEAR`, `WAYBACK_OBSERVED`, `OP_STATUS_CODE`, `OP_STATUS_DESC`,
`OPERATING`, `ENTERED_YEAR`, `EXITED_YEAR`, `EXIT_SOURCE`, `LEFT_CENSORED`, `RIGHT_CENSORED`. No
`REGISTRY_ID`, no `ACTIVE`/`ACTIVE_BROAD` — see O7 below for why.

## At a glance
| | |
|---|---|
| **Input** | `data/processed/{wayback_facility_status,wayback_program_status,wayback_facility_spells,facilities,programs}.csv.gz` + `data/datasets/{regulatory,emissions}.csv.gz` |
| **Output** | `data/datasets/operating.csv.gz` (5,872,965 × 27) + `data/datasets/wayback_only_facilities.csv.gz` (168,322 rows = 15,302 facilities × 11 years) |
| **Runtime** | not measured; `operating.csv` uncompressed is ~494MB, largest read is the Wayback status file across 11 snapshot years |
| **Requires** | `01_regulatory.R` and `08_emissions.R` must run first (this script reads their `data/datasets/` outputs) |
| **Dependencies** | `readr`, `dplyr`, `tidyr`, `lubridate`, `here` |

## Walkthrough
`frs_ids` reads `facilities.csv.gz` for the ICIS universe (`ids`) — despite the variable name, this is the
ICIS facility table, not actual FRS data (flagged as a naming trap in the script's own FLAGGED ISSUES #1).
`status` reads `wayback_facility_status.csv.gz` once and is reused twice: once (implicitly, via the main
rectangle's left-join) restricted to `ids`, and again later restricted to the complement of `ids` for
`wayback_only_facilities.csv.gz` — avoiding a second read of the same file. `progst` reads
`wayback_program_status.csv.gz` with an explicit `col_select` pinned to the 8-group allowlist (`sip`,
`titlev`, `nsps`, `mact`, `neshap`, `fesop`, `nsr`, `psd`) — the actual guardrail keeping `gact`/`cfc` out,
since the source file still carries all 10 groups. `spells` reads `wayback_facility_spells.csv.gz`
(facility-level, also reused for the wayback-only output). `begin` computes both
`earliest_program_begin_year_raw` (unscreened min of parsed `BEGIN_DATE` years) and
`earliest_program_begin_year` (same min, screened to `[1970, 2025]`) from `programs.csv.gz`. Two new reads
(`icis_yr`, `em_yr`) pull `ICIS_OBSERVED` from `regulatory.csv.gz` and `EMISSIONS_OBSERVED`/`GHG_OBSERVED`
from `emissions.csv.gz` — both guaranteed to share this script's exact rectangle. The assemble step builds
the `expand_grid` rectangle and left-joins all six inputs on, then computes `active` (`operating==1 OR
icis_observed==1` that year, via `case_when` exploiting `NA`-propagating `|` semantics) and `active_broad`
(`active==1 OR emissions_observed==1 OR ghg_observed==1`). Nine `stopifnot()` invariants close the main
build, including three specifically checking the `ACTIVE`/`ACTIVE_BROAD` monotonic nesting row-by-row (using
`which()` to avoid an `NA`-poisoned `any()` false alarm). After `write_dataset(op, "operating")`, a second,
independent block builds `wayback_only_facilities.csv.gz`: `wb_only_ids <- setdiff(wb_all_ids, ids)` isolates
facilities Wayback has ever captured that aren't on the current ICIS roster, `WAYBACK_YEARS <- 2015:2025` (a
narrower window than the layer's standard `YEARS`, deliberately), and the same `status`/`spells` blocks are
re-joined onto this complementary rectangle — with no `ACTIVE`/`ACTIVE_BROAD` columns, since those signals
are structurally undefined (not just `0`) for a population absent from `regulatory.csv.gz`/`emissions.csv.gz`
entirely. Five more `stopifnot()` invariants (including an explicit "0 overlap with `ids`" check) close this
second build before `write_dataset(wb_only, "wayback_only_facilities")`.

## Notes & gotchas
- **O1** — "**Universe = dataset 0's exactly** — same 279,665 facilities (as of 2026-07-27) × 2005–2025
  rectangle, so `operating` joins **1:1** to `regulatory` on `(PGM_SYS_ID, YEAR)` (verified: identical key
  vectors). ... Wayback covers a **larger** set; the **15,302 wayback-only facilities** (absent from
  `ICIS-AIR_FACILITIES`) are **dropped** — this layer is keyed to the ICIS universe. The **2,927** ICIS
  facilities with no Wayback spell get `NA` spell fields."
- **O1a** — "**The 15,302 wayback-only 'disappeared' facilities are excluded from `operating.csv.gz`'s own
  rectangle** (not added to it, to keep its 1:1 join to `regulatory.csv.gz` exact). ... **Why excluding from
  the main rectangle is defensible:** all 15,302 carry **zero ICIS events** and **zero ICIS attributes**
  ... they'd be all-`NA` ghosts in the ICIS datasets ... **Why it has a cost:** ~**1,050** (**1,018** per O7's
  exact re-check) are real **mid-window (2016–2025)** disappearances that ds 1's main table cannot see — now
  reachable via `wayback_only_facilities.csv.gz` (O7) instead of a manual raw-layer join."
- **O2** — "**Strictly raw — NO imputation.** Yearly `operating`/`op_status`/`prog_*_active` are carried for
  2015–2025 and left **`NA`** for 2005–2014 and any facility-year absent from a snapshot. `WAYBACK_OBSERVED`
  (1 iff the facility appears in that year's snapshot) is the coverage flag. ... Mirrors ds 0's zero-vs-NA
  discipline: don't manufacture certainty Wayback lacks. Spells are provided **separately** (O4) so the user
  can extend downstream by choice, not by baked-in assumption."
- **O3 (⚠ silent-failure-risk, program-status divergence is by design)** — "**`operating` carried unchanged
  from the cleaning layer** — whitelist flag (1 iff code ∈ {OPR,TMP,SEA}). `PROG_*_ACTIVE` is pinned to an
  **explicit 8-group allowlist** ... via `col_select`, using the cleaning layer's own program-specific active
  rule (N11). ... **N11's divergence is structural, verified, and by design — not a bug to reconcile:**
  ... checked directly on the 2025 Wayback snapshot: 20,574 of 454,144 program rows (4.5%) carry a status
  that disagrees with their own facility's status that year. Each column is reported exactly as ICIS has it;
  a closed program on an open facility is real information (that program's status specifically), not
  something to correct against `operating`."
- **O4** — "**Entry/exit spells broadcast facility-level, time-invariant** — `ENTERED_YEAR`, `EXITED_YEAR`,
  `EXIT_SOURCE`, `LEFT_CENSORED`, `RIGHT_CENSORED`, as-is. ⚠ **`EXIT_SOURCE` in this dataset is effectively
  pure `cls`** (18,771 confirmed closures ...). Of 11,801 Wayback `dropout` exits ... **11,799 are
  wayback-only facilities dropped by O1**; only **2** survive. **Disappearances are therefore NOT visible in
  ds 1 — this is an accepted, documented cost**."
- **O5** — "**`EARLIEST_PROGRAM_BEGIN_YEAR` = min `BEGIN_DATE` year, SCREENED to [1970, 2025]; plus
  `EARLIEST_PROGRAM_BEGIN_YEAR_RAW` = unscreened min.** ... **3,168** facilities < 1970 (incl. a `218`),
  **4,088** dated **entirely > 2025** (`2026–2028`) ... Because the field is a **min**, one garbage-low date
  poisons a facility's earliest year. Screen = validity filter on malformed values ..., **not** imputation."
- **O6 (ACTIVE/ACTIVE_BROAD, important and non-obvious)** — "**NEW (2026-07-28): `ACTIVE` / `ACTIVE_BROAD` —
  two YEAR-VARYING facility-existence indicators**, not a facility-level 'ever' summary. `ACTIVE` =
  `OPERATING==1` OR `ICIS_OBSERVED==1` **in that specific year**; `ACTIVE_BROAD` = `ACTIVE==1` OR
  (`EMISSIONS_OBSERVED==1` OR `GHG_OBSERVED==1`) **in that specific year**. ... Both keep the 0-vs-NA
  discipline: `0` only where every checked signal positively says 'not active that year'; `NA` where at least
  one signal had nothing to say that year. **Why this exists:** `regulatory.csv.gz`'s `ICIS_OBSERVED` alone
  under-counts 'was this facility real that year' ... **92,080** facilities are wayback-confirmed operating
  in some year with **zero** ICIS events ever ... Conversely `OPERATING` is wayback-only (2015–2025
  coverage), while `ICIS_OBSERVED` has full 2005–2025 coverage — of 133,753 facilities with ≥1 ICIS event
  somewhere in-window, **15,699 (11.7%)** ... have **no** wayback-confirmed operating year at all. ... **Why
  YEAR-VARYING, not an 'ever' summary (explicit user correction mid-session):** a facility-level flag can't
  distinguish 'this facility was real in 2008' from 'this facility was real in 2022' ... Full facility-year
  distribution as of 2026-07-28: `OPERATING` 0/1/NA = 686,029 / 1,784,712 / 3,402,224; `ACTIVE` = 681,016 /
  2,233,920 / 2,958,029; `ACTIVE_BROAD` = 670,476 / 2,316,699 / 2,885,790."
- **O7 (the wayback-only carve-out)** — "**NEW (2026-07-28): `wayback_only_facilities.csv.gz`** — a small,
  separate supplementary output (NOT one of the eight numbered datasets; joins to nothing else in this
  layer) covering the ~15,302 facilities Wayback has captured operating-status snapshots for that are absent
  from the current ICIS-AIR facility extract entirely (the O1a population). Grain `PGM_SYS_ID × year`, but
  window **2015–2025 only** ... since these facilities have zero information of any kind before 2015. ...
  **Deliberately carries no `ACTIVE`/`ACTIVE_BROAD`-style column** — `ICIS_OBSERVED` and
  `EMISSIONS_OBSERVED`/`GHG_OBSERVED` are structurally undefined for this population (no row to look up in
  `regulatory.csv.gz` or `emissions.csv.gz` at all, not merely a confident `0`), so any such column would
  either be all-`NA` or wrongly imply a real zero. ... **Checked directly this session:** **0 of 15,302**
  wayback-only facilities appear in *any* ICIS event asset ... `exit_source` breakdown among the 15,302:
  `dropout` 11,799, `cls` 31, `other` 3, `NA` 3,469."
- **O8 (Q4-repin update)** — "**NEW (2026-07-29): Wayback capture pins re-audited for Q4 consistency; only
  2024 moved.** ... **Finding: this is not a fixable inconsistency for most years.** The Internet Archive
  never crawled this URL in Q4 of **2015, 2017, 2019, 2023, or 2025** ... **2024 is the one year with genuine
  Q4 coverage** ... and was re-pinned to 2024-12-10. ... **Effect on this dataset, full rebuild 2026-07-29:**
  `ACTIVE_BROAD==1` facility-years 2,316,699 → 2,316,808 (+109, +0.005%); `ACTIVE==1` 2,233,920 → 2,234,031
  (+111); wayback-observed facility-years 2,470,741 → 2,471,144 (+403, +0.016%)."
- **Upstream wayback-cleaner traps that surface as this script's own output columns** (from
  `code/02_cleaning/wayback/README.md`'s "Known nuances and traps"):
  - **N9** — a genuine close-then-reopen "does not create a spurious early exit" at the raw layer, but is
    "invisible in `exited_year`/`entered_year`/`exit_source`, even though the year-varying
    `operating`/`op_status_code` columns still show it correctly" — affects ~0.26% of ever-operating
    facilities. Read `operating`/`OP_STATUS_CODE` year-by-year, not just the spell-summary fields, if this
    matters.
  - **N10** — "`prog_*_active` can read a confident-looking `0` with zero supporting record" — 2.18% of
    present facility-years have zero `PROGRAMS` rows at all, so every `PROG_*_ACTIVE` group reads `0` with
    nothing backing it, "indistinguishable, from the column alone, from a facility genuinely enrolled in
    nothing."
  - **W7a** — a 2018-adjacent gap in `ENTERED_YEAR`/`EXITED_YEAR`/`EXIT_SOURCE` "should be read as 'confirmed
    non-operating by the next real observation,' not as a precise closure date" — affects ~1.8% of facilities
    with real status on both sides of 2018.
  - **W8** — `PROG_*_ACTIVE` "is `NA`, not a confident `0`, wherever the facility's own status that year is
    blank or `CLS` (Permanently Closed)."
- Verified by reading the full script (`code/03_datasets/02_operating.R`, 327 lines) and sampling both
  `data/datasets/operating.csv.gz` and `data/datasets/wayback_only_facilities.csv.gz` directly (`gzcat ... |
  head` / `awk`-filtered rows). O1–O8 quotes pulled verbatim from `dataset_construction_decisions.md` Part
  C; N9/N10/W7a/W8 pulled verbatim from `code/02_cleaning/wayback/README.md` — not independently re-derived
  this pass.
