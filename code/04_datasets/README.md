# 04_datasets — the six deliverable datasets

**Stage inputs:** `data/processed/*.csv.gz` (cleaned assets) + `data/raw/{frs,us_counties}` + `data/datasets/`
outputs of earlier scripts in this folder (`hpv_active` reads `hpv_spells` and `regulatory`).
**Stage outputs:** `data/datasets/{regulatory,operating,hpv_spells,hpv_active,penalties,coordinates}.csv.gz`
**Run:** each script individually, in file order — `Rscript code/04_datasets/01_regulatory.R`, etc. **Not yet
wired into `code/RUN_ALL.R`** (the six datasets are still being finalized; `attainment` is not built).

The deliverable is **six datasets, not one wide panel** — a departure from the `03_panel_building` layer's
three sample panels. Each is built once over the **full** facility universe (no ever-active screen, no
sample restriction); any subsetting is a filter the user applies downstream. Everything joins on `PGM_SYS_ID`
(+ `YEAR` where the grain is facility × year). Decisions are documented in depth in
`briefs/dataset_construction_decisions.md` (find a decision by its code, e.g. `R7`, `O5`, `H6`).

## Build order & files

| file | builds | grain | notes |
|------|--------|-------|-------|
| `00_parameters.R` | — | — | shared `YEARS`, paths, and `write_dataset()` (uppercases every column on write — the layer-wide naming convention, decision G2). Sourced by every script below, not run directly. |
| `01_regulatory.R` | **dataset 0** `regulatory` | facility × year | ICIS-Air only: event counts + ICIS facility characteristics. The zero-vs-NA rule (`ICIS_OBSERVED`) originates here and is reused by `hpv_active`. |
| `02_operating.R` | **dataset 1** `operating` | facility × year | Wayback status, program-active flags, entry/exit spells, earliest program-enrollment year (screened + raw). Joins 1:1 to `regulatory`. |
| `03_hpv_spells.R` | **dataset 2** `hpv_spells` | spell | One row per HPV violation (`ENF_RESPONSE_POLICY_CODE == "HPV"`), UNcollapsed. The source of truth behind `hpv_active`. |
| `04_hpv_active.R` | **dataset 2b** `hpv_active` | facility × year | Deterministic **R2** (interval-overlap) collapse of `hpv_spells`. Joins 1:1 to `regulatory`/`operating`. |
| `05_penalties.R` | **dataset 3** `penalties` | formal action | Action-level penalties + the multi-facility settlement key (`ENF_IDENTIFIER`). Reconciles exactly to `regulatory`'s `PENALTY_AMOUNT`. |
| `06_coordinates.R` | **dataset 4** `coordinates` | facility | FRS lat/lon, derived county FIPS, coordinate-vs-ICIS-county error diagnostics. Reuses `03_panel_building/coord_county_flag.R` over the full universe. |

Dataset 5 (`attainment`, PM2.5 2012 nonattainment) is **not yet built** — deferred pending a shape decision
(see the open item in `briefs/dataset_construction_decisions.md`).

## Conventions

- **`UPPER_SNAKE_CASE` columns, always** — every builder assembles internally in lowercase, then uppercases
  once on write via `write_dataset()`. One transform point, no per-file casing drift (G2).
- **Full universe, no sample panels** — restrictions are the user's to apply, not baked into the build (G3).
- **Zero-vs-NA discipline, reused across datasets** — `regulatory`'s `ICIS_OBSERVED` flag is the reference
  implementation; `hpv_active` explicitly reuses it (H6) rather than inventing a separate observability rule.
- **File numbers are build order, not a dataset index** — `03_hpv_spells.R`/`04_hpv_active.R` are datasets
  "2" and "2b"; `05_penalties.R` is dataset "3". Matches the numbering convention used in
  `03_panel_building/` (`00_spine.R`, `01_attainment.R`, `03_build.R` — no "02" file exists there either).
- **Every build ends with `stopifnot()` invariants** (grain uniqueness, rectangle completeness, zero-vs-NA
  consistency) printed alongside a one-line summary. Independent verification beyond the in-script asserts
  is run ad hoc each session and logged in `briefs/dataset_construction_decisions.md`, not re-run automatically.

## Where the "why" lives

This README explains *what/how*. For *why* a construction choice was made (universe definition, zero-vs-NA,
the HPV spell/collapse rules, the settlement broadcast issue, the begin-year screen) see
**`briefs/dataset_construction_decisions.md`**. The two HPV diagnostics that informed dataset 2/2b
(`code/diagnostics/08_hpv_spell_diagnostics.R`, `09_hpv_facility_year_rules.R`) are diagnostics, not part of
this build — see `code/diagnostics/README.md`.
