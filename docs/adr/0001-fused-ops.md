# ADR-0001: One native call per compiler operation (fused ops)

Status: accepted

## Context

The Cangjie compiler lowers every use of an `Extern<ArkTSRuntime>` value to a few runtime calls: `memberAccess`, `indexedAccess`, `memberUpdate`, `indexedUpdate`, `functionCall`, `toExtern<R>` and `fromExtern<R>`. A straightforward N-API implementation pays several native transitions per operation: open a handle scope, read the receiver out of its reference, create the key, run the engine call, create a reference for the result, close the scope. ohos.ark_interop, the baseline the runtime is measured against, pays a similar sequence.

## Decision

Each operation whose target is an object or function and whose arguments are plain values is one `extern "C"` call into `libarkts_runtime_native.so` (`ats_rt_ext_get_named`, `ats_rt_ext_set_named`, `ats_rt_ext_element_get`, the call ops; `native/ops.cpp`). Inside that one call the op:

1. checks it is on the owner thread and that the environment is alive;
2. deletes finalized pins if no other op or runtime frame is in flight (ADR-0003);
3. decides where its engine locals live: spilled into the caller's scope, or in a scope of its own (ADR-0002);
4. runs the engine call;
5. returns the result as a copied scalar, copied text (ADR-0004), or a new pin the caller owns (ADR-0003).

No `napi_value` outlives the op.

Arguments cross as `ats_rt_ext_arg`: tag 0 a scalar, 1 a pin, 2 UTF-8 text the caller holds for the duration of the op.

Everything else takes the generic path in Cangjie (`native_values.cj`), inside a runtime frame:

- string receivers;
- element indices at or above `UInt32.Max`;
- argument types that need a conversion the op cannot do itself.

On the Cangjie side the status `AR_GENERIC` (-100) means "the fused path does not apply". It is not a native status.

### Threads

Off the owner thread, a fused op returns `ATS_RT_EXT_NOT_OWNER` having run nothing. The Cangjie side then posts the operation to the owner thread through a threadsafe function and blocks until it has run (`ArkTSRuntime.run`, `NativeSession.runPosted`).

### Kinds of FFI declaration

- **Ordinary `foreign func`:** the fused ops, because they run JS (getters, setters, callees), and JS may call back into Cangjie. Deleting references is also ordinary FFI, because a drain does an unbounded amount of work.
- **`@FastNative`:** only short engine calls that never run JS, such as typeof, number and string reads, and creating primitives.

## Consequences

- An operation costs one native transition plus the engine call.
- There are two paths, fused and generic, and they must give identical results. The differential suite (ADR-0008) checks this program by program, against ark_interop and against plain ArkTS.
- Each op states by hand the largest number of locals it can spill (`kWorstGetNamed` and the `2 +` terms in `ops.cpp`). See issue #1.
