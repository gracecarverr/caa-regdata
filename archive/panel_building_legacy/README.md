# Archived: the original (`data/processed/`-based) panel-building pipeline

**Archived 2026-07-28.** This is the full original panel-building system, moved here in one piece
when the pipeline was inverted: panel-building now consumes `data/datasets/` (the nine-dataset
layer) instead of re-deriving facility-year aggregations directly from `data/processed/`. See
`code/04_panel_building/README.md` and `briefs/panel/panel_construction_decisions.md` for the
current system.

## Why archive instead of update in place

The underlying ICIS-AIR/Wayback/FRS sources are **live-refreshed**, not a one-time download — every
number in `briefs/panel/panel_construction_decisions.md` (as archived here) is dated and explicitly
caveated as drifting with the next live pull. That means re-running this archived code later
reproduces the old **logic** applied to whatever `data/processed/` looks like at that later time —
**not** today's old-panel **numbers**. To preserve both:

- **The code** (`code/03_panel_building/` below) — still runnable as-is against a `data/processed/`
  snapshot, for methodology reference or to regenerate an equivalent panel from fresher raw data.
- **A frozen data snapshot** (`data/panels/` below) — the exact `spine.csv.gz`, `universe.csv.gz`,
  `major_synmin.csv.gz`, and `electric.csv.gz` as they stood on **2026-07-28**, the day of the
  cutover. This is a deliberate, narrow exception to this project's usual rule that derived data is
  always rebuilt from code, never hand-preserved — justified here specifically because the source
  data moves and the code alone can't get back to this exact point in time.

## What's here

| path | what |
|---|---|
| `code/03_panel_building/` | The full original pipeline: `00_spine.R` (facility spine — universe, coordinates, county, static profiles, entry/exit spells, all computed directly from `data/processed/` + `data/raw/{frs,us_counties}`), `03_build_functions.R`/`03_build_parameters.R`/`03_build.R` (the shared `build_panel()` recipe + the three sample-panel specs), `coord_county_flag.R` and `hap_list_112b.R` (both since copied — not moved — to `code/03_datasets/`, which needs them going forward too). |
| `data/panels/` | Frozen 2026-07-28 snapshot: `spine.csv.gz`, `universe.csv.gz`, `major_synmin.csv.gz`, `electric.csv.gz`, and the README describing them. |
| `briefs/panel/` | `panel_construction_decisions.md` (the full decision log — CC1–CC9, F1–F9, per-asset decisions, P1–P9, PR1–PR2, N1–N18), `panel_findings_summary.md`, `panel_open_questions.md`. |
| `diagnostics/` | The panel-structure-specific diagnostics that analyzed the old universe → major_synmin → electric funnel and no longer apply to the 2-panel system that replaced it: `05_panel_summaries.R`, `06_panel_profile.R`, `06b_panel_deep_stats.R`, `07_majsyn_operating_profile.R`, `build_panels_page.R`, `coord_county_check/`. |

## What replaced this

`code/04_panel_building/` builds exactly two panels going forward —
`major_synmin_continuous_2015_2025.csv.gz` and `electric_continuous_2015_2025.csv.gz` — from
`data/datasets/` instead of `data/processed/`, with continuity (facilities active every year
2015–2025) defined by the datasets layer's `ACTIVE_BROAD` signal
(`briefs/datasets/dataset_construction_decisions.md`, decision `O6`) rather than this old system's
"≥1 regulatory event in every year" rule. See `briefs/panel/panel_construction_decisions.md` (the
new, short one — this archive's copy of the old file sits at
`briefs/panel/panel_construction_decisions.md` relative to *this* directory, i.e.
`archive/panel_building_legacy/briefs/panel/panel_construction_decisions.md`).
