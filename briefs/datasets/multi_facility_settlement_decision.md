# Open decision: how to handle multi-facility settlement penalties

> Not yet resolved — this extends **P5** in `dataset_construction_decisions.md`
> ("Multi-facility settlement structure EXPOSED, not resolved... neither 'take one value' nor 'sum' is
> universally right") with the dollar-magnitude evidence needed to actually decide. See also **E4** /
> **F2** in `../../archive/panel_building_legacy/briefs/panel/panel_construction_decisions.md`, which already
> established the same rule for the (now-archived, frozen) panel layer (`build_panel()`'s penalty block sums
> over `dup==0` only — a narrower fix for row-level duplication, not the cross-facility broadcast this brief
> is about).

## Question

`data/datasets/penalties.csv.gz` is one row per formal action per co-defendant facility. When a settlement
(`ENF_IDENTIFIER`) covers more than one facility, **the recorded `PENALTY_AMOUNT` is usually the full
settlement amount, repeated on every co-defendant's row** — not a per-facility share. Summing `PENALTY_AMOUNT`
naively (e.g. by facility, by year, or in aggregate) silently multiplies a shared penalty by however many
facilities were named in the settlement. How should this dataset (or its downstream consumers) handle it?

Diagnostic script: `code/diagnostics/12_penalties_profile.R` — its "CSV 6" section is a persistent, standing
script dedicated to backing this exact brief (`settlement_structure.csv`, `differing_settlements_detail.csv`,
`differing_settlements_trivial_vs_large.csv`, `settlement_dollars_by_population.csv`,
`co_defendant_distribution.csv`, all in `output/penalties_profile/`). Every figure below traces to one of
those files, not a one-off calculation.

*Refreshed 2026-07-27 (predates the 2026-07-26 ICIS-AIR refresh) — re-derived end to end
directly from `12_penalties_profile.R`'s own output (re-verified 2026-07-27 against an independent scratch
recomputation first, which matched exactly — see the CSVs above for the authoritative source going forward).
§3's taxonomy shifted in a way worth reading carefully, not just the headline counts — see the note there.*

## Evidence

### 1. How big is the multi-facility population?

Small in count, large in dollars:

| | value |
|---|---|
| settlements total | 103,084 |
| multi-facility settlements | 571 (**0.55%**) |
| max co-defendants in one settlement | 117 |
| ...of those 571: uniform amount repeated across facilities | 507 (88.8%) |
| ...of those 571: differing per-facility amounts | 64 (11.2%) |

Co-defendant counts are mostly small (321 settlements have exactly 2 facilities) but with a long tail
— **18 settlements have 20+ co-defendants**, one has 117.

### 2. The dollar impact — this is the number that makes the decision matter

Restricting to `DUP == 0` (event-key duplicates already excluded, so this isolates the cross-facility
broadcast specifically):

| aggregation method | total, 571 multi-facility settlements | as % of dataset total ($5,569,661,208) |
|---|---|---|
| **naive per-row sum** (current behavior if you just `sum(PENALTY_AMOUNT)`) | **$2,344,080,331** | 42.1% |
| **de-duplicated settlement total** (sum of *distinct* amounts per `ENF_IDENTIFIER`) | **$354,492,862** | 6.4% |
| max single amount per settlement | $350,331,897 | 6.3% |

*(As of 2026-07-27.)*

**The naive sum overstates the multi-facility total by $1,989,587,470 — 35.7% of the entire dataset's penalty
dollars, from settlements that are only 0.55% of all settlements by count.** This
is not a rounding issue; a naive aggregate penalty total (e.g. "total CAA penalties assessed 2005–2025") would
be inflated by more than a third if this isn't handled.

**This is not driven by one outlier.** The top 15 settlements by naive-sum size account for 72.4% of the
$1.94B overcounting, e.g.:

| settlement | co-defendants | true amount | naive sum (× co-defendants) |
|---|---|---|---|
| 06-2025-3401 | 43 | $9,400,000 | $404,200,000 |
| NM000A200275488 | 11 | $31,604,866 | $347,653,525 |
| NM000A200225814 | 5 | $40,336,818 | $201,684,090 |
| 08-2021-0183 | 30 | $3,000,000 | $90,000,000 |
| 04-2010-1528 | 11 | $8,000,000 | $88,000,000 |

These are large corporate-wide settlements (e.g. a single enforcement action against a multi-facility
operator) recorded once per named facility, each row carrying the *full* settlement amount — a real, expected
ICIS-Air data pattern, not a data-quality bug.

### 3. The 64 differing-amount settlements are a smaller, separate problem — and most of them aren't really "different"

*(As of 2026-07-27 — see the note below on how the taxonomy itself shifted, not just the count.)*

> **Methodology (unchanged from the prior pass):** settlement structure (which settlements are "differing")
> is identified from **all** rows, matching the dataset's own shipped `IS_MULTI_FACILITY`/
> `N_SETTLEMENT_FACILITIES` columns; dollar and spread figures are computed from `DUP==0` rows *within* those
> settlements, consistent with §2's rationale for stripping row-level duplicate inflation before looking at
> the cross-facility question.

| pattern | n settlements | naive sum | distinct-value sum |
|---|---|---|---|
| fully distinct (every facility has its own unique amount, `DUP==0`) | 20 | — | — |
| partial (some facilities repeat a value, some differ, `DUP==0`) | 23 | — | — |
| `DUP==0` spread is exactly $0 (duplicate-record artifact — see below) | 21 | — | — |
| **combined** | **64** | **$98,276,823** | **$53,535,663** |

For the 20 "fully distinct" settlements, every co-defendant's amount is genuinely different — summing across
facilities is very plausibly *correct* here (each facility may really owe a different share), so the
"de-duplicate by distinct value" rule from §2 is the wrong instinct for this subset specifically. The 23
"partial repeat" settlements looked like the genuinely ambiguous middle case: some facilities share a value
while others differ within the same settlement.

**But "distinct amounts" doesn't mean "meaningfully different" — checking the actual size of the difference
(max − min per settlement, `DUP==0` basis) splits the 64 very unevenly:**

| spread (max − min penalty within the settlement, `DUP==0`) | n settlements | naive sum | distinct-value sum |
|---|--:|--:|--:|
| **zero** (duplicate-record artifact — flagged "differing" only because a non-canonical `DUP>0` row differs) | 21 | $4,186,057 | $1,945,446 |
| **trivial ($5 or less, genuine `DUP==0` difference)** | 24 (see note) | $13,327,864 | $5,090,633 |
| genuinely large (>$5, mostly \\$1,000s–\\$100,000s) | **19** | $80,762,902 | $46,499,584 |

⚠ **The taxonomy shifted, not just the counts — read this before citing the old "53 artifacts" framing.** The
previous pass folded "trivial Texas rounding" and "duplicate-record inconsistency" into one 53-settlement
bucket. Recomputing cleanly separates them, and the split moved: **24 settlements now show a genuine (nonzero)
`DUP==0` spread of $5 or less — down from the 43 previously described as "Texas, differing by $1–3."** The
other **21 settlements have `DUP==0` spread of exactly $0** (up from 10) — these are flagged "differing" only
because a non-canonical `DUP>0` row carries a different amount, e.g. settlement `04-2000-0101`: both
co-defendant facilities show `$0` on their `DUP==0` row, but one also has a `DUP==1` row carrying $3,500,000.
Of the 24 trivial-spread settlements, **all 24 are Texas** (`ENF_IDENTIFIER` starting `TX...`) — still a clean
state-specific signature, just a smaller count than before. Of the 21 zero-spread settlements, **10 are also
Texas** — so Texas settlements now split across both artifact buckets (34 of 45 total artifacts), not
cleanly contained in one as previously described. The **19 genuinely-large-spread settlements are completely
unaffected by this reclassification** — same count, same dollar figures, still only 1 of them is Texas.

**Net effect: only 19 of the 64 (29.7%) — not 64 — are settlements where the amounts genuinely differ in a
way that plausibly reflects real per-facility penalty determinations** (was 19 of 72, 26.4% — the numerator
is identical, only the denominator shrank). The other 45 are artifacts: 24 trivial rounding differences
(all Texas) and 21 duplicate-record inconsistencies (10 of which are also Texas). No purely mechanical rule
resolves the remaining 19 without either occasionally under- or over-counting — those need case-level
judgment or an explicit approximation; the other 45 do not.

### 4. Facility-level attribution — a related but distinct question

Even if aggregate totals are handled, a facility-level question remains: for a multi-facility settlement, how
much penalty should *this one facility* be credited/charged with? Two candidate rules, applied dataset-wide
(`DUP == 0`):

| rule | total | reading |
|---|---|---|
| **as-recorded** (current `PENALTY_AMOUNT`, full settlement amount per facility) | $5,569,661,208 | Every co-defendant "owns" the full settlement — correct for "was this facility named in a $X action," wrong for "how much did this facility pay" summed across facilities. |
| **split-even** (settlement total ÷ n co-defendants, broadcast to each) | $3,552,789,747 | Every co-defendant gets an equal share — avoids the aggregate inflation in §2 by construction, but assumes co-defendants split evenly, which decision §3 shows is not always true (19 settlements have genuinely unequal per-facility amounts; the other 45 formerly-"differing" settlements split evenly enough that even splits would barely move the number). |

### 5. Are co-defendants genuinely different physical facilities, or the same facility under multiple `PGM_SYS_ID`s? (FRS ID check)

A prior question underneath §§1–4: does "multi-facility" mean genuinely distinct sites, or could some of it be one
physical facility registered under >1 `PGM_SYS_ID` (e.g. separate program-system IDs for the same plant) getting
mistaken for co-defendants? Checked by joining each co-defendant's `PGM_SYS_ID` to `REGISTRY_ID` (the FRS ID) via
`data/processed/facilities.csv.gz` and comparing, per `ENF_IDENTIFIER`, `n_distinct(REGISTRY_ID)` against
`n_distinct(PGM_SYS_ID)`. `REGISTRY_ID` resolved for all 2,610 co-defendant rows (no missing joins).

| | settlements | % of 571 |
|---|--:|--:|
| all co-defendants share **one** `REGISTRY_ID` (same physical facility) | 33 | 5.8% |
| co-defendants span **>1** `REGISTRY_ID` (genuinely different facilities) | 538 | 94.2% |
| ...of those 538: **every** co-defendant has its own distinct `REGISTRY_ID` (`n_registry_id == n_pgm_sys_id`) | 491 | 91.3% |

*(The 84.0% previously shown for this last row was a pre-existing arithmetic error — 494/552 is actually
89.5%, not 84.0% — corrected here along with the refresh; not a consequence of the ICIS-AIR snapshot change.)*

**The majority do not share an FRS ID.** Multi-facility settlements are overwhelmingly settlements against
genuinely separate physical facilities (consistent with the "corporate-wide settlement naming multiple plants"
reading in §2), not an artifact of one site being registered under several `PGM_SYS_ID`s.

The 33 same-`REGISTRY_ID` settlements are a small, distinct pattern, not a scaled-down version of the
main finding: 32 of 33 have exactly 2 co-defendant rows (one has 3), naive-sum dollars across
all 33 total only $29,008,522 (1.2% of the $2.34B naive multi-facility total in §2), and 31 of 33 already
carry a uniform amount across their rows. These look like one
physical facility appearing twice under different program-system IDs within the same enforcement action,
rather than a true co-defendant broadcast — worth excluding from, or flagging separately in, any
co-defendant-counting logic, but too small to matter for the aggregate-dollar decision in §2.

## Summary

*(Figures as of 2026-07-27.)*

- **This is not a marginal edge case in dollar terms.** 0.55% of settlements drive over a third of the
  dataset's naive total.
- **The uniform-amount case (507 of 571, 88.8% of multi-facility settlements) has a clean, mechanical fix**:
  de-duplicating to the distinct settlement amount recovers the correct total (§2) with no ambiguity.
- **The differing-amount case is smaller than it first looked.** Of the 64 settlements flagged "differing,"
  only **19 (29.7%)** have amounts that plausibly reflect real per-facility penalty determinations — the other
  **45 (70.3%)** are artifacts (24 trivial Texas rounding differences of $5 or less, 21 duplicate-record
  inconsistencies where the canonical `DUP==0` amount is actually uniform). Effectively, **552 of 571
  multi-facility settlements (96.7%)** — not 507 — can be handled with the same clean de-duplication rule as
  §2; only 19 (3.3%) genuinely need case-level judgment. The taxonomy of the 45 artifacts shifted from the
  prior pass (was 43 Texas-trivial / 10 duplicate-record = 53 total) — see the note in §3 before citing the
  old split.
- **Aggregate-total handling and facility-level attribution are two different decisions** — fixing the
  former (don't overcount the total) doesn't by itself answer the latter (what does *this* facility owe).
- **Co-defendants are genuinely different facilities, not an ID artifact** (§5): only 33 of 571 (5.8%)
  multi-facility settlements have all co-defendants resolving to the same FRS `REGISTRY_ID`; 538 (94.2%) span
  genuinely distinct physical facilities, 491 of those with every co-defendant on its own unique `REGISTRY_ID`
  (91.3% — corrected from a pre-existing 84.0% arithmetic error in the prior pass, unrelated to the refresh).
  The 33 same-facility cases are small in count and dollars ($29.0M, 1.2% of the naive multi-facility total)
  and look like one site double-registered under two `PGM_SYS_ID`s, not true co-defendant broadcasting.

## Options (not a recommendation)

- (a) **Status quo** — leave `penalties.csv.gz` exactly as is (P5's existing choice): `PENALTY_AMOUNT` as
  recorded, `N_SETTLEMENT_FACILITIES`/`IS_MULTI_FACILITY` expose the structure, the user is responsible for
  not naively summing. Simplest, but the $1.99B/35.7% exposure in §2 means a naive
  downstream user is one `sum()` away from a badly wrong headline number.
- (b) **Add a settlement-level de-duplicated total as a new column** (e.g. `penalty_amount_settlement_dedup`),
  computed as the sum of distinct amounts per `ENF_IDENTIFIER`, same value broadcast to every co-defendant row
  — correct for the 507 uniform settlements and, per §3, a good approximation for 45 more of the 64
  "differing" ones (off by only $5 or less for the 24 Texas cases, and arguably *more*
  correct than the status quo for the 21 duplicate-record cases). A genuine approximation only
  remains for 19 settlements. Would still need a documented caveat for those 19, not a silent fix.
- (c) **Add a `is_settlement_primary_row` flag** (one row per `ENF_IDENTIFIER` designated primary, arbitrarily
  or by some rule e.g. first `PGM_SYS_ID`) so `sum(PENALTY_AMOUNT[is_settlement_primary_row])` gives a
  correct-for-uniform-settlements aggregate without adding a new dollar column — cheaper than (b), same
  caveat for the 64 differing-amount settlements, and "primary" is an arbitrary label for those (no
  principled way to pick which facility's amount "represents" the settlement when they genuinely differ).
- (d) **Add a split-even per-facility attribution column** for facility-level (not aggregate) analysis — see
  §4. Orthogonal to (b)/(c): answers "how much did this facility pay," not "what's the total across
  facilities."
- (e) **Do (b) or (c) AND (d) together** — the aggregate-total problem (§2) and the facility-attribution
  problem (§4) are different questions and don't have to share one fix.
