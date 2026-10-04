# CAA Regulatory Data — Data Dictionary: Derived Layer

Column-by-column documentation for every **created/derived** variable in this repo — the nine built datasets
in [`data/datasets/`](../data/datasets/README.md) (built by [`code/03_datasets`](../code/03_datasets/README.md))
and the two facility × year panels in [`data/panels/`](../data/panels/README.md) (built by
[`code/04_panel_building`](../code/04_panel_building/README.md)). For **raw** EPA source fields, see
[`data_dictionary.md`](data_dictionary.md); this file only covers columns that are computed, aggregated, or
recoded by this repo's build code. For the *why* behind a specific choice, find its decision code (e.g. `R2`,
`H6`, `O6`) in [`briefs/datasets/dataset_construction_decisions.md`](../briefs/datasets/dataset_construction_decisions.md)
(Part 1 below) or its `PB`-prefixed counterpart in
[`briefs/panel/panel_construction_decisions.md`](../briefs/panel/panel_construction_decisions.md)
(Part 2 below) — this file gives the *what/how*, not the full rationale.

> **Verified against code.** Part 1 was re-checked directly against the build scripts (`code/03_datasets/*.R`)
> and `briefs/datasets/dataset_construction_decisions.md` on 2026-07-29 (picking up the 2026-07-28 `R9`
> derivation fixes — `EMITS_VOC`, `N_VIOL_NSPS`, `N_PENALTY_ACTION` — and the `R6` `EMITS_HAP` addendum, all
> of which this file had missed in the prior pass) and against the actual `.csv.gz` headers on disk as of
> 2026-07-27. Part 2 was rewritten 2026-07-29 against the
> current `code/04_panel_building/*.R` build scripts (which replaced the archived `code/03_panel_building/`
> pipeline this file used to describe — see `archive/panel_building_legacy/README.md`) — not yet re-checked
> against a freshly rebuilt panel file, since a Wayback-snapshot redownload is in progress upstream as of this
> writing; re-verify column names/counts against the rebuilt `.csv.gz` headers once that lands.

## Conventions used throughout

- **Casing.** Both layers are **fully `UPPER_SNAKE_CASE`** — `data/datasets/` builders assemble in lowercase,
  then uppercase once on write (decision `G2`); `data/panels/` reads columns directly off the
  already-uppercase datasets layer with no separate casing step of its own (`code/04_panel_building/README.md`'s
  Conventions section), so there's no mixed casing between the two layers as of the current
  (`code/04_panel_building/`) pipeline.
- **Join keys.** Every file in both layers carries `PGM_SYS_ID` (the ICIS-Air facility id) and `REGISTRY_ID`
  (the cross-program FRS facility id, `NA` where no FRS match — `G4`). Facility-year files join `(PGM_SYS_ID,
  YEAR)` 1:1 onto one another; event-grain files (`hpv_spells`, `penalties`) join many-to-one via
  `PGM_SYS_ID` (+ year where relevant).
- **The zero-vs-NA discipline (the single most load-bearing convention in this repo).** Every count/status
  column in a facility-year file is gated by an observability flag for that file (`ICIS_OBSERVED`,
  `WAYBACK_OBSERVED`, `PIPELINE_OBSERVED`, `EMISSIONS_OBSERVED`/`GHG_OBSERVED`, or the panel layer's
  `OBS_SOURCE`). Within an **observed** facility-year, a `0` is a confirmed true zero; an **unobserved**
  facility-year is `NA` — we simply don't know. Never treat `NA` as `0`, and never assume `0` means "checked
  and none happened" without first checking the observability flag. Below, a column tagged **COUNT_COL**
  follows this rule; a handful of dollar/lag columns (`PENALTY_AMOUNT`, `MEAN_*_LAG_DAYS`) follow a
  *different*, narrower rule ("no value or zero → `NA`") that's called out explicitly where it applies.
- **Duplicates are surfaced, never dropped.** Every `N_*`/`n_*` count counts **all rows** of its source event
  table, with no deduplication. Where an asset carries duplicate event-key rows (inspections, enforcement,
  certs), a companion `_DUP`/`_dup` (event-key repeat) and `_DUP_EXACT`/`_dup_exact` (byte-identical repeat)
  column reports how many of those rows were duplicates; recover the event-distinct count as `n_x − n_x_dup`.
  Violations and stack tests carry zero dups **enforced via `stopifnot()` at build time**
  (`01_regulatory.R:146,216`) — not merely a comment — so they carry no `_dup` columns.

---

# Part 1 — `data/datasets/` (the nine built datasets)

Each dataset is built once over the **full** 279,665-facility ICIS-Air universe (no ever-active screen, no
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
| `N_VIOL_SIP` / `N_VIOL_TITLEV` / `N_VIOL_NSPS` / `N_VIOL_MACT` / `N_VIOL_FESOP` | COUNT_COL | Match against `PROGRAM_CODES` with explicit `\b`-bounded codes (State Implementation Plan / Title V Permits / New Source Performance Standards / MACT Standards / Federally-Enforceable State Operating Permit). **Fixed 2026-07-28 (`R9`):** was a `grepl()` substring match against `PROGRAM_DESCS`, which let `N_VIOL_NSPS` scope-creep into `CAANSPSM`'s description by substring accident (418 rows) — now coded, not coincidental, and matches `PROG_NSPS`'s deliberate `CAANSPS`+`CAANSPSM` pooling (`R6`) by design. Overlapping, not partitioning — need not sum to `N_VIOLATIONS`. | **R9** |
| `N_VIOL_EPA` / `N_VIOL_STATE` / `N_VIOL_LOCAL` | COUNT_COL | `AGENCY_TYPE_DESC` bucketed to federal / state / local (see agent report for exact string sets). | R3 |
| `N_ENFORCEMENT` | COUNT_COL | Count of pooled `formal_actions` + `informal_actions` rows for the facility-year. | R2 |
| `N_FORMAL` / `N_INFORMAL` | COUNT_COL | Partition of `N_ENFORCEMENT` by source table. | R3 |
| `N_PENALTY_ACTION` | COUNT_COL | `grepl("^113D1", ENF_TYPE_CODE)`, pooled. **Fixed 2026-07-28 (`R9`):** was an exact match `ENF_TYPE_DESC == "CAA 113D1 Action For Penalty"`, which missed four 112(r)/MRR expedited-settlement variants of the same action (`ENF_TYPE_CODE` `113D1E`/`113D1E1`/`113D1E2`/`113D1E3`) — a 201-row (~2.9%) undercount of the true 113D1 family. | **R9** |
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
| `EMITS_PM` / `EMITS_CO` / `EMITS_NOX` / `EMITS_SO2` | flag | "Ever reported" flag from `pollutants.csv.gz`: `any(grepl(<pattern>, POLLUTANT_DESC, ignore.case=TRUE))` per facility (Particulate Matter / Carbon Monoxide / Nitrogen Oxides / Sulfur Dioxide). Undated, boolean only — **not** a measured quantity (contrast with `emissions.csv.gz`'s pounds columns). Each backed by only 1–8 distinct `POLLUTANT_CODE` values, so the plain substring match is safe here. Facility absent from `pollutants.csv.gz` → coalesced to `0` (a true "no profile" reading, not missing data). | **R6** |
| `EMITS_VOC` | flag | Same "ever reported" pattern, but with a negative-lookbehind regex `(?<!NON-)VOLATILE ORGANIC` on `POLLUTANT_DESC`. **Fixed 2026-07-28 (`R9`):** the old plain `grepl("VOLATILE ORGANIC", ...)` matched `POLLUTANT_CODE 300000310` "NON-VOLATILE ORGANIC COMPOUNDS" as a false positive, flipping 30 facilities from `1` to the correct `0`. | **R9** |
| `EMITS_HAP` | flag | "Ever reported" flag, but **not** a single-pattern match: (a) a CAS (Chemical Abstracts Service registry number)-number join against the official CAA §112(b) HAP list (188 substances, `code/03_datasets/hap_list_112b.R`), **unioned with** (b) the original umbrella-phrase rule (`grepl("HAZARDOUS AIR POLLUTANT", POLLUTANT_DESC)`) and (c) a name match for 17 CAS-less compound-class entries (e.g. "Chromium Compounds"). **Fixed 2026-07-28 (`R6` addendum):** the pre-fix rule was (b) alone, which missed the large majority of HAPs that ICIS-AIR records under a specific chemical name (Benzene, Formaldehyde, Lead, Mercury, ...) rather than the umbrella phrase. (b) was kept, not dropped, because it independently catches a real signal: an aggregate `"TOTAL HAZARDOUS AIR POLLUTANTS (HAPS)"` summary record (no CAS) that some facilities report instead of itemizing species. Full-universe `EMITS_HAP=1` count post-fix: 67,011 of 279,665 (24.0%). A coverage diagnostic prints on every build (`pollutants coverage: N/M rows (%) match none of the six EMITS_* categories`). | **R6** |
| `PROG_SIP` / `PROG_TITLEV` / `PROG_NSPS` / `PROG_MACT` / `PROG_NESHAP` / `PROG_FESOP` / `PROG_NSR` / `PROG_PSD` | flag | "Ever enrolled" flag from `programs.csv.gz` by `PROGRAM_CODE` (SIP=`CAASIP`, Title V=`CAATVP`, NSPS=`CAANSPS`+`CAANSPSM` pooled, MACT=`CAAMACT`, NESHAP=`CAANESH`, FESOP=`CAAFESOP`, NSR=`CAANSR`, PSD=`CAAPSD`). This is a deliberately **narrowed 8-group set** — `CAAGACTM` (area-source MACT) and `CAACFC` (Title VI ozone) are excluded here to match dataset 1's 8-group `PROG_*_ACTIVE` allowlist, even though the panel layer (Part 2) keeps all 10 groups. Coalesced `NA→0`. | **R6** (aligns w/ `O3`) |
| `N_PROGRAMS` | count | `n_distinct(PROGRAM_CODE)` per facility, **including** GACT/CFC (broader scope than the 8 `PROG_*` flags above). Facility-level, **not** subject to the coalesce-to-0 step. | **R7** |

## `operating.csv.gz` — dataset 1, facility × year, Wayback reconstruction

Same 279,665 × 21-year rectangle as dataset 0 (1:1 joinable); strictly raw — year-varying fields are `NA`
wherever no Wayback snapshot exists, never imputed (`O2`).

| Field | Type | Definition & derivation | Decision |
|---|---|---|---|
| `WAYBACK_OBSERVED` | flag | `1` iff `wayback_facility_status.csv.gz` has a snapshot for `(PGM_SYS_ID, year)`. Always 0/1, never itself `NA`. | O2 |
| `OP_STATUS_CODE` / `OP_STATUS_DESC` | passthrough | Wayback-reconstructed operating-status code/description for that year. `NA` for 2005–2014 and any uncovered facility-year. | O2 |
| `OPERATING` | flag | `1` iff `OP_STATUS_CODE %in% c("OPR","TMP","SEA")`; carried unchanged from the cleaning layer, **except** the `OPERATING_IMPUTED==1` rows below, where it's bridge-imputed rather than code-derived. `NA` outside wayback coverage. | O3 |
| `OPERATING_IMPUTED` | flag (NEW 2026-07-30) | `1` iff this row is 2018 AND `OPERATING` was bridge-imputed from a matching real 2017/2019 observation (both in-service, or both not); `0` otherwise, never `NA`. The one exception to `O2`'s "strictly raw" rule — see `O2` for the full derivation and the checks (panel eligibility, entry/exit spells) that were verified unaffected before adding it. `OP_STATUS_CODE`/`OP_STATUS_DESC` are never fabricated for these rows (stay `NA`) and `WAYBACK_OBSERVED` stays `0` (no real snapshot exists) — this column is the only signal that `OPERATING` is inferred rather than observed here. | **O2** |
| `PROG_SIP_ACTIVE`, `PROG_TITLEV_ACTIVE`, `PROG_NSPS_ACTIVE`, `PROG_MACT_ACTIVE`, `PROG_NESHAP_ACTIVE`, `PROG_FESOP_ACTIVE`, `PROG_NSR_ACTIVE`, `PROG_PSD_ACTIVE` (8 flags) | flag | From `wayback_program_status.csv.gz`, an explicit 8-group allowlist (chosen to guard against upstream schema drift after `gact`/`cfc` were silently added elsewhere) — "is this program group active in this year's wayback snapshot." `NA` where the facility isn't covered by that year's snapshot. | **O3** |
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
| `OP_STATUS_CODE` / `OP_STATUS_DESC` / `OPERATING` / `OPERATING_IMPUTED` | passthrough / flag | Same definitions as `operating.csv.gz`'s columns of the same name. | O7, O2 |
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
| `HPV_ACTIVE` | flag | Built from `hpv_spells`: drop `missing_start` spells (no interval to test); screen day-zero year to `[1970, 2025]` (excludes 268/44,744 mappable spells, catching e.g. a mistyped `0218` that would spuriously flag 2005–2017 — `H7`); compute a conservative closing date (`resolved` if `closed`, else Dec 31 of the day-zero year for `open`/`bad_order` — chosen over alternatives in diagnostic 09, `H5`); `1` if any qualifying spell's interval overlaps the calendar year (can be `1` even where `ICIS_OBSERVED == 0` — a spell always wins); `0` if no overlap but `ICIS_OBSERVED == 1` (true zero, reusing dataset 0's flag rather than inventing a new one — `H6`); `NA` if no overlap and unobserved. | **H5** (collapse rule), **H6** (zero-vs-NA reuse), **H7** (day-zero screen) |

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

> **Caveat (`P5`).** As of 2026-07-27, 571 settlements span more than one facility; the penalty is usually one
> dollar figure repeated across co-defendants (507 of 571), but 64 settlements carry *differing* per-facility
> amounts. Do not sum `PENALTY_AMOUNT` across a settlement's facilities without first deciding a broadcast
> rule — see `briefs/datasets/multi_facility_settlement_decision.md`.

## `coordinates.csv.gz` — dataset 4, one row per facility

Coordinate source: FRS via `REGISTRY_ID` (`C1`); full 279,665-facility universe (`C4`).

| Field | Type | Definition & derivation | Decision |
|---|---|---|---|
| `ICIS_COUNTY_FIPS` | GEOID | The ICIS-*claimed* county resolved to a GEOID: `(STATE, COUNTY_NAME)` normalized (case, "(city)"/"County"/"Parish"/etc. suffix stripping, "Saint"→"St") and matched against a name crosswalk built from the county shapefile. Independent of any coordinate. `NA` if the normalized name doesn't resolve to exactly one GEOID in this shapefile vintage. | **C5** |
| `LATITUDE` / `LONGITUDE` | numeric | `FRS_FACILITIES.csv`'s `LATITUDE_MEASURE`/`LONGITUDE_MEASURE`, joined via `REGISTRY_ID` (first record kept if multiple). `NA` if no FRS match. | **C1** |
| `HAS_COORDINATE` | flag | `1` iff both lat/lon are non-missing. | C1 |
| `COUNTY_FIPS` | GEOID | Point-in-polygon spatial join (`st_within`) of the FRS coordinate against the county shapefile — the county the *coordinate itself* falls in, computed only where a coordinate exists. `NA` for non-CONUS facilities (shapefile is CONUS+DC only) or points outside every polygon. | **C2** |
| `COORD_COUNTY_DIST_KM` | km | Distance from the coordinate to the ICIS-claimed county's polygon, via a direct **geodesic** distance. **`0` by construction** where `COUNTY_FIPS == ICIS_COUNTY_FIPS` (no distance computed, exact match); a real distance value only for the checkable-and-mismatched subset. `NA` if uncheckable (no coordinate, or `COUNTY_NAME` unresolvable). `0 ≠ NA` is strictly honored — don't treat a missing check as agreement. **Fixed 2026-07-28 (`C3` addendum):** was reprojected into EPSG:5070 (NAD83 / Conus Albers), valid only for CONUS — Alaska mismatches diverged from the true geodesic distance by up to ~21% (e.g. 817 km vs 993 km); CONUS distances were negligibly affected (mean 0.11 km). `COORD_GROSS_ERROR` itself likely never flipped from this fix (every affected mismatch was well past the 5 km cutoff either way), but the distance number wasn't trustworthy outside CONUS before it. | **C3** |
| `COORD_GROSS_ERROR` | flag | `1` iff checkable and `COORD_COUNTY_DIST_KM > 5` (km). `NA` exactly where `COORD_COUNTY_DIST_KM` is `NA`. | **C3** |

## `pipeline.csv.gz` — dataset 6, facility × year, EPA ECHO "CAA Compliance Pipeline"

As of 2026-07-27 (automated fetch — this drifts with each live source refresh), 7,218 of 66,723 raw rows are
EPA linkage-helper placeholders (no real violation date) and are excluded (`PL1`). Year anchor is
`VIOL_START_DATE`, deliberately not the cleaned asset's own `date` (which can trace to a later
enforcement/eval date and would misdate the violation — `PL2`). Universe: the same 279,665 × 21 rectangle as
datasets 0/1/2b (`PL3`).

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

# Part 2 — `data/panels/` (two panels, built by `code/04_panel_building/`)

**This entire part was rewritten 2026-07-29** — it used to describe the archived `code/03_panel_building/`
pipeline (a facility spine + three sample panels: `universe`/`major_synmin`/`electric`, 111 lowercase-`snake_case`
columns). That pipeline is archived in full (`archive/panel_building_legacy/README.md`); the current
`code/04_panel_building/` pipeline builds from `data/datasets/` instead of `data/processed/` directly, ships
**exactly two panels**, no persisted spine file, and uses the same `UPPER_SNAKE_CASE` casing as Part 1
throughout. See `code/04_panel_building/README.md` and `briefs/panel/panel_construction_decisions.md` (`PB1`–`PB8`)
for the full "why."

`major_synmin_2015_2025` and `electric_2015_2025` are the **same column recipe** (`build_panel()` in
`03_build_functions.R`) over two different facility filters, both drawn from one shared in-memory candidate
set (`00_spine.R`'s `spine` — CONUS + Major/Synthetic-Minor class; not written to disk, since only these two
panels ever consume it in the same R session — `PB1`).

## Facility filters (`PANEL_SPECS`)

| Panel | Filter |
|---|---|
| `major_synmin_2015_2025` | `STATE` in the 48 contiguous states + DC, **+** `AIR_POLLUTANT_CLASS_DESC %in% c("Major Emissions", "Synthetic Minor Emissions")`, **+** `EVER_ACTIVE` (see below). |
| `electric_2015_2025` | the above **+** NAICS 2211 (prefix-anywhere match, catches child codes like `221112`) **or** SIC 4911 (anchored exact 4-digit match). |

`EVER_ACTIVE` (**revised 2026-07-29, explicit user decision — `PB2`**): `1` iff `ACTIVE_BROAD == 1`
(`operating.csv.gz`, dataset-layer decision `O6`) in **at least one** of the 11 years 2015–2025 —
`any(ACTIVE_BROAD == 1, na.rm = TRUE)`. Originally required `ACTIVE_BROAD == 1` in *every* year
("continuously active," `all(...)`); retired because that screen dropped exactly the facilities most likely
to exit *because of* enforcement/penalty outcomes — survivorship bias in a panel meant to study enforcement
and compliance. `EVER_ACTIVE` itself rides along as a column in both built panels, constant `TRUE` on every
row (a facility that failed the screen is never in the panel to begin with) — present for traceability, not
because it varies within either file.

Grain: `PGM_SYS_ID × YEAR`, window **2015–2025 only** (`PB3`) — not the repo-wide 2005–2025, since the
eligibility screen and both panels are already restricted to this span. Every eligible facility gets a full
11-year rectangle of rows (`build_panel()`'s `expand_grid`) regardless of which year(s) made it eligible —
years outside its actual activity read as `OBS_SOURCE == "unobserved"` (see below), not as missing rows.

## Facility-level attributes (constant across all 11 rows of a `PGM_SYS_ID`)

Read straight from `regulatory.csv.gz`/`coordinates.csv.gz`/`operating.csv.gz` (Part 1) by `00_spine.R`, with
no panel-specific re-derivation — same columns, same casing, same decisions as their Part 1 entries above.

| Field | Type | Definition & derivation | Decision |
|---|---|---|---|
| `REGISTRY_ID`, `FACILITY_NAME`, `STREET_ADDRESS`, `CITY`, `COUNTY_NAME`, `STATE`, `ZIP_CODE`, `EPA_REGION`, `NAICS_CODES`, `SIC_CODES`, `FACILITY_TYPE_CODE`, `FACILITY_TYPE`, `AIR_POLLUTANT_CLASS_DESC` | passthrough | Identical to their `regulatory.csv.gz` entries in Part 1 (current ICIS snapshot, time-invariant). | R5 |
| `EMITS_VOC` / `EMITS_PM` / `EMITS_CO` / `EMITS_NOX` / `EMITS_SO2` / `EMITS_HAP` | flag | Identical to `regulatory.csv.gz`'s columns of the same name. | R6 |
| `PROG_SIP` / `PROG_TITLEV` / `PROG_NSPS` / `PROG_MACT` / `PROG_NESHAP` / `PROG_FESOP` / `PROG_NSR` / `PROG_PSD` | flag | Identical to `regulatory.csv.gz`'s columns of the same name — the same narrowed **8-group** set (no `GACT`/`CFC`), matching dataset 1's `PROG_*_ACTIVE` allowlist. Unlike the archived pipeline, the panel layer does **not** carry a 10-group version — `PROG_GACT`/`PROG_CFC` don't exist anywhere in this pipeline. | R6 |
| `N_PROGRAMS` | count | Identical to `regulatory.csv.gz`'s column — `NA`-able, **never** coalesced to `0` (unlike the archived pipeline's `n_programs`, which did coalesce). A facility absent from `programs.csv.gz` reads `NA`, not `0`. | R7, PB6 |
| `LATITUDE` / `LONGITUDE` / `HAS_COORDINATE` / `COUNTY_FIPS` / `ICIS_COUNTY_FIPS` / `COORD_COUNTY_DIST_KM` / `COORD_GROSS_ERROR` | numeric/flag/GEOID | Identical to their `coordinates.csv.gz` entries in Part 1. | C1–C5 |
| `COORD_NO_COUNTY_MATCH` | flag | Panel-layer-only derivation (`coordinates.csv.gz` doesn't ship this exact flag): `1` iff `HAS_COORDINATE == 1` but the point-in-polygon lookup still failed to land in any county polygon — distinct from `HAS_COORDINATE == 0` (no coordinate to begin with). | — |
| `ENTERED_YEAR` / `EXITED_YEAR` / `EXIT_SOURCE` | year / categorical | Identical to their `operating.csv.gz` entries in Part 1 (wayback-derived facility-level spell fields, `O4`). | O4 |
| `EARLIEST_PROGRAM_BEGIN_YEAR` / `EARLIEST_PROGRAM_BEGIN_YEAR_RAW` | year | Identical to their `operating.csv.gz` entries in Part 1. | O5 |
| `EVER_ACTIVE` | flag | The panel's own eligibility screen (see above) — always `TRUE` within either built panel. | PB2 |

**Removed from the panel, 2026-07-29 (explicit user decisions):**
- **`OP_STATUS_CURRENT_DESC`** (the static, current-ICIS-snapshot status Part 1's `regulatory.csv.gz` carries,
  `R5`) — excluded here to avoid it being mistaken for the panel's genuinely year-varying operating-status
  evidence (`OP_STATUS_CODE`/`OPERATING`/`ACTIVE`/`ACTIVE_BROAD`, below). Still available directly from
  `regulatory.csv.gz` for anyone who wants the current snapshot specifically.
- **`LEFT_CENSORED`/`RIGHT_CENSORED`** — dropped as a derived convenience on top of `ENTERED_YEAR`/
  `EXITED_YEAR`/`EXIT_SOURCE`, which already carry the same entry/exit information directly.

## Year-varying block (facility × year, `build_panel()`)

**Event counts** — every `N_*`/`_DUP`/`_DUP_EXACT` column, plus `PENALTY_AMOUNT`/`PENALTY_AMOUNT_DUP`, is a
direct passthrough of its identically-named `regulatory.csv.gz` column (Part 1) — same source tables, same
logic, same zero-vs-NA gate (`ICIS_OBSERVED`), no re-derivation at this layer. Not repeated here; see Part 1's
`regulatory.csv.gz` table.

| Field | Type | Definition & derivation | Decision |
|---|---|---|---|
| `ANY_INSPECTIONS` / `ANY_VIOLATIONS` / `ANY_ENFORCEMENT` / `ANY_CERTS` | flag | `1` iff the matching `N_*` count `> 0`; NA-safe (`NA > 0` is `NA`, so an unobserved facility-year reads `NA` here too, never a silent `0`). | — |
| `OP_STATUS_CODE` / `OPERATING` / `OPERATING_IMPUTED` / `PROG_SIP_ACTIVE` … `PROG_PSD_ACTIVE` (8 flags, same set as the facility-level `PROG_*` above) / `ICIS_OBSERVED` / `EMISSIONS_OBSERVED` / `GHG_OBSERVED` / `ACTIVE` / `ACTIVE_BROAD` | passthrough / flag | Direct passthrough of their identically-named `operating.csv.gz` columns (Part 1) — no panel-specific re-derivation. `PROG_NSR_ACTIVE`/`PROG_PSD_ACTIVE` inherit the dataset layer's preconstruction-program rule (`{PLN,CNS}` counts as active, since these permits attach before a source operates). `OPERATING_IMPUTED` lets a user identify/exclude the 2018 bridge-imputed rows (`O2`) if they want raw-observation-only analysis. | O2, O3, O6 |
| `HPV_ACTIVE` | flag | Direct passthrough of `hpv_active.csv.gz` (Part 1) — the R2 interval-overlap collapse, `H5`/`H6`/`H7` zero-vs-NA discipline. **No `HPV_ACTIVE_1MO` variant** — `hpv_active.csv.gz` never shipped it, and recomputing a third implementation of the same interval logic was explicitly ruled out. | H5–H7, PB7 |
| `OBS_SOURCE` | categorical | The one piece of real logic this layer adds. **Revised 2026-07-30 (`PB4`):** now a four-way split. `"event"` = `ICIS_OBSERVED == 1` (a real ICIS record that year); `"operating"` = no ICIS event but `ACTIVE_BROAD == 1` (confirmed active some other way — a genuine structural zero); `"confirmed_inactive"` = no ICIS event but `ACTIVE_BROAD == 0` (every checked signal — wayback status, emissions/GHG reporting — positively confirms the facility was NOT active that year — also a genuine structural zero, previously mislabeled `"unobserved"`); `"unobserved"` = no ICIS event and `ACTIVE_BROAD` is genuinely `NA` (no evidence either way that year — the only truly unknown case). `ACTIVE_BROAD`'s own 0-vs-`NA` distinction (`O6`) was already computed correctly upstream; this split just stops discarding it. Checked directly: 33% of major_synmin's pre-fix `"unobserved"` facility-years (30,612 of 92,013) actually had `ACTIVE_BROAD == 0`. **Revised 2026-07-29 (`PB2`/`PB4`):** under the old all-11-years eligibility screen, `"unobserved"`-type rows were impossible by construction; under the current ≥1-year rule they're real and substantial, since a facility can qualify via one year while other years in its 11-year rectangle have no confirmed activity. | PB4 |

**The known-operating-zero fill:** for rows with `OBS_SOURCE %in% c("operating", "confirmed_inactive")`,
every `N_*` count and `HPV_ACTIVE` is filled `NA → 0` — a facility-year we know was active, or know was
inactive, with no ICIS event is a true zero either way, not unknown. `PENALTY_AMOUNT`/`PENALTY_AMOUNT_DUP` are
**deliberately excluded** from this fill in both branches — a known-outcome, zero-ICIS-event facility-year
still reads `NA` for `PENALTY_AMOUNT` (no confirmed formal action), matching the dataset layer's own `R4`
convention.

### Cross-cutting notes (Part 2)

- **`OBS_SOURCE` is context-dependent**, same as its predecessor concept was: within an already-filtered
  `"operating"` subsample, `OBS_SOURCE == "event"` is mechanically equivalent to "some count > 0" —
  conditioning on it there is conditioning on the outcome. Across the full panel it carries independent
  information by separating `"unobserved"`/`"confirmed_inactive"` from real, event-generating activity.
- **This layer carries no separate HPV-count column of its own** (unlike the old `hpv_active`/`hpv_active_1mo`
  vs. a spine-level recorded-year count) — `N_HPV` (an event count, from `regulatory.csv.gz`) and `HPV_ACTIVE`
  (an interval-overlap status, from `hpv_active.csv.gz`) answer different questions and will disagree year to
  year; use the interval flag for a status question, the recorded-year count for an events question.
