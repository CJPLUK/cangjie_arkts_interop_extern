# Type the pin table's results and ownership

## Where

- `arkts_runtime/native/pins.h`: `AtsRtExtPin` (16-21), `Pins::push` (39).
- `arkts_runtime/native/backend.cpp`: `Pins::value` and `Pins::push` (66-86), and the `release(s)` calls in `push` and `drain`.

## Problem

- **`push`:** it returns `bool`, meaning "the caller must post a wake".
- **`alias`:** it is non-null exactly when the table is in Alias mode. The pin's validity depends on another object's state.
- **`state`:** a raw `State *` that carries one reference-count share, released by hand with `release(s)` on three paths.

## Suggested reshape

- Return an enum from `push`, for example `Queued`, `QueuedWakeNeeded` or `Freed`.
- Make `Pins::value` switch on the table's read mode instead of testing `alias` for null.
- Hold the `State` share in a small RAII type that releases it in its destructor.

## Done when

No `bool` result from `push`; no manual `release` calls; the lifetime suite passes.
