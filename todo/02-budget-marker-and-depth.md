# Make posting the turn marker one call, and rename HostBudget::depth

## Where

- `arkts_runtime/native/budget.h`: `depth` (line 17); `wantsMarker`, `markerPosted` and `turnEnded` (26-28).
- The caller: `arkts_runtime/native/ops.cpp:32`.

## Problem

- **Marker:** posting it is a protocol the caller must get right. It calls `wantsMarker()`, posts, and calls `markerPosted()` only if the post succeeded. A second caller could get the order wrong.
- **Depth:** `HostBudget::depth` counts known frames (ADR-0002), but its name reads like `State::opDepth`, which counts ops in flight.

## Suggested reshape

- Fold the protocol into one call that takes the post as a function, for example `budget.markerPost([&] { return statePost(s, kTaskTurnEnd) == napi_ok; })`.
- Rename `depth` after what it counts, for example `framesOpen`.

## Done when

One call at the call site; no field named plain `depth`; `budget_test` passes.
