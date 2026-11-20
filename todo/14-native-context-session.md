# Give the environment one class, or give NativeContext and NativeSession one job each

## Where

- `arkts_runtime/src/native_context.cj`: `NativeContext` (39-191); its forwarders `getNapiEnv`, `isOnOwnerThread` and `runtimeFrame` (44-46).
- `arkts_runtime/src/native_session.cj`: `NativeSession`.
- `arkts_runtime/src/runtime.cj`: `ArkTSRuntime.context` (43, 53, 65), and the 38 `context.session.` chains under `src/`.

## Problem

The glossary has one concept here, the environment, but the code splits it over two classes with no clear line between them:
- `NativeSession` holds the native state, dispatch, frames and the pin cache.
- `NativeContext` holds the value factories (`object`, `array`, `function`, `external`, `requireArkModule`, ...), plus three members that only forward to the session.

`ArkTSRuntime` keeps a `NativeContext`, yet most of its work goes through `context.session.`, so callers must know both classes and which one owns each member.

## Suggested reshape

Either:
- **One class:** fold the factories into the class that owns the state, so `ArkTSRuntime` holds that one object and the forwarders go; or
- **One job each:** keep the factories apart under a name that says so (for example `ValueFactory`, built from a session), have `ArkTSRuntime` hold the session directly, and delete the forwarders.

## Done when

No forwarding members; nothing reaches through `context.session`; the device suite passes.
