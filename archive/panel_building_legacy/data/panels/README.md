# data/panels — derived spine and sample panels

Built by [`code/03_panel_building`](../../code/03_panel_building/README.md) from the processed assets. All
files are gzip-compressed CSV, **gitignored**, rebuilt from code. This is where sample selection and
aggregation happen (cleaning did none of that).

| file | grain | what | built by |
|------|-------|------|----------|
| `spine.csv.gz` | one row per facility | the **facility spine**: ever-active universe + coordinates + county + current-snapshot attributes + static `emits_*`/`prog_*` profiles + reconstructed entry/exit spells | `00_spine.R` |
| `universe.csv.gz` | facility × year | all ever-active facilities (CONUS) — 111 cols | `03_build.R` |
| `major_synmin.csv.gz` | facility × year | + Major / Synthetic Minor class — 111 cols | `03_build.R` |
| `electric.csv.gz` | facility × year | + electric utilities (NAICS 2211 / SIC 4911) — 111 cols | `03_build.R` |
| `_preview/` | — | first-N-row plain-CSV previews for eyeballing (gitignored scratch, from `code/diagnostics/preview_panels.R`) | — |

> A PM2.5-attainment treatment block used to be attached to `electric.csv.gz` (`pm25_status`, `pm25_area`,
> `naa_pm25_2012`, `any_naa`, via `01_attainment.R`). That code was removed from this repo entirely on
> 2026-07-27 — already synced to the sibling `CAA_Project` repo — so `electric.csv.gz` no longer carries
> those columns; see decision W10 in `briefs/panel/panel_construction_decisions.md`.

## The sample panels

All are the **same recipe** over a different facility filter — column blocks, count semantics
(all-row counts + `_dup` / `_dup_exact` duplicate-load indicators), and the load-bearing **zero-vs-NA**
convention (`obs_source ∈ {event, operating, unobserved}`) are documented once in
[`code/03_panel_building/README.md`](../../code/03_panel_building/README.md). Construction rationale is in
[`briefs/panel/panel_construction_decisions.md`](../../briefs/panel/panel_construction_decisions.md) (Part C, decisions
P1–P8); open caveats in [`briefs/panel/panel_open_questions.md`](../../briefs/panel/panel_open_questions.md).
**Column-by-column definitions** for every built field in the spine and the three sample panels:
[`docs/data_dictionary_derived.md`](../../docs/data_dictionary_derived.md).

## Key things to remember when using a panel

- **`0` ≠ `NA`.** Within an *observed* facility-year (`obs_source ∈ {event, operating}`) a zero count is a
  true zero; an *unobserved* facility-year is `NA` (includes closed/CLS and all pre-2015 years). Don't treat
  `NA` as `0`.
- **`n_*` count all rows — nothing is deduped.** Duplicate load is surfaced by `_dup` (event-key repeats)
  and `_dup_exact` (byte-identical) on inspections, enforcement (+ formal/informal), and certs; recover
  event-distinct counts as `n_x − n_x_dup`. `penalty_amount` sums all formal rows, with `penalty_amount_dup`
  giving the duplicate dollars; `n_penalties` is the **count** of formal rows carrying a positive `$` penalty
  (with `n_penalties_dup` for the duplicate rows) — the count companion to `penalty_amount`'s dollar sum.
  Note the coding differs by design: `n_penalties` is a count, so it follows `0`≠`NA` (observed-no-penalty
  → `0`, unobserved → `NA`), whereas `penalty_amount` is `NA`-when-none — an observed facility-year with a
  formal action but no penalty dollars reads `n_penalties = 0` **and** `penalty_amount = NA`. (`hpv_active` is
  the lone `dup==0` exception — a status flag, not a count.)
- **Wayback status columns are 2015–2025 only** (`NA` for 2005–2014).
- **Facility class/industry are the current snapshot** applied to all years; program `prog_*` flags are
  ever-enrolled and undated (F6/N7). `program_begin_year` (facility-level, time-invariant) dates the
  *earliest* program enrollment from `ICIS-AIR_PROGRAMS.BEGIN_DATE`; `NA` where no program record. No close
  date exists, so this dates entry only.
