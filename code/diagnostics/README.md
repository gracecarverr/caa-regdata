# diagnostics — characterization, previews, and one-off investigations

Code that is **not part of the build pipeline** but is valuable for understanding, checking, and
characterizing the data. Nothing here is required to produce the panels; `code/RUN_ALL.R` does **not** run
this folder. Run these by hand as needed.

## What lives here

| script | what it does | inputs → outputs |
|--------|--------------|------------------|
| `05_panel_summaries.R` | Computes summary tabulations for the three built panels and emits `booktabs` LaTeX fragments (one `\input`-able `.tex` per table) plus a compilable wrapper. Every cell is computed from the panels — **no hand-entered numbers** — so the tables are fully reproducible. | `data/panels/{electric,major_synmin,universe}.csv.gz` → `output/tables/*.tex` |
| `06_panel_profile.R` | Broader **exploratory** characterization of the three panels: five-number summaries (+ mean/sd, %zero, and explicit NA accounting) for every count measure, categorical frequencies, binary-flag prevalence, per-year coverage, and by-state counts, plus figures (distributions, ECDFs, time series, penalty distribution, count correlations, electric PM2.5 exposure). Count summaries respect the `0 ≠ NA` rule (computed on observed facility-years; NA share reported). Live-computed — no hand-entered numbers. Needs `ggplot2`, `scales`. | `data/panels/{electric,major_synmin,universe}.csv.gz` → `output/panel_profile/*.csv` + `output/figures/*.png` |
| `build_site.R` | Assembles the committed documentation site `docs/index.html` — per-source summary sections built **directly from `data/raw/`** (independent of cleaning/panels). Sources the section builders in `tables/`. This is the "docs generated from data, so they can't drift" step. | `data/raw/*` + `tables/*.R` → `docs/index.html` |
| `tables/` | One `build_<asset>_section()` per source (16 + `_html.R` primitives); each returns one HTML `<section>` for `build_site.R`. Ported from the old CAA_Project `*_table.xlsx` workbooks (stats + curated content verbatim). | sourced by `build_site.R` |
| `preview_panels.R` | **Local scratch (gitignored).** Dumps the first N rows of each built panel to a plain uncompressed CSV for eyeballing in a viewer. Builds nothing. | `data/panels/*.csv.gz` → `data/panels/_preview/*.csv` (also gitignored) |

> `build_site.R` produces a **committed deliverable** (GitHub Pages serves `docs/index.html` directly), so
> although it lives here it is run by `code/RUN_ALL.R` as a documentation step. Set `SKIP_SECTIONS=emissions`
> to skip the ~900 MB emissions read during a quick rebuild.

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

Keep pipeline-critical logic **out** of here — if a finding changes how an asset or panel is built, fold the
change into `code/02_cleaning/` or `code/03_panel_building/` and record the decision in
`briefs/panel_construction_decisions.md`. Diagnostics document *why* a choice was investigated; the pipeline
implements the choice.

> Note: several investigations referenced in the project notes (NAICS-code reconciliation, LQG mismatches,
> AFS↔FRS matching) are **not yet ported into this folder**. When they are, each gets its own subfolder as
> above.
