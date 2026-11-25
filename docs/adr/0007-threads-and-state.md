# ADR-0007: One owner thread per environment; other threads post and wait

Status: accepted

## Context

N-API values may be used only on the thread that owns the environment: its owner thread. Cangjie code that uses `Extern<ArkTSRuntime>` may run on any thread, and Cangjie finalizers run on GC threads.

## Decision

The bound environment has one `State` (`native/state.h`), shared by `backend.cpp` (session, pins, functions) and `ops.cpp`.

### Fields by thread

- **Owner thread only:**
  - the budget (ADR-0002);
  - the open runtime and user frames, innermost last;
  - `inFlightCount` (fused ops and runtime frames in flight);
  - the spill and scope counters;
  - the text buffers. The last string result stays in UTF-8 until `ats_rt_ext_text_take`, so a caller must take it before its next op;
  - each pin's `isArray` (on `AtsRtExtPin`, not `State`).
- **Touched from other threads:** only `alive`, `owners`, `postMutex` and the atomics of the pin table.

The same split holds on the Cangjie side, with one general rule: **no Cangjie-side cache is read or written off the owner thread.** The Cangjie spec makes unsynchronised concurrent access undefined behaviour, and a cache's fields are plain fields. So:

- the pin cache (ADR-0005) is used only after an owner-thread check;
- whether a pin holds an array is cached on the native pin (`AtsRtExtPin::isArray`), not on `Pinned`. The fused element ops find it out after their owner check and return `ATS_RT_EXT_GENERIC` for a non-array; the owner-thread generic paths ask `ats_rt_ext_pin_is_array`.

### Off-thread operations

Operations off the owner thread are posted to it as TSFN tasks (`ats_rt_ext_post`), and the caller blocks until the task has run. Task ids below 1 belong to the runtime:

- `kTaskWake` (0) drains finalized pins;
- `kTaskTurnEnd` (-1) is the budget's turn marker.

`ats_rt_ext_post`, the entry point Cangjie posts through, rejects an id below 1 with `napi_invalid_arg` and queues nothing; native code posts the runtime's tasks by name.

### `postMutex`

`postMutex` serializes every TSFN post against environment cleanup. N-API forbids using a threadsafe function after `napi_release_threadsafe_function(..., napi_tsfn_abort)`, so a finalizer's wake must never reach a TSFN that cleanup has already aborted.

After cleanup, posting returns `napi_closing`.

## Consequences

- The fast path (ADR-0001) only compares the current thread with the owner thread.
- Other threads pay a post and a wait per operation. The differential suite (ADR-0008) runs every program off the owner thread as well, with eight threads at once and a GC thread for the thread program.
- `State` mixes the two kinds of field (kept so: see `.out-of-scope/state-split-by-thread.md`). The runtime's task ids share the `Int64` space with user tasks, but Cangjie cannot post one of them.
