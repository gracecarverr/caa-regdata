# Sample panels

Standalone, explicit scripts — one per sample panel. Each is fully self-contained: it spells out the
`facility_year_panel()` recipe inline (no shared helpers, no configurable builder). Copy a script and
change the facility filter to make a new panel. The recipe mirrors the CAA_Project panel builder, so the
columns match CAA_Project's `universe` / `major_synmin` / `electric_attainment` panels.

Built on the derived facility spine (`00_spine.R` → `data/panels/spine.csv.gz`) and, for the electric
panel, the PM2.5 attainment treatment (`01_attainment.R` → `data/panels/attainment.csv.gz`).

| script | panel | cols | facilities |
|---|---|---|---|
| [`universe.R`](universe.R) | `data/panels/universe.csv.gz` | 93 | all ever-active facilities (contiguous US) |
| [`major_synmin.R`](major_synmin.R) | `data/panels/major_synmin.csv.gz` | 93 | + Major / Synthetic Minor emissions class |
| [`electric.R`](electric.R) | `data/panels/electric.csv.gz` | 97 | + electric utilities (NAICS 2211 / SIC 4911), with PM2.5 attainment treatment |

## Shape (all sample panels)

Balanced **facility × year** (every in-scope facility × every year in `YEARS`, 2005–2025). Column blocks,
in order:

- **Inspections** `n_inspections`, `n_fce`, `n_pce` (FCE/PCE monitor type — overlap, need not sum),
  `n_insp_epa` / `n_insp_state` / `n_insp_local` (conducting agency — partition).
- **Violations** `n_violations`, `n_hpv` / `n_frv` (high-priority = has an HPV day-zero date — partition),
  `n_viol_sip` / `n_viol_titlev` / `n_viol_nsps` / `n_viol_mact` / `n_viol_fesop` (program — overlap),
  `n_viol_epa` / `n_viol_state` / `n_viol_local` (agency — partition).
- **Enforcement** (formal + informal pooled) `n_enforcement`, `n_enforcement_raw` (all rows incl. dup
  artifacts, ~1.6×), `n_formal` / `n_informal` (partition), the action-type buckets `n_penalty_action`,
  `n_warning_letter`, `n_admin_np`, `n_civil_judicial`, `n_nov`, `n_admin_order` (exact `ENF_TYPE_DESC`
  matches — unmapped types dropped, so these need not sum), `n_enf_epa` / `n_enf_state` / `n_enf_local`.
- **Certifications** `n_certs`, `n_certs_raw` (~5×), `n_certs_deviation`.
- **Stack tests** `n_stack_tests`, `n_stack_pass`, `n_stack_fail` (Pending/Incomplete/N-A uncounted).
- **Any-flags** `any_inspections` / `any_violations` / `any_enforcement` / `any_certs` — `1` if the
  matching `n_*` > 0, else `0` (NA where the count is NA).
- **Observation source** `obs_source` — why a facility-year's counts are `0` vs `NA`: `event` (≥ 1 event of
  some measure that year — original semantics), `operating` (no event, but the facility is OPERATING in that
  year's wayback snapshot, so a zero-event year is a **true structural zero**), `unobserved` (neither → `NA`).
- **Facility attributes** — the full facility spine (identity, geography, industry, class, `op_status_current_desc`
  = *current* snapshot, `emits_*`, `prog_*`, `n_programs`) plus the reconstructed entry/exit spell summary
  `entered_year` / `exited_year` / `exit_source` / `left_censored` / `right_censored` (time-invariant per facility).
- **Wayback status** (year-varying) `op_status_code` (raw ICIS code) + `operating` (1 if code ∈ {OPR,TMP,SEA})
  and `prog_{sip,titlev,nsps,mact,neshap,fesop,nsr,psd}_active` — historical operating & program status from the
  11 annual ICIS-AIR wayback snapshots. **Populated 2015–2025 only; `NA` for 2005–2014** (no snapshot exists —
  we cannot assert a status). See `docs/panel_construction_decisions.md` §B.7 / F7.
- **HPV status** `hpv_active`, `hpv_active_1mo` — interval-based (in HPV status during any part of the
  year / for > 30 days), from the HPV spell, *distinct from* the recorded-year count `n_hpv`.
- **Penalty** `penalty_amount` — sum of formal-action penalties that facility-year (0 / none → NA).
- **Treatment** (electric only) `pm25_status`, `pm25_area`, `naa_pm25_2012`, `any_naa`.

Every `n_*` is **event-level** (`dup == 0`) unless the name ends in `_raw`.

### Count meaning

A facility-year is **observed** (so a zero-count is a *true* zero) if `obs_source ∈ {event, operating}`:

- `0` — observed but had none of *this* measure. Observed either because it had ≥ 1 event of some measure
  (`obs_source == "event"`) **or** because the facility is OPERATING in that year's wayback snapshot
  (`operating == 1` → `obs_source == "operating"`), even with zero events.
- `NA` — `obs_source == "unobserved"`: no event **and** not known-operating (includes closed/`CLS` years and
  all pre-2015 years, where no snapshot exists). We cannot assert a zero.

The `operating` channel is what lets us code known-zeros for facilities that exist but had a quiet year;
it only ever turns an `NA` into a `0` (never overwrites a positive count), and `penalty_amount` is exempt
(it keeps its own `0`/none → `NA` rule). Recover the original event-only semantics with `obs_source == "event"`.

### Treatment (electric panel)

`attach_pm25_attainment()` adds `pm25_status` (N / M / NA), `pm25_area`, `naa_pm25_2012`
(1 nonattainment / 0 maintenance-or-attainment / NA outside the 2016–2025 PM2.5 window or for an
unplaceable facility), and `any_naa` (identical to `naa_pm25_2012` while PM2.5 is the only standard built).
