# Split State by thread, and give runtime tasks their own type

## Where

- `arkts_runtime/native/state.h`: `struct State` (line 16); `kTaskWake` and `kTaskTurnEnd` (13-14).
- The task dispatch: `arkts_runtime/native/backend.cpp:32-33`.

## Problem

- **Mixed fields:** `State` mixes fields only the owner thread may touch (budget, brackets, `opDepth`, op counters, text buffers) with fields other threads touch (`alive`, `owners`, `postMutex`, the pin atomics, the pin counters). Which is which was documented only in comments, now deleted (ADR-0007).
- **Shared ids:** the runtime's own tasks use the reserved ids 0 and -1 in the same `Int64` space as user task ids. User ids stay at 1 or above by convention only.

## Suggested reshape

- Move the owner-thread fields into their own struct, reachable only after the owner check (for example returned by `opEnter`), so code off the owner thread cannot name them.
- Give the TSFN payload a kind (`User`, `Wake`, `TurnEnd`) next to the id, instead of reserving id values.

## Done when

Only cross-thread fields remain directly on `State`, and no id value is reserved; the device suite passes, including `manyThreads`.
