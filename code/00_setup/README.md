# 00_setup — environment setup

**Stage input:** none · **Stage output:** `output/sessionInfo.txt` · **Run:** sourced first by `code/RUN_ALL.R`.

`00_setup.R` prepares the R environment before any data work. It does **not** read or write data.

## What it does

1. **Checks required packages** are installed (`here`, `readr`, `dplyr`, `tidyr`, `lubridate`, `data.table`,
   `sf`, `ggplot2`, `scales`, `R.utils`) and stops early with an actionable message if any are missing. It only
   *checks* — package **versions** are pinned by `renv` (`renv.lock`); run `renv::restore()` once to install
   them.
2. **Sets deterministic, quiet global options** (`readr.show_col_types = FALSE`, `scipen` so long IDs/counts
   aren't written in scientific notation, `stringsAsFactors = FALSE`).
3. **Records the session** (`sessionInfo()`) to `output/sessionInfo.txt` so every run is traceable to exact
   package versions.

## Notes

- **`sf` needs system libraries (GDAL/GEOS/PROJ).** `renv::restore()` installing `sf` from source (typical on
  Linux) will fail before it ever gets to R's package check if those aren't present on the machine — see the
  Computational requirements section of the top-level [`README.md`](../../README.md) for install commands.
- **No seed is set.** The pipeline has no stochastic step (point-in-polygon placement and `dup`/`dup_exact`
  flagging are deterministic, driven by file row order). If you add sampling or bootstrapping, set a seed
  explicitly in that script — this is a project rule.
- Sourcing `00_setup.R` at the top of a stage you're running standalone is safe and cheap.
- `renv.lock` was initialized 2026-07-21 (`renv::init()` + hydrate from the then-installed library); run
  `renv::restore()` on a fresh checkout to install the pinned versions.
