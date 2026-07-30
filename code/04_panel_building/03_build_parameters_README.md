> **Status:** draft — [ ] verified against the current script (Claude, 2026-07-30)

# `03_build_parameters.R` — defines `YEARS` and `PANEL_SPECS`, the facility-filter definitions for the two panels

## Purpose in the pipeline
> **TODO (Grace):** write the 1-2 sentence purpose blurb here — why this script exists and what depends on
> it. Starting material, from the script's own header comment:
> "window + the two panel specs this pipeline ships. PANEL_SPECS lists the two panels to build. Both start
> from 00_spine.R's `spine` (already CONUS + Major/Synthetic-Minor class, with EVER_ACTIVE precomputed) --
> electric adds the NAICS/SIC filter on top. 03_build.R applies each spec's `filter`, calls build_panel(),
> and writes data/panels/<name>.csv.gz. This is a from-scratch rewrite, NOT the old
> code/03_panel_building/03_build_parameters.R renamed -- the archived version... shipped THREE levels
> (universe/major_synmin/electric) with continuity as an optional add-on family; this pipeline ships ONLY
> these two panels, per explicit project decision."

## Inputs & outputs
- **Input:** none — a pure parameters/config file, no data reads. Operates on the `spine` object left in
  scope by `00_spine.R` (a `spine` data frame with `STATE`, `AIR_POLLUTANT_CLASS_DESC`, `EVER_ACTIVE`,
  `NAICS_CODES`, `SIC_CODES` columns is assumed present when `PANEL_SPECS`' filter functions are actually
  called by `03_build.R`).
- **Output:** not a data file — the `PANEL_SPECS` list itself (plus `YEARS` and `electric_filter()`),
  consumed by `03_build.R`.

Actual content of the file (real code, not fabricated data — there is no output file to sample):

```r
YEARS <- 2015:2025

electric_filter <- function(s) dplyr::filter(s,
  grepl("(^|[^0-9])2211", NAICS_CODES) |
  grepl("(^|[^0-9])4911([^0-9]|$)", SIC_CODES))

PANEL_SPECS <- list(
  list(name = "major_synmin_2015_2025",
       filter = function(s) dplyr::filter(s, EVER_ACTIVE)),
  list(name = "electric_2015_2025",
       filter = function(s) electric_filter(dplyr::filter(s, EVER_ACTIVE)))
)
```

## At a glance
| | |
|---|---|
| **Input** | none (pure config); assumes `spine` from `00_spine.R` is in scope when its filters actually run |
| **Output** | `YEARS`, `electric_filter()`, `PANEL_SPECS` — objects consumed by `03_build.R`, not a file |
| **Runtime** | negligible — defines a constant, a function, and a two-element list; no data read or written |
| **Requires** | nothing to source this file itself; `03_build.R` sources it after `00_spine.R` |
| **Dependencies** | `dplyr` (namespaced calls only, `dplyr::filter`; no `library()` call in this file) |

## Walkthrough
**`YEARS <- 2015:2025`** — this pipeline's window, distinct from the repo-wide `YEARS <- 2005:2025`
(`00_setup.R`) and coincidentally identical to `00_spine.R`'s `SCREEN_YEARS`.

**`electric_filter(s)`** — a function taking a facility data frame `s` and returning the subset matching
NAICS 2211 (electric power generation, matched via a left-bounded prefix regex) or SIC 4911 (Electric
Services, matched via a both-sides-bounded exact regex).

**`PANEL_SPECS`** — a two-element list, each element a named list with `name` (used as the output filename
stem) and `filter` (a function taking `spine` and returning the eligible facility subset). `major_synmin_
2015_2025`'s filter is just `EVER_ACTIVE`; `electric_2015_2025`'s filter composes `EVER_ACTIVE` with
`electric_filter()`.

## Notes & gotchas
- **Facility filters table**, quoted verbatim from `docs/data_dictionary_derived.md` Part 2:

  | Panel | Filter |
  |---|---|
  | `major_synmin_2015_2025` | `STATE` in the 48 contiguous states + DC, **+** `AIR_POLLUTANT_CLASS_DESC %in% c("Major Emissions", "Synthetic Minor Emissions")`, **+** `EVER_ACTIVE` (see below). |
  | `electric_2015_2025` | the above **+** NAICS 2211 (prefix-anywhere match, catches child codes like `221112`) **or** SIC 4911 (anchored exact 4-digit match). |

  Note the CONUS/class portion of that filter is already baked into `spine` by `00_spine.R` — this file only
  adds `EVER_ACTIVE` and, for electric, the NAICS/SIC test on top.
- ⚠️ **NAICS-prefix-match vs. SIC-anchored-exact-match asymmetry — a real, deliberate design difference,
  not an oversight.** The script's own inline comments: NAICS regex `(^|[^0-9])2211` is *"left-bounded only,
  since every real NAICS leaf code under 2211 is a 4+ digit extension of "2211" (e.g. 221112, 221122), so a
  trailing-digit match is always a true positive"* — i.e. it catches child codes like `221112`, `221115`,
  `221122` via prefix match. SIC regex `(^|[^0-9])4911([^0-9]|$)` is bounded on **both** sides because
  *"SIC 4911 (Electric Services) is itself a complete leaf code"* — an anchored exact 4-digit match, not a
  prefix match. Anyone extending this file to add another NAICS/SIC code should preserve this distinction:
  a NAICS prefix that has real child codes needs left-bounding only; a SIC code that's already a complete leaf
  needs both-sides bounding to avoid accidentally matching it as a substring of a longer code.
- **`EVER_ACTIVE` (the filter both panel specs apply)** is precomputed in `00_spine.R`, not derived here — see
  that script's README for the full `PB2` eligibility-rule quote. This file only consumes the already-computed
  boolean column.
- **Three panel levels in the archived pipeline, two here** — per this file's own header comment, the
  archived `code/03_panel_building/03_build_parameters.R` shipped `universe`/`major_synmin`/`electric` with
  continuity as an optional add-on family; this rewrite ships only `major_synmin_2015_2025` and
  `electric_2015_2025`, per `PB1`'s explicit scope decision.
- Verified by reading the script in full (35 lines, all quoted or paraphrased above) and cross-checking the
  facility-filter table and NAICS/SIC asymmetry claims against `docs/data_dictionary_derived.md` Part 2 and
  the script's own inline comments. Not run in this session.
