# diagnostics/tables — HTML section builders for the docs site

One script per source, each defining `build_<asset>_section()` that returns a single HTML `<section>` for the
documentation site. Sourced by [`../build_site.R`](../build_site.R), which concatenates the sections into
`docs/index.html`. Built **directly from `data/raw/`** with the same computations + curated content as the old
CAA_Project `*_table.xlsx` workbooks (ported verbatim).

- `_html.R` — shared HTML rendering primitives (table/section helpers, escaping).
- `<asset>.R` — one per ICIS-Air / AFS / emissions source (16 total): `facilities`, `violations`,
  `inspections`, `formal_actions`, `informal_actions`, `certs`, `stacktests`, `pollutants`, `programs`,
  `program_subparts`, `afs_actions`, `afs_air_program`, `afs_facilities`, `afs_hist_compliance`, `afs_hpv`,
  `emissions`.

These are **documentation/reporting**, not part of the data build — hence their home under `diagnostics/`.
Run via `Rscript code/diagnostics/build_site.R` (set `SKIP_SECTIONS=emissions` to skip the ~900 MB read).
