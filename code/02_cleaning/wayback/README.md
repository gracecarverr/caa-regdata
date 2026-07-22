# 02_cleaning/wayback — reconstructed operating-status history

These three cleaners are **bespoke** (not driven by `CLEAN_SPECS`) because they do something the regular
cleaners never do: they reconstruct a **facility × year time series** from 11 annual snapshots of the
ICIS-Air download, captured ~Q4 each year 2015–2025 and staged under
`data/raw/ICIS_AIR_WAYBACK/ICIS-AIR_downloads_{2015..2025}/`.

They run in order (18 depends on 17's output) after the regular cleaners, driven by `../02_clean.R`.

## Why these exist

The **current** ICIS-Air download carries only a single snapshot of operating status and has **no reliable
facility entry/exit dates** and **no program-close date** (`BEGIN_DATE` is unreliable). To build a panel you
need to know *when* a facility (and its programs) were actually in service. These scripts recover that from
snapshot **presence** and observed status transitions across the 11 Wayback captures. One snapshot = one panel
year (it reflects the ~Q4 state of that year).

See `briefs/panel/panel_construction_decisions.md` and `briefs/panel/panel_open_questions.md` for the full rationale and
the known caveats these choices carry.

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
  `briefs/panel/panel_construction_decisions.md`.

The program-group code → group mapping in `19_...R` (`GROUPS`) must stay aligned with the `prog_*` flags built
in `code/03_panel_building/00_spine.R`.
