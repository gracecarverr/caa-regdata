> **Status:** draft — [ ] verified against the current script (Claude, 2026-07-30)

# `01_download.R` — acquire all raw sources into `data/raw/`

## Purpose in the pipeline
> **TODO (Grace):** write the 1-2 sentence purpose blurb here — why this script exists and what depends on
> it. Starting material, from the script's own header comment:
> "code/01_data_download/01_download.R -- acquire raw data into data/raw/ (immutable) + record provenance.
> Skipped when code/RUN_ALL.R is called with DOWNLOAD=false. Standalone: no shared helpers, no config.
>
> Fetches ICIS-Air, AFS, combined emissions, the CAA Compliance Pipeline dataset, FRS facility/program-link
> data (all from the same EPA ECHO bulk directory), US county boundaries, and the ICIS-Air Wayback annual
> snapshots (pinned to specific confirmed captures -- see below). Idempotent throughout: if a source's files
> are already present it does nothing (raw is immutable). Records a provenance row per extracted file in
> data/raw/MANIFEST.csv (source, file, url, downloaded_at, md5)."

## Inputs & outputs
- **Input:** none (fetches from the internet — EPA ECHO bulk downloads, Internet Archive Wayback Machine,
  Census TIGER).
- **Output:** many files across `data/raw/` (10 ICIS-Air tables × current + 10 Wayback years, 5 AFS tables,
  emissions CSV, pipeline CSV, 2 FRS tables, county shapefile components) plus `data/raw/MANIFEST.csv` — one
  provenance row per extracted file; unit of analysis is **one extracted raw file**, keyed by `source` +
  `file`.

Example — first 4 rows of `data/raw/MANIFEST.csv` (sampled from disk, 2026-07-30):

| source | file | url | downloaded_at | md5 |
|---|---|---|---|---|
| icis_air | ICIS-AIR_FACILITIES.csv | https://echo.epa.gov/files/echodownloads/ICIS-AIR_downloads.zip | 2026-07-26T16:26:00-0400 | c3f69659bf3c382d3309c2db820f1d12 |
| icis_air | ICIS-AIR_FCES_PCES.csv | https://echo.epa.gov/files/echodownloads/ICIS-AIR_downloads.zip | 2026-07-26T16:26:00-0400 | b5b934ceead932a5007be53cb546db96 |
| icis_air | ICIS-AIR_FORMAL_ACTIONS.csv | https://echo.epa.gov/files/echodownloads/ICIS-AIR_downloads.zip | 2026-07-26T16:26:00-0400 | df324152e33df18a475d4c81b5c0eab8 |

MANIFEST.csv currently has 75 rows (data + header) on disk. Note: rows only exist for files this script
actually (re-)downloaded — the Wayback files already staged on disk before automation predate this script
and have no MANIFEST row (see gotchas).

## At a glance
| | |
|---|---|
| **Input** | none (network fetch) |
| **Output** | `data/raw/*` (~9.8GB total on disk; `ICIS_AIR_WAYBACK/` alone is ~6.4GB, `ICIS-AIR_downloads/` ~791MB, `afs_downloads/` ~851MB) + `data/raw/MANIFEST.csv` |
| **Runtime** | not measured directly, but idempotent — no-op (seconds) if all sources already staged; a full fresh run would move ~9.8GB over the network plus 8-retry-capped large-file fetches, likely tens of minutes |
| **Requires** | nothing upstream — first data-touching script in the pipeline |
| **Dependencies** | `readr` (only for `write_csv()` on MANIFEST rows); shells out to system `curl` directly (not `download.file`) |

## Walkthrough
1. **`record_provenance()`** appends one row to `data/raw/MANIFEST.csv` per extracted file: source tag,
   basename (not full path), source URL, local ISO-8601-ish timestamp, and md5. Called after every successful
   extraction.
2. **`fetch_zip()`** — the shared download primitive. HEAD-probes the URL first (`curlGetHeaders`) to learn
   the expected `Content-Length`, then shells out to `curl -L -C - --retry 3 --retry-delay 5 --max-time 300`
   up to 8 times, resuming (`-C -`) from wherever the partial file currently ends rather than restarting from
   zero — needed because some EPA endpoints (observed on FRS's `national_combined.zip`) drop mid-transfer on
   large single-file downloads. Success requires the file to be at least `min_bytes` **and** within 1% of the
   expected `Content-Length` (or no expected size was determined at all).
3. **Six ECHO bulk sources**, each with the same idempotency shape (skip if expected file(s) already exist,
   else download-unzip-record): ICIS-Air (10 tables), AFS (5 tables), combined emissions (1 CSV), CAA
   Compliance Pipeline (1 CSV), FRS (2 of 4 tables used), US counties (Census shapefile, renamed to
   `us_counties.*` and trimmed to the 5 components the pipeline needs).
4. **Wayback loop** — the most bespoke section. Iterates `WAYBACK_TIMESTAMPS`, a hand-pinned
   year→capture-ID map for 2015–2017 and 2019–2025 (10 years; 2018 excluded, see gotchas). Builds an
   Internet-Archive `id_`-modifier URL (raw byte-for-byte replay, no HTML rewriting) for each pinned
   timestamp, fetches it through the same `fetch_zip()` (with a higher 1MB `min_bytes` floor), and unzips
   into a per-year folder. `wayback_expected_tables()` special-cases 2015, whose capture predates EPA's table
   rename (`ICIS-AIR_HPV_HISTORY.csv` instead of `ICIS-AIR_VIOLATION_HISTORY.csv`).

## Notes & gotchas
- **Wayback pins are fixed timestamps, not a live search — deliberately.** Quoted from the script header:
  "Pinned to the exact capture confirmed byte-for-byte against the staged files by
  code/diagnostics/wayback_verify/wayback_verify.R... NOT a live 'latest capture' search: a live search is
  what previously produced a false '2016 doesn't reproduce' conclusion (its true match is a capture 5 days
  older than the latest one that year; 2022 has the same pattern)." ⚠️ Never "simplify" this to a live
  latest-capture lookup — it silently produces wrong data for at least 2016 and 2022.
- **2018 has zero real captures.** "2018 is NOT automated here -- the Internet Archive has ZERO captures of
  this URL at any status code for 2018 (the staged '2018' data was found to be a mislabeled duplicate of 2019
  and was deleted from data/raw/, W7); there is no capture to pin." ⚠️ Any downstream code that assumes every
  year 2015–2025 has a Wayback folder will break on 2018.
- **Not every pinned snapshot actually lands in Q4**, even though downstream cleaners treat each year as "the
  ~Q4 state of year Y." Quoted: "only 2016/2020/2021/2022 actually landed in Q4 (Oct-Dec)... the Internet
  Archive simply never crawled this URL in Q4 of 2015, 2017, 2019, 2023, or 2025 (2019 and 2023 have exactly
  ONE 200-status capture in their entire calendar year). Those years' pins are already the best -- in most
  cases the ONLY -- capture available and are left unchanged. **2024 is the one year with genuine Q4
  coverage**... and was re-pinned from its old Sep 26 capture to the Dec 10 one."
- **FRS product mixup, resolved.** The obvious-looking FRS URL is wrong: "the URL previously tried,
  `ordsext.epa.gov/FLA/www3/state_files/national_combined.zip` (~1.26 GB)... is the **wrong product**: a
  33-column multi-table FRS export, not the 10-column `FRS_FACILITIES.csv` this pipeline actually uses
  (different row count too — 5.3M vs. 3.26M rows). The real source... is
  `echo.epa.gov/files/echodownloads/frs_downloads.zip`." ⚠️ If FRS coordinate data ever looks structurally
  different than expected, check which of these two URLs is in play.
- **`fetch_zip`'s Content-Length regex has a latent bug on Wayback responses**, per the script's own
  `REVIEW(bug)` comment: it greedily matches the *last* `content-length:`-containing string in the
  concatenated headers, and Wayback responses also carry an `x-archive-orig-content-length` header whose name
  contains that substring — so on Wayback fetches the regex actually extracts
  `x-archive-orig-content-length`, not the real response `Content-Length`. "In every case checked here the two
  values are identical, so this hasn't caused a false failure -- but that's incidental, not guaranteed." ⚠️
  Silent-failure risk if the Archive ever serves a byte count that doesn't match its own recorded original.
- **Idempotency check granularity varies by source**: ICIS-Air/AFS/FRS/Wayback check for the *full expected
  table set* being present (catches partially-trimmed folders); emissions/pipeline check one exact filename;
  US counties checks one renamed `.shp`. The Wayback per-year check is explicitly an "exact-set check (not
  'any .csv present')... catches the 2022/2023-2025 trimmed folders noted in the file header and re-fetches
  them to the full 10-table set."
- **On-disk folders for 2022–2025 are currently trimmed (9 or 8 of 10 tables)** even though a fresh run would
  produce the full 10-file set — noted as "Harmless: the wayback cleaning scripts... read specific named files
  only, never `list.files()`-glob the directory, so extra tables are simply never read."
- **MANIFEST provenance is incomplete for pre-automation Wayback files**: "The Wayback files already staged on
  disk predate this automation and have no MANIFEST row (raw is immutable — they are not retroactively
  re-fetched just to backfill provenance); any year re-acquired by a fresh `01_download.R` run from here on
  gets a real MANIFEST row like every other automated source." ⚠️ Don't assume `MANIFEST.csv` is a complete
  inventory of every file in `data/raw/`.
- **Green Book / PM2.5 attainment data is intentionally not fetched here** — "that code was already synced to
  the CAA_Project repo (2026-07-23) and lives there now," removed from this repo 2026-07-27.
- Verified by reading the script in full, reading the folder README in full, and sampling `MANIFEST.csv`
  directly off disk. Did not re-run the download (idempotent no-op expected, and would move ~9.8GB — not
  worth doing just to verify a already-current script).
