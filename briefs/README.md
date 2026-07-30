# briefs — institutional & construction documentation

Narrative documentation for the project: the **institutional facts** behind the data (statute, agencies,
data systems) and the **decisions** made building the assets and panels, with their implications.

These briefs are the "why." For the "what" (column definitions, counts) see the matching section in
`data/processed/README.md` and `docs/data_dictionary.md`; for the "how" (code) see `code/*/README.md`.

## Contents

Split into subfolders mirroring the pipeline's own panel-layer (`code/04_panel_building/`) vs.
dataset-layer (`code/03_datasets/`) distinction, plus a `literature/` folder for external reference
material. `institutional_overview.md`, `database_overviews.md`, and this README stay at the top level
as the reference/index docs.

| brief | scope |
|-------|-------|
| [`institutional_overview.md`](institutional_overview.md) | **Start here.** The Clean Air Act enforcement setting: what each data system (ICIS-Air, AFS, FRS) is, the key regulatory concepts (Title V, HPV, FCE/PCE, NAAQS/attainment, program types), and — for each — the **implication for the data**. Its `## ` sections are split one-per-brief (Briefs 00–08) and rendered on the site's Briefs page by `code/diagnostics/build_briefs_page.R`; Home (`build_home.R`) just links there rather than embedding it. |
| [`database_overviews.md`](database_overviews.md) | What each database (ICIS-Air, AFS, the combined emissions dataset, the compliance/enforcement pipeline) contains, what's missing, and how the files join — transcribed verbatim from the project's Google Doc. Not rendered as its own page (superseded by the live Raw Data page); it's the source for `facility_identifiers.md` and `data_systems.md` below, and the datasets-layer detail is now covered by `datasets/datasets_overview.md` instead. |
| [`facility_identifiers.md`](facility_identifiers.md) | The several IDs one facility carries (`PGM_SYS_ID`, `AFS_ID`, `REGISTRY_ID`/FRS) and how they crosswalk — condensed from `database_overviews.md`, deliberately not restating `datasets/afs_crosswalk_feasibility.md`'s coverage numbers (linked instead). Rendered as Brief 09 on the site's Briefs page. |
| [`data_systems.md`](data_systems.md) | What ICIS-Air, AFS, the combined Emissions dataset, and the CAA Compliance Pipeline each are and cover — condensed from `database_overviews.md`. Rendered as Brief 10 on the site's Briefs page. |
| [`pollutant_classification.md`](pollutant_classification.md) | How pollutants are recorded as data (the `ICIS-AIR_POLLUTANTS.csv`/AFS `AIR_PROGRAM.csv` record shape, the facility-level-vs-pollutant-level scope of `AIR_POLLUTANT_CLASSIFICATION_CODE`, and which emissions program covers which pollutants) — cross-references rather than restates `institutional_overview.md`'s NAAQS/HAP/Facility Classification briefs. Rendered as Brief 11 on the site's Briefs page. |

### `literature/` — empirical literature reference

| brief | scope |
|-------|-------|
| [`literature/literature_matrix.md`](literature/literature_matrix.md) | Empirical CAA/stationary-source literature matrix (citation, setting, data source, identification, main finding) — transcribed verbatim from the project's Google Sheet. |

### `panel/` — the panel-building layer (`code/04_panel_building/`)

| brief | scope |
|-------|-------|
| [`panel/panel_construction_decisions.md`](panel/panel_construction_decisions.md) | Every construction decision (`PB1`–`PB8`) for the **current** two-continuous-panel layer — eligibility ("ever-active"), the dropped continuity screen, and their data issues. The predecessor spine/three-sample-panel system's decision codes (`CC*`/`F*`/`N*`/`W*`/`E*`/`V*`/`PR*`/`T*`) live only in [`../archive/panel_building_legacy/briefs/panel/panel_construction_decisions.md`](../archive/panel_building_legacy/briefs/panel/panel_construction_decisions.md). |
| [`panel/panel_profile.md`](panel/panel_profile.md) | Narrative profile of the two current panels — scale, coverage over time, entry/exit, HPV-active rates, penalty summary. Rendered as-is (plus live-computed summary-stat tables from `output/panel_profile/*.csv`) on the site's Panels page by `code/diagnostics/build_panels_page.R`. |
| [`../archive/panel_building_legacy/briefs/panel/panel_open_questions.md`](../archive/panel_building_legacy/briefs/panel/panel_open_questions.md) | **Archived.** Choices left unsettled in the old spine/three-panel layer — balance vs. unbalanced, operating-indicator / Census merge, violation date rule, the electric definition, covariates, and verification items. Not all still apply to the current two-panel layer. |
| [`../archive/panel_building_legacy/briefs/panel/panel_findings_summary.md`](../archive/panel_building_legacy/briefs/panel/panel_findings_summary.md) | **Archived.** The old layer's meeting-ready one-pager; superseded by `panel/panel_profile.md` above, which is what the site now renders. |

### `datasets/` — the nine-dataset layer (`code/03_datasets/`)

| brief | scope |
|-------|-------|
| [`datasets/dataset_construction_decisions.md`](datasets/dataset_construction_decisions.md) | Every dataset-construction decision (R/O/P/H-numbered) across all nine datasets, the alternative not taken, and the data issue behind it. |
| [`datasets/regulatory_dataset_profile.md`](datasets/regulatory_dataset_profile.md) | General profile writeup of dataset 0 (`regulatory.csv.gz`) — coverage, event-count distributions, facility characteristics. No open decision attached. |
| [`datasets/hpv_profile.md`](datasets/hpv_profile.md) | General profile writeup of datasets 2/2b (`hpv_spells.csv.gz` / `hpv_active.csv.gz`) — spell status/duration, program/agency composition, active-rate trend. No open decision attached. |
| [`datasets/coordinates_profile.md`](datasets/coordinates_profile.md) | General profile writeup of dataset 4 (`coordinates.csv.gz`) — coverage funnel, coordinate-vs-county agreement, facility geography, state-level coverage gaps. No open decision attached. |
| [`datasets/pipeline_profile.md`](datasets/pipeline_profile.md) | General profile writeup of dataset 6 (`pipeline.csv.gz`) — EPA ECHO's CAA Compliance Pipeline, evaluation-to-enforcement chain. No open decision attached. |
| [`datasets/emissions_profile.md`](datasets/emissions_profile.md) | General profile writeup of dataset 7 (`emissions.csv.gz`) — combined pollutant report coverage and magnitude distributions. No open decision attached. |
| [`datasets/begin_year_operating_proxy.md`](datasets/begin_year_operating_proxy.md) | **Open decision.** Whether `EARLIEST_PROGRAM_BEGIN_YEAR` (dataset 1) is usable as a pre-2015 facility-existence marker. |
| [`datasets/afs_crosswalk_feasibility.md`](datasets/afs_crosswalk_feasibility.md) | **Open decision.** Whether the AFS↔ICIS facility-id crosswalk is good enough to use AFS's pre-2015 historical compliance status (incl. an explicit shut-down code) as an operating-status signal — 74.5% coverage for the population that needs it, but with severe state-level variance. |
| [`datasets/multi_facility_settlement_decision.md`](datasets/multi_facility_settlement_decision.md) | **Open decision.** How to handle multi-facility settlement penalties in dataset 3 — naive summing overstates the total by 35.7%. |

## How institutional facts connect to the data

When an institutional fact has a concrete implication for how an asset should be read or used, that
implication is **also** recorded next to the affected data or code — in the matching section of
`data/processed/README.md` and/or the stage README under `code/`. The overview brief is the hub; the
per-file notes are the spokes. If you change an institutional fact here, grep for it in `data/` and `code/`.

