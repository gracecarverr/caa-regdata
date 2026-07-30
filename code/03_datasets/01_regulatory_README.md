> **Status:** draft — [ ] verified against the current script (Claude, 2026-07-30)

# `01_regulatory.R` — builds dataset 0, `regulatory.csv.gz` (ICIS-Air event counts + facility characteristics)

## Purpose in the pipeline
> **TODO (Grace):** write the 1-2 sentence purpose blurb here — why this script exists and what depends on
> it. Starting material, from the script's own header comment:
> "code/03_datasets/01_regulatory.R -- DATASET 0: the regulatory dataset. Facility x year, built from the
> raw ICIS-Air download and NOTHING ELSE. Every column here is either an ICIS event count or an ICIS
> facility characteristic; no wayback status, no FRS coordinates, no AFS. Those live in other datasets and
> merge on PGM_SYS_ID (+ year)."

## Inputs & outputs
- **Input:** `data/processed/{inspections,violations,formal_actions,informal_actions,certs,stacktests}.csv.gz`
  — event-grain (one row per inspection/violation/enforcement action/cert/stack test), historical, spanning
  the raw ICIS-Air extract's full recorded date range. **Plus** `data/processed/{facilities,pollutants,programs}.csv.gz`
  — current-snapshot grain (one row per facility / pollutant-profile / program-enrollment as of the extract
  date, no history), which is why the facility-characteristic and `EMITS_*`/`PROG_*` columns are
  time-invariant.
- **Output:** `data/datasets/regulatory.csv.gz` — facility × year, one row per `(PGM_SYS_ID, YEAR)`; 80
  columns, full ICIS-AIR_FACILITIES universe (279,665 facilities as of 2026-07-27) × 21 years (2005–2025).

Example — 2 rows from `data/datasets/regulatory.csv.gz` (sampled from the actual file on disk, 2026-07-30;
picked to show an *observed* row — most rows are all-`NA` since 87.4% of the rectangle is unobserved, see R1):

| PGM_SYS_ID | YEAR | ICIS_OBSERVED | N_INSPECTIONS | N_VIOLATIONS | N_HPV | N_PENALTY_ACTION | PENALTY_AMOUNT | EMITS_HAP |
|---|---|---|---|---|---|---|---|---|
| 0500000026055R0002 | 2014 | 1 | 2 | 1 | 1 | 0 | NA | 0 |
| 0500000026061R0001 | 2013 | 1 | 1 | 1 | 1 | 0 | NA | 0 |

The other 71 columns fall into a few groups: inspection detail (`N_FCE`, `N_PCE`, `N_INSP_EPA/STATE/LOCAL`,
`N_INSPECTIONS_DUP`, `N_INSPECTIONS_DUP_EXACT`); violation program/agency breakdowns (`N_FRV`,
`N_VIOL_SIP/TITLEV/NSPS/MACT/FESOP`, `N_VIOL_EPA/STATE/LOCAL`); enforcement detail (`N_ENFORCEMENT`,
`N_FORMAL`, `N_INFORMAL`, `N_PENALTIES`, `N_PENALTIES_DUP`, `N_WARNING_LETTER`, `N_ADMIN_NP`,
`N_CIVIL_JUDICIAL`, `N_NOV`, `N_ADMIN_ORDER`, `N_ENF_EPA/STATE/LOCAL`, and a full set of `_DUP`/`_DUP_EXACT`
companions); `PENALTY_AMOUNT_DUP`; certs/stack tests (`N_CERTS`, `N_CERTS_DEVIATION`, `N_CERTS_DUP*`,
`N_STACK_TESTS`, `N_STACK_PASS`, `N_STACK_FAIL`); facility characteristics (`REGISTRY_ID`, `FACILITY_NAME`,
`STREET_ADDRESS`, `CITY`, `COUNTY_NAME`, `STATE`, `ZIP_CODE`, `EPA_REGION`, `NAICS_CODES`, `SIC_CODES`,
`FACILITY_TYPE_CODE`, `FACILITY_TYPE`, `AIR_POLLUTANT_CLASS_DESC`, `OP_STATUS_CURRENT_DESC`); the other five
`EMITS_*` flags (`EMITS_VOC`, `EMITS_PM`, `EMITS_CO`, `EMITS_NOX`, `EMITS_SO2`); the eight `PROG_*` flags
(`PROG_SIP/TITLEV/NSPS/MACT/NESHAP/FESOP/NSR/PSD`); and `N_PROGRAMS`.

## At a glance
| | |
|---|---|
| **Input** | `data/processed/{inspections,violations,formal_actions,informal_actions,certs,stacktests,facilities,pollutants,programs}.csv.gz` |
| **Output** | `data/datasets/regulatory.csv.gz` — 5,872,965 rows × 80 cols (as of 2026-07-27) |
| **Runtime** | not measured; reads nine cleaned assets (largest, `regulatory.csv` uncompressed, is ~2GB) and builds a 5.9M-row rectangle — likely low single-digit minutes |
| **Requires** | nothing upstream in this layer (only `data/processed/`); sources `00_parameters.R` and `hap_list_112b.R` |
| **Dependencies** | `readr`, `dplyr`, `tidyr`, `here` |

## Walkthrough
`rd()` is a small helper that reads one cleaned asset with a fixed `col_select`, pinning `PGM_SYS_ID`/`year`/
`dup` to explicit types and everything else to character (so `dup_exact` is compared as the string `"1"`
downstream, a convention independently duplicated from the equivalent `03_panel_building` helper rather than
shared). `FACILITY_TYPE` is a fixed named-vector lookup covering all 15 official ICIS-Air facility-type
codes. `attrs` reads `facilities.csv.gz` (the full 279,665-facility universe, `ids <- attrs$PGM_SYS_ID`) and
selects the current-snapshot facility characteristics. `emits` aggregates `pollutants.csv.gz` to one row per
`PGM_SYS_ID` with six `emits_*` flags via `POLLUTANT_DESC` pattern matches (`emits_hap` is the three-way
union described in R6 below); a coverage diagnostic prints how much of the raw pollutant table matches none
of the six categories. `progs` aggregates `programs.csv.gz` to one row per facility with eight `prog_*` "ever
enrolled" flags (an 8-group allowlist, GACT/CFC excluded) plus `n_programs` (which counts *all* program
codes, including GACT/CFC). Five aggregator functions (`agg_inspections`, `agg_violations`,
`agg_enforcement`, `agg_certs`, `agg_stacktests`) each read one event asset, filter to `YEARS`, and
`group_by(PGM_SYS_ID, year)` to produce facility-year counts; `agg_violations`/`agg_stacktests` assert
`dup == 0` via `stopifnot()` since those two assets are dup-free by construction. The "assemble" section
`full_join`s the five aggregator outputs into `counts`, restricts to the ICIS universe, coalesces every count
column `NA → 0` (a row present in `counts` means ≥1 ICIS record of *some* type — see R2), then builds the
full facility × year rectangle via `expand_grid(PGM_SYS_ID = ids, year = YEARS)`, left-joining `counts`,
`attrs`, `emits`, `progs` onto it. `icis_observed` is derived from whether `n_inspections` is non-`NA` after
the join (equally valid to use any other count column, since a `counts` row has every count column non-`NA`
after the coalesce). `PROFILE_COLS` (the `emits_*`/`prog_*` flags) get a separate `NA → 0` coalesce, since a
facility absent from the pollutant/program tables has a genuinely absent (zero) profile — `n_programs` is
deliberately excluded from this step (R7). The last mutate reverses the blanket `0`-coalesce specifically for
`penalty_amount`/`penalty_amount_dup`, recoding literal `0` back to `NA` (R4). Four `stopifnot()` invariants
close the script: grain uniqueness, rectangle completeness, and the two-directional zero-vs-NA observability
check. `write_dataset(reg, "regulatory")` uppercases and writes the file, followed by a summary line.

## Notes & gotchas
- **R1** — "**Universe = every `PGM_SYS_ID` in `ICIS-AIR_FACILITIES` (279,665 as of 2026-07-27), NO
  ever-active screen.** ... Retains the never-inspected population (mostly operating minor sources).
  **52.2% of facilities have zero events in-window** ... sit all-`NA` here until dataset 1 supplies operating
  status. Consequence: only **12.6%** of the rectangle is observed — the dataset is close to unusable
  standalone by design, which is why ds 0 and ds 1 must be documented as a pair."
- **R2 (⚠ load-bearing)** — "**Zero-vs-NA rule (load-bearing).** A facility-year is `ICIS_OBSERVED == 1` iff
  ICIS holds ≥1 row across ANY of the six event assets that year. Then a count of 0 for some *other* measure
  is a **true zero**. With no record of any type → **every count is `NA`** (unknown, not zero). ...
  Operating-status inference is deliberately held out — that is **dataset 1's** job, kept out so ds 0 is pure
  ICIS."
- **R3** — "**Every `N_*` counts ALL rows; nothing deduped.** Duplicate load surfaced via `N_*_DUP` (event-key
  repeats, `dup>0`) and `N_*_DUP_EXACT` (byte-identical). Event-distinct = `count − dup`. ... **Violations &
  stack tests carry zero dups — enforced via `stopifnot()` at build time** (`01_regulatory.R:146,216`:
  `stopifnot(all(v$dup == 0))` / `stopifnot(all(s$dup == 0))`), not merely a comment — a `dup>0` row would
  fail the build, not just go unnoticed."
- **R4 (⚠ silent-failure-risk if unread)** — "**REVERSED 2026-07-28 (explicit user decision):**
  `PENALTY_AMOUNT` is `NA` whenever a facility-year had no formal action at all, OR its formal action(s)
  summed to exactly $0 — both collapse into `NA`, not just genuinely-unobserved years. ... User was asked
  whether 'no formal action' and 'formal action worth exactly $0' should read differently or the same —
  chose the same (both `NA`, meaning 'no confirmed positive penalty dollars')." Consequence stated in the
  script itself: "An observed facility-year with a formal action but no penalty dollars can read
  `N_PENALTIES = 0` **and** `PENALTY_AMOUNT = NA` simultaneously; this is by design (`R4`), not a bug."
- **R5** — "**Facility characteristics are the current ICIS snapshot, time-invariant, applied to all 21
  years.** ... An industry reclassification or ownership change is **not** visible — a known limitation, not
  a bug. **Addendum (2026-07-28) — `FACILITY_TYPE` lookup expanded from 8 to all 15 official ICIS-Air
  codes**... The old 8-code list silently mapped any other code to `NA`; **558 facilities** carried a real
  code (`TRB`/`MWD`/`SDT`/`MXO`) the list didn't have."
- **R6 (EMITS_HAP fix, load-bearing)** — "**`EMITS_*` (6) and `PROG_*` (8) are ever-reported / ever-enrolled,
  undated → time-invariant flags.** A facility absent from `pollutants`/`programs` gets flag = **0** (absent
  profile). ... **Addendum (2026-07-28) — `EMITS_HAP` was broken, now fixed:** the old rule matched only the
  literal substring `"HAZARDOUS AIR POLLUTANT"` in `POLLUTANT_DESC`, missing the large majority of HAPs that
  ICIS-AIR records under a specific chemical name (Benzene, Formaldehyde, Lead, Mercury, ...) ... Fixed ...
  CAS (Chemical Abstracts Service registry number)-join against the official CAA §112(b) HAP list (188
  substances, `code/03_datasets/hap_list_112b.R`) **unioned with** (not replacing) the old umbrella-phrase
  rule ... plus a name match for the 17 CAS-less compound-class entries. Full-universe `EMITS_HAP=1` facility
  count: **67,011 of 279,665 (24.0%)** post-fix."
- **R7** — "**`N_PROGRAMS` is `NA`-able, never 0.** ... Distinguishes 'not associated with **any** program'
  (`NA`) from the `PROG_*` flags' 'not enrolled in **this** program' (0). **12,544 facilities (4.5%) are
  absent from `programs.csv.gz`** ... → `N_PROGRAMS = NA` for exactly those (263,424 facility-years). ⚠ **NA
  now carries two meanings in this file** — see R8."
- **R8** — "**`program_begin_year` is deliberately ABSENT from ds 0.** ... `BEGIN_DATE` is a
  facility-lifecycle proxy, so it belongs with the operating evidence in **dataset 1**, not with the undated
  'ever-enrolled' flags."
- **R9 (three `_DESC`→`_CODE` fixes, load-bearing)** — "**Three `_DESC`-text-match bugs found & fixed
  (2026-07-28), switched to `_CODE`-based matching where a code exists.** ... **(1) `EMITS_VOC` false
  positive:** `grepl("VOLATILE ORGANIC", POLLUTANT_DESC)` matched `POLLUTANT_CODE 300000310`
  'NON-VOLATILE ORGANIC COMPOUNDS' — a plain substring match with no negation handling. Flipped **30
  facilities** from `EMITS_VOC=1` to the correct `0` ... Fixed with a negative-lookbehind regex,
  `(?<!NON-)VOLATILE ORGANIC`... **(2) `N_VIOL_NSPS` scope creep:** `grepl("New Source Performance
  Standards", PROGRAM_DESCS)` also matched `CAANSPSM`'s description ('...(Non-Major)') by substring — 418
  rows. ... `agg_violations()` now matches on `PROGRAM_CODES` with explicit `\b`-bounded codes for all five
  `N_VIOL_*` program flags, so the parity with `PROG_NSPS` is coded, not coincidental. **(3)
  `N_PENALTY_ACTION` undercount:** exact match `ENF_TYPE_DESC == 'CAA 113D1 Action For Penalty'` missed four
  112(r)/MRR expedited-settlement variants of the same action (`ENF_TYPE_CODE` `113D1E`/`113D1E1`/`113D1E2`/
  `113D1E3` ...) — a **201-row undercount** of the true 113D1 family (201/6,881, ~2.9%). Switched to
  `grepl("^113D1", ENF_TYPE_CODE)`."
- **B.2 ⚠ Two meanings of `NA` in this file** — "A downstream user must not conflate them: `is.na(N_INSPECTIONS)`
  (and all other event counts) is a **year-level** condition → facility not observed in ICIS that year
  (`ICIS_OBSERVED == 0`). `is.na(N_PROGRAMS)` is a **facility-level** condition → no program association on
  record at all, constant across all 21 years. Both ride on `NA` in the same table. Needs a codebook line so
  `is.na()` isn't read as one thing."
- Verified by reading the full script (`code/03_datasets/01_regulatory.R`, 291 lines) and sampling
  `data/datasets/regulatory.csv.gz` directly (`gzcat ... | head`, both a default row and an
  `ICIS_OBSERVED==1` row). Column groupings above and the R1–R9/B.2 quotes are pulled verbatim from
  `briefs/datasets/dataset_construction_decisions.md` Part B — not independently re-derived this pass.
