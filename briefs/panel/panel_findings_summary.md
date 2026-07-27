# CAA Panel — Findings Summary

*Meeting one-pager. Every figure traces to `output/panel_profile/*.csv` (regenerated from the built panels)
or to the nuance IDs in `panel_construction_decisions.md`. Panel window 2005–2025; wayback
operating/program status exists only 2015–2025.*

---

## 1. Scale & coverage

Balanced facility × year (2005–2025). "Observed" = a 0 count is a real zero; "unobserved" = `NA`.

| Panel | Facilities | Facility-years | Observed (event) | Observed (operating) | **Unobserved (NA)** |
|---|--:|--:|--:|--:|--:|
| Universe | 132,461 | 2,781,681 | 26.3% | 25.1% | **48.6%** |
| Major/SynMin | 45,212 | 949,452 | 47.6% | 15.0% | **37.3%** |
| Electric | 3,015 | 63,315 | 66.9% | 9.1% | **24.0%** |

*(Figures as of 2026-07-27, regenerated via `code/diagnostics/06_panel_profile.R`; were 135,213/45,423/3,025
facilities before the 2026-07-26 ICIS-AIR refresh.)*

> **Concern:** nearly **half** (48.6%) of universe facility-years are `NA` (not zero). Much of that is structural — the
> *operating* channel that turns a quiet year into a true zero exists only **2015–2025**, so a pre-2015 year is
> observed only if a regulatory **event** landed; add closed/never-observed facilities. Counts must be read on
> the observed subset; a mean over all cells silently mixes in missingness.

## 2. Key measures (per **observed** facility-year)

Mean count (share of observed years with ≥1).

| Measure | Universe | Major/SynMin | Electric |
|---|--:|--:|--:|
| Inspections | 0.85 (42%) | 1.46 (61%) | 2.44 (68%) |
| Violations | 0.05 (4%) | 0.09 (7%) | 0.09 (6%) |
| Enforcement | 0.19 (8%) | 0.31 (11%) | 0.28 (10%) |
| Certifications | 1.57 (18%) | 3.46 (40%) | 6.13 (68%) |
| Stack tests | 0.37 (8%) | 0.82 (16%) | 2.35 (32%) |

*(As of 2026-07-27.)*

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

*(As of 2026-07-27 — these percentages are stable to the ICIS-AIR refresh, unlike the absolute counts above.)*

> **Concern:** raw cert and informal-enforcement counts are inflated ~5× and ~2×. Use the headline count for
> "records," and `count − dup` for distinct events. **Do not** treat raw cert volume as activity.

## 4. ⚠ Penalties

| Panel | Facility-years w/ penalty | Total | Mean | Max | **Duplicate $** |
|---|--:|--:|--:|--:|--:|
| Universe | 34,824 | $4.485 B | $128,783 | $64.5 M | **$205.9 M (4.6%)** |
| Major/SynMin | 25,438 | $3.129 B | $123,005 | $49.5 M | **$152.0 M (4.9%)** |
| Electric | 2,122 | $457.5 M | $215,600 | $18.0 M | **$52.9 M (11.6%)** |

*(As of 2026-07-27; were 34,832/$4.483B, 25,456/$3.126B, 2,119/$457.5M before the refresh.)*

> **Concerns:** (a) **Multi-facility settlements are broadcast** — one penalty is repeated across every
> co-defendant, so **penalties must not be summed across facilities.** (b) Duplicate penalty rows are few
> (238 in universe, was 284) but high-value, so they carry 4.6% of dollars — 11.6% for electric (a handful of
> large re-entered settlements).

## 5. ⚠ Data-quality caveats that can bite an analysis

| # | Finding | Magnitude | Why it matters |
|---|---|---|---|
| C1 | **Pre-2015 has no operating status** | operating/program flags exist only 2015–2025 | Before 2015 a quiet year is `NA` (observable only via an event); the operating-based structural-zero recovery and `prog_*_active` don't exist. |
| C2 | **Facility exits: `dropout` unadjudicable** | 11,801 dropouts vs 18,802 clean `CLS` (of 30,774 exits) | A "dropout" (vanished from ICIS) may be a real closure or an extract artifact — only **1 of 11,801** ever generates a later event, so events can't tell them apart. Trust `CLS`; treat `dropout` as an upper bound. |
| C3 | **Unplaceable / bad coordinates** | 14,294 no coordinate (was 15,730); **1,699 gross coord errors** (>5 km, unchanged); 4,813 county names unresolvable (was 4,069, mostly CT) | No coordinate → no county. Gross errors misplace facilities across state lines. |
| C4 | **Program-active forced zeros** | 2.18% (61,397) of present facility-years have **no** PROGRAMS record → all 8 `prog_*_active = 0` (last measured 2026-07-18, not independently re-verified 2026-07-27 — see N10) | For those, `0` may mean "extract missing," not "not enrolled." |
| C5 | **Reopenings collapsed in spell summary** | ~519 facilities open→close→reopen repo-wide (presumed stable — Wayback data itself doesn't drift with ICIS-AIR refreshes, same as the confirmed-stable 583/220,579 broader reopen count; not independently re-verified this exact narrower figure), **418 reach the universe panel** (was 373) | `entered_year`/`exited_year` treat these as one continuous spell; interior closed years are `NA` (not 0) unless an event lands. Year-varying `operating` keeps the true sequence. |
| C6 | **HPV status ≠ HPV count** | universe-level total not independently re-verified this pass (last measured: 34,576 `hpv_active` fac-yrs vs Σ`n_hpv` = 24,403); the underlying `hpv_active` dataset total is now 35,417 (was 35,186) | `n_hpv` tags the recorded year; `hpv_active` spans the spell (69% of spells cross ≥1 year, last measured). Use the right one. |
| C7 | **Major emissions cert under-coverage** | 72.7% coverage in 2025 (9,456 of 12,998 operating, was 72.5%/9,428 of 13,012), declining from 77.6% in 2015 (was 77.5%); 3,542 major operating facs have no reported cert (was 3,584) | Title V requires annual certs for majors. Gap is **reporting lag** — 2025 certs sparse in ICIS. Practical: don't assume a cert per major per year; use `any_certs` flag. |
| C8 | **Undated events dropped** | 9.2% of violations have no parseable date | Dropped, never imputed — a coverage floor on violations. |
| C9 | **Early-year violation sparsity is an artifact** | ramps up over the window | Reporting coverage, **not** a real decline — don't read a trend. |

---

### One-line takeaways for the room (figures as of 2026-07-27)
1. **~49% of universe cells are `NA`, not 0** — pre-2015 + unobserved; never average over raw cells.
2. **Certs are 81% duplicates, informal enforcement 48%** — counts now expose this; use `count − dup`.
3. **Never sum penalties across facilities** (multi-facility broadcast); 4.6–11.6% of $ are duplicate rows.
4. **`dropout` exits (11,801) can't be verified** — closures vs artifacts are indistinguishable.
5. **Geography gates:** 14,294 facilities unplaceable (was 15,730), 1,699 grossly mis-coordinated.
