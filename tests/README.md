# tests — invariant checks on the built assets

Light, dependency-minimal checks that the cleaned assets satisfy the invariants the pipeline promises. Run
**after** a build (they read `data/processed/`).

```sh
Rscript tests/test_assets.R
Rscript tests/test_schema.R
```

| file | checks |
|------|--------|
| `test_assets.R` | every event asset carries `dup`/`dup_exact`; `dup_exact == 1 ⇒ dup > 0` (a byte-identical row is never the first occurrence); prints row/col/distinct-event counts |
| `test_schema.R` | **stub** — planned: required columns present, keys non-missing, `dup==0` count matches the distinct-event count, row-count range guards against silent source changes |

## What they guard

The cleaning contract is "keep every column and every row; only add flags," so these assert the **flags
behave** rather than re-deriving the data. The key invariant is that `dup`/`dup_exact` are internally
consistent, so `filter(dup == 0)` reliably reproduces the event-level (deduplicated) view. See
[`code/02_cleaning/README.md`](../code/02_cleaning/README.md).

> After any change to the cleaning functions or parameters, run `test_assets.R` **and** re-verify byte
> identity of the processed assets (`gzip -dc … | md5`) against a pre-change baseline — a cleaning change that
> alters outputs must be surfaced, not silently accepted.
