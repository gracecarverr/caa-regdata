# Sample panels

Standalone, explicit scripts — one per sample panel. Each picks a set of facilities and calls
`facility_year_panel()` (`R/panel.R`); there is no configurable builder. Copy a script and change the
facility filter to make a new panel.

| script | panel | facilities |
|---|---|---|
| [`universe.R`](universe.R) | `data/panels/universe.csv.gz` | all ever-active facilities (contiguous US) |
| [`major_synmin.R`](major_synmin.R) | `data/panels/major_synmin.csv.gz` | + Major / Synthetic Minor emissions class |
| [`electric.R`](electric.R) | `data/panels/electric.csv.gz` | + electric utilities (NAICS 2211 / SIC 4911), with PM2.5 attainment treatment |

## Shape (all sample panels)

Balanced **facility × year** (every in-scope facility × every year in the window). Columns:

- **Counts** `n_inspections`, `n_violations`, `n_enforcement`, `n_certs` — distinct events (`dup == 0`)
  that facility-year.
- **Facility attributes** — the full facility spine (identity, geography, industry, class, operating
  status, `emits_*`, `prog_*`, `n_programs`).

### Count meaning

- `0` — the facility-year was **observed** (≥ 1 event of some measure) but had none of *this* measure — a true zero.
- `NA` — the facility-year was **not observed** at all; we cannot assert a zero.

### Treatment (electric panel)

`attach_pm25_attainment()` adds `pm25_status` (N / M / NA), `pm25_area`, and `naa_pm25`
(1 nonattainment / 0 maintenance-or-attainment / NA outside the PM2.5 window or for an unplaceable facility).
