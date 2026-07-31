# data/datasets — the nine deliverable datasets

Built by [`code/03_datasets`](../../code/03_datasets/README.md) from the processed assets. All files are
gzip-compressed CSV, **gitignored**, rebuilt from code. Every column is `UPPER_SNAKE_CASE`; every dataset is
built over the **full** facility universe (no ever-active screen, no sample restriction — that's a filter
the user applies downstream). This layer is this repo's main product; the panel layer in
[`data/panels/`](../panels/README.md) (`code/04_panel_building`) is built **on top of** it (as of
2026-07-28) rather than being an independent, coexisting layer — nine purpose-built full-universe tables
here (dataset 5, attainment, is intentionally skipped — see below) feed the two continuous facility × year
panels there.

| file | grain | what | built by |
|------|-------|------|----------|
| `regulatory.csv.gz` | facility × year | **dataset 0** — ICIS-Air only: event counts (inspections, violations, enforcement, certs, stack tests) + ICIS facility characteristics. `ICIS_OBSERVED` is the zero-vs-NA reference flag reused elsewhere in the layer. | `01_regulatory.R` |
| `operating.csv.gz` | facility × year | **dataset 1** — Wayback operating status (2015–2025, strictly raw, `NA` outside coverage), 8 `PROG_*_ACTIVE` flags, entry/exit spells, `EARLIEST_PROGRAM_BEGIN_YEAR` (screened to [1970,2025]) + `_RAW`. Joins **1:1** to `regulatory.csv.gz`. | `02_operating.R` |
| `hpv_spells.csv.gz` | spell | **dataset 2** — one row per HPV violation (`ENF_RESPONSE_POLICY_CODE == "HPV"`), UNcollapsed. `SPELL_STATUS` ∈ {closed, open, bad_order, missing_start}; dates carried as parsed, no screen. | `03_hpv_spells.R` |
| `hpv_active.csv.gz` | facility × year | **dataset 2b** — `HPV_ACTIVE` flag, a deterministic **R2** (interval-overlap) collapse of `hpv_spells.csv.gz`, screened at collapse to a plausible day-zero year. Joins **1:1** to `regulatory.csv.gz`. | `04_hpv_active.R` |
| `penalties.csv.gz` | formal action | **dataset 3** — action-level penalties + the multi-facility settlement key (`ENF_IDENTIFIER`, `N_SETTLEMENT_FACILITIES`, `IS_MULTI_FACILITY`). Windowed sum reconciles exactly to `regulatory.csv.gz`'s `PENALTY_AMOUNT`. | `05_penalties.R` |
| `coordinates.csv.gz` | facility | **dataset 4** — FRS lat/lon, derived `COUNTY_FIPS` (point-in-polygon), and coordinate-vs-ICIS-county error diagnostics (`COORD_COUNTY_DIST_KM`, `COORD_GROSS_ERROR`). | `06_coordinates.R` |
| `pipeline.csv.gz` | facility × year | **dataset 6** — EPA ECHO CAA Compliance Pipeline: violation counts split HPV/FRV, how many trace to a linked evaluation or enforcement action, self-disclosure count, EA-penalty count/sum, and eval→violation / violation→enforcement lag in days. Joins **1:1** to `regulatory.csv.gz`. | `07_pipeline.R` |
| `emissions.csv.gz` | facility × year | **dataset 7** — annual pollutant quantities (VOC/PM10/PM2.5/NOx/SO2/CO/HAP in lbs; GHG in MTCO2e) from EIS/TRIS/E-GGRT/CAMDBS, joined via `REGISTRY_ID` (cross-program, not `PGM_SYS_ID`). `IS_SHARED_REGISTRY` flags facilities that share an FRS id with another `PGM_SYS_ID` — don't sum across those without accounting for it. Joins **1:1** to `regulatory.csv.gz`. | `08_emissions.R` |
| `wayback_only_facilities.csv.gz` | facility × year (2015–2025 only) | **dataset 1b** — supplementary, NOT part of the numbered 0–7 sequence and joins to nothing else in this layer. The ~15,302 facilities Wayback has seen operating-status snapshots for that are entirely absent from the current ICIS-AIR extract (zero ICIS events or attributes of any kind). Carries `OP_STATUS_CODE`/`OP_STATUS_DESC`/`OPERATING`/`WAYBACK_OBSERVED` (year-varying) + `ENTERED_YEAR`/`EXITED_YEAR`/`EXIT_SOURCE`/`LEFT_CENSORED`/`RIGHT_CENSORED` (facility-level). Added 2026-07-28 (decision `O7`) so a user doesn't have to hand-join the raw Wayback layer to recover this population. | `02_operating.R` |

Dataset 5 (`attainment`, PM2.5 2012 nonattainment, facility × year) does not exist in this layer — the
number is skipped intentionally; see decision W10 in
`archive/panel_building_legacy/briefs/panel/panel_construction_decisions.md`.

## Source assets & time-type

What each dataset is actually built from, and whether that source is a historical/event log (many dated
records per facility) or a current snapshot (one undated record per facility, no history) — full detail in
`briefs/datasets/dataset_construction_decisions.md`'s per-Part "Source" notes:

| dataset | source | time-type |
|---|---|---|
| `regulatory` | `data/processed/{inspections,violations,formal_actions,informal_actions,certs,stacktests}.csv.gz` (event-grain) + `{facilities,pollutants,programs}.csv.gz` (snapshot-grain) | historical (events) + current snapshot (attributes) |
| `operating` / `wayback_only_facilities` | `data/processed/wayback_{facility_status,facility_spells,program_status}.csv.gz` (11 archived annual captures) + `programs.csv.gz`'s `BEGIN_DATE` | historical (11 yearly snapshots, 2015–2025) |
| `hpv_spells` / `hpv_active` | `data/processed/violations.csv.gz` | historical (event-grain) |
| `penalties` | `data/processed/formal_actions.csv.gz` | historical (event-grain) |
| `coordinates` | `data/raw/frs/FRS_FACILITIES.csv` + `data/raw/us_counties/us_counties.shp` + `facilities.csv.gz` | current snapshot (FRS/ICIS) + static reference (shapefile) |
| `pipeline` | `data/raw/PIPELINE_CAA_00_COMPLETE.csv` (automated weekly refresh as of 2026-07-27) | historical (event-grain) |
| `emissions` | `data/processed/emissions.csv.gz` (raw `POLL_RPT_COMBINED_EMISSIONS.csv`) | historical, but uneven — EIS triennial (2008/2011/2014/2017/2020), TRIS/CAMDBS/E-GGRT annual from 2015 |

## Joining

Every dataset joins on `PGM_SYS_ID`. `regulatory`, `operating`, and `hpv_active` share the identical
279,665-facility × 2005–2025 rectangle (as of 2026-07-27; drifts with each live ICIS-AIR refresh) and join
**1:1** on `(PGM_SYS_ID, YEAR)`. `hpv_spells` and
`penalties` are event-grain (spell / formal-action) and join **many-to-one** onto the rectangle via
`PGM_SYS_ID` (+ `YEAR` for facility-year merges — but see `penalties`' settlement-broadcast caveat before
summing across facilities). `coordinates` is facility-grain and joins onto any of the above via `PGM_SYS_ID`.

Every file also carries `REGISTRY_ID` (the FRS cross-program facility id), joined in from `facilities.csv.gz`
alongside `PGM_SYS_ID` and `NA` where a facility has no FRS match — useful for checks that need facility
identity across ICIS program systems (e.g. whether co-defendants in a multi-facility settlement are the same
physical site, see `briefs/datasets/multi_facility_settlement_decision.md` §5).

## Things to know before using a dataset

- **Zero-vs-NA discipline is load-bearing, not a formality.** `regulatory.csv.gz`'s `ICIS_OBSERVED` flag is the
  reference implementation — a facility-year with no ICIS record that year is `NA` (unknown), not a false `0`
  — and `hpv_active.csv.gz` explicitly reuses it rather than inventing a separate rule. `emissions.csv.gz` has
  its own analogous pair, `EMISSIONS_OBSERVED`/`GHG_OBSERVED`. Coalescing any of these `NA`s to `0` before
  checking the flag will silently understate true zeros' denominator.
- **`PENALTY_AMOUNT` (`regulatory.csv.gz`) is `NA` if no formal action occurred that facility-year *or* if it
  summed to exactly `$0`** — both read the same, a documented, unresolved ambiguity (same caveat carried
  unchanged into `data/panels/`, see `data/panels/README.md`). It can't currently distinguish "no enforcement"
  from "enforcement, zero-dollar penalty."
- **Don't sum `penalties.csv.gz`'s per-action `PENALTY_AMOUNT` across facilities sharing a settlement
  (`ENF_IDENTIFIER`) without a broadcast rule.** 571 settlements span more than one facility (up to 117
  co-defendants), and 64 of those carry *differing* per-facility amounts — it is not a clean one-value-repeated
  broadcast. See decision `P5` and `briefs/datasets/multi_facility_settlement_decision.md`.
- **`emissions.csv.gz`'s `IS_SHARED_REGISTRY` flags facilities sharing an FRS `REGISTRY_ID` with another
  `PGM_SYS_ID`** — don't sum pollutant quantities across those rows without accounting for the shared
  registration, or a single physical facility's emissions can be double-counted.
- **`N_PROGRAMS` is `NA`-able, never coalesced to `0`** (decision `R7`) — a facility with no program record at
  all reads `NA`, distinct from a genuine `0` on any individual `PROG_*` flag.
- **`PROG_GACT`/`PROG_CFC` don't exist in this layer** (decisions `R6`/`O3`) — if a downstream script or an
  older brief references them, that's stale; they were never carried into `regulatory.csv.gz`/`operating.csv.gz`.
- **`hpv_spells.csv.gz` is uncollapsed and includes non-clean intervals** — `SPELL_STATUS` can be
  `bad_order` or `missing_start`, not just `closed`/`open`; use `hpv_active.csv.gz` (the deterministic **R2**
  collapse) rather than re-deriving a facility-year HPV flag from raw spells unless you specifically need the
  record-grain view.
- **Dataset 5 (`attainment`) does not exist here, on purpose** (decision `W10`) — don't search for a missing
  file; it was dropped from this repo entirely, not accidentally omitted.

## Where the "why" lives

**Construction rationale, decision codes, and verification results:**
[`briefs/datasets/dataset_construction_decisions.md`](../../briefs/datasets/dataset_construction_decisions.md) — organized by
dataset (Parts A–H), each with a coding-decisions table and a verification table from independent audits run
each build session. **Column/field definitions** for the underlying raw sources:
[`docs/data_dictionary.md`](../../docs/data_dictionary.md); for the **built/derived columns in these nine
files** (every `N_*` count, flag, and derived field, column by column): [`docs/data_dictionary_derived.md`](../../docs/data_dictionary_derived.md).
