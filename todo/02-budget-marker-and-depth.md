# Make posting the turn marker one call

## Where

- `arkts_runtime/native/budget.h`: `wantsMarker`, `markerPosted` and `turnEnded` (26-28).
- The caller: `arkts_runtime/native/ops.cpp:32`.

## Problem

- **Marker:** posting it is a protocol the caller must get right. It calls `wantsMarker()`, posts, and calls `markerPosted()` only if the post succeeded. A second caller could get the order wrong.

## Suggested reshape

- Fold the protocol into one call that takes the post as a function, for example `budget.markerPost([&] { return statePost(s, kTaskTurnEnd) == napi_ok; })`.

## Done when

One call at the call site; `budget_test` passes.
