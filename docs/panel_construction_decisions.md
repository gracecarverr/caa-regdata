# Asset & Panel Construction Decisions


---

## Part A · every asset

| # | Decision | Alternative not taken | Why / data issue |
|---|---|---|---|
| **CC1** | **Facility key = `PGM_SYS_ID`** (ICIS-Air regulated-facility id). `REGISTRY_ID` carried on the spine for cross-system joins. | Key on `REGISTRY_ID` (physical site) or AFS id. | "Facility" is ambiguous — many `PGM_SYS_ID`→one `REGISTRY_ID`; regulation attaches to the permit `[D1, D3]`. |
| **CC2** | **Assets keep ALL dated events; the window is applied at panel build** (`YEARS = 2005:2025`, `00_setup.R:8`). | Bake the window into the assets. | Keeps assets reusable for any window; `build_panel(years=)` filters `[C6]`. |
| **CC3** | **Dates parsed with `lubridate::mdy(quiet=TRUE)`** — accepts both `mm-dd-yyyy` and `mm/dd/yyyy`. | A single-format parser. | The same column mixes both separators; naive parsing drops half the rows `[C7]`. |
| **CC4** | **Undated events are dropped** (`filter(!is.na(year))`). | Impute a date; keep with `NA` year. | An event with no parseable date can't be placed in a panel year. This is where the 9.2% dateless violations `[C1]`, out-of-range years `[C4]`, and blank cert dates `[C5]` exit — **dropped, never imputed**, and the count is reported. |
| **CC5** | **Blank `PGM_SYS_ID` dropped.** | Keep. | Unkeyable rows. |
| **CC7** | **Multi-valued code fields kept as delimited strings** (`program`, `pollutant`), not split. | Explode to one row per code. | Splitting would re-inflate the grain; substring matching where needed `[B3]`. |
| **CC8** | **Assets materialized to disk** — `facilities.csv` + `attainment.csv` tracked; event assets `.csv.gz` git-ignored, rebuilt from code. | Rebuild in memory each run. | Durable, merge-ready building blocks; large ones stay out of git. |
| **CC9** | **NO event deduplication — every raw row is kept and *flagged*, never dropped** (`add_dup_flags`, `00_setup.R`). Each event asset carries `dup` (occurrence index within its event-id group; `0` = first row, `1,2,…` = repeats) and `dup_exact` (`1` if byte-identical on kept columns to an earlier row). `filter(dup == 0)` reproduces the former `distinct(id, .keep_all=TRUE)` asset **exactly**. | Drop duplicates at the asset (the old `distinct`); or keep all rows with no flag. | Reversibility + transparency: dropping is lossy and hides how much duplication exists; keeping-but-blind loses the event count. Flags give **both** — raw and event-level counts are each one filter away, and duplication is auditable in-place. `dup_exact` separates pure artifact copies from same-id rows carrying new `program`/`pollutant` detail (the ID-vs-whole-row distinction in D-E1). Facility-**spine** dedup (F2/F3/N5, one row per facility) is unaffected — that's definitional, not event dedup. |

---

## Part B · Per-asset decisions

**Duplication by source** (raw rows vs. distinct event-id vs. distinct whole-row, verified this session). `dup==0` counts the middle column; `n_<measure>_raw` (certs, enforcement) counts the first. Only **certs** and **informal enforcement** are materially duplicated:

| source | raw rows | distinct event-id (`dup==0`) | distinct whole-row | duplicate rows |
|---|---|---|---|---|
| inspections (`FCES_PCES`) | 1,802,044 | 1,801,418 | 1,801,621 | **~0%** |
| violations (`VIOLATION_HISTORY`) | 91,842 | 91,842 | 91,842 | **0%** |
| formal enforcement | 105,615 | 104,763 | 105,615 | ~1% |
| informal enforcement | 336,073 | 174,494 | 174,494 | **48%** |
| certs (`TITLEV_CERTS`) | 2,533,455 | 481,219 | 491,113 | **81%** |
| stack tests (`STACK_TESTS`) | 646,327 | 646,327 | 646,327 | 0% |

For certs, `dup>0` (2,052,236) exceeds `dup_exact` (2,042,342) by **9,894** — same-`ACTIVITY_ID` rows that differ on a kept column (= 491,113 − 481,219), i.e. sub-detail rows, not pure artifacts.

### B.1 `facilities` — the spine (`assets/facilities.R`)
The universe definition + the merge spine + the source of all sample filters. Runs **after** the four event assets.

| # | Decision | Alternative | Why / data issue |
|---|---|---|---|
| **F1** | **Universe = "ever-active in window"** — `PGM_SYS_ID` appearing in ≥1 event asset with an event dated in `YEARS` → **133,703** facilities (`facilities.R:14`). | All 279k `ICIS-AIR_FACILITIES` rows regardless of activity. | Ties the universe to observed regulatory activity; but classification alone includes dormant units `[G2]` and there are no entry/exit dates `[A3]`. |
| **F2** | **Attributes = current snapshot, 1 row/facility** (`distinct(PGM_SYS_ID, .keep_all=TRUE)`, keeps first). | Reconstruct historical class/industry. | ICIS ships only the current snapshot — class, operating status, NAICS/SIC are time-invariant here `[A1, A2, A5]`. |
| **F3** | **Coordinates from FRS via `REGISTRY_ID`** (`distinct(REGISTRY_ID)`, first lat/long, numeric). | Use ICIS address geocoding. | FRS is the physical-site registry. Facilities with no FRS match / bad coords → `NA` → **unplaceable** (no county, no attainment). |
| **F5** | **33-column schema** — keys (`PGM_SYS_ID`, `REGISTRY_ID`), geography (address, `county_fips`, lat/long, state, region), industry (NAICS/SIC), `AIR_POLLUTANT_CLASS_DESC`, `AIR_OPERATING_STATUS_DESC`, plus the two static attribute profiles below (F6). | Minimal keys only. | Carries all sample-filter fields + the establishment-linkage keys for the future Census/operating merge (see open-questions D-A2). |
| **F6** | **Two static "ever-*" attribute profiles**, one row/facility, matched from the ICIS code tables: (a) *pollutant profile* `emits_voc/pm/co/nox/so2/hap` (from `ICIS-AIR_POLLUTANTS`, pre-existing); (b) *program-enrollment profile* `prog_sip/titlev/nsps/mact/neshap/fesop/nsr/psd` + `n_programs` (from `ICIS-AIR_PROGRAMS`, **new**). Each `prog_*` = 1 if the facility is **ever** enrolled in that program (exact `PROGRAM_CODE` match; `prog_nsps` pools major `CAANSPS` + non-major `CAANSPSM`); `n_programs` counts **all** distinct codes incl. minor ones. Missing → `0` (coalesced, like the pollutant profile). | (i) A single categorical `program_type` column; (ii) time-varying enrollment via `BEGIN_DATE`. | Enrollment is a **set**, not one value — median **2**, max **15** programs/facility — so a lone categorical can't represent it without exploding the panel grain or a machine-hostile delimited string; **indicators encode set membership at the facility-year grain** and drop straight into regressions as non-exclusive dummies. **Static** because `ICIS-AIR_PROGRAMS` has a `BEGIN_DATE` but **no end date** (only a current operating-status snapshot) → de-enrollment is unidentified, so a time-varying flag would be only partially identified (D-A2/operating-status merge). Area-source GACT (`CAAGACTM`) is deliberately **not** folded into `prog_mact`. **New pipeline dependency:** `facilities.csv` (and every panel) now reads `ICIS-AIR_PROGRAMS.csv` — previously used only in `data_docs/`. Enrollment rates: SIP 90.1%, Title V 19.0%, NSPS 30.8%, MACT 29.0%, FESOP 8.0%, NSR 5.4%, PSD 4.1%, NESHAP 2.4%; `n_programs=0` for **3,236** (2.4%) active facilities with no PROGRAMS record. |

### B.2 `inspections` (`assets/inspections.R`) — source `FCES_PCES`
| # | Decision | Why / data issue |
|---|---|---|
| **I1** | **Pool FCEs and PCEs** into "inspections"; `type` (`ACTIVITY_TYPE_DESC`) preserves full-vs-partial. | One compliance-monitoring measure; detail retained for slicing. |
| **I2** | **Date = `ACTUAL_END_DATE`** (evaluation end). | The completion date of the evaluation. |
| **I3** | **Event id = `ACTIVITY_ID`; all rows kept, `dup`/`dup_exact` flagged** (CC9). | ~0% duplicated — the flag is a no-op here, kept for schema consistency. |
| **I4** | Keep `monitor_type`, `agency` (`STATE_EPA_FLAG` E/S/L). | Who did it / how — for downstream slicing. |

### B.3 `violations` (`assets/violations.R`) — source `VIOLATION_HISTORY`
| # | Decision | Alternative | Why / data issue |
|---|---|---|---|
| **V1** | **Date = first non-blank of (`EARLIEST_FRV_DETERM_DATE`, `HPV_DAYZERO_DATE`)** then `mdy` (`violations.R:16`, via `first_nonblank`). Covers **90.8%**; the 9.2% undated are dropped. | FRV only; DSCV/NFTC fallback; HPV-resolved. | Best-populated *determination* date `[C1]`. **Verified this session:** DSCV/NFTC recover **0** of the dateless (they never fill when FRV & day-zero are both blank); `DSCV` = "discovery" but only 38% populated. See open-questions **D-B1/D-B2**. |
| **V2** | **`hpv` flag = `HPV_DAYZERO_DATE` non-blank.** | Use an explicit HPV type code. | Day-zero presence = entered HPV status. |
| **V3** | **Event id = `COMP_DETERMINATION_UID`; all rows kept, `dup`/`dup_exact` flagged** (CC9). | — | 0% duplicated here — no-op flag, kept for schema consistency. |
| **V4** | Keep `program` (`PROGRAM_DESCS`), `pollutant` (`POLLUTANT_DESCS`), `agency`. | — | Multi-valued program/pollutant kept as-is `[B3]`. |
| **V5** | **Early-year sparsity left as-is** (header note). | Coverage-adjust. | Coverage ramps up over time — a reporting artifact, *not* a real decline `[C2]`; documented, not corrected. |
| **V6** | **Retain the HPV spell endpoints as parsed Dates** — `hpv_dayzero_date` (clock start) + `hpv_resolved_date` (close; `NA` if unresolved). `hpv_resolved_date` was previously exported as a raw `mdy` string; now parsed at the asset layer. | Keep only the `hpv` flag / the recorded-year count. | The interval `[dayzero, resolved]` is what `build_panel` needs to derive **time in HPV status** (P8). Parsing here keeps the asset reusable; verified **no downstream consumer** read the former string (the data-dictionary/explore scripts read the raw file). **44,457** HPV spells — **40,460** resolved, **3,997** open, **377** with `resolved < dayzero`. |

### B.4 `enforcement` (`assets/enforcement.R`) — sources `FORMAL_ACTIONS` + `INFORMAL_ACTIONS`
| # | Decision | Alternative | Why / data issue |
|---|---|---|---|
| **E1** | **Pool formal + informal into one asset, tagged `kind`.** | Two separate assets. | One enforcement measure; `kind` preserves the split (informal ≈ 3× formal). |
| **E2** | **Date: formal = `SETTLEMENT_ENTERED_DATE`, informal = `ACHIEVED_DATE`.** | Filing date for formal. | Settlement date can lag filing by months/years `[C3]` — a known timing mismatch. |
| **E3** | **`penalty = parse_number(PENALTY_AMOUNT)`, FORMAL only** (`any_of()` makes the column optional; informal → `NA`). | Impute informal penalties. | Informal actions carry no penalty field. |
| **E4** | **Event id = (`kind`, `ENF_IDENTIFIER`) per facility; all rows kept, `dup`/`dup_exact` flagged** (CC9). Informal ≈ **48%** duplicate rows, formal ≈ 1%. | Drop duplicates (old `distinct`); sum penalties across raw rows. | Penalties must be summed over `dup==0` only — a multi-facility settlement **repeats one penalty across every co-defendant**, and raw rows repeat it again `[F2]`. build_panel's penalty block filters `dup==0` (verified this session). |

### B.5 `certs` (`assets/certs.R`) — source `TITLEV_CERTS`
| # | Decision | Why / data issue |
|---|---|---|
| **T1** | **Event id = `ACTIVITY_ID`; all ~5 rows/cert kept, `dup`/`dup_exact` flagged** (CC9). | `TITLEV_CERTS` is **81%** duplicate rows (one raw row per program/pollutant). `n_certs` counts `dup==0` (481,219 certs); `n_certs_raw` counts all rows (2.53M). The distinction is now explicit in the panel, not baked in. |
| **T2** | Date = `ACTUAL_END_DATE`; keep `deviation_flag` (`FACILITY_RPT_DEVIATION_FLAG`), `agency`. | The certification date + self-reported deviation. |
| **T3** | **Coverage caveat (documented, not fixed):** only ~62%/yr of "Major" facilities show a cert. | Class-major ≠ Title V annual certifier `[F4]`; don't assume a cert per major. |

### B.6 `attainment` (`assets/attainment.R`) — Green Book shapefiles + Wayback
| # | Decision | Alternative | Why / data issue |
|---|---|---|---|
| **AT1** | **PM2.5 (2012 std) ONLY, 2016–2025 ONLY** — deliberately narrow (3,805 facilities / 8 areas). | All pollutants, all years. | Wayback snapshot coverage; ozone/SO₂/lead not built yet. |
| **AT2** | **Time-varying, rebuilt from stacked Green Book Wayback status DBFs + NAA shapefiles.** | County-level `phistory` (all pollutants/years). | Maintenance-aware & sub-county; the `phistory` county version is preserved in `archive/panel_funnel_v1/04_attach_attainment.R`. |
| **AT3** | **Sub-county point-in-polygon** (`st_within`) places a facility by its coordinate → `composid`. | County FIPS join. | A NAA boundary is sub-county; coordinate placement is exact. Facilities without coords are absent. |
| **AT4** | **Maintenance-aware: `status` = N (nonattainment) / M (maintenance);** absent = attainment. | Binary in/out. | Redesignation matters for the research question. |
| **AT5** | **2023 snapshot missing → carried forward from 2022, flagged `imputed`.** | Drop 2023. | Preserves the panel year; the imputation is explicit. |

---

## Part C · Panel-construction decisions (`build_panel.R`)
These are the levers a panel-builder sets. **Implemented defaults are marked ✔; open choices point to `panel_open_questions.md`.**

### Panel column inventory
A **default** `build_panel(outcomes = c("inspections","violations","enforcement","certs"))` → **46 columns**; a **full** `build_panel(detail = TRUE, treatment = "attainment")` → **81 columns**. The families:

| Family | Columns | When | Source |
|---|---|---|---|
| **Keys** | `PGM_SYS_ID`, `year` | always | spine × window |
| **Core counts** | `n_inspections`, `n_violations`, `n_enforcement`, `n_certs` (event-level, `dup==0`) | per requested outcome | event assets (P2) |
| **Raw counts** | `n_certs_raw`, `n_enforcement_raw` (all rows, incl. duplicates) | certs / enforcement requested | event assets (P2, CC9) |
| **Any-flags** | `any_inspections`, `any_violations`, `any_enforcement`, `any_certs` | per requested outcome | derived, NA-safe (P5) |
| **HPV status** | `hpv_active`, `hpv_active_1mo` | when `violations` requested | violations spell (P8) |
| **Facility attributes** | `REGISTRY_ID`, `FACILITY_NAME`, address/`county_fips`/lat-long/`STATE`/`EPA_REGION`, `NAICS_CODES`/`SIC_CODES`, `FACILITY_TYPE_CODE`/`facility_type`, `AIR_POLLUTANT_CLASS_DESC`, `AIR_OPERATING_STATUS_DESC` | always | spine (F2–F5) |
| **Pollutant profile** | `emits_voc/pm/co/nox/so2/hap` | always | spine (F6) |
| **Program enrollment** | `prog_sip/titlev/nsps/mact/neshap/fesop/nsr/psd`, `n_programs` | always | spine (F6) |
| **Detail breakdowns** | inspections `n_fce/n_pce/n_insp_{epa,state,local}`; violations `n_hpv/n_frv/n_viol_{sip,titlev,nsps,mact,fesop,epa,state,local}`; enforcement `n_formal/n_informal/n_{nov,warning_letter,admin_order,penalty_action,civil_judicial,admin_np}/n_enf_{epa,state,local}`; certs `n_certs_deviation`; stack tests `n_stack_tests/n_stack_pass/n_stack_fail` | `detail = TRUE` | event assets (`DETAIL`, `00_setup.R`) |
| **Penalty** | `penalty_amount` (formal only; blank/`0`→`NA`) | `detail = TRUE` | enforcement (E3/E4) |
| **Treatment** | `pm25_status`, `pm25_area`, `naa_pm25_2012`, `any_naa` | `treatment = "attainment"` | attainment (P6) |


| # | Decision | Status | Notes |
|---|---|---|---|
| **P1** | **Sample filters** — `class`, `state`, `naics`, `sic` (NAICS/SIC anchored-regex, **OR'd**), and **`active_years`** = keep facilities with ≥1 regulatory action in *every* listed year (activity-based "operating" proxy, uses all four event assets). | ✔ lever | Class/NAICS/SIC operate on the **current-snapshot** attributes → membership time-invariant `[A1, A5]`; `active_years` selects on activity itself (a "continuously observed" subsample, not random — D-A2). |
| **P2** | **Outcomes → facility×year counts, measures kept separate**; `any_activity` = union. Canonical `n_<measure>` counts **event-level** rows (`dup==0`); the substantial-dup measures also get an all-row count `n_certs_raw`, `n_enforcement_raw` (CC9). Detail breakdowns are computed on `dup==0`, so partitions still sum to `n_<measure>`. | ✔ | No dedup upstream (CC9); the panel exposes both views. `any_<measure>` is identical either way (≥1 raw row ⇔ ≥1 event). Summing across measures would double-count one interaction `[B2]`. |
| **P3** | **Zero semantics: within an *observed* facility-year, a measure with no event = `0` (true zero)**; an *unobserved* facility-year is absent (or `NA` if balanced) — **never `0`**. | ✔ core | The load-bearing semantic. `0` = observed & none; `NA`/absent = not observed. Open: **D-A1**. |
| **P4** | **`balance=TRUE` → full `PGM_SYS_ID × year` rectangle (unobserved cells `NA`); `FALSE` → observed rows only.** The shipped **funnel presets are built `balance=TRUE`** (the function default stays `FALSE`). | ✔ presets use `TRUE` | A facility-year with no action = `NA` (can't assert a zero); within an active year, absent measures = `0`. Rectangular frame is what the **Census / operating-status merge** needs (**D-A1/D-A2**). |
| **P5** | **`any_<measure>` flags are NA-safe** (`NA` where the count is `NA`). | ✔ | Consistent with P3/P4. |
| **P6** | **`treatment="attainment"` join** — PM2.5 facility×year; `cover = 2016:2025`, `placeable = has coords`; `naa_pm25_2012` = `NA` outside coverage/placeable, else `1` if `N` else `0`; `pm25_status` keeps N/M; `any_naa`. | ✔ lever | Coverage caveats inherited from AT1–AT5. |
| **P7** | **Attributes joined from the spine; output `PGM_SYS_ID, year` first;** `write_as` → `panels/<name>.csv.gz`. | ✔ | The spine's two static profiles (F6) — `emits_*`, `prog_*`, `n_programs` — ride along here automatically; no per-year logic. |
| **P8** | **HPV-status flags (interval-based)** — attached whenever `"violations"` ∈ `outcomes`. `hpv_active` = in High-Priority-Violation status during **any** part of the year; `hpv_active_1mo` = in HPV status **> 30 days** of the year. Built from the spell `[hpv_dayzero_date, spell_end]` (V6): `spell_end` = `hpv_resolved_date` when resolved & valid, else (open **or** `resolved < dayzero`) **day-zero-year-only** (= Dec 31 of the day-zero year). Per facility-year the **union** of overlapping spells is taken; a spell-year is `1` **regardless of other activity** and is never masked; other facility-years are `0` (`NA` only for unobserved, no-spell cells when `balance=TRUE`). | ✔ lever | **Distinct from the recorded-year count `n_hpv`** (detail): `n_hpv` tags a determination to the single year it was *recorded*, but **69%** of resolved spells span >1 calendar year, so a status question needs the interval. Union (not sum) prevents concurrent spells double-counting days; **>30 days** operationalizes "more than a month." **Open-spell rule = day-zero-year-only** (your decision): conservative — an unresolved HPV is asserted only in its start year rather than assumed ongoing to panel-end, avoiding fabricated multi-year status from a missing close date. **Never-mask rule** is the point of an interval flag — HPV status carries across years with no new determination (a 2012→2014 spell reads `1` in 2013 where `any_violations` is `NA`). Coverage caveat inherited from V5. Universe 2005–2025: **32,815** facility-years `hpv_active` (vs Σ`n_hpv` = 24,586), **31,002** `hpv_active_1mo`. |

### Presets — the six shipped panels (two families, both `balance=TRUE`)
`presets/funnel_2005_2025_balanced.R` and `presets/funnel_2015_2025_continuous.R`.

| # | Decision | Notes |
|---|---|---|
| **PR1** | **Three funnel levels** — `universe` (all ever-active, 133,703) → `major_synmin` (`class ∈ {Major, Synthetic Minor Emissions}`, 45,398) → `electric_attainment` (+ `NAICS 2211` OR `SIC 4911`, 3,240; `treatment="attainment"`). | The NAICS/SIC-`OR` admits 223 SIC-only cases (98 unclassified-NAICS kept, ~125 non-electric) 🔎 — open **D-C1**. |
| **PR2** | **`_continuous_2015_2025` family** — the same three levels restricted to facilities active in **every** year 2015–2025, window 2015–2025. | Counts: universe 11,018 · major/synmin 10,224 · electric 1,321. Selects on the outcome (D-A2); no `NA` cells by construction. |
| **PR3** | `treatment="attainment"` on **electric only**; universe & major/synmin carry no treatment. | Mirrors the funnel; trivial to add to all three. |

### Funnel — facility counts, step to step
Each level narrows the sample; each `_continuous_2015_2025` variant applies the same filters **plus** "active in every year 2015–2025."

| step | balanced (2005–2025) | Δ from prev level | continuous (every yr 2015–2025) | Δ from prev level |
|---|---|---|---|---|
| `universe` | 133,703 | — | 11,018 | — |
| → `major_synmin` | 45,398 | **−88,305** (34% kept) | 10,224 | **−794** (93% kept) |
| → `electric_attainment` | 3,240 | **−42,158** (7.1% kept) | 1,321 | **−8,903** (13% kept) |

- **Across the funnel (balanced):** the class filter removes ~⅔ (133,703 → 45,398), then the electric NAICS/SIC filter removes ~93% of what remains (45,398 → 3,240).
- **Balanced → continuous, per level** (adding "active every year 2015–2025"): universe **−122,685** (8.2% kept) · major/synmin **−35,174** (22.5%) · electric **−1,919** (40.8%). Continuity retention rises with facility size; the "every year" bar drops far more than window turnover (of the 80,919 universe facilities active ≥1 yr in 2015–2025, only 11,018 are active all 11). Selection-on-outcome caveat: `panel_open_questions.md` §1.6 / D-A2.

### Panel activity snapshots (non-continuous, balanced 2005–2025)

| panel | facilities | rows | observed fac-yrs (≥1 action) |
|---|---|---|---|
| `universe` | 133,703 | 2,807,763 | 730,768 (26%) |
| `major_synmin` | 45,398 | 953,358 | 451,787 (47%) |
| `electric_attainment` | 3,240 | 68,040 | 44,919 (66%) |

Share of observed facility-years with ≥1 event (total events in parentheses), by measure:

| measure | universe | major_synmin | electric |
|---|---|---|---|
| inspections | 85% (1,259,617) | 83% (899,719) | 81% (124,188) |
| certs | 36% (432,469) | 54% (397,309) | 77% (58,622) |
| enforcement | 15% (172,026) | 15% (120,558) | 11% (9,309) |
| violations | 7% (69,806) | 9% (56,711) | 7% (4,596) |

**Patterns:** observed-year coverage rises down the funnel (26% → 47% → 66%); **certs concentrate in majors/electric** (36% → 77%, as Title V binds the larger sources); inspections are frequent everywhere (~81–85%) and *intensify* (mean 1.72 → 1.99 → 2.76 per observed year); violations/enforcement stay rare (~7–15%). Electric-specific: **126 facilities ever in a PM2.5 NAA / 1,162 nonattainment facility-years** (2016–2025); 73% Major, 27% Synthetic Minor; 18% "Permanently Closed" in the current snapshot `[G2]`.

### Panel activity snapshots (continuous — active every year 2015–2025)
The `_continuous_2015_2025` panels require ≥1 action in **every** year 2015–2025, so they are **fully observed by construction — 0 NA cells** (window = 11 years, not 21).

| panel | facilities | rows | observed fac-yrs |
|---|---|---|---|
| `universe_continuous_2015_2025` | 11,018 | 121,198 | 100% (0 NA) |
| `major_synmin_continuous_2015_2025` | 10,224 | 112,464 | 100% (0 NA) |
| `electric_attainment_continuous_2015_2025` | 1,321 | 14,531 | 100% (0 NA) |

Share of facility-years with ≥1 event (total events in parentheses), by measure:

| measure | universe | major_synmin | electric |
|---|---|---|---|
| inspections | 77% (266,661) | 76% (248,278) | 78% (40,535) |
| certs | 75% (148,632) | 79% (145,783) | 88% (23,283) |
| enforcement | 14% (36,742) | 15% (35,401) | 10% (2,634) |
| violations | 12% (23,393) | 12% (22,717) | 9% (1,855) |

**Note vs non-continuous:** every facility here is active *every* year (via some measure), yet only ~76–78% of facility-years carry an *inspection* — a "continuously active" year can be, say, a cert-only or violation-only year. Certs again concentrate in electric (88%). The continuity filter selects on the outcome (`panel_open_questions.md` §1.6 / D-A2).

### Build order & reproducibility (`run_all.R`)
- **Order:** four event assets → `facilities` (reads them for the active set) → `attainment` → presets. Package check up front; `sessionInfo()` logged to `data_docs/output/sessionInfo.txt`.
- **No stochastic step** — point-in-polygon and the `dup`/`dup_exact` flagging are deterministic (row order = file order), so no seed is required.

---

## Part D · Data issues & nuances the pipeline touches

**Handled in the assets (no action needed downstream):**
- Row-grain double-counting `[B1]` → all rows kept + `dup` flag; canonical counts use `dup==0` (CC9). Two-format dates `[C7]` → `mdy` (CC3). Multi-facility penalty broadcast `[F2]` → sum penalties over `dup==0` (E4). Out-of-range/undated events `[C4,C5]` → dropped (CC4).

**Carried as documented caveats (the analyst must remember):**
- Snapshot class/industry/operating status applied to all years `[A1, A2, A5]` (F2, P1). No facility entry/exit → ambiguous zeros `[A3]` (P3, P4). Violation date-rule choice moves counts `[C1]` (V1). Early-year violation sparsity is an artifact `[C2]` (V5). Formal-action settlement-date lag `[C3]` (E2). Cert under-coverage of majors `[F4]` (T3). Right-truncation of 2025 `[C6]` (CC2). Attainment is PM2.5-only, 2016–2025 (AT1). HPV status inherits the early-year violation-coverage ramp (P8/V5); program enrollment is ever-enrolled and static (F6, N7).

**Nuances worth knowing (subtle, not in the matrix):**
- **N1 — no rows are dropped (CC9); `dup==0` marks the first row of each event id.** When an event id spans several raw rows (e.g. a violation across multiple `program`/`pollutant` values, or a cert's ~5 program/pollutant rows), every row is retained; `dup==0` is the first (its descriptive columns match the old asset), `dup>0` the rest, and `dup_exact` says whether a repeat is byte-identical or carries new sub-detail. Event-level work filters `dup==0`; the multi-valued detail that the old dedup discarded is now recoverable from the `dup>0` rows.
- **N2 — the spine's active-window is hard-coded to `YEARS` (2005–2025)** in `facilities.R`, independent of `build_panel(years=)`. Building a panel for a *wider* window would still only see facilities active in 2005–2025; widen both if needed.
- **N3 — "first non-blank" ≠ "first parseable"** (`first_nonblank`): a non-blank-but-malformed `FRV` date would be taken and the good `HPV` fallback skipped. Currently 0 unparseable, so no effect — a latent fragility (open-questions D-B5).
- **N4 — unplaceable facilities cascade:** no FRS coordinate → no `county_fips` (F4) *and* no attainment placement (AT3). Coordinate coverage is the gate for all geography-based joins.
- **N5 — FRS coordinate & facility-attribute dedup keep the first record** (`distinct(REGISTRY_ID)`, `distinct(PGM_SYS_ID)`); a site with multiple coordinate records or a facility with multiple attribute rows silently takes the first.
- **N6 — HPV status ≠ HPV count, and open-spell handling is conservative.** `hpv_active`/`hpv_active_1mo` (interval, ongoing status) and `n_hpv` (recorded-year count) answer different questions and will not agree year-to-year (P8). Open spells (no resolution) and `resolved < dayzero` rows are treated **day-zero-year-only**, so an unresolved HPV contributes status to *one* year only — deliberately understating rather than fabricating multi-year status. The two `hpv_resolved_date`/`hpv_dayzero_date` junk dates (3-digit years) fail to parse and fall through the same NA-guards (dropped / treated as open).
- **N7 — `prog_*`/`n_programs = 0` means "no enrollment record," not "confirmed not enrolled."** Missing PROGRAMS rows coalesce to `0` (like `emits_*`); 3,236 active facilities have no record at all. And because these are **ever-enrolled** flags with no end date, they cannot date *when* a facility came under a program — use with care in any timing/event-study design (F6).

---

## Part E · Decisions still open
For the choices *not yet settled* — balance vs unbalanced (D-A1), operating indicator / Census merge (D-A2), the violation date rule (D-B1/B2), the electric definition (D-C1), whether to add emissions/penalties/covariates (D-D2–D4), and verification items (D-E1–E3) — see [`panel_open_questions.md`](panel_open_questions.md).
