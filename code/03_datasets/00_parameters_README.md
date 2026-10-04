> **Status:** draft — [ ] verified against the current script (Claude, 2026-07-30)

# `00_parameters.R` — shared window, paths, and the layer's uppercase-on-write convention

## Purpose in the pipeline
> **TODO (Grace):** write the 1-2 sentence purpose blurb here — why this script exists and what depends on
> it. Starting material, from the script's own header comment:
> "code/03_datasets/00_parameters.R -- shared window + paths for the eight-dataset build. ... Everything
> joins on PGM_SYS_ID (+ year where the grain is facility x year). All eight are built once over the FULL
> facility universe, so any sample restriction is a filter the user applies downstream -- there are no
> pre-built sample panels."

## Inputs & outputs
This script is **sourced by every other script in `code/03_datasets/`, not run directly** — it has no input
file and no output file of its own. It defines three things every other script in this layer depends on:
- `YEARS <- 2005:2025` — the analysis window applied at build time (not baked into `data/processed/`).
- `CLEAN`/`DATASETS` — the `data/processed/` (input) and `data/datasets/` (output) directory paths.
- `write_dataset(df, name)` — the function every builder calls at the end of its script; it uppercases every
  column name (`rename_with(df, toupper)`) and writes `data/datasets/<name>.csv.gz`.
- `EVENT_ASSETS` — the six ICIS-Air event asset names (`inspections`, `violations`, `formal_actions`,
  `informal_actions`, `certs`, `stacktests`) whose presence defines `ICIS_OBSERVED` in `01_regulatory.R`.

Because there's no dataset produced here, there's no example-rows table for this file — see the other four
scripts' READMEs for what the columns it enables actually look like on disk.

## At a glance
| | |
|---|---|
| **Input** | none (defines constants/paths only) |
| **Output** | none — sourced by every other `code/03_datasets/*.R` script, not run standalone |
| **Runtime** | negligible (defines a handful of constants and one function; no I/O) |
| **Requires** | nothing upstream |
| **Dependencies** | `here`, `readr`, `dplyr` (via `write_dataset()`'s `rename_with`) |

## Walkthrough
The whole file is three declarations. `YEARS <- 2005:2025` sets the analysis window as a single literal that
every dataset builder in this layer sources — the cleaned assets (`data/processed/`) keep every dated event
regardless of window, and the window is applied only here, at build time (decision G1). `CLEAN`/`DATASETS`
resolve the two directory paths (`here::here("data/processed")` / `here::here("data/datasets")`) so every
builder reads/writes through the same two path variables rather than re-deriving them. `write_dataset()` is
the single transform point for the layer-wide `UPPER_SNAKE_CASE` convention (G2): every builder assembles
its data frame with lowercase-internal column names, then calls `write_dataset(df, "name")` at the very end,
which uppercases every column via `dplyr::rename_with(df, toupper)` and writes the gzipped CSV. `toupper()`
is idempotent on columns that are already uppercase (e.g. `REGISTRY_ID`, `STATE`, carried straight from ICIS
attributes), so mixed-origin column casing never needs a per-file fixup. `EVENT_ASSETS` is a plain character
vector naming the six ICIS-Air event tables that `01_regulatory.R` reads to define `ICIS_OBSERVED`.

## Notes & gotchas
- **G1** — "**Window `YEARS = 2005:2025`** applied at dataset build, not in the assets. ... Assets stay
  reusable for any window; the window is one line here."
- **G2** — "**Every column in the dataset layer is `UPPER_SNAKE_CASE`.** Builders assemble internally in
  lowercase, then uppercase **once on write** via `write_dataset()`. ... One convention across all eight
  files so join keys (`PGM_SYS_ID`, `YEAR`) and every derived column line up on merge with no per-file
  casing fixups. Single transform point = no typo drift across ~60 column literals. `toupper()` is
  idempotent on the already-uppercase ICIS attributes."
- **G3** — "**Full universe, no sample panels.** Datasets 1–5 built over all facilities; restrictions are
  downstream filters. ... The eight-dataset design pushes sample definition to the analysis, not the build —
  one canonical set of files, many samples."
- **G4** — "**Every dataset carries `REGISTRY_ID` (FRS cross-program facility id) alongside `PGM_SYS_ID`**,
  joined in from `facilities.csv.gz`; `NA` where a facility has no FRS match (same convention as
  `coordinates`' `HAS_COORDINATE==0`)."
- ⚠ **FLAGGED ISSUE in the script itself**: "`YEARS` (~line 17) A SEPARATE literal from `03_panel_building`'s
  own `YEARS <- 2005:2025` (`00_spine.R` / `03_build_parameters.R`) -- same value today, not shared code, so
  the two layers can silently drift apart if one is edited without the other." (Note: the panel-building
  layer referenced here has since been renamed/moved to `code/04_panel_building/` per the decisions doc's
  2026-07-28 addendum — the drift risk itself is unchanged, only the path.)
- Verified by reading the script directly (`code/03_datasets/00_parameters.R`, 51 lines) and cross-checking
  against Part A of `dataset_construction_decisions.md`. Not run — nothing to run standalone.
