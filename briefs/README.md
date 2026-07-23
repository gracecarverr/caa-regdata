# briefs — institutional & construction documentation

Narrative documentation for the project: the **institutional facts** behind the data (statute, agencies,
data systems) and the **decisions** made building the assets and panels, with their implications.

These briefs are the "why." For the "what" (column definitions, counts) see `data/processed/*.README.md`
and `docs/data_dictionary.md`; for the "how" (code) see `code/*/README.md`.

## Contents

`institutional_overview.md`, `database_overviews.md`, and this README stay at the top level as the
reference/index docs. `datasets/` holds the construction decisions for `code/04_datasets/` — this repo's
main product.

| brief | scope |
|-------|-------|
| [`institutional_overview.md`](institutional_overview.md) | **Start here.** The Clean Air Act enforcement setting: what each data system (ICIS-Air, AFS, FRS, Green Book) is, the key regulatory concepts (Title V, HPV, FCE/PCE, NAAQS/attainment, program types), and — for each — the **implication for the data**. Links out to the in-depth briefs. Rendered (trimmed) as the site's Home page by `code/diagnostics/build_home.R`. |
| [`database_overviews.md`](database_overviews.md) | What each database (ICIS-Air, AFS, the combined emissions dataset, the compliance/enforcement pipeline) contains, what's missing, and how the files join — transcribed verbatim from the project's Google Doc. Rendered as the site's Databases page by `code/diagnostics/build_databases_page.R`. |

> The former `panel/` subfolder (`panel_construction_decisions.md`, `panel_open_questions.md`,
> `panel_findings_summary.md`) moved to the CAA_Project repo alongside the facility-spine/panel-building
> code (2026-07-23), along with its Panels site page.

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

