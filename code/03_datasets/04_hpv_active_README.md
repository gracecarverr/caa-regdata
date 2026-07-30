> **Status:** draft — [ ] verified against the current script (Claude, 2026-07-30)

# `04_hpv_active.R` — builds dataset 2b, `hpv_active.csv.gz` (facility × year R2 collapse of `hpv_spells`)

## Purpose in the pipeline
> **TODO (Grace):** write the 1-2 sentence purpose blurb here — why this script exists and what depends on
> it. Starting material, from the script's own header comment:
> "code/03_datasets/04_hpv_active.R -- DATASET 2b: hpv_active. Facility x year. The directly-usable HPV
> status flag, a deterministic R2 collapse of hpv_spells (dataset 2). Joins 1:1 to regulatory / operating."

## Inputs & outputs
- **Input:** `data/datasets/hpv_spells.csv.gz` (dataset 2, spell grain — see `03_hpv_spells.R`'s README) +
  `data/datasets/regulatory.csv.gz` (for `ICIS_OBSERVED`) + `data/processed/facilities.csv.gz` (for the
  facility universe / `REGISTRY_ID`).
- **Output:** `data/datasets/hpv_active.csv.gz` — facility × year, one row per `(PGM_SYS_ID, YEAR)`; joins 1:1
  to `regulatory.csv.gz`/`operating.csv.gz` (identical key vectors). Just 3 real columns beyond the keys.

Example — 4 rows from `data/datasets/hpv_active.csv.gz` (sampled from the actual file on disk, 2026-07-30 —
first 2 rows are the file's first facility, all-`NA` since it's unobserved in 2005/2006; last 2 rows are a
facility with a covering HPV spell in 2014–2015):

| PGM_SYS_ID | REGISTRY_ID | YEAR | HPV_ACTIVE |
|---|---|---|---|
| 0100000009003E0010 | 110070834547 | 2005 | NA |
| 0100000009003E0010 | 110070834547 | 2006 | NA |
| 0500000026055R0002 | 110056434158 | 2014 | 1 |
| 0500000026055R0002 | 110056434158 | 2015 | 1 |

That's the full column list — `PGM_SYS_ID`, `REGISTRY_ID`, `YEAR`, `HPV_ACTIVE`.

## At a glance
| | |
|---|---|
| **Input** | `data/datasets/hpv_spells.csv.gz`, `data/datasets/regulatory.csv.gz`, `data/processed/facilities.csv.gz` |
| **Output** | `data/datasets/hpv_active.csv.gz` — 5,872,965 rows × 3 real cols (as of 2026-07-27): `HPV_ACTIVE` 1=35,417, 0=709,220, NA=5,128,328; 9,743 ever-active facilities |
| **Runtime** | not measured; small — reads one small spell table (44,777 rows) and two lightweight columns off `regulatory.csv.gz`, then a per-year overlap loop across `YEARS` (21 iterations) |
| **Requires** | `01_regulatory.R` and `03_hpv_spells.R` must run first (this script reads both their `data/datasets/` outputs) |
| **Dependencies** | `readr`, `dplyr`, `tidyr`, `lubridate`, `here` |

## Walkthrough
`DZ_MIN`/`DZ_MAX <- 1970L/2025L` set the day-zero plausibility screen. `s_all` reads
`hpv_spells.csv.gz` (note: **uppercase** column names here, since that file was already written through
`write_dataset()`), filters out `missing_start` spells (no interval to test), and parses `HPV_DAYZERO_DATE`/
`HPV_RESOLVED_DATE` with `ymd()` (not `mdy()` — the spell table stores ISO strings). `keep` is a logical
vector for spells whose `dz_year` is non-`NA` and within `[DZ_MIN, DZ_MAX]`; `s` is the screened subset, with
`end_cons` computed as the resolved date for `closed` spells or Dec-31 of the day-zero year for `open`/
`bad_order` (the R2 conservative-closing rule). `cover` is built by looping over every year in `YEARS`,
testing which spells in `s` overlap that calendar year (`dz <= ye & end_cons >= ys`), and `distinct()`-ing the
result so a facility with multiple overlapping spells in the same year still produces one `covered` row.
`frs_ids`/`ids` establish the ds-0-matching universe; `obs` reads `ICIS_OBSERVED` off `regulatory.csv.gz`.
`ha` builds the full `expand_grid` rectangle, left-joins `cover` and `obs`, and derives `hpv_active` via
`case_when`: `1` if covered (spell wins, regardless of `icis_observed`), `0` if uncovered but
`icis_observed==1` (true zero), `NA` otherwise (unknown). Five `stopifnot()` invariants close the build:
grain uniqueness, rectangle completeness, `HPV_ACTIVE ∈ {0,1,NA}`, every `HPV_ACTIVE==1` has a covering
spell, and no covered facility-year is `NA`. `write_dataset(ha, "hpv_active")` writes the file with a
status-breakdown summary line.

## Notes & gotchas
- **H6** — "**Zero-vs-NA mirrors ds 0.** `1` if an R2 spell covers the year (**spell wins even where
  `ICIS_OBSERVED==0`** — the interval is direct evidence; 2,431 such fac-yrs as of 2026-07-27); `0` if
  uncovered but `ICIS_OBSERVED==1`; `NA` if uncovered and unobserved. ... Consistent with the layer's
  discipline: an unobserved year shouldn't assert 'not in HPV status' any more than '0 inspections'. Matches
  the panel. *(User decision, 2026-07-20 — reversed from an initial 'pure 0/1'.)*"
- **H7 (⚠ caught a real data bug)** — "**Day-zero plausibility screen [1970, 2025] at the collapse** — a
  spell maps to years only if its day-zero year is in range. Excludes **268 of 44,744** mappable spells as of
  2026-07-27 (implausible/unparseable day-zero). ... **Caught a real bug + garbage-propagation.** Record
  `CAMDAM1489` has day-zero `11-05-0218` (mistyped `2018`) → parses to **year 218** → an unscreened spell runs
  218→2021 and spuriously flags 2005–2017. The screen makes the exclusion **explicit and reported**; dates
  are parsed with `ymd()` so nothing hides in a parse quirk. Current post-screen total: **35,417 by design**
  (2026-07-27)."
- ⚠ **In-script FLAGGED ISSUE #2 (mechanism correction, output unaffected)**: the header comment describing
  the day-zero screen implies the `CAMDAM1489` (year-218) record is excluded via the `[1970,2025]` range
  comparison. It's actually excluded through a **silent CSV round-trip failure**: `03_hpv_spells.R`'s `mdy()`
  parses `"11-05-0218"` to a Date with year 218; `write_csv()` serializes that as the string `"218-11-05"`
  (3-digit year, not zero-padded); `ymd()` here can't reparse a 3-digit year, so `dz_year` comes back `NA` and
  the record is dropped via the `is.na(dz_year)` branch of `keep`, not the `dz_year < DZ_MIN` comparison the
  name of the section implies. "Net effect on the output is the same (the spell is dropped either way), but
  this is why `dz_year` is never actually seen < 1970 despite this known bad record existing in the raw
  data." Confirmed directly: `mdy("11-05-0218") |> as.character() == "218-11-05"`, `ymd("218-11-05") == NA`.
- ⚠ **In-script FLAGGED ISSUE #1**: `DZ_MAX` is "a hardcoded literal matching but not derived from
  `max(YEARS)`" — same drift risk as `BEGIN_YEAR_MAX` in `02_operating.R`; the two would silently diverge if
  the analysis window is ever extended without updating this constant too.
- Verified by reading the full script (`code/03_datasets/04_hpv_active.R`, 125 lines) and sampling
  `data/datasets/hpv_active.csv.gz` directly (`gzcat ... | head` and an `awk`-filtered `HPV_ACTIVE==1` row).
  H6/H7 quotes pulled verbatim from `dataset_construction_decisions.md` Part D2 — not independently
  re-derived this pass.
