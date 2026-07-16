# Asset & Panel Construction Decisions

> ⚠ **Code cross-references predate the current layout.** The *decisions and data facts below remain valid*,
> but some cited paths/filenames (e.g. `assets/facilities.R`, `presets/…`, `build_panel(years=)`,
> `00_setup.R:8`, `data/clean/…`) come from an earlier architecture. The current pipeline lives under
> `code/` with standalone panel scripts in `code/03_panel_building/04_panels/` and cleaned assets in
> `data/processed/`. Being reconciled during line-by-line verification — confirm exact locations in the
> current `code/` tree. See `briefs/00_institutional_overview.md` for the institutional hub.

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
| inspections (`FCES_PCES`) | 1,802,044 | 1,801,418 | 1,802,044 | **~0%** |
| violations (`VIOLATION_HISTORY`) | 101,147 | 101,147 | 101,147 | **0%** |
| formal enforcement | 105,656 | 104,799 | 105,656 | ~1% |
| informal enforcement | 336,410 | 174,667 | 174,667 | **48%** |
| certs (`TITLEV_CERTS`) | 2,563,435 | 487,215 | 497,109 | **81%** |
| stack tests (`STACK_TESTS`) | 646,332 | 646,332 | 646,332 | 0% |

For certs, `dup>0` (2,076,220) exceeds `dup_exact` (2,066,326) by **9,894** — same-`ACTIVITY_ID` rows that differ on a kept column (= 497,109 − 487,215), i.e. sub-detail rows, not pure artifacts.

### B.1 `facilities` — the spine (`assets/facilities.R`)
The universe definition + the merge spine + the source of all sample filters. Runs **after** the four event assets.

| # | Decision | Alternative | Why / data issue |
|---|---|---|---|
| **F1** | **Universe = "ever-active in window"** — `PGM_SYS_ID` appearing in ≥1 event asset with an event dated in `YEARS` → **136,505** facilities on the spine (**135,213** after the contiguous-US filter applied at panel build → the `universe` panel). | All 279k `ICIS-AIR_FACILITIES` rows regardless of activity. | Ties the universe to observed regulatory activity; but classification alone includes dormant units `[G2]` and there are no entry/exit dates `[A3]`. |
| **F2** | **Attributes = current snapshot, 1 row/facility** (`distinct(PGM_SYS_ID, .keep_all=TRUE)`, keeps first). Operating status kept here is renamed **`op_status_current_desc`** to mark it as the *current* snapshot. | Reconstruct historical class/industry. | ICIS *live download* ships only the current snapshot — class, NAICS/SIC are time-invariant here `[A1, A2, A5]`. **Operating & program status are no longer only static:** a year-varying series is now reconstructed from the ICIS-AIR **wayback** snapshots — see **F7 / B.7** and the panel `WAYBACK` block. |
| **F3** | **Coordinates from FRS via `REGISTRY_ID`** (`distinct(REGISTRY_ID)`, first lat/long, numeric). | Use ICIS address geocoding. | FRS is the physical-site registry. Facilities with no FRS match / bad coords → `NA` → **unplaceable** (no county, no attainment). |
| **F5** | **38-column schema** — keys (`PGM_SYS_ID`, `REGISTRY_ID`), geography (address, `county_fips`, lat/long, state, region), industry (NAICS/SIC), `AIR_POLLUTANT_CLASS_DESC`, `op_status_current_desc`, the two static attribute profiles below (F6), **plus the reconstructed spell summary (F7): `entered_year`, `exited_year`, `exit_source`, `left_censored`, `right_censored`**. | Minimal keys only. | Carries all sample-filter fields + the establishment-linkage keys for the future Census/operating merge (D-A2), now partly answered by the wayback reconstruction (F7). |
| **F6** | **Two static "ever-*" attribute profiles**, one row/facility, matched from the ICIS code tables: (a) *pollutant profile* `emits_voc/pm/co/nox/so2/hap` (from `ICIS-AIR_POLLUTANTS`, pre-existing); (b) *program-enrollment profile* `prog_sip/titlev/nsps/mact/neshap/fesop/nsr/psd` + `n_programs` (from `ICIS-AIR_PROGRAMS`, **new**). Each `prog_*` = 1 if the facility is **ever** enrolled in that program (exact `PROGRAM_CODE` match; `prog_nsps` pools major `CAANSPS` + non-major `CAANSPSM`); `n_programs` counts **all** distinct codes incl. minor ones. Missing → `0` (coalesced, like the pollutant profile). | (i) A single categorical `program_type` column; (ii) time-varying enrollment via `BEGIN_DATE`. | Enrollment is a **set**, not one value — median **2**, max **15** programs/facility — so a lone categorical can't represent it without exploding the panel grain or a machine-hostile delimited string; **indicators encode set membership at the facility-year grain** and drop straight into regressions as non-exclusive dummies. **Static** because `ICIS-AIR_PROGRAMS` has a `BEGIN_DATE` but **no end date** (only a current operating-status snapshot) → de-enrollment is unidentified, so a time-varying flag would be only partially identified (D-A2/operating-status merge). Area-source GACT (`CAAGACTM`) is deliberately **not** folded into `prog_mact`. **New pipeline dependency:** `facilities.csv` (and every panel) now reads `ICIS-AIR_PROGRAMS.csv` — previously used only in `data_docs/`. Enrollment rates (contiguous-US universe): SIP 90.2%, Title V 18.2%, NSPS 31.2%, MACT 29.4%, FESOP 7.8%, NSR 5.4%, PSD 4.0%, NESHAP 2.2%; `n_programs=0` for **3,255** (2.4%) active facilities with no PROGRAMS record. |

| **F7** | **Reconstructed entry/exit spell summary** (1 row/facility), joined from `data/clean/wayback_facility_spells.csv.gz` (built in `scripts/02_clean/18_`). `entered_year` = first snapshot year OPERATING; `exited_year` = first year after which never operating again (**reopening-robust** — defined off the *last* operating year, so a close→reopen does not fabricate an early exit); `exit_source` ∈ {`cls`, `other`, `dropout`, `NA`}; `left_censored`/`right_censored` mark facilities already-present in the first (2015) / still-operating in the last (2025) snapshot. | ICIS `BEGIN_DATE` (unreliable) + no close date. | ICIS ships **no** facility entry/exit dates `[A3]`; the annual wayback snapshots let us *observe* appearance/disappearance and operating→closed transitions. Left/right-censored because the snapshot window is only 2015–2025. `dropout` (last seen operating, then vanished) is kept **distinct** from an observed `cls` because a disappearance can be an ICIS extract artifact, not a real closure. |

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
| **T1** | **Event id = `ACTIVITY_ID`; all ~5 rows/cert kept, `dup`/`dup_exact` flagged** (CC9). | `TITLEV_CERTS` is **81%** duplicate rows (one raw row per program/pollutant). `n_certs` counts `dup==0` (487,215 certs); `n_certs_raw` counts all rows (2.56M). The distinction is now explicit in the panel, not baked in. |
| **T2** | Date = `ACTUAL_END_DATE`; keep `deviation_flag` (`FACILITY_RPT_DEVIATION_FLAG`), `agency`. | The certification date + self-reported deviation. |
| **T3** | **Coverage caveat (documented, not fixed):** only ~62%/yr of "Major" facilities show a cert. | Class-major ≠ Title V annual certifier `[F4]`; don't assume a cert per major. |

### B.6 `attainment` (`assets/attainment.R`) — Green Book shapefiles + Wayback
| # | Decision | Alternative | Why / data issue |
|---|---|---|---|
| **AT1** | **PM2.5 (2012 std) ONLY, 2016–2025 ONLY** — deliberately narrow (3,829 facilities / 8 areas). | All pollutants, all years. | Wayback snapshot coverage; ozone/SO₂/lead not built yet. |
| **AT2** | **Time-varying, rebuilt from stacked Green Book Wayback status DBFs + NAA shapefiles.** | County-level `phistory` (all pollutants/years). | Maintenance-aware & sub-county; the `phistory` county version is preserved in `archive/panel_funnel_v1/04_attach_attainment.R`. |
| **AT3** | **Sub-county point-in-polygon** (`st_within`) places a facility by its coordinate → `composid`. | County FIPS join. | A NAA boundary is sub-county; coordinate placement is exact. Facilities without coords are absent. |
| **AT4** | **Maintenance-aware: `status` = N (nonattainment) / M (maintenance);** absent = attainment. | Binary in/out. | Redesignation matters for the research question. |
| **AT5** | **2023 snapshot missing → carried forward from 2022, flagged `imputed`.** | Drop 2023. | Preserves the panel year; the imputation is explicit. |

### B.7 `wayback` historical status — sources `ICIS_AIR_WAYBACK/ICIS-AIR_downloads_{2015..2025}`
Reconstructs **year-varying** facility operating status + program-active flags from the **11 annual ICIS-AIR snapshots** (echo.epa.gov downloads captured Sep–Nov each year, 2015–2025). Built in `scripts/02_clean/{17,18,19}_wayback_*.R`; the live download gives only one current snapshot. Three clean assets: `wayback_facility_status.csv.gz` (facility×year), `wayback_facility_spells.csv.gz` (facility summary → spine F7), `wayback_program_status.csv.gz` (facility×year, 8 program groups).

| # | Decision | Alternative | Why / data issue |
|---|---|---|---|
| **W1** | **1 snapshot = 1 panel year.** Snapshot Y (captured Q4-Y) maps directly to panel year Y; no within-window interpolation. | Date-based reconstruction from `BEGIN_DATE`. | Snapshots are annual and the panel is annual → the snapshot *is* the year's status. Capture months (Sep–Nov) confirmed with the data owner. |
| **W2** | **`operating` = code ∈ {`OPR`,`TMP`,`SEA`}** (Operating / Temporarily-Closed / Seasonal all count as in-service); `op_status_code` also kept raw. | Only `OPR` = operating. | Per-project decision: temporarily-closed and seasonal facilities are still establishments in service. `CLS`/`PLN`/`CNS`/`NER`/`NED`/`NES`/`LDF` → 0; missing code → `NA`. |
| **W3** | **Pre-2015 = `NA`, no back-fill.** Panel years 2005–2014 carry `NA` for every wayback field. | Carry the 2015 status back to 2005. | Wayback coverage starts 2015; we **cannot assert** a status where no snapshot exists (matches the panel's observed-vs-unobserved NA convention). Left edge of the 2015–2025 window is itself left-censored (F7). |
| **W4** | **Interior gaps LOCF-filled within a facility's observed span** (a facility absent from a *middle* snapshot carries its prior status/flags forward); leading/trailing edges are **not** extrapolated. | Respect the gap as `NA`; or fill from both sides. | Interior gaps are rare (~0.34% of facility-programs) and almost always ICIS extract hiccups, not real exits-and-returns; forward-fill is the conservative reading. |
| **W5** | **`BEGIN_DATE` ignored** for program history; snapshot **presence** (row exists & status ≠ `CLS`) is the truth. Program covered = the **8 spine groups** only (`prog_*_active`). | Trust `BEGIN_DATE`; build all program codes. | `BEGIN_DATE` is 100% populated 2021+ but unreliable (junk years, no close date). Starting with the 8 already-flagged groups keeps the panel aligned with the static `prog_*` profile (F6). |
| **W6** | **Known-zero coding.** A facility-year with `operating == 1` (in service in the wayback snapshot) but **no events** is coded as a **true structural zero** — `NA → 0` across the whole count/flag block (all `n_*`, `n_*_raw`, `any_*`, `hpv_active/1mo`). `obs_source` records provenance: `event` (≥1 event — original semantics), `operating` (new wayback-based zero), `unobserved` (still `NA`). | Leave every zero-event facility-year `NA` (event-only observation). | Previously the only evidence a facility-year *existed* was a regulatory event, so quiet years were `NA`. The wayback operating status is a **second observation channel**: if a facility is operating that year it demonstrably exists, so a zero-event year is a genuine zero, not missingness — this recovers ~16% of facility-years (major_synmin) as true zeros. **Trigger is `operating == 1` only** (`OPR/TMP/SEA`); **closed (`CLS`) years stay `NA`** (a shut plant can still carry legacy enforcement, so we don't assert its zeros). Only ever turns `NA → 0`, never overwrites a positive count; **`penalty_amount` is exempt** (keeps its own `0`/none → `NA` rule). Fully reversible: `obs_source == "event"` recovers the original event-only panel. |

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
| **Observation source** | `obs_source` ∈ {`event`, `operating`, `unobserved`} — why a facility-year's counts are `0` vs `NA` | always | derived from events + wayback `operating` (W6) |
| **HPV status** | `hpv_active`, `hpv_active_1mo` | when `violations` requested | violations spell (P8) |
| **Facility attributes** | `REGISTRY_ID`, `FACILITY_NAME`, address/`county_fips`/lat-long/`STATE`/`EPA_REGION`, `NAICS_CODES`/`SIC_CODES`, `FACILITY_TYPE_CODE`/`facility_type`, `AIR_POLLUTANT_CLASS_DESC`, `op_status_current_desc` | always | spine (F2–F5) |
| **Entry/exit spell** | `entered_year`, `exited_year`, `exit_source`, `left_censored`, `right_censored` (time-invariant per facility) | always | spine / wayback (F7, B.7) |
| **Pollutant profile** | `emits_voc/pm/co/nox/so2/hap` | always | spine (F6) |
| **Program enrollment** | `prog_sip/titlev/nsps/mact/neshap/fesop/nsr/psd`, `n_programs` | always | spine (F6) |
| **Wayback status** (year-varying) | `op_status_code`, `operating`, `prog_{sip,titlev,nsps,mact,neshap,fesop,nsr,psd}_active` — 2015–2025 only, `NA` elsewhere | always | wayback (B.7) |
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
| **P8** | **HPV-status flags (interval-based)** — attached whenever `"violations"` ∈ `outcomes`. `hpv_active` = in High-Priority-Violation status during **any** part of the year; `hpv_active_1mo` = in HPV status **> 30 days** of the year. Built from the spell `[hpv_dayzero_date, spell_end]` (V6): `spell_end` = `hpv_resolved_date` when resolved & valid, else (open **or** `resolved < dayzero`) **day-zero-year-only** (= Dec 31 of the day-zero year). Per facility-year the **union** of overlapping spells is taken; a spell-year is `1` **regardless of other activity** and is never masked; other facility-years are `0` (`NA` only for unobserved, no-spell cells when `balance=TRUE`). | ✔ lever | **Distinct from the recorded-year count `n_hpv`** (detail): `n_hpv` tags a determination to the single year it was *recorded*, but **69%** of resolved spells span >1 calendar year, so a status question needs the interval. Union (not sum) prevents concurrent spells double-counting days; **>30 days** operationalizes "more than a month." **Open-spell rule = day-zero-year-only** (your decision): conservative — an unresolved HPV is asserted only in its start year rather than assumed ongoing to panel-end, avoiding fabricated multi-year status from a missing close date. **Never-mask rule** is the point of an interval flag — HPV status carries across years with no new determination (a 2012→2014 spell reads `1` in 2013 where `any_violations` is `NA`). Coverage caveat inherited from V5. Universe 2005–2025: **34,576** facility-years `hpv_active` (vs Σ`n_hpv` = 24,403), **32,653** `hpv_active_1mo`. |

### Presets — the six shipped panels (two families, both `balance=TRUE`)
`presets/funnel_2005_2025_balanced.R` and `presets/funnel_2015_2025_continuous.R`.

| # | Decision | Notes |
|---|---|---|
| **PR1** | **Three funnel levels** — `universe` (all ever-active, contiguous US, 135,213) → `major_synmin` (`class ∈ {Major, Synthetic Minor Emissions}`, 45,423) → `electric_attainment` (+ `NAICS 2211` OR `SIC 4911`, 3,025; `treatment="attainment"`). | The NAICS/SIC-`OR` admits 212 SIC-only cases (90 unclassified-NAICS kept, ~122 non-electric) 🔎 — open **D-C1**. |
| **PR2** | **`_continuous_2015_2025` family** — the same three levels restricted to facilities active in **every** year 2015–2025, window 2015–2025. | Counts: universe 10,681 · major/synmin 9,929 · electric 1,183. Selects on the outcome (D-A2); no `NA` cells by construction. |
| **PR3** | `treatment="attainment"` on **electric only**; universe & major/synmin carry no treatment. | Mirrors the funnel; trivial to add to all three. |

### Funnel — facility counts, step to step
Each level narrows the sample; each `_continuous_2015_2025` variant applies the same filters **plus** "active in every year 2015–2025."

| step | balanced (2005–2025) | Δ from prev level | continuous (every yr 2015–2025) | Δ from prev level |
|---|---|---|---|---|
| `universe` | 135,213 | — | 10,681 | — |
| → `major_synmin` | 45,423 | **−89,790** (34% kept) | 9,929 | **−752** (93% kept) |
| → `electric_attainment` | 3,025 | **−42,398** (6.7% kept) | 1,183 | **−8,746** (12% kept) |

- **Across the funnel (balanced):** the class filter removes ~⅔ (135,213 → 45,423), then the electric NAICS/SIC filter removes ~93% of what remains (45,423 → 3,025).
- **Balanced → continuous, per level** (adding "active every year 2015–2025"): universe **−124,532** (7.9% kept) · major/synmin **−35,494** (21.9%) · electric **−1,842** (39.1%). Continuity retention rises with facility size; the "every year" bar drops far more than window turnover (of the 80,012 universe facilities active ≥1 yr in 2015–2025, only 10,681 are active all 11). Selection-on-outcome caveat: `panel_open_questions.md` §1.6 / D-A2.

### Panel activity snapshots (non-continuous, balanced 2005–2025)

| panel | facilities | rows | observed fac-yrs (≥1 action) |
|---|---|---|---|
| `universe` | 135,213 | 2,839,473 | 740,287 (26%) |
| `major_synmin` | 45,423 | 953,883 | 454,632 (48%) |
| `electric_attainment` | 3,025 | 63,525 | 42,544 (67%) |

Share of observed facility-years with ≥1 event (total events in parentheses), by measure:

| measure | universe | major_synmin | electric |
|---|---|---|---|
| inspections | 83% (1,237,178) | 80% (881,329) | 78% (118,533) |
| certs | 35% (424,510) | 52% (390,103) | 77% (56,430) |
| enforcement | 14% (169,671) | 14% (118,806) | 11% (8,884) |
| violations | 7% (68,662) | 9% (55,632) | 7% (4,354) |

**Patterns:** observed-year coverage rises down the funnel (26% → 48% → 67%); **certs concentrate in majors/electric** (35% → 77%, as Title V binds the larger sources); inspections are frequent everywhere (~78–83%) and *intensify* (mean 1.67 → 1.94 → 2.79 per observed year); violations/enforcement stay rare (~7–14%). Electric-specific: **127 facilities ever in a PM2.5 NAA / 1,165 nonattainment facility-years** (2016–2025); 75% Major, 25% Synthetic Minor; 18% "Permanently Closed" in the current snapshot `[G2]`.

### Panel activity snapshots (continuous — active every year 2015–2025)
The `_continuous_2015_2025` panels require ≥1 action in **every** year 2015–2025, so they are **fully observed by construction — 0 NA cells** (window = 11 years, not 21).

| panel | facilities | rows | observed fac-yrs |
|---|---|---|---|
| `universe_continuous_2015_2025` | 10,681 | 117,491 | 100% (0 NA) |
| `major_synmin_continuous_2015_2025` | 9,929 | 109,219 | 100% (0 NA) |
| `electric_attainment_continuous_2015_2025` | 1,183 | 13,013 | 100% (0 NA) |

Share of facility-years with ≥1 event (total events in parentheses), by measure:

| measure | universe | major_synmin | electric |
|---|---|---|---|
| inspections | 76% (258,502) | 75% (241,176) | 75% (37,994) |
| certs | 76% (146,682) | 80% (143,833) | 93% (22,605) |
| enforcement | 14% (35,746) | 14% (34,502) | 10% (2,381) |
| violations | 11% (22,613) | 12% (21,942) | 9% (1,682) |

**Note vs non-continuous:** every facility here is active *every* year (via some measure), yet only ~75–76% of facility-years carry an *inspection* — a "continuously active" year can be, say, a cert-only or violation-only year. Certs again concentrate in electric (93%). The continuity filter selects on the outcome (`panel_open_questions.md` §1.6 / D-A2).

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
- **N8 — `exit_source == "dropout"` cannot be adjudicated by regulatory events, and is ~disjoint from the event universe.** Of **30,774** observed exits (14% of ever-operating facilities), **18,802** are `cls` (an observed Permanently-Closed status), **171** `other`, and **11,801** `dropout` (last seen operating, then vanished — kept distinct from `cls` because a disappearance can be an ICIS *extract artifact* rather than a real closure, F7). The obvious test for artifact-vs-closure — does the facility generate regulatory activity *after* its vanish year? — is a **dead end here**: only **1 of the 11,801** dropouts appears in *any* of the six event assets at all (vs 51% of all wayback facilities). This is structural, not noise — facilities with regulatory activity persist in the ICIS facility extract, so the ones that vanish are precisely the event-less. The lone exception (`03000PA00011`, `exited_year` 2019) does carry an event dated **2026**, seven years post-vanish — a confirmed extract artifact, not a closure — which both proves the mechanism exists *and* shows how rarely events can catch it. **Practical guidance:** treat `cls` (18,802) as trustworthy exits; `dropout` (11,801) is an *upper bound* on unexplained exits and needs a per-question judgment call. Independent activity channels that *could* adjudicate the dropouts — programs `UPDATED_DATE`, year-stamped `POLL_RPT_COMBINED_EMISSIONS` — are untested (open-questions D-C4).
- **N9 — the spell summary assumes a single continuous operating episode; genuine reopenings (0.26%) are collapsed there but preserved in the panel.** `entered_year` = *first* operating year, `last_op_year`/`exited_year` = *last* operating year (18_), with no check for interruptions in between — so a facility that operates, closes, then reopens is summarized as one spell `[entered, exited]`. This is deliberate (**reopening-robust**: defining exit off the *last* operating year stops a mid-window closure from fabricating a spurious early exit, F7), but the same choice **erases the intermediate closure** from the one-row summary. Empirically rare: **583 of 220,579** ever-operating facilities (**0.26%**) have ≥1 genuine non-operating year strictly inside their span — real transitions (**1,353** interrupting facility-years are `CLS`, 126 `CNS`, 46 `PLN`), i.e. "Permanently Closed" is not always permanent in ICIS. **Scope of the loss:** only the spine spell fields (`entered_year`/`exited_year`/`exit_source`, F7) collapse; the **year-varying** `operating`/`op_status_code` in the panel (W-block, B.7) retains the true per-year sequence (a close→reopen still reads `1,0,…,1`). So year-by-year work is unaffected; only treating `[entered_year, exited_year]` as a *continuous* in-service interval mis-covers these 583. `exit_source` is likewise classified on the **final** transition only, so a `CLS`→reopen→vanish facility is typed by its last event, not its first closure.
- **N10 — year-varying `prog_*_active` reads "absence of a program record as a 0," which is record-backed 97.8% of the time and a forced zero 2.18%.** `19_wayback_program_status.R` reconstructs `prog_{sip,titlev,…}_active` per snapshot year from **snapshot presence**, not `BEGIN_DATE` (ignored, unreliable): a facility **present** in the year's `ICIS-AIR_FACILITIES` snapshot but carrying no active (non-`CLS`) row for group X is coded `0`, not `NA` (the structural-zero convention, gated on facility presence). This rests on ICIS-AIR PROGRAMS listing *all* active assignments each year. Empirically: of **2,811,232** present facility-years, **97.82%** have ≥1 PROGRAMS row, so an absent group there is a genuine "in the table, not in this program" zero; but **2.18% (61,397)** are present with **zero PROGRAMS rows at all** — for these every one of the 8 flags is forced to `0` with no record backing any of them, and `0` there could equally mean "extract missing this facility-year" rather than "confirmed not enrolled." Distinct from the **static** spine flags (N7, F6): those are ever-enrolled/undated; these are year-resolved but inherit the same missing→`0` risk in the no-record cohort. The subsequent **LOCF** (interior-gap carry-forward, mirroring `17_`) is negligible in magnitude — **75** facility-years across **32** facilities (0.003%) — so the "coverage unchanged until evidence otherwise" step is not the binding assumption; the no-record forced zero is.
- **N11 — `prog_*_active` uses a *blacklist* (active unless `CLS`); the facility `operating` flag uses a *whitelist* (`OPR/TMP/SEA` only). The two use opposite conventions and will not agree for planned/construction/missing statuses.** `19_` keeps a program row as active via `is.na(AIR_OPERATING_STATUS_CODE) | AIR_OPERATING_STATUS_CODE != "CLS"`, so *everything except Permanently-Closed* counts as `1`. The **NA branch is currently vacuous** — 0 of **4,310,008** in-group program rows have a missing status (every row carries a code), so "missing ≈ active" changes nothing today; it is a latent/defensive choice only. The **live** consequence of the blacklist is that non-operating statuses count as active: `PLN` (planned, 22,340 rows), `CNS` (under construction, 13,910), and `NER/NED/NES/LDF` (1,717) — ~0.98% of the 3,140,094 kept rows — read `prog_X_active = 1`. By contrast the facility `operating` flag in `17_`/W-block is a whitelist (`1` only for `OPR/TMP/SEA`; `PLN`/`CNS` → `0`; missing code → `NA`). **Net:** a facility in `PLN` status reads `operating = 0` but `prog_X_active = 1` in the same year. This is defensible if `prog_X_active` is read as *subject-to / enrolled under* program X (a permit obligation can attach before the plant runs) rather than *operating under* it — but the flags carry opposite planned/construction and NA conventions, so they answer different questions and should not be assumed to agree. Reconciliation (switching `19_` to the `17_` whitelist) is a **semantic change**, left open (see open-questions).

---

## Part E · Decisions still open
For the choices *not yet settled* — balance vs unbalanced (D-A1), operating indicator / Census merge (D-A2), the violation date rule (D-B1/B2), the electric definition (D-C1), whether to add emissions/penalties/covariates (D-D2–D4), and verification items (D-E1–E3) — see [`panel_open_questions.md`](panel_open_questions.md).
