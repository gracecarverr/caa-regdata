> **Status:** draft — [ ] verified against the current script (Claude, 2026-07-30)

# `00_setup.R` — environment setup for the pipeline

## Purpose in the pipeline
> **TODO (Grace):** write the 1-2 sentence purpose blurb here — why this script exists and what depends on
> it. Starting material, from the script's own header comment:
> "00_setup.R -- environment setup for the pipeline. Sourced first by code/RUN_ALL.R (and safe to source at
> the top of any stage you run on its own). Does NOT touch data.
>
> Responsibilities:
>   1. verify the R packages the pipeline needs are installed (fail early with a clear message)
>   2. set deterministic, quiet global options
>   3. record the session (package versions) to output/ for reproducibility
>
> The pipeline pins packages with renv (see renv.lock); this script only *checks* and reports."

## Inputs & outputs
- **Input:** none — does not read any data file.
- **Output:** `output/sessionInfo.txt` — plain-text dump of `sessionInfo()` (R version, platform, locale,
  attached/loaded package versions). Not a data file; one file, overwritten on every run.

Example — actual contents of `output/sessionInfo.txt` on disk (2026-07-30):

```
R version 4.4.3 (2025-02-28)
Platform: aarch64-apple-darwin20
Running under: macOS 26.2
...
loaded via a namespace (and not attached):
 [1] gtable_0.3.6        dplyr_1.2.0         compiler_4.4.3
 [4] renv_1.1.8          Rcpp_1.1.2          tidyselect_1.2.1
 [7] tidyr_1.3.2         scales_1.4.0        here_1.0.2
[10] ggplot2_4.0.1       readr_2.1.5         R6_2.6.1
 ...
[40] data.table_1.18.2.1 farver_2.1.2        e1071_1.7-17
[43] purrr_1.2.1         tools_4.4.3         pkgconfig_2.0.3
```

## At a glance
| | |
|---|---|
| **Input** | none |
| **Output** | `output/sessionInfo.txt` (plain text, ~2KB) |
| **Runtime** | seconds — package-existence checks + `sessionInfo()`, no data I/O |
| **Requires** | nothing upstream; this is the first script in the pipeline |
| **Dependencies** | `here` (path resolution); checks for (but does not attach) `readr`, `dplyr`, `tidyr`, `lubridate`, `data.table`, `sf`, `ggplot2`, `scales`, `R.utils` |

## Walkthrough
1. **Package check.** `REQUIRED_PKGS` lists every package used anywhere in `code/` (a hand-maintained
   inventory, not auto-derived). `requireNamespace()` checks each is *installed* without attaching it —
   downstream scripts do their own `library()` calls. Missing packages trigger a `stop()` with an actionable
   `renv::restore()` / `install.packages()` message rather than letting a later script fail with a cryptic
   "could not find function" error.
2. **`R.utils` namespace touch.** A standalone `requireNamespace("R.utils", quietly = TRUE)` call exists
   purely so `renv::snapshot()`'s static dependency scanner can discover and pin it — `R.utils` itself is
   never `library()`'d or `::`'d anywhere; it's an internal dependency `data.table::fread()` uses to read
   `.csv.gz` directly.
3. **Global options.** Sets `readr.show_col_types = FALSE` (no type-guessing chatter — the pipeline reads raw
   data as character deliberately), `stringsAsFactors = FALSE` (explicit for clarity though it's the R ≥4.0
   default anyway), and `scipen = 999` (no scientific notation in written IDs/counts).
4. **Session recording.** Writes `sessionInfo()` output to `output/sessionInfo.txt` inside a `local()` block
   so the scratch `out` variable doesn't leak into the caller's global environment.

## Notes & gotchas
- Few gotchas in this script by design — it's a preflight check, not a data-touching step.
- The script's own header flags a maintenance risk explicitly: `REQUIRED_PKGS` "is maintained by hand and
  can silently drift out of sync with what scripts actually `library()`... nothing fails loudly if a script
  starts using a new package here without also adding it to `REQUIRED_PKGS`; it would only surface downstream
  as a runtime 'could not find function' error in whatever script uses it." ⚠️ This is a silent-failure-risk
  worth knowing about if you add a new package dependency anywhere in the pipeline — update this list too.
- No seed is set here, and the script's own comment explains why: "The pipeline has no stochastic step
  (point-in-polygon and dup flagging are deterministic), so no seed is required. If you add sampling/
  bootstrapping, set a seed explicitly in that script (project rule)."
- The final `cat()` confirmation line reports `length(REQUIRED_PKGS)` — i.e., "all packages we checked for,"
  not "all packages actually used by the pipeline." Same drift risk as above.
- Verified by reading the script in full and by reading `output/sessionInfo.txt` directly off disk. Did not
  execute the script this session (no need — it's idempotent and produces the same file already on disk).
