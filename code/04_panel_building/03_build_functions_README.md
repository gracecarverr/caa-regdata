> **Status:** draft — [ ] verified against the current script (Claude, 2026-07-30)

# `03_build_functions.R` — defines `build_panel()`, the shared facility × year recipe both panels run through

## Purpose in the pipeline
> **TODO (Grace):** write the 1-2 sentence purpose blurb here — why this script exists and what depends on
> it. Starting material, from the script's own header comment:
> "the shared facility x year panel recipe, now built by READING the already-built datasets layer instead
> of re-aggregating raw event assets. Requires (in scope when build_panel() runs): YEARS (defined in
> 03_build_parameters.R, = 2015:2025 for this pipeline)... This is a from-scratch rewrite, NOT the old
> code/03_panel_building/03_build_functions.R renamed... Nearly everything that file computed by hand
> (per-source event aggregation, dedup-load flags, HPV interval collapse, wayback status attachment, the
> known-operating-zero fill) is now a straight READ from a dataset that already computed it once, upstream...
> The ONE piece of real logic that survives from the archived pipeline is the known-operating-zero fill
> (OBS_SOURCE) -- combining "did ICIS record an event this year" with "do we otherwise have positive
> evidence the facility was active this year" is still this panel's own job, nobody upstream does it."

## Inputs & outputs
- **Input:** `data/datasets/regulatory.csv.gz` (via `read_counts()`) — all `N_*` event counts +
  `PENALTY_AMOUNT`/`PENALTY_AMOUNT_DUP`, facility × year.
- **Input:** `data/datasets/operating.csv.gz` (via `read_wayback()`) — year-varying wayback status
  (`OP_STATUS_CODE`, `OPERATING`, 8 `PROG_*_ACTIVE` flags) plus `ICIS_OBSERVED`/`EMISSIONS_OBSERVED`/
  `GHG_OBSERVED`/`ACTIVE`/`ACTIVE_BROAD`, facility × year.
- **Input:** `data/datasets/hpv_active.csv.gz` (via `read_hpv()`) — `HPV_ACTIVE`, facility × year.
- **Output:** no output of its own; the `build_panel()` function it defines is what `03_build.R` calls to
  produce both panel files — see `03_build.R`'s README for example rows.

## At a glance
| | |
|---|---|
| **Input** | `data/datasets/regulatory.csv.gz`, `operating.csv.gz`, `hpv_active.csv.gz` |
| **Output** | none directly — defines `build_panel()`, called by `03_build.R` |
| **Runtime** | not measured; each `build_panel()` call re-reads all three source files filtered to that panel's facility set, so `03_build.R`'s two-panel loop reads them twice total |
| **Requires** | `code/03_datasets/` fully built; `YEARS` must be in scope (defined in `03_build_parameters.R`) |
| **Dependencies** | `readr`, `dplyr`, `tidyr`, `here` |

## Walkthrough
**`COUNT_COLS`** — the full list of `N_*` event-count column names carried straight through from
`regulatory.csv.gz` (inspections, violations, enforcement, penalties, certs, stack tests, and their `_DUP`/
`_DUP_EXACT` companions).

**`read_counts(ids, years)`** — reads `regulatory.csv.gz` filtered to `ids`/`years`, with every count column
explicitly typed `col_double()` (no `col_guess()`).

**`WAYBACK_COLS`/`ACTIVITY_COLS`** and **`read_wayback(ids, years)`** — reads `operating.csv.gz` filtered to
`ids`/`years`, explicit typing throughout (`OP_STATUS_CODE` is the one character column; everything else
defaults to `col_integer()`).

**`read_hpv(ids, years)`** — reads `hpv_active.csv.gz` filtered to `ids`/`years`, just `HPV_ACTIVE`.

**`FILL_COLS`** and **`code_obs_source(panel)`** — the one piece of real logic in this file. Derives
`OBS_SOURCE` via `case_when()` (`ICIS_OBSERVED == 1` → `"event"`; else `ACTIVE_BROAD == 1` → `"operating"`;
else `"unobserved"`), then for rows where `OBS_SOURCE == "operating"`, fills `NA → 0` across `FILL_COLS`
(`COUNT_COLS` + `HPV_ACTIVE`) — `PENALTY_AMOUNT`/`PENALTY_AMOUNT_DUP` are excluded from this fill.

**`build_panel(facs, years)`** — the exported entry point. `expand_grid(PGM_SYS_ID = ids, YEAR = years)` to
build the balanced rectangle, left-joins in `read_counts()`/`read_wayback()`/`read_hpv()`, derives the four
`ANY_*` flags (`NA`-safe: `NA > 0` stays `NA`), calls `code_obs_source()`, left-joins the static facility
attributes from `facs` (the filtered spine slice), and returns the assembled panel sorted by
`(PGM_SYS_ID, YEAR)`.

## Notes & gotchas
- ⚠️ **`OBS_SOURCE` derivation (`PB4`), the one piece of real logic in this file.** Quoted in full:
  *"`OBS_SOURCE` derives from `ACTIVE_BROAD` + the facility-year's own `ICIS_OBSERVED`**, not a bespoke
  wayback join. `event` = `ICIS_OBSERVED==1`; `operating` = `!event & ACTIVE_BROAD==1`; `unobserved` = neither.
  **UPDATED 2026-07-29 (PB2 revision):** `unobserved` now genuinely appears in both panels — under the old
  all-11-years continuity screen it was impossible by construction (every row had already passed
  `ACTIVE_BROAD==1` for that year); under the new ≥1-year rule, a facility can be eligible via one qualifying
  year while other years in its 11-year rectangle have `ACTIVE_BROAD` false/`NA`, which reads as
  `unobserved`."* And on why this reproduces rather than reinvents the archived logic: *"Verified:
  `ICIS_OBSERVED==1` always implies `ACTIVE_BROAD==1` (an invariant asserted when `ACTIVE_BROAD` was built), so
  `case_when()` checking `event` first is exhaustive and mutually exclusive by construction."*
- ⚠️ **The known-operating-zero fill**, from `docs/data_dictionary_derived.md` Part 2, quoted verbatim:
  *"for rows with `OBS_SOURCE == "operating"`, every `N_*` count and `HPV_ACTIVE` is filled `NA → 0` (a
  confirmed-active facility-year with no ICIS event is a true zero, not unknown). `PENALTY_AMOUNT`/
  `PENALTY_AMOUNT_DUP` are **deliberately excluded** from this fill — a known-active, zero-ICIS-event
  facility-year still reads `NA` for `PENALTY_AMOUNT` (no confirmed formal action), matching the dataset
  layer's own `R4` convention."*
- **`OBS_SOURCE`'s own definition**, from the same source, on the exact three-way split: *"`"event"` =
  `ICIS_OBSERVED == 1` (a real ICIS record that year); `"operating"` = no ICIS event but `ACTIVE_BROAD == 1`
  (confirmed active some other way — a genuine structural zero); `"unobserved"` = neither."*
- **No `HPV_ACTIVE_1MO` (`PB7`):** *"Only the binary `HPV_ACTIVE`, read straight from `hpv_active.csv.gz`.
  ... `hpv_active.csv.gz` never shipped this variant; adding a third copy of the same logic was ruled out as
  unnecessary duplication."*
- **`N_PROGRAMS` stays `NA`-able (`PB6`)** — not derived in this file directly, but rides along on the `facs`
  join from `00_spine.R`'s `spine`; see that script's README.
- ⚠️ **No `col_guess()` anywhere (`PB8`).** This file's own header comments on `read_counts()`/
  `read_wayback()` document the concrete bug this guarded against: *"`col_guess()` on `regulatory.csv.gz`'s
  `PENALTY_AMOUNT`/`PENALTY_AMOUNT_DUP` (NA in ~99.6% of rows)... sampled all-`NA` rows and typed all four
  columns `col_logical()` — silently discarding every real value later in the file as an unparseable
  "logical," with **no error and no `problems()` entry**."* This file's `FLAGGED ISSUES` section documents the
  same discovery from the `read_counts()` side specifically (a spurious "parsing issues" warning with
  `problems()` reporting zero rows, investigated anyway per the project's "flag issues, don't silently accept"
  discipline).
- **`ANY_*` flags are `NA`-safe by construction** — `NA > 0` evaluates to `NA` in R, and `as.integer(NA)` stays
  `NA`, so an unobserved facility-year's `ANY_INSPECTIONS`/`ANY_VIOLATIONS`/`ANY_ENFORCEMENT`/`ANY_CERTS`
  correctly reads `NA`, never a silent `0` — called out explicitly in this script's own inline comment.
- **`build_panel()` assumes a shared universe/window across sources** — its header comment notes: *"every
  source shares this exact universe/window already, per O1/O6/H6, so a left_join from expand_grid is
  sufficient — no full_join-across-sources reconciliation like the archived pipeline needed."*
- Verified by reading the script in full, including its `FLAGGED ISSUES` section, and cross-checking the
  `OBS_SOURCE`/known-operating-zero-fill language against both `panel_construction_decisions.md` (`PB4`) and
  `docs/data_dictionary_derived.md` Part 2. Not run in this session — column values in the walkthrough are
  read from the code, not from an executed trace.
