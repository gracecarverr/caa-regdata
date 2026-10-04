> **Status:** draft — [ ] verified against the current script (Claude, 2026-07-30)

# `18_wayback_facility_spells.R` — collapse facility-year status into one-row-per-facility entry/exit spells

## Purpose in the pipeline
> **TODO (Grace):** write the 1-2 sentence purpose blurb here — why this script exists and what depends on
> it. Starting material, from the script's own header comment:
> "code/02_cleaning/wayback/18_wayback_facility_spells.R -- collapse the facility x year wayback status
> series into a one-row-per-facility ENTRY/EXIT summary. The raw ICIS-AIR facility table has NO entry/exit
> dates; these are RECONSTRUCTED from when a facility appears in / disappears from the annual snapshots
> (2015-2025) and from observed operating->closed transitions.
> in : data/processed/wayback_facility_status.csv.gz
> out: data/processed/wayback_facility_spells.csv.gz
>      PGM_SYS_ID, entered_year, exited_year, exit_source, left_censored, right_censored
>
> entered_year   = first snapshot year the facility is OPERATING (op in {OPR,TMP,SEA}); NA if never operating.
> left_censored  = 1 if the facility is already present in the first snapshot (2015): true entry may predate
>                  the window and is unknown.
> exited_year    = first year after which the facility is NEVER operating again (permanent exit). NA if the
>                  facility is still operating in the last snapshot (2025) -> right-censored.
> exit_source    = 'cls'     : exit confirmed by an observed Permanently-Closed (CLS) status;
>                  'other'   : exit via another non-operating code (PLN/CNS/NER/NED/NES/LDF);
>                  'dropout' : facility was last seen OPERATING then vanished from later snapshots (could be
>                              a real closure OR an ICIS extract artifact -- kept distinct on purpose);
>                  NA        : never exited within the window (right-censored) or never operating.
> right_censored = 1 if operating in the last snapshot (2025): exit, if any, is after the window.
> NOTE: exited_year is defined off the LAST operating year, so a close-then-reopen facility is treated as
> still-in-service until its final operating year -- reopenings do not create a spurious early exit."

## Inputs & outputs
- **Input:** `data/processed/wayback_facility_status.csv.gz` — facility × year operating status (output of
  `17_wayback_facility_status.R`).
- **Output:** `data/processed/wayback_facility_spells.csv.gz` — **one row per facility**. Key fields:
  `PGM_SYS_ID`, `entered_year`, `exited_year`, `exit_source` (`cls`/`other`/`dropout`/NA), `left_censored`,
  `right_censored`.

Example — real rows from `data/processed/wayback_facility_spells.csv.gz`
(`gzcat data/processed/wayback_facility_spells.csv.gz | ...`, sampled 2026-07-30):

| PGM_SYS_ID | entered_year | exited_year | exit_source | left_censored | right_censored |
|---|---|---|---|---|---|
| 010000000901110001 | 2017 | NA | NA | 0 | 1 |
| 0500000026163R0095 | 2015 | 2022 | cls | 1 | 0 |
| 020000000001062015 | 2015 | 2017 | dropout | 1 | 0 |

Row 1: entered 2017, still operating at window close (right-censored, no exit). Row 2: present since the
first snapshot (left-censored), confirmed closed in 2022. Row 3: present since the first snapshot, last seen
operating in 2015, vanished by its next real observation in 2017 (dropout, not a confirmed closure). File has
292,039 facility rows on disk.

## At a glance
| | |
|---|---|
| **Input** | `data/processed/wayback_facility_status.csv.gz` (2,797,699 facility-year rows) |
| **Output** | `data/processed/wayback_facility_spells.csv.gz` — 292,039 facility rows, ~996KB |
| **Runtime** | not measured directly; a handful of `dplyr` group-by/summarise/join passes over ~2.8M rows collapsing to ~292k facilities — likely well under a minute |
| **Requires** | `17_wayback_facility_status.R` (reads its output directly); runs second of the 3 `wayback/` scripts within `02_clean.R` |
| **Dependencies** | `readr`, `dplyr` |

## Walkthrough
1. **Read `wayback_facility_status.csv.gz`** with explicit column types (`PGM_SYS_ID` character, `year`
   integer, status columns character, `operating` integer). `FIRST_SNAP`/`LAST_SNAP` are derived as
   `min(year)`/`max(year)` (2015/2025) rather than hard-coded.
2. **`per_fac`**: each facility's observed span (`first_year`, `last_year`) across *all* rows (including NA
   gap years).
3. **`op_win`**: each facility's operating window — `entered_year` = first year `operating == 1`,
   `last_op_year` = last year `operating == 1` — computed only over rows where `operating == 1`, so gap years
   never contribute.
4. **`spells`**: left-join `op_win` onto `per_fac`. `ever_op` flags whether the facility was ever seen
   operating at all. `left_censored`/`right_censored` are set from whether `entered_year`/`last_op_year` hit
   the window edges (2015/2025).
5. **`exit_code`**: for facilities with a known `last_op_year`, find the **first real (non-NA) observation
   strictly after** `last_op_year` — this is what lets the script correctly skip the 2018 gap rather than
   treating it as "no evidence" (see gotchas).
6. **Final `exited_year`/`exit_source` case_when**: right-censored or never-operating facilities get NA;
   others get the observed post-operating transition year and its code, classified into `cls` (observed
   `CLS`), `other` (any other real non-operating code), or `dropout` (no real post-operating observation at
   all before the facility's last-seen year — i.e. the facility just vanishes from the snapshots).
7. Write to `data/processed/wayback_facility_spells.csv.gz`.

## Notes & gotchas
- **N9 — reopening collapse: a genuine interior closure can be silently absorbed into one continuous-looking
  spell.** Quoted from `code/02_cleaning/wayback/README.md`: "A genuine close-then-reopen is invisible in
  `exited_year`/`entered_year`/`exit_source`, even though the year-varying `operating`/`op_status_code`
  columns still show it correctly (N9). `18_`'s one-row-per-facility spell summary defines `entered_year` off
  the *first* operating year and `exited_year`/`exit_source` off the *last* (deliberately — this is what makes
  it robust to reopening in the first place, see the bullet above), but that same choice means an interior
  closure between them gets silently absorbed into one continuous-looking spell. As last measured, **583 of
  ~220,579 ever-operating facilities (0.26%)** have ≥1 genuine non-operating year strictly inside their span.
  Only the collapsed spell-summary fields lose this; a downstream consumer reading the year-by-year
  `operating` column directly (not just the spell summary) sees the true operating→closed→operating
  sequence." ⚠️
- **W7a — a 2018-adjacent gap in `exited_year` means "confirmed non-operating by the next real observation,"
  not a precise closure date.** Quoted from the same source: "A 2018-adjacent gap in
  `entered_year`/`exited_year`/`exit_source` should be read as 'confirmed non-operating by the next real
  observation,' not as a precise closure date (W7a). E.g. a facility operating in 2017, with 2018's explicit
  `NA` gap (see above), then non-operating in 2019 gets `exited_year = 2019` — that means 'still confirmed
  operating in 2017, confirmed non-operating by 2019, exact transition year unknown,' not 'closed in 2019.' As
  last measured this pattern (operating→gap→non-operating) affects **~1.8%** of facilities with real status on
  both sides of 2018 — not a rare edge case. No code fix is needed for this — the exit-classification logic
  already only ever counts real observations — but the resulting `exited_year` shouldn't be read as more
  precise than the gap allows." ⚠️ The script's own inline comment gives the exact underlying count for this
  case: "4,258 facilities are operating in 2017 and non-operating in 2019 (4,211 CLS / 35 CNS / 12 PLN) with
  2018 unobserved."
- **`dropout` exits are kept distinct from confirmed closures on purpose** — a vanish from the snapshots could
  be a real closure or an ICIS extract artifact; per the folder README, `dropout` should be read as "an upper
  bound on unexplained exits (N8)," not a confirmed exit count.
- Verified by reading the script in full this session (not previously read) and by directly sampling
  `wayback_facility_spells.csv.gz` off disk, including deliberately searching for `cls` and `dropout` example
  rows to confirm both codes appear with the expected shape. Did not re-run the script.
