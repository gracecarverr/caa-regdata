# 02_cleaning_functions.R — reference

Shared mechanics for the regular cleaners. Sourced by `02_clean.R`. Loads `readr`, `dplyr`, `lubridate`.

All functions assume the working directory is resolved via [`here`](https://here.r-lib.org/), so paths are
project-root-relative regardless of where the script is launched.

## `read_raw(relpath)`

Reads a raw source table as **all-character** (`col_types = cols(.default = col_character())`), so no column
is silently type-guessed, truncated, or coerced. `relpath` is relative to `data/raw/`.

Returns a tibble with exactly the source columns, all character.

> **Why all-character?** Type inference on messy regulatory exports can drop leading zeros from IDs, misparse
> mixed date formats, or turn codes into numbers. Reading as text keeps the processed asset lossless; typed
> parsing is done deliberately and locally where it's needed (e.g. the `date` column).

## `dup_index(d, key)`

Returns a 0-based integer vector: each row's occurrence index within the group defined by the `key` columns
(first row of a group = `0`, second = `1`, …). Group keys are formed by joining the `key` columns with `"\r"`
(a separator that cannot occur inside a CSV field). Equivalent to the original per-script
`ave(seq_len(n), paste(k1, k2, sep="\r"), FUN = seq_along) - 1L`.

Used to populate the `dup` column on event tables.

## `write_clean(d, name)`

Creates `data/processed/` if needed, writes `d` to `data/processed/<name>.csv.gz` (gzip-compressed CSV via
`readr::write_csv`), and prints a one-line `name: N rows | M columns` summary. Returns `d` invisibly.

## `clean_one(spec)`

Executes one cleaning spec (see `02_cleaning_parameters.R`). **The order of operations is load-bearing** and
reproduces the original per-source scripts exactly:

1. `read_raw(spec$raw)` — load as character.
2. If `spec$date` is a function: set `date <- spec$date(d)` and `year <- lubridate::year(date)`.
3. `dup_exact <- as.integer(duplicated(d))` — computed over the frame **as it stands**, so on event tables
   it includes the freshly-added `date`/`year` columns (matching the originals).
4. If `spec$key` is given: `dup <- dup_index(d, spec$key)`.
5. `write_clean(d, spec$name)`.

Attribute tables supply neither `date` nor `key`, so they receive only `dup_exact`.

### Reproducibility note

This refactor was verified to produce **byte-identical decompressed output** to the original 16 per-source
scripts (compared via `gzip -dc | md5` against the pre-refactor assets). If you change any function here,
re-verify the same way — a cleaning change that alters outputs must be surfaced, not silently accepted.
