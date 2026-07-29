# The Eight Datasets

## Regulatory

Facility × year record built purely from ICIS-Air: inspections, violations, enforcement actions, penalties,
certifications, and stack tests, alongside each facility's static characteristics (location, classification,
industry codes). It's the spine every other dataset in this layer joins to.

**Scale.** 5,872,965 rows — every one of 279,665 ICIS-Air facilities × 21 years (2005–2025). Only 12.6% of
that rectangle is actually observed in ICIS-Air that year; the rest is unknown, not zero.

**Key decisions.**

* The universe is every facility ICIS-Air has ever tracked, with no "was this facility ever active" screen
  applied — including the 52.2% of facilities with zero events anywhere in the window (R1).
* A zero-vs-unknown discipline anchors this entire layer: a count is a true zero only if the facility was
  actually observed that year; otherwise it's unknown (R2). Every other dataset here inherits this rule.
* The penalty-amount field reads the same whether no formal action occurred or a formal action assessed
  exactly $0 — the two cases aren't distinguishable in this field alone (R4).

**Headline finding.** Coverage is far from uniform — only 12.6% of facility-years are observed overall, and
that share has drifted down over time (13.9% in the early window to 10.6% recently). It's also sharply
tiered by facility classification: 60.8% of Major-source facility-years are observed, versus just 6.4% for
Minor sources.

**Caveat.** Never compute a rate from this dataset without conditioning on whether the facility-year was
actually observed — the 12.6% baseline observation rate means an unconditional average will be badly
diluted by unknowns.

## Operating

Supplies the year-varying operating evidence the Regulatory dataset deliberately withholds: web-archive-
reconstructed operating status, program-active flags, entry/exit spells, and two facility-existence tiers
that combine multiple independent signals. Joins one-to-one to Regulatory.

**Scale.** Same 5,872,965-row rectangle. 42.1% of facility-years are archive-observed overall — close to
80% within 2015–2025, the actual window that source covers. A companion file separately tracks about 15,302
facilities the archive saw operating that current ICIS-Air no longer lists at all.

**Key decisions.**

* Every signal here is kept strictly raw — no imputation. Outside 2015–2025, or wherever the archive has no
  snapshot, the value is unknown (O2).
* The broader of the two existence tiers unions archive-confirmed operating status with ICIS and
  emissions/greenhouse-gas reporting, closing gaps no single signal covers alone (O6) — the panel layer's
  continuity screen is built on this tier.
* The universe here matches Regulatory's exactly, dropping the ~15,302 archive-only facilities into their
  own companion file so the two main datasets stay row-for-row joinable (O1/O1a).

**Headline finding.** 92,080 facilities are archive-confirmed operating with zero ICIS events recorded,
ever — meaning ICIS observation alone badly undercounts which facilities genuinely exist, which is exactly
what motivated building the broader existence tiers in the first place.

**Caveat.** A facility's disappearance from ICIS is only reliably captured here when it's a confirmed
closure — real mid-window disappearances that were never formally closed (roughly 1,018 of them) are
invisible in this main file; they only show up in the companion "archive-only" file.

## HPV Spells

The uncollapsed, spell-grain record of every High Priority Violation determination — one row per HPV spell,
kept deliberately raw rather than merged or deduplicated.

**Scale.** 44,777 spells across 15,656 facilities; 42.8% of those facilities have more than one spell.

**Key decisions.**

* The HPV universe is defined by the enforcement-response-policy code itself, not a broader violation
  category — it excludes the less-severe "federally reportable" tier entirely (H1).
* Overlapping spells at the same facility are NOT merged here — that collapse is deliberately deferred to
  the facility-year dataset below, keeping this file a faithful, minimally processed record (H2).
* Where a spell needs to become a single facility-year flag, an interval-overlap rule was chosen over two
  simpler alternatives (day-zero-year-only, or open-ended extension) after directly comparing what each
  would produce (H5).

**Headline finding.** Once resolved, an HPV spell tends to run long — median 315 days, and 44.2% span more
than a full calendar year. Title V (57.3%) and state implementation plan (48.5%) obligations dominate which
programs are implicated.

**Caveat.** Dates here are carried exactly as they parse from the raw source, with no plausibility
screening — a handful of clearly wrong values (one has a day-zero year of "218") pass through unchanged.
Screening happens downstream, in HPV Active, not here.

## HPV Active

The facility × year collapse of HPV Spells into a single, ready-to-use "was this facility in active-HPV
status this year" flag. Joins one-to-one to Regulatory and Operating.

**Scale.** Same 5,872,965-row rectangle; 35,417 facility-years are active (0.6%), 709,220 are confirmed
not-active, and the remaining 5,128,328 are unknown. 9,743 facilities are ever-active across the whole
window.

**Key decisions.**

* The same zero-vs-unknown discipline as Regulatory applies, with one addition: a spell can mark a
  facility-year active even in a year ICIS-Air itself has no other observed record for that facility
  (2,431 facility-years) (H6).
* Collapsing spells into years applies a plausibility screen on day-zero dates (rejecting anything outside
  1970–2025) — which caught a real data-entry bug: a mistyped day-zero year that would otherwise have
  spuriously flagged over a decade of facility-years as HPV-active (H7).

**Headline finding.** The active-HPV rate has fallen steadily and substantially, from 8.4% in 2005 to 2.0%
in 2025 — a roughly 4.3x decline that isn't fully explained by the known coverage-ramp and right-truncation
caveats affecting the edges of the window.

**Caveat.** That declining trend is flagged as genuinely unresolved, not a clean measure of falling
enforcement intensity — it's worth independent investigation before treating it as a headline finding on
its own.

## Penalties

The action-level detail behind Regulatory's facility-year penalty-amount field — one row per formal
enforcement action, reconciling exactly to that summary number.

**Scale.** 105,946 formal actions across 37,363 facilities, spanning 1972–2026 (this dataset isn't
restricted to the main panel window); 72,560 of those actions assessed a nonzero penalty.

**Key decisions.**

* Only formal enforcement actions are included — informal actions have no penalty amount to report at all
  (P2).
* Multi-facility settlements (one enforcement action naming several co-defendant facilities) are exposed via
  an explicit settlement identifier and facility count, not silently resolved — the per-row penalty amount
  is left exactly as reported, which is often the full settlement total repeated on every co-defendant's row
  (P5).

**Headline finding.** 571 settlements (0.55% of all actions) span more than one facility. Naively summing
the penalty amount across all rows overstates the true multi-facility penalty total by roughly $1.99B —
35.7% of this dataset's entire penalty total. The good news: 507 of those 571 settlements simply repeat one
uniform amount per co-defendant (a clean de-dup fixes them); only 19 settlements (3.3%) have genuinely
different per-facility amounts that need case-by-case judgment.

**Caveat.** Never sum the penalty amount across a settlement's co-defendant facilities without a
de-duplication rule — this is the single most consequential caveat anywhere in this dataset.

## Coordinates

One row per facility: latitude/longitude sourced from EPA's Facility Registry Service, a derived county
assignment (computed two independent ways), and diagnostics comparing the two.

**Scale.** 279,665 facilities; 236,219 (84.5%) have a coordinate, 236,059 (84.4%) have a county assignment,
and 2,873 (1.3% of those checkable) show a gross location error.

**Key decisions.**

* Coordinates come from the Facility Registry Service via each facility's registry ID; no match there means
  no coordinate at all, not an estimated one (C1).
* County assignment uses genuine point-in-polygon geometry against the full Census county file (all 56
  state/territory codes, not just the continental US) — not a text match against ICIS's own county name
  field (C2).
* A second, coordinate-independent county field is also included, derived from ICIS's own name text — it
  covers 93.6% of facilities, wider than the 84.5% that have a usable coordinate at all (C5).

**Headline finding.** For facilities where both a coordinate and an ICIS-claimed county exist, 97.3% land in
exactly the county ICIS claims. But quality varies sharply by state — Louisiana has only 29.1% coordinate
coverage, while New York's gross-error rate (7.3%) runs roughly 10x its peers despite near-complete coverage
there.

**Caveat.** Don't treat coordinate coverage or quality as geographically uniform — check the state before
leaning on this dataset's geography for Louisiana, New Mexico, or New York specifically.

## Pipeline

Facility × year data from EPA ECHO's Compliance Pipeline — the one dataset in this layer that links, on the
same row, the specific evaluation that discovered a violation to the enforcement action it triggered.
Covers both HPV and the less-severe "federally reportable" violation tier.

**Scale.** Same 5,872,965-row rectangle, but only 31,279 facility-years (0.53%) are actually observed
here — 18,334 facilities ever appear, out of just 20,222 of the full 279,665-facility universe (7.2%) that
show up in this source at all.

**Key decisions.**

* Roughly 7,218 raw rows are EPA placeholder records with no real violation behind them, and are excluded
  outright (PL1).
* The year a record is assigned to is anchored to the violation's own start date, chosen only after testing
  it directly against alternative date fields — not assumed (PL2).
* A penalty-amount field carried over from this source is exposed but explicitly flagged not to be summed
  against the Penalties dataset — the two aren't additive (PL4).

**Headline finding.** The less-severe violation tier outnumbers HPV more than 2-to-1 in this source (39,987
vs. 17,210). The evaluation-to-violation linkage this dataset is built to provide is essentially absent
before 2015, climbing to roughly 40–45% by 2020 onward.

**Caveat.** That near-zero pre-2015 linkage reflects "not yet tracked," not "zero linked evaluations" —
treat it as a tracking-era artifact, not a real rate, before about 2015. Separately, this dataset's penalty
field ($1.10B total) is not additional money on top of the Penalties dataset ($4.6B total) — the two should
never be summed together.

## Emissions

Facility × year combined pollutant report drawing on four EPA reporting systems — the only dataset in this
layer with actual measured emission quantities, rather than the boolean "does this facility emit X" flags
carried in Regulatory.

**Scale.** Same 5,872,965-row rectangle; 281,413 facility-years (4.79%) are observed for at least one
criteria pollutant, covering 54,335 facilities ever; 42,734 facility-years (5,334 facilities ever) are
observed for greenhouse gases specifically.

**Key decisions.**

* This is the one dataset in the layer that can't join on the standard facility program-system ID — it
  joins on the Facility Registry Service ID instead, since its raw rows are cross-program by nature (EM1).
* Pollutant totals are matched to each source row's pollutant name exactly, never by a partial/substring
  match — a direct test confirmed that a naive substring match would have inflated the PM10/PM2.5 totals by
  about 1.7x (EM4).
* Cases where several facilities share one registry ID are exposed as a flag rather than silently resolved
  (affecting 22,175 facilities) — the same kind of ambiguity Penalties handles for multi-facility
  settlements (EM2).

**Headline finding.** This dataset's coverage ceiling is only about 19.7% of the full ICIS-Air universe —
most emissions reporters simply aren't ICIS-Air facilities at all. Several key pollutants (VOC, PM10,
PM2.5, CO) only report in specific triennial cycle years (2008, 2011, 2014, 2017, 2020), reading as a hard
zero in every off-cycle year; nitrogen and sulfur oxides report annually instead.

**Caveat.** Never sum emissions across facilities that share one Facility Registry Service ID — it
double-counts. And never read an off-cycle-year zero for VOC/PM10/PM2.5/CO as a real emissions decline; it
just means that pollutant wasn't due to report that year.
