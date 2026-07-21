# 00_setup — environment setup

**Stage input:** none · **Stage output:** `output/sessionInfo.txt` · **Run:** sourced first by `code/RUN_ALL.R`.

`00_setup.R` prepares the R environment before any data work. It does **not** read or write data.

## What it does

1. **Checks required packages** are installed (`here`, `readr`, `dplyr`, `tidyr`, `lubridate`, `data.table`,
   `sf`, `ggplot2`, `scales`) and stops early with an actionable message if any are missing. It only *checks* —
   package **versions** are meant to be pinned by `renv` (`renv.lock`); run `renv::restore()` once to install
   them.
2. **Sets deterministic, quiet global options** (`readr.show_col_types = FALSE`, `scipen` so long IDs/counts
   aren't written in scientific notation, `stringsAsFactors = FALSE`).
3. **Records the session** (`sessionInfo()`) to `output/sessionInfo.txt` so every run is traceable to exact
   package versions.

## Notes

- **No seed is set.** The pipeline has no stochastic step (point-in-polygon placement and `dup`/`dup_exact`
  flagging are deterministic, driven by file row order). If you add sampling or bootstrapping, set a seed
  explicitly in that script — this is a project rule.
- Sourcing `00_setup.R` at the top of a stage you're running standalone is safe and cheap.
- **`renv.lock` does not currently exist in this repo** (no `renv/` folder or `.Rprofile` either) — despite
  the language above, package versions are **not actually pinned** yet. `renv::restore()` will fail until
  `renv::init()` + `renv::snapshot()` has been run once and the lockfile committed. Until then, reproducing
  this pipeline elsewhere relies on whatever package versions happen to be installed.
