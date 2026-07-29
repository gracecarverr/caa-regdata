# Open decision: is the AFS↔ICIS crosswalk good enough to use AFS as a pre-2015 operating signal?

> Not yet resolved — this is evidence for a decision you haven't made, not a record of one already made (see
> `panel/panel_construction_decisions.md` / `dataset_construction_decisions.md` for those). Related to
> **D-A2** in `../panel/panel_open_questions.md` (interim operating-status proxies) and a companion piece to
> `begin_year_operating_proxy.md` (the other pre-2015 candidate signal already investigated) — read that one
> first if you haven't; this asks a *prerequisite* question for a different candidate signal, not the same
> question again.

## Question

Wayback's `OPERATING` flag (dataset 1) has zero coverage before 2015. The legacy AFS system —
frozen in 2014, so it covers exactly the years wayback can't — carries
`AFS_AIR_PRG_HIST_COMPLIANCE.csv`: quarterly per-facility-program compliance-status snapshots back to
~1998, including an explicit **`9 = "In Compliance, Shut Down"`** code. That's the closest thing to a real
shut-down flag this project has for 2005–2014. But AFS uses `AFS_ID`; ICIS-Air (this repo's spine) uses
`PGM_SYS_ID`; the two share no format (`data/raw/README.md`: *"AFS uses different identifiers than
ICIS-Air; don't join them without an explicit crosswalk"*). **This brief asks only whether that crosswalk is
good enough to be worth building on** — not whether the compliance-status codes themselves turn out to be
clean once linked (a separate, downstream question, not addressed here).

This was investigated once before, in the predecessor project (`CAA_Project`), and — per the user, going in —
"we've done this in the past but haven't found great results." That prior attempt was never ported into
`caa-regdata`, so its numbers were not traceable from this repo and had never been checked against *this*
repo's actual facility universe. Diagnostic: `code/diagnostics/afs_frs_match/afs_icis_crosswalk.R`. Full
output tables: `output/afs_frs_match/*.csv`.

*Refreshed 2026-07-27 — re-run against both the current ICIS-AIR roster (279,665
facilities) and a re-fetched `FRS_PROGRAM_LINKS.csv` (both refreshed 2026-07-26). Everything in §§1–4 and §6
reproduced **byte-for-byte identical** to the prior run — those stages depend on the frozen AFS population and
FRS's `AIR`-tagged rows, not on the live ICIS-AIR facility count. Only §5 (which joins to the *current* spine)
moved, and only trivially.*

## 1. Method

Two hops, bridged through the EPA Facility Registry Service (FRS), which assigns one `REGISTRY_ID` per
physical facility across every EPA program system:

```
AFS_ID  --(hop 1, via FRS_PROGRAM_LINKS.csv)-->  REGISTRY_ID  --(hop 2, via ICIS-AIR_FACILITIES.csv)-->  PGM_SYS_ID
```

**Hop 1** works because FRS's air-program (`PGM_SYS_ACRNM == "AIR"`) rows whose `PGM_SYS_ID` is 18
characters long embed the legacy `AFS_ID` as their last 10 characters (state + zero-padding + `AFS_ID`).
This was verified, not assumed: extracting via last-10-characters matches 59.3% of AIR rows to a real
`AFS_ID`; the rejected alternative (strip a 2-letter state prefix + leading zeros + re-pad) only matches
52.5% — last-10 is the rule used, same conclusion as the original CAA_Project script.

**Hop 2** is a direct, essentially unambiguous join (`ICIS-AIR_FACILITIES.csv` already carries
`REGISTRY_ID`; only 208 of 164,935 hop-1-linked `AFS_ID`s, 0.13%, map to more than one `REGISTRY_ID`).

Unmatched AFS records after both hops get one further check: a conservative exact-after-normalization
name/address+state+zip5 candidate search against FRS. These are recorded as **evidence, not matches** — a
shared name or address doesn't prove the same physical facility, so nothing from this step is added to the
crosswalk (same discipline as the original script; any acceptance rule would need separate review).

## 2. Baseline reproduction — is the port correct?

Before trusting any new number, the full-AFS-population run was checked against CAA_Project's original
result. It matches **exactly**, including the full state-by-state breakdown:

| measure | this repo | CAA_Project (prior run) |
|---|--:|--:|
| AFS facilities total | 236,734 | 236,734 |
| Linked to a `REGISTRY_ID` (hop 1) | 164,935 (69.7%) | 164,935 (69.7%) |
| Ambiguous (>1 `REGISTRY_ID`) | 208 (0.13%) | 208 (0.13%) |
| Reaching an ICIS id end-to-end | **164,880 (69.6%)** | 164,880 (69.6%) |

This is a real reproduction, not a coincidence of rounding — the state-level table
(`output/afs_frs_match/unmatched_by_state.csv`) matches CAA_Project's `unmatched_afs_by_state.csv` row for
row. The method transferred cleanly; the earlier "haven't found great results" was not a bug in a since-fixed
script.

## 3. The closed-facility skew — reproduces, and explains part of "not great"

Match rate by AFS `OPERATING_STATUS`:

| status | n facilities | matched | % matched |
|---|--:|--:|--:|
| O (operating) | 169,063 | 123,850 | 73.3% |
| **X (closed)** | 60,680 | 35,171 | **58.0%** |
| T | 4,685 | 4,329 | 92.4% |
| C | 1,037 | 740 | 71.4% |
| P | 981 | 588 | 59.9% |
| I | 288 | 257 | 89.2% |

The crosswalk is worst for exactly the facilities a historical-status proxy would most want to place —
closed ones. A plausible read: older closed records were less likely to be migrated into FRS's current AIR
index at all, independent of anything about the physical facility.

## 4. ⚠ New finding: coverage is not a uniform ~70% — it's bimodal by state

Nothing in the original CAA_Project writeup called this out, but the state table makes it hard to miss.
Several large industrial states barely link at all, while most others link almost completely:

| worst-covered | n AFS facilities | % matched | | best-covered | n AFS facilities | % matched |
|---|--:|--:|---|---|--:|--:|
| IL | 20,197 | **0.6%** | | CO | 26,843 | 100% |
| SC | 4,428 | **1.4%** | | KS | 6,912 | 100% |
| OH | 6,602 | **1.6%** | | VA | 8,709 | 100% |
| MI | 3,609 | **5.0%** | | NE | 5,664 | 100% |
| NC | 7,807 | **7.9%** | | OK | 8,477 | 100% |
| MT | 2,602 | 7.1% | | TX | 5,539 | 99.7% |
| NY | 12,379 | 11.3% | | LA | 13,100 | 97.8% |

Twenty thousand Illinois facilities and 0.6% of them link. This isn't sampling noise — it looks like FRS's
AIR-program index for these states never had the legacy `AFS_ID` populated into the 18-character id format
hop 1 depends on, a state-level data-completeness gap, not a flaw in the join logic (the 59.3%-vs-52.5%
extraction check and the exact CAA_Project reproduction above both point away from a methodology bug). **Any
aggregate coverage number in this brief is an average over states that behave nothing alike** — a national
"~70% works" or "~70% doesn't" read is wrong either way; it depends heavily on which states the analysis
actually needs.

## 5. The number that actually matters: does it reach the population we'd apply it to?

The baseline (69.6%) answers "does AFS crosswalk well in general" — not the question this repo needs
answered, which is narrower: does it reach the facilities a pre-2015 proxy would actually be used on.

- **Current 279,665-facility ICIS spine** (`data/processed/facilities.csv.gz`): **59.6%**
  (166,601) trace back to *some* AFS record. Lower than the 69.6% baseline, as expected —
  a share of the current spine are facilities that entered after AFS was frozen in 2014 and have no AFS
  history to find, by construction.
- **The 171,161-facility pre-2015-begin-year population** (`output/begin_year_proxy/`, the exact
  group `begin_year_operating_proxy.md` §1 identifies as needing a pre-2015 signal): **74.5%**
  (127,562) are reachable. Higher than both the baseline and the full-spine number —
  expected, since this population is selected for pre-2015 existence, which is precisely AFS's coverage
  window. **This is the most favorable number in this brief**, but §4's state skew still applies to it in
  full: 74.5% is a national average, and a begin-year facility in Illinois or Ohio is reached at nowhere near
  that rate.

## 6. Candidate search on the unmatched

Of the 71,799 AFS facilities unmatched after both hops, **67.8% (48,698)** have at least one exact
name/address+state+zip5 candidate in FRS — evidence the physical facility likely *is* represented in FRS
under some other identifier, just not one hop 1 recovers. (CAA_Project's fuller 3-key search found 71.2% —
close; the gap here is a narrower 2-key search, not new missing data.) **None of these are in the
crosswalk.** If pursued, this is a second, separate project — fuzzy/candidate acceptance rules need their own
review before any match is trusted, per the same discipline the original script established.

## Summary

- **The port is verified correct** — exact reproduction of CAA_Project's baseline, state table included. The
  earlier "haven't found great results" read was accurate, not a since-fixed bug.
- **The closed-facility skew (§3) reproduces** — worse coverage for exactly the facilities a shut-down signal
  needs most.
- **The state-level skew (§4) is the header finding of this run** — coverage is not a stable ~70%; it swings
  from under 1% to 100% by state, for reasons that look structural (FRS data completeness) rather than fixable
  by better matching logic.
- **For the actual use case (§5), the picture is more favorable than the raw baseline suggests**: 74.5% of
  the specific pre-2015-begin-year population links — but that number still inherits §4's state
  concentration, so it overstates usefulness for whichever states happen to sit in the low-coverage group.

## Options (not a recommendation)

- (a) **Don't pursue further** — even the best-case 74.5% national figure is unevenly distributed in a way
  that would need per-state caveats attached to every downstream use, and the crosswalk itself doesn't touch
  whether `AFS_AIR_PRG_HIST_COMPLIANCE`'s status codes are clean once linked (§ not addressed here).
- (b) **Pursue, but scope to well-covered states only** — restrict any AFS-based pre-2015 signal to states
  with high crosswalk coverage (roughly the ~90–100% group in §4), and leave the rest `NA` rather than
  silently mixing reliable and near-absent coverage into one national rate.
- (c) **Chase the candidate-match population (§6)** before deciding — 48,698 unmatched facilities have an
  exact FRS candidate; if a reviewed acceptance rule recovers even a fraction of these, the state skew in §4
  could narrow. This is real additional work (a full separate review discipline), not a quick add-on.
- (d) **Pursue only for the closed-facility subset specifically** — since (§3) that's both the
  hardest-to-crosswalk group and the one a shut-down-status signal is built for, it may be worth knowing
  precisely which states' closed facilities are reachable before investing in downstream use of the
  compliance-status codes themselves.
