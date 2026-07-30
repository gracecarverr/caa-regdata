# diagnostics — characterization, previews, and one-off investigations

Code that is **not part of the build pipeline** (doesn't produce a `data/datasets/` or `data/panels/` asset)
but is valuable for understanding, checking, and characterizing the data. Most of this folder is run by hand
as needed — `code/RUN_ALL.R` does **not** source it. The exception is the four site-generation scripts
(`build_site.R`, `build_home.R`, `build_databases_page.R`, `build_panels_page.R`), which produce committed
`docs/` deliverables and so ARE run by `RUN_ALL.R` — see the table below and the note after it.

## What lives here

| script | what it does | inputs → outputs |
|--------|--------------|------------------|
| `08_hpv_spell_diagnostics.R` | Record-grain view of raw HPV violation records that informs how `hpv_spells` (dataset 2) should be constructed. Constructs no spells — flags the structure (missing start, open vs. resolved, bad-ordered/unparseable dates, dup rows, raw interval overlap) that the construction rules must resolve. | `data/processed/violations.csv.gz` → `output/hpv_spell_diagnostics/records.csv.gz` + console summary |
| `09_hpv_facility_year_rules.R` | Companion to `08` — compares four candidate spell→facility-year mapping rules (day-zero-year only, interval overlap, extended-open overlap, 30-day-union) by their effect on HPV-active coverage, to make the mapping choice (R2, used by `hpv_active`) by seeing it rather than assuming it. | `data/processed/violations.csv.gz` → `output/hpv_spell_diagnostics/facility_year_rules.csv.gz` + console comparison |
| `10_begin_year_proxy.R` | Evaluates whether `EARLIEST_PROGRAM_BEGIN_YEAR` (dataset 1) is a usable proxy for operating status pre-2015 (where wayback has no coverage), by comparing it against wayback `OPERATING` where both exist (2015–2025). Descriptive/statistical agreement only, not causal. | `data/datasets/operating.csv.gz` → `output/begin_year_proxy/{coverage,agreement,lag,post_exit_false_positive}.csv` + console summary |
| `11_operating_profile.R` | Exploratory profile of dataset 1: coverage, operating-status distribution, program-active prevalence, entry/exit spells, begin-year coverage. Every rate is computed on the observed subset with NA share reported (0 ≠ NA honored). | `data/datasets/operating.csv.gz` → `output/operating_profile/*.csv` + `output/figures/datasets/operating/*.png` |
| `12_penalties_profile.R` | Exploratory profile of dataset 3: penalty-amount distribution, action/enforcement-type composition, multi-facility settlement structure (descriptive only — the broadcast-rule decision itself lives in `briefs/datasets/multi_facility_settlement_decision.md`). | `data/datasets/penalties.csv.gz` → `output/penalties_profile/*.csv` + `output/figures/datasets/penalties/*.png` |
| `13_regulatory_profile.R` | Exploratory profile of dataset 0: coverage, event-count distributions, facility-characteristic breakdowns. `ICIS_OBSERVED` is the zero-vs-NA gate; every summary reports the NA share. | `data/datasets/regulatory.csv.gz` → `output/regulatory_profile/*.csv` + `output/figures/datasets/regulatory/*.png` |
| `14_hpv_profile.R` | Exploratory profile of datasets 2 + 2b (`hpv_spells` spell-level, `hpv_active` facility × year collapse): spell-duration distribution, program frequency, HPV-active rate over time. | `data/datasets/{hpv_spells,hpv_active,regulatory}.csv.gz` → `output/hpv_profile/*.csv` + `output/figures/datasets/hpv/*.png` |
| `15_coordinates_profile.R` | Exploratory profile of dataset 4: coordinate coverage, coordinate-vs-ICIS-county error, `ICIS_COUNTY_FIPS` coverage/agreement, facility geography. `HAS_COORDINATE` gates everything downstream (0 ≠ NA honored). | `data/datasets/coordinates.csv.gz` → `output/coordinates_profile/*.csv` + `output/figures/datasets/coordinates/*.png` |
| `16_pipeline_profile.R` | Exploratory profile of dataset 6: linkage rate over time, HPV/FRV share, evaluation-to-enforcement lag distribution, plus a row-level empirical check of `SORT_DATE`'s coalesce priority order. Mirrors dataset 0's zero-vs-NA gate; every rate reports the NA share. | `data/processed/pipeline.csv.gz`, `data/datasets/pipeline.csv.gz` → `output/pipeline_profile/*.csv` + `output/figures/datasets/pipeline/*.png` |
| `17_emissions_profile.R` | Exploratory profile of dataset 7: coverage by program/year, pollutant totals, GHG over time, plus a full-cross-program-extract view showing what coverage looks like before the ICIS-match restriction. `EMISSIONS_OBSERVED`/`GHG_OBSERVED` gate zero-vs-NA. | `data/processed/{emissions,facilities}.csv.gz`, `data/datasets/emissions.csv.gz` → `output/emissions_profile/*.csv` + `output/figures/datasets/emissions/*.png` |
| `18_panel_profile.R` | Exploratory profile of the panel layer (both panels): coverage (`OBS_SOURCE` composition), count-measure distributions, HPV-active rate, penalty distribution, geography, coordinate coverage, entry/exit censoring, and the electric-is-a-subset-of-major_synmin comparison. Added 2026-07-28 to fill the gap left when the old panel-layer profiles were archived (see the note below) — profiles the new two-panel structure from scratch. | `data/panels/{major_synmin_2015_2025,electric_2015_2025}.csv.gz` → `output/panel_profile/*.csv` + `output/figures/panels/*.png` |
| `preview_datasets.R` | **Local scratch (gitignored).** Dumps the first N rows (default 1,000; `N=` env override) of each of the eight `03_datasets` deliverables to a plain uncompressed CSV for eyeballing in a viewer. Builds nothing. | `data/datasets/*.csv.gz` → `data/datasets/_preview/*.csv` (gitignored) |
| `site_shell.R` | Shared header/nav/hero/footer chrome + CSS design system for the public `docs/` site (Home, Raw Data, Databases). No computed numbers — chrome only. Sourced by every `build_*` page script below. | sourced by `build_site.R`, `build_home.R`, `build_databases_page.R` |
| `build_site.R` | Assembles the "Raw Data" page — per-source summary sections built **directly from `data/raw/`** (independent of cleaning/datasets). Sources the section builders in `tables/`. This is the "docs generated from data, so they can't drift" step. | `data/raw/*` + `tables/*.R` → `docs/raw_data.html` |
| `tables/` | One `build_<asset>_section()` per source (16 + `_html.R` primitives); each returns one HTML `<section>` for `build_site.R`. Ported from the old CAA_Project `*_table.xlsx` workbooks (stats + curated content verbatim). | sourced by `build_site.R` |
| `build_home.R` | Assembles the "Home" page — hero, nav cards, and `briefs/institutional_overview.md` rendered via `commonmark` (its "Valuable Links" section and "Data implication" callouts stripped for a public audience; everything else passed through unedited). | `briefs/institutional_overview.md` → `docs/index.html` |
| `build_databases_page.R` | Assembles the "Databases" page — what each database contains, what's missing, and join keys, from `briefs/database_overviews.md` (transcribed verbatim from the project's Google Doc) rendered via `commonmark`. | `briefs/database_overviews.md` → `docs/databases.html` |

`08`–`10` are one-off investigations that informed a construction decision (see `briefs/datasets/dataset_construction_decisions.md`); `11`–`17` are the seven standing per-dataset profiling companions (one per built dataset — attainment isn't one of this repo's datasets, see decision W10 in `archive/panel_building_legacy/briefs/panel/panel_construction_decisions.md`); `18` is the panel-layer companion, one level up, profiling the two panels `code/04_panel_building/` builds from those datasets.

> ⚠ **2026-07-28:** `05_panel_summaries.R`, `06_panel_profile.R`, `06b_panel_deep_stats.R`,
> `07_majsyn_operating_profile.R`, the old `build_panels_page.R`, and `coord_county_check/` were
> **archived** to `archive/panel_building_legacy/diagnostics/` along with the old panel-building
> pipeline they profiled (the universe/major_synmin/electric funnel, built from `data/processed/`).
> They analyzed a panel structure that no longer exists going forward (`code/04_panel_building/`
> builds two narrowly-scoped continuous panels instead) and wouldn't run against it as-is.
> `18_panel_profile.R` (added the same day) and a rewritten `build_panels_page.R` now profile and
> publish the new two-panel structure from scratch — `docs/panels.html` is regenerated again as of
> that rewrite, not left as a static historical page.
>
> `build_site.R`, `build_home.R`, `build_databases_page.R`, and `build_panels_page.R` produce
> **committed deliverables** (GitHub Pages serves `docs/` directly), so although most of this folder
> is hand-run, these four are run by `code/RUN_ALL.R` as the "docs: build site" step (which still
> requires `18_panel_profile.R` to have been run by hand first, same as every profile script `11`–`18`
> — its output feeds `build_panels_page.R` but it produces no committed `docs/` asset itself). Set
> `SKIP_SECTIONS=emissions` on `build_site.R` to skip the ~900 MB emissions read during a quick
> rebuild; `SKIP_SITE=true` on `RUN_ALL.R` skips all four.

## Conventions for adding a diagnostic

Give each self-contained investigation its **own subfolder** with a short README stating the question, the
method, and the finding — e.g.:

```
diagnostics/
├── naics_codes/            # e.g. reconciling NAICS assignments
│   ├── README.md           #   what/why/finding
│   └── <script>.R
├── afs_frs_match/          # e.g. AFS ↔ FRS id matching quality
│   ├── README.md
│   └── <script>.R
└── ...
```

Keep pipeline-critical logic **out** of here — if a finding changes how an asset or dataset is built, fold the
change into `code/02_cleaning/` or `code/03_datasets/` and record the decision in
`briefs/datasets/dataset_construction_decisions.md`. Diagnostics document *why* a choice was investigated; the
pipeline implements the choice.

`archive/panel_building_legacy/diagnostics/coord_county_check/` followed this pattern (now archived
with the rest of the old panel-building pipeline) — see its own README for the question, method, and
finding (coordinate-vs-ICIS-county cross-check behind dataset 4's `coordinates`, which is unaffected
by the archival — this diagnostic just predates the current directory layout).

> Note: several other investigations referenced in the project notes (NAICS-code reconciliation, LQG
> mismatches, AFS↔FRS matching) are **not yet ported into this folder**. When they are, each gets its own
> subfolder as above.
