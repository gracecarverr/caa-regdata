# Dataset Construction Decisions

> Scope: the **`code/03_datasets/` layer** (renamed from `code/04_datasets/`, see the panel-building
> addendum below) — the nine deliverable datasets that supersede the single wide panel, now this repo's
> main product. This layer never depends on the panel-building code — the dependency runs the other way as
> of 2026-07-28 (see below). It consumes the `data/processed/` cleaned assets directly. The PM2.5-attainment
> slice of the old panel layer specifically (`01_attainment.R`, `data/raw/greenbook/`) was removed from this
> repo entirely on 2026-07-27 — that code was already synced to the CAA_Project repo on 2026-07-23 and lives
> there now; see decision W10 in
> `archive/panel_building_legacy/briefs/panel/panel_construction_decisions.md` (the archived version of the
> old panel decisions doc — see the addendum just below for why it's archived).
>
> **Addendum (2026-07-28):** `RUN_ALL.R`'s datasets-loop run order is no longer the plain `01..08` numeric
> sequence — `08_emissions.R` now runs before `02_operating.R` (right after `01_regulatory.R`), because
> `02_operating.R` reads both `regulatory.csv.gz` and `emissions.csv.gz` as of this session (O6). The `01..08`
> file-name prefixes still match the stable "dataset 0..7" IDs used throughout this doc — they were never a
> build-order guarantee — but this is the first time the *actual* run order has diverged from that numbering,
> so it's flagged here rather than left implicit. `08_emissions.R` itself has no dependency on any other
> dataset in this layer (checked directly), so moving it earlier is safe.
>
> **Addendum (2026-07-28), panel-building inverted:** the old facility-spine/three-sample-panel pipeline
> (`code/03_panel_building/`, built directly from `data/processed/`) has been **archived in full** —
> code, its 2026-07-28 data outputs, and its docs — to `archive/panel_building_legacy/` (see that
> directory's README for why archived rather than converted in place). It's replaced by
> `code/04_panel_building/`, which builds exactly two panels
> (originally `major_synmin_continuous_2015_2025`/`electric_continuous_2015_2025`; renamed
> `major_synmin_2015_2025`/`electric_2015_2025` on 2026-07-29 when the eligibility rule was revised — see
> `PB2` in `briefs/panel/panel_construction_decisions.md`) **from this datasets layer**
> instead of `data/processed/` directly — the dependency direction this scope note used to describe as
> one-way is now genuinely one-way in the opposite sense: this layer still depends on nothing downstream,
> but panel-building now depends on *this layer's* `regulatory`/`operating`/`hpv_active`/`coordinates`
> outputs, in particular the `ACTIVE_BROAD` signal (`O6`) for its eligibility screen. See
> `briefs/panel/panel_construction_decisions.md` (the new, short version) for what's specific to those two
> panels; every construction decision upstream of them — including everything this file documents — is
> unchanged by that rebuild.

**The deliverable is nine datasets, not one panel.** Each is built once over the FULL facility universe;
any sample restriction is a downstream filter, not a pre-built panel. All join on `PGM_SYS_ID` (+ `YEAR`
where the grain is facility × year).

| # | dataset | grain | contents | status |
|---|---|---|---|---|
| 0 | `regulatory`  | facility × year | ICIS-Air only: event counts + ICIS facility characteristics | ✅ built & audited |
| 1 | `operating`   | facility × year | wayback status, program-active flags, entry/exit, program begin year, `ACTIVE`/`ACTIVE_BROAD` (O6) | ✅ built & audited |
| 1b | `wayback_only_facilities` | facility × year (2015–2025) | supplementary — NEW 2026-07-28 (O7); the ~15,302 facilities Wayback has seen but the current ICIS-AIR extract has not | ✅ built & audited |
| 2 | `hpv_spells`  | spell           | one row per HPV spell, UNcollapsed | ✅ built & audited |
| 2b | `hpv_active` | facility × year | R2 collapse of `hpv_spells` → HPV-active flag | ✅ built & audited |
| 3 | `penalties`   | formal action   | action-level penalties + multi-facility settlement key | ✅ built & audited |
| 4 | `coordinates` | facility        | FRS lat/lon, county, coordinate-error diagnostics | ✅ built & audited |
| 6 | `pipeline`    | facility × year | EPA ECHO "CAA Compliance Pipeline": linked evaluation→violation→enforcement counts, HPV/FRV split, eval/enforcement lag days | ✅ built & audited |
| 7 | `emissions`   | facility × year | annual pollutant quantities (VOC/PM10/PM2.5/NOx/SO2/CO/HAP, lbs; GHG, MTCO2e) from EIS/TRIS/E-GGRT/CAMDBS | ✅ built & audited |

---

## Part A · layer-wide conventions (`00_parameters.R`)

| # | Decision | Alternative not taken | Why |
|---|---|---|---|
| **G1** | **Window `YEARS = 2005:2025`** applied at dataset build, not in the assets. | Bake the window into `data/processed/`. | Assets stay reusable for any window; the window is one line here. Inherited from panel-layer CC2 (`archive/panel_building_legacy/briefs/panel/panel_construction_decisions.md` — same idea: keep every dated event in the asset, apply the year window only at build time). |
| **G2** | **Every column in the dataset layer is `UPPER_SNAKE_CASE`.** Builders assemble internally in lowercase, then uppercase **once on write** via `write_dataset()`. | Hand-name every output column uppercase in each aggregator; or leave mixed case as sources deliver it. | One convention across all eight files so join keys (`PGM_SYS_ID`, `YEAR`) and every derived column line up on merge with no per-file casing fixups. Single transform point = no typo drift across ~60 column literals. `toupper()` is idempotent on the already-uppercase ICIS attributes. |
| **G3** | **Full universe, no sample panels.** Datasets 1–5 built over all facilities; restrictions are downstream filters. | Ship pre-filtered contiguous-US / major-source panels as in the old panel layer. | The eight-dataset design pushes sample definition to the analysis, not the build — one canonical set of files, many samples. |
| **G4** | **Every dataset carries `REGISTRY_ID` (FRS cross-program facility id) alongside `PGM_SYS_ID`**, joined in from `facilities.csv.gz`; `NA` where a facility has no FRS match (same convention as `coordinates`' `HAS_COORDINATE==0`). | Leave `REGISTRY_ID` only on `regulatory`/`coordinates` (the prior state) and require a manual join elsewhere. | `regulatory` and `coordinates` already carried it, but `operating`, `hpv_spells`, `hpv_active`, `penalties` didn't — surfaced when checking whether multi-facility settlement co-defendants share an FRS id (`multi_facility_settlement_decision.md` §5) required a manual join to `facilities.csv.gz` that shouldn't be necessary for a question this basic (facility identity across ICIS program systems, not just within one). |

---

## Part B · Dataset 0 — `regulatory` (`01_regulatory.R`)

**Built from the raw ICIS-Air download and NOTHING ELSE.** Every column is either an ICIS event count or
an ICIS facility characteristic — no wayback status, no FRS coordinates, no AFS. Those are other datasets
in this layer.

**Source:** `data/processed/{inspections,violations,formal_actions,informal_actions,certs,stacktests}.csv.gz`
— event-grain (one row per inspection/violation/enforcement action/cert/stack test), historical, spanning
the raw ICIS-Air extract's full recorded date range — **plus** `data/processed/{facilities,pollutants,programs}.csv.gz`,
which are **current-snapshot** grain (one row per facility/pollutant-profile/program-enrollment as of the
extract date, no history), which is why the facility-characteristic and `EMITS_*`/`PROG_*` columns below are
time-invariant.

**Shape (as of 2026-07-27; drifts with each live ICIS-AIR refresh — see EM2):**
```
5,872,965 rows | 80 cols | 279,665 facilities × 21 years | 742,206 observed facility-years (12.6%)
```

### B.1 Coding decisions

| # | Decision | Alternative not taken | Why / data fact |
|---|---|---|---|
| **R1** | **Universe = every `PGM_SYS_ID` in `ICIS-AIR_FACILITIES` (279,665 as of 2026-07-27), NO ever-active screen.** | Keep only facilities with ≥1 event in-window (the panel-layer "ever-active" universe, ~134k). | Retains the never-inspected population (mostly operating minor sources). **52.2% of facilities have zero events in-window** (145,912 of 279,665, `output/regulatory_profile/facility_level_overview.csv`, `13_regulatory_profile.R`) and sit all-`NA` here until dataset 1 supplies operating status. Consequence: only **12.6%** of the rectangle is observed — the dataset is close to unusable standalone by design, which is why ds 0 and ds 1 must be documented as a pair. |
| **R2** | **Zero-vs-NA rule (load-bearing).** A facility-year is `ICIS_OBSERVED == 1` iff ICIS holds ≥1 row across ANY of the six event assets that year. Then a count of 0 for some *other* measure is a **true zero**. With no record of any type → **every count is `NA`** (unknown, not zero). | Use operating status to code zeros; or code all non-events as 0. | Within-ICIS presence is the only within-ICIS evidence the facility was tracked that year. Operating-status inference is deliberately held out — that is **dataset 1's** job, kept out so ds 0 is pure ICIS. |
| **R3** | **Every `N_*` counts ALL rows; nothing deduped.** Duplicate load surfaced via `N_*_DUP` (event-key repeats, `dup>0`) and `N_*_DUP_EXACT` (byte-identical). Event-distinct = `count − dup`. | Dedup at aggregation (old `distinct`). | Honesty about the raw record + measurable duplication in place. Inherited from panel-layer CC9 / the 2026-07-17 no-dedup revision. Duplicated families: inspections, enforcement (incl. formal/informal split), certs. **Violations & stack tests carry zero dups — enforced via `stopifnot()` at build time** (`01_regulatory.R:146,216`: `stopifnot(all(v$dup == 0))` / `stopifnot(all(s$dup == 0))`), not merely a comment — a `dup>0` row would fail the build, not just go unnoticed. |
| **R4** | **REVERSED 2026-07-28 (explicit user decision):** `PENALTY_AMOUNT` is `NA` whenever a facility-year had no formal action at all, OR its formal action(s) summed to exactly $0 — both collapse into `NA`, not just genuinely-unobserved years. | The zero-vs-NA rule applied literally to `PENALTY_AMOUNT` (0 = true zero when observed) — this file's convention from 2026-07-27 to 2026-07-28, flagged for sign-off at the time. | User was asked whether "no formal action" and "formal action worth exactly $0" should read differently or the same — chose the same (both `NA`, meaning "no confirmed positive penalty dollars"). Brought back in line with `code/04_panel_building/03_build_functions.R`'s `attach_penalty()`, reversed identically the same day (see W11 in `archive/panel_building_legacy/briefs/panel/panel_construction_decisions.md`) — the two layers briefly agreed on the *opposite* convention as of 2026-07-27, which is what this row used to describe. |
| **R5** | **Facility characteristics are the current ICIS snapshot, time-invariant, applied to all 21 years.** (`FACILITY_NAME`, `STATE`, `NAICS_CODES`, `AIR_POLLUTANT_CLASS_DESC`, `OP_STATUS_CURRENT_DESC`, …) | Reconstruct history. | ICIS carries no history for these. An industry reclassification or ownership change is **not** visible — a known limitation, not a bug. **Addendum (2026-07-28) — `FACILITY_TYPE` lookup expanded from 8 to all 15 official ICIS-Air codes** (source: the `FACILITY_TYPE_CODE` field definition, https://echo.epa.gov/tools/data-downloads/icis-air-download-summary, fetched 2026-07-28; same fix as the panel-layer spine, F9 in `archive/panel_building_legacy/briefs/panel/panel_construction_decisions.md`). The old 8-code list silently mapped any other code to `NA`; **558 facilities** carried a real code (`TRB`/`MWD`/`SDT`/`MXO`) the list didn't have. Two already-mapped codes also had drifted wording, corrected to the official meaning: `CTG` "City government" → "Municipality"; `NON` "Non-classified" → "Non-government" (a real ownership category, not "unclassified"). |
| **R6** | **`EMITS_*` (6) and `PROG_*` (8) are ever-reported / ever-enrolled, undated → time-invariant flags.** A facility absent from `pollutants`/`programs` gets flag = **0** (absent profile). `PROG_GACT`/`PROG_CFC` (CAAGACTM/CAACFC) deliberately **excluded** (2026-07-21) to match the 8-group allowlist now used in dataset 1's `PROG_*_ACTIVE` (O3); `N_PROGRAMS` still counts every `PROGRAM_CODE` including these two — only the per-program flags dropped. | Treat absence as `NA`; keep all 10 groups; or add a combined `GACT_CURRENT`-style column carrying `gact`/`cfc` separately instead of dropping them (not implemented — would need its own schema-pin decision the way the 8-group allowlist already has one; a real option, just not built). | ICIS gives no start/end dates for pollutant or program association, so these can only be "ever" flags. Absence of an enrollment record = not enrolled in that program → a true 0. **Addendum (2026-07-28) — `EMITS_HAP` was broken, now fixed:** the old rule matched only the literal substring `"HAZARDOUS AIR POLLUTANT"` in `POLLUTANT_DESC`, missing the large majority of HAPs that ICIS-AIR records under a specific chemical name (Benzene, Formaldehyde, Lead, Mercury, ...) rather than that umbrella phrase — the other five `EMITS_*` flags are fine (each backed by only 1-8 distinct `POLLUTANT_CODE` values). Fixed identically to the panel-layer spine (F6 addendum in `archive/panel_building_legacy/briefs/panel/panel_construction_decisions.md`): CAS (Chemical Abstracts Service registry number)-join against the official CAA §112(b) HAP list (188 substances, `code/03_datasets/hap_list_112b.R`) **unioned with** (not replacing) the old umbrella-phrase rule, since that rule turned out to catch a real, distinct signal — an aggregate `"TOTAL HAZARDOUS AIR POLLUTANTS (HAPS)"` summary record (no CAS) that some facilities report instead of itemizing species — plus a name match for the 17 CAS-less compound-class entries (e.g. "Chromium Compounds"). Full-universe `EMITS_HAP=1` facility count: **67,011 of 279,665 (24.0%)** post-fix. A coverage diagnostic is now printed on every build (`pollutants coverage: N / M rows (%) match none of the six EMITS_* categories`). |
| **R7** | **`N_PROGRAMS` is `NA`-able, never 0.** `n_distinct(PROGRAM_CODE)` is ≥1 for any facility present in `programs.csv.gz`, so a 0 never arises legitimately; a facility with **no program association** stays `NA`. | Coalesce to 0 like the `PROG_*` flags (the pre-fix behavior). | Distinguishes "not associated with **any** program" (`NA`) from the `PROG_*` flags' "not enrolled in **this** program" (0). **12,544 facilities (4.5%) are absent from `programs.csv.gz`** (as of 2026-07-27, `output/regulatory_profile/facility_level_overview.csv`, `13_regulatory_profile.R`) → `N_PROGRAMS = NA` for exactly those (263,424 facility-years). ⚠ **NA now carries two meanings in this file** — see R8. |
| **R8** | **`program_begin_year` is deliberately ABSENT from ds 0.** | Carry it here alongside program enrollment. | `BEGIN_DATE` is a facility-lifecycle proxy, so it belongs with the operating evidence in **dataset 1**, not with the undated "ever-enrolled" flags. |
| **R9** | **Three `_DESC`-text-match bugs found & fixed (2026-07-28), switched to `_CODE`-based matching where a code exists.** Found by systematically diffing every `_DESC`-based match in this file against its parallel `_CODE`/raw values. | Keep matching on `_DESC` text everywhere. | **(1) `EMITS_VOC` false positive:** `grepl("VOLATILE ORGANIC", POLLUTANT_DESC)` matched `POLLUTANT_CODE 300000310` "NON-VOLATILE ORGANIC COMPOUNDS" — a plain substring match with no negation handling. Flipped **30 facilities** from `EMITS_VOC=1` to the correct `0` (54 raw rows / 49 facilities carried that code; 30 had no other genuine VOC-matching row to fall back on). Fixed with a negative-lookbehind regex, `(?<!NON-)VOLATILE ORGANIC`, applied identically to the coverage diagnostic just below. **(2) `N_VIOL_NSPS` scope creep:** `grepl("New Source Performance Standards", PROGRAM_DESCS)` also matched `CAANSPSM`'s description ("...(Non-Major)") by substring — 418 rows. This happened to land on the same `CAANSPS`+`CAANSPSM` grouping `PROG_NSPS` already uses deliberately (R6), but by phrasing accident, not design. `agg_violations()` now matches on `PROGRAM_CODES` with explicit `\b`-bounded codes for all five `N_VIOL_*` program flags, so the parity with `PROG_NSPS` is coded, not coincidental. **(3) `N_PENALTY_ACTION` undercount:** exact match `ENF_TYPE_DESC == "CAA 113D1 Action For Penalty"` missed four 112(r)/MRR expedited-settlement variants of the same action (`ENF_TYPE_CODE` `113D1E`/`113D1E1`/`113D1E2`/`113D1E3`, each with its own suffixed DESC text) — a **201-row undercount** of the true 113D1 family (201/6,881, ~2.9%). Switched to `grepl("^113D1", ENF_TYPE_CODE)`; confirmed no other `ENF_TYPE_CODE` starts with `113D1` (`113D`, `113DWD` are distinct, unrelated actions). The other `_DESC`-based matches in this file (`n_fce`/`n_pce`, `AIR_STACK_TEST_STATUS_DESC`, `AGENCY_TYPE_DESC`, remaining `N_VIOL_*`/enforcement-type flags) were checked against their `_CODE` families and found clean — no fix needed there. |

### B.2 ⚠ Two meanings of `NA` in this file

A downstream user must not conflate them:
- `is.na(N_INSPECTIONS)` (and all other event counts) is a **year-level** condition → facility not observed in ICIS that year (`ICIS_OBSERVED == 0`).
- `is.na(N_PROGRAMS)` is a **facility-level** condition → no program association on record at all, constant across all 21 years.

Both ride on `NA` in the same table. Needs a codebook line so `is.na()` isn't read as one thing.

### B.3 Verification (this session, independent of the in-build assertions)

All passed on the rebuilt file:

| check | result |
|---|---|
| `PGM_SYS_ID × YEAR` unique; rectangle complete (rows = 279,665 × 21, as of 2026-07-27) | ✓ |
| all 80 column names uppercase | ✓ |
| observability rule across **all 48 event-count columns** (obs → never `NA`, unobs → always `NA`) | ✓ |
| every observed row carries ≥1 real event (rule means what it claims) | ✓ 0 violations |
| `N_HPV + N_FRV = N_VIOLATIONS`; `N_FORMAL + N_INFORMAL = N_ENFORCEMENT` | ✓ |
| no `_DUP` exceeds its parent; `PENALTY_AMOUNT > 0 ⟺ N_PENALTIES > 0` | ✓ |
| attributes complete (0 missing `STATE`) and time-invariant (0 facilities with varying class / `N_PROGRAMS`) | ✓ |
| `N_PROGRAMS`: `NA` for 12,544 facilities (= programs-table gap), never 0, min non-`NA` = 1 | ✓ |

*Note on the audit:* an initial `grep("^N_")` check swept `N_PROGRAMS` (a profile column) into the
event-count set and false-flagged all 5.1M unobserved rows. Corrected by excluding `N_PROGRAMS` — 0 real
leaks. Recorded here because the `N_`-prefix ambiguity is a genuine trap (R7/R8).

---

## Part C · Dataset 1 — `operating` (`02_operating.R`)

The operating evidence ds 0 deliberately holds out (R2/R8): year-varying operating status, program-active
flags, facility entry/exit spells, earliest program-enrollment year. Built from the bespoke **Wayback**
reconstruction (`code/02_cleaning/wayback/`, panel-layer W1–W6/N8–N11) + `programs.BEGIN_DATE`.

**Source:** `data/processed/wayback_{facility_status,facility_spells,program_status}.csv.gz` — **historical**,
built from 11 archived annual Internet Archive captures (2015–2025) of the ICIS-Air bulk download, one
facility × year row per snapshot (not a single current snapshot) — **plus** `data/processed/programs.csv.gz`'s
`BEGIN_DATE` field, which is current-snapshot grain (a single recorded enrollment date per facility, not a
time series).

**Shape (as of 2026-07-29 Q4 re-pin rebuild, `O8`; drifts with each live ICIS-AIR refresh — see EM2):**
```
5,872,965 rows | 27 cols | 279,665 facilities × 21 years | 2,471,144 wayback-observed facility-years (42.1%)
```
42.1% of the 21-year rectangle is wayback-covered (down from 46.3% before the 2026-07-26 ICIS-AIR refresh —
the ~454 newly-added facilities are recent additions with little/no Wayback history, so growing the ICIS
roster dilutes overall coverage; see O1). Wayback is **2015–2025 only**, so within those 11 years coverage
is **~80%** of facility-years (was ~88%). **Column count corrected 2026-07-28: 22, not 21** — the "21"
figure predates this session and was already stale (verified by reconstructing the pre-session build from
source: `expand_grid` keys + `status` + `wayback_observed` + 8 `prog_*_active` + 5 spell fields + 2 begin-year
fields + `REGISTRY_ID` = 22, not 21 — a pre-existing documentation drift, not introduced by this change).
Now **27**: +5 new columns from O6 below (`ICIS_OBSERVED`, `EMISSIONS_OBSERVED`, `GHG_OBSERVED` carried in
as the raw constituent signals, plus the two computed unions `ACTIVE`/`ACTIVE_BROAD`).

### C.1 Coding decisions

| # | Decision | Alternative not taken | Why / data fact |
|---|---|---|---|
| **O1** | **Universe = dataset 0's exactly** — same 279,665 facilities (as of 2026-07-27) × 2005–2025 rectangle, so `operating` joins **1:1** to `regulatory` on `(PGM_SYS_ID, YEAR)` (verified: identical key vectors). | Use Wayback's own 292,040-facility universe. | Wayback covers a **larger** set; the **15,302 wayback-only facilities** (absent from `ICIS-AIR_FACILITIES`) are **dropped** — this layer is keyed to the ICIS universe. The **2,927** ICIS facilities with no Wayback spell get `NA` spell fields (up from 2,472 — most of the ~454 facilities added by the 2026-07-26 ICIS-AIR refresh are recent additions with no Wayback-era history at all). |
| **O2** | **Strictly raw — NO imputation.** Yearly `operating`/`op_status`/`prog_*_active` are carried for 2015–2025 and left **`NA`** for 2005–2014 and any facility-year absent from a snapshot. `WAYBACK_OBSERVED` (1 iff the facility appears in that year's snapshot) is the coverage flag. | Extend status across pre-2015 / interior gaps using the entry/exit spells. | Mirrors ds 0's zero-vs-NA discipline: don't manufacture certainty Wayback lacks. Spells are provided **separately** (O4) so the user can extend downstream by choice, not by baked-in assumption. *(User decision, 2026-07-20.)* |
| **O3** | **`operating` carried unchanged from the cleaning layer** — whitelist flag (1 iff code ∈ {OPR,TMP,SEA}). `PROG_*_ACTIVE` is pinned to an **explicit 8-group allowlist** (`sip/titlev/nsps/mact/neshap/fesop/nsr/psd`) via `col_select`, using the cleaning layer's own program-specific active rule (N11). | Re-derive here; or read `wayback_program_status.csv.gz` unrestricted (all 10 groups it now carries). | **N11's divergence is structural, verified, and by design — not a bug to reconcile:** `operating` reads `AIR_OPERATING_STATUS_CODE` off `ICIS-AIR_FACILITIES.csv` (one row per facility); `PROG_*_ACTIVE` reads the same-named column off `ICIS-AIR_PROGRAMS.csv` (one row per program enrollment), which EPA does not keep synchronized to the facility record — checked directly on the 2025 Wayback snapshot: 20,574 of 454,144 program rows (4.5%) carry a status that disagrees with their own facility's status that year. Each column is reported exactly as ICIS has it; a closed program on an open facility is real information (that program's status specifically), not something to correct against `operating`. Kept faithful to source. Build asserts `operating == whitelist(op_status_code)` as a tripwire. ⚠ **History (2026-07-21):** `data/processed/wayback_program_status.csv.gz` was stale (predating this session) when dataset 1 was first built, so it only had 8 groups; rebuilding it as part of the W7 fix (`archive/panel_building_legacy/briefs/panel/panel_construction_decisions.md`) regenerated it with the 2 groups the code had long supported upstream (`gact`, `cfc`) but this dataset had never carried. `02_operating.R` originally read that file with no column allowlist, so it silently absorbed both new columns on rebuild. **Decision: exclude `gact`/`cfc` from this dataset** — `col_select` now pins to the original 8 explicitly, so a future change to the upstream file can't silently change this dataset's schema again. Shape stayed at **21 cols** through that 2026-07-21 fix (row count moves only with the live ICIS-AIR facility roster, see the Shape line above, not with this schema-pinning decision). **Two more traps in the underlying wayback reconstruction — full detail in `code/02_cleaning/wayback/README.md`:** a `PROG_*_ACTIVE = 0` can have zero supporting `PROGRAMS` record behind it (N10, 2.18% of present facility-years have no `PROGRAMS` rows at all, so every group forces to `0`); and a blank-status or `CLS` facility-year reads `NA` for every group, not a confident `0` (W8). |
| **O4** | **Entry/exit spells broadcast facility-level, time-invariant** — `ENTERED_YEAR`, `EXITED_YEAR`, `EXIT_SOURCE`, `LEFT_CENSORED`, `RIGHT_CENSORED`, as-is. | Collapse into a single operating-span imputation. | ⚠ **`EXIT_SOURCE` in this dataset is effectively pure `cls`** (18,771 confirmed closures, unchanged since Wayback data itself doesn't drift with ICIS-AIR refreshes). Of 11,801 Wayback `dropout` exits (last-seen-operating then vanished — the N8 upper bound on unexplained exits; this count is stable — Wayback is a separately-pinned archival source), **11,799 are wayback-only facilities dropped by O1**; only **2** survive. **Disappearances are therefore NOT visible in ds 1 — this is an accepted, documented cost** (user decision, 2026-07-20; see O1a). Coherent (a facility gone from snapshots is also gone from the facilities table), but load-bearing: exit analysis from ds 1 alone sees confirmed closures only. **Two more traps, both in the underlying wayback reconstruction, not this dataset's own logic — full detail in `code/02_cleaning/wayback/README.md`:** a genuine close-then-reopen collapses to one continuous-looking spell here even though the year-varying `OPERATING` column still shows it correctly (N9, 0.26% of ever-operating facilities); and `EXITED_YEAR` next to the 2018 gap should be read as "confirmed non-operating by the next real observation," not a precise closure date (W7a, ~1.8% of facilities with status on both sides of 2018). |
| **O1a** | **The 15,302 wayback-only "disappeared" facilities are excluded from `operating.csv.gz`'s own rectangle (not added to it, to keep its 1:1 join to `regulatory.csv.gz` exact).** ⚠ **UPDATED 2026-07-28 (O7):** the workaround this row used to describe — "go to the raw Wayback layer directly, join `wayback_facility_spells.csv.gz` (filter `exit_source == "dropout"`) to `wayback_facility_status.csv.gz` yourself" — is now pre-done and shipped as `data/datasets/wayback_only_facilities.csv.gz` (O7). This row's original exclusion rationale is unchanged and still the operative decision for the *main* table; only the "go find it yourself" instruction is superseded. | Broaden ds 1 to the union universe; or add them to both ds 0 and ds 1. (Both re-considered and re-rejected 2026-07-28, see O7.) | **Why excluding from the main rectangle is defensible:** all 15,302 carry **zero ICIS events** and **zero ICIS attributes** (absent from `facilities.csv.gz`) — they'd be all-`NA` ghosts in the ICIS datasets (confirmed again, more precisely, in O7: 0/15,302 have any ICIS event record at all). And the missing exits are **dominated by artifacts**: **10,781 of ~11,833 "exit" in 2015**, the first snapshot year (left-edge dropouts, N8). **Why it has a cost:** ~**1,050** (**1,018** per O7's exact re-check) are real **mid-window (2016–2025)** disappearances that ds 1's main table cannot see — now reachable via `wayback_only_facilities.csv.gz` (O7) instead of a manual raw-layer join. |
| **O5** | **`EARLIEST_PROGRAM_BEGIN_YEAR` = min `BEGIN_DATE` year, SCREENED to [1970, 2025]; plus `EARLIEST_PROGRAM_BEGIN_YEAR_RAW` = unscreened min.** (Renamed from `program_begin_year` to mark it a min.) | Facility min of raw dates only; or clip to the panel window. | ⚠ As of 2026-07-27 (`output/operating_profile/screen_effect.csv`, `11_operating_profile.R`): **3,168** facilities < 1970 (incl. a `218`), **4,088** dated **entirely > 2025** (`2026–2028`) — the >2025 count rose sharply from 3,056 since the 2026-07-20 profiling (7 days earlier), plausibly real: some facilities' earliest program record is now a genuine near-future "planned/under construction" `BEGIN_DATE` as time moves forward, not just the ICIS-AIR facility-roster growth (which alone would predict a much smaller shift) — flagged as a real observation, not independently re-verified further this pass. Because the field is a **min**, one garbage-low date poisons a facility's earliest year. Screen = validity filter on malformed values (**1970** = Clean Air Act; **2025** = window end), **not** imputation. The screen changed **7,256** facilities (**7,015** → `NA`, only out-of-range dates); `_RAW` preserves everything for full traceability. `NA` (screened) where no program record (**≥ 12,544**, the R7 programs-gap) or no in-range date. *(User decision, 2026-07-20; figures refreshed 2026-07-27.)* |
| **O6** | **NEW (2026-07-28): `ACTIVE` / `ACTIVE_BROAD` — two YEAR-VARYING facility-existence indicators**, not a facility-level "ever" summary. `ACTIVE` = `OPERATING==1` OR `ICIS_OBSERVED==1` **in that specific year**; `ACTIVE_BROAD` = `ACTIVE==1` OR (`EMISSIONS_OBSERVED==1` OR `GHG_OBSERVED==1`) **in that specific year**. `ICIS_OBSERVED` (from `regulatory.csv.gz`) and `EMISSIONS_OBSERVED`/`GHG_OBSERVED` (from `emissions.csv.gz`) are carried into this table as their own columns too, alongside the two unions, so the constituent evidence for `ACTIVE`/`ACTIVE_BROAD` is visible in place rather than requiring a join back to two other files. Both keep the 0-vs-NA discipline: `0` only where every checked signal positively says "not active that year"; `NA` where at least one signal had nothing to say that year. | (i) A facility-level "ever active" summary instead (considered first, rejected — see below). (ii) Fold `PROG_*_ACTIVE`-style per-program logic in too. (iii) A 3rd tier adding Pipeline (dataset 6) — checked, adds **zero** facility-years beyond `ICIS_OBSERVED` (Pipeline is derived from linked ICIS evaluations, fully subsumed) — not used. | **Why this exists:** `regulatory.csv.gz`'s `ICIS_OBSERVED` alone under-counts "was this facility real that year" — it requires a *recorded regulatory event*, not just operation. Probe this session (2026-07-28, whole-window framing, drifts with any live ICIS-AIR refresh): **92,080** facilities are wayback-confirmed operating in some year with **zero** ICIS events ever (mostly never-inspected minor sources) — `OPERATING` alone misses these from `regulatory.csv.gz`'s perspective, and `ICIS_OBSERVED` alone misses them from `operating.csv.gz`'s. Conversely `OPERATING` is wayback-only (2015–2025 coverage), while `ICIS_OBSERVED` has full 2005–2025 coverage — of 133,753 facilities with ≥1 ICIS event somewhere in-window, **15,699 (11.7%)**, mostly (**11,029**) active *only* pre-2015, have **no** wayback-confirmed operating year at all. Neither signal alone is sufficient; `ACTIVE` closes both gaps, year by year. **Why YEAR-VARYING, not an "ever" summary (explicit user correction mid-session):** a facility-level flag can't distinguish "this facility was real in 2008" from "this facility was real in 2022" — a year-varying measure is what a facility × year panel actually needs (e.g. as an operating-status merge input, D-A2 in the panel briefs), and collapsing to "ever" is a trivial `any()` a downstream user can do themselves if that's what they want; the reverse (recovering per-year detail from an "ever" flag) is impossible. **Why not a 3rd, Pipeline-based tier:** checked directly — 0 marginal facility-years. **Verified this session:** `ACTIVE`/`ACTIVE_BROAD` nest monotonically (`OPERATING==1 ⇒ ACTIVE==1 ⇒ ACTIVE_BROAD==1`, checked row-by-row, 0 violations); collapsing `ACTIVE`/`ACTIVE_BROAD` to "ever `==1` per facility" over the full rebuild reproduces the probe's whole-window counts exactly — **225,833** (`ACTIVE`) and **228,521** (`ACTIVE_BROAD`) of 279,665 facilities. Full facility-year distribution as of 2026-07-28: `OPERATING` 0/1/NA = 686,029 / 1,784,712 / 3,402,224; `ACTIVE` = 681,016 / 2,233,920 / 2,958,029; `ACTIVE_BROAD` = 670,476 / 2,316,699 / 2,885,790. Column names are this session's working recommendation, not settled — deliberately avoided an `*_ACTIVE` suffix pattern matching `PROG_*_ACTIVE` (a different, program-enrollment-specific concept in this same table) to reduce confusion. |
| **O7** | **NEW (2026-07-28): `wayback_only_facilities.csv.gz`** — a small, separate supplementary output (NOT one of the eight numbered datasets; joins to nothing else in this layer) covering the ~15,302 facilities Wayback has captured operating-status snapshots for that are absent from the current ICIS-AIR facility extract entirely (the O1a population). Grain `PGM_SYS_ID × year`, but window **2015–2025 only** (Wayback's real coverage — not this layer's standard 2005–2025, `G1`) since these facilities have zero information of any kind before 2015. Columns: `OP_STATUS_CODE`/`OP_STATUS_DESC`/`OPERATING`/`WAYBACK_OBSERVED` (year-varying) + `ENTERED_YEAR`/`EXITED_YEAR`/`EXIT_SOURCE`/`LEFT_CENSORED`/`RIGHT_CENSORED` (facility-level, broadcast) — i.e. exactly the join O1a told a user to do by hand (`wayback_facility_spells.csv.gz` + `wayback_facility_status.csv.gz`), pre-done. **Deliberately carries no `ACTIVE`/`ACTIVE_BROAD`-style column** — `ICIS_OBSERVED` and `EMISSIONS_OBSERVED`/`GHG_OBSERVED` are structurally undefined for this population (no row to look up in `regulatory.csv.gz` or `emissions.csv.gz` at all, not merely a confident `0`), so any such column would either be all-`NA` or wrongly imply a real zero. | (i) Leave O1a's "go do the join yourself" as the permanent answer (status quo, rejected this session). (ii) Broaden `operating.csv.gz`'s own universe to include these facilities (rejected — would break the tested 1:1 join to `regulatory.csv.gz`, and every ICIS-sourced column would be permanently `NA` for them for a structurally different reason than this table's normal "unobserved" `NA`). | **Checked directly this session (does NOT change the O1a analysis, sharpens it):** **0 of 15,302** wayback-only facilities appear in *any* ICIS event asset (inspections/violations/formal/informal/certs/stacktests) — including **0 of 1,018** that look like genuine mid-window (non-2015-boundary) disappearances (`exit_source == "dropout"`, `exited_year != 2015`). So this population carries real Wayback-derived operating history but has **zero** ICIS regulatory footprint of any kind — there is no data being newly exposed here that ICIS ever had, only Wayback's own record made queryable without a manual raw-layer join. `exit_source` breakdown among the 15,302 (2026-07-28, drifts with refresh): `dropout` 11,799, `cls` 31, `other` 3, `NA` 3,469 — consistent with, and refining, O1a's original figures. Middle-ground design chosen over (i)/(ii) above per explicit user decision. |

| **O8** | **NEW (2026-07-29): Wayback capture pins re-audited for Q4 consistency; only 2024 moved.** `17-19_wayback_*.R` interpret each of the 11 annual snapshots as "the ~Q4 state of year Y," but only 4 of 10 pinned years (2016/2020/2021/2022) actually landed in Q4 — the rest were whichever capture happened to byte-match what was already staged, chosen with no regard for calendar timing. `code/diagnostics/wayback_verify/wayback_q4_repin.R` queried the Wayback CDX API for every 200-status capture of the ICIS-Air bulk URL, per year, to check whether a true Q4 alternative existed. | (i) Force every year to its latest-in-year capture instead (rejected — doesn't fix the Q4-consistency problem this was meant to solve, and abandons the byte-verified pins for years where Q4 genuinely isn't available). (ii) Leave all pins as-is and only fix the docs (considered, but 2024 did have a real fix available, so this would leave a correctable inconsistency uncorrected). | **Finding: this is not a fixable inconsistency for most years.** The Internet Archive never crawled this URL in Q4 of **2015, 2017, 2019, 2023, or 2025** — 2019 and 2023 have exactly **one** 200-status capture in their entire calendar year, so there is no alternative to try regardless of search-window width. Those 5 years' pins are unchanged (already the best/only capture available). **2024 is the one year with genuine Q4 coverage** (captures 2024-11-16 and 2024-12-10, vs. its old 2024-09-26 pin) and was re-pinned to 2024-12-10 (most-recent-first, matching the file's existing selection convention). Full per-year finding: `output/wayback_verify/q4_repin_summary.csv` / `q4_repin_candidates.csv`. **Effect on this dataset, full rebuild 2026-07-29:** `ACTIVE_BROAD==1` facility-years 2,316,699 → 2,316,808 (+109, +0.005%); `ACTIVE==1` 2,233,920 → 2,234,031 (+111); wayback-observed facility-years 2,470,741 → 2,471,144 (+403, +0.016%) — a small, single-direction shift consistent with one year's snapshot moving ~2.5 months later in its own year, not a data-quality problem. Downstream: `major_synmin_2015_2025` panel facility count 45,873 → 45,872 (−1, `panel_construction_decisions.md`). **Incidental finding, not fixed as part of this decision:** `01_download.R`'s idempotency check (`all(file.exists(...))` against a fixed `ICIS_AIR_TABLES` name list) never matches 2015's folder, because 2015's capture uses the legacy table name `ICIS-AIR_HPV_HISTORY.csv` where every later year uses `ICIS-AIR_VIOLATION_HISTORY.csv` — every `RUN_ALL.R` run re-downloads 2015 unnecessarily. Harmless (same deterministic pin, same resulting files) but flagged for a future fix. |

### C.2 Verification (this session, independent of in-build assertions)

| check | result |
|---|---|
| shape 5,872,965 × 27 (as of 2026-07-28, was × 22 pre-session — see the Shape note above); grain `PGM_SYS_ID × YEAR` unique; all names uppercase | ✓ |
| **1:1 join to `regulatory.csv.gz`** — same row count, identical key vectors (unchanged by O6/O7) | ✓ |
| strictly-raw: `operating`/`op_status`/`prog_*_active`/`WAYBACK_OBSERVED` all `NA`/0 before 2015 | ✓ 0 leaks |
| `WAYBACK_OBSERVED ⟺ op_status_code` present; `operating == whitelist(code)`, never `NA` when code present | ✓ |
| all 6 facility-level fields (spells + begin years) constant within facility | ✓ |
| screened begin year ∈ [1970,2025] ∪ `NA`; screened ≥ raw (screen only removes) | ✓ |
| screen effect: 7,256 facilities changed, 7,015 → `NA`; raw range [218, 2028] preserved | ✓ |
| **NEW (O6):** `ICIS_OBSERVED`/`EMISSIONS_OBSERVED`/`GHG_OBSERVED` never `NA` anywhere (both source datasets share this exact universe) | ✓ |
| **NEW (O6):** `ACTIVE`/`ACTIVE_BROAD` nest monotonically, row-by-row (`OPERATING==1 ⇒ ACTIVE==1 ⇒ ACTIVE_BROAD==1`) | ✓ 0 violations |
| **NEW (O7):** `wayback_only_facilities.csv.gz` shape 168,322 × 11 = 15,302 facilities × 11 (2015–2025) years; 0 overlap with the ICIS roster; `WAYBACK_OBSERVED ⟺ op_status_code` present | ✓ |

---

## Part D · Dataset 2 — `hpv_spells` (`03_hpv_spells.R`) + `hpv_active` (planned)

The spell-level source of truth for High Priority Violation status. `hpv_active` (facility × year) will be a
deterministic collapse of this table under rule R2 (below), so nothing is lost. Design choices were made off
two diagnostics: `code/diagnostics/08_hpv_spell_diagnostics.R` (record profile) and `09_hpv_facility_year_rules.R`
(mapping-rule comparison).

**Source:** `data/processed/violations.csv.gz` — the raw ICIS-Air violation-history extract, event-grain (one
row per violation record), historical (spans the extract's full recorded date range, not a snapshot).

**Shape (as of 2026-07-27; drifts with each live ICIS-AIR refresh):**
```
44,777 spells | 19 cols | 15,656 facilities
status: closed 40,515 · open 3,755 · bad_order 474 · missing_start 33
```

### D.1 Coding decisions

| # | Decision | Alternative not taken | Why / data fact |
|---|---|---|---|
| **H1** | **HPV universe = `ENF_RESPONSE_POLICY_CODE == "HPV"`** (the enforcement-response tier), NOT day-zero presence. | Define HPV as "has `HPV_DAYZERO_DATE`". | The tier below, **FRV** (Federally Reportable Violation), is excluded. Diagnostic 08 (`code/diagnostics/08_hpv_spell_diagnostics.R`, re-run 2026-07-27) confirms the two definitions still differ by only **33** records (every day-zero record is ENF-coded HPV; ENF adds 33 start-less ones — unchanged, a within-violations-table structural fact, not a roster-size effect). The FRV-side "resolved date but no day-zero" count is **28,535** as of 2026-07-27 — a different object (N17), correctly out of scope; not re-derived from diagnostic 08 (which counts HPV-side missing-start, not this FRV-side stat) — flagged, not re-verified this pass. *(User decision, 2026-07-20; figures refreshed 2026-07-27.)* |
| **H2** | **Spell grain — one row per HPV record, UNcollapsed.** Overlapping/concurrent spells are NOT merged. | Merge into consolidated per-facility spells. | Faithful source of truth; merging is a collapse-time choice. **43.1%** of closed spells overlap another spell of the same facility (re-run 2026-07-27, `code/diagnostics/08_hpv_spell_diagnostics.R`) — union is deferred to `hpv_active`, not baked in here. |
| **H3** | **`SPELL_STATUS` ∈ {closed, open, bad_order, missing_start}** (mutually exclusive); **`SPELL_DAYS`** (inclusive) defined **only** for `closed`. | Drop open / bad-order / start-less records. | Keeps every HPV record, flagged. **`closed` is the complement of the other three** — has both a day-zero and a resolved date ≥ day-zero. As of 2026-07-27: **closed** (40,515, 90.5%, the remainder); **open** (3,755, 8.4%) = day-zero, no resolved (persistent noncompliance — kept). **bad_order** (474, 1.1%) = resolved < day-zero. **missing_start** (33, unchanged) = no day-zero (23 have a resolved date, 10 have neither). |
| **H4** | **Dates carried AS PARSED — no plausibility screen.** | Screen implausible day-zero years here. | Source of truth stays faithful; a `218` day-zero record still survives (H7). Screening is a downstream / `hpv_active`-collapse decision, kept out of the spell table. |
| **H5** | **Facility-year mapping rule = R2** (interval overlap; open/bad-order conservatively closed on Dec-31 of the day-zero year). Feeds `hpv_active`. | R1 day-zero-year-only; R3 extend open spells to window end; R4 union>30-days. | Diagnostic 09 quantified each lever over 2005–2025 (re-run 2026-07-27, `code/diagnostics/09_hpv_facility_year_rules.R` — figures moved, not just drift-since-last-check): **R1→R2 (duration) +19,588 fac-yrs** (was +19,378; day-zero-year-only *halves* coverage — rejected); **R2→R3 (extend open spells) +10,957** (was +11,546), concentrated in recent years (an assumption about missing resolution dates — rejected as too strong); **R2→R4 (30-day threshold) −1,964** (was −1,952, minor). R2 chosen: faithful to spell duration without manufacturing an open-ended tail. *(User decision, 2026-07-20.)* |

### D.2 Verification (this session)

| check | result |
|---|---|
| 44,777 × 19 (as of 2026-07-27); all names uppercase; row grain unique on (PGM_SYS_ID, ACTIVITY_ID, COMP_DETERMINATION_UID, day-zero) | ✓ |
| `SPELL_STATUS` exhaustive/exclusive; reconciles (closed 40,515 + bad_order 474 = 40,989 day-zero+resolved) | ✓ |
| `SPELL_DAYS` non-NA **iff** `closed`, and ≥ 1 | ✓ |
| `DAYZERO_YEAR` NA **iff** `missing_start`; `RESOLVED_YEAR` NA = open (3,755) + missing_start-no-dates (10) | ✓ |
| every spell facility exists in the ds 0 universe (0 orphans) | ✓ |

## Part D2 · Dataset 2b — `hpv_active` (`04_hpv_active.R`)

Facility × year, the directly-usable HPV status flag — a deterministic R2 collapse of `hpv_spells`. Joins 1:1
to ds 0/1 (verified: identical key vectors).

**Shape (as of 2026-07-27; drifts with each live ICIS-AIR refresh):**
```
5,872,965 rows | HPV_ACTIVE: 1 = 35,417 | 0 = 709,220 | NA = 5,128,328 | 9,743 ever-active facilities
```

| # | Decision | Alternative not taken | Why / data fact |
|---|---|---|---|
| **H6** | **Zero-vs-NA mirrors ds 0.** `1` if an R2 spell covers the year (**spell wins even where `ICIS_OBSERVED==0`** — the interval is direct evidence; 2,431 such fac-yrs as of 2026-07-27); `0` if uncovered but `ICIS_OBSERVED==1`; `NA` if uncovered and unobserved. | Pure `0/1` (a spell covers or it doesn't). | Consistent with the layer's discipline: an unobserved year shouldn't assert "not in HPV status" any more than "0 inspections". Matches the panel. *(User decision, 2026-07-20 — reversed from an initial "pure 0/1".)* |
| **H7** | **Day-zero plausibility screen [1970, 2025] at the collapse** — a spell maps to years only if its day-zero year is in range. Excludes **268 of 44,744** mappable spells as of 2026-07-27 (implausible/unparseable day-zero). | No screen (H4 keeps the spell table faithful, but the collapse is where H4 said screening belongs). | ⚠ **Caught a real bug + garbage-propagation.** Record `CAMDAM1489` has day-zero `11-05-0218` (mistyped `2018`) → parses to **year 218** → an unscreened spell runs 218→2021 and spuriously flags 2005–2017. The screen makes the exclusion **explicit and reported**; dates are parsed with `ymd()` so nothing hides in a parse quirk. Current post-screen total: **35,417 by design** (2026-07-27). The other screened spells are future day-zeros that start after the window and never overlap it anyway. |

### D2.1 Verification (this session)

| check | result |
|---|---|
| 5,872,965 × 3 (as of 2026-07-27); grain unique; all uppercase; **1:1 join to ds 0** (identical keys) | ✓ |
| zero-vs-NA: no `0` in unobserved years; no `NA` in observed years; every `HPV_ACTIVE==1` has a covering spell | ✓ |
| spell-wins: 2,431 fac-yrs `HPV_ACTIVE==1` with `ICIS_OBSERVED==0` (expected) | ✓ |
| 9,743 ever-active facilities, 35,417 HPV_ACTIVE==1 (as of 2026-07-27; exact pre-screen R2 total not independently re-derived this pass, see H5) | ✓ |

---

## Part E · Dataset 3 — `penalties` (`05_penalties.R`)

The action-level record behind ds 0's facility-year `PENALTY_AMOUNT` / `N_PENALTIES`. One row per formal action.

**Source:** `data/processed/formal_actions.csv.gz` — the raw ICIS-Air formal-actions extract, event-grain
(one row per formal enforcement action), historical, not window-restricted (P3).

**Shape (as of 2026-07-27; drifts with each live ICIS-AIR refresh):**
```
105,946 actions | 17 cols | 37,363 facilities | years 1972–2026 | 72,560 with penalty>0
```

### E.1 Coding decisions

| # | Decision | Alternative not taken | Why / data fact |
|---|---|---|---|
| **P1** | **Grain = one row per `formal_actions.csv.gz` row; ALL rows kept, `dup>0` flagged not dropped.** Not one row per facility × formal action — a multi-facility settlement's co-defendant rows are separate source rows, not a fan-out this build introduces. `ENF_IDENTIFIER` (not `ACTIVITY_ID`) is the field that groups co-defendant rows of one settlement (P5); `ACTIVITY_ID` is a violation-grain field used elsewhere in this layer (`hpv_spells`/`pipeline`), not the settlement key here. | Dedup to distinct actions. | Layer convention (CC9/R3). As of 2026-07-27: 823 dup rows; event-distinct = 105,123. |
| **P2** | **Formal actions only.** | Pool informal too (as ds 0's enforcement does). | Only formal actions carry `PENALTY_AMOUNT`; informal has no penalty column. Penalties are the point of this dataset. |
| **P3** | **NOT window-restricted — all action years (1972–2026) kept.** | Clip to 2005–2025. | Six-dataset design pushes sample/window filters downstream; `YEAR` is provided so the user clips as needed. 67,049 of 105,946 actions fall in 2005–2025 (as of 2026-07-27). |
| **P4** | **`PENALTY_AMOUNT` kept AS RECORDED per row (0 or positive, never `NA`); no zero-vs-NA discipline.** | Apply ds 0's observed/`NA` coding. | Every row is an observed action with a recorded amount — the observability question doesn't arise at action grain. `HAS_PENALTY` = amount>0 companion flag. |
| **P5** | **Multi-facility settlement structure EXPOSED, not resolved** — `ENF_IDENTIFIER` (settlement key), `N_SETTLEMENT_FACILITIES`, `IS_MULTI_FACILITY`; per-row penalty left faithful. | Deduplicate broadcast penalties, or split them across co-defendants. | ⚠ As of 2026-07-27 (`output/penalties_profile/settlement_structure.csv`, `12_penalties_profile.R`): **571 settlements** span >1 facility (up to **117** co-defendants), each a separate row. The penalty is *usually* one value repeated (**507 of 571**) but **64 settlements carry DIFFERING per-facility amounts** — so it is **not** a clean broadcast, and neither "take one value" nor "sum" is universally right. Exposing the structure lets the user pick per analysis. **Do NOT sum `PENALTY_AMOUNT` across a settlement's facilities without a broadcast rule.** See `multi_facility_settlement_decision.md` §5 for a **separate, older** FRS-`REGISTRY_ID` crosswalk sub-analysis — 552 of 588 settlements (a REGISTRY_ID-based count from an earlier profiling pass, not re-run against the current 571-settlement `ENF_IDENTIFIER`-based count above) span genuinely distinct `REGISTRY_ID`s — not independently re-verified in this pass, and not a second measurement of the same 571. |

### E.2 Verification (this session)

| check | result |
|---|---|
| 105,946 × 17 (as of 2026-07-27); all uppercase; `HAS_PENALTY`/`IS_MULTI_FACILITY` consistent; `N_SETTLEMENT_FACILITIES` constant within `ENF_IDENTIFIER` | ✓ |
| `PENALTY_AMOUNT` ≥ 0, never `NA`; every action facility in the ds 0 universe (0 orphans) | ✓ |
| **reconciles to ds 0 exactly** — Σ `PENALTY_AMOUNT` over 2005–2025 actions = ds 0's observed `PENALTY_AMOUNT` total, **diff $0** | ✓ |

---

## Part F · Dataset 4 — `coordinates` (`06_coordinates.R`)

One row per facility: FRS lat/lon, derived county FIPS, and coordinate-vs-ICIS-county error diagnostics.
Reuses the panel spine's coordinate block + `coord_county_flag.R` helper, over the full universe.

**Source:** `data/raw/frs/FRS_FACILITIES.csv` (FRS, current-snapshot grain — one row per `REGISTRY_ID`, no
history) + `data/raw/us_counties/us_counties.shp` (Census cartographic boundary file, a static reference
shapefile, not time-varying) + `data/processed/facilities.csv.gz` (ICIS current snapshot, for `ICIS_COUNTY_FIPS`'s
`COUNTY_NAME` text).

**Shape (as of 2026-07-27; drifts with each live ICIS-AIR/FRS refresh):**
```
279,665 facilities | 11 cols | 236,219 with coordinates (84.5%) | 236,059 county_fips | 2,873 gross errors (1.3% of checkable)
```

### F.1 Coding decisions

| # | Decision | Alternative not taken | Why / data fact |
|---|---|---|---|
| **C1** | **Coordinate source = FRS via `REGISTRY_ID`** (deduped to one row/`REGISTRY_ID`). No FRS match → `HAS_COORDINATE == 0`, `NA` lat/lon. | ICIS-native coords (none reliable). | 84.5% of facilities get a coordinate; the ~15.5% gap is facilities with no `REGISTRY_ID` or no FRS row. |
| **C2** | **`COUNTY_FIPS` = point-in-polygon** of the coordinate into the county shapefile (EPSG:4326 → shapefile CRS). | Trust ICIS `COUNTY_NAME` text. | The shapefile is **NOT CONUS-only** (full Census county file, 56 `STATEFP` values: all 50 states + DC + 5 territories — see panel brief N18, the 2026-07-21 swap from a CONUS-filtered derivative to the raw file) and this join consults no state crosswalk, so it was never actually restricted to CONUS. Of AK/HI/PR/GU/MP/VI facilities with a valid FRS coordinate, **1,244 of 1,288 (96.6%)** get a real `COUNTY_FIPS`; the rest fail only because the point doesn't fall inside any polygon (offshore/imprecise coordinate), not a CONUS restriction. Derived FIPS is new here (ds 0 carries only the ICIS county *name*). |
| **C3** | **Error diagnostics via the shared `flag_coord_county` helper** — `COORD_COUNTY_DIST_KM` (km from coordinate to ICIS-claimed county; 0 = in-county, NA = uncheckable) and `COORD_GROSS_ERROR` (1 iff checkable & >5 km). | Roll a separate check. | Identical logic to the panel spine, so results are comparable. **0 ≠ NA honored** — never asserts 0 for a facility whose county name couldn't be resolved. **"Shared" is by convention, not by code** — `code/03_datasets/coord_county_flag.R` is a standalone, byte-for-byte-duplicated copy of `archive/panel_building_legacy/code/03_panel_building/coord_county_flag.R` (its own docstring flags this); a fix to one must be applied to both by hand. **Addendum (2026-07-28) — `COORD_COUNTY_DIST_KM` switched from EPSG:5070 to a direct geodesic distance:** the 2026-07-27 fix making AK/HI/PR/VI/GU/MP checkable didn't update the distance step, which still reprojected into EPSG:5070 (NAD83 / Conus Albers) — valid only for CONUS. Checked: CONUS mismatches were negligibly affected (mean 0.11 km, max 13 km vs. geodesic, over 3,379 cases) but Alaska mismatches diverged by up to ~21% (e.g. 817 km vs 993 km geodesic). `COORD_GROSS_ERROR` likely never flipped (every non-CONUS mismatch found was well past the 5 km cutoff either way), but the distance number itself wasn't trustworthy outside CONUS. Fixed in both copies of the helper, kept in sync per the note above. |
| **C4** | **Full 279,665 universe** (as of 2026-07-27; the spine computed this block for the 133,753 ever-active subset only). | Restrict to ever-active. | Consistent with the layer's full-universe rule; joins on `PGM_SYS_ID` to every facility-year dataset. |
| **C5** | **`ICIS_COUNTY_FIPS` = GEOID resolved from `(STATE, COUNTY_NAME)` text alone** (added 2026-07-22; same `flag_coord_county` helper as C3, its previously-unreturned `resolved_geoid`). `NA` when the name doesn't resolve to exactly one GEOID in this shapefile vintage. | Rely on `COUNTY_FIPS` (coordinate-derived) alone as the only FIPS field. | Needs no coordinate — pure function of the ICIS name — so coverage is wider than `COUNTY_FIPS`: set for **261,646 (93.6%)** of all 279,665 facilities (as of 2026-07-27, `output/coordinates_profile/icis_county_fips_summary.csv`, `15_coordinates_profile.R`) vs. `COUNTY_FIPS`'s 236,059 (84.4%). Where both are set (225,216 facilities), they agree **97.3%** of the time (219,167/225,216) — matches the C3 match rate closely, since both sides share the same resolution logic. Gives a lat/long-independent second check on county assignment, and a fallback FIPS where `COUNTY_FIPS` is `NA` for lack of a coordinate. |

### F.2 Verification (this session)

| check | result |
|---|---|
| 279,665 × 11 (as of 2026-07-27); grain unique; all uppercase; `HAS_COORDINATE` / `COORD_GROSS_ERROR` logic consistent; `COUNTY_FIPS` only where a coordinate exists | ✓ |
| coordinate plausibility: 0 lat/lon out of range, 0 exact-(0,0); dist median 0 km, p99 7.8 km | ✓ |
| **consistency vs panel spine** — across all 133,753 shared facilities (as of 2026-07-27; not independently re-verified this pass, see spine's own N13 figures) | — |
| **`ICIS_COUNTY_FIPS` vs `COUNTY_FIPS` agreement** — 219,167/225,216 (97.3%) where both set; 261,646 (93.6%) of all facilities have `ICIS_COUNTY_FIPS` set | ✓ |

---

## Part G · Dataset 6 — `pipeline` (`07_pipeline.R`)

Facility × year, built from EPA ECHO's **CAA Compliance Pipeline** download
(`data/raw/PIPELINE_CAA_00_COMPLETE.csv`; manually staged 2026-07-23, **automated in `01_download.R` as of
2026-07-27** — see the CAA Pipeline note in that script's header — so this source is now on the same
weekly-refresh footing as the rest of the ECHO downloads). Raw grain is one row per **violation**, optionally
linked backward to the evaluation (inspection) that found it and forward to the enforcement action it
triggered.

**Value-added vs. datasets 0/2/3** (why this is worth a seventh file, not a restatement of what exists):

| Existing dataset | What it has | What `pipeline` adds |
|---|---|---|
| `regulatory` (ds 0) | inspection/violation/enforcement **counts**, no linkage between them | which evaluation *found* which violation, which violation *triggered* which enforcement action — a same-row causal chain no ICIS-Air table alone provides |
| `hpv_spells` (ds 2) | **HPV only** (FRV excluded by H1) | the **FRV population** (39,987 in-window rows, 2.3× the HPV count) — a violation tier invisible elsewhere in this layer |
| `penalties` (ds 3) | formal-action penalties, action-grain | `EA_PENALTY_AMT` attributable to the *specific violation* that caused it — see the caveat at G4 below |
| none | — | `MEAN_EVAL_TO_VIOL_LAG_DAYS` / `MEAN_VIOL_TO_EA_LAG_DAYS` — "pipeline speed" measures nothing else in the layer computes |

**Shape (as of 2026-07-27; the raw pipeline file is now automated and live-refreshed, same as every other
ECHO source in this layer — see the note above):**
```
5,872,965 rows | 14 cols | 279,665 facilities × 21 years | 31,279 observed facility-years (0.5%)
18,334 ever-observed facilities | 17,210 HPV + 39,987 FRV = 57,197 in-window violations
```
*(Was 31,796 observed / 18,529 ever-observed / 17,130 HPV + 40,708 FRV = 57,838, measured against the
manually-staged 2026-07-23 raw file — now superseded by the automated 2026-07-27 fetch.)*

### G.1 Coding decisions

| # | Decision | Alternative not taken | Why / data fact |
|---|---|---|---|
| **PL1** | **7,218 of 66,723 raw rows are EPA-system-generated placeholders, not real violations**, identified by blank `VIOL_START_DATE` + `VIOL_ACTIVITY_ID` prefixed `9906`/`9913` + `VIOL_TYPE` blank or `"Linked to Viol. Below"` — matches the dictionary's note that these IDs "did not have an actual violation activity identification number." | Keep them as zero-duration/degenerate rows. | They have no date to anchor a year, so they are structurally excluded (asserted in-build) rather than filtered by a fragile heuristic. After exclusion, `VIOL_TYPE` partitions **exactly** into {HPV, FRV} — asserted. |
| **PL2** | **Year anchor = `VIOL_START_DATE`**, not the cleaned asset's own `date` column (`SORT_DATE`). | Use `SORT_DATE`/`date` (already parsed in `data/processed/pipeline.csv.gz`). | `SORT_DATE` is EPA's own "latest stage reached" display date — now permanently checked by `code/diagnostics/16_pipeline_profile.R` (`pl2_sort_date_check.csv`): **0 exceptions across 66,699 non-blank rows** (2026-07-27), confirming `SORT_DATE = coalesce(EVAL_DATE, VIOL_START_DATE, EA_DATE)`. ⚠ **Correction**: this priority order is the *opposite* of a previous, incorrect prose description here ("EA_DATE if an EA is linked, else VIOL_START_DATE, else EVAL_DATE") — that ordering was never actually tested against the data; empirically it gives a 58% mismatch rate. The correct order was found by testing every plausible permutation and keeping the one with 0 exceptions, not by trusting the dictionary's prose. Using `SORT_DATE` instead of `VIOL_START_DATE` would misdate a violation into a later year purely because it was eventually evaluated or enforced after the fact. |
| **PL3** | **Universe = the same 279,665-facility (as of 2026-07-27) × 2005–2025 rectangle as ds 0/1/2b** (G3/G4), so `pipeline` joins **1:1** to `regulatory.csv.gz` on `(PGM_SYS_ID, YEAR)` (verified: identical key vectors). | Build only over the 20,222 facilities the raw file actually contains. | Consistent with the layer's full-universe convention; as of 2026-07-27 **all 20,222 of 20,222 (100%)** raw-file facilities match the ICIS universe — the full rectangle costs nothing either way. |
| **PL4** | **`EA_PENALTY_AMT_SUM` is exposed per facility-year but flagged — do NOT sum alongside `penalties.csv.gz`'s `PENALTY_AMOUNT` without a dedup rule.** | Reconcile the two now. | Same P5 pattern as ds 3: both very likely trace to the same underlying enforcement-action dollars. Reconciling requires matching pipeline's `EA_ACTIVITY_ID`/`EA_FEA_ACTIVITY_ID` against ds 3's `ENF_IDENTIFIER`, which is deliberately left undone here — exposing the structure lets the user pick per analysis, as ds 3 already does for multi-facility settlements. |
| **PL5** | **`N_VIOL_SELF_DISCLOSED` guarded against `NA` propagation** — `EVAL_TYPE_DESC` is blank (parses to `NA`) on the ~46% of rows with no linked evaluation, and an unguarded `== "Self-Disclosure"` comparison produces `NA`, which then poisons `sum()` for the whole facility-year group under the zero-vs-NA rule. Fixed by gating on `has_eval & !is.na(EVAL_TYPE_DESC)` first. | Trust `sum(x == "...")` directly. | Caught by an independent post-build Python check (not the in-build `stopifnot`s, which didn't originally cover this column) — added two more invariants (`N_VIOL_SELF_DISCLOSED`, `N_VIOL_WITH_EVAL`/`N_VIOL_WITH_EA` never `NA` on an observed row) to guard against the same class of bug recurring. |
| **PL6** | **`REGISTRY_ID` joined from `facilities.csv.gz`, not read from the raw file's own `REGISTRY_ID` column** (which is present natively, unlike most other sources in this layer). | Trust the pipeline file's own `REGISTRY_ID`. | Matches G4 exactly and avoids a second, possibly stale, FRS snapshot disagreeing with the rest of the layer. |

**Deliberately deferred** (documented as scope, not silently missing): full `EVAL_TYPE_DESC`/`EA_TYPE`
category breakdowns beyond self-disclosure; any dedup reconciliation of `EA_PENALTY_AMT_SUM` against ds 3
(PL4).

### G.2 Verification (this session)

| check | result |
|---|---|
| 5,872,965 × 14 (as of 2026-07-27); grain `PGM_SYS_ID × YEAR` unique; rectangle complete (279,665 × 21); all names uppercase | ✓ |
| **1:1 join to `regulatory.csv.gz`** — identical key vectors | ✓ |
| zero-vs-NA: `PIPELINE_OBSERVED==1 ⟺` every count column non-`NA`; `==0 ⟺` every count `NA` | ✓ |
| `N_VIOL_HPV + N_VIOL_FRV == N_VIOL_PIPELINE` on every observed row | ✓ |
| `N_VIOL_WITH_EA_PENALTY > 0 ⟺ EA_PENALTY_AMT_SUM > 0` on every observed row | ✓ |
| placeholder rows (7,218 — the raw pipeline file is now live-refreshed, no longer static) structurally absent from every facility-year (no `VIOL_START_DATE` → no year) | ✓ |
| HPV 17,210 + FRV 39,987 = 57,197, matching `code/diagnostics/16_pipeline_profile.R`'s own independent count from raw `VIOL_START_DATE` year distribution, 2005–2025 window | ✓ |

**Profile**: `briefs/datasets/pipeline_profile.md` (built by `code/diagnostics/16_pipeline_profile.R`) —
linkage rates, `EVAL_TYPE_DESC`/`EA_TYPE` breakdowns, lag-day distributions, and the eval-linkage coverage
cliff before 2015.

---

## Part H · Dataset 7 — `emissions` (`08_emissions.R`)

Facility × year, built from the combined pollutant report (`data/processed/emissions.csv.gz`; raw source
`POLL_RPT_COMBINED_EMISSIONS.csv`, cross-program: EIS, TRIS, E-GGRT, CAMDBS). Raw grain is `REPORTING_YEAR ×
REGISTRY_ID × PGM_SYS_ACRNM × PGM_SYS_ID × POLLUTANT_NAME`, 10,411,871 rows. **Historical**, but structurally
uneven across programs, not a uniform annual time series: EIS (90% of rows) only reports in NEI's triennial
inventory years (2008/2011/2014/2017/2020); TRIS/CAMDBS/E-GGRT report annually but only from 2015 on (EM7).

**Value-added vs. datasets 0–6** — nothing else in this layer carries measured emission *quantities*. Ds 0's
`EMITS_*` flags are undated booleans from `ICIS-AIR_POLLUTANTS.csv` ("ever permitted to emit"), not
measurements. This dataset adds annual pounds for VOC/PM10/PM2.5/NOx/SO2/CO, a broader HAP total, and GHG
(metric tons CO2e, its own column/unit) — and is the only source in the layer that is cross-program (TRI,
mandatory GHG reporting, Clean Air Markets — not just ICIS-Air).

**Shape (as of 2026-07-27; drifts with each live ICIS-AIR/FRS refresh — see EM2):**
```
5,872,965 rows | 15 cols | 279,665 facilities × 21 years | 281,413 observed facility-years (4.79%)
54,335 ever-observed facilities | 42,734 GHG-observed facility-years | 5,334 ever-GHG-observed facilities
```

### H.1 Coding decisions

| # | Decision | Alternative not taken | Why / data fact |
|---|---|---|---|
| **EM1** | **Join key = `REGISTRY_ID` (FRS), not `PGM_SYS_ID`.** Every other dataset in this layer joins on `PGM_SYS_ID`; this is the first that can't, because the raw rows are cross-program (`PGM_SYS_ACRNM` ∈ {EIS 90.1%, TRIS 7.7%, E-GGRT 1.9%, CAMDBS 0.3%}) and each program has its own facility-id scheme. | Use the raw file's own `PGM_SYS_ID`. | It isn't reliably an ICIS-Air id outside EIS/CAMDBS rows; `REGISTRY_ID` is the only cross-program identifier both sides share. |
| **EM2** | **`REGISTRY_ID` fan-out exposed, not resolved** — `N_PGM_SYS_ID_SHARING_REGISTRY` / `IS_SHARED_REGISTRY`, same pattern as ds 3's multi-facility settlements (P5). As of 2026-07-27: 8,658 REGISTRY_IDs map to >1 `PGM_SYS_ID` in `facilities.csv.gz` (max 150); 22,175 facilities (465,675 facility-years) carry `IS_SHARED_REGISTRY==1`. **These exact counts are NOT fixed** — ICIS-AIR and FRS are EPA's live current-bulk downloads with no archival checksum, so the fan-out shifts with every source refresh. `08_emissions.R`'s invariants check the flag is *internally consistent* (matches its own definition, survives the facility-level join unchanged) — never a snapshot-pinned number — and the current count is printed in the build summary each run, not hand-entered here. | Restrict to REGISTRY_IDs matching exactly one facility, or split emissions proportionally across co-mapped facilities; **originally also tried a hardcoded `stopifnot(... == 8632)` check** — dropped 2026-07-27 once a live ICIS-AIR refresh made it stale (see W-note in `01_download.R`'s git history / this repo's reproducibility discipline: nothing that depends on EPA's live snapshot state belongs in a fixed equality check). | No principled way to split a reported quantity across co-mapped facilities from this source alone; broadcasting identically and flagging lets the user decide, consistent with how ds 3 handles multi-facility settlements. **Do not sum `emissions` across facilities sharing a `REGISTRY_ID`** — it double-counts the same reported value. |
| **EM3** | **Only ~19.4% of ICIS facility-rows (54,335 of 279,665, as of 2026-07-27) ever have emissions data** — a REGISTRY_ID-match rate against the raw file (last profiled at 31.6% of 162,383 distinct `REGISTRY_ID`s, not independently re-verified this pass) is a separate, lower-level statistic; most emissions reporters (pure TRI/GHG/NEI filers) are outside the ICIS-Air CAA universe entirely. | Build a separate, wider dataset over the full emissions-source universe. | Kept to the ICIS `PGM_SYS_ID` universe (G3/G4) so this joins 1:1 to `regulatory.csv.gz` like every other dataset; the coverage cost is real and documented, not hidden. |
| **EM4** | **Pollutant columns match a single canonical `POLLUTANT_NAME` string EXACTLY, never by substring/regex.** PM10 and PM2.5 each have a total (`"Primary PM10 (filterables and condensibles)"` / `"...PM2.5..."`) plus several component/speciation variants that are SUBSETS of that total. **Verified the risk is real**: a naive substring match (`grepl("PM10", ...)`) inflates the true PM10 total by **1.7×** (11.66B lbs vs. the correct 7.04B lbs, raw-file-wide); same 1.7× inflation for PM2.5. VOC/NOx/SO2/CO have exactly one variant each, so exact match costs nothing there. | Sum all rows matching a substring/regex per category. | A silent, easy-to-miss double-count — caught only by deliberately comparing exact-match vs. substring-match totals before committing to the design. |
| **EM5** | **`HAP_LBS` sums every row with `NEI_TYPE == "HAP"`** (292 distinct pollutant names). Checked for a "Total HAP" aggregate row first (would double-count against the individual HAPs it aggregates) — **none exists**, so the plain sum is safe. | Assume safety without checking. | Same class of risk as EM4; this one happened to be clean. |
| **EM6** | **`GHG_MTCO2E`/`GHG_OBSERVED` kept fully independent of `EMISSIONS_OBSERVED`/the pounds columns.** `UNIT_OF_MEASURE` is `MTCO2e` for E-GGRT rows only (196,055 of 10.4M), `Pounds` for everything else — never combinable. GHG reporting (E-GGRT) is also its own regulatory requirement, not a subset of EIS/TRI/CAMD air-toxics reporting, so a facility can be `GHG_OBSERVED` without being `EMISSIONS_OBSERVED` or vice versa. | Fold GHG into the same observability flag as the pounds measures. | Conflating the two would assert a false zero-vs-NA relationship between two independent reporting regimes. |
| **EM7** | **Coverage is structurally uneven, not incidental** — EIS (90% of raw rows) has data ONLY in 2008, 2011, 2014, 2017, 2020 (NEI's real triennial inventory cycle); TRIS/CAMDBS/E-GGRT report annually but only from 2015 on. Raw `REPORTING_YEAR` spans 2008–2024, inside this layer's 2005–2025 window (G1) — 2005–2007 and 2025 are simply never observed. | Interpolate/carry forward between NEI cycles. | Left as raw, undated gaps (same zero-vs-NA discipline as the rest of the layer) — interpolation is an analysis-time choice, not a build-time one. |
| **EM8** | **Duplicate rows kept, not deduped** (R3 precedent) — 11,774 of 10,397,173 `(year, REGISTRY_ID, PGM_SYS_ACRNM, PGM_SYS_ID, POLLUTANT_NAME)` groups have >1 row (1,984 byte-identical). All rows are summed as-is. | Dedup at aggregation. | Consistent with every other dataset's "count/sum everything, flag don't drop" convention; the duplicate share is small (0.11%). |

### H.2 Verification (this session)

| check | result |
|---|---|
| 5,872,965 × 15; grain `PGM_SYS_ID × YEAR` unique; rectangle complete (279,665 × 21); all names uppercase | ✓ |
| **1:1 join to `regulatory.csv.gz`** — identical key vectors | ✓ |
| zero-vs-NA: `EMISSIONS_OBSERVED`/`GHG_OBSERVED` each independently gate their own columns (never NA when observed, never non-NA when not) | ✓ |
| `IS_SHARED_REGISTRY` is internally consistent (matches `N_PGM_SYS_ID_SHARING_REGISTRY > 1`, NA-ness agrees, no non-positive fan-out) and survives the facility-level join into `em` unchanged — **not** checked against a fixed count (see EM2) | ✓ |
| independent re-derivation: naive substring match on `PM10`/`PM2.5` inflates the raw-file-wide total by 1.7× vs. the exact-match design — confirms EM4 is load-bearing, not theoretical | ✓ |
| built-dataset pollutant totals (e.g. PM10 6.02B lbs) are smaller than the raw-file-wide total (7.04B lbs) — expected, since the dataset is restricted to the ~19.4% ICIS-matched universe (EM3), partially offset by EM2's broadcast | ✓ (explained, not an error) |

**Profile**: `briefs/datasets/emissions_profile.md` (built by `code/diagnostics/17_emissions_profile.R`) —
pollutant-level distributions, the triennial/2015 coverage pattern, and the shared-`REGISTRY_ID` fan-out.

---

## Dataset 5 · planned (not yet built)

Designs from `00_parameters.R`; decisions recorded as each is built. Every builder routes through
`write_dataset()` so the G2 uppercase convention holds layer-wide and joins on `PGM_SYS_ID`/`YEAR` line up.
- **ds 0 + ds 1 are a pair** — ds 1's `operating` / `WAYBACK_OBSERVED` is what makes ds 0's 87% all-`NA`
  core interpretable (which `NA`s are "not operating" vs "operating but no ICIS event"). Read together.
