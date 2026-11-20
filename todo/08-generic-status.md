# Replace the AR_GENERIC sentinel with a type

## Where

- `arkts_runtime/src/native_api.cj:14`: `AR_GENERIC = -100`.
- Its uses in `arkts_runtime/src/runtime.cj`: 178, 256, 314.

## Problem

An `Int32` status mixes the native library's statuses with a Cangjie-side value meaning "the fused path does not apply, take the generic one". A native status that happened to equal -100 would be read as that.

## Suggested reshape

Have the fused attempt return `?Int32` (`None` means take the generic path), or an enum such as `Done(status)` or `Generic`.

## Done when

`AR_GENERIC` is deleted.
