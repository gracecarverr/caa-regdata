# data/processed — cleaned assets (one per raw source)

Bare-bones "clean" assets built by [`code/02_cleaning`](../../code/02_cleaning/README.md). **Every original
column and row is kept**; the only additions are `date`/`year`/`dup`/`dup_exact` (event tables) or `dup_exact`
(attribute tables). Files are gzip-compressed CSV, **gitignored**, rebuilt from `data/raw/` by code.

- **Field definitions** for the original columns: [`docs/data_dictionary.md`](../../docs/data_dictionary.md)
  (transcribed from EPA's published dictionaries).
- **Added columns** (`date`, `year`, `dup`, `dup_exact`): defined in
  [`code/02_cleaning/README.md`](../../code/02_cleaning/README.md).
- **Why duplicates are flagged not dropped, date rules, etc.:**
  [`briefs/panel_construction_decisions.md`](../../briefs/panel_construction_decisions.md) (decision codes in
  the caveats below).

> Row/column counts below are from the logged rebuild. Regenerate with `Rscript code/02_cleaning/02_clean.R`
> (counts print per asset). `dup==0` gives the event-level (deduplicated) view; `dup_exact==0` drops only
> byte-identical repeats.

## ICIS-Air event tables (added: `date`, `year`, `dup`, `dup_exact`)

| asset | source CSV | rows | cols | `date` from |
|-------|-----------|------|------|-------------|
| `inspections` | `ICIS-AIR_FCES_PCES.csv` | 1,802,044 | 14 | `ACTUAL_END_DATE` (evaluation end) |
| `violations` | `ICIS-AIR_VIOLATION_HISTORY.csv` | 101,147 | 20 | `EARLIEST_FRV_DETERM_DATE`, else `HPV_DAYZERO_DATE` |
| `formal_actions` | `ICIS-AIR_FORMAL_ACTIONS.csv` | 105,656 | 14 | `SETTLEMENT_ENTERED_DATE` |
| `informal_actions` | `ICIS-AIR_INFORMAL_ACTIONS.csv` | 336,410 | 14 | `ACHIEVED_DATE` |
| `certs` | `ICIS-AIR_TITLEV_CERTS.csv` | 2,563,435 | 11 | `ACTUAL_END_DATE` |
| `stacktests` | `ICIS-AIR_STACK_TESTS.csv` | 646,332 | 14 | `ACTUAL_END_DATE` |

**Institutional implications**
- **`violations`** — ~9% of rows are undated (both determination dates blank) and get `year = NA`; they drop
  out at panel build (CC4/V1). `hpv` status = has an `HPV_DAYZERO_DATE`. Early-year sparsity is a reporting
  ramp-up artifact, **not** a real decline (V5) — don't read a downward trend into it.
- **`certs`** — **~81% duplicate rows** (one raw row per program/pollutant). `dup==0` → ~481k certifications;
  all rows → 2.53M. Use `n_certs` (dup==0), not raw rows, as the certification count (T1). Only ~62%/yr of
  "Major" facilities file a cert — class-Major ≠ Title V certifier (T3/F4).
- **`formal_actions` / `informal_actions`** — pooled into "enforcement" in the panel. **Only formal carry
  penalties.** A settlement can span multiple co-defendant facilities and **repeats one penalty across each**,
  so penalties are summed over `dup==0` only (E4/F2). Informal ≈ 48% duplicate rows; formal ≈ 1%.
- **`inspections` / `stacktests`** — ~0% duplication; the `dup` flag is a no-op kept for schema consistency.

## ICIS-Air attribute / lookup tables (added: `dup_exact` only)

| asset | source CSV | rows | cols |
|-------|-----------|------|------|
| `facilities` | `ICIS-AIR_FACILITIES.csv` | 279,211 | 20 |
| `pollutants` | `ICIS-AIR_POLLUTANTS.csv` | 976,479 | 8 |
| `programs` | `ICIS-AIR_PROGRAMS.csv` | 456,601 | 8 |
| `program_subparts` | `ICIS-AIR_PROGRAM_SUBPARTS.csv` | 190,570 | 6 |

**Institutional implications**
- **`facilities`** is the *current snapshot* (class, industry, operating status are time-invariant here); the
  derived spine (`data/panels/spine.csv.gz`) selects the ever-active universe and adds coordinates/profiles.
  Year-varying operating status is reconstructed separately from the Wayback tables (F2).
- **`programs`** has a `BEGIN_DATE` but **no end date**, so program enrollment can't be dated to when it
  started/ended from this table alone (drives the "ever-enrolled, static" `prog_*` flags — F6/N7).

## AFS — legacy Air Facility System (added: `dup_exact` only)

| asset | source CSV | rows | cols |
|-------|-----------|------|------|
| `afs_actions` | `AFS_ACTIONS.csv` | 2,579,661 | 17 |
| `afs_air_program` | `AIR_PROGRAM.csv` | 1,139,429 | 12 |
| `afs_facilities` | `AFS_FACILITIES.csv` | 236,734 | 22 |
| `afs_hist_compliance` | `AFS_AIR_PRG_HIST_COMPLIANCE.csv` | 10,204,801 | 5 |
| `afs_hpv` | `AFS_HPV_HISTORY.csv` | 32,057 | 8 |

**Institutional implication** — AFS is the **pre-2001 predecessor** to ICIS-Air with its own identifiers; it
covers the earlier historical period. Don't assume AFS ids align with ICIS-Air `PGM_SYS_ID` without an
explicit crosswalk.

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
| `wayback_program_status` | facility × year (2015–2025) | 8 `prog_*_active` flags from snapshot presence (status ≠ CLS) |

**Institutional implications** (load-bearing — see W1–W6, F7, N8–N11)
- **2015–2025 only**; pre-2015 is not back-filled. Window edges are **left/right-censored**.
- **Snapshot presence is the truth**, not the unreliable `BEGIN_DATE`.
- **`dropout` exits** (last seen operating, then vanished) are kept distinct from confirmed `cls` closures —
  a disappearance can be an ICIS extract artifact. `dropout` is an *upper bound* on unexplained exits (N8).
- `prog_*_active` uses a *blacklist* (active unless CLS) while facility `operating` uses a *whitelist*
  (OPR/TMP/SEA) — they answer different questions and won't always agree (N11).
