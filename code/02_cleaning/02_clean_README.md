> **Status:** draft — [ ] verified against the current script (Claude, 2026-07-30)

# `02_clean.R` — driver for the cleaning stage

## Purpose in the pipeline
> **TODO (Grace):** write the 1-2 sentence purpose blurb here — why this script exists and what depends on
> it. Starting material, from the script's own header comment:
> "02_clean.R -- driver for the cleaning stage. Turns every raw source table into a bare-bones 'clean' asset
> in data/processed/ (keep all columns, keep all rows; add only date/year/dup/dup_exact where relevant).
>
> Run order:
>   1. the 17 regular sources, described as data in 02_cleaning_parameters.R (executed via clean_one())
>   2. the 3 bespoke Wayback operating-status cleaners in wayback/ (17 -> 18 -> 18 depends on 17's output)
>
> Standalone:  Rscript code/02_cleaning/02_clean.R      (assumes data/raw/ is already populated)
> Or sourced by code/RUN_ALL.R."

## Inputs & outputs
- **Input:** `data/raw/*` (all raw sources populated by `01_download.R`) — this script reads no data
  directly itself; it orchestrates `clean_one()` calls (defined in `02_cleaning_functions.R`) and sources
  the 3 Wayback scripts, each of which does its own raw reads.
- **Output:** `data/processed/*.csv.gz` — 20 files total (17 from the regular-source loop + 3 from the
  Wayback scripts). This driver produces no output of its own beyond what those two paths write.

Example — first 4 rows of `data/processed/violations.csv.gz`, one of the 17 regular-source outputs
(`gzcat data/processed/violations.csv.gz | head -4`, sampled 2026-07-30):

| PGM_SYS_ID | ACTIVITY_ID | COMP_DETERMINATION_UID | PROGRAM_CODES | EARLIEST_FRV_DETERM_DATE | date | year | dup_exact | dup |
|---|---|---|---|---|---|---|---|---|
| DC0000001100100011 | 3605021486 | DC000A135774 | CAATVP | 07-23-2026 | 2026-07-23 | 2026 | 0 | 0 |
| FL0000001210700005 | 3605021352 | FL000A0000121070000560671 | CAATVP | 06-29-2026 | 2026-06-29 | 2026 | 0 | 0 |
| SD0000004610900004 | 3605020865 | SD000A135771 | CAATVP | 06-30-2026 | 2026-06-30 | 2026 | 0 | 0 |

(Table trimmed to 9 of the file's 19 columns for readability — full columns are `PGM_SYS_ID, ACTIVITY_ID,
AGENCY_TYPE_DESC, STATE_CODE, AIR_LCON_CODE, COMP_DETERMINATION_UID, ENF_RESPONSE_POLICY_CODE,
PROGRAM_CODES, PROGRAM_DESCS, POLLUTANT_CODES, POLLUTANT_DESCS, EARLIEST_FRV_DETERM_DATE, HPV_DAYZERO_DATE,
HPV_RESOLVED_DATE, DSCV_PATHWAY_DATE, NFTC_PATHWAY_DATE, date, year, dup_exact, dup`. Unit of analysis is one
compliance-determination event; 101,921 rows on disk.)

## At a glance
| | |
|---|---|
| **Input** | `data/raw/*` (all sources) |
| **Output** | `data/processed/*.csv.gz` — 20 files, ~350MB total (largest: `emissions.csv.gz` 144MB, `afs_hist_compliance.csv.gz` 52MB) |
| **Runtime** | not measured directly; the largest single inputs (`afs_hist_compliance`, `emissions`) plus 11 years of Wayback snapshot reads in the wayback loop suggest low-to-mid single-digit minutes |
| **Requires** | `01_download.R` (raw data staged in `data/raw/`) |
| **Dependencies** | none of its own beyond what it sources — `02_cleaning_functions.R` loads `readr`, `dplyr`, `lubridate`; the wayback scripts additionally load `data.table`, `tidyr` |

## Walkthrough
1. **Sources two files**: `02_cleaning_functions.R` (defines `clean_one()`, `read_raw()`, `dup_index()`,
   `write_clean()` — see `02_cleaning_functions_README.md` for the full function-by-function reference) and
   `02_cleaning_parameters.R` (defines `CLEAN_SPECS`, the list of 17 regular-source specs — see
   `02_cleaning_parameters_README.md` for the field-by-field spec reference and source→output table). This
   driver's own README does not duplicate either — see those two files for what each spec does.
2. **Regular-source loop**: `for (spec in CLEAN_SPECS) clean_one(spec)` — one call per spec, no per-spec
   `try/catch`. A missing raw file (e.g. `01_download.R` wasn't run) halts the entire loop with an uncaught
   error rather than skipping that source and continuing.
3. **Wayback loop**: lists files in `wayback/` matching `^[0-9].*[.]R$` (i.e. `17_*.R`, `18_*.R`, `19_*.R` —
   excludes that folder's `README.md`), sorts them (relies on the two-digit numeric prefix sorting correctly
   as a plain string — see gotchas), and `source()`s each in turn in the *same* R environment (not a
   subprocess), so each wayback script can see objects left behind by the previous one. Order matters: 18
   reads 17's output file directly, so 17 must run first.

## Notes & gotchas
- **Why 17 sources are data and 3 are scripts** — quoted from `code/02_cleaning/README.md`'s "Structure"
  section: "17 of the 20 sources follow one of two regular shapes — **event** (add date/year/dup/dup_exact)
  or **attribute** (add only dup_exact). Those differ only in *which* file, *which* date column, and *which*
  duplicate key, so they are expressed as data in `CLEAN_SPECS` and executed by one function, `clean_one()`.
  The 3 **Wayback** operating-status cleaners reconstruct a facility × year status history from 11 annual
  snapshots (LOCF gap-filling, spell collapsing). That logic is genuinely bespoke, so those keep their own
  scripts in `wayback/`."
- **The numeric-prefix sort is a latent trap**, per the driver script's own inline comment: "`sort()` relies
  on the two-digit numeric prefixes sorting correctly as plain strings (17 < 18 < 19), which holds here but
  would break silently if a script numbered >=100 were ever added (lexicographic '100' sorts before '17')."
  ⚠️ Adding a 4th Wayback script numbered 100+ would silently reorder execution.
- **No per-spec error handling in the regular loop** — a single bad/missing raw source stops the whole
  cleaning stage rather than producing 16 of 17 outputs and reporting the failure. This is a deliberate
  fail-fast choice per the script's own comment, not an oversight, but worth knowing if you're debugging a
  partial `data/processed/` after a failed run.
- **Cleaning here is deliberately lossless** — from the folder README: "Each raw source table becomes one
  `data/processed/<name>.csv.gz` that **keeps every original column and every original row** — nothing is
  dropped, deduplicated, recoded, or type-cast... The only columns ever **added** [are] `date`, `year`,
  `dup` (0-based occurrence index within a within-facility event key — **not** a dedup, it labels repeats so
  the panel layer can decide how to collapse them), `dup_exact` (1 if byte-identical to an earlier row)."
- Verified by reading `02_clean.R` in full, reading `02_cleaning/README.md`, `02_cleaning_functions_README.md`,
  and `02_cleaning_parameters_README.md` in full, and sampling `violations.csv.gz` directly off disk (101,921
  rows). Did not re-run the full cleaning stage this session.
