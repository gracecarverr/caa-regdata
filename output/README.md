# output — generated tables, figures, and run records

Generated artifacts that are **products of code**, not inputs. Rebuilt by re-running the pipeline /
diagnostics; no file here is hand-edited (tweak the script, not the output — project rule).

| path | produced by | what |
|------|-------------|------|
| `sessionInfo.txt` | `code/00_setup/00_setup.R` | R + package versions for the last run (reproducibility record). **Not tracked** (rewritten every run — see `.gitignore`). |
| `hpv_spell_diagnostics/*.csv.gz` | `code/diagnostics/08_hpv_spell_diagnostics.R`, `09_hpv_facility_year_rules.R` | Record-grain HPV violation diagnostics (`records.csv.gz`) and a facility-year mapping-rule comparison (`facility_year_rules.csv.gz`) — built to inform (not construct) the HPV spell/collapse decisions in `code/04_datasets`. See `briefs/datasets/dataset_construction_decisions.md` Part D. |

> Panel-layer output (`tables/*.tex` from `05_panel_summaries.R`, `panel_profile/*.csv` + companion figures
> from `06_panel_profile.R`, `majsyn_operating/*.csv` + figures from `07_majsyn_operating_profile.R`,
> `coord_county_check/*.csv`) moved to the CAA_Project repo alongside the diagnostics that produce them
> (2026-07-23).

> The documentation **site** is written to `docs/index.html` (committed, GitHub Pages), not here — see
> `code/diagnostics/build_site.R`. Everything under `output/` is currently **tracked** (a committed snapshot
> alongside the paper/site) except `sessionInfo.txt`, which is gitignored as a volatile per-run record.
