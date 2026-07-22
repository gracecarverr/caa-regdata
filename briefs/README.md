# briefs — institutional & construction documentation

Narrative documentation for the project: the **institutional facts** behind the data (statute, agencies,
data systems) and the **decisions** made building the assets and panels, with their implications.

These briefs are the "why." For the "what" (column definitions, counts) see `data/processed/*.README.md`
and `docs/data_dictionary.md`; for the "how" (code) see `code/*/README.md`.

## Contents

Split into two subfolders mirroring the pipeline's own panel-layer (`code/03_panel_building/`) vs.
dataset-layer (`code/04_datasets/`) distinction. `institutional_overview.md`, `database_overviews.md`, and
this README stay at the top level as the reference/index docs.

| brief | scope |
|-------|-------|
| [`institutional_overview.md`](institutional_overview.md) | **Start here.** The Clean Air Act enforcement setting: what each data system (ICIS-Air, AFS, FRS, Green Book) is, the key regulatory concepts (Title V, HPV, FCE/PCE, NAAQS/attainment, program types), and — for each — the **implication for the data**. Links out to the in-depth briefs. Rendered (trimmed) as the site's Home page by `code/diagnostics/build_home.R`. |
| [`database_overviews.md`](database_overviews.md) | What each database (ICIS-Air, AFS, the combined emissions dataset, the compliance/enforcement pipeline) contains, what's missing, and how the files join — transcribed verbatim from the project's Google Doc. Rendered as the site's Databases page by `code/diagnostics/build_databases_page.R`. |

### `panel/` — the panel-building layer (`code/03_panel_building/`)

| brief | scope |
|-------|-------|
| [`panel/panel_construction_decisions.md`](panel/panel_construction_decisions.md) | Every asset- and panel-construction decision, the alternative not taken, and the data issue behind it (facility key, date rules, duplicate handling, universe definition, spine attributes, attainment, Wayback status, zero semantics, HPV intervals). |
| [`panel/panel_open_questions.md`](panel/panel_open_questions.md) | Choices **not yet settled** — balance vs. unbalanced, operating-indicator / Census merge, violation date rule, the electric definition, covariates, and verification items. |
| [`panel/panel_findings_summary.md`](panel/panel_findings_summary.md) | Meeting-ready one-pager of panel scale, key measures, duplicate load, and penalties. Rendered as-is on the site's Panels page by `code/diagnostics/build_panels_page.R`, alongside live-computed summary-stat tables. |

### `datasets/` — the six-dataset layer (`code/04_datasets/`)

| brief | scope |
|-------|-------|
| [`datasets/dataset_construction_decisions.md`](datasets/dataset_construction_decisions.md) | Every dataset-construction decision (R/O/P/H-numbered) across all six datasets, the alternative not taken, and the data issue behind it. |
| [`datasets/regulatory_dataset_profile.md`](datasets/regulatory_dataset_profile.md) | General profile writeup of dataset 0 (`regulatory.csv.gz`) — coverage, event-count distributions, facility characteristics. No open decision attached. |
| [`datasets/hpv_profile.md`](datasets/hpv_profile.md) | General profile writeup of datasets 2/2b (`hpv_spells.csv.gz` / `hpv_active.csv.gz`) — spell status/duration, program/agency composition, active-rate trend. No open decision attached. |
| [`datasets/coordinates_profile.md`](datasets/coordinates_profile.md) | General profile writeup of dataset 4 (`coordinates.csv.gz`) — coverage funnel, coordinate-vs-county agreement, facility geography, state-level coverage gaps. No open decision attached. |
| [`datasets/begin_year_operating_proxy.md`](datasets/begin_year_operating_proxy.md) | **Open decision.** Whether `EARLIEST_PROGRAM_BEGIN_YEAR` (dataset 1) is usable as a pre-2015 facility-existence marker. |
| [`datasets/multi_facility_settlement_decision.md`](datasets/multi_facility_settlement_decision.md) | **Open decision.** How to handle multi-facility settlement penalties in dataset 3 — naive summing overstates the total by 35.2%. |

## How institutional facts connect to the data

When an institutional fact has a concrete implication for how an asset should be read or used, that
implication is **also** recorded next to the affected data or code — in the relevant
`data/processed/<name>.README.md` and/or the stage README under `code/`. The overview brief is the hub; the
per-file notes are the spokes. If you change an institutional fact here, grep for it in `data/` and `code/`.

> **⚠ Cross-reference status.** `panel_construction_decisions.md` and `panel_open_questions.md` were written
> against an earlier code layout (a `build_panel()` function with `presets/`, an `assets/` folder, and a
> `00_setup.R`). The **decisions and data facts remain valid**, but some code paths/filenames they cite
> (e.g. `assets/facilities.R`, `presets/…`, `build_panel(years=)`) predate the current `code/` structure and
> the standalone panel scripts in `code/03_panel_building/04_panels/`. These are being reconciled during the
> line-by-line verification pass — treat a cited path as "the decision lives *somewhere* in the pipeline,"
> and confirm the exact location in the current `code/` tree.
