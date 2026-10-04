# wayback_verify — can the staged ICIS-Air Wayback snapshots be reproduced from the Archive?

## Question
`data/raw/ICIS_AIR_WAYBACK/ICIS-AIR_downloads_<year>/` holds manually-staged annual snapshots of EPA's
live ICIS-Air bulk download, sourced from the Internet Archive at some point in the past. A prior,
uncommitted attempt at automating re-acquisition of these from the Wayback Machine's CDX API picked one
candidate per year (the latest capture in that calendar year) and hoped it matched — see the header of
[`../../01_data_download/01_download.R`](../../01_data_download/01_download.R). That reproduced the staged
files byte-for-byte for 2015/2017/2019/2020/2025, but **not** 2016; 2018 has zero Wayback captures of the
URL at any status code (deleted from `data/raw/` as a mislabeled duplicate of 2019, decision W7); and
2021–2024 were never tested. No single selection rule was confirmed to work for every year.

This asks the sharper question directly: **for each currently-staged year, does *any* Wayback capture
reproduce it byte-for-byte** — rather than trusting a heuristic guess for which capture to try.

## Run

```sh
Rscript code/diagnostics/wayback_verify/wayback_verify.R
```

Needs **network access** (queries the Wayback Machine's CDX API and downloads candidate zips into `_cache/`,
gitignored). Set `EXHAUSTIVE=true` to keep checking candidates past the first match.

## Method (`wayback_verify.R`)
1. md5 every staged `*.csv` first (the ground truth being tested against).
2. Per staged year, query the CDX API once (unfiltered by status, digest-collapsed) for captures of the
   live ICIS-Air URL within that calendar year.
3. Filter to HTTP 200, sort most-recent-first, dedupe by content digest (same digest ⇒ byte-identical zip,
   never fetched twice).
4. Walk candidates in that order, downloading and selectively extracting each one; the first whose CSVs
   md5-match every staged file is recorded as the match and iteration stops (set `EXHAUSTIVE=true` to keep
   checking the rest). A candidate missing a staged filename is `INCOMPLETE`, not hashed. No match after
   all candidates ⇒ `FAIL`, noting the closest miss.

Outputs → `output/wayback_verify/`: `summary_by_year.csv` (headline status + matched capture per year),
`candidates_by_year.csv` (every unique candidate considered, tried or not), `file_mismatches.csv` (per-file
diffs for tried-and-failed candidates), `staged_file_md5s.csv` (the ground truth). Read-only w.r.t.
`data/raw/`; downloaded candidate zips are cached in `_cache/` (gitignored, disposable).

## Finding (run 2026-07-27)
**All 10 currently-staged years reproduce byte-for-byte from a Wayback capture** — including the two
things this was actually built to resolve:

- **2016 was a false negative in the prior attempt, not a real gap.** The *earlier* of its two 200-status
  captures (`20161225101825`, 2016-12-25) matches all 10 files exactly; the prior heuristic only ever
  tried the *latest* one (`20161230164933`, 2016-12-30, five days later), which is a genuinely different
  crawl (all 10 files differ). Rank-by-recency alone is not a safe selection rule — this is direct proof.
- **2021–2024, previously untested, all pass.** 2022 and 2024 also needed a non-latest candidate (rank 2 of
  3, and rank 3 of 5, respectively) — each had at least one more-recent capture that was a genuine mismatch
  across every file (`candidates_by_year.csv` / `file_mismatches.csv`), consistent with the 2016 pattern:
  the *most recent* crawl in a year is not reliably the one that was staged.
- **2018 is out of scope for this run** — there is no `ICIS-AIR_downloads_2018/` folder to test against (it
  was deleted per W7). Its "zero captures at any status code" finding stands from the prior investigation
  and was spot-checked again during this run's design; it is not re-derived here because there is nothing
  staged to compare it to.
- **No exhaustive search was needed beyond a handful of candidates**: at most 12 unique candidates in a
  year (2025), most years 1–5, and the match was always found within the first 3 tried.

**Practical implication**: a reliable per-year selection rule is *not* "take the latest capture" — it's
"try candidates most-recent-first and verify against a known-good hash," exactly what this script does.
That is a candidate mechanism for folding into `01_download.R`'s automation (recording the confirmed
`matched_timestamp` per year rather than a live "latest" guess) — a follow-up decision, not made here.

## Update (2026-07-29): Q4 re-pin, and all 10 years now confirmed PASS

`code/01_data_download/01_download.R`'s pins were audited for Q4 (Oct-Dec) consistency
(`wayback_q4_repin.R`, sibling script in this folder) — only 2024 had a real Q4 alternative and was moved
from Sep 26 to Dec 10; the other 9 years are unchanged (most have zero Q4 captures at all, see that script's
README section / `dataset_construction_decisions.md` `O8`). Re-running *this* script afterward against the
freshly re-downloaded raw files confirmed **all 10 currently-staged years match byte-for-byte**, including
2024's new pin. Two consecutive runs each hit a transient CDX-API timeout on a different subset of years
(2015 in one run, 2024/2025 in the other) — every year that succeeded in both runs agreed exactly on
timestamp/digest/rank, and the two runs' successful years don't overlap in their failures, so the merged
result in `summary_by_year.csv` is a complete, verified record despite neither individual run finishing
clean. `wayback_q4_repin.R`'s own `check_completeness()` doesn't do this byte-level check (there's no staged
ground truth to compare a Q4 capture against) — this script is what actually proves 2024's new pin is correct.
