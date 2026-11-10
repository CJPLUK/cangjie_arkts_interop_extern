# Direct N-API backend

`ArkTSRuntime` implements the simple `Extern` contract: each member read, index operation,
update and call is dispatched individually. The compiler passes evaluated values; this
backend does not build expression trees or batch unrelated operations.

The core Cangjie package imports only standard-library packages. Its private implementation
is split between `native_api.cj` (C ABI declarations), `native_values.cj` (local values and
owned references), `native_context.cj` (factories and callback registries), and
`native_session.cj` (thread dispatch and scopes). All `ArkTSRuntime` members remain in its
single declaration in `runtime.cj`.

| Operation | Native mechanism |
| --- | --- |
| Binding | Borrow `napi_env` on the JS thread and capture native thread identity |
| Local lifetime | `napi_open_handle_scope` / `napi_close_handle_scope` |
| Retained lifetime | A strong `napi_ref`; a private box is used only if the implementation rejects the value type |
| Property/index access | `napi_get_property`, `napi_set_property`, `napi_get_element`, `napi_set_element` |
| Calls | `napi_call_function`, preserving an extracted method's retained receiver |
| Callbacks | `napi_create_function` and a finalizer that removes the Cangjie closure root |
| Worker-to-JS dispatch | A per-session N-API thread-safe function |
| Strings and BigInt | Explicit UTF-8/UTF-16 lengths and BigInt sign/word operations |
| Modules | `napi_load_module`; system modules use the host `requireNapi` through N-API |

The C++ bridge in `backend.cpp` handles the native callback ABI, reference release queue and
thread-safe function lifecycle. Its external ABI contains opaque pointers, scalar types and
its own small C-compatible result structures, independent of VM layouts. C++ allocation errors are translated into failure statuses, and Cangjie
callback bodies catch exceptions before returning to C. The implementation uses no private
`ARKTS_*` entry point or global Cangjie interop callback table.

Local values use an immutable Cangjie struct to avoid allocating a wrapper for each access.
A single fast native call decodes type and primitive payload into a 16-byte C result.
Immediate values copy their Cangjie number/boolean/type data and recreate a local N-API value
in the active scope. Heap values use direct strong references, including strings, symbols,
bigints and externals on the validated OpenHarmony targets. If `napi_create_reference` rejects
a primitive with `napi_invalid_arg`, a private box supplies a compatible reference instead.
The direct path avoids both the box allocation and its element lookup. A Cangjie
finalizer queues the reference for deletion; deletion runs on the owning JS thread. Native
state uses explicit ownership so its tombstone remains valid while Cangjie values outlive an
environment.

The hot path uses one `@FastNative` leaf call to validate environment lifetime and the
native OS thread together. It reads the retained session tombstone and thread identity without
allocating, locking, entering N-API or invoking callbacks. Scope entry validates on the native
side. Returning an opaque heap handle does not repeat those checks; the N-API operation that
consumes it validates its environment. Teardown and cross-thread dispatch guarantees remain
in place.

Number, boolean, null and undefined factories copy their payloads in Cangjie with no native
call. They materialize handles only when a native operation needs them. Factories with known
result types and retained heap references avoid redundant `napi_typeof` calls. Audited
callback-free type, numeric payload, singleton and pending-exception operations use
`@FastNative`. Scope open/close and direct reference creation/read also use fast FFI;
queue draining and compatibility boxing are split into ordinary calls so neither unbounded
release work nor JS allocation is hidden in those fast paths. Short-string copying is bounded
to 128 UTF-16 code units; larger strings retain ordinary FFI and exact-size allocation.
Operations that can execute JS retain normal FFI transitions and explicit pending-exception checks. This includes property access, function calls and array insertion.

Cross-thread calls publish their single result through `SyncCounter`: writes happen before
its decrement, and the waiting caller reads only after the counter reaches zero. This avoids
reacquiring a condition-variable mutex after wakeup. Posting uses a nonblocking, callback-free
fast FFI call; task execution and cancellation remain asynchronous on the owning thread.

Copied immediate scalar conversions can run on the calling Cangjie thread after a lifecycle
check, without posting another task to JS. Conversion readers that may need the VM retain
dispatch. The device test blocks the JS event loop while another native thread reads copied
number, integer and boolean values, ensuring this path does not depend on event-loop progress.

Named-property reads/writes create their keys inside the ordinary native operation. Embedded
NUL keys use explicit-length N-API strings; ordinary keys use named-property APIs. Numeric
property keys are likewise created inside the native read. This removes separate FFI calls
without changing the compiler's operation ordering.

Array construction marshals element kinds, copied primitive payloads and local heap handles
once, then materializes and inserts elements in one native loop. `Array<Float64>` uses pinned
numeric buffers directly, including nested conversions, avoiding per-element wrappers. Input
values are copied before any JS setter can mutate the Cangjie source array. Reading checks
the current array bounds before each element, so getters that shrink the array still fail at
the same index. Getters, throwing accessors and reentrant Cangjie/GC calls keep normal FFI. Checked integer-index reads
combine the array type check, current length check and element read in one native call.
These are implementations of individual operations; the compiler's ordering of independent
`Extern` operations is unchanged. A device regression test keeps both created and read
primitives across closed scopes and collection, then checks their materialized values,
including NaN, negative zero and infinities. The retained-value test also checks strings,
bigints and symbols across scopes and forced JS collection, covering direct primitive references.

When an environment closes, the cleanup hook marks the session dead, drains pending reference
releases and aborts the dispatcher. Pending task callbacks receive cancellation and complete
waiting calls with an exception. Later posts and retained-value reads reject the dead session.
Dropping a retained value after teardown releases its native bookkeeping without entering the
destroyed VM. Binding remains permanent; a destroyed environment is not silently rebound.

JS exceptions are checked and cleared before another operation can run. Operations that can
execute JS also inspect the pending-exception state rather than relying only on the returned
N-API status. Available JS messages and stacks become `ForeignRuntimeException`. Native
argument and module errors use `ArkTSNativeException`; its codes preserve the previous error
categories. Existing member/index behavior is pinned by the device suite, including the
legacy integer-index boundary behavior.

Two helper operations need the engine's JS built-ins invoked through N-API: `Object.keys`
provides own enumerable string keys consistently on the validated targets, and
`Object.defineProperty` preserves refusal-as-exception behavior. The target implementations'
property enumeration filters and property-definition statuses alone did not provide those
semantics consistently.

The supplied apps compile the bridge during hvigor configuration and link/package it with
the NDK C++ runtime. Their `JSModule` registration adapter passes `getNapiEnv()` to `bind`.
An independent consumer is provided in `../standalone`; it initializes Cangjie through its
runtime C API, loads the library from a normal N-API module and packages no Cangjie interop
library. Its Worker test checks environment teardown, task cancellation and late reference
release. The main device suite additionally checks callback capture and finalization exactly
once, raw UTF-16 keys, GC lifetime, exceptions, nested calls and concurrent dispatch.

Measured comparisons against a fresh build of the old backend, remaining per-case differences,
and validation results are recorded in [the performance follow-up](performance.md).

The library release profile uses `-O2` with IEEE floating-point semantics. The test runner
accepts `BUILD_MODE=release`; signed-zero and error-propagation checks pass in optimized builds.
The allocation used to provoke `OutOfMemoryError` escapes the dispatched closure so the
optimizer cannot replace the allocation with a constant size.
