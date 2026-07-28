# output — generated tables, figures, and run records

Generated artifacts that are **products of code**, not inputs. Rebuilt by re-running the pipeline /
diagnostics; no file here is hand-edited (tweak the script, not the output — project rule).

| path | produced by | what |
|------|-------------|------|
| `sessionInfo.txt` | `code/00_setup/00_setup.R` | R + package versions for the last run (reproducibility record). **Not tracked** (rewritten every run — see `.gitignore`). |
| `tables/*.tex` | `code/diagnostics/05_panel_summaries.R` | `booktabs` LaTeX fragments summarizing the built panels, one `\input`-able `.tex` per table, plus a compilable `panel_summaries.tex` wrapper. Every cell is computed from the panels — no hand-entered numbers. |
| `panel_profile/*.csv` | `code/diagnostics/06_panel_profile.R` | Broader exploratory characterization of the three sample panels: five-number summaries, categorical frequencies, binary-flag prevalence, per-year coverage, by-state counts, duplication and penalty summaries. Feeds `docs/panels.html`. |
| `figures/*.png` | `code/diagnostics/06_panel_profile.R` | Companion figures to `panel_profile/`: distributions, ECDFs, activity/coverage/operating time series, penalty distribution, count correlations, electric PM2.5 exposure. |
| `majsyn_operating/*.csv` | `code/diagnostics/07_majsyn_operating_profile.R` | Focused profile of the `major_synmin` panel's operating dynamics: sample overview, facilities/activity per year, observation-source composition, class/industry mix by state, program enrollment, HPV/penalty summaries. **Not currently present on disk** — re-run the script to regenerate. |
| `figures/majsyn_operating/*.png` | `code/diagnostics/07_majsyn_operating_profile.R` | Companion figures to `majsyn_operating/`: panel shape, distributions, ECDFs, activity over time, obs-source composition, class/industry mix, program enrollment, HPV & penalties, facility maps. |
| `panel_deep_stats/*.csv` | `code/diagnostics/06b_panel_deep_stats.R` | Panel-layer stats `06_panel_profile.R` doesn't cover: spine-level ever-active count, per-panel reopen detection, coordinate-check gross/clean/NA breakdown, continuous-2015–2025 funnel. Backs figures cited in `panel_construction_decisions.md` / `panel_findings_summary.md`. |
| `coord_county_check/*.csv` | `code/diagnostics/coord_county_check/coord_county_check.R` | Per-facility coordinate-vs-ICIS-county consistency check: match/mismatch status, distances, and coordinate pathology flags, by facility and by state. See the script's own README for the method and findings. |
| `hpv_spell_diagnostics/*.csv.gz` | `code/diagnostics/08_hpv_spell_diagnostics.R`, `09_hpv_facility_year_rules.R` | Record-grain HPV violation diagnostics (`records.csv.gz`) and a facility-year mapping-rule comparison (`facility_year_rules.csv.gz`) — built to inform (not construct) the HPV spell/collapse decisions in `code/04_datasets`. See `briefs/datasets/dataset_construction_decisions.md` Part D. |
| `begin_year_proxy/*.csv` | `code/diagnostics/10_begin_year_proxy.R` | Whether `EARLIEST_PROGRAM_BEGIN_YEAR` (dataset 1) is usable as a pre-2015 operating-status proxy: coverage, agreement with wayback `OPERATING` where both exist, lag, post-exit false-positive rate. See `briefs/datasets/begin_year_operating_proxy.md`. |
| `afs_frs_match/*.csv` | `code/diagnostics/afs_frs_match/afs_icis_crosswalk.R` | AFS↔ICIS facility-id crosswalk linkability: hop1/hop2 coverage, unmatched breakdowns by status/state, candidate search, spine- and pre-2015-population-restricted coverage. See the script's own README and `briefs/datasets/afs_crosswalk_feasibility.md`. |
| `wayback_verify/*.csv` | `code/diagnostics/wayback_verify/wayback_verify.R` | Whether the staged ICIS-Air Wayback snapshots reproduce byte-for-byte from a live Wayback Machine capture, per staged year. See the script's own README. |
| `operating_profile/*.csv` + `figures/datasets/operating/*.png` | `code/diagnostics/11_operating_profile.R` | Exploratory profile of dataset 1 (`operating`): coverage, operating-status distribution, program-active prevalence, entry/exit spells, begin-year coverage. |
| `penalties_profile/*.csv` + `figures/datasets/penalties/*.png` | `code/diagnostics/12_penalties_profile.R` | Exploratory profile of dataset 3 (`penalties`): penalty-amount distribution, action/enforcement-type composition, multi-facility settlement structure. |
| `regulatory_profile/*.csv` + `figures/datasets/regulatory/*.png` | `code/diagnostics/13_regulatory_profile.R` | Exploratory profile of dataset 0 (`regulatory`): coverage, event-count distributions, facility-characteristic breakdowns. |
| `hpv_profile/*.csv` + `figures/datasets/hpv/*.png` | `code/diagnostics/14_hpv_profile.R` | Exploratory profile of datasets 2/2b (`hpv_spells`/`hpv_active`): spell-duration distribution, program frequency, HPV-active rate over time. |
| `coordinates_profile/*.csv` + `figures/datasets/coordinates/*.png` | `code/diagnostics/15_coordinates_profile.R` | Exploratory profile of dataset 4 (`coordinates`): coordinate coverage, coordinate-vs-ICIS-county error, `ICIS_COUNTY_FIPS` coverage/agreement, facility geography. |
| `pipeline_profile/*.csv` + `figures/datasets/pipeline/*.png` | `code/diagnostics/16_pipeline_profile.R` | Exploratory profile of dataset 6 (`pipeline`): linkage rate over time, HPV/FRV share, evaluation-to-enforcement lag distribution. |
| `emissions_profile/*.csv` + `figures/datasets/emissions/*.png` | `code/diagnostics/17_emissions_profile.R` | Exploratory profile of dataset 7 (`emissions`): coverage by program/year, pollutant totals, GHG over time. |

Compile the panel-summary wrapper with `pdflatex`/`xelatex` on a machine that has the `booktabs` package
(none is needed to *generate* the `.tex`).

> The documentation **site** is written to `docs/raw_data.html` + `docs/index.html` + `docs/databases.html` +
> `docs/panels.html` (committed, GitHub Pages), not here — see `code/diagnostics/build_site.R`. Everything
> under `output/` is currently **tracked** (a committed snapshot alongside the paper/site) except
> `sessionInfo.txt`, which is gitignored as a volatile per-run record.
