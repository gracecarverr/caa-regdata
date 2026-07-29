# Panel Construction Decisions

> **2026-07-28: this replaces a much longer document.** The original `panel_construction_decisions.md`
> (CC1–CC9, F1–F9, P1–P9, PR1–PR2, N1–N18 — the full facility-spine and three-sample-panel system built
> directly from `data/processed/`) is archived at
> `archive/panel_building_legacy/briefs/panel/panel_construction_decisions.md`, alongside the code and data
> it describes. Almost everything in that document was actually about the underlying **data** (HAP
> matching, coordinate/county cross-checks, wayback reconstruction, HPV interval rules, duplicate-load
> semantics) — all of that logic now lives once in `code/03_datasets/` and is documented in
> `briefs/datasets/dataset_construction_decisions.md`. This file covers only what's specific to the two
> panels `code/04_panel_building/` actually builds.

## Scope

Two panels, `major_synmin_continuous_2015_2025` and `electric_continuous_2015_2025`, built from
`data/datasets/{regulatory,operating,hpv_active,coordinates}.csv.gz` — not from `data/processed/` directly.
See `code/04_panel_building/README.md` for the file-by-file build order.

## Decisions

| # | Decision | Alternative not taken | Why |
|---|---|---|---|
| **PB1** | **Two panels only, not a funnel.** No `universe`/non-continuous `major_synmin`/`electric`, no persisted `spine.csv.gz`. | Rebuild the old three-level funnel (`universe → major_synmin → electric`) plus continuous variants, matching the archived system's shape. | Explicit project decision, 2026-07-28: only these two panels are actually needed going forward. A broader sample-panel framework can be added back later if a real use case appears — it isn't scope-frozen, just not built speculatively. |
| **PB2** | **Continuity = `ACTIVE_BROAD == 1` in every year 2015–2025**, replacing the archived system's "≥1 regulatory event in every year" rule. `ACTIVE_BROAD` (`data/datasets/operating.csv.gz`, decision `O6`) unions Wayback-confirmed operating status, ICIS events, and emissions/GHG reporting — each for that specific year. | Keep the old event-only continuity rule; or use `ACTIVE` (the narrower wayback∪ICIS tier) instead of `ACTIVE_BROAD`. | Explicit project decision, 2026-07-28 (`ACTIVE_BROAD`, not `ACTIVE`). The old rule only credited a facility-year via a *recorded regulatory event* — the same undercount problem documented for `O6`'s universe-definition motivation. No partial credit: a single year with `ACTIVE_BROAD == 0` (confirmed inactive) or `NA` (no evidence at all that year) fails the screen — `all(ACTIVE_BROAD == 1)` over the 11-year vector requires every element to be exactly `1`. |
| **PB3** | **Window = 2015–2025 only**, not the repo-wide 2005–2025. | Ship the full 21-year window with pre-2015 rows `NA`-padded. | The continuity screen is only defined over 2015–2025 (Wayback's real coverage window) — both panels are already restricted to facilities that pass it, so a decade of pre-2015 rows would add nothing but padding. |
| **PB4** | **`OBS_SOURCE` derives from `ACTIVE_BROAD` + the facility-year's own `ICIS_OBSERVED`**, not a bespoke wayback join. `event` = `ICIS_OBSERVED==1`; `operating` = `!event & ACTIVE_BROAD==1`; `unobserved` = neither. In practice `unobserved` never appears in either panel, since every row here already passed the `ACTIVE_BROAD` continuity screen. | Reimplement the archived pipeline's `code_known_zeros()` wayback-join logic. | Faithful reproduction of the archived semantics (that pipeline also treated a wayback status of `NA` and `0` identically — neither triggered its zero-fill) — `ACTIVE_BROAD`'s own 0-vs-NA distinction already encodes the same two-outcome decision, so there's nothing left to rederive. Verified: `ICIS_OBSERVED==1` always implies `ACTIVE_BROAD==1` (an invariant asserted when `ACTIVE_BROAD` was built), so `case_when()` checking `event` first is exhaustive and mutually exclusive by construction. |
| **PB5** | **`PROG_GACT`/`PROG_CFC` don't exist in this panel** — inherited for free, since `regulatory.csv.gz`/`operating.csv.gz` never carry them (`R6`/`O3`), not something this pipeline has to drop itself. | — | Consistency with the datasets layer's own scope decision; nothing panel-specific here. |
| **PB6** | **`N_PROGRAMS` stays `NA`-able**, not coalesced to `0` for a facility with no program record. | Coalesce to `0` (the archived spine's behavior). | Adopts `regulatory.csv.gz`'s convention (`R7`) directly, since `N_PROGRAMS` is read straight from there — no separate panel-level override. |
| **PB7** | **No `HPV_ACTIVE_1MO`.** Only the binary `HPV_ACTIVE`, read straight from `hpv_active.csv.gz`. | Recompute the >30-day interval variant independently in this pipeline (a third implementation of the same interval-overlap logic, after the archived panel-layer one and a considered-but-declined dataset-layer one). | Explicit project decision. `hpv_active.csv.gz` never shipped this variant; adding a third copy of the same logic was ruled out as unnecessary duplication. |
| **PB8** | **Every read specifies column types explicitly — no `col_guess()` anywhere in this pipeline.** | Let `readr` guess types (the initial draft of this pipeline did, briefly). | Caught during testing (2026-07-28): `col_guess()` on `regulatory.csv.gz`'s `PENALTY_AMOUNT`/`PENALTY_AMOUNT_DUP` (NA in ~99.6% of rows) and `operating.csv.gz`'s `EXITED_YEAR`/`EXIT_SOURCE` (NA for facilities that never exited) sampled all-`NA` rows and typed all four columns `col_logical()` — silently discarding every real value later in the file as an unparseable "logical," with **no error and no `problems()` entry** (a readr/vroom quirk: the misleading "parsing issues" warning that DID fire pointed at the wrong signal — `problems()` on the returned tibble reported zero rows even though real data was being dropped). Fixed by typing every selected column explicitly in `code/04_panel_building/00_spine.R` and `03_build_functions.R`; re-verified post-fix that `PENALTY_AMOUNT` carries real dollar figures (9,437 non-`NA` rows, $1.16B summed) and `EXITED_YEAR`/`EXIT_SOURCE` carry real values (1,045 non-`NA` exits) in the rebuilt panels. |

## Shape (as of the 2026-07-28 build)

```
major_synmin_continuous_2015_2025: 222,871 rows | 116 cols | 20,261 facilities
electric_continuous_2015_2025:      21,043 rows | 116 cols |  1,913 facilities
candidate set (CONUS + major/synmin class, pre-continuity): 55,777 facilities, 36.3% continuously active
```

Figures drift with each live ICIS-AIR/Wayback refresh.

**Profile**: `briefs/panel/panel_profile.md` (built by `code/diagnostics/18_panel_profile.R`) — coverage,
count-measure distributions, HPV-active rate, penalties, geography, coordinate coverage, entry/exit
censoring, and the electric-is-a-subset-of-major_synmin comparison.

## Where the rest of the "why" lives

For everything upstream of these two panels — universe definitions, zero-vs-NA discipline, the HAP/
coordinate/wayback/HPV construction logic, the `ACTIVE`/`ACTIVE_BROAD` tier design itself — see
`briefs/datasets/dataset_construction_decisions.md` (decisions `O1`–`O7` in particular). For the archived
predecessor system and why it was archived rather than converted in place, see
`archive/panel_building_legacy/README.md`. For a full characterization of the two panels themselves — not
just the decisions behind them — see `briefs/panel/panel_profile.md`.
