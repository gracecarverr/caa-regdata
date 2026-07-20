# 03_build_functions.R — reference

The shared facility × year panel recipe. All three sample panels are `build_panel()` run over a different
facility filter. Extracted **verbatim** from the former standalone panel scripts (`universe.R`,
`major_synmin.R`, `electric.R`) — the refactor was verified to reproduce byte-identical panel output.

Depends on `YEARS` (defined in `03_build_parameters.R`) being in scope when `build_panel()` runs, and on the
cleaned assets in `data/processed/` + `spine`/`attainment` in `data/panels/`.

## Top-level entry point

### `build_panel(facs, treatment = FALSE)`
Returns the finished balanced panel for the facilities in `facs` (a filtered slice of the spine):

1. aggregate the five sources to facility-year counts (`agg_*`), full-joined;
2. build the balanced `PGM_SYS_ID × YEARS` rectangle (unobserved cells `NA`, observed-no-event `0`);
3. add `any_*` flags; join the spine attributes; attach HPV-interval status, penalty, and wayback status;
4. `code_known_zeros()` (sets `obs_source`, fills structural zeros);
5. if `treatment = TRUE`: `attach_pm25_attainment()` and append the 4 treatment columns;
6. select the canonical column order and arrange by `PGM_SYS_ID, year`.

`treatment = FALSE` → `universe` / `major_synmin`; `treatment = TRUE` → `electric`.

## Helpers

| function | what it returns |
|----------|-----------------|
| `rd(name, cols)` | reads `data/processed/<name>.csv.gz`, keeping `cols`; `PGM_SYS_ID`/`year`/`dup` typed, rest character |
| `agg_inspections(ids)` | facility-year inspection counts (all rows) + FCE/PCE + agency splits + `n_inspections_dup` / `_dup_exact` |
| `agg_violations(ids)` | violations (all rows) + HPV/FRV + program + agency splits; asserts zero dups |
| `agg_enforcement(ids)` | formal+informal pooled (all rows): `n_enforcement` + type/agency splits + `n_enforcement_dup` / `_dup_exact` and formal/informal `_dup` / `_dup_exact`; `n_penalties` = formal rows with a positive `$` penalty (count companion to `penalty_amount`) + `n_penalties_dup` = those on `dup>0` rows |
| `agg_certs(ids)` | `n_certs` (all rows) + deviation count + `n_certs_dup` / `_dup_exact` |
| `agg_stacktests(ids)` | stack tests (all rows) + pass/fail; asserts zero dups |
| `attach_hpv_status(panel, ids)` | interval-based `hpv_active` / `hpv_active_1mo` from the HPV spell (union of overlapping spells; open spells day-zero-year-only). Keeps `dup==0` — status flag, not a count; duplicate spells are output-identical |
| `attach_penalty(panel, ids)` | `penalty_amount` = Σ formal penalties over **all** rows (0/none → `NA`) + `penalty_amount_dup` = Σ penalty on `dup>0` rows |
| `attach_wayback(panel, ids)` | year-varying `op_status_code`, `operating`, and 8 `prog_*_active` flags (2015–2025) |
| `attach_pm25_attainment(panel)` | `pm25_status`, `pm25_area`, `naa_pm25_2012`, `any_naa` (treatment panels only) |
| `code_known_zeros(panel)` | sets `obs_source ∈ {event, operating, unobserved}`; fills `NA→0` across `COUNT_COLS` for known-operating zero-event rows |

## Column vectors

- `ATTR_COLS` — spine attributes carried onto every panel.
- `WAYBACK_COLS` — the year-varying status block.
- `PANEL_COLS` — canonical order for `universe`/`major_synmin`; `TREATMENT_COLS` appended for `electric`.
- `COUNT_COLS` — the measures eligible for known-zero filling (all `n_*`/`any_*`/HPV flags, incl.
  `n_penalties` / `n_penalties_dup`; **not** `penalty_amount` / `_dup`, which stay NA-when-none).

## Load-bearing invariants (don't change without re-verifying panel output)

- **`dup==0`** selects event-level rows; `_raw` counts use all rows. Never dedup upstream.
- **Order** in `build_panel()` matters: `attach_wayback` must precede `code_known_zeros` (needs `operating`);
  `attach_hpv_status` must precede it too (so `hpv_active` exists to fill).
- **Known-zero coding only turns `NA→0`**, never overwrites a positive count; `penalty_amount` is exempt.
- **HPV union** (not sum) of overlapping spells; open spells are **day-zero-year-only** (conservative).

To re-verify after a change: rebuild a panel with the change and compare `gzip -dc panel.csv.gz | md5`
against a baseline built without it. A change that alters panel output must be surfaced, not silently
accepted (project rule).
