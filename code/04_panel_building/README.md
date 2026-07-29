# 04_panel_building — two continuous panels, built from `data/datasets/`

**Stage inputs:** `data/datasets/{regulatory,operating,hpv_active,coordinates}.csv.gz` (the datasets layer,
`code/03_datasets/` — must already be built; see `code/RUN_ALL.R`'s stage order).
**Stage outputs:** `data/panels/{major_synmin_continuous_2015_2025,electric_continuous_2015_2025}.csv.gz`
**Run:** as stage `04` of `code/RUN_ALL.R` (after stage `03 datasets`). Each script also runs standalone —
`Rscript code/04_panel_building/03_build.R` — assuming `data/datasets/` is already built.

This replaces a much larger pipeline that used to build a general-purpose facility spine plus three sample
panels (`universe`/`major_synmin`/`electric`) directly from `data/processed/` (the cleaning layer), computing
its own coordinate/county spatial join, HAP matching, wayback status attachment, and event aggregation —
duplicating logic that `code/03_datasets/` already implements once. That entire pipeline, its outputs as of
2026-07-28, and its docs are archived in full at `archive/panel_building_legacy/`; see that directory's
README for why it was archived rather than converted in place. **This pipeline ships only what's actually
needed going forward: two narrowly-scoped panels**, not a general sample-panel framework.

## The two panels

Both are the **same recipe** (`build_panel()`, `03_build_functions.R`) over a different facility filter, and
both share one precomputed candidate set (`00_spine.R`'s `spine`: CONUS + Major/Synthetic-Minor emissions
class). Grain is `PGM_SYS_ID × YEAR`, window **2015–2025 only** (not the repo-wide 2005–2025) — see below.

| panel | facility filter | 
|---|---|
| `major_synmin_continuous_2015_2025` | CONUS, Major/Synthetic-Minor class, **`ACTIVE_BROAD == 1` in every year 2015–2025** |
| `electric_continuous_2015_2025` | the above **+** NAICS 2211 or SIC 4911 |

**The continuity rule is new.** The archived pipeline's `_continuous_2015_2025` concept (documented as
`PR2` in the archived `panel_construction_decisions.md`) was never actually shipped as a built panel file —
it existed only as an ad hoc diagnostic count, defined as "≥1 regulatory event in every year." This pipeline
ships it for real, and redefines continuity using `ACTIVE_BROAD` (`data/datasets/operating.csv.gz`, decision
`O6` in `briefs/datasets/dataset_construction_decisions.md`) — a facility-year is only "active" if wayback
confirms it operating, OR ICIS recorded an event, OR emissions/GHG reporting covers it, **that specific
year**. A facility needs a positive signal in **all 11 years** to pass; one gap or confirmed-inactive year
anywhere in the span fails the screen, no partial credit and no imputation across it.

**Why 2015–2025, not 2005–2025:** the continuity screen is only meaningful over the span `ACTIVE_BROAD`
actually has data for at reasonable coverage (wayback itself starts in 2015), and both panels are already
restricted to facilities passing that exact screen — there's no analytical reason to carry a decade of
pre-2015 rows that would just be a redundant view of the same, already-known-continuous set.

## Build order & files

| file | builds | notes |
|------|--------|-------|
| `00_spine.R` | in-memory `spine` | CONUS + major/synmin class filter, facility attributes (`regulatory.csv.gz`), coordinates (`coordinates.csv.gz`), entry/exit spell + begin-year (`operating.csv.gz`), and the `CONTINUOUSLY_ACTIVE` flag (`operating.csv.gz`'s `ACTIVE_BROAD`, 2015–2025). Not written to disk — only these two panels consume it, in the same session. |
| `03_build_functions.R` | `build_panel()` | Reads counts (`regulatory.csv.gz`), wayback/activity signals (`operating.csv.gz`), and `HPV_ACTIVE` (`hpv_active.csv.gz`) for a facility set + window, joins them, computes `ANY_*` flags and `OBS_SOURCE` (the known-operating-zero fill — see its own header comment for the derivation). |
| `03_build_parameters.R` | `PANEL_SPECS` | `YEARS = 2015:2025`, the electric NAICS/SIC filter, and the two panel specs. |
| `03_build.R` | the 2 panels | Driver: spine → per-spec filter → `build_panel()` → write. |

## Conventions (inherited from the datasets layer, unchanged here)

- **`UPPER_SNAKE_CASE` columns**, matching `code/03_datasets/`'s convention (no separate uppercasing step
  needed here — every column is read directly off an already-uppercase dataset file).
- **`PROG_GACT`/`PROG_CFC` don't exist** — `regulatory.csv.gz`/`operating.csv.gz` never carried them to
  begin with (dataset-layer decisions `R6`/`O3`), so there's nothing to drop here.
- **`N_PROGRAMS` is `NA`-able**, never coalesced to `0` — same convention as `regulatory.csv.gz` (`R7`).
- **No `HPV_ACTIVE_1MO`** — `hpv_active.csv.gz` never shipped the >30-day variant; not recomputed here.
- **Zero-vs-NA discipline**, now derived from `ACTIVE_BROAD` + `ICIS_OBSERVED` (`OBS_SOURCE`) instead of a
  bespoke wayback join — see `03_build_functions.R`'s header comment.

## Where the "why" lives

This README explains *what/how*. For *why* — the continuity rule, the panel scope decision (2 panels, not a
funnel), the `OBS_SOURCE` derivation — see `briefs/panel/panel_construction_decisions.md`. For the archived
predecessor system, see `archive/panel_building_legacy/README.md`.
