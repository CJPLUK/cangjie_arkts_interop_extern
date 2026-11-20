# ADR-0002: Leak op locals into the caller's scope, bounded by a host budget

Status: accepted

## Context

Every engine value an op creates (the key, the result, the receiver when it must be fetched) is a handle-scope local. It stays alive, and keeps its value alive, until the scope it was created in closes. Opening and closing a scope per op is one of the costs ADR-0001 removes. The alternative is to let the locals land in whatever scope is open, normally the one around the ark_interop export or the JS-called function. That scope's lifetime is outside the runtime's control, so a long loop of ops in one turn would grow it without limit.

## Decision

`HostBudget` (`native/budget.h`) decides for each op where its locals live. It is pure: no N-API, no threads, no allocation. It lives in `State` and is touched only on the owner thread.

- **Leak or scoped.** Before creating any local, an op asks `admit(worst)`, where `worst` bounds the units it may leak.
  - If `units + worst <= kCapacity`, the op **leaks**. Its locals go into the scope on top, and afterwards it `charge`s the units it actually leaked.
  - Otherwise it runs **scoped**: it opens and closes its own scope.

  Leaked locals are never read after the op returns. They only occupy slots, and root their values, until the caller's scope closes.
- **Units.**
  - A local weighs `kUnitLocal` (1).
  - A fresh heap result weighs `kUnitFreshHeap` (64), because it can root an arbitrary object graph.
  - Created text weighs 1 per 512 bytes.

  `kCapacity` is 2^19 units: at most 4 MiB of handle slots, or 8K fresh heap results per turn or frame.
- **Known frames.** The runtime's own scopes are known frames: callback trampolines, TSFN tasks, generic brackets, and `ArkTSRuntime.newScope`. Each saves `units` on entry (`enter`) and restores it on exit (`exit`), because everything leaked above its scope died when the scope closed.
- **Turn marker.** At depth 0 the caller is one the runtime cannot see. The first leak there posts a TSFN task, the turn marker. The marker runs once the JS stack has unwound, and resets `units` to 0 (`wantsMarker`, `markerPosted`, `turnEnded`).

## Contract

At depth 0, the caller's scope must close before the turn marker runs.

- **Met automatically:** ark_interop exports and JS-called functions. The engine closes the host scope of a JS turn before a TSFN task runs.
- **Must wrap their work in `ArkTSRuntime.newScope`:** Cangjie UI handlers and `postJSTask` bodies. Otherwise every value they create stays alive until the root scope, which never closes.

## Invariants

- **Bound:** `units <= kCapacity` + the largest `worst` ever admitted.
- **Sound:** `units >=` the weight of leaked locals not yet reclaimed, given the contract.

## Verification

`native/budget_test.cpp` checks both invariants against a simulated engine scope stack. The simulation encodes the engine's rule, not the budget's:

- a scope frees everything leaked into it when it closes;
- scopes close last-in, first-out;
- the root scope never closes.

Unseen callers open a host scope per turn, known frames are scopes the runtime opens, and foreign code may open and close scopes in between. The test runs:

- random walks;
- long turns that fill the budget, after which ops run scoped;
- frame restores, checked directly;
- a negative control that breaks the contract, so ops leak into the root and Sound must be seen to fail.

Run it on the host:

```sh
c++ -std=c++17 -O2 arkts_runtime/native/budget_test.cpp -o budget_test && ./budget_test
```

On the device, `src/tests/step13_lifetime.cj` checks the budget through the native stats (`ArkTSRuntime.nativeStats`):

- 10K fresh results in one turn stay within the bound;
- a later turn finds the budget empty;
- `newScope` restores the budget even when its body throws.

## Consequences

- In the common case no op opens a scope.
- A turn that creates more than the capacity costs one scope per op from then on.
- The contract is a rule users must follow. Breaking it leaks memory; it never causes a crash.
