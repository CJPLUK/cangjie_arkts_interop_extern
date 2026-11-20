# Write each op's worst-case locals as a sum of named units

## Where

`arkts_runtime/native/ops.cpp`:
- `kWorstGetNamed = 3 + kUnitFreshHeap` (line 8);
- the `OpPlacement` sizes `2 + worstArg(...)` (217), `2 + kUnitFreshHeap` (247), `1 + worstArg(...)` (268), and the call's `worst` (306);
- the `place.units += ...` charges after each engine call.

## Problem

Each op declares its worst case as bare integers. What the terms stand for (receiver fetch, key, result, fresh heap result) lived only in comments, which are now deleted. The charge made on exit is computed separately from the declared worst case, so the two can drift apart, and a charge above the worst case breaks the budget's Bound invariant (ADR-0002).

## Suggested reshape

Name the units an op can spill (for example `kUnitReceiverFetch`, `kUnitKey`, `kUnitResult`) and write each worst case as a sum of them. Better still, describe each op's locals once and use that one description for both `admit` and the exit charge.

## Done when

No bare integers in placement sizes; `budget_test` and the step13 lifetime scenarios pass.
