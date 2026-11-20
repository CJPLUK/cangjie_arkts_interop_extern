# Classify call arguments once, without placeholders

## Where

`arkts_runtime/src/runtime.cj`: `noTexts` (348), `callFused` (350-382), `callArgOf` (385), `textOfArg` (399), `receiverArgOf` (411), `plainArg` (747).

## Problem

- **Placeholder:** `callArgOf` returns `textArg(CPointer(), 0)` for text. `callFused` later re-derives the text with `textOfArg`, which matches the value again and throws `IllegalStateException` on cases that cannot happen, then patches the placeholder.
- **Shared list:** `noTexts` is a shared mutable `ArrayList` that must never be added to.
- **Unreachable arm:** `receiverArgOf`'s `Text(_) => None` can never match, because member access rejects string receivers.
- **Partial function:** `plainArg` throws on inputs its parameter type allows.

## Suggested reshape

- Classify each argument once into a type that carries what the op needs, for example `Plain(NativeArg)` or `Text(String)`.
- Hold the texts in a local array sized from that classification.
- Narrow the parameter types so that `plainArg` and `receiverArgOf` accept only the cases they handle.

## Done when

No placeholder, no shared list, and no `IllegalStateException` in these helpers; the diff suite passes.
