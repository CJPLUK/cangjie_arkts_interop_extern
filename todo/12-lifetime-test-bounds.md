# Derive the lifetime test's budget bound, and make its turn dependency explicit

## Where

`arkts_runtime/src/tests/step13_lifetime.cj`: `BUDGET_BOUND` (21), `budgetIsEmpty` (67) and its registration (11); the order of scenarios in `Lifetime.test.ets`.

## Problem

- **Duplicated constant:** `BUDGET_BOUND = (1 << 19) + 128` copies the native `kCapacity` and a worst-case allowance; a change to either on the native side silently invalidates the test.
- **Hidden dependency:** `budgetIsEmpty` passes only because the runner calls it in a later turn than `fusedOpsSpill`, and its name hides that.

## Suggested reshape

- Expose the capacity and the largest admitted worst case through `ats_rt_ext_stats`, and compute the bound from them.
- Have the ArkTS side wait for the next turn before calling the check, and name the check after what it asserts, for example `budgetEmptyNextTurn`.

## Done when

No copied constant; the turn dependency is visible in the test itself.
