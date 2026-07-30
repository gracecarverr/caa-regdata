> **Status:** draft — [ ] verified against the current script (Claude, 2026-07-30)

# `00_spine.R` — builds the shared CONUS + Major/Synthetic-Minor candidate facility set both panels filter from

## Purpose in the pipeline
> **TODO (Grace):** write the 1-2 sentence purpose blurb here — why this script exists and what depends on
> it. Starting material, from the script's own header comment:
> "build the shared CANDIDATE FACILITY SET for the two panels this pipeline ships
> (major_synmin_2015_2025, electric_2015_2025). Both target panels require CONUS + Major/Synthetic-Minor
> class, so that filter is applied HERE, once, rather than duplicated per panel spec. electric is a strict
> subset of this candidate set (03_build_parameters.R adds the NAICS/SIC filter). This is a from-scratch
> rewrite, NOT the old code/03_panel_building/00_spine.R renamed... This version reads ONLY from
> data/datasets/ (the eight-dataset layer) -- no raw event assets, no FRS/shapefile spatial join, no HAP
> list -- all of that work already happened once, upstream, building regulatory.csv.gz/coordinates.csv.gz."

## Inputs & outputs
- **Input:** `data/datasets/regulatory.csv.gz` — facility × year (ICIS-Air only); one row/facility kept after
  `distinct(PGM_SYS_ID, .keep_all = TRUE)`; supplies facility attributes, `EMITS_*`, `PROG_*`, `N_PROGRAMS`.
- **Input:** `data/datasets/coordinates.csv.gz` — one row per facility; supplies `LATITUDE`/`LONGITUDE`/
  `HAS_COORDINATE`/`COUNTY_FIPS`/`ICIS_COUNTY_FIPS`/`COORD_COUNTY_DIST_KM`/`COORD_GROSS_ERROR`.
- **Input:** `data/datasets/operating.csv.gz` — facility × year; read twice: once collapsed to one row/facility
  for `ENTERED_YEAR`/`EXITED_YEAR`/`EXIT_SOURCE`/`EARLIEST_PROGRAM_BEGIN_YEAR(_RAW)`, once at facility × year
  grain (2015–2025 only) to compute the `EVER_ACTIVE` eligibility flag from `ACTIVE_BROAD`.
- **Output:** **no persisted output — in-memory only.** `spine` is an in-memory data frame (one row per
  candidate facility) left in the R session; only `03_build.R`, sourcing this script in the same session,
  consumes it. No `spine.csv.gz` is written. Per `PB1` in `panel_construction_decisions.md`: *"Explicit
  project decision, 2026-07-28: only these two panels are actually needed going forward. A broader sample-panel
  framework can be added back later if a real use case appears — it isn't scope-frozen, just not built
  speculatively."*

Example rows: not applicable — there is no file on disk to sample (`spine` never leaves memory). For
reference, `spine`'s column set is: `PGM_SYS_ID`, `REGISTRY_ID`, `FACILITY_NAME`, `STREET_ADDRESS`, `CITY`,
`COUNTY_NAME`, `STATE`, `ZIP_CODE`, `EPA_REGION`, `NAICS_CODES`, `SIC_CODES`, `FACILITY_TYPE_CODE`,
`FACILITY_TYPE`, `AIR_POLLUTANT_CLASS_DESC`, the 6 `EMITS_*` flags, the 8 `PROG_*` flags, `N_PROGRAMS`,
`LATITUDE`, `LONGITUDE`, `HAS_COORDINATE`, `COUNTY_FIPS`, `ICIS_COUNTY_FIPS`, `COORD_COUNTY_DIST_KM`,
`COORD_GROSS_ERROR`, `COORD_NO_COUNTY_MATCH`, `ENTERED_YEAR`, `EXITED_YEAR`, `EXIT_SOURCE`,
`EARLIEST_PROGRAM_BEGIN_YEAR`, `EARLIEST_PROGRAM_BEGIN_YEAR_RAW`, `EVER_ACTIVE` — one row per candidate
facility (CONUS + Major/Synthetic-Minor class).

## At a glance
| | |
|---|---|
| **Input** | `data/datasets/regulatory.csv.gz`, `coordinates.csv.gz`, `operating.csv.gz` |
| **Output** | none persisted — in-memory `spine` object only, consumed by `03_build.R` in the same session |
| **Runtime** | not measured directly; reads `regulatory.csv.gz` (5.87M rows, 44 MB compressed) and `operating.csv.gz` (27 MB compressed, read twice) in full before filtering — likely tens of seconds, I/O-dominated |
| **Requires** | `code/03_datasets/` fully built (`regulatory.csv.gz`, `coordinates.csv.gz`, `operating.csv.gz` must exist) |
| **Dependencies** | `readr`, `dplyr`, `tidyr`, `here` |

## Walkthrough
**Constants.** `CONUS` (48 contiguous states + DC, hard-coded list, identical to the archived pipeline's
constant), `MAJOR_SYNMIN_CLASSES` (`"Major Emissions"`, `"Synthetic Minor Emissions"`), `SCREEN_YEARS`
(2015:2025 — the eligibility-screen window, distinct from the repo-wide 2005:2025).

**`attrs`** — reads `regulatory.csv.gz`, explicitly typing every selected column (no `col_guess()`), collapses
to one row per `PGM_SYS_ID` (stable via `arrange` then `distinct`), drops `YEAR`. `OP_STATUS_CURRENT_DESC` is
deliberately excluded from the column selection.

**`candidates`/`cand_ids`** — the CONUS + Major/Synthetic-Minor class filter applied once here, shared by both
downstream panels; `stopifnot` asserts `PGM_SYS_ID` uniqueness in `attrs`.

**`coords`** — reads `coordinates.csv.gz` filtered to `cand_ids`, explicitly typing FIPS columns as character
(to protect leading zeros), and derives `COORD_NO_COUNTY_MATCH` (a flag not shipped by `coordinates.csv.gz`
itself) inline.

**`op_facility`** — reads `operating.csv.gz` filtered to `cand_ids`, collapsed to one row/facility for the
five facility-level spell/begin-year fields; `LEFT_CENSORED`/`RIGHT_CENSORED` are deliberately excluded from
the column selection.

**`eligible`** — reads `operating.csv.gz` again, this time at facility × year grain restricted to
`SCREEN_YEARS`, and computes `EVER_ACTIVE = any(ACTIVE_BROAD == 1, na.rm = TRUE)` per facility. A second
`stopifnot` re-reads `(PGM_SYS_ID, YEAR)` unfiltered to assert grain uniqueness in the source file (documented
in FLAGGED ISSUES as a deliberate small redundant read).

**Assembly** — `candidates` left-joined to `coords`, `op_facility`, `eligible`; `EVER_ACTIVE` coalesced to
`FALSE` for any candidate absent from `eligible` (defensive — shouldn't happen given `operating.csv.gz` is a
balanced rectangle). Closing `stopifnot()` block asserts: no duplicate `PGM_SYS_ID`; no non-CONUS state or
non-major/synmin class leaked in; `COORD_NO_COUNTY_MATCH` never set without a coordinate; `EVER_ACTIVE` is a
clean logical with no `NA`. A summary line prints facility count and % ever-active.

## Notes & gotchas
- ⚠️ **No persisted spine file — by design, not an oversight.** From `PB1`: *"Two panels only, not a funnel.
  No `universe`/non-continuous `major_synmin`/`electric`, no persisted `spine.csv.gz`."* If a future script
  tries to read `data/panels/spine.csv.gz` or similar, it does not exist — `spine` is only valid within the
  `03_build.R` R session that sources this file.
- **`EVER_ACTIVE` eligibility rule, computed in this script — revised 2026-07-29 (`PB2`, explicit user
  decision).** Quoted in full: *"eligibility = `ACTIVE_BROAD == 1` in *at least one* year 2015–2025 —
  `any(ACTIVE_BROAD == 1, na.rm = TRUE)`. ... Original rule (2026-07-28, superseded): continuity =
  `ACTIVE_BROAD == 1` in *every* year 2015–2025, `all(ACTIVE_BROAD == 1)` — one gap or confirmed-inactive year
  anywhere failed the whole facility."* Why revised: *"the all-11-years rule requires full-window continuity,
  which drops exactly the facilities most likely to exit *because of* enforcement/penalty outcomes —
  survivorship bias in a panel meant to study enforcement and compliance. Two-way fixed-effects estimators
  don't need a balanced panel, so there was no mechanical reason to require one."* Consequence: *"unlike the
  original rule, a facility can now have real within-window gaps — `OBS_SOURCE == "unobserved"` is no longer
  impossible in these panels."*
- ⚠️ **`col_guess()` silently corrupted data in earlier drafts of this script — now fixed by explicit typing
  everywhere (`PB8`).** Quoted: *"Caught during testing (2026-07-28): `col_guess()` on `regulatory.csv.gz`'s
  `PENALTY_AMOUNT`/`PENALTY_AMOUNT_DUP` (NA in ~99.6% of rows) and `operating.csv.gz`'s `EXITED_YEAR`/
  `EXIT_SOURCE` (NA for facilities that never exited) sampled all-`NA` rows and typed all four columns
  `col_logical()` — silently discarding every real value later in the file as an unparseable "logical," with
  **no error and no `problems()` entry**... Fixed by typing every selected column explicitly in
  `code/04_panel_building/00_spine.R` and `03_build_functions.R`."* This script's own inline comments
  independently corroborate this (the `attrs`/`op_facility` read blocks each explain the specific columns that
  were previously mistyped).
- **CONUS + class filter is applied once here, not duplicated per panel spec** — `electric` is a strict subset
  of this candidate set, with the NAICS/SIC filter added in `03_build_parameters.R`.
- **`COORD_NO_COUNTY_MATCH`** is a panel-layer-only derivation not shipped by `coordinates.csv.gz` itself. Per
  `docs/data_dictionary_derived.md` Part 2: *"Panel-layer-only derivation (`coordinates.csv.gz` doesn't ship
  this exact flag): `1` iff `HAS_COORDINATE == 1` but the point-in-polygon lookup still failed to land in any
  county polygon — distinct from `HAS_COORDINATE == 0` (no coordinate to begin with)."*
- **`N_PROGRAMS` stays `NA`-able**, not coalesced to `0` — inherited directly from `regulatory.csv.gz` (`PB6`):
  *"Adopts `regulatory.csv.gz`'s convention (`R7`) directly, since `N_PROGRAMS` is read straight from there —
  no separate panel-level override."*
- **`OP_STATUS_CURRENT_DESC` and `LEFT_CENSORED`/`RIGHT_CENSORED` are deliberately excluded** from this
  script's reads (2026-07-29 explicit user decisions) — see `docs/data_dictionary_derived.md` Part 2's
  "Removed from the panel" note for the reasoning (risk of being mistaken for genuinely year-varying evidence;
  redundant with `ENTERED_YEAR`/`EXITED_YEAR`/`EXIT_SOURCE`, respectively).
- Verified by reading the script in full, including both `FLAGGED ISSUES` entries. Not run in this session —
  the "not measured" runtime and the "in-memory only, no output file" claim are inferred from the script's own
  header comment and the absence of any `write_csv()`/`write_rds()` call in the file, not from executing it.
