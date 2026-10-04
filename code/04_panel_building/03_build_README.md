> **Status:** draft — [ ] verified against the current script (Claude, 2026-07-30)

# `03_build.R` — driver: builds the spine, then both panels, and writes them to disk

## Purpose in the pipeline
> **TODO (Grace):** write the 1-2 sentence purpose blurb here — why this script exists and what depends on
> it. Starting material, from the script's own header comment:
> "driver for the panel-building stage. Builds the shared candidate facility spine, then the two panels.
> Order: 00_spine.R -> in-memory `spine` (CONUS + Major/Synthetic-Minor class, eligibility precomputed);
> PANEL_SPECS -> data/panels/<name>.csv.gz (major_synmin_2015_2025, electric_2015_2025). Standalone:
> Rscript code/04_panel_building/03_build.R (assumes data/datasets/ is already built -- see
> code/RUN_ALL.R's stage order, datasets now build BEFORE panels). Or sourced by code/RUN_ALL.R."

## Inputs & outputs
- **Input:** sources `00_spine.R` (produces in-memory `spine`), `03_build_functions.R` (`build_panel()`), and
  `03_build_parameters.R` (`YEARS`, `PANEL_SPECS`) — which together read
  `data/datasets/{regulatory,operating,hpv_active,coordinates}.csv.gz`.
- **Output:** `data/panels/major_synmin_2015_2025.csv.gz` — facility × year, 2015–2025, CONUS + Major/
  Synthetic-Minor class + `EVER_ACTIVE`. 113 cols, 45,872 facilities, 504,592 rows (as of the 2026-07-29 Q4
  re-pin rebuild).
- **Output:** `data/panels/electric_2015_2025.csv.gz` — facility × year, 2015–2025, the above + NAICS 2211 or
  SIC 4911. 113 cols, 2,965 facilities, 32,615 rows.

Example — rows from `data/panels/major_synmin_2015_2025.csv.gz` (`gzcat ... | head`, sampled from the actual
file on disk, 2026-07-30). Both panels share the identical column recipe (`build_panel()`), and this same
facility (`01000000OCS0000003`, an offshore wind facility, NAICS `221115` — a Wind Electric Power Generation
code under the 2211 prefix) also appears in `electric_2015_2025.csv.gz` with byte-identical row values:

| PGM_SYS_ID | YEAR | STATE | OPERATING | ACTIVE_BROAD | N_INSPECTIONS | HPV_ACTIVE | OBS_SOURCE |
|---|---|---|---|---|---|---|---|
| 01000000OCS0000003 | 2015 | MA | NA | NA | NA | NA | unobserved |
| 01000000OCS0000003 | 2025 | MA | 1 | 1 | 1 | 0 | event |
| 01000000OCS0000004 | 2025 | MA | 1 | 1 | 1 | 0 | event |

The 2015 row shows the `unobserved` case: no wayback snapshot, no ICIS event, no emissions/GHG report that
specific year, so `OPERATING`/`ACTIVE_BROAD`/all `N_*` counts/`HPV_ACTIVE` are genuinely `NA`, not `0`. The
full 113-column row also carries facility attributes (`FACILITY_NAME`, `STATE`, `NAICS_CODES`, ...),
coordinates, and entry/exit fields — see `03_build_functions.R`'s README and `docs/data_dictionary_derived.md`
Part 2 for the complete column list.

## At a glance
| | |
|---|---|
| **Input** | `00_spine.R`, `03_build_functions.R`, `03_build_parameters.R` (which together read `data/datasets/{regulatory,operating,hpv_active,coordinates}.csv.gz`) |
| **Output** | `data/panels/major_synmin_2015_2025.csv.gz`, `data/panels/electric_2015_2025.csv.gz` |
| **Runtime** | not measured directly; dominated by `00_spine.R`'s and `build_panel()`'s reads of `regulatory.csv.gz` (44 MB compressed, 5.87M rows) and `operating.csv.gz` (27 MB compressed) — likely on the order of a minute or two end to end |
| **Requires** | `code/03_datasets/` fully built (stage `03` of `code/RUN_ALL.R`, must run before this stage `04`) |
| **Dependencies** | `readr`, `dplyr` (loaded here); `tidyr`, `here` (loaded transitively by the sourced files) |

## Walkthrough
**Step 1 — prerequisite construction.** Sources `00_spine.R`, which leaves `spine` (plus `CONUS`,
`MAJOR_SYNMIN_CLASSES`, `SCREEN_YEARS`) in this session.

**Step 2 — load the shared recipe and specs.** Sources `03_build_functions.R` (defines `build_panel()`) and
`03_build_parameters.R` (defines `YEARS <- 2015:2025` and the two-element `PANEL_SPECS` list). A `REVIEW
(design)` comment flags that `YEARS` here, `SCREEN_YEARS` in `00_spine.R`, and the repo-wide `YEARS <-
2005:2025` in `00_setup.R` are three independently-defined literals that currently agree but aren't enforced
to stay in sync.

**Step 3 — build and write.** Loops over `PANEL_SPECS`; for each spec, applies `spec$filter(spine)` to get the
facility set, calls `build_panel(facs, YEARS)`, creates `data/panels/` if needed, and writes
`data/panels/<spec$name>.csv.gz`. Prints a one-line summary (rows, facilities, cols, year range) per panel.

## Notes & gotchas
- **Two panels only, not a funnel (`PB1`):** *"Explicit project decision, 2026-07-28: only these two panels
  are actually needed going forward. A broader sample-panel framework can be added back later if a real use
  case appears — it isn't scope-frozen, just not built speculatively."*
- ⚠️ **`EVER_ACTIVE` eligibility rule — revised 2026-07-29, explicit user decision reversing the original
  2026-07-28 design (`PB2`).** Quoted in full: *"**REVISED 2026-07-29 (explicit user decision): eligibility =
  `ACTIVE_BROAD == 1` in *at least one* year 2015–2025** — `any(ACTIVE_BROAD == 1, na.rm = TRUE)`.
  `ACTIVE_BROAD` (`data/datasets/operating.csv.gz`, decision `O6`) unions Wayback-confirmed operating status,
  ICIS events, and emissions/GHG reporting — each for that specific year. **Original rule (2026-07-28,
  superseded):** continuity = `ACTIVE_BROAD == 1` in *every* year 2015–2025, `all(ACTIVE_BROAD == 1)` — one
  gap or confirmed-inactive year anywhere failed the whole facility."* The reasoning for the reversal: *"the
  all-11-years rule requires full-window continuity, which drops exactly the facilities most likely to exit
  *because of* enforcement/penalty outcomes — survivorship bias in a panel meant to study enforcement and
  compliance. Two-way fixed-effects estimators don't need a balanced panel, so there was no mechanical reason
  to require one."* And the consequence: *"unlike the original rule, a facility can now have real within-window
  gaps — `OBS_SOURCE == "unobserved"` is no longer impossible in these panels."* This is a good example of an
  explicit user decision reversing an earlier design already shipped once (panels were even renamed from
  `*_continuous_2015_2025` to drop "continuous" since it was no longer accurate).
- **Window = 2015–2025 only, not the repo-wide 2005–2025 (`PB3`):** *"The eligibility screen is only defined
  over 2015–2025 (Wayback's real coverage window) — both panels are already restricted to facilities that pass
  it, so a decade of pre-2015 rows would add nothing but padding."*
- **Grain stays a full 11-year rectangle per facility, even post-`PB2`:** *"Both panels remain a full 11-year
  rectangle per facility (`balanced == TRUE` in `overview.csv`) — `EVER_ACTIVE` is evaluated once over each
  facility's whole 2015–2025 record, not per year, so `build_panel()`'s `expand_grid` still gives every
  eligible facility one row per year regardless of which year(s) made it eligible."*
- ⚠️ **Three independently-defined `2015:2025` literals** (this file's `YEARS`, `00_spine.R`'s
  `SCREEN_YEARS`, and implicitly the repo-wide `00_setup.R` `YEARS <- 2005:2025` they diverge from) — flagged
  in the script's own `REVIEW(design)` comment and `FLAGGED ISSUES` section as a drift risk: nothing enforces
  they stay in sync if one changes without the others.
- Verified by reading the script in full and the two output files' headers/sample rows directly off disk
  (`gzcat data/panels/{major_synmin,electric}_2015_2025.csv.gz | head`, 2026-07-30; both headers are
  byte-identical via `md5`). Row/facility/column counts in Inputs & Outputs above are quoted from
  `panel_construction_decisions.md`'s "Shape" section (as of the 2026-07-29 Q4 re-pin rebuild), not
  recomputed in this session. Runtime is inferred from upstream file sizes, not measured by running the
  script.
