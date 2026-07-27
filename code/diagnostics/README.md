# diagnostics — characterization, previews, and one-off investigations

Code that is **not part of the build pipeline** (doesn't produce a `data/datasets/` or `data/panels/` asset)
but is valuable for understanding, checking, and characterizing the data. Most of this folder is run by hand
as needed — `code/RUN_ALL.R` does **not** source it. The exception is the site-generation scripts (including
the panel-profiling step the Panels page depends on), which `RUN_ALL.R` does run — see the table below and
the note after it.

## What lives here

| script | what it does | inputs → outputs |
|--------|--------------|------------------|
| `05_panel_summaries.R` | Summary tabulations for the three built panels (electric, major_synmin, universe): booktabs LaTeX table fragments + a compilable wrapper, for paper use. Hand-run only (needs a TeX engine to *compile*, not to generate). | `data/panels/{electric,major_synmin,universe}.csv.gz` → `output/tables/*.tex` |
| `06_panel_profile.R` | Exploratory profile of the three built panels: five-number summaries, frequencies, coverage (CSV) + distribution/time-series figures (PNG). Every count is reported on the observed subset with NA share (0 ≠ NA honored). **Run by `code/RUN_ALL.R`** — the Panels page (`build_panels_page.R`) depends on its CSV output. | `data/panels/{electric,major_synmin,universe}.csv.gz` → `output/panel_profile/*.csv` + `output/figures/*.png` |
| `07_majsyn_operating_profile.R` | Descriptive profile of the major_synmin panel restricted to `year %in% 2015:2025 & operating == 1` (the widest window where `operating` is defined) — where facilities are, how counts are distributed, Major vs. Synthetic Minor. Hand-run only. | `data/panels/major_synmin.csv.gz` → `output/figures/majsyn_operating/*.png` + `output/majsyn_operating/*.csv` |
| `08_hpv_spell_diagnostics.R` | Record-grain view of raw HPV violation records that informs how `hpv_spells` (dataset 2) should be constructed. Constructs no spells — flags the structure (missing start, open vs. resolved, bad-ordered/unparseable dates, dup rows, raw interval overlap) that the construction rules must resolve. | `data/processed/violations.csv.gz` → `output/hpv_spell_diagnostics/records.csv.gz` + console summary |
| `09_hpv_facility_year_rules.R` | Companion to `08` — compares four candidate spell→facility-year mapping rules (day-zero-year only, interval overlap, extended-open overlap, 30-day-union) by their effect on HPV-active coverage, to make the mapping choice (R2, used by `hpv_active`) by seeing it rather than assuming it. | `data/processed/violations.csv.gz` → `output/hpv_spell_diagnostics/facility_year_rules.csv.gz` + console comparison |
| `10_begin_year_proxy.R` | Evaluates whether `EARLIEST_PROGRAM_BEGIN_YEAR` (dataset 1) is a usable proxy for operating status pre-2015 (where wayback has no coverage), by comparing it against wayback `OPERATING` where both exist (2015–2025). Descriptive/statistical agreement only, not causal. | `data/datasets/operating.csv.gz` → `output/begin_year_proxy/{coverage,agreement,lag,post_exit_false_positive}.csv` + console summary |
| `11_operating_profile.R` | Exploratory profile of dataset 1: coverage, operating-status distribution, program-active prevalence, entry/exit spells, begin-year coverage. Every rate is computed on the observed subset with NA share reported (0 ≠ NA honored). | `data/datasets/operating.csv.gz` → `output/operating_profile/*.csv` + `output/figures/datasets/operating/*.png` |
| `12_penalties_profile.R` | Exploratory profile of dataset 3: penalty-amount distribution, action/enforcement-type composition, multi-facility settlement structure (descriptive only — the broadcast-rule decision itself lives in `briefs/datasets/multi_facility_settlement_decision.md`). | `data/datasets/penalties.csv.gz` → `output/penalties_profile/*.csv` + `output/figures/datasets/penalties/*.png` |
| `13_regulatory_profile.R` | Exploratory profile of dataset 0: coverage, event-count distributions, facility-characteristic breakdowns. `ICIS_OBSERVED` is the zero-vs-NA gate; every summary reports the NA share. | `data/datasets/regulatory.csv.gz` → `output/regulatory_profile/*.csv` + `output/figures/datasets/regulatory/*.png` |
| `14_hpv_profile.R` | Exploratory profile of datasets 2 + 2b (`hpv_spells` spell-level, `hpv_active` facility × year collapse): spell-duration distribution, program frequency, HPV-active rate over time. | `data/datasets/{hpv_spells,hpv_active,regulatory}.csv.gz` → `output/hpv_profile/*.csv` + `output/figures/datasets/hpv/*.png` |
| `15_coordinates_profile.R` | Exploratory profile of dataset 4: coordinate coverage, coordinate-vs-ICIS-county error, `ICIS_COUNTY_FIPS` coverage/agreement, facility geography. `HAS_COORDINATE` gates everything downstream (0 ≠ NA honored). | `data/datasets/coordinates.csv.gz` → `output/coordinates_profile/*.csv` + `output/figures/datasets/coordinates/*.png` |
| `preview_datasets.R` | **Local scratch (gitignored).** Dumps the first N rows (default 1,000; `N=` env override) of each of the eight `04_datasets` deliverables to a plain uncompressed CSV for eyeballing in a viewer. Builds nothing. | `data/datasets/*.csv.gz` → `data/datasets/_preview/*.csv` (gitignored) |
| `site_shell.R` | Shared header/nav/hero/footer chrome + CSS design system for the public `docs/` site (Home, Raw Data, Databases, Panels). No computed numbers — chrome only. Sourced by every `build_*` page script below. | sourced by `build_site.R`, `build_home.R`, `build_databases_page.R`, `build_panels_page.R` |
| `build_site.R` | Assembles the "Raw Data" page — per-source summary sections built **directly from `data/raw/`** (independent of cleaning/datasets). Sources the section builders in `tables/`. This is the "docs generated from data, so they can't drift" step. | `data/raw/*` + `tables/*.R` → `docs/raw_data.html` |
| `tables/` | One `build_<asset>_section()` per source (16 + `_html.R` primitives); each returns one HTML `<section>` for `build_site.R`. Ported from the old CAA_Project `*_table.xlsx` workbooks (stats + curated content verbatim). | sourced by `build_site.R` |
| `build_home.R` | Assembles the "Home" page — hero, nav cards, and `briefs/institutional_overview.md` rendered via `commonmark` (its "Valuable Links" section and "Data implication" callouts stripped for a public audience; everything else passed through unedited). | `briefs/institutional_overview.md` → `docs/index.html` |
| `build_databases_page.R` | Assembles the "Databases" page — what each database contains, what's missing, and join keys, from `briefs/database_overviews.md` (transcribed verbatim from the project's Google Doc) rendered via `commonmark`. | `briefs/database_overviews.md` → `docs/databases.html` |
| `build_panels_page.R` | Assembles the "Panels" page — the findings-summary narrative (`briefs/panel/panel_findings_summary.md`, used as-is) plus summary-stat tables computed live from `06_panel_profile.R`'s CSV output. No number is retyped. | `briefs/panel/panel_findings_summary.md` + `output/panel_profile/*.csv` → `docs/panels.html` |

`08`–`10` are one-off investigations that informed a construction decision (see `briefs/datasets/dataset_construction_decisions.md`); `11`–`15` are the five standing per-dataset profiling companions (one per built dataset — attainment isn't one of this repo's datasets, see decision W10 in `briefs/panel/panel_construction_decisions.md`). `05` and `07` are panel-layer companions to `06` — all three are hand-run except `06` itself.

> `build_site.R`, `build_home.R`, `build_databases_page.R`, `06_panel_profile.R`, and `build_panels_page.R`
> produce **committed deliverables** (GitHub Pages serves `docs/` directly), so although most of this folder
> is hand-run, these five are run by `code/RUN_ALL.R` as the "docs: build site" step. Set
> `SKIP_SECTIONS=emissions` on `build_site.R` to skip the ~900 MB emissions read during a quick rebuild;
> `SKIP_SITE=true` on `RUN_ALL.R` skips all five.

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
change into `code/02_cleaning/` or `code/04_datasets/` and record the decision in
`briefs/datasets/dataset_construction_decisions.md`. Diagnostics document *why* a choice was investigated; the
pipeline implements the choice.

`coord_county_check/` follows this pattern already — see its own README for the question, method, and
finding (coordinate-vs-ICIS-county cross-check behind dataset 4's `coordinates`).

> Note: several other investigations referenced in the project notes (NAICS-code reconciliation, LQG
> mismatches, AFS↔FRS matching) are **not yet ported into this folder**. When they are, each gets its own
> subfolder as above.
