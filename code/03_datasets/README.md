# 04_datasets — the eight deliverable datasets

**Stage inputs:** `data/processed/*.csv.gz` (cleaned assets) + `data/raw/{frs,us_counties}` + `data/datasets/`
outputs of earlier scripts in this folder (`hpv_active` reads `hpv_spells` and `regulatory`; **as of
2026-07-28, `operating` also reads `regulatory` and `emissions`** — see `02_operating.R`'s row below).
**Stage outputs:** `data/datasets/{regulatory,operating,wayback_only_facilities,hpv_spells,hpv_active,penalties,coordinates,pipeline,emissions}.csv.gz`
**Run:** as stage `04` of `code/RUN_ALL.R`. ⚠ **Not plain file order since 2026-07-28** — `RUN_ALL.R` sources
an explicit list: `01_regulatory.R, 08_emissions.R, 02_operating.R, 03_hpv_spells.R, 04_hpv_active.R,
05_penalties.R, 06_coordinates.R, 07_pipeline.R` (emissions moved up so `02_operating.R` can read its
output — see O6 in `briefs/datasets/dataset_construction_decisions.md`). Each script also runs standalone —
`Rscript code/04_datasets/01_regulatory.R`, etc. — assuming its own inputs already exist on disk
(`data/processed/`, plus any `data/datasets/*.csv.gz` it depends on per the table below).

The deliverable is **eight datasets, not one wide panel** — a departure from the `03_panel_building` layer's
three sample panels, which this repo also still builds (see `code/03_panel_building/README.md`); this layer
is the repo's main product. Each is built once over the **full** facility universe (no ever-active screen, no
sample restriction); any subsetting is a filter the user applies downstream. Everything joins on `PGM_SYS_ID`
(+ `YEAR` where the grain is facility × year); every file also carries `REGISTRY_ID` (the FRS cross-program
facility id) alongside `PGM_SYS_ID` (`G4`). Decisions are documented in depth in
`briefs/datasets/dataset_construction_decisions.md` (find a decision by its code, e.g. `R7`, `O5`, `H6`).

## Build order & files

| file | builds | grain | notes |
|------|--------|-------|-------|
| `00_parameters.R` | — | — | shared `YEARS`, paths, and `write_dataset()` (uppercases every column on write — the layer-wide naming convention, decision G2). Sourced by every script below, not run directly. |
| `01_regulatory.R` | **dataset 0** `regulatory` | facility × year | ICIS-Air only: event counts + ICIS facility characteristics. The zero-vs-NA rule (`ICIS_OBSERVED`) originates here and is reused by `hpv_active`. |
| `02_operating.R` | **dataset 1** `operating` + **dataset 1b** `wayback_only_facilities` | facility × year | Wayback status, program-active flags, entry/exit spells, earliest program-enrollment year (screened + raw), plus (NEW 2026-07-28) year-varying `ACTIVE`/`ACTIVE_BROAD` facility-existence indicators built from `regulatory`'s `ICIS_OBSERVED` and `emissions`'s `EMISSIONS_OBSERVED`/`GHG_OBSERVED` — see O6. Joins 1:1 to `regulatory`. Also writes the small supplementary `wayback_only_facilities.csv.gz` (facility × year, 2015–2025 only) for the ~15,302 facilities Wayback has seen that the current ICIS roster hasn't — see O7. |
| `03_hpv_spells.R` | **dataset 2** `hpv_spells` | spell | One row per HPV violation (`ENF_RESPONSE_POLICY_CODE == "HPV"`), UNcollapsed. The source of truth behind `hpv_active`. |
| `04_hpv_active.R` | **dataset 2b** `hpv_active` | facility × year | Deterministic **R2** (interval-overlap) collapse of `hpv_spells`. Joins 1:1 to `regulatory`/`operating`. |
| `05_penalties.R` | **dataset 3** `penalties` | formal action | Action-level penalties + the multi-facility settlement key (`ENF_IDENTIFIER`). Reconciles exactly to `regulatory`'s `PENALTY_AMOUNT`. |
| `06_coordinates.R` | **dataset 4** `coordinates` | facility | FRS lat/lon, derived county FIPS, coordinate-vs-ICIS-county error diagnostics. Uses `coord_county_flag.R` (local to this folder) over the full universe. This copy is a byte-for-byte duplicate (module docstring aside) of `code/03_panel_building/coord_county_flag.R`, plus one added output column (`icis_county_fips`); nothing enforces the two stay in sync, so a fix to the shared logic must be hand-applied to both. |
| `07_pipeline.R` | **dataset 6** `pipeline` | facility × year | EPA ECHO's "CAA Compliance Pipeline": links, in a single record, the evaluation (inspection) that found a violation to the enforcement action it triggered — a same-row chain no ICIS-Air table alone carries. Also includes FRV violations, not just HPV (`hpv_spells` is HPV-only). |
| `08_emissions.R` | **dataset 7** `emissions` | facility × year | Combined pollutant report (EIS/TRIS/E-GGRT/CAMDBS). Adds a real magnitude axis — annual pounds for VOC/PM10/PM2.5/NOx/SO2/CO, a broader HAP total, and GHG (metric tons CO2e) — where `regulatory`'s `EMITS_*` flags are booleans only ("ever permitted to emit"), not measured quantities. |

Dataset 5 (`attainment`, PM2.5 2012 nonattainment) does not exist in this layer — the number is skipped
intentionally, matching the panel layer, where the equivalent attainment code was removed from this repo
entirely on 2026-07-27 (already synced to the sibling `CAA_Project` repo; see decision W10 in
`briefs/panel/panel_construction_decisions.md`).

## Conventions

- **`UPPER_SNAKE_CASE` columns, always** — every builder assembles internally in lowercase, then uppercases
  once on write via `write_dataset()`. One transform point, no per-file casing drift (G2).
- **`PGM_SYS_ID` + `REGISTRY_ID` on every file** — the FRS id is joined in from `facilities.csv.gz` alongside
  the ICIS program-system id, `NA` where a facility has no FRS match (G4).
- **Full universe, no sample panels** — restrictions are the user's to apply, not baked into the build (G3).
- **Zero-vs-NA discipline, reused across datasets** — `regulatory`'s `ICIS_OBSERVED` flag is the reference
  implementation; `hpv_active` explicitly reuses it (H6) rather than inventing a separate observability rule.
- **File numbers are a stable dataset index, not a build-order guarantee** — `03_hpv_spells.R`/
  `04_hpv_active.R` are datasets "2" and "2b"; `05_penalties.R` is dataset "3". ⚠ Before 2026-07-28 the file
  numbers also happened to equal the literal run order (`01` through `08` in sequence); that's no longer
  true (`08_emissions.R` now runs 2nd, see the Run: line above and O6) — the numbers were always meant as a
  semantic dataset ID, this was just the first time the two diverged. Matches the numbering convention used
  in `03_panel_building/` (`00_spine.R`, `03_build.R` — no "01"/"02" file exists there).
- **Every build ends with `stopifnot()` invariants** (grain uniqueness, rectangle completeness, zero-vs-NA
  consistency) printed alongside a one-line summary. Independent verification beyond the in-script asserts
  is run ad hoc each session and logged in `briefs/datasets/dataset_construction_decisions.md`, not re-run automatically.

## Where the "why" lives

This README explains *what/how*. For *why* a construction choice was made (universe definition, zero-vs-NA,
the HPV spell/collapse rules, the settlement broadcast issue, the begin-year screen) see
**`briefs/datasets/dataset_construction_decisions.md`**. For **column-by-column definitions of every derived
field** in these eight files, see **`docs/data_dictionary_derived.md`**. The two HPV diagnostics that informed
dataset 2/2b (`code/diagnostics/08_hpv_spell_diagnostics.R`, `09_hpv_facility_year_rules.R`) are diagnostics,
not part of this build — see `code/diagnostics/README.md`.
