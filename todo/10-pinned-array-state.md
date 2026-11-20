# Type Pinned's array cache and its constructors

## Where

`arkts_runtime/src/native_values.cj`, `class Pinned` (329-360): the two `init`s, `arrayState`, `isArrayHere`, `isArray`.

## Problem

- **`arrayState`:** an `Int8` used as a tri-state (0 unknown, 1 array, 2 not an array), set with the magic `kind == 6`.
- **`isArrayHere`:** returns `false` both for "not an array" and for "unknown, because we are off the bind thread".
- **The two `init`s** (pin a value; adopt a pin a fused op created) cannot be told apart at call sites.

## Suggested reshape

- Use `?Bool` or an enum (`Unknown`, `Array`, `NotArray`) for the cache, and the named `JSType` constant instead of 6.
- Return `?Bool` from `isArrayHere`, so callers handle "unknown" explicitly.
- Make the adopting constructor a named static function, for example `Pinned.adopt(session, cell, kind)`.

## Done when

No magic numbers; the callers of `isArrayHere` handle the unknown case; the device suite passes.
