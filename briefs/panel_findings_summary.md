# CAA Panel — Findings Summary

*Meeting one-pager. Every figure traces to `output/panel_profile/*.csv` (regenerated from the built panels)
or to the nuance IDs in `briefs/panel_construction_decisions.md`. Panel window 2005–2025; wayback
operating/program status exists only 2015–2025.*

---

## 1. Scale & coverage

Balanced facility × year (2005–2025). "Observed" = a 0 count is a real zero; "unobserved" = `NA`.

| Panel | Facilities | Facility-years | Observed (event) | Observed (operating) | **Unobserved (NA)** |
|---|--:|--:|--:|--:|--:|
| Universe | 135,213 | 2,839,473 | 26.1% | 27.5% | **46.4%** |
| Major/SynMin | 45,423 | 953,883 | 47.7% | 16.4% | **35.9%** |
| Electric | 3,025 | 63,525 | 67.0% | 9.8% | **23.2%** |

> **Concern:** nearly **half** of universe facility-years are `NA` (not zero). Much of that is structural — the
> *operating* channel that turns a quiet year into a true zero exists only **2015–2025**, so a pre-2015 year is
> observed only if a regulatory **event** landed; add closed/never-observed facilities. Counts must be read on
> the observed subset; a mean over all cells silently mixes in missingness.

## 2. Key measures (per **observed** facility-year)

Mean count (share of observed years with ≥1).

| Measure | Universe | Major/SynMin | Electric |
|---|--:|--:|--:|
| Inspections | 0.81 (40%) | 1.44 (60%) | 2.43 (68%) |
| Violations | 0.05 (3%) | 0.09 (6%) | 0.09 (6%) |
| Enforcement | 0.17 (7%) | 0.30 (11%) | 0.27 (10%) |
| Certifications | 1.47 (17%) | 3.37 (39%) | 6.05 (67%) |
| Stack tests | 0.37 (8%) | 0.83 (16%) | 2.36 (32%) |

Intensity rises down the funnel; violations & enforcement are rare everywhere (~3–11%).

---

## 3. ⚠ Duplicate load (counts include **all** rows; duplication is flagged, not dropped)

Share of each family's rows that are duplicates (`n_*_dup / n_*`), observed facility-years.

| Family | Universe | Major/SynMin | Electric | Note |
|---|--:|--:|--:|---|
| **Certifications** | **81%** | **81%** | **81%** | one raw row per program/pollutant |
| **Informal enforcement** | **48%** | **48%** | **48%** | near-all byte-identical repeats |
| Enforcement (pooled) | 36% | 36% | 34% | |
| Formal enforcement | 1% | 1% | 1% | re-entries, none byte-identical |
| Inspections | ~0% | ~0% | ~0% | |
| Violations / Stack tests | 0% | 0% | 0% | none by construction |

> **Concern:** raw cert and informal-enforcement counts are inflated ~5× and ~2×. Use the headline count for
> "records," and `count − dup` for distinct events. **Do not** treat raw cert volume as activity.

## 4. ⚠ Penalties

| Panel | Facility-years w/ penalty | Total | Mean | Max | **Duplicate $** |
|---|--:|--:|--:|--:|--:|
| Universe | 34,832 | $4.483 B | $128,696 | $64.5 M | **$206.0 M (4.6%)** |
| Major/SynMin | 25,456 | $3.126 B | $122,798 | $49.5 M | **$152.2 M (4.9%)** |
| Electric | 2,119 | $457.5 M | $215,899 | $18.0 M | **$52.9 M (11.6%)** |

> **Concerns:** (a) **Multi-facility settlements are broadcast** — one penalty is repeated across every
> co-defendant, so **penalties must not be summed across facilities.** (b) Duplicate penalty rows are few
> (284 in universe) but high-value, so they carry 4.6% of dollars — 11.6% for electric (a handful of large
> re-entered settlements).

## 5. ⚠ Data-quality caveats that can bite an analysis

| # | Finding | Magnitude | Why it matters |
|---|---|---|---|
| C1 | **Pre-2015 has no operating status** | operating/program flags exist only 2015–2025 | Before 2015 a quiet year is `NA` (observable only via an event); the operating-based structural-zero recovery and `prog_*_active` don't exist. |
| C2 | **Facility exits: `dropout` unadjudicable** | 11,801 dropouts vs 18,802 clean `CLS` (of 30,774 exits) | A "dropout" (vanished from ICIS) may be a real closure or an extract artifact — only **1 of 11,801** ever generates a later event, so events can't tell them apart. Trust `CLS`; treat `dropout` as an upper bound. |
| C3 | **Unplaceable / bad coordinates** | 15,730 no coordinate; **1,699 gross coord errors** (>5 km, up to ~1,970 km); 4,069 county names unresolvable (mostly CT) | No coordinate → no county, no attainment. Gross errors misplace facilities across state lines. |
| C4 | **Program-active forced zeros** | 2.18% (61,397) of present facility-years have **no** PROGRAMS record → all 8 `prog_*_active = 0` | For those, `0` may mean "extract missing," not "not enrolled." |
| C5 | **Reopenings collapsed in spell summary** | 519 facilities open→close→reopen (373 universe) | `entered_year`/`exited_year` treat these as one continuous spell; interior closed years are `NA` (not 0) unless an event lands. Year-varying `operating` keeps the true sequence. |
| C6 | **HPV status ≠ HPV count** | universe: 34,576 `hpv_active` fac-yrs vs Σ`n_hpv` = 24,403 | `n_hpv` tags the recorded year; `hpv_active` spans the spell (69% of spells cross ≥1 year). Use the right one. |
| C7 | **Cert under-coverage of majors** | only ~62%/yr of "Major" facilities show a cert | Class-major ≠ Title V annual certifier; don't assume a cert per major. |
| C8 | **Undated events dropped** | 9.2% of violations have no parseable date | Dropped, never imputed — a coverage floor on violations. |
| C9 | **Early-year violation sparsity is an artifact** | ramps up over the window | Reporting coverage, **not** a real decline — don't read a trend. |
| C10 | **Attainment is narrow** | PM2.5 (2012 NAAQS) only, 2016–2025, electric-only; 127 electric facilities ever nonattainment (4.2%), 34,325 fac-yrs `NA` | Treatment coverage is thin; ozone/SO₂/lead not built. |

---

### One-line takeaways for the room
1. **~46% of universe cells are `NA`, not 0** — pre-2015 + unobserved; never average over raw cells.
2. **Certs are 81% duplicates, informal enforcement 48%** — counts now expose this; use `count − dup`.
3. **Never sum penalties across facilities** (multi-facility broadcast); 4.6–11.6% of $ are duplicate rows.
4. **`dropout` exits (11,801) can't be verified** — closures vs artifacts are indistinguishable.
5. **Geography gates:** 15,730 facilities unplaceable, 1,699 grossly mis-coordinated.
