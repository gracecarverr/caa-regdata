# 03_panel_building — facility spine, attainment treatment, and the sample panels

**Stage inputs:** `data/processed/*.csv.gz` (cleaned assets) + `data/raw/{frs,us_counties,greenbook}`
**Stage outputs:** `data/panels/{spine,attainment,universe,major_synmin,electric}.csv.gz`
**Run:** `Rscript code/03_panel_building/03_build.R` — or stage 3 of `code/RUN_ALL.R`.

This is where sample selection, aggregation, and treatment happen (the cleaning stage did none of that). The
decisions here are documented in depth in `briefs/panel_construction_decisions.md` (find a decision by its
code, e.g. `F7`, `P3`, `W6`); the caveats in `briefs/panel_open_questions.md`.

## Build order & files

| file | role |
|------|------|
| `00_spine.R` | Builds the **facility spine** → `data/panels/spine.csv.gz`: one row per **ever-active** facility (≥1 event in `YEARS`), with coordinates (FRS via `REGISTRY_ID`), county (point-in-polygon), current-snapshot attributes, the two static profiles (`emits_*`, `prog_*`), and the reconstructed entry/exit spell summary. A derived construction, **not** a raw-source clean asset. |
| `01_attainment.R` | Builds the **PM2.5 (2012) attainment treatment** → `data/panels/attainment.csv.gz`: one row per facility-year inside a PM2.5 nonattainment/maintenance area. Runs **after** the spine (needs coordinates). Sub-county point-in-polygon; PM2.5-2016–2025 only. |
| `03_build.R` | **Driver** — runs the two above, then builds the sample panels by applying each `PANEL_SPECS` filter to the spine and calling `build_panel()`. |
| `03_build_functions.R` | The shared **panel recipe**: per-source aggregators, HPV-interval status, penalty, wayback status, known-zero coding, `attach_pm25_attainment`, and `build_panel()`. See `03_build_functions_README.md`. |
| `03_build_parameters.R` | `YEARS`, `CONUS`, and `PANEL_SPECS` (the per-panel filters + treatment flag). See `03_build_parameters_README.md`. |

## The sample panels

All three are the **same recipe** over a different facility filter (this is why the recipe lives in one
function, not three copied scripts):

| panel | cols | facilities in scope |
|-------|------|---------------------|
| `universe`     | 105 | all ever-active facilities (contiguous US + DC) |
| `major_synmin` | 105 | + Major / Synthetic Minor emissions class |
| `electric`     | 109 | + electric utilities (NAICS 2211 / SIC 4911), **with PM2.5 attainment treatment** (4 extra cols) |

## Shape (all sample panels)

Balanced **facility × year** (every in-scope facility × every year in `YEARS`, 2005–2025). Column blocks, in
order:

- **Inspections** `n_inspections`, `n_fce`, `n_pce` (FCE/PCE monitor type — overlap, need not sum),
  `n_insp_epa` / `n_insp_state` / `n_insp_local` (conducting agency — partition), and duplicate-load
  indicators `n_inspections_dup` / `n_inspections_dup_exact`.
- **Violations** `n_violations`, `n_hpv` / `n_frv` (high-priority = has an HPV day-zero date — partition),
  `n_viol_sip` / `n_viol_titlev` / `n_viol_nsps` / `n_viol_mact` / `n_viol_fesop` (program — overlap),
  `n_viol_epa` / `n_viol_state` / `n_viol_local` (agency — partition).
- **Enforcement** (formal + informal pooled) `n_enforcement` (all rows), `n_formal` / `n_informal`
  (partition), the action-type buckets `n_penalty_action`, `n_warning_letter`, `n_admin_np`,
  `n_civil_judicial`, `n_nov`, `n_admin_order` (exact `ENF_TYPE_DESC` matches — unmapped types dropped, so
  these need not sum), `n_enf_epa` / `n_enf_state` / `n_enf_local`, and duplicate-load indicators
  `n_enforcement_dup` / `n_enforcement_dup_exact` (+ `n_formal_dup` / `n_informal_dup` and their `_dup_exact`).
- **Certifications** `n_certs` (all rows), `n_certs_deviation`, and `n_certs_dup` / `n_certs_dup_exact`
  (~81% of cert rows are event-key duplicates).
- **Stack tests** `n_stack_tests`, `n_stack_pass`, `n_stack_fail` (Pending/Incomplete/N-A uncounted).
- **Any-flags** `any_inspections` / `any_violations` / `any_enforcement` / `any_certs` — `1` if the matching
  `n_*` > 0, else `0` (NA where the count is NA).
- **Observation source** `obs_source` — why a facility-year's counts are `0` vs `NA`: `event` (≥1 event of
  some measure that year), `operating` (no event, but OPERATING in that year's wayback snapshot → a **true
  structural zero**), `unobserved` (neither → `NA`).
- **Facility attributes** — the full facility spine (identity, geography, industry, class,
  `op_status_current_desc` = *current* snapshot, `emits_*`, `prog_*`, `n_programs`) plus the reconstructed
  entry/exit spell summary `entered_year` / `exited_year` / `exit_source` / `left_censored` / `right_censored`
  (time-invariant per facility).
- **Wayback status** (year-varying) `op_status_code` + `operating` (1 if code ∈ {OPR,TMP,SEA}) and
  `prog_{sip,titlev,nsps,mact,gact,neshap,fesop,nsr,psd,cfc}_active`. **Populated 2015–2025 only; `NA` for 2005–2014**
  (no snapshot exists — we cannot assert a status). See `briefs/panel_construction_decisions.md` §B.7 / F7.
- **HPV status** `hpv_active`, `hpv_active_1mo` — interval-based (in HPV status during any part of the year /
  for > 30 days), from the HPV spell, *distinct from* the recorded-year count `n_hpv`.
- **Penalty** `penalty_amount` — sum of formal-action penalties that facility-year over **all** rows
  (0 / none → NA); `penalty_amount_dup` — the dollars contributed by event-key duplicate rows.
- **Treatment** (electric only) `pm25_status`, `pm25_area`, `naa_pm25_2012`, `any_naa`.

Every `n_*` counts **all rows** — nothing is deduped. Duplicate load is surfaced (never removed) by the
`_dup` (event-key repeats) and `_dup_exact` (byte-identical repeats) indicators on the families that carry
duplicates (inspections, enforcement incl. formal/informal, certs); violations and stacktests have zero dups.
Recover event-distinct counts as `n_x − n_x_dup`. The HPV interval flag `hpv_active` is the one exception — a
status flag, not a count, so it still keys on `dup == 0` (output-identical, since duplicate spells repeat the
same interval).

### Count meaning (the load-bearing zero-vs-NA semantic)

A facility-year is **observed** (so a zero-count is a *true* zero) if `obs_source ∈ {event, operating}`:

- `0` — observed but had none of *this* measure. Observed either because it had ≥1 event of some measure
  (`obs_source == "event"`) **or** because the facility is OPERATING in that year's wayback snapshot
  (`operating == 1` → `obs_source == "operating"`), even with zero events.
- `NA` — `obs_source == "unobserved"`: no event **and** not known-operating (includes closed/`CLS` years and
  all pre-2015 years, where no snapshot exists). We cannot assert a zero.

The `operating` channel only ever turns an `NA` into a `0` (never overwrites a positive count), and
`penalty_amount` / `penalty_amount_dup` are exempt (their own `0`/none → `NA` rule). Recover the original
event-only semantics with `obs_source == "event"`.

## Adding a panel

Add one `list(name=, filter=, treatment=)` entry to `PANEL_SPECS` in `03_build_parameters.R`. No new code —
`build_panel()` handles the rest. (This replaces the old "copy the whole script and change the filter"
workflow; the recipe now lives in `03_build_functions.R` exactly once.)
