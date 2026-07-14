# Panel Creation — Open Questions & Decisions

---

## Part 1 · Decisions we need to make

### 1.1 Panel shape: who is "in," and what is a zero?

**D-A1 · Balancing & zero-coding** `[A3, A2, G2]`
- **Question:** Base panel = observed facility-years only, or a full facility × year rectangle? And when a facility-year has no event, is that a `0` or `NA`?
- **Why it matters:** `FACILITIES` has no entry/exit dates `[A3]` and operating status is a current snapshot `[A2]`, so an empty facility-year is genuinely ambiguous — *closed* vs *operating-but-idle* vs *not-yet-reporting*. Coding it `0` asserts "observed and nothing happened"; coding it `NA` says "we can't tell." Getting this wrong biases any count/rate outcome.
- **Options:** (a) **Unbalanced base** — observed facility-years only; within an observed year, a measure with no event = true `0`. (b) **Balanced rectangle** — every facility × every year; unobserved cells = `NA` (never `0`). (c) Provide both via a toggle.
- **Lean / current:** Implemented as (c) — unbalanced base, `balance=TRUE` fills `NA`, never `0`. This is the defensible default (the zero is only asserted where we observe the facility that year). *The two downstream uses want different shapes* — within-EPA activity analysis is fine unbalanced; a **Census merge — and a future operating-status merge (D-A2)** — want all years present (NA-filled) so the frame is rectangular. Keeping the toggle resolves the tension rather than forcing one. → decide: is the toggle the answer, or do we commit to one shape?

**D-A2 · Operating indicator — build *now* for the future Census operating-status merge** `[A2, A3, G2]`
- **Question:** We want a per-year "was this facility operating?" indicator. Today we have only a current-snapshot operating status `[A2]` and no commission/decommission dates `[A3]`. The **historical operating status is coming from the planned Census merge** — so the real question is: how do we build the panel now so that merge lands cleanly (and how do we proxy operating in the meantime)?
- **Why it matters:** Operating status is exactly what disambiguates the zero (D-A1) — an empty facility-year is "operating but idle" vs "not yet built / already closed." `[G2]`. Without it, zero-activity years are uninterpretable.
- **Key point:** *operating status and the Census linkage are the **same** future merge, not two* (see 2.5) — Census establishment data (LBD-style birth/death/continuity) **is** the historical operating record. So treat operating status as a **future time-varying asset modeled on the attainment asset** — a separate `operating.csv` keyed **facility × year**, left-joined by `build_panel()`, `NA` until the merge. For that to work the panel must be *merge-ready now*:
  1. **Facility × year must exist as addressable rows** — the rectangular / `balance=TRUE` frame (D-A1). An operating flag needs a row to land on precisely in the no-activity years where the distinction matters most.
  2. **Keep the establishment-linkage keys on the spine** — the Census merge links on *physical establishment*: `REGISTRY_ID` (FRS), lat/long, `county_fips`, and full **address** (the bridge to the Census Business Register in an RDC). Add a null **ORISPL / EIA plant-code** column for the EIA-860 electric interim.
  3. **Operating status is a *flag*, not a *filter*** — never drop rows on it now, or you lose the facility-years you'd later want to reclassify.
- **Interim proxies (until the Census merge):** (a) activity-based — active in year *t* (⚠ circular if activity is also an outcome); (b) **emissions-reporting presence** — we already hold `POLL_RPT_COMBINED_EMISSIONS`, a semi-independent operating signal; (c) for electric specifically, **EIA-860** online/retirement dates — mergeable *now* via an ORISPL crosswalk.
- **To confirm at the meeting:** which Census product supplies the operating history (LBD vs Economic Census / Business Register), RDC access status, and the exact **FRS `REGISTRY_ID` ↔ Census establishment** crosswalk (existing bridge vs name/address match).
- **Lean:** Keep the base panel unfiltered; the authoritative operating history arrives *with* the Census merge, so the near-term job is the **establishment-linkage keys + rectangular frame**, not reconstructing operating status ourselves. EIA-860 is a fine electric-only interim.

### 1.2 The time dimension: which date, which window

**D-B1 · Canonical violation date** `[C1, E3]`
- **Question:** Which date places a violation in a year? `VIOLATION_HISTORY` offers ≥5 (`EARLIEST_FRV_DETERM_DATE`, `HPV_DAYZERO_DATE`, `HPV_RESOLVED_DATE`, `DSCV`/`NFTC` pathway).
- **Why it matters:** The choice *materially* moves yearly counts — e.g. 2005 shows **416 FRV-only vs 1,596 coalesced** `[C1]`. And the timing fields are sparse (`HPV_DAYZERO` 56% missing, `DSCV` 62%) `[E3]`.
- **Options:** (a) current: `coalesce(FRV, HPV_DAYZERO)`; (b) FRV only; (c) extend the fallback chain to `DSCV`/`NFTC` to recover more. Report all three so the date rule is a documented, swappable parameter.
- **Lean:** Keep coalesce(FRV, HPV) as default; show the count sensitivity as a robustness table rather than picking silently.

**D-B2 · Chase the dateless violations?** `[C1, E3]`
- **Question:** **9,305 of 101,147 violation rows (9.2%)** have neither FRV nor HPV_dayzero → no year → silently dropped. Do we recover them via `DSCV`/`NFTC` fallback?
- **Lean:** Worth a quick count of how many the fallback recovers before deciding; if it's most of the 9.2%, extend the chain (ties to D-B1c).

**D-B4 · Early-year coverage ramp** `[C2]`
- **Note (not really optional):** Violation coverage ramps from ~400 facilities/yr (2005–07) to ~3–4k by the 2020s `[C2]` Decide how we communicate this (coverage-adjusted comparisons? drop the earliest bins for violation outcomes?).

**D-B5 · First-non-blank vs first-parseable date** `[matrix latent / C7]`
- **Note:** The date logic takes the first *non-blank* field, not the first *parseable* one. Currently 0 unparseable dates so no effect — but a latent fragility if a malformed FRV pre-empts a good HPV fallback. Cheap to harden.

*(Minor, note only: `FORMAL_ACTIONS` land in settlement-entered year, which can lag filing by months/years `[C3]` — a timing mismatch vs other measures.)*

### 1.3 Sample definition & the snapshot problem

**D-C1 · How do we define "electric"?** `[matrix electric row; planning #1]`
- **Question:** The electric sub-panel qualifies a facility by NAICS `2211` **or** SIC `4911`. How do we treat the disagreements?
  - Both NAICS 2211 & SIC 4911: **1,738** (solidly electric)
  - NAICS 2211 only: **1,279** (solidly electric — NAICS is the authoritative modern code)
  - **SIC 4911 only: 223** ← the problem cases: **98** have NAICS `999999` (unclassified; SIC is the only signal — defensible to keep) and **125** have a clearly *non-electric* NAICS (hospitals, landfills, sewage, telecom, corrections). 🔎 *re-verify against current asset*
- **Options:** (a) NAICS-authoritative — drop the 125 non-electric SIC-only; keep the 98 unclassified. (b) Union as-is (keep all 223). (c) Manually adjudicate the 125.
- **Lean:** (a) — NAICS is the modern authoritative code; the 125 are legacy-SIC false positives. Document the 98 kept-on-SIC as a sensitivity.

*How NAICS/SIC matching works — which digit level?* (reference for D-C1 and any industry filter.) The digit count is the granularity dial, not a fixed "2–3 digits," and NAICS vs SIC behave differently in `build_panel`:
- **NAICS is a prefix match** — `2211` catches every electric child (`22111`, `221112`, `221122`…) but not gas `2212` or hospitals `622110`. Fewer digits = broader:

| level | code | scope |
|---|---|---|
| 2-digit | `22` | Utilities — electric **+ gas + water/sewage** |
| 3-digit | `221` | same utilities subsector |
| **4-digit** | **`2211`** | **Electric Power (generation + T&D)** |
| 5–6 digit | `221112` | fragments electric by fuel/function — too narrow |

- **SIC is an *exact* 4-digit match** in the current code — `sic="491"` or `"49"` match **nothing** (verified). Breadth comes from *listing codes*, not shortening: `4911` = pure electric; `4931`/`4939` = combination utilities that `4911` **misses**.
- **Takeaway:** keep NAICS `2211` as the authoritative electric identifier (electric = one clean code; SIC scatters it across 4911/4931/4939). Use 2–3-digit codes only for deliberately broad groupings ("all utilities" = `22`).

**D-C2 · Time-invariant classification** `[A1, A5]`
- **Question:** Class (`major/synmin/minor`) and NAICS/SIC are **current snapshots** applied to all 2005–2025 years `[A1, A5]`. There are 'BEGIN_DATES' and 'UPDATED_DATES,' however, the EPA states themselves that "The date that data were entered in the program system. Note that air program start dates are not a required field in ICIS-Air, and are usually the date the data were last updated (see also UPDATED_DATE), as opposed to the actual date that the plant or facility first began operating."
- **Options:** (a) accept + document time-invariance; (b) partially reconstruct history from `PROGRAMS` Title V enrollment dates (caveat: "program begin date is not reliable" per planning notes).
- **Lean:** Accept for now, document loudly; treat enrollment-date reconstruction as a later robustness check, not a v1 dependency.

**D-C3 · Facility as the unit** `[D1, D3]`
- **Question:** Panel is keyed on `PGM_SYS_ID` (regulated facility) carrying `REGISTRY_ID` (physical site). Many `PGM_SYS_ID`s map to one `REGISTRY_ID` (ownership/permit restructuring) `[D1]`. Do we ever collapse to the physical site?
- **Lean:** Keep `PGM_SYS_ID` as the panel unit (regulation attaches to the permit); carry `REGISTRY_ID` for cross-system joins `[D3]`. Flag site-collapse as a modeling choice, not a data default.

### 1.4 What goes in the panel (measures & covariates)

**D-D1 · Outcomes & double-counting** `[B1, B2]`
- Keep the four measures (inspections / violations / enforcement / certs) **separate**; `any_activity` = their union `[B2]`. Count **distinct event IDs**?, not raw rows `[B1]` (raw overcounts ~5× certs, ~2× informal). → confirm agreed treatment. Formal actions ~3% have duplicate IDs, different penalty amounts, dates. Deduplication by ID potentially loses multi-facility actions. 

**D-D3 · Penalties as an outcome?** `[F2, B5]`
- 795 duplicate ENF_IDENTIFIERS. Median: 2 facilities per case (mean 3.6, range 1-117). Median Penalty: the $15,150 including 0s, $50,000 non-0 (627 cases). 

**D-D4 · Additional covariates?** `[planning]`
- Candidates flagged in planning: **State/EPA flag** (who acted), **facility type** (private/govt/corporation), **programs**, **pollutants**, **stack tests**. Which earn a place in the standard panel vs stay optional joins? (Cert coverage caveat: only ~62%/yr of majors show a cert `[F4]`, and certs are 80.6% duplicate rows `[B1]`.)

### 1.5 Trust & verification (before we lean on it)

- **D-E1 · Verify the de-duplication.** Planning note: *"Claude de-duplicated event tables, need to investigate."* Walk through the distinct-ID logic (ACTIVITY_ID / COMP_DETERMINATION_UID / ENF_IDENTIFIER) and confirm counts against raw. *(Independently confirmed this session: TITLEV is 80.6% exact-duplicate rows, informal 48%.)* The assets dedupe by **event ID** (one row per event), **not** by entire row — entire-row dedup removes only byte-identical copies, so it over-counts wherever one event spans differing rows:

| table | raw rows | entire-row distinct | by event ID |
|---|---|---|---|
| certs | 2,563,435 | 497,109 | **487,215** |
| informal | 336,410 | 174,667 | 174,667 |
| inspections | 1,802,044 | 1,802,044 | **1,801,418** |

*informal:* all duplicates are byte-identical → both dedups agree. *certs:* entire-row leaves **+9,894** over-counted (IDs whose rows differ in a date/flag). *inspections:* no exact dups at all, yet 626 IDs span differing rows → entire-row removes nothing. **ID-dedup is correct for event counts; entire-row over-counts.** The cost is nuance **N1** — ID-dedup keeps the *first* row and drops differing siblings (see `construction_decisions.md` CC6/N1).

- **D-E2 · Understand `balance=TRUE`.** Live walk-through of what the rectangle + NA-fill actually produces (ties to D-A1).
- **D-E3 · Per-source cleaning scripts** that clean/prepare each EPA dataset *and flag the decisions made inside each asset* — is this the target structure?


---

## Part 2 · Framing questions (step back)

### 2.1 What does building a panel force us to confront?
A raw table lets you dodge questions a panel makes unavoidable. Building facility × year forces a stand on:
- **Identity** — what is "a facility"? (`PGM_SYS_ID` vs `REGISTRY_ID`; multi-PGM→one site) `[D1, D3]`
- **Membership / the denominator** — who is "in" each year, and what does an empty cell mean? `[A3]`
- **Time** — one timestamp per event when the source offers several `[C1]`; a window with truncated edges `[C6]`; coverage that ramps `[C2]`.
- **Time-invariance** — snapshot attributes (class, industry) stretched across years `[A1, A5]`.
- **What counts as an event** — distinct ID vs row `[B1]`; measures that overlap `[B2]`.
> The panel is where "we have the data" becomes "we have taken a position on identity, time, and membership."

### 2.2 How do we characterize a facility? (candidate sample dimensions)
| Dimension | Values / examples | Source | Time-varying? |
|---|---|---|---|
| Regulatory size class | Major / Synthetic-minor / Minor | `AIR_POLLUTANT_CLASS` | Snapshot `[A1]` |
| Permit type | Title V (individual operating permit) · general permit · synthetic-minor · true minor | Programs / Title V | Snapshot-ish |
| Industry | NAICS / SIC (e.g. electric 2211 / 4911) | `FACILITIES` | Snapshot `[A5]` |
| Location attainment | in / out of a NAA (PM2.5 …); N vs M | Green Book / Wayback | **Time-varying (now)** |
| Program enrollment | NSPS · NESHAP/MACT · SIP · PSD/NSR · Title V | `PROGRAMS` | dated but unreliable |
| Operating / activity | ever-active · active-in-year · operating proxy | events | derivable |
| Ownership / type | private / government / corporation | facility type code | Snapshot |
| Geography | state · EPA region · county_fips | FRS | fixed |

### 2.3 What must different facility types report? (why observability ≠ behavior)
- **Title V majors** — **annual compliance certification** (`TITLEV_CERTS`), scheduled full compliance evaluations, more monitoring.
- **Synthetic minors** — accepted enforceable limits *to stay under* major/Title V thresholds → fewer obligations.
- **Minors** — least.
> **Identification point for the meeting:** what we observe as "regulatory activity" is partly a function of *what a facility is obligated to report and be monitored for*, which varies by class/permit. Cross-class comparisons of activity therefore mix regulator behavior with reporting-regime differences. This is why cert coverage looks incomplete for majors `[F4]` and why "activity" is a selected outcome.

### 2.4 Snapshot vs temporal datasets
| Dataset | Snapshot or temporal | Notes |
|---|---|---|
| `FACILITIES` attributes (class, op-status, NAICS/SIC, address, coords) | **Snapshot** (current only) | no history `[A1, A2, A5]` |
| `PROGRAMS` enrollment | semi-temporal | has begin dates but "begin date unreliable" (planning) |
| `FCES_PCES` (inspections) | **Temporal** (dated) | |
| `VIOLATION_HISTORY` | **Temporal** (dated) | 5 date fields, sparse early `[C1, C2, E3]` |
| `FORMAL` / `INFORMAL` actions | **Temporal** (dated) | settlement lag `[C3]`; informal 48% dup rows |
| `TITLEV_CERTS` | **Temporal** (dated) | 80.6% dup; ~62% major coverage `[B1, F4]` |
| `STACK_TESTS` | **Temporal** (dated) | pollutant detail missing `[E2]` |
| Emissions (NEI/…) | **Temporal** (annual) | mixed units `[F1]` |
| Attainment (Green Book Wayback) | **Temporal** | PM2.5, 2016–2025 (maintenance-aware) |
| AFS | **Frozen legacy** (ends Oct 2014) | migrated into pre-2014 ICIS-Air `[D4]` |

---

## Part 3 · Open research & conceptual questions
*(from the Open Questions tab — lower priority for cleaning decisions, but meeting-worthy)*

- **SIP vs Title V vs NSR** differences in permits/violations/regulatory behavior.
- **Data-generating-process chart** for how the datasets interrelate.
- **Public-facing framing** — how to describe the repo/project to a general audience.
- Smaller data queries: pipeline `VIOL_TYPE` "linked to violation below" (which row?); `AIR_POLLUTANT_CLASS` = "other" meaning; multiple `PROGRAM_CODES`/pollutant placeholders (`FACIL`, `ADMIN`) in violations; `STACK_TESTS` pollutant 100% missing.
- **HPV definition changed in 2014** (policy discontinuity to keep in mind).

---

## Appendix · Data-issues matrix (condensed)
Full version with handling/provenance: `data_docs/output/tables/data_issues_matrix.xlsx`.

| Cat | High severity | Med | Low |
|---|---|---|---|
| **A Temporal/snapshot** | A3 no entry/exit dates (ambiguous zeros) | A1 class snapshot · A2 op-status snapshot · A4 first_year left-censored · A5 NAICS/SIC snapshot | |
| **B Grain/double-count** | B1 ACTIVITY_ID not row-unique · B2 event tables overlap | B3 multi-valued code fields · B4 pipeline placeholder IDs · B5 multi-facility penalty broadcast | |
| **C Dates** | C6 right-truncation (2025/26) · C7 two date formats | C1 no canonical violation date · C2 coverage ramp · C4 out-of-range dates · C5 mixed-text dates | C3 settlement lag |
| **D Identifiers** | D1 PGM vs REGISTRY · D3 keys not comparable across systems | D2 no shared event keys · D4 AFS/ICIS 2014 seam | |
| **E Missingness** | | E3 violation timing sparse · E4 AFS detail sparse · E6 coordinate cascade (10%) | E1 local-agency fields · E2 stack-test pollutant · E5 pipeline cost fields |
| **F Values/units/codes** | F1 emissions mixed units | F2 penalty skew/zeros · F4 Title V cert under-coverage | F3 opaque codes · F5 code/desc pairs |
| **G Sample/coverage** | | G1 AFS→FRS 30% unlinked · G2 majors 16% dormant · G3 attainment coverage (PM2.5, 2016–25) | |
