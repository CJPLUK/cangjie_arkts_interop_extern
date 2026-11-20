# ADR-0008: Prove semantics against ark_interop with differential programs

Status: accepted

## Context

The runtime must behave exactly like the ohos.ark_interop library it replaces: the same values, the same error types and messages, and the same `this` binding. Unit tests that state expected values by hand check only what their author thought of.

## Decision

Each differential program in `testapp/entry/src/ohosTest/ets/test/DiffPrograms.ts` exists in three variants, and their transcripts must be identical line for line:

- **Reference: plain ArkTS** (`DiffPrograms.ts`). Where the Extern contract differs from plain JS, the program spells out the contract: extracted methods keep `this`, `Int64` is a bigint, `Option`, `String` conversion.
- **Interop variant: Cangjie with ark_interop** (`diff_interop/interop.cj`), written as an ark_interop user would. Where the Extern contract decides an outcome (contract errors, extracted methods keeping `this`), the program checks it by hand.
- **Extern variant: Cangjie with `Extern<ArkTSRuntime>`** (`diff_extern/extern.cj`).

How the programs run:

- Every program gets a fresh world from `world()`.
- Transcripts are `label=value` lines, formatted by `difflog.cj` and by the matching helpers in `DiffPrograms.ts`.
- An escaping exception ends a transcript.
- `attempt` logs:
  - `ok`;
  - `js:<whether the JS error text contains a fragment>` for a JS throw;
  - `contract` (member, function, conversion, index) for an error the Extern contract raises.

`Diff.test.ets` runs, for each program:

1. the reference;
2. the interop and Extern variants on the owner thread;
3. the Extern variant again on a spawned thread. This runs `offThreadRuns` times: once by default, more for programs that race threads, and not at all (`offThreadRuns: 0`) for programs with too many operations to run through posting.

### The thread program

Off the owner thread, the Extern variant of `manyThreads` starts eight thread bodies together on a barrier, while another thread runs the Cangjie GC. Each body touches only its own slot and the read-only shared object, so the transcript does not depend on the interleaving.

On the owner thread the bodies run one after another, because a spawned thread's operations would wait for the owner thread, which would be waiting for them. ark_interop runs only on the owner thread.

### Lone surrogates

Strings with lone surrogates are compared through `wellFormed` and `convertible`. A Cangjie `String` built from a lone surrogate holds invalid UTF-8, and `runes()` throws on it.

## Consequences

- A difference from ark_interop shows up as the first differing line, with all three transcripts dumped to the log.
- New behaviour needs a program in all three variants.
- Behaviour that only Extern has (conversions to interfaces, `Float16`, `BigInt` edges) has no reference here. It is covered by the step tests in `src/tests`.
