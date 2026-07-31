# output — generated tables, figures, and run records

Generated artifacts that are **products of code**, not inputs. Every file here traces to a script and a
logged run — the reproducibility rule this repo follows (`CLAUDE.md`): if a number here can't be traced back
to the script that produced it, that's a bug, not a shortcut. Rebuilt by re-running the pipeline /
diagnostics; no file here is hand-edited (tweak the script, not the output — project rule). Most of this
folder is produced by `code/diagnostics/` (hand-run, not part of `code/RUN_ALL.R`) profiling the datasets
(`code/03_datasets/`) and panels (`code/04_panel_building/`) that ARE part of the build — see that folder's
own README for which of its scripts are standing per-asset companions vs. one-off investigations.

| path | produced by | what |
|------|-------------|------|
| `sessionInfo.txt` | `code/00_setup/00_setup.R` | R + package versions for the last run (reproducibility record). **Not tracked** (rewritten every run — see `.gitignore`). |
| `tables/*.tex` | **stale** — was `code/diagnostics/05_panel_summaries.R`, archived 2026-07-28 with no direct replacement | `booktabs` LaTeX fragments summarizing the old three-sample-panel layer. Files still on disk (dated 2026-07-28, pre-archival) are leftovers, not a current build output — nothing in this repo writes to `output/tables/` anymore. Delete or regenerate a new summary-table script against the current two-panel layer if these are still wanted. |
| `panel_profile/*.csv` + `figures/panels/panel_{coverage_over_time,hpv_active_over_time,count_distributions,penalty_dist,state_composition,facility_count_over_time,mean_counts_over_time,violations_enforcement}.png` | `code/diagnostics/18_panel_profile.R` | Exploratory characterization of the two current continuous panels (`major_synmin_2015_2025`, `electric_2015_2025`): coverage (`OBS_SOURCE` composition), count-measure distributions, HPV-active rate, penalty distribution, geography, coordinate coverage, entry/exit censoring, electric-is-a-subset-of-major_synmin comparison. Feeds `docs/panels.html`. |
| `panel_profile/{electric_vs_other_summary,electric_vs_other_by_year,lag_future_violations,lag_future_violations_bin_summary}.csv` + `figures/panels/panel_{electric_vs_other_means,electric_vs_other_over_time,lag_future_violations}.png` | `code/diagnostics/19_panel_electric_lag_profile.R` | Two cuts `18` doesn't cover: electric vs. **other** major_synmin facilities netted out cleanly (`IS_ELECTRIC` by membership in `electric_2015_2025`'s own facility set, not a re-derived NAICS/SIC regex), and regulatory lag (`MEAN_VIOL_TO_EA_LAG_DAYS`) in year *t* vs. future violations in year *t+1*. Descriptive/correlational only. Added 2026-07-30. |
| `panel_profile/{concentration_lorenz,concentration_gini,exit_curve_by_year,inspection_hit_rate_by_year,self_disclosure_share_by_year,state_enforcement_intensity,emissions_enforcement_facility_year,emissions_enforcement_bin_summary}.csv` + `figures/panels/panel_{concentration_lorenz,exit_curve,inspection_hit_rate,self_disclosure_share,state_enforcement_intensity,emissions_enforcement}.png` | `code/diagnostics/20_panel_extended_profile.R` | Six more electric-vs-other descriptive cuts: concentration (Lorenz/Gini), cumulative exit, inspection hit rate, self-disclosure share, state enforcement intensity, and emissions volume vs. inspection/enforcement intensity. All descriptive/correlational only. Added 2026-07-30. |
| `panel_profile/{agency_share_by_year,recidivism_by_lag}.csv` + `figures/panels/panel_{agency_share_over_time,recidivism}.png` | `code/diagnostics/21_panel_agency_recidivism_profile.R` | Two more cuts: EPA vs. state vs. local share of inspections/enforcement over time, and repeat-offender persistence (`P(violation at t+k \| violation status at t)`, k=1-3, electric vs. other, against each group's unconditional baseline). Both descriptive/correlational only. Added 2026-07-30. |
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

## Notes

- **`output/panel_profile/` and `output/figures/panels/` are shared destinations, not one script's private
  output.** Four scripts write into them — `18_panel_profile.R` (the base panel-layer profile), and
  `19`/`20`/`21` (further electric-vs-other, concentration, agency-share, and recidivism cuts layered on top,
  each adding its own files rather than duplicating `18`'s). No two scripts write the same filename, but
  deleting the whole directory and re-running only one of the four will leave the others' files missing —
  regenerate all four in sequence (`18` → `21`) for a complete rebuild, same order as
  `code/diagnostics/README.md`'s table.
- **`output/tables/*.tex` is the one genuinely stale entry in this folder** (see its row above) — it predates
  the archival of the old panel-building layer and nothing currently regenerates it. Everything else here is
  a live output of a script that still runs.
- **`output/sessionInfo.txt` is the only gitignored file directly under `output/`**; `output/tables/*.tex` is
  tracked-if-added but left untracked by default (see `.gitignore`'s comment on that line) — don't assume
  "not tracked" and "gitignored" mean the same thing here.
- **This README documents *what got written and by what script*; the brief layer documents *what it means*.**
  The panel layer mirrors 1:1 (`panel_profile/` → `briefs/panel/panel_profile.md`, covering `18`–`21` above).
  The dataset layer doesn't mirror by folder name — some profile output feeds a dedicated brief
  (`hpv_profile/` → `briefs/datasets/hpv_profile.md`, `pipeline_profile/` → `briefs/datasets/pipeline_profile.md`,
  `emissions_profile/` → `briefs/datasets/emissions_profile.md`, `coordinates_profile/` →
  `briefs/datasets/coordinates_profile.md`), some feeds a differently-named one (`operating_profile/` and
  `regulatory_profile/` both feed `briefs/datasets/regulatory_dataset_profile.md`), and some feeds straight
  into `briefs/datasets/dataset_construction_decisions.md` (`penalties_profile/`'s settlement-structure finding
  — also has its own standalone `multi_facility_settlement_decision.md`). Check
  `briefs/datasets/dataset_construction_decisions.md` by decision code (e.g. `O5`, `P5`) if a profile CSV's
  number doesn't obviously map to a same-named brief.
