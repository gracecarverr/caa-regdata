# data/datasets — the six deliverable datasets

Built by [`code/04_datasets`](../../code/04_datasets/README.md) from the processed assets. All files are
gzip-compressed CSV, **gitignored**, rebuilt from code. Every column is `UPPER_SNAKE_CASE`; every dataset is
built over the **full** facility universe (no ever-active screen, no sample restriction — that's a filter
the user applies downstream). This layer supersedes the single wide panel in `data/panels/` — six
purpose-built tables instead of one.

| file | grain | what | built by |
|------|-------|------|----------|
| `regulatory.csv.gz` | facility × year | **dataset 0** — ICIS-Air only: event counts (inspections, violations, enforcement, certs, stack tests) + ICIS facility characteristics. `ICIS_OBSERVED` is the zero-vs-NA reference flag reused elsewhere in the layer. | `01_regulatory.R` |
| `operating.csv.gz` | facility × year | **dataset 1** — Wayback operating status (2015–2025, strictly raw, `NA` outside coverage), 8 `PROG_*_ACTIVE` flags, entry/exit spells, `EARLIEST_PROGRAM_BEGIN_YEAR` (screened to [1970,2025]) + `_RAW`. Joins **1:1** to `regulatory.csv.gz`. | `02_operating.R` |
| `hpv_spells.csv.gz` | spell | **dataset 2** — one row per HPV violation (`ENF_RESPONSE_POLICY_CODE == "HPV"`), UNcollapsed. `SPELL_STATUS` ∈ {closed, open, bad_order, missing_start}; dates carried as parsed, no screen. | `03_hpv_spells.R` |
| `hpv_active.csv.gz` | facility × year | **dataset 2b** — `HPV_ACTIVE` flag, a deterministic **R2** (interval-overlap) collapse of `hpv_spells.csv.gz`, screened at collapse to a plausible day-zero year. Joins **1:1** to `regulatory.csv.gz`. | `04_hpv_active.R` |
| `penalties.csv.gz` | formal action | **dataset 3** — action-level penalties + the multi-facility settlement key (`ENF_IDENTIFIER`, `N_SETTLEMENT_FACILITIES`, `IS_MULTI_FACILITY`). Windowed sum reconciles exactly to `regulatory.csv.gz`'s `PENALTY_AMOUNT`. | `05_penalties.R` |
| `coordinates.csv.gz` | facility | **dataset 4** — FRS lat/lon, derived `COUNTY_FIPS` (point-in-polygon), and coordinate-vs-ICIS-county error diagnostics (`COORD_COUNTY_DIST_KM`, `COORD_GROSS_ERROR`). | `06_coordinates.R` |

Dataset 5 (`attainment`, PM2.5 2012 nonattainment, facility × year) is **not yet built** — see the open item
in `briefs/datasets/dataset_construction_decisions.md`.

## Joining

Every dataset joins on `PGM_SYS_ID`. `regulatory`, `operating`, and `hpv_active` share the identical
279,211-facility × 2005–2025 rectangle and join **1:1** on `(PGM_SYS_ID, YEAR)`. `hpv_spells` and
`penalties` are event-grain (spell / formal-action) and join **many-to-one** onto the rectangle via
`PGM_SYS_ID` (+ `YEAR` for facility-year merges — but see `penalties`' settlement-broadcast caveat before
summing across facilities). `coordinates` is facility-grain and joins onto any of the above via `PGM_SYS_ID`.

## Where the "why" lives

**Construction rationale, decision codes, and verification results:**
[`briefs/datasets/dataset_construction_decisions.md`](../../briefs/datasets/dataset_construction_decisions.md) — organized by
dataset (Parts A–F), each with a coding-decisions table and a verification table from independent audits run
each build session. **Column/field definitions** for the underlying raw sources:
[`docs/data_dictionary.md`](../../docs/data_dictionary.md).
