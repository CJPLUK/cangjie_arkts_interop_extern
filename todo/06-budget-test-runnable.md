# Make budget_test.cpp runnable, and its cases named

## Where

`arkts_runtime/native/budget_test.cpp`; `arkts_runtime/native/build.sh`.

## Problem

- **No way to run it:** nothing builds or runs the host test. Its run command was a comment, now deleted; it survives only in ADR-0002.
- **Positional bools:** `run(seed, steps, bool scopeRuleKept, bool expectSound, odds)` takes two of them.
- **Anonymous sections:** the sections of `main` are unnamed blocks, so a failure does not say which case broke.

## Suggested reshape

- Add a host test command, for example `native/test.sh`, or a `test` mode in `build.sh`.
- Replace the bools with an enum or an options struct, for example `ScopeRule::Kept` or `ScopeRule::Broken`.
- Split `main` into named cases (random walks, long turns, frame restore, scoped once full, negative control) that print their names.

## Done when

One command runs it, and a failure names its case.
