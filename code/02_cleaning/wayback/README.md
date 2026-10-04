# 02_cleaning/wayback — reconstructed operating-status history

These three cleaners are **bespoke** (not driven by `CLEAN_SPECS`) because they do something the regular
cleaners never do: they reconstruct a **facility × year time series** from 11 annual snapshots of the
ICIS-Air download, staged under `data/raw/ICIS_AIR_WAYBACK/ICIS-AIR_downloads_{2015..2025}/`.

**Not every snapshot is actually Q4.** The pipeline targets a Q4 (Oct-Dec) capture per year so each snapshot
reads as "the ~year-end state of year Y," but a full CDX-API audit of the Wayback Machine's capture history
(2026-07-29, `code/diagnostics/wayback_verify/wayback_q4_repin.R`) found the Archive never crawled this URL
in Q4 of **2015, 2017, 2019, 2023, or 2025** — 2019 and 2023 have exactly one 200-status capture in their
*entire* calendar year, so there is no alternative to try. Those years are pinned to the best (often only)
capture available: 2015-09-27, 2017-05-14, 2019-05-25, 2023-06-01, 2025-09-14. Only **2016, 2020, 2021,
2022, and 2024** are true Q4 captures. Treat "the ~Q4 state of that year" below as the *intent*, not a
guarantee that holds for every year — see `output/wayback_verify/q4_repin_summary.csv` for the full per-year
finding and `code/01_data_download/01_download.R`'s header for the pin rationale.

They run in order (18 depends on 17's output) after the regular cleaners, driven by `../02_clean.R`.

## Why these exist

The **current** ICIS-Air download carries only a single snapshot of operating status and has **no reliable
facility entry/exit dates** and **no program-close date** (`BEGIN_DATE` is unreliable). To build a panel you
need to know *when* a facility (and its programs) were actually in service. These scripts recover that from
snapshot **presence** and observed status transitions across the 11 Wayback captures. One snapshot = one panel
year (it reflects the ~Q4 state of that year).

Consumed downstream by the facility-spine/panel-building code at `code/04_panel_building/` — see
`briefs/panel/panel_construction_decisions.md` for the current rationale, and
`archive/panel_building_legacy/briefs/panel/panel_open_questions.md` for the (archived) open questions this
layer originally shipped with.

## The three scripts

| script | output | what it builds |
|--------|--------|----------------|
| `17_wayback_facility_status.R` | `wayback_facility_status.csv.gz` | facility × year operating status. `operating = 1` iff status ∈ {OPR, TMP, SEA} (Operating / Temporarily-closed / Seasonal all count as "in service"). Interior snapshot gaps are LOCF-filled within each facility's observed span `[first_snap, last_snap]`; edges are **not** extrapolated. |
| `18_wayback_facility_spells.R` | `wayback_facility_spells.csv.gz` | one row per facility: reconstructed `entered_year` / `exited_year` with `exit_source` ∈ {`cls`, `other`, `dropout`} and `left_censored` / `right_censored` flags. Depends on 17's output. |
| `19_wayback_program_status.R` | `wayback_program_status.csv.gz` | facility × year "is program group active?" flags for the 10 groups in the spine (`prog_{sip,titlev,nsps,mact,gact,neshap,fesop,nsr,psd,cfc}_active`), from snapshot presence + a program-specific active rule: operating groups are active for status ∈ {OPR,TMP,SEA}; the preconstruction groups NSR/PSD are additionally active for {PLN,CNS}. `BEGIN_DATE` is deliberately ignored. |

## Load-bearing conventions (do not change without re-verifying the panel)

- **"In service" = {OPR, TMP, SEA}.** Temporarily-closed and Seasonal are treated as operating.
- **Snapshot presence is the truth**, not the source begin/close dates.
- **LOCF fills interior gaps only.** A facility absent from a *middle* snapshot inherits its last observed
  status; leading/trailing edges are left `NA` and handled downstream.
- **`dropout` exits are kept distinct** from confirmed closures (`cls`): a facility last seen operating then
  vanishing might be a real closure *or* an ICIS extract artifact — the panel layer decides.
- **Close-then-reopen** does not create a spurious early exit: `exited_year` is defined off the *last*
  operating year.
- **2018 has no real snapshot** (the raw folder was a mislabeled duplicate of 2019 and was removed from
  `data/raw/`, 2026-07-21). It is asserted explicit `NA` in `op_status_code`/`op_status_desc`/`operating`
  and all `prog_*_active` columns for that year — **not** LOCF-filled like an ordinary interior gap, since
  there is no real observation for *any* facility to infer from. See W7 in
  `archive/panel_building_legacy/briefs/panel/panel_construction_decisions.md`.

The program-group code → group mapping in `19_...R` (`GROUPS`) must stay aligned with the `prog_*` flags
built downstream in `code/04_panel_building/00_spine.R`.

## Known nuances and traps

This code hasn't changed since the archived panel-building doc profiled it, so these findings are still
true — migrated here (with attribution) rather than left stranded in a folder labeled "legacy," since they
describe this stage's own current output, not the retired spine/panel logic that doc otherwise covers.

- **`dropout` exits can't be corroborated by regulatory events, so treat them with more caution than `cls`**
  (N8). This is a **raw-layer** finding — it's about `data/processed/wayback_facility_spells.csv.gz`
  (this stage's own output, all **11,801** `dropout`-classified facilities), not `data/datasets/operating.csv.gz`
  (dataset 1), which barely sees this population at all: dataset 1 is restricted to the current ICIS-Air
  facility universe (`O1`), and **11,799 of the 11,801** `dropout` facilities aren't in that universe — Wayback
  saw them operating at some point, but the current ICIS extract has no record of them existing. Only **2**
  `dropout` exits survive in `operating.csv.gz` itself; the other 11,799 are covered instead by the
  supplementary `data/datasets/wayback_only_facilities.csv.gz` (dataset 1b, `O7`), built specifically because
  dataset 1's universe restriction couldn't carry them. Of observed exits at the raw layer, `cls` (confirmed
  Permanently-Closed status) is trustworthy. `dropout` (last seen operating, then vanished from the snapshots)
  might be a real closure or an ICIS extract artifact — and the obvious check, "does the facility generate any
  regulatory activity after its vanish year," is a dead end: as last measured, only **1 of 11,801** `dropout`
  facilities appeared in *any* of the six ICIS event tables afterward. This is structural, not a sign the check
  failed — facilities with regulatory activity tend to stay in the ICIS extract, so the ones that vanish are
  disproportionately the ones with none. Read `dropout` as an upper bound on unexplained exits, not a
  confirmed one.
- **A genuine close-then-reopen is invisible in `exited_year`/`entered_year`/`exit_source`, even though the
  year-varying `operating`/`op_status_code` columns still show it correctly** (N9). `18_`'s one-row-per-facility
  spell summary defines `entered_year` off the *first* operating year and `exited_year`/`exit_source` off the
  *last* (deliberately — this is what makes it robust to reopening in the first place, see the bullet above),
  but that same choice means an interior closure between them gets silently absorbed into one continuous-looking
  spell. As last measured, **583 of ~220,579 ever-operating facilities (0.26%)** have ≥1 genuine non-operating
  year strictly inside their span. Only the collapsed spell-summary fields lose this; a downstream consumer
  reading the year-by-year `operating` column directly (not just the spell summary) sees the true
  operating→closed→operating sequence.
- **`prog_*_active` can read a confident-looking `0` with zero supporting record** (N10). A facility present
  in a year's snapshot but carrying no active row for program group X is coded `0` for that group — correct
  when the facility genuinely has other `PROGRAMS` rows that just don't include X, but as last measured
  **2.18%** of present facility-years have **zero** `PROGRAMS` rows at all, so *every* `prog_*_active` group
  reads `0` for them with nothing backing any of the ten flags — indistinguishable, from the column alone,
  from a facility genuinely enrolled in nothing.
- **A 2018-adjacent gap in `entered_year`/`exited_year`/`exit_source` should be read as "confirmed non-operating
  by the next real observation," not as a precise closure date** (W7a). E.g. a facility operating in 2017,
  with 2018's explicit `NA` gap (see above), then non-operating in 2019 gets `exited_year = 2019` — that means
  "still confirmed operating in 2017, confirmed non-operating by 2019, exact transition year unknown," not
  "closed in 2019." As last measured this pattern (operating→gap→non-operating) affects **~1.8%** of facilities
  with real status on both sides of 2018 — not a rare edge case. No code fix is needed for this — the
  exit-classification logic already only ever counts real observations — but the resulting `exited_year`
  shouldn't be read as more precise than the gap allows.
- **`prog_*_active` is `NA`, not a confident `0`, wherever the facility's own status that year is blank or
  `CLS` (Permanently Closed)** (W8). Every other real status code (including the rare `NER`/`NED`/`NES`/`LDF`)
  still gets a real `0`/`1` per the program-specific rule above. Blank-status facility-years have no status
  evidence at all that year, so asserting "not enrolled" for all ten groups would manufacture certainty that
  isn't there; `CLS` mirrors the same "closed years don't get confident zeros" reasoning used for the
  operating-based zero-fill elsewhere in this pipeline (a closed facility's program enrollment isn't
  confidently "none," it's simply not asserted).

*(Migrated 2026-07-30 from `archive/panel_building_legacy/briefs/panel/panel_construction_decisions.md`
N8/N9/N10/W7a/W8 — see that doc for the full original write-ups and exact verification detail.)*
