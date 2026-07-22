# 03_build_parameters.R — reference

The window, geography, and per-panel filters that drive `03_build.R`.

## Constants

| name | value | meaning |
|------|-------|---------|
| `YEARS` | `2005:2025` | panel window. Assets keep **all** dated events; the window is applied here (decision **CC2**). Referenced throughout `03_build_functions.R`. |
| `CONUS` | 48 states + DC | contiguous US (excludes AK, HI, territories). |
| `MAJOR_SYNMIN_CLASSES` | `c("Major Emissions", "Synthetic Minor Emissions")` | the class filter shared by `major_synmin` and `electric`. |

## `PANEL_SPECS`

A list; each entry defines one sample panel. Fields:

| field | meaning |
|-------|---------|
| `name` | output stem → `data/panels/<name>.csv.gz` |
| `filter` | `function(spine) -> filtered rows` — the facilities in scope |
| `treatment` | `TRUE` to attach the PM2.5 (2012) attainment treatment block (electric only) |

Current specs (each narrows the previous — the funnel):

| name | filter | treatment |
|------|--------|-----------|
| `universe` | `STATE %in% CONUS` | — |
| `major_synmin` | + `AIR_POLLUTANT_CLASS_DESC %in% MAJOR_SYNMIN_CLASSES` | — |
| `electric` | + `NAICS 2211` **OR** `SIC 4911` (anchored regex) | ✔ PM2.5 |

> The electric NAICS/SIC filter is an **OR**, which admits a few SIC-only / unclassified-NAICS cases — see
> `briefs/panel/panel_construction_decisions.md` (PR1) and the open question on the electric definition (D-C1).

## Adding / changing a panel

- **New panel:** add a `list(name=, filter=, treatment=)` entry. `build_panel()` does the rest — no new code.
- **Different window:** change `YEARS`. Note the **spine's** active-window is set independently in `00_spine.R`
  (also `2005:2025`); a facility absent from the spine's window won't appear even if you widen `YEARS` here
  (nuance **N2**) — widen both if needed.
