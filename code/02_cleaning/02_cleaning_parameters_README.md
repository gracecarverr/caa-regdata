# 02_cleaning_parameters.R — reference

`CLEAN_SPECS` is a list with one entry per **regular** source (16 of the 19). The driver `02_clean.R` calls
`clean_one()` on each. The 3 Wayback sources are not here — they have bespoke scripts in `wayback/`.

## Spec fields

| field  | required | meaning |
|--------|----------|---------|
| `name` | yes | output stem → `data/processed/<name>.csv.gz` |
| `raw`  | yes | input path relative to `data/raw/` |
| `date` | event tables only | `function(d) -> Date`; its result becomes `date`, and `year` is derived from it |
| `key`  | event tables only | `character` vector of columns defining the within-facility event key; adds the 0-based `dup` index |

An entry with **no** `date`/`key` is an **attribute** table: it keeps all columns/rows and gets only `dup_exact`.

## Source → output map

### Event tables (add date/year/dup/dup_exact)

| output (`name`) | raw file (under `data/raw/`) | `date` source | `dup` key |
|-----------------|------------------------------|---------------|-----------|
| `inspections`      | `ICIS-AIR_downloads/ICIS-AIR_FCES_PCES.csv`        | `mdy(ACTUAL_END_DATE)` | `PGM_SYS_ID, ACTIVITY_ID` |
| `violations`       | `ICIS-AIR_downloads/ICIS-AIR_VIOLATION_HISTORY.csv`| `coalesce(mdy(EARLIEST_FRV_DETERM_DATE), mdy(HPV_DAYZERO_DATE))` | `PGM_SYS_ID, COMP_DETERMINATION_UID` |
| `formal_actions`   | `ICIS-AIR_downloads/ICIS-AIR_FORMAL_ACTIONS.csv`   | `mdy(SETTLEMENT_ENTERED_DATE)` | `PGM_SYS_ID, ENF_IDENTIFIER` |
| `informal_actions` | `ICIS-AIR_downloads/ICIS-AIR_INFORMAL_ACTIONS.csv` | `mdy(ACHIEVED_DATE)` | `PGM_SYS_ID, ENF_IDENTIFIER` |
| `certs`            | `ICIS-AIR_downloads/ICIS-AIR_TITLEV_CERTS.csv`     | `mdy(ACTUAL_END_DATE)` | `PGM_SYS_ID, ACTIVITY_ID` |
| `stacktests`       | `ICIS-AIR_downloads/ICIS-AIR_STACK_TESTS.csv`      | `mdy(ACTUAL_END_DATE)` | `PGM_SYS_ID, ACTIVITY_ID` |

### Attribute tables (add dup_exact only)

| output (`name`) | raw file (under `data/raw/`) |
|-----------------|------------------------------|
| `facilities`         | `ICIS-AIR_downloads/ICIS-AIR_FACILITIES.csv` |
| `pollutants`         | `ICIS-AIR_downloads/ICIS-AIR_POLLUTANTS.csv` |
| `programs`           | `ICIS-AIR_downloads/ICIS-AIR_PROGRAMS.csv` |
| `program_subparts`   | `ICIS-AIR_downloads/ICIS-AIR_PROGRAM_SUBPARTS.csv` |
| `afs_actions`        | `afs_downloads/AFS_ACTIONS.csv` |
| `afs_air_program`    | `afs_downloads/AIR_PROGRAM.csv` |
| `afs_facilities`     | `afs_downloads/AFS_FACILITIES.csv` |
| `afs_hist_compliance`| `afs_downloads/AFS_AIR_PRG_HIST_COMPLIANCE.csv` |
| `afs_hpv`            | `afs_downloads/AFS_HPV_HISTORY.csv` |
| `emissions`          | `POLL_RPT_COMBINED_EMISSIONS.csv` (`REPORTING_YEAR` already present — no date parse) |

## Adding a source

- **Regular shape:** add one `list(...)` entry here. Event table → give `date` and `key`; attribute table →
  give just `name` and `raw`. No new code.
- **Bespoke shape** (multi-file, gap-filling, reshaping): write a script under `wayback/` (or a new
  subfolder) and source it from `02_clean.R`. Don't force it into a spec.

Always add a matching `data/processed/<name>.README.md` documenting columns and institutional implications.
