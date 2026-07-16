# output — generated tables, figures, and run records

Generated artifacts that are **products of code**, not inputs. Rebuilt by re-running the pipeline /
diagnostics; no file here is hand-edited (tweak the script, not the output — project rule).

| path | produced by | what |
|------|-------------|------|
| `sessionInfo.txt` | `code/00_setup/00_setup.R` | R + package versions for the last run (reproducibility record) |
| `tables/*.tex` | `code/diagnostics/05_panel_summaries.R` | `booktabs` LaTeX fragments summarizing the built panels, one `\input`-able `.tex` per table, plus a compilable `panel_summaries.tex` wrapper. Every cell is computed from the panels — no hand-entered numbers. |

Compile the panel-summary wrapper with `pdflatex`/`xelatex` on a machine that has the `booktabs` package
(none is needed to *generate* the `.tex`).

> The documentation **site** is written to `docs/index.html` (committed, GitHub Pages), not here — see
> `code/diagnostics/build_site.R`.
