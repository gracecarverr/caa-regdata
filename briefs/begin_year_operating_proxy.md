# Open decision: `EARLIEST_PROGRAM_BEGIN_YEAR` as an operating-status proxy

> Not yet resolved — this is evidence for a decision you haven't made, not a record of one already made (see
> `panel_construction_decisions.md` / `dataset_construction_decisions.md` for those). Related to **D-A2** in
> `panel_open_questions.md`, an earlier open question about interim operating-status proxies, written before
> the wayback reconstruction existed.

## Question

`data/datasets/operating.csv.gz` carries `EARLIEST_PROGRAM_BEGIN_YEAR` (facility-level min `BEGIN_DATE` year
across a facility's program enrollments — decision O5) alongside the wayback-reconstructed `OPERATING` flag.
`OPERATING` only covers 2015–2025 (`NA` for 2005–2014, where no wayback snapshot exists). Should
`EARLIEST_PROGRAM_BEGIN_YEAR` be used as a proxy for operating status — most plausibly to extend coverage
into 2005–2014?

Right now the field is fully inert: a repo-wide grep confirms `BEGIN_DATE` feeds nothing else in the
pipeline — not `operating`, not `entered_year`/`exited_year`, not `prog_*_active`. Adopting it as a proxy
would be a new use, not a restoration of an old one.

**Proxy tested:** `proxy = 1{EARLIEST_PROGRAM_BEGIN_YEAR <= YEAR}` — onset-only, since `BEGIN_DATE` has no
matching close date in the source. **Ground truth:** wayback `OPERATING`, available 2015–2025
(`WAYBACK_OBSERVED == 1`). All numbers below are descriptive agreement statistics against that overlap
window, not a causal claim about anything.

Diagnostic script: `code/diagnostics/10_begin_year_proxy.R`. Full output tables:
`output/begin_year_proxy/*.csv`.

## Evidence

### 1. Coverage

| metric | n | % of 279,211 facilities |
|---|---|---|
| facilities with any raw begin-year | 266,744 | 95.5% |
| facilities with a screened (`[1970,2025]`) begin-year | 260,760 | 93.4% |
| facility-years 2005–2014 (pre-wayback) | 2,792,110 | — |
| ...currently `NA` under wayback (all of them) | 2,792,110 | — |
| ...would gain a non-`NA` proxy value if adopted | 2,607,600 | — |

Coverage upside is real and large: **2.6M of the 2.8M pre-wayback facility-years (93%)** currently `NA` would
get a proxy value.

### 2. Agreement vs. wayback ground truth, 2015–2025 (n = 2,420,480 facility-years)

Aggregate: base rate `OPERATING=1` 71.7% | **sensitivity 0.909** | **specificity 0.010** | overall agreement
0.655 | confusion TP=1,578,312 FN=157,223 TN=6,587 FP=678,358.

By year — the aggregate hides a strong trend:

| year | n | base rate operating | sensitivity | specificity | agreement |
|---|---|---|---|---|---|
| 2015 | 207,960 | 0.726 | 0.853 | 0.027 | 0.627 |
| 2016 | 225,643 | 0.727 | 0.873 | 0.023 | 0.641 |
| 2017 | 227,350 | 0.723 | 0.889 | 0.016 | 0.647 |
| 2019 | 240,546 | 0.721 | 0.890 | 0.012 | 0.645 |
| 2020 | 246,346 | 0.720 | 0.890 | 0.008 | 0.643 |
| 2021 | 249,610 | 0.717 | 0.898 | 0.008 | 0.646 |
| 2022 | 252,358 | 0.715 | 0.916 | 0.005 | 0.657 |
| 2023 | 254,116 | 0.714 | 0.927 | 0.003 | 0.663 |
| 2024 | 257,011 | 0.707 | 0.941 | 0.002 | 0.666 |
| 2025 | 259,540 | 0.704 | **1.000** | **0.000** | 0.704 |

(2018 absent — no real wayback snapshot that year, W7.)

**The proxy is a one-way ratchet.** Once `YEAR >= EARLIEST_PROGRAM_BEGIN_YEAR`, `proxy` stays 1 forever — it
has no mechanism to ever predict "not operating" again. As the panel moves later, more and more facilities
have already crossed their (fixed) begin-year, so specificity mechanically decays toward zero and sensitivity
mechanically climbs toward one. By 2025 the proxy has degenerated into "always predict operating" for every
facility with a screened begin-year — specificity is *exactly* 0, not just low.

### 3. Lag: `ENTERED_YEAR` (wayback) − `EARLIEST_PROGRAM_BEGIN_YEAR`, n = 201,518 facilities with both

Mean 0.38 | median 1 | IQR [0, 1] | 16.9% have begin-year *after* observed entry (proxy would lag reality for
these).

| bucket | n facilities | % |
|---|---|---|
| begin-year AFTER entry (proxy lags reality) | 33,988 | 16.9% |
| same year | 28,336 | 14.1% |
| 1 year lead | 112,709 | 55.9% |
| 2–5 years lead | 18,667 | 9.3% |
| 6–10 years lead | 4,565 | 2.3% |
| \>10 years lead | 3,253 | 1.6% |

For facilities where both are observed, the begin-year mostly leads observed entry by exactly 1 year (56% of
cases) or matches it (14%) — a plausible permit-before-startup pattern. But 17% go the wrong way, and a
non-trivial tail leads by 6+ years (4%). Full histogram in `output/begin_year_proxy/lag_histogram.csv` — one
notable artifact: a spike of 109 facilities at exactly lag=45, almost certainly the same population as the
~2.3% implausible `BEGIN_DATE` years already flagged in decision O5.

**Caveat:** `ENTERED_YEAR` is left-censored at 2015 (wayback floor) — any facility with `ENTERED_YEAR == 2015`
may have actually entered earlier, understating its true lag. Not corrected for here.

### 4. Post-exit false positives — the proxy's structural blind spot

For facility-years strictly after a wayback-confirmed exit:

| exit_source | facility-years | facilities | % proxy false-positive |
|---|---|---|---|
| cls (confirmed closure) | 93,351 | 17,145 | **99.5%** |
| other | 821 | 153 | 94.2% |
| dropout | 8 | 1 | 12.5% |

By years since exit — does it decay?

| years since exit | facility-years | % false-positive |
|---|---|---|
| 1 | 17,299 | 98.8% |
| 2 | 14,915 | 99.2% |
| 3 | 14,158 | 99.4% |
| 4 | 12,783 | 99.7% |
| 5 | 11,308 | 99.8% |
| 6 | 9,329 | 99.8% |
| 7 | 5,177 | 99.7% |
| 8 | 5,177 | 99.8% |
| 9 | 4,034 | 100.0% |

No decay — if anything it gets *slightly worse* with more years since exit, exactly as the ratchet structure
predicts. There is essentially no mechanism by which this proxy can ever detect a confirmed closure.

## Summary of what the evidence shows

- **Coverage gain is real**: adopting the proxy would fill 93% of the currently-`NA` 2005–2014 facility-years.
- **As an "is this facility currently operating" signal, it degrades toward useless** the further a
  facility-year sits past its begin-year — by construction, since it never resets. In the 2015–2025 window
  where it can be checked, its false-negative behavior is decent (sensitivity ~0.85–1.00) but its
  false-positive behavior is severe and gets worse over time (specificity 0.03 → 0.00); it essentially never
  correctly identifies a facility as *not* operating once enrolled.
- **As an "has this facility started operating by year Y" (onset-only) signal, it looks much more usable** —
  the lag distribution is concentrated and mostly in the plausible direction (0–1 year lead, 70% of cases).

The evidence doesn't resolve the decision — it depends on what the proxy would be used *for* (a same-year
operating flag vs. a first-observed-in-program-history flag are different claims), which is your call, not an
inference from these numbers.

## Options (not a recommendation)

- (a) Don't adopt it — leave 2005–2014 `operating` as `NA`, consistent with dataset 1's "strictly raw, no
  imputation" discipline (O2).
- (b) Adopt it *only* as an onset/entry signal (e.g. "facility had begun at least one program by year Y"),
  never as a stand-in for "is operating in year Y" — the lag evidence supports this narrower use much better
  than the agreement evidence supports the broader one.
- (c) Adopt it with an explicit expiration — e.g. combine with `EXITED_YEAR` where available to cap the
  proxy's "operating" claim at a known exit, accepting it still can't say anything for facilities with no
  wayback spell at all (the un-covered case this proxy exists to help with).
