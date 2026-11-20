# Make the kind of handle-scope bracket visible at call sites

## Where

`arkts_runtime/src/native_session.cj`: `scopeOpen` (81), `userScopeOpen` (83), `bracketOpen`, `scopeClose` (99), and their 14 call sites.

## Problem

Two functions differ only by a flag. A generic bracket holds `napi_value`s, so pins must not drain while it is open; `newScope`'s bracket holds none (ADR-0003). Nothing at a call site shows which one it is, and both return a raw scope pointer that must be passed back to `scopeClose`.

## Suggested reshape

Return a bracket value of a named kind (for example `GenericBracket` or `UserBracket`, or one type carrying a `BracketKind`) with its own `close()`. Or replace the try/finally at each call site with `withBracket(kind) { ... }`.

## Done when

No raw scope pointer in callers, and the kind is named at every call site.
