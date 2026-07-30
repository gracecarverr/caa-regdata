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

Two panels, `major_synmin_2015_2025` and `electric_2015_2025`, built from
`data/datasets/{regulatory,operating,hpv_active,coordinates}.csv.gz` — not from `data/processed/` directly.
See `code/04_panel_building/README.md` for the file-by-file build order.

> **2026-07-29: panels renamed, `PB2` revised.** Both panels were originally named `*_continuous_2015_2025`
> and required `ACTIVE_BROAD == 1` in every year 2015–2025. That continuity screen is retired (see the
> revised `PB2` below) in favor of an "active in at least one year" rule, and the panels are renamed to
> `major_synmin_2015_2025`/`electric_2015_2025` since "continuous" is no longer accurate. Every other
> decision below (`PB1`, `PB3`–`PB8`) is unchanged in substance; only the panel names in their prose have
> been updated to match.

## Decisions

| # | Decision | Alternative not taken | Why |
|---|---|---|---|
| **PB1** | **Two panels only, not a funnel.** No `universe`/non-continuous `major_synmin`/`electric`, no persisted `spine.csv.gz`. | Rebuild the old three-level funnel (`universe → major_synmin → electric`) plus continuous variants, matching the archived system's shape. | Explicit project decision, 2026-07-28: only these two panels are actually needed going forward. A broader sample-panel framework can be added back later if a real use case appears — it isn't scope-frozen, just not built speculatively. |
| **PB2** | **REVISED 2026-07-29 (explicit user decision): eligibility = `ACTIVE_BROAD == 1` in *at least one* year 2015–2025** — `any(ACTIVE_BROAD == 1, na.rm = TRUE)`. `ACTIVE_BROAD` (`data/datasets/operating.csv.gz`, decision `O6`) unions Wayback-confirmed operating status, ICIS events, and emissions/GHG reporting — each for that specific year. **Original rule (2026-07-28, superseded):** continuity = `ACTIVE_BROAD == 1` in *every* year 2015–2025, `all(ACTIVE_BROAD == 1)` — one gap or confirmed-inactive year anywhere failed the whole facility. | *(Original alternatives, still not taken):* keep the old event-only continuity rule; or use `ACTIVE` (the narrower wayback∪ICIS tier) instead of `ACTIVE_BROAD`. *(2026-07-29 alternative not taken:)* keep the all-11-years continuity requirement. | **Why revised:** the all-11-years rule requires full-window continuity, which drops exactly the facilities most likely to exit *because of* enforcement/penalty outcomes — survivorship bias in a panel meant to study enforcement and compliance. Two-way fixed-effects estimators don't need a balanced panel, so there was no mechanical reason to require one. *(Original 2026-07-28 rationale, still applies to the choice of `ACTIVE_BROAD` over `ACTIVE`/event-only:)* the old archived rule only credited a facility-year via a *recorded regulatory event* — the same undercount problem documented for `O6`'s universe-definition motivation. **Consequence of the revision:** unlike the original rule, a facility can now have real within-window gaps — `OBS_SOURCE == "unobserved"` is no longer impossible in these panels (see `PB4`'s update). |
| **PB3** | **Window = 2015–2025 only**, not the repo-wide 2005–2025. | Ship the full 21-year window with pre-2015 rows `NA`-padded. | The eligibility screen is only defined over 2015–2025 (Wayback's real coverage window) — both panels are already restricted to facilities that pass it, so a decade of pre-2015 rows would add nothing but padding. |
| **PB4** | **`OBS_SOURCE` derives from `ACTIVE_BROAD` + the facility-year's own `ICIS_OBSERVED`**, not a bespoke wayback join. **REVISED 2026-07-30: now a four-way split, not three.** `event` = `ICIS_OBSERVED==1`; `operating` = `!event & ACTIVE_BROAD==1`; `confirmed_inactive` = `!event & ACTIVE_BROAD==0` (**NEW**); `unobserved` = `!event & ACTIVE_BROAD` is `NA` (now the residual, not the catch-all). **UPDATED 2026-07-29 (PB2 revision):** `unobserved`-type rows now genuinely appear in both panels — under the old all-11-years continuity screen they were impossible by construction (every row had already passed `ACTIVE_BROAD==1` for that year); under the new ≥1-year rule, a facility can be eligible via one qualifying year while other years in its 11-year rectangle have `ACTIVE_BROAD` false/`NA`. | Reimplement the archived pipeline's `code_known_zeros()` wayback-join logic (original alternative, still not taken). **2026-07-30 alternative not taken:** leave the two-outcome fill as-is and just document that `unobserved` is a mixed bag. | *(Original rationale, now superseded for the fill's outcome-count but not its logic — see below):* Faithful reproduction of the archived semantics (that pipeline also treated a wayback status of `NA` and `0` identically — neither triggered its zero-fill) — `ACTIVE_BROAD`'s own 0-vs-NA distinction already encodes the same two-outcome decision, so there's nothing left to rederive. Verified: `ICIS_OBSERVED==1` always implies `ACTIVE_BROAD==1` (an invariant asserted when `ACTIVE_BROAD` was built), so `case_when()` checking `event` first is exhaustive and mutually exclusive by construction. **Why revised 2026-07-30:** investigating why `unobserved` ran 12–49% of facility-years surfaced that the *original* `case_when()` here — despite the paragraph above — only tested `ACTIVE_BROAD == 1`, so it silently let `ACTIVE_BROAD`'s own already-correct 0-vs-`NA` split collapse back into one `unobserved` catch-all, contradicting the stated design. Checked directly: 33% of major_synmin's `unobserved` facility-years (30,612 of 92,013) had `ACTIVE_BROAD == 0` — Wayback (or emissions/GHG) positively confirmed the facility was NOT active that year, a real, known outcome, not missing data. Electric showed the same pattern (1,984 of 3,842, 52%). Fixed by adding the explicit `ACTIVE_BROAD == 0` branch and extending the known-operating-zero fill to cover it too (a confirmed-inactive facility-year with no ICIS event is just as much a true zero as a confirmed-active one). This does not touch `data/datasets/operating.csv.gz` (`O6`) at all — that dataset's `ACTIVE_BROAD` was already correct; only the panel layer's use of it changed. |
| **PB5** | **`PROG_GACT`/`PROG_CFC` don't exist in this panel** — inherited for free, since `regulatory.csv.gz`/`operating.csv.gz` never carry them (`R6`/`O3`), not something this pipeline has to drop itself. | — | Consistency with the datasets layer's own scope decision; nothing panel-specific here. |
| **PB6** | **`N_PROGRAMS` stays `NA`-able**, not coalesced to `0` for a facility with no program record. | Coalesce to `0` (the archived spine's behavior). | Adopts `regulatory.csv.gz`'s convention (`R7`) directly, since `N_PROGRAMS` is read straight from there — no separate panel-level override. |
| **PB7** | **No `HPV_ACTIVE_1MO`.** Only the binary `HPV_ACTIVE`, read straight from `hpv_active.csv.gz`. | Recompute the >30-day interval variant independently in this pipeline (a third implementation of the same interval-overlap logic, after the archived panel-layer one and a considered-but-declined dataset-layer one). | Explicit project decision. `hpv_active.csv.gz` never shipped this variant; adding a third copy of the same logic was ruled out as unnecessary duplication. |
| **PB8** | **Every read specifies column types explicitly — no `col_guess()` anywhere in this pipeline.** | Let `readr` guess types (the initial draft of this pipeline did, briefly). | Caught during testing (2026-07-28): `col_guess()` on `regulatory.csv.gz`'s `PENALTY_AMOUNT`/`PENALTY_AMOUNT_DUP` (NA in ~99.6% of rows) and `operating.csv.gz`'s `EXITED_YEAR`/`EXIT_SOURCE` (NA for facilities that never exited) sampled all-`NA` rows and typed all four columns `col_logical()` — silently discarding every real value later in the file as an unparseable "logical," with **no error and no `problems()` entry** (a readr/vroom quirk: the misleading "parsing issues" warning that DID fire pointed at the wrong signal — `problems()` on the returned tibble reported zero rows even though real data was being dropped). Fixed by typing every selected column explicitly in `code/04_panel_building/00_spine.R` and `03_build_functions.R`; re-verified post-fix that `PENALTY_AMOUNT` carries real dollar figures (9,437 non-`NA` rows, $1.16B summed) and `EXITED_YEAR`/`EXIT_SOURCE` carry real values (1,045 non-`NA` exits) in the rebuilt panels. |
| **PB9** | **NEW 2026-07-30: `OPERATING_IMPUTED` passthrough.** Straight passthrough of `operating.csv.gz`'s new column (dataset-layer `O2` exception — 2018's `OPERATING` bridge-imputed where a facility has matching real 2017 and 2019 observations). No `code_obs_source()`/`OBS_SOURCE` logic change here — an imputed row already flows through `ACTIVE_BROAD` exactly like a real one; this column exists only so a user can filter imputed 2018 rows out. **Effect on this panel's 2018 coverage:** 2018 stops being an outlier year — see `panel_profile.md` §2 for the before/after table. | Fold "was this imputed" into `OBS_SOURCE` as a 5th/6th category. | Kept orthogonal by design: `OBS_SOURCE` answers "why do we trust this facility-year's ICIS-sourced counts," `OPERATING_IMPUTED` answers "was the underlying operating evidence itself observed or bridged" — different questions, no need to multiply `OBS_SOURCE`'s categories to answer both. Full derivation, and what was verified unaffected (panel eligibility here, `PB2`; entry/exit spells) before adding it, in `O2`. |

## Shape (as of the 2026-07-29 Q4 re-pin rebuild)

```
major_synmin_2015_2025: 504,592 rows | 114 cols | 45,872 facilities
electric_2015_2025:      32,615 rows | 114 cols |  2,965 facilities
candidate set (CONUS + major/synmin class, pre-eligibility): 55,777 facilities, 82.2% ever active
```

> **2026-07-29:** figures refreshed against the rebuild following the Wayback capture re-pin
> (`briefs/datasets/dataset_construction_decisions.md` `O8` — only 2024's snapshot moved, from Sep 26 to a
> genuine Q4 capture, Dec 10; the other 9 pinned years are unchanged since the Archive has no Q4 capture for
> most of them). Effect here is a single facility (major_synmin: 45,873 → 45,872) — consistent with the
> upstream shift being small (`O8`'s ~0.005-0.02% facility-year deltas), not a design change. `OP_STATUS_
> CURRENT_DESC`/`LEFT_CENSORED`/`RIGHT_CENSORED` were dropped from the panel build earlier the same day
> (explicit user decisions — see `docs/data_dictionary_derived.md` Part 2); the 113-column count is
> unaffected by the Wayback re-pin and unchanged from that prior revision.

> **2026-07-30:** column count moved 113 → **114** (`PB9`, `OPERATING_IMPUTED` passthrough) — the only column
> added; row/facility counts are unchanged (proven before building: a facility's 2017/2019 real observations
> already independently qualify it for eligibility, so the 2018 bridge can never be the deciding year, `O2`).

Both panels remain a full 11-year rectangle per facility (`balanced == TRUE` in `overview.csv`) —
`EVER_ACTIVE` is evaluated once over each facility's whole 2015–2025 record, not per year, so
`build_panel()`'s `expand_grid` still gives every eligible facility one row per year regardless of which
year(s) made it eligible. What changed under the `PB2` revision is that `OBS_SOURCE == "unobserved"` is now
real and substantial rather than impossible — see `PB4`.

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
