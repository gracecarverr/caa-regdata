# Open decision: how to handle multi-facility settlement penalties

> Not yet resolved — this extends **P5** in `dataset_construction_decisions.md`
> ("Multi-facility settlement structure EXPOSED, not resolved... neither 'take one value' nor 'sum' is
> universally right") with the dollar-magnitude evidence needed to actually decide. See also **E4** /
> **F2** in `../panel/panel_construction_decisions.md`, which already established the same rule for the panel
> layer (`build_panel()`'s penalty block sums over `dup==0` only — a narrower fix for row-level duplication,
> not the cross-facility broadcast this brief is about).

## Question

`data/datasets/penalties.csv.gz` is one row per formal action per co-defendant facility. When a settlement
(`ENF_IDENTIFIER`) covers more than one facility, **the recorded `PENALTY_AMOUNT` is usually the full
settlement amount, repeated on every co-defendant's row** — not a per-facility share. Summing `PENALTY_AMOUNT`
naively (e.g. by facility, by year, or in aggregate) silently multiplies a shared penalty by however many
facilities were named in the settlement. How should this dataset (or its downstream consumers) handle it?

Diagnostic script: `code/diagnostics/12_penalties_profile.R` (general profile) plus a targeted deep-dive run
inline for this brief. Profile output: `output/penalties_profile/*.csv`.

## Evidence

### 1. How big is the multi-facility population?

Small in count, large in dollars:

| | value |
|---|---|
| settlements total | 102,745 |
| multi-facility settlements | 588 (**0.57%**) |
| max co-defendants in one settlement | 117 |
| ...of those 588: uniform amount repeated across facilities | 516 (87.8%) |
| ...of those 588: differing per-facility amounts | 72 (12.2%) |

Co-defendant counts are mostly small (327 settlements have exactly 2 facilities) but with a long tail — 8
settlements have 20+ co-defendants, one has 117.

### 2. The dollar impact — this is the number that makes the decision matter

Restricting to `DUP == 0` (event-key duplicates already excluded, so this isolates the cross-facility
broadcast specifically):

| aggregation method | total, 588 multi-facility settlements | as % of dataset total ($5,499,334,296) |
|---|---|---|
| **naive per-row sum** (current behavior if you just `sum(PENALTY_AMOUNT)`) | **$2,288,111,455** | 41.6% |
| **de-duplicated settlement total** (sum of *distinct* amounts per `ENF_IDENTIFIER`) | **$350,065,865** | 6.4% |
| max single amount per settlement | $346,068,831 | 6.3% |

**The naive sum overstates the multi-facility total by $1,938,045,591 — 35.2% of the entire dataset's penalty
dollars, from settlements that are only 0.57% of all settlements by count.** This is not a rounding issue; a
naive aggregate penalty total (e.g. "total CAA penalties assessed 2005–2025") would be inflated by more than a
third if this isn't handled.

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

### 3. The 72 differing-amount settlements are a smaller, separate problem — and most of them aren't really "different"

> **Correction (this pass):** an earlier draft of this brief reported $93,590,446 naive / $51,262,365
> distinct-value sum for "the 72." Re-deriving it for the refinement below surfaced that those dollar figures
> were actually computed over a *different* 52-settlement population (grouping on `DUP==0` rows only, which
> changes which settlements even qualify as "differing" — 20 settlements are only classified as differing at
> all because a duplicate row, not the canonical record, carries a different amount). Recomputed correctly
> below, using the same method as §1/§2 throughout: settlement structure (which 72) identified from **all**
> rows, matching the dataset's own shipped `IS_MULTI_FACILITY`/`N_SETTLEMENT_FACILITIES` columns; dollar and
> spread figures computed from `DUP==0` rows *within* those 72, consistent with §2's rationale for stripping
> row-level duplicate inflation before looking at the cross-facility question.

| pattern | n settlements | naive sum | distinct-value sum |
|---|---|---|---|
| fully distinct (every facility has its own unique amount) | 23 | — | — |
| partial (some facilities repeat a value, some differ) | 29 | — | — |
| **combined** | **72** | **$97,459,223** | **$52,943,681** |

For the 23 "fully distinct" settlements, every co-defendant's amount is genuinely different — summing across
facilities is very plausibly *correct* here (each facility may really owe a different share), so the
"de-duplicate by distinct value" rule from §2 is the wrong instinct for this subset specifically. The 29
"partial repeat" settlements looked like the genuinely ambiguous middle case: some facilities share a value
while others differ within the same settlement.

**But "distinct amounts" doesn't mean "meaningfully different" — checking the actual size of the difference
(max − min per settlement) splits the 72 very unevenly:**

| spread (max − min penalty within the settlement) | n settlements | naive sum | distinct-value sum |
|---|--:|--:|--:|
| **trivial ($5 or less)** | **53 (73.6%)** | $16,696,321 | $6,444,097 |
| genuinely large (>$5, mostly \\$1,000s–\\$100,000s) | 19 (26.4%) | $80,762,902 | $46,499,584 |

That 53 splits into two distinct, unrelated patterns — not one:

- **43 are Texas settlements (`ENF_IDENTIFIER` starting `TX000A...`) differing by exactly $1–3.** Of the 19
  genuinely-large-spread settlements, only 1 is Texas — this is close to a clean state-specific signature.
  Almost certainly an even split of one total penalty across co-defendants with a leftover $1–3 from integer
  division landing on one or two facilities, not a real per-facility penalty determination.
- **10 settlements have `DUP==0` spread of exactly $0** (all facilities show the *same* canonical amount,
  often $0) **but still get flagged "differing" because a separate duplicate row carries a different amount**
  for one of the facilities — e.g. settlement `04-2000-0101`: both co-defendant facilities show `$0` on their
  `DUP==0` row, but one of them also has a `DUP==1` row carrying `$3,500,000`. This is a duplicate-*record*
  inconsistency, not a cross-facility difference at all — a completely separate issue from the Texas pattern,
  and arguably a reason to reconsider whether `DUP>0` rows should ever be allowed to influence the
  differing/uniform classification in the first place (right now they can, via `N_DISTINCT_AMOUNTS` computed
  on all rows).

**Net effect: only 19 of the 72 (26.4%) — not 72 — are settlements where the amounts genuinely differ in a way
that plausibly reflects real per-facility penalty determinations.** The other 53 are artifacts: 43 trivial
rounding differences (Texas) and 10 duplicate-record inconsistencies. No purely mechanical rule resolves the
remaining 19 without either occasionally under- or over-counting — those need case-level judgment or an
explicit approximation; the other 53 do not.

### 4. Facility-level attribution — a related but distinct question

Even if aggregate totals are handled, a facility-level question remains: for a multi-facility settlement, how
much penalty should *this one facility* be credited/charged with? Two candidate rules, applied dataset-wide
(`DUP == 0`):

| rule | total | reading |
|---|---|---|
| **as-recorded** (current `PENALTY_AMOUNT`, full settlement amount per facility) | $5,499,334,296 | Every co-defendant "owns" the full settlement — correct for "was this facility named in a $X action," wrong for "how much did this facility pay" summed across facilities. |
| **split-even** (settlement total ÷ n co-defendants, broadcast to each) | $3,561,288,705 | Every co-defendant gets an equal share — avoids the aggregate inflation in §2 by construction, but assumes co-defendants split evenly, which decision §3 shows is not always true (19 settlements have genuinely unequal per-facility amounts; the other 53 formerly-"differing" settlements split evenly enough that even splits would barely move the number). |

### 5. Are co-defendants genuinely different physical facilities, or the same facility under multiple `PGM_SYS_ID`s? (FRS ID check)

A prior question underneath §§1–4: does "multi-facility" mean genuinely distinct sites, or could some of it be one
physical facility registered under >1 `PGM_SYS_ID` (e.g. separate program-system IDs for the same plant) getting
mistaken for co-defendants? Checked by joining each co-defendant's `PGM_SYS_ID` to `REGISTRY_ID` (the FRS ID) via
`data/processed/facilities.csv.gz` and comparing, per `ENF_IDENTIFIER`, `n_distinct(REGISTRY_ID)` against
`n_distinct(PGM_SYS_ID)`. `REGISTRY_ID` resolved for all 2,642 co-defendant rows (no missing joins).

| | settlements | % of 588 |
|---|--:|--:|
| all co-defendants share **one** `REGISTRY_ID` (same physical facility) | 36 | 6.1% |
| co-defendants span **>1** `REGISTRY_ID` (genuinely different facilities) | 552 | 93.9% |
| ...of those 552: **every** co-defendant has its own distinct `REGISTRY_ID` (`n_registry_id == n_pgm_sys_id`) | 494 | 84.0% |

**The majority do not share an FRS ID.** Multi-facility settlements are overwhelmingly settlements against
genuinely separate physical facilities (consistent with the "corporate-wide settlement naming multiple plants"
reading in §2), not an artifact of one site being registered under several `PGM_SYS_ID`s.

The 36 same-`REGISTRY_ID` settlements are a small, distinct pattern, not a scaled-down version of the main
finding: 35 of 36 have exactly 2 co-defendant rows (one has 3), naive-sum dollars across all 36 total only
$29,032,173 (1.3% of the $2.29B naive multi-facility total in §2), and 33 of 36 already carry a uniform amount
across their rows. These look like one physical facility appearing twice under different program-system IDs
within the same enforcement action, rather than a true co-defendant broadcast — worth excluding from, or
flagging separately in, any co-defendant-counting logic, but too small to matter for the aggregate-dollar
decision in §2.

## Summary

- **This is not a marginal edge case in dollar terms.** 0.57% of settlements drive over a third of the
  dataset's naive total.
- **The uniform-amount case (516 of 588, 87.8% of multi-facility settlements) has a clean, mechanical fix**:
  de-duplicating to the distinct settlement amount recovers the correct total (§2) with no ambiguity.
- **The differing-amount case is smaller than it first looked.** Of the 72 settlements flagged "differing,"
  only **19 (26.4%)** have amounts that plausibly reflect real per-facility penalty determinations — the other
  **53 (73.6%)** are artifacts (43 trivial $1–3 Texas rounding differences, 10 duplicate-record
  inconsistencies where the canonical `DUP==0` amount is actually uniform). Effectively, **569 of 588
  multi-facility settlements (96.8%)** — not 516 — can be handled with the same clean de-duplication rule as
  §2; only 19 (3.2%) genuinely need case-level judgment.
- **Aggregate-total handling and facility-level attribution are two different decisions** — fixing the
  former (don't overcount the total) doesn't by itself answer the latter (what does *this* facility owe).
- **Co-defendants are genuinely different facilities, not an ID artifact** (§5): only 36 of 588 (6.1%)
  multi-facility settlements have all co-defendants resolving to the same FRS `REGISTRY_ID`; 552 (93.9%) span
  genuinely distinct physical facilities, 494 of those with every co-defendant on its own unique `REGISTRY_ID`.
  The 36 same-facility cases are small in count and dollars ($29M, 1.3% of the naive multi-facility total) and
  look like one site double-registered under two `PGM_SYS_ID`s, not true co-defendant broadcasting.

## Options (not a recommendation)

- (a) **Status quo** — leave `penalties.csv.gz` exactly as is (P5's existing choice): `PENALTY_AMOUNT` as
  recorded, `N_SETTLEMENT_FACILITIES`/`IS_MULTI_FACILITY` expose the structure, the user is responsible for
  not naively summing. Simplest, but the $1.94B/35.2% exposure in §2 means a naive downstream user is one
  `sum()` away from a badly wrong headline number.
- (b) **Add a settlement-level de-duplicated total as a new column** (e.g. `penalty_amount_settlement_dedup`),
  computed as the sum of distinct amounts per `ENF_IDENTIFIER`, same value broadcast to every co-defendant row
  — correct for the 516 uniform settlements and, per §3, a good approximation for 53 more of the 72
  "differing" ones (off by only $1–3 for the 43 Texas cases, and arguably *more* correct than the status quo
  for the 10 duplicate-record cases). A genuine approximation only remains for 19 settlements. Would still
  need a documented caveat for those 19, not a silent fix.
- (c) **Add a `is_settlement_primary_row` flag** (one row per `ENF_IDENTIFIER` designated primary, arbitrarily
  or by some rule e.g. first `PGM_SYS_ID`) so `sum(PENALTY_AMOUNT[is_settlement_primary_row])` gives a
  correct-for-uniform-settlements aggregate without adding a new dollar column — cheaper than (b), same
  caveat for the 72 differing-amount settlements, and "primary" is an arbitrary label for those 72 (no
  principled way to pick which facility's amount "represents" the settlement when they genuinely differ).
- (d) **Add a split-even per-facility attribution column** for facility-level (not aggregate) analysis — see
  §4. Orthogonal to (b)/(c): answers "how much did this facility pay," not "what's the total across
  facilities."
- (e) **Do (b) or (c) AND (d) together** — the aggregate-total problem (§2) and the facility-attribution
  problem (§4) are different questions and don't have to share one fix.
