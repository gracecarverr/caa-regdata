# diagnostics/tables — HTML section builders for the docs site

One script per source, each defining `build_<asset>_section()` that returns a single HTML `<section>` for the
documentation site. Sourced by [`../build_site.R`](../build_site.R), which concatenates the sections into
`docs/raw_data.html`. Built **directly from `data/raw/`** with the same computations + curated content as the old
CAA_Project `*_table.xlsx` workbooks (ported verbatim).

- `_html.R` — shared HTML rendering primitives (table/section helpers, escaping).

| script | raw input (under `data/raw/`) | section |
|--------|-------------------------------|---------|
| `facilities.R` | `ICIS-AIR_downloads/ICIS-AIR_FACILITIES.csv` | Facilities |
| `violations.R` | `ICIS-AIR_downloads/ICIS-AIR_VIOLATION_HISTORY.csv` | Violations |
| `inspections.R` | `ICIS-AIR_downloads/ICIS-AIR_FCES_PCES.csv` | Inspections (FCE/PCE) |
| `formal_actions.R` | `ICIS-AIR_downloads/ICIS-AIR_FORMAL_ACTIONS.csv` | Formal enforcement actions |
| `informal_actions.R` | `ICIS-AIR_downloads/ICIS-AIR_INFORMAL_ACTIONS.csv` | Informal enforcement actions |
| `certs.R` | `ICIS-AIR_downloads/ICIS-AIR_TITLEV_CERTS.csv` | Title V certifications |
| `stacktests.R` | `ICIS-AIR_downloads/ICIS-AIR_STACK_TESTS.csv` | Stack tests |
| `pollutants.R` | `ICIS-AIR_downloads/ICIS-AIR_POLLUTANTS.csv` | Pollutants |
| `programs.R` | `ICIS-AIR_downloads/ICIS-AIR_PROGRAMS.csv` | Programs |
| `program_subparts.R` | `ICIS-AIR_downloads/ICIS-AIR_PROGRAM_SUBPARTS.csv` | Program subparts |
| `afs_actions.R` | `afs_downloads/AFS_ACTIONS.csv` | AFS actions |
| `afs_air_program.R` | `afs_downloads/AIR_PROGRAM.csv` | AFS air program |
| `afs_facilities.R` | `afs_downloads/AFS_FACILITIES.csv` | AFS facilities |
| `afs_hist_compliance.R` | `afs_downloads/AFS_AIR_PRG_HIST_COMPLIANCE.csv` (~10.2M rows) | AFS historical compliance |
| `afs_hpv.R` | `afs_downloads/AFS_HPV_HISTORY.csv` | AFS HPV history |
| `emissions.R` | `POLL_RPT_COMBINED_EMISSIONS.csv` (~880 MB, ~10.4M rows — reads via `data.table::fread`, not `readr`, to avoid OOM) | Combined Emissions |

These are **documentation/reporting**, not part of the data build — hence their home under `diagnostics/`.
Run via `Rscript code/diagnostics/build_site.R` (set `SKIP_SECTIONS=emissions` to skip the ~900 MB read).
