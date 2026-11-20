# Make the kind of frame visible at call sites

## Where

`arkts_runtime/src/native_session.cj`: `runtimeFrameOpen` (81), `userFrameOpen` (83), `frameOpen`, `frameClose` (99), and their 14 call sites.

## Problem

Two functions differ only by a flag. A runtime frame holds `napi_value`s, so pins must not drain while it is open; a user frame (`newScope`) holds none (ADR-0003). Nothing at a call site shows which one it is, and both return a raw scope pointer that must be passed back to `frameClose`.

## Suggested reshape

Return a frame value of a named kind (for example `RuntimeFrame` or `UserFrame`, or one type carrying a `FrameKind`) with its own `close()`. Or replace the try/finally at each call site with `withFrame(kind) { ... }`.

## Done when

No raw scope pointer in callers, and the kind is named at every call site.
