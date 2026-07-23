# Dataset Construction Decisions

> Scope: the **`code/04_datasets/` layer** — the six deliverable datasets that supersede the single wide
> panel, now this repo's main product. Facility-spine/panel-building code and its construction-decisions
> doc (formerly `../panel/panel_construction_decisions.md`) moved to the CAA_Project repo (2026-07-23); this
> layer still consumes the `data/processed/` cleaned assets unchanged, just without a local copy of the
> spine-layer decision log.

**The deliverable is six datasets, not one panel.** Each is built once over the FULL facility universe;
any sample restriction is a downstream filter, not a pre-built panel. All join on `PGM_SYS_ID` (+ `YEAR`
where the grain is facility × year).

| # | dataset | grain | contents | status |
|---|---|---|---|---|
| 0 | `regulatory`  | facility × year | ICIS-Air only: event counts + ICIS facility characteristics | ✅ built & audited |
| 1 | `operating`   | facility × year | wayback status, program-active flags, entry/exit, program begin year | ✅ built & audited |
| 2 | `hpv_spells`  | spell           | one row per HPV spell, UNcollapsed | ✅ built & audited |
| 2b | `hpv_active` | facility × year | R2 collapse of `hpv_spells` → HPV-active flag | ✅ built & audited |
| 3 | `penalties`   | formal action   | action-level penalties + multi-facility settlement key | ✅ built & audited |
| 4 | `coordinates` | facility        | FRS lat/lon, county, coordinate-error diagnostics | ✅ built & audited |
| 5 | `attainment`  | facility × year | PM2.5 (2012) nonattainment | ⬜ not started |
| 6 | `pipeline`    | facility × year | EPA ECHO "CAA Compliance Pipeline": linked evaluation→violation→enforcement counts, HPV/FRV split, eval/enforcement lag days | ✅ built & audited |

---

## Part A · layer-wide conventions (`00_parameters.R`)

| # | Decision | Alternative not taken | Why |
|---|---|---|---|
| **G1** | **Window `YEARS = 2005:2025`** applied at dataset build, not in the assets. | Bake the window into `data/processed/`. | Assets stay reusable for any window; the window is one line here. Inherited from panel-layer CC2. |
| **G2** | **Every column in the dataset layer is `UPPER_SNAKE_CASE`.** Builders assemble internally in lowercase, then uppercase **once on write** via `write_dataset()`. | Hand-name every output column uppercase in each aggregator; or leave mixed case as sources deliver it. | One convention across all six files so join keys (`PGM_SYS_ID`, `YEAR`) and every derived column line up on merge with no per-file casing fixups. Single transform point = no typo drift across ~60 column literals. `toupper()` is idempotent on the already-uppercase ICIS attributes. |
| **G3** | **Full universe, no sample panels.** Datasets 1–5 built over all facilities; restrictions are downstream filters. | Ship pre-filtered contiguous-US / major-source panels as in the old panel layer. | The six-dataset design pushes sample definition to the analysis, not the build — one canonical set of files, many samples. |
| **G4** | **Every dataset carries `REGISTRY_ID` (FRS cross-program facility id) alongside `PGM_SYS_ID`**, joined in from `facilities.csv.gz`; `NA` where a facility has no FRS match (same convention as `coordinates`' `HAS_COORDINATE==0`). | Leave `REGISTRY_ID` only on `regulatory`/`coordinates` (the prior state) and require a manual join elsewhere. | `regulatory` and `coordinates` already carried it, but `operating`, `hpv_spells`, `hpv_active`, `penalties` didn't — surfaced when checking whether multi-facility settlement co-defendants share an FRS id (`multi_facility_settlement_decision.md` §5) required a manual join to `facilities.csv.gz` that shouldn't be necessary for a question this basic (facility identity across ICIS program systems, not just within one). |

---

## Part B · Dataset 0 — `regulatory` (`01_regulatory.R`)

**Built from the raw ICIS-Air download and NOTHING ELSE.** Every column is either an ICIS event count or
an ICIS facility characteristic — no wayback status, no FRS coordinates, no Green Book, no AFS. Those are
datasets 1–5.

**Shape (rebuilt & audited this session):**
```
5,863,431 rows | 80 cols | 279,211 facilities × 21 years | 751,963 observed facility-years (12.8%)
```

### B.1 Coding decisions

| # | Decision | Alternative not taken | Why / data fact |
|---|---|---|---|
| **R1** | **Universe = every `PGM_SYS_ID` in `ICIS-AIR_FACILITIES` (279,211), NO ever-active screen.** | Keep only facilities with ≥1 event in-window (the panel-layer "ever-active" universe, ~136k). | Retains the never-inspected population (mostly operating minor sources). **51% of facilities have zero events in-window** and sit all-`NA` here until dataset 1 supplies operating status. Consequence: only **12.8%** of the rectangle is observed — the dataset is close to unusable standalone by design, which is why ds 0 and ds 1 must be documented as a pair. |
| **R2** | **Zero-vs-NA rule (load-bearing).** A facility-year is `ICIS_OBSERVED == 1` iff ICIS holds ≥1 row across ANY of the six event assets that year. Then a count of 0 for some *other* measure is a **true zero**. With no record of any type → **every count is `NA`** (unknown, not zero). | Use operating status to code zeros; or code all non-events as 0. | Within-ICIS presence is the only within-ICIS evidence the facility was tracked that year. Operating-status inference is deliberately held out — that is **dataset 1's** job, kept out so ds 0 is pure ICIS. |
| **R3** | **Every `N_*` counts ALL rows; nothing deduped.** Duplicate load surfaced via `N_*_DUP` (event-key repeats, `dup>0`) and `N_*_DUP_EXACT` (byte-identical). Event-distinct = `count − dup`. | Dedup at aggregation (old `distinct`). | Honesty about the raw record + measurable duplication in place. Inherited from panel-layer CC9 / the 2026-07-17 no-dedup revision. Duplicated families: inspections, enforcement (incl. formal/informal split), certs. **Violations & stack tests carry zero dups — asserted in the build** (`all(dup == 0)`). |
| **R4** | **`PENALTY_AMOUNT` obeys the zero-vs-NA rule** — real dollar sum (0 included) when observed, `NA` when unobserved. | Old convention: `NA` when no penalty. | One rule for the whole file. **Flagged for sign-off** — this changed penalty semantics from the panel layer. |
| **R5** | **Facility characteristics are the current ICIS snapshot, time-invariant, applied to all 21 years.** (`FACILITY_NAME`, `STATE`, `NAICS_CODES`, `AIR_POLLUTANT_CLASS_DESC`, `OP_STATUS_CURRENT_DESC`, …) | Reconstruct history. | ICIS carries no history for these. An industry reclassification or ownership change is **not** visible — a known limitation, not a bug. |
| **R6** | **`EMITS_*` (6) and `PROG_*` (8) are ever-reported / ever-enrolled, undated → time-invariant flags.** A facility absent from `pollutants`/`programs` gets flag = **0** (absent profile). `PROG_GACT`/`PROG_CFC` (CAAGACTM/CAACFC) deliberately **excluded** (2026-07-21) to match the 8-group allowlist now used in dataset 1's `PROG_*_ACTIVE` (O3); `N_PROGRAMS` still counts every `PROGRAM_CODE` including these two — only the per-program flags dropped. | Treat absence as `NA`; or keep all 10 groups. | ICIS gives no start/end dates for pollutant or program association, so these can only be "ever" flags. Absence of an enrollment record = not enrolled in that program → a true 0. |
| **R7** | **`N_PROGRAMS` is `NA`-able, never 0.** `n_distinct(PROGRAM_CODE)` is ≥1 for any facility present in `programs.csv.gz`, so a 0 never arises legitimately; a facility with **no program association** stays `NA`. | Coalesce to 0 like the `PROG_*` flags (the pre-fix behavior). | Distinguishes "not associated with **any** program" (`NA`) from the `PROG_*` flags' "not enrolled in **this** program" (0). **12,467 facilities (4.5%) are absent from `programs.csv.gz`** → `N_PROGRAMS = NA` for exactly those (261,807 facility-years). ⚠ **NA now carries two meanings in this file** — see R8. |
| **R8** | **`program_begin_year` is deliberately ABSENT from ds 0.** | Carry it here alongside program enrollment. | `BEGIN_DATE` is a facility-lifecycle proxy, so it belongs with the operating evidence in **dataset 1**, not with the undated "ever-enrolled" flags. |

### B.2 ⚠ Two meanings of `NA` in this file

A downstream user must not conflate them:
- `is.na(N_INSPECTIONS)` (and all other event counts) is a **year-level** condition → facility not observed in ICIS that year (`ICIS_OBSERVED == 0`).
- `is.na(N_PROGRAMS)` is a **facility-level** condition → no program association on record at all, constant across all 21 years.

Both ride on `NA` in the same table. Needs a codebook line so `is.na()` isn't read as one thing.

### B.3 Verification (this session, independent of the in-build assertions)

All passed on the rebuilt file:

| check | result |
|---|---|
| `PGM_SYS_ID × YEAR` unique; rectangle complete (rows = 279,211 × 21) | ✓ |
| all 80 column names uppercase | ✓ |
| observability rule across **all 48 event-count columns** (obs → never `NA`, unobs → always `NA`) | ✓ |
| every observed row carries ≥1 real event (rule means what it claims) | ✓ 0 violations |
| `N_HPV + N_FRV = N_VIOLATIONS`; `N_FORMAL + N_INFORMAL = N_ENFORCEMENT` | ✓ |
| no `_DUP` exceeds its parent; `PENALTY_AMOUNT > 0 ⟺ N_PENALTIES > 0` | ✓ |
| attributes complete (0 missing `STATE`) and time-invariant (0 facilities with varying class / `N_PROGRAMS`) | ✓ |
| `N_PROGRAMS`: `NA` for 12,467 facilities (= programs-table gap), never 0, min non-`NA` = 1 | ✓ |

*Note on the audit:* an initial `grep("^N_")` check swept `N_PROGRAMS` (a profile column) into the
event-count set and false-flagged all 5.1M unobserved rows. Corrected by excluding `N_PROGRAMS` — 0 real
leaks. Recorded here because the `N_`-prefix ambiguity is a genuine trap (R7/R8).

---

## Part C · Dataset 1 — `operating` (`02_operating.R`)

The operating evidence ds 0 deliberately holds out (R2/R8): year-varying operating status, program-active
flags, facility entry/exit spells, earliest program-enrollment year. Built from the bespoke **Wayback**
reconstruction (`code/02_cleaning/wayback/`, panel-layer W1–W6/N8–N11) + `programs.BEGIN_DATE`.

**Shape (built & audited this session):**
```
5,863,431 rows | 21 cols | 279,211 facilities × 21 years | 2,716,186 wayback-observed facility-years (46.3%)
```
46.3% of the 21-year rectangle is wayback-covered — but Wayback is **2015–2025 only**, so within those 11
years coverage is **~88%** of facility-years.

### C.1 Coding decisions

| # | Decision | Alternative not taken | Why / data fact |
|---|---|---|---|
| **O1** | **Universe = dataset 0's exactly** — same 279,211 facilities × 2005–2025 rectangle, so `operating` joins **1:1** to `regulatory` on `(PGM_SYS_ID, YEAR)` (verified: identical key vectors). | Use Wayback's own 292,040-facility universe. | Wayback covers a **larger** set; the **15,301 wayback-only facilities** (absent from `ICIS-AIR_FACILITIES`) are **dropped** — this layer is keyed to the ICIS universe. The **2,472** ICIS facilities with no Wayback spell get `NA` spell fields. |
| **O2** | **Strictly raw — NO imputation.** Yearly `operating`/`op_status`/`prog_*_active` are carried for 2015–2025 and left **`NA`** for 2005–2014 and any facility-year absent from a snapshot. `WAYBACK_OBSERVED` (1 iff the facility appears in that year's snapshot) is the coverage flag. | Extend status across pre-2015 / interior gaps using the entry/exit spells. | Mirrors ds 0's zero-vs-NA discipline: don't manufacture certainty Wayback lacks. Spells are provided **separately** (O4) so the user can extend downstream by choice, not by baked-in assumption. *(User decision, 2026-07-20.)* |
| **O3** | **`operating` carried unchanged from the cleaning layer** — whitelist flag (1 iff code ∈ {OPR,TMP,SEA}). `PROG_*_ACTIVE` is pinned to an **explicit 8-group allowlist** (`sip/titlev/nsps/mact/neshap/fesop/nsr/psd`) via `col_select`, using the cleaning layer's own program-specific active rule (N11). | Re-derive here; or read `wayback_program_status.csv.gz` unrestricted (all 10 groups it now carries). | The two rules answer different questions and won't always agree (N11); kept faithful to source. Build asserts `operating == whitelist(op_status_code)` as a tripwire. ⚠ **History (2026-07-21):** `data/processed/wayback_program_status.csv.gz` was stale (predating this session) when dataset 1 was first built, so it only had 8 groups; rebuilding it as part of the W7 fix (`../panel/panel_construction_decisions.md`) regenerated it with the 2 groups the code had long supported upstream (`gact`, `cfc`) but this dataset had never carried. `02_operating.R` originally read that file with no column allowlist, so it silently absorbed both new columns on rebuild. **Decision: exclude `gact`/`cfc` from this dataset** — `col_select` now pins to the original 8 explicitly, so a future change to the upstream file can't silently change this dataset's schema again. Shape stays **5,863,431 rows | 21 cols**. |
| **O4** | **Entry/exit spells broadcast facility-level, time-invariant** — `ENTERED_YEAR`, `EXITED_YEAR`, `EXIT_SOURCE`, `LEFT_CENSORED`, `RIGHT_CENSORED`, as-is. | Collapse into a single operating-span imputation. | ⚠ **`EXIT_SOURCE` in this dataset is effectively pure `cls`** (18,771 confirmed closures). Of 11,801 Wayback `dropout` exits (last-seen-operating then vanished — the N8 upper bound on unexplained exits), **11,799 are wayback-only facilities dropped by O1**; only **2** survive. **Disappearances are therefore NOT visible in ds 1 — this is an accepted, documented cost** (user decision, 2026-07-20; see O1a). Coherent (a facility gone from snapshots is also gone from the facilities table), but load-bearing: exit analysis from ds 1 alone sees confirmed closures only. |
| **O1a** | **The 15,301 wayback-only "disappeared" facilities are excluded (not added to any dataset). To study disappearances, go to the raw Wayback layer directly** — `data/processed/wayback_facility_spells.csv.gz` (filter `exit_source == "dropout"`) joined to `wayback_facility_status.csv.gz`. | Broaden ds 1 to the union universe; or add them to both ds 0 and ds 1. | **Why excluding is defensible:** all 15,301 carry **zero ICIS events** and **zero ICIS attributes** (absent from `facilities.csv.gz`) — they'd be all-`NA` ghosts in the ICIS datasets. And the missing exits are **dominated by artifacts**: **10,781 of ~11,833 "exit" in 2015**, the first snapshot year (left-edge dropouts, N8). **Why it has a cost:** ~**1,050** are real **mid-window (2016–2025)** disappearances that ds 1 cannot see. Anyone modeling facility exit/survival must pull these from the raw Wayback layer and reconcile them against the ds 1 universe by hand. |
| **O5** | **`EARLIEST_PROGRAM_BEGIN_YEAR` = min `BEGIN_DATE` year, SCREENED to [1970, 2025]; plus `EARLIEST_PROGRAM_BEGIN_YEAR_RAW` = unscreened min.** (Renamed from `program_begin_year` to mark it a min.) | Facility min of raw dates only; or clip to the panel window. | ⚠ ~2.3% of source `BEGIN_DATE` years are **implausible** — **3,170** facilities < 1970 (incl. a `218`), **3,056** dated **entirely > 2025** (`2026–2028`). Because the field is a **min**, one garbage-low date poisons a facility's earliest year. Screen = validity filter on malformed values (**1970** = Clean Air Act; **2025** = window end), **not** imputation. The screen changed **6,226** facilities (**5,984** → `NA`, only out-of-range dates); `_RAW` preserves everything for full traceability. `NA` (screened) where no program record (**≥ 12,467**, the R7 programs-gap) or no in-range date. *(User decision, 2026-07-20.)* |

### C.2 Verification (this session, independent of in-build assertions)

| check | result |
|---|---|
| shape 5,863,431 × 21; grain `PGM_SYS_ID × YEAR` unique; all names uppercase | ✓ |
| **1:1 join to `regulatory.csv.gz`** — same row count, identical key vectors | ✓ |
| strictly-raw: `operating`/`op_status`/`prog_*_active`/`WAYBACK_OBSERVED` all `NA`/0 before 2015 | ✓ 0 leaks |
| `WAYBACK_OBSERVED ⟺ op_status_code` present; `operating == whitelist(code)`, never `NA` when code present | ✓ |
| all 6 facility-level fields (spells + begin years) constant within facility | ✓ |
| screened begin year ∈ [1970,2025] ∪ `NA`; screened ≥ raw (screen only removes) | ✓ |
| screen effect: 6,226 facilities changed, 5,984 → `NA`; raw range [218, 2028] preserved | ✓ |

---

## Part D · Dataset 2 — `hpv_spells` (`03_hpv_spells.R`) + `hpv_active` (planned)

The spell-level source of truth for High Priority Violation status. `hpv_active` (facility × year) will be a
deterministic collapse of this table under rule R2 (below), so nothing is lost. Design choices were made off
two diagnostics: `code/diagnostics/08_hpv_spell_diagnostics.R` (record profile) and `09_hpv_facility_year_rules.R`
(mapping-rule comparison).

**Shape (built & audited this session):**
```
44,490 spells | 18 cols | 15,638 facilities
status: closed 40,083 · open 3,997 · bad_order 377 · missing_start 33
```

### D.1 Coding decisions

| # | Decision | Alternative not taken | Why / data fact |
|---|---|---|---|
| **H1** | **HPV universe = `ENF_RESPONSE_POLICY_CODE == "HPV"`** (the enforcement-response tier), NOT day-zero presence. | Define HPV as "has `HPV_DAYZERO_DATE`". | The tier below, **FRV** (Federally Reportable Violation), is excluded. Diagnostic 08 showed the two definitions differ by only **33** records (every day-zero record is ENF-coded HPV; ENF adds 33 start-less ones), but the ENF filter is self-documenting and *surfaces* the 33 instead of silently dropping them. The 28,299 "resolved date but no day-zero" records are **FRVs** (28,276 coded FRV), a different object — correctly out of scope. *(User decision, 2026-07-20.)* |
| **H2** | **Spell grain — one row per HPV record, UNcollapsed.** Overlapping/concurrent spells are NOT merged. | Merge into consolidated per-facility spells. | Faithful source of truth; merging is a collapse-time choice. **42.6%** of closed spells overlap another spell of the same facility (diagnostic 09) — union is deferred to `hpv_active`, not baked in here. |
| **H3** | **`SPELL_STATUS` ∈ {closed, open, bad_order, missing_start}** (mutually exclusive); **`SPELL_DAYS`** (inclusive) defined **only** for `closed`. | Drop open / bad-order / start-less records. | Keeps every HPV record, flagged. **open** (3,997, 9%) = day-zero, no resolved (persistent noncompliance — kept). **bad_order** (377, 0.8%) = resolved < day-zero. **missing_start** (33) = no day-zero (23 have a resolved date, 10 have neither). |
| **H4** | **Dates carried AS PARSED — no plausibility screen.** | Screen implausible day-zero years here. | Source of truth stays faithful; day-zero year range is **218–2026** (a `218` and 164 `2026` records survive). Screening is a downstream / `hpv_active`-collapse decision, kept out of the spell table. |
| **H5** | **Facility-year mapping rule = R2** (interval overlap; open/bad-order conservatively closed on Dec-31 of the day-zero year). Feeds `hpv_active`. | R1 day-zero-year-only; R3 extend open spells to window end; R4 union>30-days. | Diagnostic 09 quantified each lever over 2005–2025: **R1→R2 (duration) +19,378 fac-yrs** (day-zero-year-only *halves* coverage — rejected); **R2→R3 (extend open spells) +11,546**, concentrated in recent years (an assumption about missing resolution dates — rejected as too strong); **R2→R4 (30-day threshold) −1,952** (minor). R2 chosen: faithful to spell duration without manufacturing an open-ended tail. R2 totals: **35,199 fac-yrs, 9,734 facilities**. *(User decision, 2026-07-20.)* |

### D.2 Verification (this session)

| check | result |
|---|---|
| 44,490 × 18; all names uppercase; row grain unique on (PGM_SYS_ID, ACTIVITY_ID, COMP_DETERMINATION_UID, day-zero) | ✓ |
| `SPELL_STATUS` exhaustive/exclusive; reconciles to diagnostic (closed 40,083 + bad_order 377 = the 40,460 day-zero+resolved) | ✓ |
| `SPELL_DAYS` non-NA **iff** `closed`, and ≥ 1 | ✓ |
| `DAYZERO_YEAR` NA **iff** `missing_start`; `RESOLVED_YEAR` NA = open (3,997) + missing_start-no-dates (10) | ✓ |
| every spell facility exists in the ds 0 universe (0 orphans) | ✓ |

## Part D2 · Dataset 2b — `hpv_active` (`04_hpv_active.R`)

Facility × year, the directly-usable HPV status flag — a deterministic R2 collapse of `hpv_spells`. Joins 1:1
to ds 0/1 (verified: identical key vectors).

**Shape (built & audited this session):**
```
5,863,431 rows | HPV_ACTIVE: 1 = 35,186 | 0 = 719,147 | NA = 5,109,098 | 9,734 ever-active facilities
```

| # | Decision | Alternative not taken | Why / data fact |
|---|---|---|---|
| **H6** | **Zero-vs-NA mirrors ds 0.** `1` if an R2 spell covers the year (**spell wins even where `ICIS_OBSERVED==0`** — the interval is direct evidence; 2,370 such fac-yrs); `0` if uncovered but `ICIS_OBSERVED==1`; `NA` if uncovered and unobserved. | Pure `0/1` (a spell covers or it doesn't). | Consistent with the layer's discipline: an unobserved year shouldn't assert "not in HPV status" any more than "0 inspections". Matches the panel. *(User decision, 2026-07-20 — reversed from an initial "pure 0/1".)* |
| **H7** | **Day-zero plausibility screen [1970, 2025] at the collapse** — a spell maps to years only if its day-zero year is in range. Excludes **165 of 44,457** mappable spells (implausible/unparseable day-zero). | No screen (H4 keeps the spell table faithful, but the collapse is where H4 said screening belongs). | ⚠ **Caught a real bug + garbage-propagation.** Record `CAMDAM1489` has day-zero `11-05-0218` (mistyped `2018`) → parses to **year 218** → an unscreened spell runs 218→2021 and spuriously flags 2005–2017 (+13 fac-yrs). Diagnostic 09's unscreened R2 (35,199) included those 13; the first `hpv_active` build got 35,186 **by accident** (a silent `col_date()` round-trip failure dropped the spell). The screen makes the exclusion **explicit and reported**; dates are now parsed with `ymd()` (consistent with diag 09) so nothing hides in a parse quirk. Net: **35,186 by design.** The other 164 screened spells are future `2026` day-zeros that start after the window and never overlap it anyway. |

### D2.1 Verification (this session)

| check | result |
|---|---|
| 5,863,431 × 3; grain unique; all uppercase; **1:1 join to ds 0** (identical keys) | ✓ |
| zero-vs-NA: no `0` in unobserved years; no `NA` in observed years; every `HPV_ACTIVE==1` has a covering spell | ✓ |
| spell-wins: 2,370 fac-yrs `HPV_ACTIVE==1` with `ICIS_OBSERVED==0` (expected) | ✓ |
| reconciles to diag 09 R2: 9,734 ever-active facilities; 35,186 = 35,199 − 13 screened | ✓ |

---

## Part E · Dataset 3 — `penalties` (`05_penalties.R`)

The action-level record behind ds 0's facility-year `PENALTY_AMOUNT` / `N_PENALTIES`. One row per formal action.

**Shape (built & audited this session):**
```
105,656 actions | 16 cols | 37,216 facilities | years 1972–2026 | 72,314 with penalty>0
```

### E.1 Coding decisions

| # | Decision | Alternative not taken | Why / data fact |
|---|---|---|---|
| **P1** | **Grain = one row per formal-action record; ALL rows kept, `dup>0` flagged not dropped.** | Dedup to distinct actions. | Layer convention (CC9/R3). 857 dup rows; event-distinct = 104,799. |
| **P2** | **Formal actions only.** | Pool informal too (as ds 0's enforcement does). | Only formal actions carry `PENALTY_AMOUNT`; informal has no penalty column. Penalties are the point of this dataset. |
| **P3** | **NOT window-restricted — all action years (1972–2026) kept.** | Clip to 2005–2025. | Six-dataset design pushes sample/window filters downstream; `YEAR` is provided so the user clips as needed. 67,082 of 105,656 actions fall in 2005–2025. |
| **P4** | **`PENALTY_AMOUNT` kept AS RECORDED per row (0 or positive, never `NA`); no zero-vs-NA discipline.** | Apply ds 0's observed/`NA` coding. | Every row is an observed action with a recorded amount — the observability question doesn't arise at action grain. `HAS_PENALTY` = amount>0 companion flag. |
| **P5** | **Multi-facility settlement structure EXPOSED, not resolved** — `ENF_IDENTIFIER` (settlement key), `N_SETTLEMENT_FACILITIES`, `IS_MULTI_FACILITY`; per-row penalty left faithful. | Deduplicate broadcast penalties, or split them across co-defendants. | ⚠ **588 settlements (0.6%) span >1 facility** (up to **117** co-defendants), each a separate row. The penalty is *usually* one value repeated (516/588) but **72 settlements carry DIFFERING per-facility amounts** — so it is **not** a clean broadcast, and neither "take one value" nor "sum" is universally right. Exposing the structure lets the user pick per analysis. **Do NOT sum `PENALTY_AMOUNT` across a settlement's facilities without a broadcast rule.** See `multi_facility_settlement_decision.md` §5: 552 of 588 (93.9%) span genuinely distinct FRS `REGISTRY_ID`s — this is not an ID-duplication artifact, only 36 settlements (6.1%, $29M) have all co-defendants on one `REGISTRY_ID`. |

### E.2 Verification (this session)

| check | result |
|---|---|
| 105,656 × 16; all uppercase; `HAS_PENALTY`/`IS_MULTI_FACILITY` consistent; `N_SETTLEMENT_FACILITIES` constant within `ENF_IDENTIFIER` | ✓ |
| `PENALTY_AMOUNT` ≥ 0, never `NA`; every action facility in the ds 0 universe (0 orphans) | ✓ |
| **reconciles to ds 0 exactly** — Σ `PENALTY_AMOUNT` over 2005–2025 actions = ds 0's observed `PENALTY_AMOUNT` total, **diff $0** | ✓ |

---

## Part F · Dataset 4 — `coordinates` (`06_coordinates.R`)

One row per facility: FRS lat/lon, derived county FIPS, and coordinate-vs-ICIS-county error diagnostics.
Reuses the panel spine's coordinate block + `coord_county_flag.R` helper, over the full universe.

**Shape (built & audited this session):**
```
279,211 facilities | 11 cols | 235,919 with coordinates (84.5%) | 234,524 county_fips | 2,839 gross errors (1.3% of checkable)
```

### F.1 Coding decisions

| # | Decision | Alternative not taken | Why / data fact |
|---|---|---|---|
| **C1** | **Coordinate source = FRS via `REGISTRY_ID`** (deduped to one row/`REGISTRY_ID`). No FRS match → `HAS_COORDINATE == 0`, `NA` lat/lon. | ICIS-native coords (none reliable). | 84.5% of facilities get a coordinate; the 15.5% gap is facilities with no `REGISTRY_ID` or no FRS row. |
| **C2** | **`COUNTY_FIPS` = point-in-polygon** of the coordinate into the county shapefile (EPSG:4326 → shapefile CRS). | Trust ICIS `COUNTY_NAME` text. | The shapefile is **CONUS + DC** — non-CONUS facilities (AK/HI/territories) resolve to `NA` `COUNTY_FIPS` even with a coordinate. Derived FIPS is new here (ds 0 carries only the ICIS county *name*). |
| **C3** | **Error diagnostics via the shared `flag_coord_county` helper** — `COORD_COUNTY_DIST_KM` (km from coordinate to ICIS-claimed county; 0 = in-county, NA = uncheckable) and `COORD_GROSS_ERROR` (1 iff checkable & >5 km). | Roll a separate check. | Identical logic to the panel spine, so results are comparable. **0 ≠ NA honored** — never asserts 0 for a facility whose county name couldn't be resolved. |
| **C4** | **Full 279,211 universe** (the spine computed this block for the 136,505 ever-active subset only). | Restrict to ever-active. | Consistent with the layer's full-universe rule; joins on `PGM_SYS_ID` to every facility-year dataset. |
| **C5** | **`ICIS_COUNTY_FIPS` = GEOID resolved from `(STATE, COUNTY_NAME)` text alone** (added 2026-07-22; same `flag_coord_county` helper as C3, its previously-unreturned `resolved_geoid`). `NA` when the name doesn't resolve to exactly one GEOID in this shapefile vintage. | Rely on `COUNTY_FIPS` (coordinate-derived) alone as the only FIPS field. | Needs no coordinate — pure function of the ICIS name — so coverage is wider than `COUNTY_FIPS`: set for **261,220 (93.6%)** of all 279,211 facilities vs. `COUNTY_FIPS`'s 235,759 (84.5%). Where both are set (224,921 facilities), they agree **97.3%** of the time (218,892/224,921) — matches the C3 match rate exactly, since both sides share the same resolution logic. Gives a lat/long-independent second check on county assignment, and a fallback FIPS where `COUNTY_FIPS` is `NA` for lack of a coordinate. |

### F.2 Verification (this session)

| check | result |
|---|---|
| 279,211 × 11; grain unique; all uppercase; `HAS_COORDINATE` / `COORD_GROSS_ERROR` logic consistent; `COUNTY_FIPS` only where a coordinate exists | ✓ |
| coordinate plausibility: 0 lat/lon out of range, 0 exact-(0,0); dist median 0 km, p99 7.7 km | ✓ |
| **consistency vs panel spine** — across all 136,505 shared facilities, **0 `coord_gross_error` disagreements** | ✓ |
| **`ICIS_COUNTY_FIPS` vs `COUNTY_FIPS` agreement** — 218,892/224,921 (97.3%) where both set; 261,220 (93.6%) of all facilities have `ICIS_COUNTY_FIPS` set (rebuilt 2026-07-22) | ✓ |

---

## Part G · Dataset 6 — `pipeline` (`07_pipeline.R`)

Facility × year, built from EPA ECHO's **CAA Compliance Pipeline** download
(`data/raw/PIPELINE_CAA_00_COMPLETE.csv`, added to this repo 2026-07-23; previously documented in
`docs/data_dictionary.md` as absent). Raw grain is one row per **violation**, optionally linked backward to
the evaluation (inspection) that found it and forward to the enforcement action it triggered.

**Value-added vs. datasets 0/2/3** (why this is worth a seventh file, not a restatement of what exists):

| Existing dataset | What it has | What `pipeline` adds |
|---|---|---|
| `regulatory` (ds 0) | inspection/violation/enforcement **counts**, no linkage between them | which evaluation *found* which violation, which violation *triggered* which enforcement action — a same-row causal chain no ICIS-Air table alone provides |
| `hpv_spells` (ds 2) | **HPV only** (FRV excluded by H1) | the **FRV population** (40,708 in-window rows, 2.4× the HPV count) — a violation tier invisible elsewhere in this layer |
| `penalties` (ds 3) | formal-action penalties, action-grain | `EA_PENALTY_AMT` attributable to the *specific violation* that caused it — see the caveat at G4 below |
| none | — | `MEAN_EVAL_TO_VIOL_LAG_DAYS` / `MEAN_VIOL_TO_EA_LAG_DAYS` — "pipeline speed" measures nothing else in the layer computes |

**Shape (built & audited this session):**
```
5,863,431 rows | 14 cols | 279,211 facilities × 21 years | 31,796 observed facility-years (0.5%)
18,529 ever-observed facilities | 17,130 HPV + 40,708 FRV = 57,838 in-window violations
```

### G.1 Coding decisions

| # | Decision | Alternative not taken | Why / data fact |
|---|---|---|---|
| **PL1** | **7,193 of 66,655 raw rows are EPA-system-generated placeholders, not real violations**, identified by blank `VIOL_START_DATE` + `VIOL_ACTIVITY_ID` prefixed `9906`/`9913` + `VIOL_TYPE` blank or `"Linked to Viol. Below"` — matches the dictionary's note that these IDs "did not have an actual violation activity identification number." | Keep them as zero-duration/degenerate rows. | They have no date to anchor a year, so they are structurally excluded (asserted in-build) rather than filtered by a fragile heuristic. After exclusion, `VIOL_TYPE` partitions **exactly** into {HPV, FRV} — asserted. |
| **PL2** | **Year anchor = `VIOL_START_DATE`**, not the cleaned asset's own `date` column (`SORT_DATE`). | Use `SORT_DATE`/`date` (already parsed in `data/processed/pipeline.csv.gz`). | `SORT_DATE` is EPA's own "latest stage reached" display date — verified (0 exceptions across 66,602 non-blank rows) to equal `EA_DATE` if an EA is linked, else `VIOL_START_DATE`, else `EVAL_DATE`. Using it would misdate a violation into a later year purely because it was eventually enforced. |
| **PL3** | **Universe = the same 279,211-facility × 2005–2025 rectangle as ds 0/1/2b** (G3/G4), so `pipeline` joins **1:1** to `regulatory.csv.gz` on `(PGM_SYS_ID, YEAR)` (verified: identical key vectors). | Build only over the 20,251 facilities the raw file actually contains. | Consistent with the layer's full-universe convention; 20,249 of those 20,251 (99.99%) already match the ICIS universe, so the cost of the full rectangle is 2 orphan facilities, not a coverage loss. |
| **PL4** | **`EA_PENALTY_AMT_SUM` is exposed per facility-year but flagged — do NOT sum alongside `penalties.csv.gz`'s `PENALTY_AMOUNT` without a dedup rule.** | Reconcile the two now. | Same P5 pattern as ds 3: both very likely trace to the same underlying enforcement-action dollars. Reconciling requires matching pipeline's `EA_ACTIVITY_ID`/`EA_FEA_ACTIVITY_ID` against ds 3's `ENF_IDENTIFIER`, which is deliberately left undone here — exposing the structure lets the user pick per analysis, as ds 3 already does for multi-facility settlements. |
| **PL5** | **`N_VIOL_SELF_DISCLOSED` guarded against `NA` propagation** — `EVAL_TYPE_DESC` is blank (parses to `NA`) on the ~46% of rows with no linked evaluation, and an unguarded `== "Self-Disclosure"` comparison produces `NA`, which then poisons `sum()` for the whole facility-year group under the zero-vs-NA rule. Fixed by gating on `has_eval & !is.na(EVAL_TYPE_DESC)` first. | Trust `sum(x == "...")` directly. | Caught by an independent post-build Python check (not the in-build `stopifnot`s, which didn't originally cover this column) — added two more invariants (`N_VIOL_SELF_DISCLOSED`, `N_VIOL_WITH_EVAL`/`N_VIOL_WITH_EA` never `NA` on an observed row) to guard against the same class of bug recurring. |
| **PL6** | **`REGISTRY_ID` joined from `facilities.csv.gz`, not read from the raw file's own `REGISTRY_ID` column** (which is present natively, unlike most other sources in this layer). | Trust the pipeline file's own `REGISTRY_ID`. | Matches G4 exactly and avoids a second, possibly stale, FRS snapshot disagreeing with the rest of the layer. |

**Deliberately deferred** (documented as scope, not silently missing): full `EVAL_TYPE_DESC`/`EA_TYPE`
category breakdowns beyond self-disclosure; any dedup reconciliation of `EA_PENALTY_AMT_SUM` against ds 3
(PL4).

### G.2 Verification (this session)

| check | result |
|---|---|
| 5,863,431 × 14; grain `PGM_SYS_ID × YEAR` unique; rectangle complete (279,211 × 21); all names uppercase | ✓ |
| **1:1 join to `regulatory.csv.gz`** — identical key vectors | ✓ |
| zero-vs-NA: `PIPELINE_OBSERVED==1 ⟺` every count column non-`NA`; `==0 ⟺` every count `NA` | ✓ |
| `N_VIOL_HPV + N_VIOL_FRV == N_VIOL_PIPELINE` on every observed row | ✓ |
| `N_VIOL_WITH_EA_PENALTY > 0 ⟺ EA_PENALTY_AMT_SUM > 0` on every observed row | ✓ |
| placeholder rows (7,193) structurally absent from every facility-year (no `VIOL_START_DATE` → no year) | ✓ |
| independent Python re-derivation: HPV 17,130 + FRV 40,708 = 57,838 (matches a hand count from raw `VIOL_START_DATE` year distribution, 2005–2025 window) | ✓ |

**Profile**: `briefs/datasets/pipeline_profile.md` (built by `code/diagnostics/16_pipeline_profile.R`) —
linkage rates, `EVAL_TYPE_DESC`/`EA_TYPE` breakdowns, lag-day distributions, and the eval-linkage coverage
cliff before 2015.

---

## Dataset 5 · planned (not yet built)

Designs from `00_parameters.R`; decisions recorded as each is built. Every builder routes through
`write_dataset()` so the G2 uppercase convention holds layer-wide and joins on `PGM_SYS_ID`/`YEAR` line up.
- **ds 0 + ds 1 are a pair** — ds 1's `operating` / `WAYBACK_OBSERVED` is what makes ds 0's 87% all-`NA`
  core interpretable (which `NA`s are "not operating" vs "operating but no ICIS event"). Read together.
