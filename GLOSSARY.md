# ArkTS Runtime for Cangjie

A runtime that gives Cangjie's `Extern<ArkTSRuntime>` values their meaning on OpenHarmony, as a faster replacement for ohos.ark_interop that behaves identically to it.

## Language

### Semantics

**Extern contract**:
What `Extern<ArkTSRuntime>` promises its users: the values, errors and `this` binding each operation produces, which must match ark_interop.
_Avoid_: runtime contract, semantics

**Contract error**:
An error the Extern contract itself raises (a missing member, an uncallable function, a failed conversion, a bad index), as opposed to an error thrown by JS.
_Avoid_: runtime error, access error

### Execution

**Operation**:
One of the things the compiler lowers Extern syntax to: member or indexed access, member or indexed update, a function call, or a conversion to or from Extern.
_Avoid_: op (for this sense), access, call

**Fused op**:
A single native call that runs a whole operation on the fast path, from the thread check to the result. Shortened to **op**, which never means an operation.
_Avoid_: native op, fast op

**Generic path**:
The slower way an operation runs when no fused op applies, inside a runtime frame.
_Avoid_: slow path, fallback

**Type probe**:
A preallocated value of a known type, matched against a conversion's target type to tell what that type is at run time without building type information.
_Avoid_: probe (alone)

**Reflective conversion**:
A conversion that finds its target type by asking the type system at run time; correct for every type but costly, so it runs only when type probes cannot decide.
_Avoid_: slow path, slow conversion

### Values

**Payload**:
What an `Extern<ArkTSRuntime>` value carries: an immediate (undefined, null, boolean or number), text, a pin, or a method (a function together with the receiver it was read from).
_Avoid_: handle, Extern handle

**Pin**:
An engine value that Cangjie keeps alive by owning a strong reference to it, released when its Cangjie owner is finalized.
_Avoid_: reference, Ref, held value, Pinned

**Pin cache**:
A small, lossy cache that remembers the pin last read for each (receiver, key) member read, so a repeated read of an unchanged value reuses that pin instead of creating another.
_Avoid_: intern table, interning

**Hint**:
A pin the pin cache offers a fused op as the likely result; the op uses it only if the value it reads is strictly equal, so a stale hint costs a miss, never a wrong value.
_Avoid_: cached value

### Threads

**Environment**:
The JS engine instance the runtime is bound to. A process binds at most one.
_Avoid_: context, session, engine instance

**Bind**:
Attaching the runtime to an environment, on the thread that becomes its owner thread; it happens once per process.
_Avoid_: attach, initialize

**Owner thread**:
The one thread allowed to touch an environment's engine values: the JS thread the environment was bound on. Every other thread must post its work there and wait.
_Avoid_: JS thread, main thread, UI thread

### Lifetime

**Turn**:
One uninterrupted run of JS on the owner thread, from the start of an event-loop task until the JS stack has fully unwound.
_Avoid_: tick

**Turn marker**:
A task the runtime queues on the owner thread at the first spill into an outer scope; by the time it runs, that turn is over and everything spilled in it has died.
_Avoid_: turn-end task

**Host budget**:
The runtime's running count of what fused ops have spilled into scopes that are still open, against a fixed capacity; an op spills only if its worst case fits, and otherwise runs scoped.
_Avoid_: handle budget, quota

**Unit**:
What the host budget counts in: one per spilled engine value, and more for values that can keep much more alive, such as a fresh heap result or created text.

**In flight**:
Said of a fused op that is running or a runtime frame that is open. While anything is in flight, no pin is deleted.

**Release**:
A pin's Cangjie owner handing the pin back when it is finalized, on any thread and without blocking. The pin's engine reference is deleted later, at a drain.
_Avoid_: delete, free

**Drain**:
Deleting the engine references of released pins, on the owner thread, whenever nothing is in flight.
_Avoid_: sweep, collect, GC

**Scope rule**:
The obligation on code the runtime cannot see: an outer scope must close before its turn ends. Cangjie UI handlers and posted JS tasks meet it by working inside a user frame.
_Avoid_: contract, budget contract

**Frame**:
A handle scope whose opening and closing the runtime sees, so it knows when everything spilled into it dies. Every frame is an engine, runtime or user frame.
_Avoid_: known frame, bracket

**Engine frame**:
A frame the engine opens when JS calls a Cangjie function; the engine also closes it.
_Avoid_: trampoline frame, callback frame, outer frame

**Runtime frame**:
A frame the runtime opens for its own work, inside which runtime code holds raw engine values, so no pin may be deleted until it closes.
_Avoid_: generic bracket, in-flight bracket

**User frame**:
A frame the runtime opens when user code asks for one (`newScope`), inside which only Extern values are held, so pins may be deleted between operations.
_Avoid_: user bracket, user scope

**Outer scope**:
The scope around a call the runtime did not see begin, outside every frame; the runtime cannot tell when it closes and relies on the scope rule.
_Avoid_: depth 0, unseen scope, host scope

**Spill**:
An op leaving the engine values it created in the caller's open scope instead of a scope of its own, deliberately and within the host budget. The opposite is running **scoped**.
_Avoid_: leak

**Stranded**:
Said of values kept alive forever because they were spilled into a scope that never closes, which is what breaking the scope rule causes.
_Avoid_: leaked, memory leak

**Alias check**:
The one-time check, made when an environment is bound, that decides whether pins in that environment are read by alias or by fetch.
_Avoid_: probe, pin probe

**Alias read / Fetch read**:
The two ways an environment reads its pins, chosen by the alias check. An alias read reuses the pin's own engine slot with no engine call. A fetch read asks the engine every time and creates a local.

### Verification

**Differential suite**:
The set of differential programs and the runner that compares their transcripts, on the owner thread and off it.
_Avoid_: diff suite, diff tests

**Differential program**:
A test scenario written three times, once per variant, whose transcripts must match line for line.
_Avoid_: diff program, diff test

**Variant**:
One of a differential program's three versions: the reference (plain ArkTS), the interop variant (Cangjie with ark_interop), or the Extern variant (Cangjie with `Extern<ArkTSRuntime>`).
_Avoid_: A/B/C, version

**Transcript**:
The ordered `label=value` lines a variant records as it runs, which the differential suite compares.
_Avoid_: log, trace, output
