# Open decision: `EARLIEST_PROGRAM_BEGIN_YEAR` as a pre-2015 existence marker

> Not yet resolved — this is evidence for a decision you haven't made, not a record of one already made (see
> `../panel/panel_construction_decisions.md` / `dataset_construction_decisions.md` for those). Related to **D-A2** in
> `../panel/panel_open_questions.md`, an earlier open question about interim operating-status proxies, written before
> the wayback reconstruction existed.

## Question

`data/datasets/operating.csv.gz` carries `EARLIEST_PROGRAM_BEGIN_YEAR` (facility-level min `BEGIN_DATE` year
across a facility's program enrollments — decision O5) alongside the wayback-reconstructed `OPERATING` flag.
`OPERATING` only covers 2015–2025 (`NA` for 2005–2014, where no wayback snapshot exists).

**The use case under consideration is narrow and specific**: for a facility whose `EARLIEST_PROGRAM_BEGIN_YEAR`
predates 2015, can that single year be used as a one-time marker — "this facility is known to have existed as
of year X" — to push the known start of a facility's history further back than wayback alone can see? This is
**not** a claim that the facility was operating continuously from X through 2015, just that X is evidence of
existence at that one point. (An earlier draft of this brief tested the continuous-indicator version and found
it doesn't work — kept below as §2, since it explains a real structural limitation of the field, but it's not
the question that matters for this narrower use.)

Right now the field is fully inert: a repo-wide grep confirms `BEGIN_DATE` feeds nothing else in the
pipeline — not `operating`, not `entered_year`/`exited_year`, not `prog_*_active`. Adopting it in any form
would be a new use, not a restoration of an old one.

Diagnostic script: `code/diagnostics/10_begin_year_proxy.R`. Full output tables:
`output/begin_year_proxy/*.csv`.

## 1. Single-year anchor: how corroborated is "existed as of begin-year" for facilities with begin-year < 2015?

This is the population where the marker would add genuinely new information — wayback has zero evidence for
anyone before 2015, so this is the only check available: for a facility with `EARLIEST_PROGRAM_BEGIN_YEAR <
2015`, is what wayback shows *once it starts observing* (2015 onward) **consistent** with the facility having
already existed at that earlier year?

**n = 171,324 facilities** have a screened begin-year before 2015. Four mutually exclusive outcomes:

| group | n facilities | % | reading |
|---|---|---|---|
| **A** — left-censored at 2015 | 112,314 | 65.6% | Consistent: the facility is already present and operating at wayback's very first snapshot, exactly what you'd expect if it existed earlier. Wayback can't confirm the specific begin-year, but there's no contradiction either. |
| **B** — first observed operating *after* 2015 | 13,190 | 7.7% | A real discrepancy: begin-year claims existence before 2015, but wayback's first evidence of actual operation comes later. Gap size matters a lot here — see below. |
| **C** — never observed operating, but present in wayback (e.g. shows `CLS`) | 45,712 | 26.7% | Consistent with "existed once, closed before 2015" — plausible, not contradicted, but also not confirmed as *operating* at the begin-year (could have been enrolled without ever starting). |
| **D** — never appears in any real wayback snapshot 2015–2025 | 108 | 0.1% | No corroboration at all, either way. Negligible in size. |

**The critical caveat is in group B.** The gap between the claimed begin-year and the first real evidence of
operation grows sharply the further back the begin-year is:

| begin-year bucket | n facilities (group B) | median gap (years) | mean gap (years) |
|---|---|---|---|
| 2010–2014 | 12,341 | 2 | 2.6 |
| 2000–2009 | 681 | 13 | 13.8 |
| \<2000 | 168 | 26 | 28.3 |

For begin-years in 2010–2014, a 2-year median gap is small and plausible (permitting lag, similar to the 2015+
lag pattern in §2 below). For begin-years in the 1990s or earlier, a 26-year median gap means the begin-year
and the facility's actual observed operation are, empirically, telling very different stories — treating a
pre-2000 begin-year as reliable evidence of existence *at that specific year* is much weaker than treating a
2013 begin-year the same way. This isn't visible if you only look at the aggregate 65.6%/7.7%/26.7%/0.1% split.

**Read on this:** groups A + C (92.3%) are at least *not contradicted* by later evidence. Group B (7.7%) is
where the marker's reliability should be treated as a function of how far back it claims — trustworthy near
the 2015 boundary, increasingly speculative further back.

## 2. Why the continuous-indicator version doesn't work (kept for context, not the operative question)

An earlier pass tested `proxy = 1{EARLIEST_PROGRAM_BEGIN_YEAR <= YEAR}` as a stand-in for `OPERATING` in every
year from the begin-year onward, using 2015–2025 as a ground-truth check (`WAYBACK_OBSERVED == 1`). Aggregate:
sensitivity 0.909, **specificity 0.010**, overall agreement 0.655 (n=2,420,480 facility-years). By year,
specificity collapses from an already-poor 0.027 (2015) to **exactly 0.000 by 2025**, while sensitivity
climbs to 1.000 — because the proxy is a one-way ratchet with no close-date signal: once true, it's true
forever. Confirmed structurally in the post-exit check — for facility-years strictly after a confirmed
closure (`exit_source == "cls"`, 93,351 facility-years / 17,145 facilities), the proxy is wrong **99.5%** of
the time, and that rate does not decay with time since exit (98.8% at year 1, 100.0% by year 9). **This is why
the single-year framing in §1 is the right question to ask, not "is it operating right now."**

Full tables for this version: `output/begin_year_proxy/{agreement,agreement_by_year,post_exit_false_positive,post_exit_false_positive_by_gap}.csv`.

## 3. Lag near the 2015 boundary (context for §1's "gap" numbers)

For the 201,518 facilities with both a wayback `ENTERED_YEAR` and a begin-year (not restricted to pre-2015
begin-years): median lag (`entered_year − begin_year`) is 1 year, IQR [0,1]; 56% lead by exactly 1 year, 14%
match exactly, 17% go the other way (begin-year after observed entry). This is the same pattern that produces
the small 2010–2014 gap in §1 — near the wayback boundary, begin-year and observed entry track each other
fairly tightly. Full histogram: `output/begin_year_proxy/lag_histogram.csv` (note one artifact: 109 facilities
at exactly lag=45, likely the same population as the ~2.3% implausible `BEGIN_DATE` years flagged in decision
O5).

## 4. Do specific permit/program types tend to precede actual operation?

**Institutional prior, already baked into the pipeline**: `code/02_cleaning/wayback/19_wayback_program_status.R`
(decision N11) treats NSR and PSD as *preconstruction* programs — those permits attach before a source
operates, which is exactly why that script codes `PLN`/`CNS` (planned / under-construction) as "active" for
NSR/PSD but not for the other program groups. The natural hypothesis: if NSR/PSD permits are issued
pre-construction, their `BEGIN_DATE` should lead `ENTERED_YEAR` (wayback-observed first operation) more than
other program types do.

**Tested directly at the program level** (not the facility-level min used in §1/§3) — `data/processed/programs.csv.gz`
carries `BEGIN_DATE` per individual program enrollment row, so each facility's *own* earliest `BEGIN_DATE`
within each of the 10 program groups was compared to that facility's wayback `ENTERED_YEAR`, screened to
`[1970, 2025]` (same screen as O5). n = 354,743 facility-program pairs with both dates observed:

| program | n facilities | mean lag (years) | % begins before entry | % same year | % begins after entry |
|---|--:|--:|--:|--:|--:|
| **CFC** | 7,862 | **0.67** | **90.7%** | 0.7% | 8.6% |
| SIP | 180,704 | 0.02 | 62.4% | 16.3% | 21.3% |
| NSR | 11,124 | −0.29 | 68.1% | 7.6% | 24.3% |
| MACT | 50,399 | −0.29 | 60.4% | 15.8% | 23.8% |
| NESHAP | 2,880 | −0.23 | 66.5% | 4.9% | 28.6% |
| PSD | 6,510 | −0.45 | 62.2% | 11.3% | 26.5% |
| Title V | 19,805 | −0.50 | 63.0% | 6.8% | 30.2% |
| FESOP | 10,217 | −0.65 | 59.9% | 8.6% | 31.5% |
| NSPS | 50,191 | −0.67 | 51.9% | 17.6% | 30.5% |
| **GACT** | 15,051 | **−1.00** | **38.5%** | 10.8% | **50.7%** |

**This does not confirm the naive version of the prior.** NSR (68.1% begin-before-entry) and PSD (62.2%) are
*not* dramatically ahead of ordinary operating programs — NESHAP (66.5%) and SIP (62.4%) look similar or
higher. The standout pattern runs in a different direction entirely:

- **CFC is the strongest lead-time signal in the data** (90.7% begin before entry, the only group with a
  positive mean lag) — despite CFC (Title VI stratospheric ozone / refrigerant handling) not being
  architecturally a preconstruction program the way NSR/PSD are. A plausible institutional read: CFC
  obligations attach to equipment/technician certification requirements that can be registered independent of
  a facility's operational status, but this is a plausible explanation for a measured pattern, not something
  confirmed by this analysis — treat it as a hypothesis, not a finding.
- **GACT is the clear outlier in the other direction** — the only group where a majority (50.7%) begin *after*
  observed entry, and the only negative median lag. Plausible institutional read: Area Source MACT (GACT)
  standards were, as a regulatory matter, generally promulgated later than major-source MACT, so a
  long-operating facility can get swept into a new GACT category well after it was already running — again, a
  hypothesis this analysis doesn't independently confirm, not a demonstrated mechanism.

**Practical implication for option (c) below**: if a per-program confidence weighting is ever attached to the
single-year marker, it should not assume "preconstruction programs = more reliable early marker" — the data
says CFC and, to a lesser extent, NSR/NESHAP lead entry more consistently than others, while GACT should
probably be down-weighted or excluded as an early-existence signal, not treated the same as the rest.

Full tables: `output/begin_year_proxy/program_type_lag_by_group.csv` (summary) and
`program_type_lag_by_facility.csv` (every facility × program-group pair).

## Summary

- **As a same-year "is this facility operating" signal, no** — structurally broken by construction (§2).
- **As a one-time "existed by year X" marker for facilities whose begin-year predates 2015, mostly usable but
  distance-dependent**: 92.3% of the pre-2015-begin-year population isn't contradicted by later wayback
  evidence (§1, groups A+C), and the discrepant group (B) is small (7.7%) but its reliability itself decays
  the further back the claimed year — solid for begin-years in the early 2010s, speculative for pre-2000
  claims.
- **Program type matters, but not the way the "preconstruction permit" prior predicts** (§4): CFC leads entry
  most reliably, GACT lags behind it more often than not, and NSR/PSD sit close to the pack rather than
  standing out as expected.

## Options (not a recommendation)

- (a) Don't adopt it — leave pre-2015 facility history as unknown, consistent with dataset 1's "strictly raw,
  no imputation" discipline (O2).
- (b) Adopt it as a single-year existence marker only for facilities in group A/C (§1) — i.e. where later
  wayback evidence doesn't contradict it — and leave group B facilities' begin-year unflagged or flagged with
  lower confidence.
- (c) Adopt it as a single-year marker everywhere begin-year < 2015, but attach a confidence/distance measure
  (e.g. bucket by decade, per the §1 gap table) — and per §4, weight by *which* program set the earliest date
  rather than treating every program type as equally reliable (e.g. down-weight or exclude GACT-only begin-years).
