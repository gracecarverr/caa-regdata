> **Status:** draft — [ ] verified against the current script (Claude, 2026-07-30)

# `hap_list_112b.R` — static reference table: CAA §112(b) Hazardous Air Pollutants list (188 substances)

## Purpose in the pipeline
> **TODO (Grace):** write the 1-2 sentence purpose blurb here — why this script exists and what depends on
> it. Starting material, from the script's own header comment:
> "static reference table: the CAA section 112(b) list of Hazardous Air Pollutants (HAPs), 188 substances
> currently in force. Sourced (not typed from memory) and validated below; used by code/03_datasets/01_regulatory.R
> to replace the old grepl('HAZARDOUS AIR POLLUTANT', POLLUTANT_DESC) rule, which only matched pollutant rows
> literally labeled with that umbrella phrase and missed the large majority of HAPs that ICIS-AIR records by
> specific chemical name (Benzene, Formaldehyde, Lead, Mercury, ...)."
>
> (2026-07-30: the header comment's file path and consumer reference were stale — pre-rename
> `code/03_panel_building/hap_list_112b.R` and a defunct `00_spine.R` consumer plus `code/04_datasets/01_regulatory.R`
> — fixed in the script directly to the current path and the one real current consumer, confirmed by `grep`:
> `01_regulatory.R:59`.)

## Inputs & outputs
This is a **static reference list**, not a pipeline-stage script with its own facility-year output — it has
no `data/datasets/` file of its own.

- **Input:** none (hand-assembled `tribble()` sourced from external legal/regulatory text — see Provenance
  below) — no file I/O.
- **Output:** the HAP list itself (`HAP_112B`, a 188-row tibble of `cas_number`/`hap_name`/
  `is_compound_class`, plus `HAP_COMPOUND_CLASS_PATTERNS`, a derived regex-pattern vector for the 17
  CAS-less entries), consumed by `01_regulatory.R`'s `EMITS_HAP` computation.

Example — 6 real entries from `HAP_112B` (as they appear in the script):

| cas_number | hap_name | is_compound_class |
|---|---|---|
| 71432 | Benzene (including benzene from gasoline) | FALSE |
| 50000 | Formaldehyde | FALSE |
| 75014 | Vinyl chloride | FALSE |
| 1332214 | Asbestos | FALSE |
| 0 | Chromium Compounds | TRUE |
| 106945 | 1-Bromopropane (1-BP, n-propyl bromide, nPB) [added by 40 CFR 63.64] | FALSE |

Full column list (3, plus the derived `pattern` column in `HAP_COMPOUND_CLASS_PATTERNS`): `cas_number`,
`hap_name`, `is_compound_class`.

## At a glance
| | |
|---|---|
| **Input** | none — the list is hand-assembled in-script from external sources (see Provenance) |
| **Output** | `HAP_112B` (188 rows) + `HAP_COMPOUND_CLASS_PATTERNS` (17 regex patterns), in-memory objects consumed by `01_regulatory.R`'s `EMITS_HAP` computation |
| **Runtime** | trivial — building and validating a 188-row tibble, no file I/O; well under 1 second |
| **Requires** | Nothing upstream in this pipeline — standalone reference data, `library(tibble)`/`library(dplyr)` only. Consumed by (not a dependency of) `01_regulatory.R`. |
| **Dependencies** | `tibble`, `dplyr` |

## Walkthrough
1. **Provenance block** (comment, lines 10-23) — documents where each entry came from: the base 189-substance
   list from 42 U.S.C. §7412(b)(1) (Cornell LII mirror, fetched 2026-07-28, parsed programmatically not
   hand-transcribed), plus three post-enactment modifications from 40 CFR Part 63 Subpart C (Caprolactam and
   Methyl ethyl ketone deleted; 1-Bromopropane added 2022) netting to the current 188.
2. **`HAP_112B` tribble** — 188 rows of `(cas_number, hap_name)`, then `mutate(is_compound_class = cas_number
   == "0")` — the 17 entries with no single CAS number (EPA's own convention, not a missing-data placeholder)
   are flagged.
3. **Validation `stopifnot()`** (lines 229-237) — asserts exactly 188 rows, no duplicate real (non-"0") CAS
   numbers, and spot-checks four well-known entries (Benzene, Formaldehyde, Vinyl chloride, Asbestos) against
   their expected CAS numbers.
4. **`HAP_COMPOUND_CLASS_PATTERNS`** — for the 17 CAS-less compound-class entries, derives a case-insensitive
   substring-match regex pattern from each name (stripping any parenthetical qualifier, e.g. "Arsenic
   Compounds (inorganic including arsine)" → `"Arsenic Compounds"`), with a special-case regex
   (`"Polyc(y|i)?lic"`) covering both the statute's "Polycylic" spelling and the more common "Polycyclic."

## Notes & gotchas
- ⚠ **R6 addendum — the CAS-join-unioned-with-umbrella-phrase-rule story, quoted in full from
  `briefs/datasets/dataset_construction_decisions.md`:**
  > "`EMITS_HAP` was broken, now fixed: the old rule matched only the literal substring `'HAZARDOUS AIR
  > POLLUTANT'` in `POLLUTANT_DESC`, missing the large majority of HAPs that ICIS-AIR records under a
  > specific chemical name (Benzene, Formaldehyde, Lead, Mercury, ...) rather than that umbrella phrase — the
  > other five `EMITS_*` flags are fine (each backed by only 1-8 distinct `POLLUTANT_CODE` values). Fixed
  > identically to the panel-layer spine (F6 addendum...): **CAS (Chemical Abstracts Service registry
  > number)-join against the official CAA §112(b) HAP list (188 substances, `code/03_datasets/
  > hap_list_112b.R`) unioned with (not replacing) the old umbrella-phrase rule, since that rule turned out
  > to catch a real, distinct signal — an aggregate `'TOTAL HAZARDOUS AIR POLLUTANTS (HAPS)'` summary record
  > (no CAS) that some facilities report instead of itemizing species — plus a name match for the 17 CAS-less
  > compound-class entries (e.g. 'Chromium Compounds').** Full-universe `EMITS_HAP=1` facility count:
  > **67,011 of 279,665 (24.0%)** post-fix. A coverage diagnostic is now printed on every build (`pollutants
  > coverage: N / M rows (%) match none of the six EMITS_* categories`)."

  In other words, `EMITS_HAP` is the union of **three** independent matches, not one: (1) CAS-number join
  against this file's 171 real-CAS entries, (2) the retained umbrella-phrase `grepl("HAZARDOUS AIR
  POLLUTANT", ...)` rule (kept deliberately, not a leftover — it catches a distinct aggregate-summary record
  type the CAS join structurally cannot), and (3) name-match regex against `HAP_COMPOUND_CLASS_PATTERNS` for
  the 17 CAS-less compound-class entries this file itself derives.

- **Provenance discipline** — the script's own comment block is explicit that the base list was "parsed
  programmatically from its CAS-number/name HTML table (not hand-transcribed)" and the CFR modifications were
  fetched via the eCFR versioner API, not typed from memory — worth preserving as the reason this file is
  trustworthy as a legal reference, not just a plausible-looking substance list.

- **"Polycylic" spelling** — not a typo introduced by this repo: "`'Polycylic Organic Matter' (sic) is not a
  typo introduced here -- it is how 42 U.S.C. 7412(b)(1) itself spells it; matching below accounts for the
  more common 'Polycyclic' spelling as well, since ICIS-AIR likely uses that spelling.'" (script comment,
  lines 31-32).

- **CAS "0" convention** — "CAS '0' marks the 17 compound-class entries (e.g. 'Chromium Compounds') that have
  no single CAS number -- this is EPA's own convention, not a missing-data placeholder." Don't treat
  `cas_number == "0"` as a data-quality problem; it's the expected encoding for `is_compound_class == TRUE`
  rows, and the `stopifnot()` duplicate-CAS check deliberately excludes these from the uniqueness test
  (`cas_number != "0"`) since multiple compound classes legitimately share the placeholder.

- **Verified by reading the script directly:** the 188-row tribble content, the `is_compound_class` /
  `is.compound_class` derivation, the validation `stopifnot()` block, the `HAP_COMPOUND_CLASS_PATTERNS`
  derivation (including the `Polycylic`→`Polyc(y|i)?lic` regex substitution), and — via `grep` against
  `01_regulatory.R` — that this file is in fact sourced from `code/03_datasets/01_regulatory.R:59`, now
  matching the header comment since the 2026-07-30 cleanup above. **Inferred/not independently
  re-verified this pass:** the external provenance claims themselves (that the Cornell LII fetch and eCFR
  API fetch actually happened and match what's in the tribble) — taken on the strength of the script's own
  documented validation, not independently re-fetched.
