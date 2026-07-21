# Clean Air Act Overview

## Valuable Links

Nonattainment and Maintenance Area Dashboard: https://awsedap.epa.gov/public/extensions/specs-area-dashboard/index.html

Title V Virginia Permit: https://www.deq.virginia.gov/home/showpublisheddocument/5711/637951157567970000

Minimum Data Reporting Requirements:
https://www.epa.gov/sites/default/files/2013-10/documents/mdrshort.pdf
https://echo.epa.gov/resources/echo-data/data-entry-requirements

## General Information

Comprehensive federal law that regulates air emissions from stationary and mobile sources. Authorizes the EPA to establish National Ambient Air Quality Standards (NAAQS).

* First passed in 1963, but the operative version was created by the 1970 amendments (same year EPA was established). Substantial expansions in 1977 and 1990.
* Cooperative federalism: the federal EPA sets standards, and the states do most of the implementation and enforcement, subject to federal approval/backstop.
* Distinguishes between mobile sources (cars, trucks, planes) and stationary sources (power plants, factories, refineries).

> **Data implication.** This project covers **stationary sources only**. Cooperative federalism shows up
> directly in the data as `STATE_EPA_FLAG` / `agency` on every event asset (E/S/L) — enforcement counts pool
> across levels of government unless deliberately split by agency.

## NAAQS

Foundation of the CAA. Set under section 108, EPA designates a set of "criteria pollutants" (currently ozone, particulate matter (PM2.5 and PM10), sulfur dioxide, nitrogen dioxide, carbon monoxide, and lead). Under section 109, NAAQS are set for each.

* Primary standards: protect public health. Secondary standards: protect welfare (crops, visibility, materials).
* NAAQS are about ambient air quality in a geographic area, not about any individual stack.
* Areas are classified as attainment (meeting the standard), nonattainment (not meeting it), or unclassifiable. These designations trigger different regulatory regimes.
   * Nonattainment areas are further graded by severity, which drives how strict the requirements are.
   * Official designations are re-evaluated by the EPA whenever the NAAQS are updated. The EPA is legally required to review the NAAQS for all criteria air pollutants at least every 5 years.

> **Data implication.** Attainment status is a **place × time × pollutant** attribute, not a facility
> attribute — it's the panel's treatment variable, and facilities are placed into an area by coordinate
> (sub-county), not county FIPS. This project has so far built only **PM2.5 (2012 standard), 2016–2025**;
> ozone/SO₂/lead attainment history is not yet constructed.

## State Implementation Plans (SIPs)

Section 110. Each state writes a plan showing how it will achieve and maintain the NAAQS.

* If a state fails to produce an adequate plan, EPA can impose a Federal Implementation Plan.

> **Data implication.** SIP enrollment (`prog_sip`) is the most common program flag in the data — ~90% of
> active facilities carry it, consistent with "applies to essentially everyone." It's an **ever-enrolled**,
> time-invariant flag with no end date, so it can't date *when* a facility came under its SIP obligations.

## Stationary Source Programs

Stationary-source regulation runs on: standard-setting programs that say how clean a source must be (NSPS, NESHAP/MACT, SIP limits), and permitting programs that bind those standards onto a specific facility and make them federally enforceable (NSR/PSD at construction, Title V during operation).

* Section 111: New Source Performance Standards (NSPS). Technology-based, nationally uniform emissions standards set by source category (power plants, cement kilns, etc).
   * NSPS apply to sources that are newly constructed or that undergo "modification."
      * Older sources can avoid the standard until they modify - incentive to keep aging plants running?
      * NSPS standards are largely "self-implementing"; they bind the source directly whether or not they've been written into a permit yet.
* Section 112: NESHAP and MACT: two regulatory generations under the same statutory section. Emissions of hazardous air pollutants (HAPs). Older Part 61 NESHAPs are pollutant-by-pollutant standards. (pre-1990 approach). Part 63 standards are MACT standards
created by 1990 amendments (set category-by-category at the level already being achieved by the lower-emitting sources of an industrial sector). A separate track for toxic air pollutants regulated through technology-based standards rather than ambient standards.

* 1990 amendments revised section 112 to require issuance of technology-based standards for
major sources and certain area sources.

* Major sources: a stationary source or group of stationary sources that emit or have potential to emit 10 tons per year or more of a HAP or 25 tons per year or more of a combination of HAPs.
   * For major sources, section 112 requires EPA to establish emission standards that require the maximum degree of reduction in emissions of HAPs. Commonly referred to as "maximum achievable control technology" or MACT standards.
* Area source: stationary source that is not a major source.

* Section 110: SIP - State Implementation Plans as an enforceable source of limits. The SIP itself is a direct source of federally enforceable emission limits on individual facilities.
   * Each SIP must include a permit program to regulate the modification and construction of any stationary source of air pollution.

> **Data implication.** `prog_nsps` pools **both** the major-source code (`CAANSPS`) and the non-major code
> (`CAANSPSM`) into one flag, so it doesn't by itself distinguish major/area-source NSPS status.
> `prog_mact`/`prog_neshap` are separate flags; the area-source GACT code (`CAAGACTM`) is deliberately **not**
> folded into `prog_mact`. All are static/ever-enrolled (see SIP note above).

## PSD and NSR

Preconstruction (New Source Review Permitting). Permitting half of the new source track. NSR splits geographically by attainment status:

* PSD (Prevention of Significant Deterioration): applies in attainment/unclassifiable areas. New or modified major sources must install Best Available Control Technology (BACT) and show their emissions won't deteriorate air quality beyond allowed increments. Major-source thresholds here are 100 tons/year for 28 source categories and 250 tons/year otherwise.
* Nonattainment NSR (NNSR) applies in nonattainment areas and is stricter: new/modified major sources must meet the Lowest Achievable Emissions Rate (LAER) and obtain emission offsets from existing sources, so net area emissions do not rise.
   * Major-source thresholds are lower and become stricter with the severity of nonattainment.

> **Data implication.** These are *preconstruction* permits, which the panel's year-varying program-active
> flags now encode directly: `prog_nsr_active` / `prog_psd_active` are active not only while a facility is
> **operating** (`OPR`/`TMP`/`SEA`) but also while it's **planned or under construction** (`PLN`/`CNS`) —
> unlike the other six program-active flags (SIP, Title V, NSPS, MACT, NESHAP, FESOP), which require the
> facility to actually be operating. A facility can therefore read `prog_nsr_active = 1` while `operating = 0`
> in the same year — that's not a contradiction, it reflects that the NSR/PSD obligation attaches before
> operation begins. (Decision **N11**, `panel_construction_decisions.md`.)

## Title V: Operating Permits (compliance backbone)

* Title V does not set new emission limits, but it consolidates all of a major source's existing obligations (NSPS, NESHAP/MACT, SIP, NSR/PSD terms) into one enforceable operating permit.
   * Threshold: 100 tons per year potential-to-emit of a regulated pollutant, lower in nonattainment areas and for HAPs.
* Required annual compliance certification: source attests to its own compliance.
* Failure to apply for a Title V permit or failure to submit the annual compliance certification is itself a federally reportable violation.

> **Data implication.** The Title V certs table (`TITLEV_CERTS`) is **~81% duplicate rows** (one raw row per
> program/pollutant on the same certification), so a certification count (`n_certs`) differs sharply from the
> raw row count — the panel now surfaces this with `n_certs_dup` rather than silently deduping. Separately,
> "required annual" does not mean "always observed": among **operating Major Emissions facilities**, only
> **72.5%** have a reported cert in 2025 (9,428 of 13,012), down from 77.5% in 2015 — a gap consistent with
> **reporting lag** in the ICIS extract (older certs for the same facilities exist through 2020–2024) rather
> than confirmed non-compliance. (Decision **N12**.)

## Layers of CAA Regulation

### Layer 1: Two Logics of CAA Regulation

1. Ambient-based (NAAQS -> SIPS). "The air in this area must be clean." EPA sets the standard, states figure out how to meet it. The SIP is the vehicle. Geographically driven, the same factory faces different requirements depending on whether it is located in an attainment or nonattainment area.
2. Source-based (technology standards). "This type of facility must control emissions this much." Doesn't matter where you are; if you are a cement plant, you meet the cement standard. NSPS, NESHAP/MACT, and the preconstruction permits (PSD/NSR) all work this way.

Title V sits on top of both. It doesn't create new requirements, it consolidates everything a facility owes into a single permit.

### Layer 2: Which Program Does What?

A facility going through its regulatory life:

* Before it's built: Does it need a construction permit?
   * In a clean-air area -> PSD, prevention of significant deterioration (best available control technology)
   * In a dirty-air area -> NNSR, new source review (lowest-achievable emission rate + offsets)
   * These are one-time permits, not ongoing programs. A source is subject to this regulation until it faces modification, which could change its designation potentially.
* Once it's operating: what ongoing standards apply?
   * SIPS: applies to essentially everyone. The state's plan for meeting NAAQS. Federally enforceable.
      * The state figures out which facilities need to do what (might set emission limits on specific plants, require certain control technologies, monitoring requirements). Different facilities in the same state can face very different SIP obligations depending on their size, industry, and location.
   * NSPS (New Source Performance Standards): applies if you're a new or modified source in a listed industrial category. Technology-based emission limits. "New" means built after the standard was published for your category.
      * Applies the moment you're a new source in a covered category.
   * NESHAP (National Emissions Standards for Hazardous Air Pollutants) (Part 61): original hazardous air pollutant standards. A short list of specific toxics (asbestos, benzene, beryllium, vinyl chloride, etc.)
      * Subject when you start operating.
   * MACT (Part 63): 1990 amendments replaced the old NESHAP approach with industry-wide technology standards for ~187 HAPs. "Maximum Achievable Control Technology." Big one for toxics.
   * FESOP (Federally Enforceable State Operating Permit): mechanism for states to cap a source's potential emissions below major source thresholds, making it a synthetic minor. Keeps small sources out of Title V.
* If it's a major source:
   * Title V: must hold a comprehensive operating permit. Must submit annual compliance certifications. This is the permitting program, not a substantive standard. Bundles everything else into one document.
   * Acid Rain (Title IV): only electric utilities. SO2/NOx cap-and-trade. CAMD data in emissions dataset.
   * Major source thresholds are set per pollutant. The facility-level classification is the "worst case": if you're major for one pollutant, you're a major facility. Regulatory burden is pollutant-specific.

> **Data implication.** "Once it's operating" is directly measurable via the year-varying `operating` flag
> (`1` iff status ∈ {OPR, TMP, SEA}, 2015–2025 only; `NA` before 2015 — no snapshot exists to assert a status).
> The "before it's built" / "once it's operating" split is exactly the NSR/PSD-vs-the-rest program-active
> distinction described under **PSD and NSR** above.

## Facility Classification

### What the Classifications Mean

Some basic terms:

* SIC (Standard Industrial Classification): older system (1930s-1990s). 4-digit codes (e.g. 2911 is petroleum refining, 4911 is electric services).
* NAICS (North American Industry Classification System): replaced SIC in 1997. 6-digit codes, more granular. Harmonized across the U.S., Canada, and Mexico.
   * NSPS and MACT standards are written for specific source categories.

**Major source.** A facility whose actual or potential emissions exceed the threshold for at least one pollutant. Potential is key, it means what the facility could emit if it ran at full capacity, 24/7, 365 days per year, with no controls.

The threshold depends on the program:

* SIP/Title V (criteria pollutants): 100 tons/year of any single criteria pollutant in attainment areas. In nonattainment areas, the threshold drops to 50, 25, or even 10 tons/year depending on how badly the area misses the NAAQS.
* HAPs (Section 112): 10 tons/year of any single HAP or 25 tons/year of all HAPs combined.
* PSD: 100 tons/year for sources in 28 listed industrial categories, 250 tons/year for everything else.
* Acid Rain: specific to electric utilities based on capacity and fuel type.

A facility can be major under one program's threshold and not another. Facility-level classification reflects the highest classification across all applicable programs and pollutants.

What being major means:

* Subject to Title V permitting, must hold a comprehensive operating permit, pay permit fees, and submit annual compliance certifications
* Higher inspection priority, EPA policy targets FCEs every 2 years for major sources
* More likely to trigger PSD/NSR review for modifications
* More extensive monitoring, recordkeeping, and reporting requirements
* More likely to face formal enforcement if violations are found
* Subject to MACT standards for applicable HAP categories

> **Data implication.** "Facility-level classification is the worst case" matches `AIR_POLLUTANT_CLASSIFICATION_CODE`
> in the Facilities table exactly (facility-level worst-case); the same field name in the Pollutants table is
> the **pollutant-specific** classification, so don't conflate the two tables' meaning of the same column
> name. Class is read from the **current snapshot only** and applied to every panel year (time-invariant) —
> a facility that changed class over 2005–2025 shows only its latest class throughout.

**Synthetic Minor.** A facility whose uncontrolled potential emissions would exceed the major source threshold, but which has accepted legally binding, federally enforceable limits on its operations or emissions that keep it below the threshold. The facility voluntarily constrains itself (through a FESOP or an SIP permit with enforceable conditions) in exchange for a lighter regulatory treatment.

* This is a deliberate regulatory choice by the facility. Limits might cap production hours, restrict fuel types, require specific control equipment, or directly cap emission rates.
* Limits must be federally enforceable, not just a promise, but a binding permit condition that EPA or state can act on.

What being a synthetic minor means:

* Avoids Title V permitting (main incentive, Title V permits are expensive and burdensome)
* Lower inspection priority (EPA targets FCEs every 5 years instead of 2)
* Still subject to NSPS and MACT if applicable to the source category
* Still subject to SIP requirements
* Enforceable limits themselves become compliance obligations. Violating the limit is an enforceable violation and can bump you back up to major

Bunching below the threshold? Gaming potential to emit calculations? Differences for facilities just above or below the threshold?

**Minor Source.** Actual and potential emissions are below all major source thresholds without needing enforceable limits. The lightest regulatory burden.

What being a minor source means:

* No Title V permit required
* Lowest inspection priority, many minor sources go years or decades without an FCE
* Still subject to SIP requirements (everyone is)
* Still subject to NSPS and MACT if applicable, being minor doesn't exempt you from technology standards for your source category
* May still need state-level operating permit (varies by state)
* Minimal federal reporting requirements

> **Data implication.** Minor sources are the class this project's compliance data represents *worst*: EPA's
> Minimum Data Requirements (MDR, Jan 2012) mandate reporting for Title V majors, synthetic minors, Part 61
> NESHAP minors, and any facility separately triggered by a CMS plan, formal action, or active HPV — ordinary
> minors are largely **absent** from compliance/enforcement records unless one of those triggers fires. So
> facility-year coverage in this data is **endogenous to size/class**, not a clean random sample of all
> sources — load-bearing for any denominator or selection argument.

"AIR_POLLUTANT_CLASSIFICATION_CODE" in Facilities table gives facility-level "worst case." In the Pollutants table, the same field is the pollutant-specific classification. In AFS, the equivalent is "EPA_CLASSIFICATION_CODE." A1 (actual or potential controlled >100 tons/year), A2 (actual <100, potential >100), B (potential uncontrolled <100), SM (synthetic minor).

Classifications dependent on potential to emit are interesting.

> **Data implication.** AFS's `EPA_CLASSIFICATION_CODE` has two more values beyond A1/A2/B/SM, verified
> against EPA's AFS documentation: **C** ("Class is unknown") and **E1/E2**. Don't drop or ignore these as
> parse failures — they're valid codes.

## The Enforcement Process

### Who Enforces?

States do most enforcement. When the EPA "delegates" a program to a state, the state takes the primary responsibility for permitting, inspecting, and enforcing the program. EPA retains oversight and backstop authority (it can step in if the state isn't doing its job).

* In the data, this is the "STATE_EPA_FLAG."
* Local agencies (air quality management districts, mostly in California and a few other states) handle some share too.

### The Enforcement Pipeline

**Step 1: Compliance monitoring**

* FCE (Full Compliance Evaluation): comprehensive review of a facility's compliance with all applicable requirements. Can be on-site (inspector visits) or off-site (record review). EPA policy says that major sources should get an FCE every 2 years, synthetic minors every 5 (are these targets frequently met)?
* PCE (Partial Compliance Evaluation): focused on a specific aspect. Stack test review, CEM audit, record check.
* Stack Tests: direct measurement of what is coming out of the stack. The facility usually conducts them, and the agency may view or observe the results.
* Title V Certification Review: the facility self-certifies annual compliance; the agency reviews it.

This is the FCE/PCEs table, Stack Tests table, and Title V Certs table. In AFS, these are all rows in the actions table differentiated by "NATIONAL_ACTION_TYPE."

> **Data implication.** FCE/PCE are pooled into one "inspections" measure, with `type` preserving the
> full-vs-partial split. PCEs are largely discretionary (reported only as part of a CMS plan or an HPV
> discovery), so PCE counts under-represent actual partial reviews and shouldn't be read as a complete census
> — the "are these targets frequently met?" question is directly testable from `n_fce`/`n_inspections` against
> the 2-year/5-year CMS cadence, but hasn't been run yet.

**Step 2: Violation found (the inspection or review reveals noncompliance)**

* FRV (Federally Reportable Violation): serious enough that the state must report it to the EPA (reporting thresholds?), but doesn't necessarily trigger the full federal enforcement response. Threshold is lower.
* HPV (High Priority Violation): the most serious category. Triggers EPA's enforcement response policy, which sets timelines for how quickly the violation must be addressed.
   * Examples: failing to obtain a required permit, violating emissions limits detected via stack test, chronic violators.
   * HPVs start a clock. Once a facility is designated "HPV" (day zero), EPA's policy says that it should be addressed within a specific timeframe.
      * This is the Violation History Table (ICIS) and HPV History Table (AFS). ICIS tracks both FRV and HPV; AFS tracks HPVs.

> **Data implication.** ICIS's `hpv` flag is read off `HPV_DAYZERO_DATE` non-blank. An HPV is an **interval**
> `[day-zero, resolved]`, and **69%** of resolved spells span more than one calendar year — so "HPV *status* in
> year Y" (`hpv_active`, interval-based) is a genuinely different question from "HPV *recorded* in year Y"
> (`n_hpv`, the year it was determined). They will not agree year-to-year; use the one that matches the
> question. Open/unresolved spells are treated day-zero-year-only (conservative, doesn't assume ongoing
> status through the panel's end).

**Step 3: Informal Action.** Agency's first response is typically informal (no legal force, but signals that a problem has been identified).

* Notice of Violation (NOV)
* Warning letter
* Phone call
* Compliance assistance

Informal actions outnumber formal 3:1 in our data. This is our Informal Actions Table. In AFS, these are action codes like 6A (EPA NOV), 7C (state NOV), and 3E (warning).

> **Data implication.** The two tiers also diverge sharply in duplicate load: **informal** enforcement rows
> are **~48%** event-key duplicates (near-all byte-identical repeats) versus **~1%** for **formal** — so a raw
> row count overstates informal activity roughly 2× relative to formal. The panel now flags this with
> `n_informal_dup` / `n_formal_dup` rather than silently deduping.

**Step 4: Formal Action.** If informal action doesn't work, or if the violation is serious enough, the agency escalates to an action with legal force.

Three tiers:

* Administrative (formal): the agency issues an order. Consent agreements, administrative orders, compliance schedules. The majority are these.
* Judicial: the agency refers the case to court. Consent decrees, civil lawsuits. Rarer, reserved for the most serious or recalcitrant cases.
* Penalties are assessed at this stage. Heavily right-skewed because most cases settle with small penalties and a few major cases drive the mean up.

This is the Formal Actions Table.

> **Data implication.** Only **formal** actions carry a penalty (`penalty_amount`; informal → `NA`). A single
> multi-facility settlement **repeats the same penalty figure across every co-defendant's row**, so summing
> `penalty_amount` **across facilities** double- (or multiply-) counts that settlement — this is a live risk,
> not hypothetical: duplicate-row penalty dollars run **4.6%** of the total in the universe panel up to
> **11.6%** in the electric panel (`penalty_amount_dup` isolates this).

**Step 5: Resolution.** The violation is resolved, the facility returns to compliance, pays the penalty, and implements the required controls. The "HPV_RESOLVED_DATE" marks this.

Most compliance happens through the threat of enforcement, not enforcement itself. Idea of 'marginal deterrence,' where the regulator underpenalizes small violations to create strong marginal incentives to avoid large violations.
