# output — generated tables, figures, and run records

Generated artifacts that are **products of code**, not inputs. Rebuilt by re-running the pipeline /
diagnostics; no file here is hand-edited (tweak the script, not the output — project rule).

| path | produced by | what |
|------|-------------|------|
| `sessionInfo.txt` | `code/00_setup/00_setup.R` | R + package versions for the last run (reproducibility record). **Not tracked** (rewritten every run — see `.gitignore`). |
| `tables/*.tex` | **stale** — was `code/diagnostics/05_panel_summaries.R`, archived 2026-07-28 with no direct replacement | `booktabs` LaTeX fragments summarizing the old three-sample-panel layer. Files still on disk (dated 2026-07-28, pre-archival) are leftovers, not a current build output — nothing in this repo writes to `output/tables/` anymore. Delete or regenerate a new summary-table script against the current two-panel layer if these are still wanted. |
| `panel_profile/*.csv` | `code/diagnostics/18_panel_profile.R` | Exploratory characterization of the two current continuous panels (`major_synmin_2015_2025`, `electric_2015_2025`): coverage (`OBS_SOURCE` composition), count-measure distributions, HPV-active rate, penalty distribution, geography, coordinate coverage, entry/exit censoring, electric-is-a-subset-of-major_synmin comparison. Feeds `docs/panels.html`. |
| `figures/panels/*.png` | `code/diagnostics/18_panel_profile.R` | Companion figures to `panel_profile/` for the two current panels: coverage/facility-count/HPV-active time series and related plots. |
| `hpv_spell_diagnostics/*.csv.gz` | `code/diagnostics/08_hpv_spell_diagnostics.R`, `09_hpv_facility_year_rules.R` | Record-grain HPV violation diagnostics (`records.csv.gz`) and a facility-year mapping-rule comparison (`facility_year_rules.csv.gz`) — built to inform (not construct) the HPV spell/collapse decisions in `code/03_datasets`. See `briefs/datasets/dataset_construction_decisions.md` Part D. |
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

> The documentation **site** is written to `docs/raw_data.html` + `docs/index.html` + `docs/databases.html` +
> `docs/panels.html` (committed, GitHub Pages), not here — see `code/diagnostics/build_site.R`. Everything
> under `output/` is currently **tracked** (a committed snapshot alongside the paper/site) except
> `sessionInfo.txt`, which is gitignored as a volatile per-run record.
