# data/panels — the two panels

Built by [`code/04_panel_building`](../../code/04_panel_building/README.md) from `data/datasets/` (the
nine-dataset layer, `code/03_datasets/`) — **not** from `data/processed/` directly. All files are
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
| `major_synmin_2015_2025.csv.gz` | facility × year (2015–2025) | CONUS, Major/Synthetic-Minor emissions class, **`ACTIVE_BROAD == 1` in at least one year 2015–2025** — 113 cols, 45,872 facilities, 504,592 rows | `03_build.R` |
| `electric_2015_2025.csv.gz` | facility × year (2015–2025) | the above **+** electric utilities (NAICS 2211 / SIC 4911) — 113 cols, 2,965 facilities, 32,615 rows | `03_build.R` |

Figures as of the 2026-07-29 rebuild, following the Wayback capture Q4 re-pin
(`briefs/datasets/dataset_construction_decisions.md` `O8`) — will drift with each live ICIS-AIR/Wayback
refresh. The 113-column count reflects an earlier same-day revision (`OP_STATUS_CURRENT_DESC` and
`LEFT_CENSORED`/`RIGHT_CENSORED` dropped, `docs/data_dictionary_derived.md` Part 2) and was unaffected by the
Q4 re-pin; only the row/facility counts moved (down by 1 facility for major_synmin, unchanged for electric).

There is no longer a separate `spine.csv.gz`, `universe.csv.gz`, or full-universe `major_synmin.csv.gz` /
`electric.csv.gz` — this pipeline ships only the two panels above (see
[`code/04_panel_building/README.md`](../../code/04_panel_building/README.md) for why: both target panels
share the same CONUS + class filter, computed once as an in-memory candidate set rather than a general
persisted spine, and there was no request for the broader full-universe samples the old system shipped).

## The eligibility rule (revised 2026-07-29)

Both panels require **`ACTIVE_BROAD == 1` in at least one of the 11 years, 2015–2025** —
`any(ACTIVE_BROAD == 1, na.rm = TRUE)`. `ACTIVE_BROAD` (from `data/datasets/operating.csv.gz`, decision `O6`
in
[`briefs/datasets/dataset_construction_decisions.md`](../../briefs/datasets/dataset_construction_decisions.md))
is itself a union of three activity signals for that specific year: Wayback-confirmed operating status, an
ICIS regulatory event, or emissions/GHG reporting.

**Originally (2026-07-28) this rule required `ACTIVE_BROAD == 1` in *every* one of the 11 years** ("continuous")
— retired by explicit user decision (see `PB2` in
[`briefs/panel/panel_construction_decisions.md`](../../briefs/panel/panel_construction_decisions.md)):
requiring full-window continuity drops exactly the facilities most likely to exit *because of*
enforcement/penalty outcomes, biasing an enforcement/compliance panel toward survivors. Every eligible
facility still gets a full 11-year rectangle of rows — years outside its actual activity now read as
`OBS_SOURCE == "unobserved"` (see below), which was impossible under the old all-11-years rule but is
expected and normal under this one.

## Key things to remember when using a panel

- **`0` ≠ `NA`.** `OBS_SOURCE ∈ {event, operating, confirmed_inactive, unobserved}` (four-way as of
  2026-07-30) — `"event"` = an ICIS record exists that year (counts are real); `"operating"` = no ICIS event,
  but confirmed active some other way (event counts are a true `0`, not missing); `"confirmed_inactive"` = no
  ICIS event, but every checked signal (Wayback status, emissions/GHG reporting) positively confirms the
  facility was NOT active that year (event counts are also a true `0` — we know the outcome, we just didn't
  get an ICIS record); `"unobserved"` = no ICIS event and no signal either way (`ACTIVE_BROAD` is genuinely
  `NA` — counts stay `NA`, the only truly unknown case). `"confirmed_inactive"`/`"unobserved"` years are
  expected for a facility whose only qualifying (`ACTIVE_BROAD == 1`) year is outside that row's year — this
  differs from the pre-2026-07-29 continuity-screened panels, where neither could appear. Before 2026-07-30,
  `"confirmed_inactive"` rows were folded into `"unobserved"` — a bug, since `ACTIVE_BROAD`'s 0-vs-`NA`
  distinction was already computed correctly one layer up (`operating.csv.gz`, `O6`) and was being discarded
  here; see `PB4` in `panel_construction_decisions.md`.
- **`N_*` count all rows — nothing is deduped.** Duplicate load is surfaced by `_DUP` (event-key repeats)
  and `_DUP_EXACT` (byte-identical) on inspections, enforcement (+ formal/informal), and certs; recover
  event-distinct counts as `N_X − N_X_DUP`. `PENALTY_AMOUNT` sums all formal rows (`NA` if no formal action
  or if it summed to exactly `$0` — both read the same); `PENALTY_AMOUNT_DUP` gives the duplicate-row
  dollars. `HPV_ACTIVE` is a binary status flag (no `HPV_ACTIVE_1MO` variant — not shipped).
- **`OPERATING_IMPUTED` (NEW 2026-07-30)** flags the one narrow exception to "no imputation" in this pipeline
  (`O2`): a 2018 row whose `OPERATING` was bridge-imputed because the facility had a real, raw 2017
  observation AND a real, raw 2019 observation agreeing on the same operating bucket. `1` for those rows, `0`
  everywhere else, never `NA` — filter on it if you want raw-observation-only analysis. `OP_STATUS_CODE` is
  still `NA` for these rows (only the coarse operating bucket is imputed, never a specific status code); see
  `O2` in `dataset_construction_decisions.md` for the full derivation and what was verified unaffected
  (panel eligibility, entry/exit spells) before adding it.
- **`ACTIVE`/`ACTIVE_BROAD`, `ICIS_OBSERVED`, `EMISSIONS_OBSERVED`/`GHG_OBSERVED` ride along as their own
  columns** — the constituent evidence behind `OBS_SOURCE` and the eligibility screen is visible in place,
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
