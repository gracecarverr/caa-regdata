# output — generated tables, figures, and run records

Generated artifacts that are **products of code**, not inputs. Rebuilt by re-running the pipeline /
diagnostics; no file here is hand-edited (tweak the script, not the output — project rule).

| path | produced by | what |
|------|-------------|------|
| `sessionInfo.txt` | `code/00_setup/00_setup.R` | R + package versions for the last run (reproducibility record). **Not tracked** (rewritten every run — see `.gitignore`). |
| `tables/*.tex` | `code/diagnostics/05_panel_summaries.R` | `booktabs` LaTeX fragments summarizing the built panels, one `\input`-able `.tex` per table, plus a compilable `panel_summaries.tex` wrapper. Every cell is computed from the panels — no hand-entered numbers. |
| `panel_profile/*.csv` | `code/diagnostics/06_panel_profile.R` | Broader exploratory characterization of the three sample panels: five-number summaries, categorical frequencies, binary-flag prevalence, per-year coverage, by-state counts, duplication and penalty summaries. Feeds `docs/panels.html`. |
| `figures/*.png` | `code/diagnostics/06_panel_profile.R` | Companion figures to `panel_profile/`: distributions, ECDFs, activity/coverage/operating time series, penalty distribution, count correlations, electric PM2.5 exposure. |
| `majsyn_operating/*.csv` | `code/diagnostics/07_majsyn_operating_profile.R` | Focused profile of the `major_synmin` panel's operating dynamics: sample overview, facilities/activity per year, observation-source composition, class/industry mix by state, program enrollment, HPV/penalty summaries. |
| `figures/majsyn_operating/*.png` | `code/diagnostics/07_majsyn_operating_profile.R` | Companion figures to `majsyn_operating/`: panel shape, distributions, ECDFs, activity over time, obs-source composition, class/industry mix, program enrollment, HPV & penalties, facility maps. |
| `coord_county_check/*.csv` | `code/diagnostics/coord_county_check/coord_county_check.R` | Per-facility coordinate-vs-ICIS-county consistency check: match/mismatch status, distances, and coordinate pathology flags, by facility and by state. See the script's own README for the method and findings. |
| `hpv_spell_diagnostics/*.csv.gz` | `code/diagnostics/08_hpv_spell_diagnostics.R`, `09_hpv_facility_year_rules.R` | Record-grain HPV violation diagnostics (`records.csv.gz`) and a facility-year mapping-rule comparison (`facility_year_rules.csv.gz`) — built to inform (not construct) the HPV spell/collapse decisions in `code/04_datasets`. See `briefs/datasets/dataset_construction_decisions.md` Part D. |

Compile the panel-summary wrapper with `pdflatex`/`xelatex` on a machine that has the `booktabs` package
(none is needed to *generate* the `.tex`).

> The documentation **site** is written to `docs/index.html` (committed, GitHub Pages), not here — see
> `code/diagnostics/build_site.R`. Everything under `output/` is currently **tracked** (a committed snapshot
> alongside the paper/site) except `sessionInfo.txt`, which is gitignored as a volatile per-run record.
