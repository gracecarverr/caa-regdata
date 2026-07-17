# Institutional Overview

The setting this data describes, and — for each institutional fact — its **implication for the data**.
This is the hub brief; deep dives live in [`panel_construction_decisions.md`](panel_construction_decisions.md)
and [`panel_open_questions.md`](panel_open_questions.md), and column-level detail in
`data/processed/*.README.md`.

> Scope note: this project currently covers **stationary-source air** regulation under the Clean Air Act.
> Facts below are stated at the level of detail the data needs; where a claim drives a construction choice,
> the linked briefs carry the specifics. Statutory/agency descriptions should be verified against EPA
> documentation before being cited in a paper. Core CAA program, threshold, class, and MDR-reporting facts
> here were cross-checked against EPA's MDR summary (Jan 2012) and ECHO data-entry requirements (2026-07-17);
> see Valuable Links (§5).

---

## 1. The statute and the regulator

**Clean Air Act (CAA).** The federal statute governing air-pollution control. For stationary sources
(factories, power plants, refineries — as opposed to mobile sources like cars), it sets up permitting,
emissions standards, monitoring, and enforcement, administered by the EPA together with state/local
agencies. Most day-to-day compliance work is delegated to states; EPA retains oversight and its own
enforcement authority.

- **Data implication.** Regulatory activity is recorded by *whichever* agency acted — federal, state, or
  local (an `agency` / `STATE_EPA_FLAG` field on the event assets marks E/S/L). Enforcement counts pool
  across levels of government unless deliberately split.

**National Ambient Air Quality Standards (NAAQS).** Health-based ambient concentration limits for
"criteria" pollutants (PM2.5, PM10, ozone, SO₂, NO₂, CO, lead). Geographic areas are designated
**attainment** (meeting the standard), **nonattainment** (not), or **unclassifiable** (insufficient data),
with a **maintenance** category for areas that were nonattainment and have since attained. Nonattainment
triggers stricter requirements on sources in the area, graded by severity.

- **Data implication.** Attainment status is a **place × time × pollutant** attribute, and it changes as
  areas are redesignated. It is the basis of the treatment variable. This project builds **PM2.5 (2012
  standard) only, 2016–2025 only** so far (see attainment decisions AT1–AT5). Areas can be **sub-county**,
  so facilities are placed by coordinate, not county FIPS.

---

## 2. The data systems

### ICIS-Air (EPA ECHO) — the primary source
EPA's **Integrated Compliance Information System – Air** is the current system of record for CAA stationary-
source compliance and enforcement. Distributed as bulk CSV tables via EPA ECHO. Provides facilities,
compliance evaluations, violations, formal/informal enforcement, Title V certifications, stack tests, and
program/pollutant lookups.

- **Facility key = `PGM_SYS_ID`** (the ICIS-Air regulated-facility / permit id). This is the project's
  facility identifier. Note "facility" is genuinely ambiguous — many `PGM_SYS_ID` can map to one physical
  site (`REGISTRY_ID`); regulation attaches to the permit. (Decision **CC1**.)
- **The live download is a single current snapshot.** It ships *current* operating status, class, and
  industry codes, and **no facility entry/exit dates**. Historical status therefore cannot be read off the
  live download — hence the Wayback reconstruction (§3).
- **The reportable universe is selective.** Minimum-Data-Requirement reporting (MDR, EPA Jan 2012) covers
  Title V **majors** (~14k), **synthetic minors** (~27k), Part 61 NESHAP minors, plus any facility in a CMS
  (Compliance Monitoring Strategy) evaluation plan, with a formal action, or with an active HPV. Ordinary
  **minors are largely absent** from compliance/enforcement records unless one of those triggers fires — so
  facility-year coverage is **endogenous to size/class**, not a clean sample of all sources. Load-bearing for
  any denominator or selection argument.

### AFS — the legacy predecessor
The **Air Facility System** is ICIS-Air's pre-2001 predecessor. Retained here for historical actions,
air-program, HPV, and historical-compliance tables (the `afs_*` assets).

- **Data implication.** AFS uses its own identifiers and coding; joining AFS to ICIS-Air is non-trivial and
  is treated as a documented, separate lineage (see the AFS↔FRS matching work). Do not assume AFS and
  ICIS-Air ids align without an explicit crosswalk.

### FRS — the facility registry (coordinates)
EPA's **Facility Registry Service** is the cross-program registry of physical sites, keyed by `REGISTRY_ID`.
Used here for facility **coordinates** (latitude/longitude).

- **Data implication.** Coordinates come from FRS via `REGISTRY_ID`. A facility with **no FRS match or bad
  coordinates gets `NA` coordinates**, which cascades: no county, no attainment placement (nuance **N4**).
  Coordinate coverage is the gate for every geography-based join.

### Green Book — attainment status
EPA's **Green Book** lists NAAQS nonattainment/maintenance areas. Current status comes from shapefiles;
**history is recovered from archived (Wayback) Green Book snapshots**, which is semi-manual.

- **Data implication.** Attainment *history* exists only as far back as usable snapshots — the narrow
  PM2.5-2016–2025 window reflects snapshot coverage, not a modeling choice.

---

## 3. Why the "Wayback" reconstruction exists

Two things the analysis needs are **not** in the current downloads: (a) *when* facilities and programs were
actually in service over time, and (b) attainment history. Both are recovered from **archived annual
snapshots**:

- **ICIS-Air Wayback** — 11 annual snapshots of the ICIS-Air download (captured ~Q4 each year, **2015–2025**),
  staged under `data/raw/ICIS_AIR_WAYBACK/`. One snapshot = one panel year. These reconstruct facility
  operating-status history, facility entry/exit spells, and program-active history — see
  `code/02_cleaning/wayback/` and decisions **F7 / B.7 / W1–W6**.
- **Green Book Wayback** — archived attainment status for the PM2.5 history.

- **Data implication.** Anything built from Wayback inherits its window (**2015–2025**; pre-2015 is `NA`,
  not back-filled), is **left/right-censored** at the window edges, and rests on **snapshot presence** as the
  measure of existence (begin/close dates are unreliable and deliberately ignored). Interior snapshot gaps
  are LOCF-filled; disappearances ("dropout") are kept distinct from confirmed closures because a vanish can
  be an extract artifact. These caveats are load-bearing — see W1–W6 and nuances N8–N11.

---

## 4. Key regulatory concepts (and their data handling)

**Compliance evaluations — FCE / PCE.** A **Full** or **Partial Compliance Evaluation** is EPA/state
inspection-type review of a source. Pooled here into "inspections," with `type` preserving full-vs-partial
(decision **I1**). Date = evaluation end (`ACTUAL_END_DATE`).

- **Data implication.** The **FCE** is the MDR-required review; CMS policy targets an FCE every **2 years**
  for majors and every **5** for synthetic minors (a target, not a guarantee). **PCEs are largely
  discretionary** — reported only when part of a CMS plan or an HPV discovery — so PCE counts
  **under-represent** actual partial reviews and should not be read as a complete census.

**Violations — FRV & HPV.** Two severity tiers. A **Federally Reportable Violation (FRV)** is one the state
must report to EPA (lower bar). A **High Priority Violation (HPV)** is the most serious class — it starts a
"day-zero" clock and triggers EPA's enforcement-response-policy timeline, with (sometimes) a resolution date.

- **Data implication.** ICIS Violation History tracks **both** FRV and HPV (`n_frv`, `n_hpv`); AFS's HPV
  table tracks **HPV only**. An HPV is an **interval** `[day-zero, resolved]`, and most resolved spells span more
  than one calendar year — so "HPV *status* in year Y" (interval-based `hpv_active`) is a different question
  from "HPV *recorded* in year Y" (`n_hpv`). Open/unresolved spells are treated day-zero-year-only
  (conservative). See **P8**, **V6**, nuance **N6**.

**Enforcement — formal vs. informal.** Formal actions (administrative/judicial, may carry penalties) and
informal actions (notices, warning letters). Pooled with a `kind` tag (**E1**).

- **Data implication.** **Only formal actions carry penalties**; informal → `NA` penalty (**E3**). A single
  settlement can span **multiple co-defendant facilities and repeats one penalty across each** — so penalties
  must be summed over first-occurrence rows only (`dup==0`), never over raw rows (**E4**, **F2**).

**Title V operating permits & annual certifications.** Major sources hold **Title V** operating permits and
file **annual compliance certifications**.

- **Data implication.** The certs table is **~81% duplicate rows** (one raw row per program/pollutant), so a
  certification count (`n_certs`, first-occurrence) differs sharply from a raw-row count (`n_certs_raw`).
  Also, class-"Major" ≠ Title V annual certifier — only ~62%/yr of majors show a cert, so **don't assume one
  cert per major** (**T1**, **T3**, **F4**).

**Facility class & program enrollment.** Facilities carry an air-pollutant **class** — **Major**, **Synthetic
Minor** (uncontrolled potential-to-emit over the threshold, but held below it by federally-enforceable
limits), or **minor** — and enroll in one or more **programs**: SIP (State Implementation Plan), NSPS (New
Source Performance Standards), MACT/NESHAP (hazardous-air-pollutant standards), NSR/PSD (New Source Review /
Prevention of Significant Deterioration), FESOP (federally-enforceable state operating permit), Title V, and
**Acid Rain / Title IV** (SO₂/NOx cap-and-trade, electric utilities only — AFS program code `A`, emissions in
CAMD).

Major-source status is **program- and pollutant-specific** and rests on **potential-to-emit** (full-capacity,
uncontrolled): 100 tpy of a criteria pollutant for Title V/SIP (lower in nonattainment — 50/25/10 by
severity), 10/25 tpy single/combined HAP under §112, 100 tpy (28 listed categories) or 250 tpy (else) for
PSD. The facility-level `AIR_POLLUTANT_CLASSIFICATION_CODE` is the **worst case** across all pollutants and
programs; the pollutant-level field carries the per-pollutant class. AFS's equivalent is
`EPA_CLASSIFICATION_CODE` (A1/A2/B/SM).

- **Data implication.** Enrollment is a **set**, not one value (median 2, max 15 programs/facility), encoded
  as non-exclusive `prog_*` indicators. Class/industry come from the **current snapshot** and are applied to
  all years (time-invariant); enrollment flags are **ever-enrolled** with **no end date**, so they cannot
  date *when* a program attached — use with care in event-study/timing designs (**F6**, **N7**, and the
  year-varying Wayback alternative **W5/N10/N11**).

**Duplicates are flagged, never dropped.** Across every event asset, no rows are removed; each carries `dup`
(occurrence index within its event id; `0` = first) and `dup_exact` (byte-identical repeat). `filter(dup==0)`
reproduces the deduplicated view exactly, while duplication stays auditable in place (**CC9**, nuance **N1**).

**Zero vs. missing.** The load-bearing panel semantic: within an **observed** facility-year, a measure with
no event is a true **0**; an **unobserved** facility-year is `NA`, never `0`. The Wayback `operating` flag
adds a second observation channel — an operating facility-year with no events is a *structural zero*, tracked
via `obs_source ∈ {event, operating, unobserved}` (**P3/P4**, **W6**).

---

## 5. Where to go next

- Building or reading an **asset**? → its `data/processed/<name>.README.md` + `docs/data_dictionary.md`.
- Want the **reasoning** behind a choice? → `panel_construction_decisions.md` (find the decision code, e.g.
  CC9, F7, P8).
- Deciding something **still open**? → `panel_open_questions.md`.
- Running the **pipeline**? → `code/README.md` and `code/RUN_ALL.R`.

## Valuable Links

- **Nonattainment & Maintenance Area Dashboard** — https://awsedap.epa.gov/public/extensions/specs-area-dashboard/index.html
- **Minimum Data Requirements (MDRs) for CAA Stationary Sources** (EPA, Jan 2012) — https://www.epa.gov/sites/default/files/2013-10/documents/mdrshort.pdf
- **ECHO / ICIS-Air data-entry requirements** — https://echo.epa.gov/resources/echo-data/data-entry-requirements
- **Title V permit (example — Virginia DEQ)** — https://www.deq.virginia.gov/home/showpublisheddocument/5711/637951157567970000
