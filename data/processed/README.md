# data/processed — cleaned assets (one per raw source)

Bare-bones "clean" assets built by [`code/02_cleaning`](../../code/02_cleaning/README.md). **Every original
column and row is kept**; the only additions are `date`/`year`/`dup`/`dup_exact` (event tables) or `dup_exact`
(attribute tables). Files are gzip-compressed CSV, **gitignored**, rebuilt from `data/raw/` by code.

- **Field definitions** for the original columns: [`docs/data_dictionary.md`](../../docs/data_dictionary.md)
  (transcribed from EPA's published dictionaries).
- **Added columns** (`date`, `year`, `dup`, `dup_exact`): defined in
  [`code/02_cleaning/README.md`](../../code/02_cleaning/README.md).
- **Why duplicates are flagged not dropped, date rules, etc.:** the decision codes cited in the caveats
  below (`CC*`/`F*`/`N*`/`W*`/`E*`/`V*`/`T*`) were made when this repo had a single panel-building layer;
  they're defined in
  [`archive/panel_building_legacy/briefs/panel/panel_construction_decisions.md`](../../archive/panel_building_legacy/briefs/panel/panel_construction_decisions.md),
  not the current short [`briefs/panel/panel_construction_decisions.md`](../../briefs/panel/panel_construction_decisions.md) (`PB1`–`PB8` only).

> Row/column counts below are from the logged rebuild. Regenerate with `Rscript code/02_cleaning/02_clean.R`
> (counts print per asset). `dup==0` gives the event-level (deduplicated) view; `dup_exact==0` drops only
> byte-identical repeats.

## ICIS-Air event tables (added: `date`, `year`, `dup`, `dup_exact`)

| asset | source CSV | rows | cols | `date` from |
|-------|-----------|------|------|-------------|
| `inspections` | `ICIS-AIR_FCES_PCES.csv` | 1,777,427 | 14 | `ACTUAL_END_DATE` (evaluation end) |
| `violations` | `ICIS-AIR_VIOLATION_HISTORY.csv` | 101,920 | 20 | `EARLIEST_FRV_DETERM_DATE`, else `HPV_DAYZERO_DATE` |
| `formal_actions` | `ICIS-AIR_FORMAL_ACTIONS.csv` | 105,946 | 14 | `SETTLEMENT_ENTERED_DATE` |
| `informal_actions` | `ICIS-AIR_INFORMAL_ACTIONS.csv` | 338,027 | 14 | `ACHIEVED_DATE` |
| `certs` | `ICIS-AIR_TITLEV_CERTS.csv` | 2,574,125 | 11 | `ACTUAL_END_DATE` |
| `stacktests` | `ICIS-AIR_STACK_TESTS.csv` | 619,735 | 14 | `ACTUAL_END_DATE` |

*Row counts as of 2026-07-27 (EPA's live ICIS-AIR bulk download refreshes without an archival checksum, so
these drift on re-download — see `archive/panel_building_legacy/briefs/panel/panel_construction_decisions.md`
W-series).*

**Institutional implications**
- **`violations`** — ~9% of rows are undated (both determination dates blank) and get `year = NA`; they drop
  out at panel build (CC4/V1). `hpv` status = has an `HPV_DAYZERO_DATE`. Early-year sparsity is a reporting
  ramp-up artifact, **not** a real decline (V5) — don't read a downward trend into it.
- **`certs`** — **~81% duplicate rows** (one raw row per program/pollutant). `dup==0` → ~489k certifications;
  all rows → 2.57M. Use `n_certs` (dup==0), not raw rows, as the certification count (T1). Only ~62%/yr of
  "Major" facilities file a cert — class-Major ≠ Title V certifier (T3/F4).
- **`formal_actions` / `informal_actions`** — pooled into "enforcement" in the panel. **Only formal carry
  penalties.** A settlement can span multiple co-defendant facilities and **repeats one penalty across each**
  — as of the 2026-07-28 fix, `attach_penalty()` sums penalties over **all** rows (not `dup==0` only) and
  reports the duplicate-dollar contribution separately, rather than silently dropping duplicate rows from the
  sum (see `archive/panel_building_legacy/briefs/panel/panel_construction_decisions.md` E4/F2 for the
  original rationale, and `briefs/datasets/dataset_construction_decisions.md` P5/`multi_facility_settlement_decision.md`
  for the current multi-facility-settlement handling). Informal ≈ 48% duplicate rows; formal ≈ 1%.
- **`inspections` / `stacktests`** — ~0% duplication; the `dup` flag is a no-op kept for schema consistency.

## ICIS-Air attribute / lookup tables (added: `dup_exact` only)

| asset | source CSV | rows | cols |
|-------|-----------|------|------|
| `facilities` | `ICIS-AIR_FACILITIES.csv` | 279,665 | 20 |
| `pollutants` | `ICIS-AIR_POLLUTANTS.csv` | 978,218 | 8 |
| `programs` | `ICIS-AIR_PROGRAMS.csv` | 457,333 | 8 |
| `program_subparts` | `ICIS-AIR_PROGRAM_SUBPARTS.csv` | 191,005 | 6 |

*Row counts as of 2026-07-27 (drifts with each live ICIS-AIR refresh, same caveat as above).*

**Institutional implications**
- **`facilities`** is the *current snapshot* (class, industry, operating status are time-invariant here);
  `data/datasets/coordinates.csv.gz` adds FRS coordinates + county placement over the full universe, and
  `code/04_panel_building/00_spine.R` applies the eligibility screen for the two panels in-memory (no
  persisted spine file — `PB1`, `briefs/panel/panel_construction_decisions.md`). Year-varying operating
  status is reconstructed separately from the Wayback tables (F2, and dataset 1, `operating`).
- **`programs`** carries `BEGIN_DATE` + `UPDATED_DATE` but **no end date**, so enrollment start is datable
  from `BEGIN_DATE` (surfaced as facility-level `program_begin_year` = earliest begin year, in the spine +
  panels) but the close is not (drives the "ever-enrolled, static" `prog_*` flags — see F6/N7 in
  `archive/panel_building_legacy/briefs/panel/panel_construction_decisions.md`).
- **`program_subparts`** has **no dates of its own**; a subpart inherits its program's `BEGIN_DATE` via a join
  on `(PGM_SYS_ID, PROGRAM_CODE)`.

## AFS — legacy Air Facility System (added: `dup_exact` only)

| asset | source CSV | rows | cols |
|-------|-----------|------|------|
| `afs_actions` | `AFS_ACTIONS.csv` | 2,579,661 | 17 |
| `afs_air_program` | `AIR_PROGRAM.csv` | 1,139,429 | 12 |
| `afs_facilities` | `AFS_FACILITIES.csv` | 236,734 | 22 |
| `afs_hist_compliance` | `AFS_AIR_PRG_HIST_COMPLIANCE.csv` | 10,204,801 | 5 |
| `afs_hpv` | `AFS_HPV_HISTORY.csv` | 32,057 | 8 |

**Institutional implication** — AFS is the legacy **Air Facility System**, frozen as of 2014 (superseded by
ICIS-Air), with its own identifiers; it covers the earlier historical period. Don't assume AFS ids align
with ICIS-Air `PGM_SYS_ID` without an explicit crosswalk.

## Emissions (added: `dup_exact` only)

| asset | source CSV | rows | cols |
|-------|-----------|------|------|
| `emissions` | `POLL_RPT_COMBINED_EMISSIONS.csv` | 10,411,871 | 10 |

`REPORTING_YEAR` is already present in the source, so no date parse is done.

## Wayback — reconstructed operating-status history (bespoke; see `code/02_cleaning/wayback/`)

| asset | grain | what |
|-------|-------|------|
| `wayback_facility_status` | facility × year (2015–2025) | operating status; `operating = 1` iff code ∈ {OPR,TMP,SEA}; interior gaps LOCF-filled |
| `wayback_facility_spells` | one row per facility | reconstructed `entered_year`/`exited_year`/`exit_source` + left/right censoring |
| `wayback_program_status` | facility × year (2015–2025) | 10 `prog_*_active` flags (`sip,titlev,nsps,mact,gact,neshap,fesop,nsr,psd,cfc`) from snapshot presence + a program-specific active rule (revised 2026-07-18 — see N11) |

**Institutional implications** (load-bearing — see W1–W6, F7, N8–N11 in
`archive/panel_building_legacy/briefs/panel/panel_construction_decisions.md`)
- **2015–2025 only**; pre-2015 is not back-filled. Window edges are **left/right-censored**.
- **Snapshot presence is the truth**, not the unreliable `BEGIN_DATE`.
- **`dropout` exits** (last seen operating, then vanished) are kept distinct from confirmed `cls` closures —
  a disappearance can be an ICIS extract artifact. `dropout` is an *upper bound* on unexplained exits (N8).
- `prog_*_active` uses a **program-specific** active rule, not a blanket blacklist/whitelist: the eight
  "operating" groups (`sip,titlev,nsps,mact,gact,neshap,fesop,cfc`) are active for status ∈ {OPR,TMP,SEA};
  the two preconstruction groups (`nsr,psd`) are additionally active for {PLN,CNS}. **Why this can disagree
  with facility-level `operating` (N11) — verified, not assumed:** the two are computed from **two different
  raw columns**. `operating` (`17_wayback_facility_status.R`) reads `AIR_OPERATING_STATUS_CODE` off
  `ICIS-AIR_FACILITIES.csv` — one row per facility. `prog_*_active` (`19_wayback_program_status.R`) reads the
  **same-named column on a different table**, `ICIS-AIR_PROGRAMS.csv` — one row per program enrollment, and
  ICIS lets that field carry its own value per enrollment, independently of the facility's own record. Direct
  comparison on the 2025 Wayback snapshot: **20,574 of 454,144 program rows (4.5%) disagree with their own
  facility's status the same year** (e.g. facility `OPR`, one of its program enrollments still `CLS`) — a real
  gap in how EPA keeps the two fields synchronized, not a data artifact either script introduces. **By design,
  each rule reports exactly what its own raw field says and neither is corrected against the other** — a
  closed program on an open facility is real information (e.g. that specific permit/program status ended)
  and should read that way, not get silently reconciled to match `operating`. Downstream, dataset 1
  (`data/datasets/operating.csv.gz`) carries only 8 of these 10 groups as `PROG_*_ACTIVE` flags (`gact`/`cfc`
  excluded to match an earlier schema — see decision `R6` in `briefs/datasets/dataset_construction_decisions.md`).
