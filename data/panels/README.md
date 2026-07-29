# data/panels — the two continuous panels

Built by [`code/04_panel_building`](../../code/04_panel_building/README.md) from `data/datasets/` (the
eight-dataset layer, `code/03_datasets/`) — **not** from `data/processed/` directly. All files are
gzip-compressed CSV, **gitignored**, rebuilt from code.

> **2026-07-28:** this pipeline replaced a larger one that built a general facility spine plus three sample
> panels (`universe`/`major_synmin`/`electric`) directly from `data/processed/`. That system, its outputs as
> of 2026-07-28, and its docs are archived in full at
> [`archive/panel_building_legacy/`](../../archive/panel_building_legacy/README.md) — see that README for
> why it was archived rather than converted in place (the short version: the source ICIS-AIR/Wayback/FRS
> data is live-refreshed, so preserving both the old code *and* a frozen data snapshot was the only way to
> keep the old numbers reproducible, not just the old logic).

| file | grain | what | built by |
|------|-------|------|----------|
| `major_synmin_continuous_2015_2025.csv.gz` | facility × year (2015–2025) | CONUS, Major/Synthetic-Minor emissions class, **continuously `ACTIVE_BROAD == 1` every year 2015–2025** — 116 cols, 20,261 facilities, 222,871 rows | `03_build.R` |
| `electric_continuous_2015_2025.csv.gz` | facility × year (2015–2025) | the above **+** electric utilities (NAICS 2211 / SIC 4911) — 116 cols, 1,913 facilities, 21,043 rows | `03_build.R` |

Figures as of the 2026-07-28 rebuild — will drift with each live ICIS-AIR/Wayback refresh.

There is no longer a separate `spine.csv.gz`, `universe.csv.gz`, or non-continuous `major_synmin.csv.gz` /
`electric.csv.gz` — this pipeline ships only the two panels above (see
[`code/04_panel_building/README.md`](../../code/04_panel_building/README.md) for why: both target panels
share the same CONUS + class filter, computed once as an in-memory candidate set rather than a general
persisted spine, and there was no request for the broader non-continuous or full-universe samples the old
system shipped).

## The continuity rule (what's new here)

Both panels require **`ACTIVE_BROAD == 1` in every one of the 11 years, 2015–2025** — no partial credit, no
imputation across a gap. `ACTIVE_BROAD` (from `data/datasets/operating.csv.gz`, decision `O6` in
[`briefs/datasets/dataset_construction_decisions.md`](../../briefs/datasets/dataset_construction_decisions.md))
is itself a union of three activity signals for that specific year: Wayback-confirmed operating status, an
ICIS regulatory event, or emissions/GHG reporting. This replaces the old (archived) system's continuity
concept, which was never actually shipped as a built file — it existed only as an ad hoc diagnostic count,
defined as "≥1 regulatory event in every year" (see `PR2` in the archived
`briefs/panel/panel_construction_decisions.md`).

## Key things to remember when using a panel

- **`0` ≠ `NA`.** `OBS_SOURCE ∈ {event, operating}` for every row in these two panels — by construction,
  every facility here has `ACTIVE_BROAD == 1` in every panel year, so `OBS_SOURCE` can never be
  `"unobserved"` here (unlike the archived system's broader, non-continuity-screened panels, where it could
  be). `"event"` = an ICIS record exists that year (counts are real); `"operating"` = no ICIS event, but
  confirmed active some other way (event counts are a true `0`, not missing).
- **`N_*` count all rows — nothing is deduped.** Duplicate load is surfaced by `_DUP` (event-key repeats)
  and `_DUP_EXACT` (byte-identical) on inspections, enforcement (+ formal/informal), and certs; recover
  event-distinct counts as `N_X − N_X_DUP`. `PENALTY_AMOUNT` sums all formal rows (`NA` if no formal action
  or if it summed to exactly `$0` — both read the same); `PENALTY_AMOUNT_DUP` gives the duplicate-row
  dollars. `HPV_ACTIVE` is a binary status flag (no `HPV_ACTIVE_1MO` variant — not shipped).
- **`ACTIVE`/`ACTIVE_BROAD`, `ICIS_OBSERVED`, `EMISSIONS_OBSERVED`/`GHG_OBSERVED` ride along as their own
  columns** — the constituent evidence behind `OBS_SOURCE` and the continuity screen is visible in place,
  not hidden inside a derived flag.
- **`PROG_GACT`/`PROG_CFC` don't exist in these columns** — `data/datasets/regulatory.csv.gz`/
  `operating.csv.gz` never carry them (dataset-layer decisions `R6`/`O3`).
- **`N_PROGRAMS` is `NA`-able**, never coalesced to `0` — a facility with no program record at all reads
  `NA`, distinct from a `0` on any individual `PROG_*` flag.
- **Wayback-derived columns (`OP_STATUS_CODE`, `OPERATING`, `PROG_*_ACTIVE`) are 2015–2025 only** — moot for
  these two panels specifically, since the panel window itself is already 2015–2025.
- **Facility class/industry are the current ICIS snapshot** applied to all years; `PROG_*` (static) flags
  are ever-enrolled and undated. `EARLIEST_PROGRAM_BEGIN_YEAR`/`_RAW` (facility-level) date the *earliest*
  program enrollment; `NA` where no program record or no in-range date.

Column-by-column definitions: [`docs/data_dictionary_derived.md`](../../docs/data_dictionary_derived.md).
Construction rationale: [`briefs/panel/panel_construction_decisions.md`](../../briefs/panel/panel_construction_decisions.md).
