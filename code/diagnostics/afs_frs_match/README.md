# afs_frs_match — can AFS facility ids be linked to ICIS-Air ids?

## Question
Legacy AFS (`AFS_ID`) and current ICIS-Air (`PGM_SYS_ID`) share no facility identifier format — a direct
string join yields zero hits (`data/raw/README.md` already flags this). If AFS's
`AFS_AIR_PRG_HIST_COMPLIANCE.csv` (quarterly compliance status per facility-program, back to ~1998, including
an explicit `9 = "In Compliance, Shut Down"` code) is ever going to serve as a pre-2015 operating-status
signal — the gap identified in [`../../../archive/panel_building_legacy/briefs/panel/panel_open_questions.md`](../../../archive/panel_building_legacy/briefs/panel/panel_open_questions.md)
D-A2 and [`../../../briefs/datasets/begin_year_operating_proxy.md`](../../../briefs/datasets/begin_year_operating_proxy.md) —
the facilities have to be linkable first. **This diagnostic answers only the linkability question**, not
whether the compliance-status data itself is clean or usable once linked.

This is a **port**, not a fresh derivation. The method was originally worked out in the predecessor project
(`CAA_Project/data_docs/scripts/explore/10_frs-crosswalk.R`), which found the crosswalk technically works but
under-covers closed facilities. It was never brought into `caa-regdata`, and its key input
(`FRS_PROGRAM_LINKS.csv`) wasn't staged here. This diagnostic reproduces that result inside this repo (so the
number is traceable from here, not only a sibling project) and then asks the two questions the prior run
never did: does the crosswalk reach the facilities *this repo* would actually apply it to.

## Run

```sh
Rscript code/diagnostics/afs_frs_match/afs_icis_crosswalk.R
```

**Depends on `10_begin_year_proxy.R` having already run** — step 4 below reads
`output/begin_year_proxy/pre2015_single_year_facilities.csv`, so run `Rscript code/diagnostics/10_begin_year_proxy.R`
first if that file doesn't exist yet.

## Method (`afs_icis_crosswalk.R`)
Two hops, bridged through FRS:

1. **Hop 1** — `FRS_PROGRAM_LINKS.csv` tags every facility's id in every EPA program system
   (`PGM_SYS_ACRNM`). Air-program rows (`PGM_SYS_ACRNM == "AIR"`) whose `PGM_SYS_ID` is **18 characters**
   embed the legacy `AFS_ID` as their **last 10 characters** (state + zero-padding + AFS_ID). Verified against
   the rejected alternative (strip state prefix + leading zeros + re-pad): last-10 matches 59.3% of AIR rows
   to a real `AFS_ID`, strip-and-repad only 52.5% — last-10 is used, reproducing the original script's choice.
2. **Hop 2** — `REGISTRY_ID → ICIS-Air PGM_SYS_ID`, a direct join (`ICIS-AIR_FACILITIES.csv` already carries
   `REGISTRY_ID`).
3. Unmatched AFS records get a conservative exact-after-normalization name/address+state+zip5 candidate
   search against FRS — **written out as evidence only, never added to the crosswalk**. A shared name or
   address does not prove the same physical facility.
4. **Extension, not in the original script**: coverage recomputed restricted to (a) the current
   279,211-facility ICIS-Air spine (`data/processed/facilities.csv.gz`) and (b) within that, the
   171,324-facility pre-2015-begin-year population already identified in `output/begin_year_proxy/` — the
   actual population a pre-2015 proxy would be applied to.

Outputs → `output/afs_frs_match/`: `hop1_length_distribution.csv`, `hop1_extraction_method.csv`,
`crosswalk_coverage.csv`, `unmatched_by_status.csv`, `unmatched_by_state.csv`, `candidate_summary.csv`,
`spine_restricted_coverage.csv`, `pre2015_population_coverage.csv`.

## Finding (run 2026-07-26)

> Figures below use the 2026-07-26 ICIS-AIR spine (279,211 facilities). The live extract has since grown to
> 279,665 (as of 2026-07-27) — not re-run against the current spine; treat percentages as directionally
> current, not exact.

- **Baseline reproduces CAA_Project's prior run exactly**: 164,880 of 236,734 AFS facilities reach an ICIS id
  end-to-end (**69.6%**), 208 ambiguous (0.13%) — a byte-for-byte match on every number checked, including the
  full state-level breakdown. The port is correct.
- **The closed-facility skew reproduces too**: match rate 73.3% for AFS `OPERATING_STATUS = O` (operating)
  vs. **58.0% for `X` (closed)** — the crosswalk is worst exactly where a historical-status proxy needs it most.
- **⚠ New finding this run didn't have before: coverage is extremely state-heterogeneous, not a uniform
  ~70%.** Several large industrial states barely crosswalk at all — **IL 0.6%, OH 1.6%, SC 1.4%, NC 7.9%, MI
  5.0%, NY 11.3%** — while others are near-complete (CO/KS/VA/NE/OK ~100%, LA 97.8%, TX 99.7%). This isn't
  sampling noise (20,197 AFS facilities in IL alone) — it looks like some states' FRS AIR records simply never
  had the legacy AFS id populated. The national aggregate conceals this entirely.
- **Repo-specific extension — the numbers that actually matter for the use case**:
  - Of the current 279,211-facility ICIS spine, **59.7%** (166,585) trace back to an AFS record at all — lower
    than the 69.6% baseline, expected since a meaningful share of the current spine are post-2014 facilities
    with no AFS history to find.
  - Of the 171,324-facility pre-2015-begin-year population — the group `begin_year_operating_proxy.md` §1
    says actually needs a pre-2015 signal — **74.5%** (127,712) are reachable. Higher than either the raw
    baseline or the full-spine number, as expected (this population is selected for pre-2015 existence, which
    is exactly what AFS covers) — but still subject to the same state skew above, so this 74.5% is not evenly
    spread across states.
- **Candidate search**: of the 71,799 unmatched AFS facilities, 67.8% (48,698) have an exact
  name/address+state+zip5 candidate in FRS — close to CAA_Project's 71.2% (a 3-key vs. 2-key search
  difference here, not a data difference) — none accepted into the crosswalk.

Full writeup and read on what this means for the operating-status-proxy decision:
[`../../../briefs/datasets/afs_crosswalk_feasibility.md`](../../../briefs/datasets/afs_crosswalk_feasibility.md).
