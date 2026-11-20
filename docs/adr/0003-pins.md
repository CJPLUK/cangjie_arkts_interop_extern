# ADR-0003: Values held by Cangjie are strong references, read by alias and deleted on the JS thread

Status: accepted

## Context

A Cangjie `Extern<ArkTSRuntime>` that holds an object, function or long string must keep the engine value alive for as long as the Cangjie value lives. Cangjie frees objects from its own GC, on finalizer threads, at any time. The engine allows reference deletion only on its own thread.

## Decision

### Pins

Each held engine value is a pin (`AtsRtExtPin`, `native/pins.h`): one strong reference (`napi_create_strong_reference`), owned by exactly one Cangjie `Pinned` (`src/native_values.cj`).

### Reading a pin

How a pin is read is probed once, at bind (`PinTable::probe`). Inside a scope, two reads of a fresh strong reference return the same `napi_value` if and only if the engine hands out the reference's own global slot.

- **Alias.** When the engine does hand out the slot (ArkTS does), the slot is read once, at pin creation. It stays valid until the reference is deleted, in any scope, with no engine call. Every later read is a field load.
- **Fetch.** Otherwise, every read is `napi_get_strong_reference_value`, which creates a local per read. The budget charges that local (ADR-0002).

### Release protocol

Dropping a `Pinned` runs `ats_rt_ext_unpin` from its finalizer, on any thread.

- **ExactlyOnce:** there is one `Pinned` per pin, so `ats_rt_ext_unpin` runs once per pin. It is a Treiber push onto a lock-free list, so finalizer threads never block each other or the JS thread.
- **JsThreadDelete:** references are deleted only on the owner thread, in `drain()`.
- **NoDeleteInFlight:** `drain()` runs only while no op or generic bracket is in flight (`opDepth == 0`), and it keeps the pins the starting op was handed. So an alias given to an op stays valid until the op returns, even if its `Pinned` was finalized meanwhile. This matters because Cangjie has no reachability fence.
- **Tombstone:** the environment's cleanup hook drains everything, then swaps the list for a tombstone. A later push only frees the bookkeeping.
- **Liveness:** the push that finds the list empty posts one wake task to the JS thread (`kTaskWake`), unless one is already queued, so finalized pins are deleted even when no op runs.

### Brackets

Two kinds of bracket open a handle scope:

- **Generic brackets** (`NativeSession.scopeOpen`, with `ATS_RT_EXT_SCOPE_IN_FLIGHT`) hold `napi_value`s, so they count as in flight: no pin is deleted until they close.
- **`ArkTSRuntime.newScope`'s bracket** (`userScopeOpen`) holds no `napi_value`, so pins may drain inside it.

### Ownership of `State`

Each pin holds one counted share of `State`, released after its reference is deleted. So `State` outlives every pin, including pins finalized after the environment was torn down.

## Consequences

- Reading a held value costs a load, not an engine call.
- Releasing never blocks a Cangjie thread.
- Deletion is deferred to the next drain point: an op at depth 0, a wake task, or cleanup.
- Some fields mean different things in different modes:
  - `alias` is null in Fetch mode;
  - `push` returns `bool`, meaning "post a wake";
  - `state` is a raw pointer that carries a reference-count share.

  See `todo/04`.
