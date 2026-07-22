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

### 3. The 72 differing-amount settlements are a smaller, separate problem

| pattern | n settlements | naive sum | distinct-value sum |
|---|---|---|---|
| fully distinct (every facility has its own unique amount) | 23 | — | — |
| partial (some facilities repeat a value, some differ) | 29 | — | — |
| **combined** | **72** | **$93,590,446** | **$51,262,365** |

For the 23 "fully distinct" settlements, every co-defendant's amount is genuinely different — summing across
facilities is very plausibly *correct* here (each facility may really owe a different share), so the
"de-duplicate by distinct value" rule from §2 is the wrong instinct for this subset specifically. The 29
"partial repeat" settlements are the genuinely ambiguous middle case: some facilities share a value (probably
broadcast) while others differ (probably a real distinct penalty) within the *same* settlement. No purely
mechanical rule resolves this subset without either occasionally under- or over-counting — it would need
case-level judgment or an explicit approximation, not something this brief can settle on its own.

### 4. Facility-level attribution — a related but distinct question

Even if aggregate totals are handled, a facility-level question remains: for a multi-facility settlement, how
much penalty should *this one facility* be credited/charged with? Two candidate rules, applied dataset-wide
(`DUP == 0`):

| rule | total | reading |
|---|---|---|
| **as-recorded** (current `PENALTY_AMOUNT`, full settlement amount per facility) | $5,499,334,296 | Every co-defendant "owns" the full settlement — correct for "was this facility named in a $X action," wrong for "how much did this facility pay" summed across facilities. |
| **split-even** (settlement total ÷ n co-defendants, broadcast to each) | $3,561,288,705 | Every co-defendant gets an equal share — avoids the aggregate inflation in §2 by construction, but assumes co-defendants split evenly, which decision §3 shows is not always true (72 settlements have genuinely unequal per-facility amounts already recorded). |

## Summary

- **This is not a marginal edge case in dollar terms.** 0.57% of settlements drive over a third of the
  dataset's naive total.
- **The uniform-amount case (516 of 588, 87.8% of multi-facility settlements) has a clean, mechanical fix**:
  de-duplicating to the distinct settlement amount recovers the correct total (§2) with no ambiguity.
- **The differing-amount case (72 settlements) does not have a clean mechanical fix** — 23 look like genuine
  per-facility amounts (sum is probably right), 29 are a mixed pattern that needs a judgment call, not a
  formula.
- **Aggregate-total handling and facility-level attribution are two different decisions** — fixing the
  former (don't overcount the total) doesn't by itself answer the latter (what does *this* facility owe).

## Options (not a recommendation)

- (a) **Status quo** — leave `penalties.csv.gz` exactly as is (P5's existing choice): `PENALTY_AMOUNT` as
  recorded, `N_SETTLEMENT_FACILITIES`/`IS_MULTI_FACILITY` expose the structure, the user is responsible for
  not naively summing. Simplest, but the $1.94B/35.2% exposure in §2 means a naive downstream user is one
  `sum()` away from a badly wrong headline number.
- (b) **Add a settlement-level de-duplicated total as a new column** (e.g. `penalty_amount_settlement_dedup`),
  computed as the sum of distinct amounts per `ENF_IDENTIFIER`, same value broadcast to every co-defendant row
  — correct for the 516 uniform settlements, an approximation (not exactly right, not exactly wrong) for the
  72 differing ones. Would need a documented caveat for those 72, not a silent fix.
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
