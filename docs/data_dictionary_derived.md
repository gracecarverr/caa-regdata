# CAA Regulatory Data — Data Dictionary: Derived Layer

Column-by-column documentation for every **created/derived** variable in this repo — the eight built datasets
in [`data/datasets/`](../data/datasets/README.md) (built by [`code/04_datasets`](../code/04_datasets/README.md))
and the facility spine + three sample panels in [`data/panels/`](../data/panels/README.md) (built by
[`code/03_panel_building`](../code/03_panel_building/README.md)). For **raw** EPA source fields, see
[`data_dictionary.md`](data_dictionary.md); this file only covers columns that are computed, aggregated, or
recoded by this repo's build code. For the *why* behind a specific choice, find its decision code (e.g. `R2`,
`H6`, `W5`) in [`briefs/datasets/dataset_construction_decisions.md`](../briefs/datasets/dataset_construction_decisions.md)
(Part 1 below) or [`briefs/panel/panel_construction_decisions.md`](../briefs/panel/panel_construction_decisions.md)
(Part 2 below) — this file gives the *what/how*, not the full rationale.

> **Verified against code, not just READMEs.** Every column below was checked directly against the build
> scripts (`code/04_datasets/*.R`, `code/03_panel_building/*.R`) and against the actual `.csv.gz` headers on
> disk as of 2026-07-27 — not just the band-level descriptions in the folder READMEs.

## Conventions used throughout

- **Casing.** `data/datasets/` columns are `UPPER_SNAKE_CASE` (every builder assembles in lowercase, then
  uppercases once on write — decision `G2`). `data/panels/` columns are `lower_snake_case`, except for a
  handful of facility-attribute columns carried through unchanged from the raw ICIS schema (`REGISTRY_ID`,
  `FACILITY_NAME`, `STREET_ADDRESS`, `CITY`, `COUNTY_NAME`, `STATE`, `ZIP_CODE`, `EPA_REGION`, `NAICS_CODES`,
  `SIC_CODES`, `FACILITY_TYPE_CODE`, `AIR_POLLUTANT_CLASS_DESC`) — this mixed casing in the panel files is a
  known artifact of the passthrough, not a typo.
- **Join keys.** Every file in both layers carries `PGM_SYS_ID` (the ICIS-Air facility id) and `REGISTRY_ID`
  (the cross-program FRS facility id, `NA` where no FRS match — `G4`). Facility-year files join `(PGM_SYS_ID,
  YEAR)`/`(PGM_SYS_ID, year)` 1:1 onto one another; event-grain files (`hpv_spells`, `penalties`) join
  many-to-one via `PGM_SYS_ID` (+ year where relevant).
- **The zero-vs-NA discipline (the single most load-bearing convention in this repo).** Every count/status
  column in a facility-year file is gated by an observability flag for that file (`ICIS_OBSERVED`,
  `WAYBACK_OBSERVED`, `PIPELINE_OBSERVED`, `EMISSIONS_OBSERVED`/`GHG_OBSERVED`, or the panel layer's
  `obs_source`). Within an **observed** facility-year, a `0` is a confirmed true zero; an **unobserved**
  facility-year is `NA` — we simply don't know. Never treat `NA` as `0`, and never assume `0` means "checked
  and none happened" without first checking the observability flag. Below, a column tagged **COUNT_COL**
  follows this rule; a handful of dollar/lag columns (`PENALTY_AMOUNT`, `penalty_amount`,
  `MEAN_*_LAG_DAYS`) follow a *different*, narrower rule ("no value or zero → `NA`") that's called out
  explicitly where it applies.
- **Duplicates are surfaced, never dropped.** Every `N_*`/`n_*` count counts **all rows** of its source event
  table, with no deduplication. Where an asset carries duplicate event-key rows (inspections, enforcement,
  certs), a companion `_DUP`/`_dup` (event-key repeat) and `_DUP_EXACT`/`_dup_exact` (byte-identical repeat)
  column reports how many of those rows were duplicates; recover the event-distinct count as `n_x − n_x_dup`.
  Violations and stack tests are asserted duplicate-free at build time, so they carry no `_dup` columns.

---

# Part 1 — `data/datasets/` (the eight built datasets)

Each dataset is built once over the **full** 279,211-facility ICIS-Air universe (no ever-active screen, no
sample restriction — `G3`); sample selection is left to the user. Full narrative: `dataset_construction_decisions.md`.

## `regulatory.csv.gz` — dataset 0, facility × year, ICIS-Air only

Universe: every `PGM_SYS_ID` in `ICIS-AIR_FACILITIES` (`R1`), years 2005–2025. `ICIS_OBSERVED` is the
reference zero-vs-NA flag reused by `hpv_active`.

| Field | Type | Definition & derivation | Decision |
|---|---|---|---|
| `ICIS_OBSERVED` | flag | `1` iff the facility-year has ≥1 row in *any* of the six ICIS event tables (inspections/violations/formal/informal/certs/stacktests); gates every `N_*` column below. | **R2** |
| `N_INSPECTIONS` | COUNT_COL | Count of `inspections` rows for the facility-year. | R2/R3 |
| `N_FCE` | COUNT_COL | `sum(grepl("^FCE", COMP_MONITOR_TYPE_DESC))` — Full Compliance Evaluations (overlaps `N_PCE`). | R3 |
| `N_PCE` | COUNT_COL | `sum(grepl("^PCE", COMP_MONITOR_TYPE_DESC))` — Partial Compliance Evaluations. | R3 |
| `N_INSP_EPA` / `N_INSP_STATE` / `N_INSP_LOCAL` | COUNT_COL | `STATE_EPA_FLAG == "E"/"S"/"L"` — conducting agency; partitions `N_INSPECTIONS`. | R3 |
| `N_INSPECTIONS_DUP` | COUNT_COL | Count of inspection rows with a repeated event key. | R3 |
| `N_INSPECTIONS_DUP_EXACT` | COUNT_COL | Subset of the above that are byte-identical repeats. | R3 |
| `N_VIOLATIONS` | COUNT_COL | Count of `violations` rows (asset asserted dup-free). | R2/R3 |
| `N_HPV` | COUNT_COL | `sum(!is.na(HPV_DAYZERO_DATE) & HPV_DAYZERO_DATE != "")` on violation rows — a **narrower, different** HPV proxy than dataset 2's `ENF_RESPONSE_POLICY_CODE=="HPV"` tier. See cross-file caveats below — do not expect this to reconcile exactly to `hpv_spells`/`hpv_active`. | R2 |
| `N_FRV` | COUNT_COL | Complement of `N_HPV` — violation rows with no HPV day-zero date. | R2 |
| `N_VIOL_SIP` / `N_VIOL_TITLEV` / `N_VIOL_NSPS` / `N_VIOL_MACT` / `N_VIOL_FESOP` | COUNT_COL | `grepl()` substring match of the program name in `PROGRAM_DESCS` (State Implementation Plan / Title V Permits / New Source Performance Standards / MACT Standards / Federally-Enforceable State Operating Permit). Overlapping, not partitioning — need not sum to `N_VIOLATIONS`. | R3 |
| `N_VIOL_EPA` / `N_VIOL_STATE` / `N_VIOL_LOCAL` | COUNT_COL | `AGENCY_TYPE_DESC` bucketed to federal / state / local (see agent report for exact string sets). | R3 |
| `N_ENFORCEMENT` | COUNT_COL | Count of pooled `formal_actions` + `informal_actions` rows for the facility-year. | R2 |
| `N_FORMAL` / `N_INFORMAL` | COUNT_COL | Partition of `N_ENFORCEMENT` by source table. | R3 |
| `N_PENALTY_ACTION` | COUNT_COL | `ENF_TYPE_DESC == "CAA 113D1 Action For Penalty"`, pooled. | R3 |
| `N_PENALTIES` | COUNT_COL | Count of **formal** rows with parsed `PENALTY_AMOUNT > 0` (informal rows have no penalty field, never counted). The count companion to the dollar sum `PENALTY_AMOUNT` — they follow *different* NA rules (see below). | R3/R4 |
| `N_PENALTIES_DUP` | COUNT_COL | Subset of `N_PENALTIES` on duplicate-flagged rows. | R3 |
| `N_WARNING_LETTER` / `N_ADMIN_NP` / `N_CIVIL_JUDICIAL` / `N_NOV` / `N_ADMIN_ORDER` | COUNT_COL | Exact `ENF_TYPE_DESC` matches ("Warning Letter" / "CAA 113A Admin Compliance Order (Non-Penalty)" / "Civil Judicial Action" / "Notice of Violation" / "Administrative Order"), pooled formal+informal; unmapped types are dropped, so these need not sum to `N_ENFORCEMENT`. | R3 |
| `N_ENF_EPA` / `N_ENF_STATE` / `N_ENF_LOCAL` | COUNT_COL | `STATE_EPA_FLAG`, pooled enforcement. | R3 |
| `N_ENFORCEMENT_DUP` / `N_ENFORCEMENT_DUP_EXACT` | COUNT_COL | Duplicate-load indicators, pooled. | R3 |
| `N_FORMAL_DUP` / `N_FORMAL_DUP_EXACT` / `N_INFORMAL_DUP` / `N_INFORMAL_DUP_EXACT` | COUNT_COL | Same, split by formal/informal. | R3 |
| `PENALTY_AMOUNT` | dollars | `sum(parse_number(PENALTY_AMOUNT), na.rm=TRUE)` over all **formal** rows for the facility-year. **Not** a COUNT_COL: real when observed, but `NA` — not `0` — when unobserved. An observed facility-year with a formal action but no penalty dollars can read `N_PENALTIES = 0` **and** `PENALTY_AMOUNT = NA` simultaneously; this is by design (`R4`), not a bug. | **R4** |
| `PENALTY_AMOUNT_DUP` | dollars | Dollars contributed by duplicate-flagged formal rows only — isolates inflation from not deduping. | R3/R4 |
| `N_CERTS` | COUNT_COL | Count of `certs` rows. | R2/R3 |
| `N_CERTS_DEVIATION` | COUNT_COL | `sum(FACILITY_RPT_DEVIATION_FLAG == "Y")` — Title V certs self-reporting a deviation. | R3 |
| `N_CERTS_DUP` / `N_CERTS_DUP_EXACT` | COUNT_COL | Duplicate-load indicators (~81% of cert rows are event-key duplicates). | R3 |
| `N_STACK_TESTS` | COUNT_COL | Count of `stacktests` rows (asset asserted dup-free). | R2/R3 |
| `N_STACK_PASS` / `N_STACK_FAIL` | COUNT_COL | `AIR_STACK_TEST_STATUS_DESC == "Pass"/"Fail"` (Pending/Incomplete/N-A left uncounted). | R3 |
| `FACILITY_TYPE` | label | `FACILITY_TYPE_CODE` mapped through a fixed lookup, all 15 official ICIS-Air codes (POF→"Privately owned", COR→"Corporation", CNG→"County government", CTG→"Municipality", FDF→"Federal facility", STF→"State facility", DIS→"District", NON→"Non-government", GOC→"GOCO (government-owned, contractor-operated)", IND→"Individual", MXO→"Mixed ownership (public/private)", MWD→"Municipal or water district", SDT→"School district", TRB→"Tribal government", UNK→"Unknown"); `NA` if unmapped (2026-07-28: expanded from 8 to all 15 codes — see `panel_construction_decisions.md`/`dataset_construction_decisions.md` for the facility counts this closed). | R5 |
| `OP_STATUS_CURRENT_DESC` | passthrough | Renamed from ICIS's `AIR_OPERATING_STATUS_DESC` — a **current, undated** snapshot, distinct from dataset 1's year-varying wayback status. | R5 |
| `EMITS_VOC` / `EMITS_PM` / `EMITS_CO` / `EMITS_NOX` / `EMITS_SO2` / `EMITS_HAP` | flag | "Ever reported" flag from `pollutants.csv.gz`: `any(grepl(<pattern>, POLLUTANT_DESC, ignore.case=TRUE))` per facility (Volatile Organic / Particulate Matter / Carbon Monoxide / Nitrogen Oxides / Sulfur Dioxide / Hazardous Air Pollutant). Undated, boolean only — **not** a measured quantity (contrast with `emissions.csv.gz`'s pounds columns). Facility absent from `pollutants.csv.gz` → coalesced to `0` (a true "no profile" reading, not missing data). | **R6** |
| `PROG_SIP` / `PROG_TITLEV` / `PROG_NSPS` / `PROG_MACT` / `PROG_NESHAP` / `PROG_FESOP` / `PROG_NSR` / `PROG_PSD` | flag | "Ever enrolled" flag from `programs.csv.gz` by `PROGRAM_CODE` (SIP=`CAASIP`, Title V=`CAATVP`, NSPS=`CAANSPS`+`CAANSPSM` pooled, MACT=`CAAMACT`, NESHAP=`CAANESH`, FESOP=`CAAFESOP`, NSR=`CAANSR`, PSD=`CAAPSD`). This is a deliberately **narrowed 8-group set** — `CAAGACTM` (area-source MACT) and `CAACFC` (Title VI ozone) are excluded here to match dataset 1's 8-group `PROG_*_ACTIVE` allowlist, even though the panel layer (Part 2) keeps all 10 groups. Coalesced `NA→0`. | **R6** (aligns w/ `O3`) |
| `N_PROGRAMS` | count | `n_distinct(PROGRAM_CODE)` per facility, **including** GACT/CFC (broader scope than the 8 `PROG_*` flags above). Facility-level, **not** subject to the coalesce-to-0 step. | **R7** |

## `operating.csv.gz` — dataset 1, facility × year, Wayback reconstruction

Same 279,211 × 21-year rectangle as dataset 0 (1:1 joinable); strictly raw — year-varying fields are `NA`
wherever no Wayback snapshot exists, never imputed (`O2`).

| Field | Type | Definition & derivation | Decision |
|---|---|---|---|
| `WAYBACK_OBSERVED` | flag | `1` iff `wayback_facility_status.csv.gz` has a snapshot for `(PGM_SYS_ID, year)`. Always 0/1, never itself `NA`. | O2 |
| `OP_STATUS_CODE` / `OP_STATUS_DESC` | passthrough | Wayback-reconstructed operating-status code/description for that year. `NA` for 2005–2014 and any uncovered facility-year. | O2 |
| `OPERATING` | flag | `1` iff `OP_STATUS_CODE %in% c("OPR","TMP","SEA")`; carried unchanged from the cleaning layer. `NA` outside wayback coverage. | O3 |
`PROG_SIP_ACTIVE`, `PROG_TITLEV_ACTIVE`, `PROG_NSPS_ACTIVE`, `PROG_MACT_ACTIVE`, `PROG_NESHAP_ACTIVE`, `PROG_FESOP_ACTIVE`, `PROG_NSR_ACTIVE`, `PROG_PSD_ACTIVE` (8 flags) | flag | From `wayback_program_status.csv.gz`, an explicit 8-group allowlist (chosen to guard against upstream schema drift after `gact`/`cfc` were silently added elsewhere) — "is this program group active in this year's wayback snapshot." `NA` where the facility isn't covered by that year's snapshot. | **O3** |
| `ENTERED_YEAR` / `EXITED_YEAR` | facility-level | From `wayback_facility_spells.csv.gz` — year the facility's observed operating spell began/ended, broadcast to all 21 rows. `NA` for the ~2,472 ICIS facilities with no wayback spell. | O4 |
| `EXIT_SOURCE` | categorical | `"cls"` (confirmed closure) / `"dropout"` (last seen operating, then vanished — an upper bound on unexplained exits) / `"other"` / `NA` (no exit observed). Because dataset 1 drops wayback-only facilities, only 2 of 11,801 wayback `dropout` exits survive here — this column is effectively almost pure `"cls"` in this file. | **O4** |
| `LEFT_CENSORED` / `RIGHT_CENSORED` | flag | Facility-level: spell already in progress at the window's left edge / still ongoing at the right edge. | O4 |
| `EARLIEST_PROGRAM_BEGIN_YEAR_RAW` | year | `min(year(mdy(BEGIN_DATE)))` across all parseable `BEGIN_DATE` values in `programs.csv.gz`, **unscreened** (raw range observed: [218, 2028] — includes clear data-entry typos). `NA` if no parseable date. | **O5** |
| `EARLIEST_PROGRAM_BEGIN_YEAR` | year | Same minimum, restricted to a `[1970, 2025]` validity screen — removes implausible candidates only, never imputes; always ≥ the raw version. `NA` if no in-range date. | **O5** |
| `ICIS_OBSERVED` | flag (NEW 2026-07-28) | Passthrough from `regulatory.csv.gz`, same `(PGM_SYS_ID, YEAR)` — `1` iff ICIS holds ≥1 event record that year. Never `NA` (dataset 0's own invariant). Carried here so `ACTIVE`'s constituent evidence is visible without a join. | **O6** |
| `EMISSIONS_OBSERVED` / `GHG_OBSERVED` | flag (NEW 2026-07-28) | Passthrough from `emissions.csv.gz`, same `(PGM_SYS_ID, YEAR)` — pounds-based / GHG reporting that year, independently. Never `NA` (dataset 7's own invariant). Carried here so `ACTIVE_BROAD`'s constituent evidence is visible without a join. | **O6** |
| `ACTIVE` | flag (NEW 2026-07-28) | **Year-varying**, not an "ever" summary: `1` iff `OPERATING==1` OR `ICIS_OBSERVED==1` **that year**; `0` iff both are confirmed `0` that year; `NA` iff `OPERATING` is `NA` that year (no wayback snapshot) AND `ICIS_OBSERVED==0` that year (no ICIS event that specific year) — genuinely no evidence either way. Closes wayback's pre-2015 blind spot and ICIS's never-inspected-facility blind spot, year by year. | **O6** |
| `ACTIVE_BROAD` | flag (NEW 2026-07-28) | `1` iff `ACTIVE==1` OR `EMISSIONS_OBSERVED==1` OR `GHG_OBSERVED==1` **that year**; `0` iff all three are confirmed `0`; `NA` iff `ACTIVE` is `NA` and neither emissions flag is `1` that year. Nests monotonically under `ACTIVE` (`ACTIVE==1 ⇒ ACTIVE_BROAD==1`, verified 0 violations). | **O6** |

## `wayback_only_facilities.csv.gz` — dataset 1b, facility × year (2015–2025 only), NEW 2026-07-28

Supplementary output, not one of the eight numbered datasets — covers the ~15,302 facilities Wayback has
captured operating-status snapshots for that are entirely absent from the current ICIS-AIR facility extract
(the `O1a` population). Grain `PGM_SYS_ID × year`, but window is **2015–2025 only** (Wayback's real coverage,
narrower than every other file's 2005–2025 — these facilities have zero information of any kind before
2015). Does **not** join to `regulatory.csv.gz`/`operating.csv.gz` — by definition, none of its facilities
appear there (confirmed: 0/15,302 have any ICIS event record at all).

| Field | Type | Definition & derivation | Decision |
|---|---|---|---|
| `WAYBACK_OBSERVED` | flag | Same definition as `operating.csv.gz`'s column of the same name, restricted to this facility set. | O7 |
| `OP_STATUS_CODE` / `OP_STATUS_DESC` / `OPERATING` | passthrough / flag | Same definitions as `operating.csv.gz`'s columns of the same name. | O7 |
| `ENTERED_YEAR` / `EXITED_YEAR` / `EXIT_SOURCE` / `LEFT_CENSORED` / `RIGHT_CENSORED` | facility-level | Same definitions as `operating.csv.gz`'s columns of the same name — the pre-done version of the manual join `O1a` used to point users to. | O7 |

No `ACTIVE`/`ACTIVE_BROAD`-style column here: `ICIS_OBSERVED` and `EMISSIONS_OBSERVED`/`GHG_OBSERVED` are
structurally undefined for this population (no row to look up in `regulatory.csv.gz` or `emissions.csv.gz`
at all, not merely a confident `0`), so such a column would either be all-`NA` or wrongly imply a real zero.

## `hpv_spells.csv.gz` — dataset 2, spell grain, UNcollapsed

One row per HPV violation record (`ENF_RESPONSE_POLICY_CODE == "HPV"` on `violations.csv.gz`, decision `H1`) —
overlapping spells at the same facility are **not** merged here (merging happens only in `hpv_active`).

| Field | Type | Definition & derivation | Decision |
|---|---|---|---|
| `HPV_DAYZERO_DATE` / `HPV_RESOLVED_DATE` | Date | `mdy()`-parsed spell start/resolution dates, carried **as parsed with no plausibility screen** (implausible years like `218` or `2026` are kept as-is). | **H4** |
| `DAYZERO_YEAR` / `RESOLVED_YEAR` | year | `year()` of the parsed dates. `DAYZERO_YEAR` is `NA` iff `SPELL_STATUS == "missing_start"`; `RESOLVED_YEAR` is `NA` for `open` and `missing_start`-with-no-dates spells. | H3 |
| `SPELL_STATUS` | categorical | Exhaustive, mutually exclusive: `"missing_start"` (no day-zero date) / `"open"` (no resolved date) / `"bad_order"` (resolved date precedes day-zero) / `"closed"` (both present, ordered). | **H3** |
| `SPELL_DAYS` | integer | `(resolved − dayzero) + 1` (inclusive), computed only where `SPELL_STATUS == "closed"`; `NA` otherwise. | **H3** |
| `DUP` / `DUP_EXACT` | flag | Passthrough duplicate-load flags; asserted `== 0` for every row in this file (violations carry no dups). | — |

Remaining columns (`ACTIVITY_ID`, `COMP_DETERMINATION_UID`, `EARLIEST_FRV_DETERM_DATE`, `PROGRAM_CODES`,
`PROGRAM_DESCS`, `POLLUTANT_CODES`, `POLLUTANT_DESCS`, `AGENCY_TYPE_DESC`, `STATE_CODE`) are direct passthrough
from `violations.csv.gz` — see `data_dictionary.md`'s `ICIS-AIR_VIOLATION_HISTORY.csv` entry for the raw
definitions.

## `hpv_active.csv.gz` — dataset 2b, facility × year, R2 interval-overlap collapse of `hpv_spells`

| Field | Type | Definition & derivation | Decision |
|---|---|---|---|
| `HPV_ACTIVE` | flag | Built from `hpv_spells`: drop `missing_start` spells (no interval to test); screen day-zero year to `[1970, 2025]` (excludes 165/44,457 mappable spells, catching e.g. a mistyped `0218` that would spuriously flag 2005–2017 — `H7`); compute a conservative closing date (`resolved` if `closed`, else Dec 31 of the day-zero year for `open`/`bad_order` — chosen over alternatives in diagnostic 09, `H5`); `1` if any qualifying spell's interval overlaps the calendar year (can be `1` even where `ICIS_OBSERVED == 0` — a spell always wins); `0` if no overlap but `ICIS_OBSERVED == 1` (true zero, reusing dataset 0's flag rather than inventing a new one — `H6`); `NA` if no overlap and unobserved. | **H5** (collapse rule), **H6** (zero-vs-NA reuse), **H7** (day-zero screen) |

## `penalties.csv.gz` — dataset 3, one row per formal enforcement action

Grain: every `formal_actions.csv.gz` row, duplicates flagged not dropped (`P1`); not restricted to 2005–2025
(`P3`); reconciles exactly to `regulatory.csv.gz`'s windowed `PENALTY_AMOUNT` sum.

| Field | Type | Definition & derivation | Decision |
|---|---|---|---|
| `ENF_IDENTIFIER` | key | The **settlement key** — multiple facility rows sharing one `ENF_IDENTIFIER` are co-defendants of a single multi-facility settlement. | **P5** |
| `PENALTY_AMOUNT` | dollars | `parse_number(PENALTY_AMOUNT)` for this row, kept as recorded (0 or positive) — every row is an observed action, so no zero-vs-NA discipline applies at this grain. | P4 |
| `HAS_PENALTY` | flag | `1` iff `PENALTY_AMOUNT > 0`. | P4 |
| `N_SETTLEMENT_FACILITIES` | count | `n_distinct(PGM_SYS_ID)` within the same `ENF_IDENTIFIER` group — constant within a settlement. | **P5** |
| `IS_MULTI_FACILITY` | flag | `1` iff `N_SETTLEMENT_FACILITIES > 1`. | P5 |
| `DUP` / `DUP_EXACT` | flag | Passthrough duplicate-load flags, kept not dropped. | — |

`SETTLEMENT_ENTERED_DATE` (parsed settlement date), `ENF_TYPE_CODE` / `ENF_TYPE_DESC` (enforcement-action type
code/description), `ACTIVITY_TYPE_CODE` / `ACTIVITY_TYPE_DESC` (activity-type code/description), and
`STATE_EPA_FLAG` (which level — EPA/State/Local — took the action) are direct passthrough from
`formal_actions.csv.gz`; see `data_dictionary.md`'s `ICIS-AIR_FORMAL_ACTIONS.csv` entry for the raw definitions.

> **Caveat (`P5`).** The penalty is usually one dollar figure repeated across co-defendants (516 of 588
> multi-facility settlements), but 72 settlements carry *differing* per-facility amounts. Do not sum
> `PENALTY_AMOUNT` across a settlement's facilities without first deciding a broadcast rule — see
> `briefs/datasets/multi_facility_settlement_decision.md`.

## `coordinates.csv.gz` — dataset 4, one row per facility

Coordinate source: FRS via `REGISTRY_ID` (`C1`); full 279,211-facility universe (`C4`).

| Field | Type | Definition & derivation | Decision |
|---|---|---|---|
| `ICIS_COUNTY_FIPS` | GEOID | The ICIS-*claimed* county resolved to a GEOID: `(STATE, COUNTY_NAME)` normalized (case, "(city)"/"County"/"Parish"/etc. suffix stripping, "Saint"→"St") and matched against a name crosswalk built from the county shapefile. Independent of any coordinate. `NA` if the normalized name doesn't resolve to exactly one GEOID in this shapefile vintage. | **C5** |
| `LATITUDE` / `LONGITUDE` | numeric | `FRS_FACILITIES.csv`'s `LATITUDE_MEASURE`/`LONGITUDE_MEASURE`, joined via `REGISTRY_ID` (first record kept if multiple). `NA` if no FRS match. | **C1** |
| `HAS_COORDINATE` | flag | `1` iff both lat/lon are non-missing. | C1 |
| `COUNTY_FIPS` | GEOID | Point-in-polygon spatial join (`st_within`) of the FRS coordinate against the county shapefile — the county the *coordinate itself* falls in, computed only where a coordinate exists. `NA` for non-CONUS facilities (shapefile is CONUS+DC only) or points outside every polygon. | **C2** |
| `COORD_COUNTY_DIST_KM` | km | Distance from the coordinate to the ICIS-claimed county's polygon (EPSG:5070 Albers). **`0` by construction** where `COUNTY_FIPS == ICIS_COUNTY_FIPS` (no distance computed, exact match); a real `st_distance()` value only for the checkable-and-mismatched subset. `NA` if uncheckable (no coordinate, or `COUNTY_NAME` unresolvable). `0 ≠ NA` is strictly honored — don't treat a missing check as agreement. | **C3** |
| `COORD_GROSS_ERROR` | flag | `1` iff checkable and `COORD_COUNTY_DIST_KM > 5` (km). `NA` exactly where `COORD_COUNTY_DIST_KM` is `NA`. | **C3** |

## `pipeline.csv.gz` — dataset 6, facility × year, EPA ECHO "CAA Compliance Pipeline"

7,193 of 66,655 raw rows are EPA linkage-helper placeholders (no real violation date) and are excluded
(`PL1`). Year anchor is `VIOL_START_DATE`, deliberately not the cleaned asset's own `date` (which can trace to
a later enforcement/eval date and would misdate the violation — `PL2`). Universe: the same 279,211 × 21
rectangle as datasets 0/1/2b (`PL3`).

| Field | Type | Definition & derivation | Decision |
|---|---|---|---|
| `PIPELINE_OBSERVED` | flag | `1` iff ≥1 real (non-placeholder) pipeline row anchors to the facility-year. | PL1/PL3 |
| `N_VIOL_PIPELINE` | COUNT_COL | Count of real rows for the facility-year. | PL1 |
| `N_VIOL_HPV` / `N_VIOL_FRV` | COUNT_COL | `VIOL_TYPE == "HPV"/"FRV"` — the raw ECHO pipeline's **own** HPV/FRV tag (asserted to sum exactly to `N_VIOL_PIPELINE`, i.e. exhaustive/exclusive here) — this is a **third, separate** HPV/FRV definition from `regulatory.N_HPV`/`N_FRV` and from `hpv_spells`/`hpv_active`. See cross-file caveats below. | PL1 |
| `N_VIOL_WITH_EVAL` | COUNT_COL | `sum(EVAL_FLAG == "Y")` — violations with a linked evaluation/inspection record. | — |
| `N_VIOL_WITH_EA` | COUNT_COL | `sum(EA_FLAG == "Y")` — violations with a linked enforcement action. | — |
| `N_VIOL_SELF_DISCLOSED` | COUNT_COL | `sum(EVAL_TYPE_DESC == "Self-Disclosure")` among rows with a linked eval, explicitly NA-guarded (an unguarded comparison against the ~46% of rows lacking a linked eval, whose `EVAL_TYPE_DESC` is blank→`NA`, would poison the whole-group sum). | **PL5** |
| `N_VIOL_WITH_EA_PENALTY` | COUNT_COL | `sum(EA_PENALTY_AMT > 0, na.rm=TRUE)`. | — |
| `EA_PENALTY_AMT_SUM` | dollars | Sum of linked EA penalty dollars over violations with a positive linked penalty. **Likely traces to the same underlying dollars as `penalties.PENALTY_AMOUNT`** — reconciliation deliberately left undone; don't sum the two files together without a dedup rule. | **PL4** |
| `MEAN_EVAL_TO_VIOL_LAG_DAYS` | days | Mean `(VIOL_START_DATE − EVAL_DATE)` over rows where a linked eval precedes the violation; `NaN`→`NA` when no eligible rows. | — |
| `MEAN_VIOL_TO_EA_LAG_DAYS` | days | Mean `(EA_DATE − VIOL_START_DATE)` over rows where a linked EA follows the violation; `NaN`→`NA`. | — |

## `emissions.csv.gz` — dataset 7, facility × year, combined pollutant report (EIS/TRIS/E-GGRT/CAMDBS)

Joined on `REGISTRY_ID`, not `PGM_SYS_ID` — the four source programs share only the FRS id (`EM1`). Where one
`REGISTRY_ID` maps to multiple `PGM_SYS_ID`s, the same pounds/GHG values are **broadcast identically** onto
every co-mapped `PGM_SYS_ID` (`EM2`) — flagged, not resolved.

| Field | Type | Definition & derivation | Decision |
|---|---|---|---|
| `EMISSIONS_OBSERVED` | flag | `1` iff ≥1 non-GHG (EIS/TRIS/CAMDBS) row exists for `(REGISTRY_ID, year)`, broadcast to every sharing `PGM_SYS_ID`. Never `NA` (coalesced to `0`). | EM1/EM2 |
| `GHG_OBSERVED` | flag | Same pattern, restricted to `E-GGRT` rows — gated **fully independently** of `EMISSIONS_OBSERVED`. | **EM6** |
| `VOC_LBS` / `PM10_LBS` / `PM25_LBS` / `NOX_LBS` / `SO2_LBS` / `CO_LBS` | pounds | `sum(ANNUAL_EMISSION)` matched to a single **exact** canonical `POLLUTANT_NAME` string per pollutant (e.g. "Primary PM10 (filterables and condensibles)"), never substring/regex — PM10/PM2.5 have component-variant names that are subsets of the canonical total, and naive substring matching was verified to inflate totals ~1.7×. `0` if `EMISSIONS_OBSERVED==1` but this pollutant wasn't reported; `NA` if `EMISSIONS_OBSERVED==0`. | **EM4** |
| `HAP_LBS` | pounds | `sum(ANNUAL_EMISSION[NEI_TYPE == "HAP"])` — every row tagged HAP (292 distinct pollutant names); verified no "Total HAP" aggregate row exists upstream, so plain summation doesn't double-count. | **EM5** |
| `GHG_MTCO2E` | metric tons CO2e | `sum(ANNUAL_EMISSION)` among E-GGRT rows only — a distinct unit from the pounds columns. `NA` if `GHG_OBSERVED==0`. | **EM6** |
| `N_PGM_SYS_ID_SHARING_REGISTRY` | count | Number of distinct `PGM_SYS_ID`s sharing this facility's `REGISTRY_ID`, facility-level (broadcast to all years). `NA` for facilities with a blank `REGISTRY_ID`. | **EM2** |
| `IS_SHARED_REGISTRY` | flag | `1` iff `N_PGM_SYS_ID_SHARING_REGISTRY > 1` — where `1`, the pounds/GHG values on this row are identical broadcasts shared with other `PGM_SYS_ID`s. **Do not sum emissions across facilities sharing a `REGISTRY_ID`.** | EM2 |

### Cross-file caveats (Part 1)

- **Three non-reconciling HPV/FRV definitions.** `regulatory.N_HPV`/`N_FRV` (day-zero-date presence on a
  violation row), `hpv_spells`/`hpv_active` (`ENF_RESPONSE_POLICY_CODE == "HPV"`), and
  `pipeline.N_VIOL_HPV`/`N_VIOL_FRV` (the raw ECHO pipeline's own `VIOL_TYPE` tag) answer closely related but
  distinct questions. Per diagnostic `H1`, `regulatory` and `hpv_spells` differ by only ~33 records — close,
  not identical — and neither is expected to reconcile exactly with `pipeline`.
- **Three penalty-dollar exposures that likely trace to the same underlying money.**
  `regulatory.PENALTY_AMOUNT`, `penalties.PENALTY_AMOUNT` (action grain), and `pipeline.EA_PENALTY_AMT_SUM`
  are very likely drawing on the same enforcement-action universe. Reconciliation across the three is
  deliberately left undone (`R4`/`P5`/`PL4`) — do not sum them together.
- **The same "broadcast, not resolved" fan-out pattern appears twice.** `penalties.N_SETTLEMENT_FACILITIES`/
  `IS_MULTI_FACILITY` (multi-facility settlements sharing one `ENF_IDENTIFIER`) and
  `emissions.N_PGM_SYS_ID_SHARING_REGISTRY`/`IS_SHARED_REGISTRY` (multiple `PGM_SYS_ID`s sharing one
  `REGISTRY_ID`) both expose a many-to-one join as a flag rather than resolving it — the common warning in
  both cases is "don't sum across the broadcast without deciding a rule first."

---

# Part 2 — `data/panels/` (facility spine + three sample panels)

Unlike Part 1, this layer *does* apply sample selection. `universe`, `major_synmin`, and `electric` are the
**same 111-column recipe** (`build_panel()` in `03_build_functions.R`) over three different facility filters —
documented once here rather than three times.

## Facility filters (`PANEL_SPECS`)

| Panel | Filter |
|---|---|
| `universe` | `STATE %in% CONUS` — every ever-active facility in the 48 contiguous states + DC. |
| `major_synmin` | `universe` filter **+** `AIR_POLLUTANT_CLASS_DESC %in% c("Major Emissions", "Synthetic Minor Emissions")`. |
| `electric` | `major_synmin` filter **+** NAICS 2211 (prefix-anywhere match, catches child codes like `221112`) **or** SIC 4911 (anchored exact 4-digit match) — decision `PR1`. The NAICS/SIC-OR disagreement set is an open question, `D-C1`. |

## `spine.csv.gz` — facility grain (one row per ever-active facility)

"Ever-active" = ≥1 dated event in 2005–2025 across any of the six event tables (`F1`). This is the input to
all three sample panels below; its own attribute columns are also carried unchanged into each panel row
(time-invariant across all 21 years of a facility — `P7`).

| Field | Type | Definition & derivation | Decision |
|---|---|---|---|
| `county_fips` | GEOID | Spatial join of the FRS coordinate against the county shapefile (`st_within`). `NA` if no coordinate or unplaceable. | F3/N4 |
| `coord_county_dist_km` | km | Distance from the coordinate to the ICIS-claimed county (same method as `coordinates.csv.gz`'s `COORD_COUNTY_DIST_KM`); `0` on an exact county match, `NA` if uncheckable. | N13 |
| `coord_gross_error` | flag | `1` iff checkable and distance `> 5` km; `NA` if uncheckable. | N13 |
| `facility_type` | label | Same fixed code→label lookup as `regulatory.FACILITY_TYPE`. | — |
| `op_status_current_desc` | passthrough | Same as `regulatory.OP_STATUS_CURRENT_DESC` — current, undated ICIS status description. | R5/F2 |
| `latitude` / `longitude` | numeric | FRS coordinate, same derivation as `coordinates.csv.gz`. | F3/N5 |
| `emits_voc`, `emits_pm`, `emits_co`, `emits_nox`, `emits_so2`, `emits_hap` (6 flags) | flag | Same "ever reported" logic as `regulatory.EMITS_*`. Coalesced `NA→0`. | F6 |
| `prog_sip`, `prog_titlev`, `prog_nsps`, `prog_mact`, `prog_neshap`, `prog_fesop`, `prog_nsr`, `prog_psd` (8 flags, same set as the datasets layer) | flag | Same "ever enrolled" logic as `regulatory.PROG_*`. Coalesced `NA→0`. | F6 |
| `prog_gact` | flag | `any(PROGRAM_CODE == "CAAGACTM")` — the Part 63 **area-source** counterpart to MACT; kept as its own flag (not folded into `prog_mact`) so the major/area distinction stays visible. **Present in the panel layer only** — see note below. | F6 |
| `prog_cfc` | flag | `any(PROGRAM_CODE == "CAACFC")` — Title VI stratospheric-ozone-protection program. **Present in the panel layer only** — see note below. | F6 |
| `n_programs` | count | `n_distinct(PROGRAM_CODE)` per facility, including `gact`/`cfc`. `0` (not `NA`) for a facility with no `programs.csv.gz` record at all — read as "no enrollment record," not "confirmed unenrolled" (`N7`). | F6/N7 |
| `program_begin_year` | year | Earliest parseable `BEGIN_DATE` year across `programs.csv.gz`, guarded to `[1900, 2026]`. `NA` if no valid year survives. | F6 |
| `entered_year` | year | First wayback snapshot year the facility is OPERATING. | F7 |
| `exited_year` | year | First year *after which* the facility is never operating again — defined off the **last** operating year (reopening-robust: a mid-window close→reopen doesn't fabricate a spurious early exit). This one-row summary collapses any genuine *interior* closure — 0.26% of ever-operating facilities have one; the panel's year-varying `operating`/`op_status_code` columns retain the true sequence. | F7/N9 |
| `exit_source` | categorical | `"cls"` / `"other"` / `"dropout"` (last seen operating, then vanished — kept distinct from `cls` since disappearance can be an ICIS extract artifact, unresolved open question `D-C4`) / `NA` (never exited). | F7/N8 |
| `left_censored` / `right_censored` | flag | `1` if already operating at the first (2015) / still operating at the last (2025) wayback snapshot. | F7 |

## The shared 111-column panel recipe (`universe`/`major_synmin`/`electric`)

Balanced facility × year rectangle, 2005–2025, built by `build_panel()`: full-join five per-source
aggregators → left-join onto the balanced rectangle → compute `any_*` → attach HPV status → attach penalty →
attach wayback → `code_known_zeros()` (order is load-bearing).

**Inspections, violations, enforcement, certifications, stack tests** — every `n_*`/`_dup`/`_dup_exact` column
in these five blocks is derived **identically** to its `N_*` counterpart in `regulatory.csv.gz` above (same
source tables, same logic, only casing differs). Two panel-layer-only additions:

| Field | Type | Definition & derivation | Decision |
|---|---|---|---|
| `n_penalties` | COUNT_COL | Same as `regulatory.N_PENALTIES`, but computed inside the enforcement aggregator specifically so it inherits COUNT_COL/known-zero treatment — diverges from `penalty_amount` below: an observed facility-year with a $0/no-penalty formal action reads `n_penalties = 0` **and** `penalty_amount = NA` simultaneously. | **N14** |
| `n_penalties_dup` | COUNT_COL | Of the penalty-bearing formal rows, how many are event-key duplicates. | N14 |

**Any-flags and observation source**

| Field | Type | Definition & derivation | Decision |
|---|---|---|---|
| `any_inspections` / `any_violations` / `any_enforcement` / `any_certs` | flag | `1` iff the matching `n_*` count `> 0`; NA-safe (an `NA` count propagates to `NA` here). | P5 |
| `obs_source` | categorical | `"event"` — the facility-year appeared in ≥1 of the five event aggregators (some measure has a real count); `"operating"` — no event, but the wayback snapshot says `operating == 1` that year (a genuine **structural zero**, 2015–2025 only); `"unobserved"` — neither (includes all pre-2015 zero-event years and closed/`CLS` zero-event years). This is the flag `code_known_zeros()` uses to turn `NA` counts into `0` for the `"operating"` rows — the mechanism behind the whole zero-vs-NA discipline for this layer. | **W6** |

**Facility attributes** — identical derivations to the `spine.csv.gz` table above (same columns, riding along
unchanged across all 21 rows of a `PGM_SYS_ID` — `P7`); not repeated here.

**Wayback status** (year-varying, `NA` outside 2015–2025 and for the facility's uncovered years — `W3`/`W7`)

| Field | Type | Definition & derivation | Decision |
|---|---|---|---|
| `op_status_code` | passthrough | Raw wayback operating-status code, forward-filled (LOCF) across interior gaps within a facility's observed span, never extrapolated at the edges. | W1/W4 |
| `operating` | flag | `1` iff `op_status_code %in% c("OPR","TMP","SEA")`. Drives the `"operating"` branch of `obs_source`. | W2 |
| `prog_sip_active` … `prog_fesop_active` (7 flags: sip/titlev/nsps/mact/gact/neshap/fesop) + `prog_cfc_active` | flag | `1` iff the facility carries ≥1 matching program row whose that-year status is in `{OPR,TMP,SEA}` (the "operating-program" rule), given the facility is present in that year's snapshot; `NA` if the facility's status that year is blank/`CLS`, or the facility isn't in that snapshot at all. | **W5**, **N11** |
| `prog_nsr_active` / `prog_psd_active` | flag | **Preconstruction-program rule**: `1` iff ≥1 matching row with status in `{OPR,TMP,SEA}` **or** `{PLN,CNS}` (planned/under-construction) — these permits attach *before* a source operates, so these two flags can be `1` while `operating = 0`. | **N11** |

> **Note — `prog_gact`/`prog_gact_active`/`prog_cfc`/`prog_cfc_active` exist in the panel layer but not
> `data/datasets/`.** This is a deliberate scope difference, not an inconsistent derivation: dataset 1
> (`operating.csv.gz`) narrows to the same 8 program groups as dataset 0 (`O3`), while the panel/spine layer
> keeps all 10 groups the underlying wayback-programs data actually carries. `n_programs`/`N_PROGRAMS` in both
> layers already count all 10 regardless of which per-group flags are exposed.
>
> **Documentation-drift note (found while compiling this dictionary, 2026-07-27):** `panel_construction_decisions.md`'s
> `W5` and `N10` entries describe "the 8 spine groups" / "every one of the 8 flags" — that predates `gact`/`cfc`
> being added; the code and the actual 111-column header both carry 10. See the addendum added at those entries.

**HPV interval status**

| Field | Type | Definition & derivation | Decision |
|---|---|---|---|
| `hpv_active` | flag | Built from violation-row HPV spells (`HPV_DAYZERO_DATE`/`HPV_RESOLVED_DATE`, `dup==0` kept — the one count-family exception to "no dedup," since this is a status flag not a count); spell end = resolved date if valid, else Dec 31 of the day-zero year; overlapping spells at a facility are **merged/unioned**. `1` iff any spell overlaps the year (never masked by other-measure unobserved status — can be `1` even where `any_violations` is `NA`); `0` if checked and no overlap; `NA` if unobserved and no overlap. Distinct from `n_hpv` (a recorded-year count, not a status) — 69% of resolved HPV spells span more than one calendar year, so the two disagree by design. | **P8**, **V6** |
| `hpv_active_1mo` | flag | Same spell construction; `1` iff the unioned overlap days for the year `> 30` (operationalizes "in HPV status for more than a month"). | P8/V6 |

**Penalty**

| Field | Type | Definition & derivation | Decision |
|---|---|---|---|
| `penalty_amount` | dollars | `sum(parse_number(PENALTY_AMOUNT), na.rm=TRUE)` over **all** formal rows (dup and non-dup) for the facility-year; then set to `NA` whenever the sum is zero **or** missing — a separate rule from the `obs_source`/COUNT_COLS convention, and explicitly exempt from `code_known_zeros()`'s NA→0 fill. Can include a broadcast multi-facility settlement penalty repeated across co-defendants — don't sum across facilities. | E3 |
| `penalty_amount_dup` | dollars | Dollars contributed specifically by event-key duplicate rows. | — |

> **Documentation-drift note (found while compiling this dictionary, 2026-07-27):** `panel_construction_decisions.md`'s
> `E4` entry describes penalties as filtered to `dup==0` before summing — that's superseded by the file's own
> 2026-07-17 revision banner; the current `attach_penalty()` sums **all** rows and reports the dup dollars
> separately in `penalty_amount_dup`, matching what's actually in `03_build_functions.R` and in the data. See
> the addendum added at that entry.

### Cross-cutting notes (Part 2)

- **`obs_source` is context-dependent.** Within an already-filtered "operating" subsample, `obs_source ==
  "event"` is mechanically equivalent to "some count > 0" — conditioning on it there is conditioning on the
  outcome. Across the full panel (all years), it carries independent information by separating `"unobserved"`
  from real zeros — that's the whole point of the convention (`W6`/`N16`).
- **`n_hpv` and `hpv_active`/`hpv_active_1mo` answer different questions** and will disagree year to year
  (`N6`) — use the interval flags for a status question, the recorded-year count for an events question.
