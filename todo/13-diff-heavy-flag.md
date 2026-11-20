# Fold Program.heavy into offThreadRuns

## Where

- `arkts_runtime/testapp/entry/src/ohosTest/ets/test/DiffPrograms.ts`: `heavy` (77), its two uses (472, 496), `programHeavy` (642).
- `Diff.test.ets:40`.

## Problem

`heavy` does not say what it does: skip the off-thread run. A second field, `offThreadRuns`, already controls how many off-thread runs a program gets.

## Suggested reshape

Use `offThreadRuns: 0` for the two programs and delete `heavy` and `programHeavy`.

## Done when

One field controls off-thread runs; the differential suite runs the same set of programs.
