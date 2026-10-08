# ArkTS runtime implementation plan

Implementation of `docs/arkts_runtime_design.md` (in `cangjie_interop_architecture`) as a
Cangjie package inside this DevEco project. Every step adds its tests together with its code,
and a step is finished only when its tests and all earlier tests pass.

## Decisions

- **Single runtime.** One concrete, non-generic class:
  `public class ArkTSRuntime <: ForeignRuntime<ArkTSRuntime>`. Values are
  `Extern<ArkTSRuntime>`. The bound context is a plain `static var` guarded by a static
  `Mutex`, as in section 3 of the design.
- **`Int64` / `UInt64` map to `bigint`**, as in the design's type mapping table.
- **Package:** `ohos_app_cangjie_entry.arkts` in `entry/src/main/cangjie/arkts/`.
  `entry/src/main/cangjie/index.cj` stays the module entry point.
- **Toolchain:** `~/.cangjie-sdk/6.1/cangjie/build-tools/bin/cjc` (has `Extern<T>` and
  `ForeignRuntime<T>` in `std.core`). `entry/libs/arm64-v8a/libcangjie-std-core.so` ships the
  matching standard library to the emulator and the phone.

## Constraints found by compiling small probes against this cjc

| Finding | Consequence |
| --- | --- |
| Forced cast `(U)e` does not parse; no flag enables it | Code and tests call `ArkTSRuntime.fromExtern<U>(e)` explicitly |
| Implicit conversion to `Extern<T>` and dynamic `e.f`, `e(...)`, `e[i]` work | Used as designed |
| `match (None<R>) { case _: Option<Int64> => ... }` works | Used for `fromExtern` dispatch |
| `case x: Extern<ArkTSRuntime>` type patterns work | Used in `toJSValue` / `readIndex` |
| `std.reflect` is not available | Not used |
| `JSKeyable` is only `String`, `JSString`, `JSSymbol` (not `Float64`) | Numeric `Extern` indices go through `getElement(Int64)` instead of `getProperty(Float64)` (deviation from the design) |
| `--enable-extern-sequence` exists | Used to test `ExternSequence` in step 10 |
| `std.unittest` is available for macOS | Host tests in layer 1 below |

## Testing strategy

Three layers. Layers 1 and 2 are automated and run at every step; layer 3 is a manual smoke
check.

### Layer 1: host tests (macOS, no ArkTS VM)

`ark_interop` cannot run on macOS, so this layer covers only what does not need a VM:

- **Compiler contract.** A `RecordingRuntime <: ForeignRuntime<RecordingRuntime>` whose `eval`,
  `toExtern` and `fromExtern` record the trees and values they receive. Tests write ordinary
  dynamic syntax and assert the exact tree shape and leaf types. This pins down what the ArkTS
  evaluator relies on (receiver shape for `this`, compound-assignment shape, `Int64` literals
  as leaves, one `eval` per chain) and catches compiler changes before they show up as device
  failures.
- **Pure logic** factored out of the runtime into functions over Cangjie values, e.g. the
  compound-assignment arithmetic on `Float64` / `BigInt` / `String` and JS truthiness.

Location: `hosttest/` at the project root (outside the DevEco build), one `*_test.cj` per
topic, `@Test` classes from `std.unittest`. Run with:

```
cjc --test hosttest/*.cj -o hosttest/run \
    --link-options="-syslibroot $(xcrun --show-sdk-path)" && \
DYLD_LIBRARY_PATH=~/.cangjie-sdk/6.1/cangjie/build-tools/runtime/lib/darwin_aarch64_cjnative \
    hosttest/run
```

wrapped in `hosttest/run.sh`. Pure logic files are shared with the runtime package by
compiling the same source files (they must not import `ohos.*`).

### Layer 2: device tests (emulator and phone, real ArkTS VM)

Instrumented tests in `entry/src/ohosTest` with `@ohos/hypium`, which import
`libohos_app_cangjie_entry.so` and call Cangjie test entry points.

- **Cangjie side:** `entry/src/main/cangjie/arkts_tests/` (package
  `ohos_app_cangjie_entry.arkts_tests`) holds one function per scenario. Each scenario returns
  `""` on success or a failure message (expected vs actual, or the exception class and
  message). `index.cj` exports them through `JSModule.registerModule`.
- **ArkTS side:** `entry/src/ohosTest/ets/test/ArkTSRuntime.test.ets` with one `describe` per
  step and one `it` per scenario, asserting `expect(result).assertEqual("")`.
- **Checks from both sides.** Scenarios receive ArkTS fixture objects as arguments. When
  Cangjie changes a JS value, the ArkTS test checks the effect with plain ArkTS code
  (`expect(rect.width).assertEqual(5)`), independently of our `fromExtern`. When ArkTS
  produces a value, Cangjie checks it after conversion.
- Fixtures in `entry/src/ohosTest/ets/test/fixtures.ets`: `Rectangle` class (`width`,
  `height`, `area()`), `calculator` object, functions that record their `this`, arrays, an
  object with a symbol key, a function that throws, a getter with a call counter.

Build and run (paths from DevEco Studio):

```
HVIGOR=/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
$HVIGOR --mode module -p module=entry@default -p product=default assembleHap
$HVIGOR --mode module -p module=entry@ohosTest -p product=default assembleHap
$HDC install -r <entry hap>; $HDC install -r <entry-ohosTest hap>
$HDC shell aa test -b com.example.externwithenum -m entry_test \
    -s unittest OpenHarmonyTestRunner -s timeout 15000
```

wrapped in `devicetest.sh`, which prints per-test results and exits non-zero on failure. The
exact HAP paths and runner arguments are confirmed in step 0.

### Layer 3: manual smoke check

A button in `Index.ets` that runs the whole device suite and shows the report on screen, for
quick checks on the phone without the test runner.

### Test conventions

- Every public method gets at least one success test and one failure test (expected
  exception type).
- Exceptions are asserted by type, and by message only where the message is part of the
  contract.
- Tests that need an unbound runtime cannot share the process with bound tests (binding is
  permanent). They run first in a dedicated `describe` that executes before anything calls
  `bind`, or are checked through a separate test entry that is invoked before module
  registration binds. Step 2 settles which.
- A failing test is never deleted or weakened to make a step pass; if the expected behaviour
  was wrong, the plan or the design doc is updated first.

## Files

```
entry/src/main/cangjie/arkts/
├── exceptions.cj   ArkTSContextNotBoundException, ArkTSContextAlreadyBoundException
├── runtime.cj      ArkTSRuntime: bind, context, run, ArkTSResult, eval, evalTree, call, index, compound assignment
├── handle.cj       ArkTSHandle (Imm / Ref), retain, evalPayload
├── conversion.cj   toJSValue, toExtern, fromExtern, array helpers
├── operators.cj    pure compound-assignment arithmetic (no ohos imports; also compiled by hosttest)
└── helpers.cj      undefined, null, object, global, symbol, strictEqual, isNull, isUndefined,
                    objectHasProperty, objectKeys, objectDefineOwnProperty,
                    requireArkModule, requireSystemNativeModule
entry/src/main/cangjie/arkts_tests/   device scenarios, one file per step
entry/src/ohosTest/ets/test/          hypium suites and fixtures
hosttest/                             host tests and run.sh
```

All runtime files declare `package ohos_app_cangjie_entry.arkts`. The class body lives in
`runtime.cj`. Members shared across files (`context`, `run`, `evalTree`, `retain`,
`toJSValue`) use the default `internal` visibility. Public helpers in `helpers.cj` are added
with `extend ArkTSRuntime { public static func ... }`. Both points are verified in step 1.

## Steps

### 0. Test infrastructure

Code:
- `hosttest/run.sh` and a trivial host test.
- `RecordingRuntime` in `hosttest/`.
- `arkts_tests` package with one trivial scenario returning `""`, exported from `index.cj`.
- `ArkTSRuntime.test.ets` with one `it` calling it; registered in `List.test.ets`.
- `fixtures.ets`.
- `devicetest.sh`.

Tests (host, compiler contract; these stay as regression tests for the whole project):
- `e.f` → one `eval(ExternMemberAccess(e, "f"))`.
- `e.a.b.c` → one `eval`, three nested `ExternMemberAccess`.
- `e.m(1, "s", 2.5)` → `ExternFunctionCall(ExternMemberAccess(e, "m"), [..])` with leaves of
  type `Int64`, `String`, `Float64` (not converted by `toExtern`).
- `let x = e.m; x(1)` → `ExternFunctionCall(x, [1])`, callee is a payload, not a member access.
- `e[0]`, `e["k"]`, `e[e.k]` → `ExternIndexedAccess` with `Int64`, `String`, and an
  unevaluated `Extern` index tree.
- `e.f = 1`, `e[0] = 1` → `ExternMemberUpdate` / `ExternIndexedUpdate`.
- `e.f += 1`, `e[0] += 1` → `ExternCompoundAssignment(ExternMemberAccess(..), "+", 1)`.
- `x += 1` on a variable `x: Extern` → `x = eval(ExternFunctionCall(ExternMemberAccess(x, "+"), [1]))`.
- `let v: Extern<R> = 42` → `toExtern<Int64>(42)`; array literal `[1, "a"]` as
  `Array<Extern<R>>` → one `toExtern` per element.
- `R.fromExtern<Float64>(e.a.b)` receives the unevaluated tree.
- `f(e.a)` with a normal Cangjie `f` → `eval` happens before `f` runs.

Done when: `hosttest/run.sh` passes; `devicetest.sh` builds, installs, runs the trivial
device test on the emulator and reports PASS; same on the phone.

### 1. Package skeleton and exceptions

Code:
- `exceptions.cj`: `ArkTSContextNotBoundException <: Exception`,
  `ArkTSContextAlreadyBoundException <: Exception`, both with `init()` and
  `init(message: String)`.
- `ArkTSRuntime <: ForeignRuntime<ArkTSRuntime>` with stub `eval` / `toExtern` /
  `fromExtern` throwing `ExternUnsupportedOperation`.
- One `extend ArkTSRuntime { public static func ... }` stub in `helpers.cj`.

Tests (device):
- `index.cj` imports the package and calls a public static from the class body and one from
  the `extend`.
- Stubs throw `ExternUnsupportedOperation` (proves `T.eval` dispatches to our class on device).
- A compile-fail check: a file in `arkts_tests` referencing an `internal` member fails to build
  (run once by hand, not part of the suite; result noted in this plan).

Done when: all tests pass on emulator and phone; the `internal` / `extend` layout is confirmed
or the Files section is updated.

### 2. Context binding

Code:
- `private static let contextMutex = Mutex()`, `private static var context_: ?JSContext = None`.
- `public static func bind(newContext: JSContext): Unit`.
- `static prop context: JSContext`, throws `ArkTSContextNotBoundException` when unbound.
- `public static func isBound(): Bool` (needed by tests and by apps).

Tests (device):
- Before bind: `isBound()` is false, and an operation that reads `context` throws
  `ArkTSContextNotBoundException`.
- Bind succeeds once; `isBound()` becomes true.
- Second `bind` with the same context throws `ArkTSContextAlreadyBoundException`.
- Second `bind` with a different `JSContext` value throws the same exception.
- Concurrency: 8 `spawn`ed threads call `bind` at once on a fresh runtime state: exactly one
  succeeds, seven throw. Because binding is permanent, this runs against a test-only instance
  of the binding logic (the mutex/check-and-install is factored into a small internal
  `OnceCell<JSContext>`-like type so it can be instantiated separately).

Done when: all tests pass; decision on ordering unbound tests is written into the Test
conventions section.

### 3. Thread dispatch: `run`

Code:
- `private enum ArkTSResult<R> { Ok(R) | Err(Exception) }`.
- `static func run<R>(operation: () -> R): R` (on bind thread: `newScope`; otherwise
  `postJSTask` and wait on `Mutex` / `Condition`).
- Every public entry point wraps its engine work in exactly one `run`; internal recursion never
  calls `run`.

Tests (device):
- On the JS thread: `run` returns the operation's value; `isInBindThread()` inside is true.
- From a `spawn`ed thread: same value returned; inside the operation `isInBindThread()` is
  true; outside it is false.
- Exception thrown inside the operation on the JS thread propagates with the same type and
  message.
- Same from a `spawn`ed thread: rethrown on the calling thread with the same type and message.
- 16 `spawn`ed threads each call `run` 100 times returning their own id: every result matches,
  no deadlock (test has a timeout).
- Nested: an operation that itself calls a public entry point on the JS thread completes (no
  deadlock, because the inner call sees `isInBindThread()`).
Known limitation (documented, not tested): if the JS thread blocks waiting for a `spawn`ed
thread that is itself inside `run`, both wait forever. No public method of the runtime waits on
another Cangjie thread, so this can only come from user code.

Done when: all tests pass on emulator and phone, including repeated runs (suite run 3 times)
to catch flakiness.

### 4. Handles

Code:
- `enum ArkTSHandle { Imm(JSValue) | Ref(JSHeapObject) }`.
- `retain(value: JSValue): Extern<ArkTSRuntime>` and `evalPayload(payload: Any): JSValue`.
- `public static func fromJSValue(value: JSValue): Extern<ArkTSRuntime>` and
  `public static func toJSValue(value: Extern<ArkTSRuntime>): JSValue` (needed to move values
  across the `JSModule` boundary; not in the design).

Tests (device):
- `retain` classification for each JS kind: `undefined`, `null`, boolean, number → `Imm`;
  string, bigint, symbol, object, array, function → `Ref` (checked through an internal test
  hook that reports the variant).
- Round trip: an ArkTS object passed in, wrapped with `fromJSValue`, returned with
  `toJSValue`; ArkTS asserts `===` identity with the original.
- Survival across calls: Cangjie stores a wrapped object in a static, a later separate call
  returns it; ArkTS asserts identity (proves the global handle outlives the scope).
- Survival across GC: same as above with `ArkTools.GC` / forced GC on the ArkTS side between the
  two calls where available.
- Release: wrap and drop 100 000 objects in a loop, force Cangjie GC; the test passes if the
  app neither crashes nor grows without bound (memory checked with `hidumper` by hand once,
  noted here).
- `evalPayload` with a foreign payload (e.g. `ExternPayload(42)` built by hand) throws
  `ExternConversionException`.

Done when: all tests pass on emulator and phone.

### 5. Evaluation

Code: `eval`, `evalTree`, member access/update, `call`, indexing, compound assignment, as
below.

- `eval(tree)`: `ExternPayload` returned unchanged; each primitive constructor becomes
  `run { retain(<operation>) }`; `case _ => Extern<ArkTSRuntime>.evalDerived(tree)`.
- `evalTree(tree): JSValue`: same operations recursively, without `run` or `retain`.
- Member access / update: `getProperty(field)` / `setProperty(field, toJSValue(value))`.
  Updates return `undefined`.
- `call`: `ExternMemberAccess` / `ExternIndexedAccess` callee → receiver evaluated once,
  passed as `thisArg`; other callees get `undefined`. Non-function → `ExternFunctionAccessException`.
- Indexing: `Int64` / `Int32` → `getElement` / `setElement`; `String` → property;
  `Extern` → string key, symbol key, integral number → element, other number → string key;
  else `ExternIndexedAccessException`. Write order: target, index, value.
- Compound assignment: evaluate receiver and key once, read, compute with `operators.cj`,
  write back, return the new value; unsupported → `ExternCompoundAssignmentException`.
  `operators.cj` covers number `+ - * / % **`, `& | ^ << >>` via Int32, bigint arithmetic and
  bitwise ops, string `+`, `&&` / `||` with JS truthiness.

Tests (host, `operators.cj`):
- Each operator on numbers, including `NaN`, `Infinity`, `-0`, division by zero, `%` with
  negative operands, shifts by ≥ 32, `**` with fractional exponents, matching JS results.
- BigInt operators, including negative shifts and division truncation.
- String `+` with number, boolean, `undefined` / `null` string forms.
- `&&` / `||` truthiness table (`0`, `-0`, `NaN`, `""`, `null`, `undefined`, objects).
- Mixed number / bigint → error, as in JS.

Tests (device), each with an ArkTS-side assertion of the effect:
- Member read of number, string, object, nested `e.a.b.c`; missing member reads `undefined`.
- Member update, then ArkTS reads the new value; update of nested `e.a.b = v`.
- Method call: fixture function records `this`; ArkTS asserts `this === rect`.
- Free call through a stored function: recorded `this` is `undefined`.
- Call through an index (`e.methods[0](1)`, `e["m"](1)`): `this` is the indexed object.
- Receiver evaluated once: receiver produced by a getter with a counter; counter is 1 after
  `e.obj.m()`.
- Call with arguments of every leaf type; ArkTS asserts the received JS types (`typeof`),
  e.g. `Int64` arrives as `bigint`, `Float64` as `number`.
- Calling a non-function → `ExternFunctionAccessException`.
- Index read/write with `Int64`, `Int32`, `String`, `Extern` string, `Extern` symbol,
  `Extern` integral number, `Extern` fractional number; unsupported index type →
  `ExternIndexedAccessException`.
- Index write order: index and value come from getters that append to a log; log order is
  target, index, value.
- Compound assignment on member and index for each operator family; ArkTS asserts the stored
  value; the receiver getter counter is 1.
- `x += 1` on an `Extern` variable holding a JS number: dispatches as a method call `"+"` and
  fails with `ExternFunctionAccessException` (documents current compiler behaviour).
- `eval` of a payload returns the same value (identity checked from ArkTS).
- `eval` of a hand-built unknown derived constructor goes to `evalDerived` and throws
  `ExternUnsupportedOperation`.
- Intermediates are not retained: a long chain in a loop of 100 000 iterations completes
  without handle exhaustion.

Done when: host and device tests pass on emulator and phone.

### 6. Conversions

Code: `toJSValue`, `toExtern`, `fromExtern` covering every row of the mapping table,
`Option<U>`, `Array<U>` (including `Array<Extern<ArkTSRuntime>>` and nested arrays), `Unit`,
and `Extern<ArkTSRuntime>` identity.

Tests (device), for every row of the mapping table:
- `toExtern`: Cangjie value → passed to ArkTS → ArkTS asserts `typeof` and value.
- `fromExtern`: ArkTS value → Cangjie asserts value.
- Round trip `fromExtern<U>(toExtern<U>(v)) == v`.
- Boundary values: `Int8.Min/Max`, `UInt32.Max`, `Int64.Min/Max`, `UInt64.Max` as bigint,
  `Float64` `NaN` / `±Infinity` / `-0.0`, `Float16` precision, empty string, non-ASCII and
  emoji strings, very long string (1 MB).
- `Option`: `Some(x)` → value, `None` → `undefined`; `undefined` and `null` → `None`.
- Arrays: empty, nested, `Array<Extern<ArkTSRuntime>>` with mixed JS values, 100 000 elements.
- `Extern` inputs: an unevaluated tree passed to `toExtern` / `fromExtern` is evaluated first.
- Failures: unsupported Cangjie type in `toExtern`, wrong JS type for the target (string as
  `Float64`, object as `Bool`), out-of-range number for `Int8` → `ExternConversionException`.
- Implicit conversion through the compiler: `let v: Extern<ArkTSRuntime> = 42` reaches ArkTS
  as bigint `42n`.

Done when: all tests pass on emulator and phone. Any mismatch between the table and actual
`ark_interop` behaviour is written into the design doc's open points.

### 7. Exceptions from the VM

Code: catch the `ark_interop` exception raised for a JS throw at the top of each operation and
rethrow as `ForeignRuntimeException` with the JS message and stack; our own `Extern*`
exceptions pass through unchanged.

Tests (device):
- First, an exploratory test records which Cangjie exception type `ark_interop` throws for a JS
  `throw new Error("boom")`, a `throw "string"`, and a `TypeError` from calling `undefined`;
  the result is written into this plan.
- Each of the three cases surfaces as `ForeignRuntimeException`; message contains `boom`.
- Exception thrown in JS called from a `spawn`ed thread: same result on the calling thread.
- Our exceptions are not wrapped: `ExternIndexedAccessException` from a bad index stays that
  type.
- After a JS exception the runtime is still usable: next operation succeeds.

Done when: all tests pass on emulator and phone.

### 8. Helpers

Code: `undefined`, `null`, `object`, `global`, `symbol(description!)`, `strictEqual`, `isNull`,
`isUndefined`, `objectHasProperty`, `objectKeys`, `objectDefineOwnProperty`,
`requireArkModule`, `requireSystemNativeModule`.

Tests (device), one success and one failure case each:
- `undefined()` / `null()` reach ArkTS as `undefined` / `null`; `isUndefined` / `isNull` on
  each JS kind.
- `object()` is a fresh empty object (two calls are not `===`).
- `global()` is ArkTS `globalThis`.
- `symbol("d")` has `description === "d"`; two symbols are distinct.
- `strictEqual` matches ArkTS `===` for a table of pairs (same object, equal numbers, `NaN`,
  `+0` / `-0`, strings, bigint).
- `objectHasProperty` / `objectKeys` on a fixture, including inherited vs own properties.
- `objectDefineOwnProperty` with each flag combination; ArkTS checks
  `Object.getOwnPropertyDescriptor`.
- `requireArkModule` loads a test module and calls an exported function; a missing module
  throws (type recorded).
- `requireSystemNativeModule` loads a known system module (e.g. `hilog`).
- Each helper called from a `spawn`ed thread.

Done when: all tests pass on emulator and phone.

### 9. End-to-end scenario and smoke page

Code: the design's example from section 1 (`createRectangle`, `width` update, `+=`, `area()`)
written with dynamic syntax in `arkts_tests`, plus the Layer 3 button.

Tests (device):
- The design example produces `area == 25.0` (with `height = 5.0`) and ArkTS sees
  `width == 5.0`.
- A mixed scenario using every feature in one function, run 1 000 times.
- Full suite run 3 times in a row on emulator and phone.

Done when: all tests pass; smoke page shows all PASS on the phone.

### 10. Optimizations (each behind its own tests)

1. `ExternSequence` handled in `eval` / `evalTree`.
   - Host: with `--enable-extern-sequence`, `RecordingRuntime` sees `ExternSequence` for two
     consecutive statements.
   - Device: the whole suite passes with the flag on and off; a sequence of two calls runs in
     one `run` (counter hook); the first result is not retained.
2. Property-name cache.
   - Device: whole suite passes; a loop reading the same field 100 000 times is measurably
     faster than without the cache (timing printed, not asserted).
3. Path / batch access waits for the new `ARKTS_*` FFI functions.

## Open points

- Exact exception type thrown by `ark_interop` on a JS exception (step 7).
- Whether `requireArkModule` paths resolve as `"entry/ets/..."` in this project layout (step 8).
- Compound assignment semantics in step 5 are ours; to confirm or move into the design doc.
- How to test the unbound state given that binding is permanent (step 2).
