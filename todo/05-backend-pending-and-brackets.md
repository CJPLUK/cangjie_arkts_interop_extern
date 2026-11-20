# Put the pin counter's ordering, and the frame stack's growth, behind a type

## Where

`arkts_runtime/native/backend.cpp`:
- `Pins::push` (71-86): `pending.fetch_add` before the pin is published;
- `drain` (88-104): the decrements;
- `ats_rt_ext_open_scope` (177-186): `openFrames.reserve` before `napi_open_handle_scope`.

## Problem

Two orderings are correct only for reasons that are now written nowhere in the code:
- **`pending`:** it is incremented before the pin is published, so a drain that takes the pin never sees `pending` below zero.
- **The frame vector:** it grows before the scope opens, so the `push_back` after the open cannot throw with the scope open.

## Suggested reshape

- Make the death list a type whose `push` and `take` maintain `pending` themselves, so the ordering lives in one place.
- Give the frame stack a `push` that cannot fail once the scope is open: grow it outside `open_scope`, or use a fixed capacity checked before opening.

## Done when

No raw counter updates outside the list type; `open_scope` has no `reserve` line; the lifetime suite passes.
