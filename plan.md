# ArkTS runtime implementation plan

Implementation of `docs/arkts_runtime_design.md` (in `cangjie_interop_architecture`) as a
Cangjie package inside this DevEco project. Every step adds its tests together with its code,
and a step is finished only when its tests and all earlier tests pass.

## Decisions

- **Single runtime.** One non-generic class with only static members, abstract so it cannot
  be instantiated: `public abstract class ArkTSRuntime <: ForeignRuntime<ArkTSRuntime>`
  (subclassing is possible but useless, since a subclass is not a `ForeignRuntime` of itself).
  Values are
  `Extern<ArkTSRuntime>`.
- **Binding** exactly as in section 3 of the design: `private static let contextMutex` and
  `private static var context_: ?JSContext` in `ArkTSRuntime`; `bind` checks and installs under
  the mutex; the `context` getter reads `context_` without the mutex. Differences: `context` is
  `internal` rather than `private` (other files of the package use it), and there is a public
  `isBound()`. `index.cj` binds the runtime when the module is registered
  (`if (!ArkTSRuntime.isBound()) { ArkTSRuntime.bind(runtime) }`).
- **`Int64` / `UInt64` map to `bigint`**, as in the design's type mapping table.
- **Package:** `arkts_runtime` in `arkts_runtime/src/` (a `cjpm` static library since step 10;
  until step 9 it was `ohos_app_cangjie_entry.arkts` inside `entry`). Each app's
  `entry/src/main/cangjie/index.cj` is its module entry point and binds the runtime.
- **Toolchain:** `~/.cangjie-sdk/6.1/cangjie/build-tools/bin/cjc` (has `Extern<T>` and
  `ForeignRuntime<T>` in `std.core`). The app ships the matching Cangjie runtime, see
  "Shipped Cangjie libraries" below.

## Shipped Cangjie libraries

The phone's app launcher (`libcj_environment`, OpenHarmony `cj_environment.cpp`) looks for
Cangjie libraries in two app folders before the system ones: `libs/arm64/runtime` (the
runtime) and `libs/arm64/ohos` (checked before `/system/lib64/platformsdk/cjsdk`). A copy at
the top of `libs/arm64` is only seen by our own library. `dependencies_libs/base/arm64-v8a`
(copied into each app's `entry/libs` by its `hvigorfile.ts` on every build; `entry/libs` is
generated and ignored by git) therefore contains:

- `runtime/`: `libcangjie-runtime.so`, `libboundscheck.so` from
  `~/.cangjie-sdk/6.1/cangjie/build-tools/runtime/lib/linux_ohos_aarch64_cjnative`.
- `ohos/`: the std libraries our library needs (`libcangjie-std-core.so`, `-collection`,
  `-math`, ... from the same folder, plus `libpcre2-8`), and `libohos.ark_interop.so`,
  `libohos.ark_interop_helper.so`, `libohos.hilog.so`, `libohos.labels.so`,
  `libohos.business_exception.so` copied from the phone
  (`/system/lib64/platformsdk/cjsdk`): the SDK only has empty link stubs of those.

Why not the system libraries: our code needs the SDK's `std-core`, which defines `Extern<T>`
and `ForeignRuntime<T>` (43 such dynamic symbols). The phone's
`/system/lib64/platformsdk/cjsdk/libcangjie-std-core.so` has none (checked with `llvm-nm -D`
on 2026-10-15). A Cangjie library loaded from the system folder resolves its own dependencies
there and brings the system `std-core` next to ours, so every one the app uses is shipped
(copied from the phone; shipped, they run on our `std-core`).

Why the whole set: shipping only `libcangjie-std-core.so` at the top of `libs/arm64` loaded two std-cores
(ours for our code, the phone's for `ark_interop` and the other system libraries). Runtime
type checks then disagreed with the Mac: `None<T>` made in generic code was not seen as
implementing our interface for `T = Int64` and `Bool` (but was for `Float64`, `Int32`,
`String`). With one std-core everything matches the Mac. The SDK std libraries need the SDK
runtime (without `runtime/`, the library fails to load). Replacing the system runtime with a
bind mount does not work: the code-signing check refuses the file. `devicetest.sh` uninstalls
before installing, because a reinstall keeps library files the new build no longer ships (a
stale second std-core brought the problem back on the emulator). The libraries add 8.3 MB.

Apps with a Cangjie UI also ship `dependencies_libs/ui/arm64-v8a/ohos` (16 MB, 106 files):
the Cangjie UI libraries (`kit.ArkUI`, `ohos.arkui.*`, `ohos.base`, ...) that the app's
library needs, copied from the phone's `/system/lib64/platformsdk/cjsdk` (the dependency
closure, computed with `llvm-readelf -d`). Without them the system copies load and pull in the
system runtime and std-core next to ours, and the app crashes at start (SIGSEGV in
`std.core::package_global_init`). With them, the app maps a single runtime and std-core, both
from its own `libs` (checked in `/proc/<pid>/maps`). The phone's copies also work on the
emulator.

## Constraints found by compiling small probes against this cjc

| Finding | Consequence |
| --- | --- |
| Forced cast `(U)e` does not parse; no flag enables it | Code and tests call `ArkTSRuntime.fromExtern<U>(e)` explicitly |
| Implicit conversion to `Extern<T>` and dynamic `e.f`, `e(...)`, `e[i]` work | Used as designed |
| `match (None<R>) { case _: Option<Int64> => ... }` works | Used for `fromExtern` dispatch |
| `case x: Extern<ArkTSRuntime>` type patterns work | Used in `toJSValue` / `readIndex` |
| `std.reflect` is not available | Not used |
| `JSKeyable` is only `String`, `JSString`, `JSSymbol` (not `Float64`) | Numeric indices become property names (their JS string form, `"5"`) instead of `getProperty(Float64)` (deviation from the design) |
| `--enable-extern-sequence` exists | Used to test `ExternSequence` in step 12 |
| `std.unittest` is available for macOS | Host tests in layer 1 below |
| Compiler bug: `let _: Extern<R> = expr` runs `expr` but skips `toExtern` (named bindings, assignments and arguments are fine) | Pinned by `wildcardBindingSkipsToExtern` in `hosttest/compiler_contract_test.cj`; flip it when cjc is fixed |
| Without the forced cast, `R.fromExtern<U>(e.a.b)` receives the already evaluated `r1`, not the tree (the argument is desugared like any call argument) | `fromExtern` cannot avoid retaining the result until `(U)e` is supported; pinned by `explicitFromExternReceivesEvaluatedValue` |
| Default (`internal`) members are visible to subpackages but not to the parent package; `extend` in another file can add `public static` functions | Device scenarios live in the subpackage `arkts.tests` and can use internal hooks; `index.cj` and user code cannot (checked by a deliberate failing build, step 1) |
| A user exception class prints as `Exception: ...` unless it overrides `getClassName` | Our exceptions override it; tested in step 1 |
| Bare `ExternPayload(x)` fails to infer `T` even in non-generic code with a known return type | Written as `Extern<ArkTSRuntime>.ExternPayload(x)` |
| `foreign` is a keyword | Not used as an identifier |
| ArkTS: allocating garbage triggers only young collections, which never cleared a `WeakRef` (16 collections, 1.8 GB freed); `hidebug.dumpJsHeapData` runs a full one (0.5–0.9 s) | GC tests force collections with a heap dump; memory is measured with `hidebug.getAppVMObjectUsedSize()` after one, not with PSS (too noisy: ±40 MB) |
| Engine values kept past their scope without a global handle still read correctly until a full GC | Lifetime tests must force a full GC and observe it (`WeakRef`) |
| The class body cannot call static functions added by an `extend` without qualifying them (`retain(v)` is "undeclared"); the `extend` can call class members unqualified | `runtime.cj` writes `ArkTSRuntime.retain` / `evalPayload` / `toJSValue` |
| `JSValue.getProperty` works only on objects ("expect object, given string"); `toString()` only on strings | Since 2026-10-16 the runtime follows it: members of primitives, `undefined` and `null` throw `ExternMemberAccessException` with `ark_interop`'s message (until then they were read through `Object(value)`) |
| `getElement` / `setElement` differ from JS (probed on the phone, array `[10, 20, 30]`): both work only on arrays ("expect array, given object"); `getElement` throws "index out of range" at and past `length` (JS reads `undefined`) and at -1; `setElement(-1)` throws; `setElement(4294967295)` stores the value but sets `length` to 0 while elements 0–2 remain; `setElement(≥ 2^32)` throws `OverflowException`. Appending and sparse writes up to 4294967294 behave like JS. `setProperty` / `getProperty` with the number's name (`"3"`, `"-1"`, `"4294967294"`, `"4294967295"`) match JS in every case, including `length` | Since 2026-10-16 integer indices use them, with exactly these rules (until then every numeric index was a property name, with the JS rules that plain ArkTS has) |
| `extend Extern<R> <: I` fails ("extending type 'Enum-Extern<...>' is not allowed"); conditional extensions (`extend<T> Array<T> <: I`) and `TypeTag<R>() as I` in generic code work | `conversion.cj` handles `Extern` as an explicit case; `Array` / `Option` are extended unconditionally and convert elements dynamically |
## Status

- **Step 0 done** (2026-10-08). Host: 24 compiler-contract tests pass. Device: 9 tests pass on
  the emulator (`127.0.0.1:5555`) and the phone (`0123456789ABCDEF`), with signed HAPs. Both
  scripts verified to exit non-zero on a failing test.
- **Step 1 done** (2026-10-08). Device: 19 tests pass on both devices (10 new: exception names,
  stubs reached through dynamic syntax and implicit conversion, `extend` helper, internal
  visibility, plus a self-test of `expectThrows`). Host: 24 pass. A build where `index.cj` calls
  an internal member fails with "no matching function declaration"; one that writes
  `ArkTSRuntime()` fails with "abstract class 'ArkTSRuntime' can not be instantiated".
- **Step 2 done** (2026-10-08), implemented literally as in the design. Device: 23 tests pass on
  both devices (4 new): the runtime is bound at module registration, to the same engine the
  tests run in; rebinding throws and leaves the context unchanged, also with 8 racing threads
  × 50 rounds. Not testable, because the runtime is already bound when tests start: the
  unbound state, the first bind, and the race between concurrent first binds (removing the
  mutex would not make any test fail).
- **Step 3 done** (2026-10-08), `run` as in section 4 of the design, `internal` instead of
  `private` (tests call it directly; no public method uses it yet). Device: 33 tests pass on
  both devices, suite run 3 times (10 new: `run` on the JS thread and from spawned threads,
  value, engine calls, exception identity, nesting, 16 threads × 100 calls without overlap, plus
  the unknown off-thread scenario). Mutation checks on the emulator, each caught: always running
  the operation directly (5 off-thread tests fail with "Thread mismatch"); running it directly
  on the calling thread without a scope (4 fail on our own checks); rethrowing a copy of the
  exception (the rethrow test fails on identity).
- **Step 4 done** (2026-10-08), `ArkTSHandle` and `retain` as in section 5 of the design, in
  `handle.cj` (an `extend ArkTSRuntime`, internal). Two decisions: `evalPayload` throws
  `ExternConversionException("Extern payload was not produced by ArkTSRuntime")` instead of the
  design's `getOrThrow()` (`NoneValueException`); the planned public `fromJSValue` /
  `toJSValue` are not added (revisit when a real use needs them). Device: 41 tests pass on both
  devices, suite run 4 times (8 new). Mutation checks, each caught:
  - `retain` without global handles (`Imm` for everything): the WeakRef test reports the
    retained object collected; the variant checks fail too. The tests that only use a value in
    a later scope, call or thread still pass, so they do not prove the handle matters.
  - The handle never released (a leaked copy): the WeakRef test reports the object never
    collected after the drop.
  - 100 000 handles per round kept instead of dropped: the ArkTS heap grew ~37 MB from round 4
    to round 10 (limit 10 MB); released, it grew at most 1.7 MB.
- **Step 5 done** (2026-10-08). `eval` / `evalTree` in `runtime.cj`, JS operators in
  `operators.cj` (pure Cangjie, also compiled by `hosttest/run.sh`), a basic `toJSValue` in
  `conversion.cj` (the full table is step 6). Host: 35 tests pass (11 new). Device: 67 tests
  pass on both devices, suite run 3 times at 65 (26 new, 1 removed: `step1.evalStub`;
  `step1.dynamicSyntaxReachesEval` now expects the "not produced by ArkTSRuntime" error).
  Choices where the design is silent:
  - `&&=` / `||=` short-circuit as in JS: the value is not evaluated and nothing is written.
  - Member or index access on `undefined` / `null` → `ExternMemberAccessException` /
    `ExternIndexedAccessException`, before the value is converted.
  - Primitive receivers (`e.str.length`, `e.str.toUpperCase()`, `e.str[1]`) read from the
    wrapper object, with the primitive as `this`; writes to a primitive throw (strict mode).
  - Every numeric index is a property name (`"5"`, `"-1"`), which gives the JS rules in all
    cases; `getElement` / `setElement` are not used (see Constraints). Decided with the user
    after `e.items[5]` was found to throw through `getElement`. Tested by `indexBoundaries`
    (past the end, a hole, -1, 4294967294, 4294967295, with `Int64` and `Extern` indices);
    mutations caught: `getElement` without a length check, Cangjie number formatting for keys.
    `nonArrayIndexing` pins the JS rules on a `Map` (entries are not indexable) and a
    `Uint8Array` (300 stored as 44; writes past the end and at -1 ignored).
  - Values become text with JS `String(...)` (`1.5` → `"1.5"`, `1e21` → `"1e+21"`, `-0` →
    `"0"`), in string `+=` and for number keys; Cangjie formatting would give `"1.500000"`.
    A symbol in string `+=` throws, as in JS. Tested by `stringConversions`; Cangjie number
    formatting in `jsString` is caught by 7 tests.
  - Compound operators: numbers use JS ToNumber for booleans, `null`, `undefined`; bigint
    only with bigint (else error, as in JS); string `+` with any primitive; objects
    unsupported (`ExternCompoundAssignmentException`).
  Mutation checks, all in one build, each caught by its own test only: method receiver
  evaluated twice; indexed call with `this` = `undefined`; indexed write converting the value
  before the index; `||=` evaluating the value; compound receiver evaluated twice.
- **Step 6 done** (2026-10-14). Suite run 4 times on the phone, once on the emulator (its
  `hdc` connection kept dropping to "Offline", once mid-install; no test failed). Every
  mapped type implements two internal interfaces in `conversion.cj`, `ToJS` (`toJS()`) and
  `FromJS<T>` (`static fromJS(JSValue)`), through `extend`s. `toJSValue` matches
  `Extern` first, then `ToJS`. `fromExtern<R>` reaches `R.fromJS` through
  `TypeTag<R>() as JSReader` (a conditional extension), with `Extern<ArkTSRuntime>` as the
  identity case. `Array<T>` / `Option<T>` convert each element through the same two
  functions, so nesting works to any depth. One consequence: an unsupported element type only
  fails when an element is actually converted (an empty `Array<Rune>` becomes `[]`). Device:
  72 tests pass on both devices (8 new; 3 step 1 stub tests removed: `toExternStub`,
  `implicitConversionReachesToExtern`, `fromExternStub`, now covered by step 6). Choices
  where the design is silent:
  - Reads are strict about the JS type: `Int64` / `UInt64` accept only bigint (not number),
    `Bool` only boolean, `String` only string; anything else gives `ExternConversionException`
    ("Cannot convert ArkTS <type> to <Target>").
  - Narrow integers need an integral number in range ("ArkTS number does not fit Int8");
    `Float16` / `Float32` round like a Cangjie float conversion.
  - `Unit` accepts any value; `Option` reads `undefined` and `null` as `None`.
  Mutation checks, both in one build, each caught: `Int64` sent as a number (7 tests fail);
  fractional numbers accepted as integers (`conversionFailures`).
- **Step 7 done** (2026-10-14). Device: 77 tests pass on both devices, suite run 3 times
  (5 new). Exploration (pinned by `step7.arkInteropJSException`, calling `ark_interop`
  directly): every JS throw (`new Error("boom")`, a thrown string, an engine `TypeError` from
  calling `undefined`, a throwing getter) raises `BusinessException` with `code` 34300002 and
  the message `Outside error occurred, ArkTS exception, [code: 0, ]message: <JS text>, stack: .`
  (`<JS text>` is e.g. `Error\nboom`, `boom string`, `TypeError\nmissing is not callable`,
  `[[Error]]boom getter`). The stack is always empty and `getData` holds nothing, so the JS
  error value is lost. The engine stays usable. Implementation: `run` wraps the operation in
  `translatingJSExceptions`, which turns code 34300002 into
  `ForeignRuntimeException(<that message>)`. Other codes (e.g. 34300005, type mismatch) and
  our own exceptions pass through unchanged; nested `run`s translate once. Mutation checks,
  each caught: no translation (3 tests fail); translating every code (`ownExceptionsNotWrapped`).
- **Step 8 done** (2026-10-14), helpers as in section 8 of the design, each one `run`. Device:
  87 tests pass on both devices, suite run 3 times (10 new; `step1.extendHelperReachable`
  and `step1.internalVisibleToSubpackage` now use real helpers / `handleKind`, since
  `notImplemented` is gone). ArkTS-side checks that strict ArkTS forbids (`globalThis`,
  `Object.getOwnPropertyDescriptor`, `Object.freeze` of a literal) lived in a TypeScript
  file, later removed (see "No TypeScript in testapp"). Findings and choices:
  - `requireArkModule` specifiers are `<module>/src/main/ets/<path>` without extension
    (`"entry/src/main/ets/arkts/TestModule"`), and the file must be in
    `arkOptions.runtimeOnly.sources` (entry `build-profile.json5`), since nothing imports it.
    `"@ohos.hilog"` works too. A missing module throws `BusinessException` 34300006 from
    `ark_interop` (passed through, like every non-JS-throw code).
  - **Limitation:** `requireArkModule` needs ArkTS code on the stack. From a spawned thread
    the call runs in a posted JS task and fails with `ForeignRuntimeException`
    ("ReferenceError Unable to get recordName and fileName ..."); pinned by
    `helpersFromOtherThread`. All other helpers work from spawned threads.
  - `requireSystemNativeModule("hilog", None)` works; an unknown name gives `undefined`.
  - `objectDefineOwnProperty` never returns `false` in practice: like JS
    `Object.defineProperty`, a refusal (frozen object, read-only non-configurable property)
    throws (`ForeignRuntimeException`, "TypeError Cannot define property").
  - `objectHasProperty` is JS `in` (inherited `area` / `toString` included); `objectKeys` is
    `Object.keys` (own enumerable strings, no symbols). Arrays count as objects. Primitives,
    `undefined` and `null` throw `ExternConversionException("ArkTS value is not an object")`.
  - `symbol()` without a description prints as `Symbol()`.
- **Step 9 done** (2026-10-14). Device: 90 tests pass on both devices, suite run 3 times;
  host: 35 pass. `TestModule.ets` gained `Rectangle` / `createRectangle()` (height 5).
  `arkts.tests/step9_end_to_end.cj` has `step9.designExample` (the design's section 1
  example; ArkTS checks `width == 5`, `area() == 25`), `step9.mixedScenario` (1 000
  iterations on the JS thread) and `step9.mixedScenarioOffThread` (100 iterations from a
  spawned thread). The mixed scenario covers members, nested members, every compound
  operator, `||` / `&&`, indexing with `Int64` / `Int32` / `Extern`, string and symbol keys,
  free calls, `Reflect.construct`, every helper, the conversions (options, nested arrays,
  limits, `Float16`, `BigInt`) and the four exception kinds. It does not use
  `requireArkModule` from the spawned thread (step 8 limitation). Mutation checks, each
  caught: `createRectangle` height 6 (`designExample`), `"?"` instead of `"!"` in the
  scenario (both mixed tests).
  - **Deviation:** by the user's choice, the smoke page (`pages/Index.ets`) runs only the
    three step 9 scenarios, not the whole suite. It shows `PASS/FAIL <name> (<ms>)` lines
    and `ALL PASS (n)` / `n FAILED`. Verified on the emulator by tapping the button with
    `uitest`: `ALL PASS (3)`. Times: designExample 1 ms, mixedScenario ×1000 212 ms,
    off-thread ×100 899 ms (about 9 ms per iteration, which is the cost of posting to the JS
    thread, a target for step 12). Not checked on the phone, which was locked; that has to
    be done by hand.

- **Step 10 done** (2026-10-14). The runtime is the `cjpm` static library `arkts_runtime/`
  (package `arkts_runtime`, scenarios in `arkts_runtime.tests`); today's project moved to
  `testapp/` and has no runtime code left; `demos/hello` and `demos/rectangle` are separate
  DevEco projects. Device: 93 tests pass on both devices, suite run 3 times (3 new in
  `Step10_Function`); host: 35 pass. Both demos and the smoke page (`ALL PASS (3)`, which
  also completes the phone check left open in step 9) checked with `uitest` on the emulator
  and the phone, with all three apps installed at once. `./demo.sh demos/<name>` builds,
  installs and starts a demo.
  - Probe 1: `cjpm` accepts `arkts_runtime = { path = "../../arkts_runtime" }` outside the
    project root. The app's `[profile.build.combined]` must go: it merges the library's
    packages and reports a cycle (`arkts_runtime` / `arkts_runtime.tests`).
  - Probe 2: hvigor does not package a symlinked `entry/libs`; a real copy works. Each app's
    `entry/hvigorfile.ts` copies `arkts_runtime/libs` (and `libs-ui` for Cangjie UI apps)
    into `entry/libs` at every build, so DevEco builds work too. Cangjie UI apps need
    `libs-ui`, see "Shipped Cangjie libraries".
  - Probe 3 not needed: each library package is its own static archive
    (`libarkts_runtime.a`, `libarkts_runtime.tests.a`) and only referenced packages are
    linked; the demos contain no scenario code (no `arkts_runtime.tests` symbols or strings).
    No `@When` flag.
  - Probe 5: a Cangjie exception thrown in an `ark_interop` function callback reaches ArkTS
    as an `Error` ("IllegalStateException: cangjie boom" plus the Cangjie stack), which
    ArkTS can catch; `ark_interop` has no API to throw a JS error itself.
  - `ArkTSRuntime.function(body)` added (`helpers.cj`). Mutation check, caught: arguments in
    reverse order (`functionCalls`: `b|a`).
  - `testapp`'s `index.cj` calling `handleKind` fails to build ("no matching function
    declaration"), as in step 1.
  - Demo details: Cangjie UI attributes need their imports (`kit.ArkUI.LengthProp` for
    `20.vp`); the `hello` button uses `.enabled(!running)`.
  - Size: the library's shipped files are 8.3 MB (`libs`) and 16 MB (`libs-ui`) in git.
  - Probe 4 (emulator and phone, in `demos/hello`):
  - **Pure CangjieUI app (wizard template): not usable.** hvigor refuses `.ets` files in a
    module with a Cangjie entry ("If the module contains the ArkTS code, the ArkTS code must
    be used as the entry"); outside `src/main/ets` they are silently not compiled. The only
    context available is a new engine from `JSRuntime()` (works on the UI thread: `Math`,
    `requireSystemNativeModule("hilog")`), but it has no `setTimeout` / `setInterval`, and
    `requireArkModule` fails there ("Unable to get recordName", no ArkTS on the stack).
  - **Mixed app (user's choice): works.** ArkTS `EntryAbility` and page; the page embeds the
    Cangjie view with `CJHybridComponent({ library: 'ohos_app_cangjie_entry', component:
    'HelloView' })` from ohpm `@cangjie/cjhybridcomponent` 1.0.0, and the view is a Cangjie
    `@HybridComponentEntry @Component` class. Importing our library from the page runs
    `JSModule.registerModule` (real context, timers available). `sayHello` with a Cangjie
    `ctx.function` callback drives the Cangjie `@State` once per second, and the screen
    follows (checked with `uitest` during and after the count).
  - **`requireArkModule` timing:** fails during `registerModule` (`BusinessException`
    34300007, "Cannot requireArkModule during initializing cangjie module") and from a
    Cangjie UI event handler ("Unable to get recordName"); works inside a call from ArkTS
    into Cangjie. So the page calls an exported Cangjie `init()` once (`aboutToAppear`),
    which loads and keeps the module; the view uses it later.
  - Also found: a lambda passed to a function cannot capture a mutable local (`var`) inside
    a `@HybridComponentEntry` class ("lambda capturing mutable variables needs to be called
    directly").

- **Compound assignment removed** (2026-10-15), by the user's decision: ArkTS will not
  support it. `ark_interop` has no operator API, so step 5 computed `op=` in Cangjie
  (`operators.cj`) with hand-copied JS semantics. Now every `ExternCompoundAssignment` throws
  `ExternCompoundAssignmentException("ArkTS compound assignment needs a member or index
  target")` without evaluating anything. Removed: `operators.cj` and its host tests, the
  step 5 compound scenarios (`compoundAssignmentOrder`, `compoundOperators`,
  `compoundThroughSyntax`, `logicalAssignment`, `compoundReceiverOnce`, `compoundErrors`);
  `stringConversions` kept only its index-key checks, as `numberKeys`; new
  `compoundAssignmentUnsupported`. Step 9 and the rectangle demo write
  `blob.width = fromExtern<Float64>(blob.width) + 2.0`, and the mixed scenario uses plain
  assignments.   The compiler-contract host tests still pin the `ExternCompoundAssignment`
  shape the compiler produces.
- **Device tests moved into the library folder** (2026-10-15), by the user's choice:
  `testapp/` and `devicetest.sh` are now in `arkts_runtime/`, next to the scenarios in
  `src/tests` (which must stay a subpackage to reach internal members). `testapp` depends on
  the library with `path = "../.."` and copies `../../libs`; the library build is unaffected
  (`src-dir` is `./src`). Device-suite logs are in `arkts_runtime/.devicetest/`. Clean build:
  88 tests pass on both devices; the `hello` demo still builds against the library.
- **Test scenarios compiled only for testapp** (2026-10-15), by the user's choice. The
  library's `compile-option` is now `--dy-std --cfg="${COMPILE_CONDITION_ENTRY},bundle=${bundleName}"`
  (both variables are set by hvigor), and every top-level declaration in `src/tests` carries
  `@When[bundle == "com.example.testArkTSForeignRuntime"]`. Other apps compile an empty
  `arkts_runtime.tests`. Alternatives that did not fit: cjpm features/source sets
  (experimental), `--no-tests` (only `check`/`tree`), `*_test.cj` files (never compiled for
  a dependency), and a testapp product name (hvigor requires `default`). Clean builds: 88
  tests pass on both devices; in the `hello` demo the tests archive has no scenario symbols
  (134 KB vs 3 MB in testapp). testapp's bundle name is now `com.example.testArkTSForeignRuntime`.
- **Cangjie UI libraries moved to the demos** (2026-10-15), by the user's choice:
  `arkts_runtime/libs-ui` is now `demos/dependencies_libs`, since the library itself does not
  need them. The demos' `entry/hvigorfile.ts` copy `../../dependencies_libs`.
- **All shipped libraries in the root `dependencies_libs/`** (2026-10-15), by the user's
  choice: `arkts_runtime/libs` is now `dependencies_libs/base` (every app) and
  `demos/dependencies_libs` is `dependencies_libs/ui` (Cangjie UI apps). The library build
  never used them. testapp copies `base`, the demos copy both. Clean builds: 88 tests pass
  on both devices; both demos run.
- **`hello` loads its ArkTS code without `init()`** (2026-10-15), by the user's choice.
  `requireArkModule` also fails from a microtask queued in `registerModule` ("Unable to get
  recordName"). Instead `Hello.ets` ends with `globalThis.Hello = { sayHello }` (the ArkTS
  compiler only warns, `arkts-no-globalthis`); the page only
  does `import '../Hello'`, and `sayHello` in Cangjie calls
  `ArkTSRuntime.global().Hello.sayHello(...)` from the button handler. The page no longer
  imports `libohos_app_cangjie_entry.so`: `CJHybridComponent` loading the library runs
  `registerModule`, which binds the runtime. `runtimeOnly.sources` is gone. Checked on the
  emulator (countdown runs, button re-enabled); `rectangle` still uses `init()`.
- **No TypeScript in testapp** (2026-10-15), by the user's choice: `jsHelpers.ts` is gone.
  In `.ets`, `globalThis` is only a warning but `Object.freeze` and
  `Object.getOwnPropertyDescriptor` are errors (`arkts-limited-stdlib`). So
  `globalIsGlobalThis` gets ArkTS's `Math` and checks `global().Math === Math`;
  `defineOwnProperty` freezes its own object and reads each descriptor with JS's
  `Object.getOwnPropertyDescriptor` from Cangjie, and ArkTS checks the values and the
  enumerable keys (`Object.keys`). 88 tests pass on both devices.
  `arkts_runtime/README.md` no longer mentions the demos.
- **Step 11 done** (2026-10-16). `demos/benchmarks`, 25 benchmarks in the 10 groups; baseline
  `results/ohos-2026-10-16-1126.*` (phone) and `results/emulator-2026-10-16-1127.*`. A run
  takes about 50 s on the phone, 25 s on the emulator. Ratio `arkts_runtime / ark_interop` on
  the phone: property access 1.6–6.0, calls 3.3–4.5, arrays 8.1–8.6, strings 1.8–6.9,
  conversions 2.4–5.4, consecutive statements 4.2–4.3, callbacks 4.5, handles 2.8, exceptions
  1.6; from another thread 0.36 (`run` waits on a condition, the `ark_interop` variant posts
  and waits per operation). In the `.html`, clicking a benchmark shows its two variants,
  copied from the sources by `run.sh` at the time of the run; `Bench.ets`, the conversions'
  shared values and the helpers from `harness.cj` are below the table. Heap growth after `handles.createAndDrop`: within ±2 KB for both
  variants, so dropped handles are released. Phone numbers repeat within about 10% between
  runs. Findings:
  - hilog's per-process quota drops the app's lines (the Cangjie GC logs a lot): `run.sh`
    turns it off (`hilog -Q pidoff`, `domainoff`) for the run, back on after, and streams the
    tag to a file instead of reading the ring buffer. The phone logs every line twice;
    duplicates are dropped.
  - The phone turns the screen off after 30 s even with `power-shell timeout -o`, and the lock
    screen sends the app to the background, where it is frozen. The app keeps the screen on
    (`setWindowKeepScreenOn`).
  - Yielding with `setTimeout(0)` between runs starved the main thread's event queue and the
    watchdog killed the app (`THREAD_BLOCK_6S`); runs are separated by 20 ms. After the pause
    the CPU is slower, so every timed run is preceded by an untimed one.

- **Fewer engine calls per statement** (2026-10-16), by the user's choice, before step 12.
  Every `JSValue.isX()` checks the thread and calls into the engine, and each statement made
  up to a dozen of them. Changes: member and index access recognise an object receiver with
  one `isObject()` before the other checks; `retain` checks numbers and `undefined` first;
  `toJSValue` / `fromJSValue` match `Float64`, `Bool` and `String` directly, before the
  `ToJS` cast and the `TypeTag` allocation; `fromExtern` of an evaluated immediate (number,
  boolean, `undefined`, `null`) on the bind thread reads it without `run`, since that creates
  no handle and runs no JS (the compiler always passes `fromExtern` an evaluated value, so a
  read was two `run`s). 88 device tests and 24 host tests pass. Phone, `arkts_runtime` ns/op
  against the step 11 baseline (`results/ohos-2026-10-16-1149.*`): `property.readNumber`
  3 076 → 1 859, `property.readChain` 5 832 → 3 965, `call.function1` 4 546 → 3 136,
  `array.loop1000` 3.37 → 2.16 ms, `string.length` 7 757 → 5 812, `convert.bool` 4 985 →
  3 670, `callback.arkTSCallsCangjie` 3 157 → 2 169; handles and exceptions unchanged. Once
  the emulator stopped at `exception.throwCatch` (app alive, no fault log); the rerun passed
  (`results/emulator-2026-10-16-1155.*`).
- **Member and index access follow `ark_interop`** (2026-10-16), by the user's choice,
  replacing the JS rules chosen in step 5 (and the index rules decided then with the user):
  - `e.f` is `getProperty` / `setProperty`: it works on objects (arrays and functions
    included); on a string, number, bigint, symbol, `undefined` or `null` `ark_interop`
    throws code 34300005 ("The ArkTS data types do not match, expect: object, given:
    string."), rethrown as `ExternMemberAccessException` with that message. `checkReceiver`,
    `objectFor` (the `Object(value)` wrapper), `isPrimitive`, `typeName` and `jsString` are
    gone. `x += 1` on an `Extern` variable (`x.+(1)`) now fails reading the member `+`.
  - `e[i]` with an `Int64` / `Int32`, or an `Extern` holding an integral number in the
    `Int64` range, is `getElement` / `setElement`; a `String`, or an `Extern` holding a string,
    a symbol or another number, is a property key (`ark_interop`'s `Float64` key for numbers,
    named by the engine: `1e21` → `"1e+21"`). Codes 34300001 (out of range) and 34300005
    become `ExternIndexedAccessException`. Probed: reads need 0..length-1; writes at or past
    `length` grow the array; -1 throws; a write at 4294967295 succeeds but empties the array
    (`length` 0), pinned by `indexBoundaries`; on a `Map`, a typed array or a plain object an
    integer index throws ("expect: array, given: object"), string keys still work.
  - Tests changed to pin these rules: `memberRead`, `primitiveReceivers`,
    `memberOfUndefinedOrNull`, `indexReadWrite`, `indexBoundaries`, `nonArrayIndexing`,
    `unsupportedIndex`, `numberKeys`, `variableCompoundIsMethodCall`,
    `ownExceptionsNotWrapped`, `mixedOnce`; `symbols` and `helpersFromOtherThread` read a
    description with JS `String(symbol)`. 88 device tests and 24 host tests pass.
    `arkts_runtime/README.md` describes the rules.
  - Benchmarks (`results/*-2026-10-16-1348.*`), phone `arkts_runtime` ns/op:
    `array.readElement` 2 072 → 1 461, `array.writeElement` 1 851 → 1 174, `array.loop1000`
    2.16 → 1.46 ms; member access unchanged. `string.length` now reads the string into
    Cangjie (`fromExtern<String>(t.str).size`), the same operation as its `ark_interop`
    variant, so it is not comparable with earlier runs. Step 12's items 4 and 5 are superseded.
- **Every concrete type converted directly** (2026-10-16), by the user's choice: `toJSValue`
  and `fromJSValue` match all integer, float, `Bool`, `String`, `BigInt` and `Unit` types
  directly; only `Array<T>` and `Option<T>` go through the `ToJS` cast / `TypeTag` (their
  element type is unknown, and arrays are invariant, so no finite list of cases covers them).
  88 device tests and 24 host tests pass. Benchmarks (`results/*-2026-10-16-1408.*`): no
  measurable change, as the suite converts only `Float64`, `Bool` and `String` (already
  direct) and containers of them; `convert.optionSome` / `optionNone` 6–7% slower on the phone
  (15 more failed type tests before `TypeTag`), within the phone's ~10% noise.
- **`toJSValue` reduced to the `ToJS` cast; `fromJSValue` keeps its direct cases**
  (2026-10-16). `toJSValue` now matches only `Extern`, then `ToJS` (every concrete type
  implements it, and the cast allocates nothing): no measurable change
  (`results/*-2026-10-16-1422.*`). Doing the same in `fromJSValue` (only `TypeTag<R>() as
  JSReader`) cost a `TypeTag` allocation per read, and per element in `Array<T>.fromJS`: on the
  phone (`ohos-2026-10-16-1434`) `convert.arrayFloat64` 657984→807187 ns, `nestedArray`
  683937→843614, `array.readElement` 1424→1763, `property.readNumber` 1755→1980, with
  `ark_interop` unchanged. Restored (`ohos-2026-10-16-1437`): 649385, 678370, 1448, 1777. The
  emulator's array conversions vary by ±20% between runs of the same code, so it cannot tell.
  Tests pass in every state (24 host, 88 device on both).
- **An `Error` inside `run` from another thread reaches the caller** (2026-10-16). The task
  posted by `run` caught only `Exception`; a Cangjie `Error` (`OutOfMemoryError`,
  `StackOverflowError`, ...) escaped it and aborted the app ("Uncaught exception:
  std.core:OutOfMemoryError. Terminate required", seen on the emulator with the fix removed).
  `ArkTSResult` has a `Failed(Error)` case, rethrown on the caller. New device test
  `step3.runOffThreadRethrowsError` (allocates `Array<Int64>(Int64.Max / 16)` inside `run`,
  expects `OutOfMemoryError` on the caller within 10 s, then `run` still works). 24 host and
  89 device tests pass on both. Benchmarks `ohos-2026-10-16-1511`, `emulator-…-1512`: no
  change; `thread.readNumber`, the only off-thread one, 0.98 / 1.02 of `*-1437`.
  `string.readLong` on the phone jumps between about 9 and 15 µs from run to run (runs on the
  JS thread, so not affected).
- **External values are retained as `Ref`** (2026-10-16). `isObject()` is false for an
  `ark_interop` external (`context.external(SharedObject)`, `JSType.EXTERNAL`), so `retain`
  held it as `Imm`: a JSValue valid only in its scope. `retain` now checks `isExternal()` after
  `isObject()` and keeps a `JSExternal`; `jsTypeName` says "external". Tests:
  `step4.retainClassifiesEachKind` and `payloadRoundTrip` include an external (the first
  failed with "expected Ref, got Imm" before the fix); `retainedValueOutlivesScope` reads the
  external's `SharedObject` back after 10000 scopes and a heavy GC (it passed even before the
  fix, so a stale scope value is not reliably caught); `step6.conversionFailures` expects
  "Cannot convert ArkTS external to String". 24 host and 89 device tests pass on both.
  Benchmarks `*-2026-10-16-1529`: no change; `convert.bool`, whose boolean now also goes
  through `isExternal()` in `retain`, 1.03 (phone) / 0.97 (emulator) of `*-1523`.
- **Index types are `ark_interop`'s** (2026-10-16). `ark_interop` takes `Int64` element
  positions (`getElement` / `setElement`) and `JSKeyable` keys (`String`, `JSString`,
  `JSSymbol`, `Utf16String`, `Float64`). `toIndex` now accepts `Int64` (element), `String`,
  `Float64` and `Utf16String` (keys), and `Extern` values as before; `Int32` is no longer an
  element position and every other Cangjie integer type stays unsupported ("Unsupported ArkTS
  index type"; convert with `Int64(i)`). A `Float64` key on an array reaches the element through
  the engine (`e.items[1.0]` is element 1). Tests: `step5.indexReadWrite` reads `e.items[0.0]`
  and `e[Utf16String("num")]`, writes `e.items[1.0]` and `e[0.25]`; `step5.unsupportedIndex`
  and `step7.ownExceptionsNotWrapped` expect `Int32` / `UInt8` indices to throw;
  `step9.mixedScenario` writes `o.items[1.0]`. README updated. 24 host and 89 device tests pass
  on both. Benchmarks `ohos-2026-10-16-1614`, `emulator-…-1615`: array benchmarks (which index
  with `Int64`) 0.96–1.05 of `*-1529` on the phone; the emulator's `array.loop1000` 1.29 is not
  matched on the phone.
- **`Extern` numbers as indices are property keys** (2026-10-16). Their `ark_interop` type is
  `Float64` (`toNumber()`), a `JSKeyable`, so they now behave as a Cangjie `Float64` key:
  `Key(value.toNumber())`, JS's rules (on an array `a[Extern 1]` is element 1, past the end
  `undefined`; on a `Map`, typed array or plain object a property). The integral / ±9e18 check
  that sent them to `getElement` is gone, with its edge cases (-0 on an object threw, ≥ 2^32
  threw an unwrapped `OverflowException`). Tests changed: `step5.indexBoundaries` (`a[Extern 5]`
  is `undefined`), `numberKeys` (-0 sets "0"), `nonArrayIndexing` (`u8[Extern 1]` is 2),
  `indexReadWrite` (comments). New benchmarks `array.readFloat64Index` and
  `array.readExternIndex` (`ark_interop` variant: `getProperty(Float64)`). Results
  `*-2026-10-16-1625`, ns/op, `ark_interop` / `arkts_runtime`: phone readElement 374 / 1610,
  readFloat64Index 474 / 1527, readExternIndex 575 / 1628; emulator 72 / 443, 104 / 425,
  116 / 425. In `ark_interop` a number key costs about 100 ns (phone) more than `getElement`;
  in `arkts_runtime` the three are within noise of each other. 24 host and 89 device tests pass
  on both.
- **An `Extern` converted to an `Extern` keeps its handle** (2026-10-16). `toExtern` of an
  `Extern` and `fromExtern<Extern<ArkTSRuntime>>` return `eval(value)`: an evaluated value as
  is (no `run`, no second global handle), an unevaluated tree evaluated as before. The compiler
  never generates these calls; code that writes them explicitly (`fromExtern<E>(o.nested)` in
  step 9) benefits. `fromExtern` checks for the `Extern` target after the immediate shortcut, so
  number / boolean reads do not pay for it. Test hook `sameHandle(a, b)` in `handle.cj`;
  `step6.externInputs` checks `to(a)` and `from<E>(a)` keep `a`'s handle, a second `retain`
  does not, and `from<E>` of a tree is a `Ref` payload. 24 host and 89 device tests pass on
  both. Benchmarks `*-2026-10-16-1635` and `ohos-…-1636` / `emulator-…-1637`: no measurable
  change; `string.length` (a non-immediate `fromExtern`) 3915 → 4464 → 4111 ns on the phone,
  897 → 1146 → 953 on the emulator.
- **Benchmark history chart** (2026-10-16): each generated `.html` has a line chart below the
  table, built by `write_chart` in `run.sh` from every `.csv` of the same device in `results/`,
  oldest first: one line per benchmark, `arkts_runtime` ns/op on a logarithmic axis, inline
  SVG (hover highlights a line and shows a point's value). First in `*-2026-10-16-1523.html`.

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

Location: `hosttest/` at the project root (outside the DevEco build), one `*_test.cj` per
topic, `@Test` classes from `std.unittest`. Run with:

```
cjc --test hosttest/*.cj -o hosttest/run \
    --link-options="-syslibroot $(xcrun --show-sdk-path)" && \
DYLD_LIBRARY_PATH=~/.cangjie-sdk/6.1/cangjie/build-tools/runtime/lib/darwin_aarch64_cjnative \
    hosttest/run
```

wrapped in `hosttest/run.sh`.

### Layer 2: device tests (emulator and phone, real ArkTS VM)

Instrumented tests in `arkts_runtime/testapp/entry/src/ohosTest` with `@ohos/hypium`, which import
`libohos_app_cangjie_entry.so` and call Cangjie test entry points.

- **Cangjie side:** `arkts_runtime/src/tests/` (package `arkts_runtime.tests`, a subpackage
  so it can reach internal members; compiled only for testapp's bundle name via `@When`) holds
  one function per scenario, one file per step, registered in `registry.cj`. Each scenario returns
  `""` on success or a failure message (expected vs actual, or the exception class and
  message). `testapp`'s `index.cj` exports them through `JSModule.registerModule`.
- **ArkTS side:** `arkts_runtime/testapp/entry/src/ohosTest/ets/test/ArkTSRuntime.test.ets` with one `describe` per
  step and one `it` per scenario, asserting `expect(result).assertEqual("")`.
- **Checks from both sides.** Scenarios receive ArkTS fixture objects as arguments. When
  Cangjie changes a JS value, the ArkTS test checks the effect with plain ArkTS code
  (`expect(rect.width).assertEqual(5)`), independently of our `fromExtern`. When ArkTS
  produces a value, Cangjie checks it after conversion.
- Fixtures in `arkts_runtime/testapp/entry/src/ohosTest/ets/test/fixtures.ets`: `Rectangle` class (`width`,
  `height`, `area()`), `calculator` object, functions that record their `this`, arrays, an
  object with a symbol key, a function that throws, a getter with a call counter.

Build and run with `./arkts_runtime/devicetest.sh` (`DEVICE=<id>` to pick a target, `--all` for every
connected device; extra arguments go to `aa test`, e.g. `-s class Step0_Infrastructure`). It builds `testapp`'s `entry@default` and
`entry@ohosTest` with DevEco's `hvigorw`, installs both HAPs with `hdc`, runs
`aa test -b com.example.testArkTSForeignRuntime -m entry_test -s unittest OpenHarmonyTestRunner`, prints
one line per test, and exits non-zero on failure. Full runner output is in
`arkts_runtime/.devicetest/last-<device>.log`, build logs in `arkts_runtime/.devicetest/build-*.log`.

Outside the IDE, hvigor only accepts `cangjieOptions` when `DEVECO_CANGJIE_PLUGIN_ENABLED=true`
and `DEVECO_CANGJIE_PATH` are set and `@ohos/cangjie-build-support` (from the Cangjie SDK) is on
`NODE_PATH`; packaging needs DevEco's bundled Java. The script sets all of this up.

Scenario names are `step<N>.<name>`; `runArkTSTest(name, ...fixtures)` and
`listArkTSTests()` are exported from `index.cj`.

**Off-thread scenarios.** ArkTS calls scenarios on the JS thread and waits for the answer, so
a scenario that waits for a spawned thread calling `run` would deadlock (the JS thread could
never execute the posted operation). Such scenarios are registered separately
(`OffThreadScenario = () -> String`, no fixtures) and called with
`runArkTSTestOffThread(name)`, which runs the body on a spawned thread and returns a
`Promise<string>` resolved on the JS thread. The ArkTS `it` awaits it.

**Garbage collection in tests.** ArkTS only runs a full collection on its own schedule;
`collectUntil` in `ArkTSRuntime.test.ets` forces one with `hidebug.dumpJsHeapData` and yields to
the event loop around it (released handles are disposed by tasks queued on the JS thread).
Lifetime tests observe the result through `WeakRef`s, with an unretained control object to
prove the collection ran. The ArkTS test must not hold the object in a local across the
`await`s (do the check in a separate function).

### Layer 3: manual smoke check

A button in `testapp`'s `Index.ets` that runs the step 9 scenarios (by the user's choice,
not the whole suite) and shows the report on screen, for quick checks on the phone without
the test runner. The demos (`./demo.sh demos/<name>`) are checked by hand the same way; with
`uitest` the screen can be read from the Mac (`uitest dumpLayout`, `uitest uiInput click`).

### Test conventions

- Every public method gets at least one success test and one failure test (expected
  exception type).
- Exceptions are asserted by type, and by message only where the message is part of the
  contract.
- The real runtime is bound before any test runs (at module registration) and binding is
  permanent, so the unbound state and the first bind are not tested (see step 2 status).
- Concurrency code gets a mutation check: break it on purpose once and confirm a test fails.
- A failing test is never deleted or weakened to make a step pass; if the expected behaviour
  was wrong, the plan or the design doc is updated first.

## Files

```
arkts_runtime/
├── cjpm.toml       static library "arkts_runtime" (src-dir ./src)
├── README.md       for apps using the library
├── src/
│   ├── exceptions.cj   ArkTSContextNotBoundException, ArkTSContextAlreadyBoundException
│   ├── runtime.cj      ArkTSRuntime: bind, context, run, ArkTSResult, eval, evalTree, call, index
│   ├── handle.cj       ArkTSHandle (Imm / Ref), retain, evalPayload
│   ├── conversion.cj   toJSValue, toExtern, fromExtern, array helpers
│   ├── helpers.cj      undefined, null, object, global, symbol, strictEqual, isNull, isUndefined,
│   │                   objectHasProperty, objectKeys, objectDefineOwnProperty,
│   │                   requireArkModule, requireSystemNativeModule, function
│   └── tests/          device scenarios, one file per step
├── testapp/        DevEco project of the test app (com.example.testArkTSForeignRuntime)
│   ├── entry/cjpm.toml                   arkts_runtime = { path = "../.." }
│   ├── entry/src/main/cangjie/index.cj   binds the runtime, exports the scenario entry points
│   ├── entry/src/main/ets/               smoke page, arkts/TestModule.ets
│   └── entry/src/ohosTest/ets/test/      hypium suites and fixtures
└── devicetest.sh   builds testapp, installs it and runs the suite
demos/hello, demos/rectangle          one DevEco project each (mixed apps, Cangjie UI)
dependencies_libs/base/arm64-v8a/     shipped Cangjie libraries, copied into every app
dependencies_libs/ui/arm64-v8a/       Cangjie UI libraries, copied into Cangjie UI apps
hosttest/                             host tests and run.sh
demo.sh                               build, install and start one demo
```

All runtime files declare `package arkts_runtime`. The class body lives in
`runtime.cj`. Members shared across files (`context`, `run`, `evalTree`, `retain`,
`toJSValue`) use the default `internal` visibility. Public helpers in `helpers.cj` are added
with `extend ArkTSRuntime { public static func ... }`. Both points are verified in step 1.
`handle.cj` also uses an `extend` (internal `retain`, `evalPayload`, `handleKind`) so the
private `ArkTSHandle` stays in that file; the design has them in the class body. An `extend`
cannot see `private` class members or declare stored (static) variables, so anything needing
either goes in the class body; move these back there if that ever applies.

## Steps

### 0. Test infrastructure

Code:
- `hosttest/run.sh` and a trivial host test.
- `RecordingRuntime` in `hosttest/`.
- `arkts.tests` package with one trivial scenario returning `""`, exported from `index.cj`.
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
- `R.fromExtern<Float64>(e.a.b)` receives the evaluated result (no forced cast yet).
- `let _: Extern<R> = expr` skips `toExtern` (compiler bug, pinned).
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
- Scenarios call a public static from the class body and one from the `extend`.
- Stubs throw `ExternUnsupportedOperation`, reached directly, through `e.f` and through an
  implicit conversion (proves the device toolchain dispatches to our class).
- Exception classes print their own name.
- A compile-fail check: `index.cj` (parent package, i.e. user code) referencing an `internal`
  member or instantiating `ArkTSRuntime` fails to build (run once by hand, not part of the suite;
  result noted in Status).

Done when: all tests pass on emulator and phone; the `internal` / `extend` layout is confirmed
or the Files section is updated.

### 2. Context binding

Code:
- `private static let contextMutex = Mutex()`, `private static var context_: ?JSContext = None`.
- `public static func bind(newContext: JSContext): Unit`.
- `static prop context: JSContext`, throws `ArkTSContextNotBoundException` when unbound.
- `public static func isBound(): Bool` (needed by tests and by apps).

Tests (device; the runtime is already bound by `index.cj` when they run):
- `isBound()` is true.
- The bound context is the engine the tests run in (same global object, on its bind thread).
- `bind` again throws `ArkTSContextAlreadyBoundException`; context unchanged.
- 8 `spawn`ed threads released together call `bind`, 50 rounds: all throw; context unchanged.

Not tested: unbound state, first bind, concurrent first binds (see Status).

Done when: all tests pass on emulator and phone.

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
- Nested: an operation that itself calls `run` completes, from the JS thread and from a
  spawned thread (no deadlock, because the inner call sees `isInBindThread()`). Repeat through
  a public entry point once one uses `run` (step 5).
- Engine calls (`context.string`, `context.number`) work inside the operation from both
  threads.
Known limitation (documented, not tested): if the JS thread blocks waiting for a `spawn`ed
thread that is itself inside `run`, both wait forever. No public method of the runtime waits on
another Cangjie thread, so this can only come from user code.

Done when: all tests pass on emulator and phone, including repeated runs (suite run 3 times)
to catch flakiness.

### 4. Handles

Code:
- `private enum ArkTSHandle { Imm(JSValue) | Ref(JSHeapObject) }` in `handle.cj`.
- `retain(value: JSValue): Extern<ArkTSRuntime>` and `evalPayload(payload: Any): JSValue`
  (internal, in an `extend ArkTSRuntime`), plus the test hook `handleKind`.
- No public `fromJSValue` / `toJSValue` for now (decided in step 4).

Tests (device):
- `retain` classification for each JS kind: `undefined`, `null`, boolean, number → `Imm`;
  string, bigint, symbol, object, array, function, ArkTS class instance → `Ref` (through
  `handleKind`).
- Round trip: `evalPayload(retain(v)) === v` for every kind.
- A value retained inside a `newScope` is usable after it closes and 10 000 other scopes.
- Foreign payloads (`Int64`, a bare `JSValue`, a hand-built `ExternPayload(42)`) throw
  `ExternConversionException`; `handleKind` of an unevaluated node is "not a payload".
- Survival and release across full GC: ArkTS creates two objects, Cangjie retains one, ArkTS
  keeps only `WeakRef`s. After forced full collections the unretained control object is gone
  (proves a collection ran) and the retained one is alive and `===` the kept Extern (Cangjie
  changes it, ArkTS sees the change). After Cangjie drops the Extern, the object is collected.
- Release under load: 10 rounds of 100 000 objects retained and dropped; ArkTS heap after full
  collections grows less than 10 MB between rounds 4 and 10.
- Off-thread: a value retained in one `run` is held by a spawned thread and used in a later
  `run`; 10 000 handles dropped on a spawned thread, then the engine still works.

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
- Indexing: `Int64` / `Int32` → property named after the number (`"5"`); `String` → property;
  `Extern` → string key, symbol key, number → its JS string form (`String(n)`);
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
written with dynamic syntax in `arkts.tests`, plus the Layer 3 button.

Tests (device):
- The design example produces `area == 25.0` (with `height = 5.0`) and ArkTS sees
  `width == 5.0`.
- A mixed scenario using every feature in one function, run 1 000 times.
- Full suite run 3 times in a row on emulator and phone.

Done when: all tests pass; smoke page shows all PASS on the phone.

### 10. Library and separate apps

Code: move the runtime out of `entry` into a library folder that several apps use. Today's
project becomes the test app, and each demo is its own small DevEco project (own
`AppScope`, own bundle name, own signing), built, installed and run separately. Apps depend
on the library by relative path and use only its public API (except the test app's
scenarios, which live in the library).

```
ExternWithEnum/                    plain folder (no longer a DevEco project)
├── arkts_runtime/                 the library
│   ├── cjpm.toml                  name = "arkts_runtime", output-type = "static"
│   ├── README.md                  for consumers (see Docs)
│   ├── libs/arm64-v8a/            runtime/ + ohos/ (moved from entry), copied into every app
│   ├── libs-ui/arm64-v8a/         Cangjie UI libraries, copied into Cangjie UI apps
│   └── src/
│       ├── runtime.cj, handle.cj, conversion.cj, helpers.cj, exceptions.cj
│       │                          package arkts_runtime
│       └── tests/                 package arkts_runtime.tests (device scenarios)
├── testapp/                       today's project, moved: com.example.testArkTSForeignRuntime
│   └── entry/
│       ├── cjpm.toml              [dependencies] arkts_runtime = { path = "../../arkts_runtime" }
│       ├── src/main/cangjie/index.cj   binds the runtime, exports the test entry points
│       ├── src/main/ets/          smoke page, TestModule.ets
│       └── src/ohosTest/          hypium suite, fixtures
├── demos/
│   ├── rectangle/                 com.example.arkts.rectangle
│   └── hello/                     com.example.arkts.hello
├── hosttest/                      compiler contract
├── devicetest.sh                  runs testapp (as today)
└── demo.sh                        demo.sh <folder>: build, install and start one demo
```

Each app ships its own copy of the Cangjie libraries, so there is exactly one std-core per
app, and each app has exactly one `ArkTSRuntime`, bound once in its `registerModule`.

Agreed with the user:
- Today's project moves into `testapp/`; the user reopens it from there in DevEco.
- The user creates both demo projects with DevEco's wizard (CangjieUI template) in
  `demos/rectangle` and `demos/hello`, with their bundle names, and signs them; we fill them
  in.
- Both demos have their UI in Cangjie; ArkTS only for the code they call (`Rectangle`,
  `sayHello`).
- Probe 4 runs first. If it fails, stop and report before doing the rest of the step.
- After probe 4 (pure CangjieUI cannot load ArkTS code, see status): both demos are **mixed
  apps**. ArkTS boilerplate is limited to `EntryAbility.ets` and a page that embeds the
  Cangjie view with `CJHybridComponent` and calls the exported Cangjie `init()` once; the
  wizard's Cangjie ability / stage files are removed.

Demos (no automated suite; checked by hand on the phone, and on the emulator with `uitest`
as in step 9):
- **`rectangle`**: a Cangjie view running the design's section 1 example. `Rectangle` /
  `createRectangle` are in an ArkTS module; a button runs the example from Cangjie, and the
  page shows the width and area read back from ArkTS (5 and 25) and the width as seen by an
  ArkTS function `describe(rect)` (`"5 x 5 = 25"`), so ArkTS confirms the update.
- **`hello`**: the whole visible UI in Cangjie (a `@HybridComponentEntry` view). Besides the
  boilerplate, the only ArkTS-side code is `sayHello(onTick)` in `entry/src/main/ets/Hello.ets`,
  which publishes itself as `globalThis.Hello`; the page imports it, and the view reads
  `ArkTSRuntime.global().Hello` (no `init()`, see status). The view has one button; pressing it calls
  `sayHello` with a Cangjie callback
  (`ArkTSRuntime.function`, below). `sayHello` calls `onTick("Hello world", 0)` at once, then
  `onTick("Hello world", n)` for n = 1 to 5, one per second (`setTimeout`, so the UI keeps
  running), then `onTick("", -1)`. The callback updates the page's state: it shows the text
  and the counter, and returns to the initial screen on -1. The button is disabled while
  the counter runs.

Library addition: **Cangjie functions as ArkTS functions.** `toJSValue` only converts values
and `Extern`, so a Cangjie lambda cannot be passed to ArkTS today. New public helper:

```cangjie
public static func function(body: (Array<Extern<ArkTSRuntime>>) -> Extern<ArkTSRuntime>): Extern<ArkTSRuntime>
```

It wraps `body` in an `ark_interop` function (`context.function`). When ArkTS calls it, the
arguments are retained as `Extern` values, `body` runs on the JS thread, and its result is
converted back (`toJSValue`, so implicit conversions such as `return 3` work). `this` is not
passed (left for later). An exception thrown by `body` must reach ArkTS as a JS error with
its message, not crash the app; how `ark_interop` does that is a probe (5).
- Device scenarios in `arkts.tests` (step 10 group): ArkTS calls the function with numbers,
  strings and objects and checks the result; `Array.prototype.map` with a Cangjie callback;
  a Cangjie function stored on an object and called later from a timer; an exception in
  `body` caught by an ArkTS `try` with the message; the function can be called after the
  creating `run` returned, and the closure's captured state is kept between calls;
  creating it from a spawned thread works (the call itself always runs on the JS thread).

Probes first (each a throwaway project, results recorded under Constraints):
1. hvigor and `cjpm` accept a path dependency outside the project root
   (`../../arkts_runtime`). Fallback: list `arkts_runtime` as a module in each app's
   `build-profile.json5` with `srcPath: "../../arkts_runtime"`.
2. The shipped libraries can live in the library and end up in each app (exactly one
   `libcangjie-std-core.so` in the installed app, checked with `hdc shell ls`). Fallback:
   `demo.sh` / `devicetest.sh` copy them into each app's `entry/libs` before building.
3. `@When[...]` with a `--cfg` from the consumer's build can leave out the whole
   `arkts_runtime.tests` package, so the demos do not contain the scenarios.
4. A CangjieUI app can bind the runtime and load an ArkTS module. Two risks: binding needs
   a `JSContext`, which today comes from `JSModule.registerModule` when ArkTS loads the
   library (a CangjieUI app may never do that); and `requireArkModule` failed off the JS call
   stack in step 8, which a button handler in a CangjieUI app may also be. The UI in Cangjie
   is a requirement, so a failure here is reported to the user, not worked around with an
   ArkTS page.
5. How an exception thrown inside an `ark_interop` function callback reaches JS (a JS error
   with the message, or a crash), and how to throw a JS error from Cangjie if it does not.

Decisions (defaults, changed only if a probe fails):
- **Package name** `arkts_runtime`; every `ohos_app_cangjie_entry.arkts` reference is renamed.
- **Tests stay in the library** as `arkts_runtime.tests`, since seven of the ten scenario
  files use internal members (`retain`, `evalTree`, `handleKind`, `run`, ...), which are not
  visible outside the package tree. They are compiled only with the test flag (probe 3); if
  that cannot work, they ship, and this is noted as a known cost.
- **Static linking.** `ArkTSRuntime` keeps its state in static members, so every `.so` that
  links the library statically has its own copy (own binding; `Extern` values cannot cross
  copies). Each app has one such `.so`, so this is fine.
- **Separate projects, not one project with several products or feature modules:** no
  shared install folder, so no risk of a second std-core, and a demo can be removed without
  touching the others. Cost: each project repeats about ten small hvigor files and needs its
  own signing setup.
- **`hello` and threads.** The waiting is an ArkTS timer and the callback runs on the JS
  thread, which is also the UI thread, so no Cangjie thread is spawned and the page state is
  updated directly.
- **Binding stays with the app:** the library cannot register an ArkTS module, so the
  consumer's `JSModule.registerModule` calls `ArkTSRuntime.bind` (as `index.cj` does now).
- Publishing (HAR on ohpm, or binary `cjpm` dependency with `.cjo`) is out of scope.
  Consumers need the same `cjc` (`Extern` lives in its `std.core`), and a `.cjo` works only
  with the compiler that built it.

Docs: a short `arkts_runtime/README.md` for consumers covering the toolchain, binding in
`registerModule`, the shipped libraries (one std-core per app), `requireArkModule`
specifiers (`<module>/src/main/ets/<path>`, plus `arkOptions.runtimeOnly.sources`) and its
off-thread limitation.

Tests:
- Host: 35 tests pass with `hosttest/run.sh` reading from the library.
- Device: the whole suite (90 tests) passes unchanged from `testapp`, 3 times on emulator and
  phone; the smoke page shows all PASS.
- `testapp`'s `index.cj` still cannot use internal members (deliberate failing build, as in
  step 1).
- The demos build without the test flag, and their library output contains no
  `arkts_runtime.tests` symbols.
- The `ArkTSRuntime.function` scenarios pass, with a mutation check (arguments passed in the
  wrong order).
- `rectangle` shows width 5 and area 25. `hello` shows "Hello world" and the counter 1 to 5,
  returns to the initial screen after about 5 seconds, and ignores presses while counting.
  Both checked with `uitest` on the emulator (screen text read with `dumpLayout`, `hello`
  sampled during and after the count) and by hand on the phone.
- All three apps installed at the same time on one device run independently.

Done when: the probes are recorded, all tests pass from `testapp`, both demos work on the
emulator and the phone, and no app contains runtime code.

### 11. Benchmarks: `arkts_runtime` against `ark_interop`

A demo app that times the same operations written twice: with typical `ark_interop` code
(`JSContext`, `JSObject`, `JSValue`, as a user of `ark_interop` would write it, without
hand-made caches) and with `Extern<ArkTSRuntime>` syntax. The ratio is the cost of the
runtime. The same set is rerun after each optimization in step 12 to measure what it gains.

App: `demos/benchmarks` (`com.example.arkts.benchmarks`). Unlike the other demos it has no
Cangjie UI (so it ships only `dependencies_libs/base`): an ArkTS page drives the runs and calls
three functions the Cangjie module exports from `registerModule`: `benchmarkNames()`,
`iterations(name)` and `runBenchmark(name, variant, done)`, which times one run of N
iterations in Cangjie (`MonoTime`) and reports the nanoseconds to `done`. The ArkTS fixtures
are in `entry/src/main/ets/Bench.ets`, published with `globalThis.Bench = { ... }` and imported
by the page (no `requireArkModule`). The benchmarks are Cangjie, one file per group
(`cangjie/b01_property.cj` … `b10_exceptions.cj`, harness in `harness.cj`), each with an
`arkInterop` and an `arktsRuntime` variant of the same operation. A run of the `ark_interop`
variant is inside one `newScope`, as a user would write a loop.

Benchmarks (each group: both variants, same fixture, same result checked once so neither
variant can skip work):
1. Property access: read and write a number field; read `a.b.c.d`.
2. Calls: method with 0, 1 and 3 arguments; free function.
3. Arrays: read and write `items[i]` within bounds; a loop over 1 000 elements.
4. Strings: `str.length`; reading a short (10 characters) and a long (10 000) string into
   Cangjie.
5. Conversions: `toExtern` / `fromExtern` of `Float64`, `Bool`, `String`, `Array<Float64>`
   (1 000 elements), nested arrays, `Option`.
6. Consecutive statements: two and three property writes in a row.
7. Callbacks: ArkTS calls a Cangjie function made with `ArkTSRuntime.function`, against one
   made with `JSContext.function`.
8. Handles: create and drop `Extern` objects; time, and ArkTS heap growth
   (`hidebug.getAppVMObjectUsedSize`) after forced full collections (`hidebug.dumpJsHeapData`,
   as in step 4).
9. Other threads: benchmark 1's read from a spawned thread (every operation goes through
   `postJSTask`).
10. Exceptions: a JS `throw` caught in Cangjie.

Method:
- Release build (`-O2`, as `profile.customized-option.release`).
- Per benchmark and variant: R = 5 timed runs of N iterations, each right after an untimed
  run, with 20 ms between runs (N chosen per benchmark so a run of the slower variant takes
  about 100 ms on the phone). Reported: median ns per operation for each variant, and the
  ratio `arkts_runtime / ark_interop`.
- No pass / fail thresholds: numbers are recorded and compared between runs.
- Phone and emulator; the phone's numbers are the reference.

Running: `demos/benchmarks/run.sh [--all]` builds the app, installs it, starts it and waits for
the end. The app runs every benchmark once at start and logs one line per benchmark to
hilog (tag `ArkTSBench`); the script collects those lines into two files with the same table
(benchmark, N, `ark_interop` ns/op, `arkts_runtime` ns/op, ratio, heap growth in KB):
- `demos/benchmarks/results/<device>-<date>.csv`: one header row, then one row per
  benchmark; the date, device and build mode are columns, so files can be concatenated.
- `demos/benchmarks/results/<device>-<date>.html`: a self-contained page (no external files)
  with the date, device and build mode above the table, to open in a browser. Clicking a
  benchmark name shows the code of its two variants (the `{ ... }` arguments of
  `Benchmark(...)`, copied from the sources at the time of the run, so each file records
  what it measured); `Bench.ets` and the shared helpers are below the table.

The page shows the same table. The script only writes the results files (and its logs in
`.devicetest/`); it never runs git. On the device it only turns hilog's flow control off for
the run and back on after.
Results files are not ignored, so they stay next to the app and runs before and after an
optimization can be compared.

Done when: all 10 groups run on phone and emulator and a first pair of results files per
device is saved, as the baseline for step 12.

### 12. Optimizations (each behind its own tests)

1. `ExternSequence` handled in `eval` / `evalTree`.
   - Host: with `--enable-extern-sequence`, `RecordingRuntime` sees `ExternSequence` for two
     consecutive statements.
   - Device: the whole suite passes with the flag on and off; a sequence of two calls runs in
     one `run` (counter hook); the first result is not retained; benchmark 6 (consecutive
     statements) against the step 11 baseline.
2. Property-name cache.
   - Device: whole suite passes; benchmark 1 (property access) is measurably faster than in
     the step 11 baseline.
3. Path / batch access waits for the new `ARKTS_*` FFI functions.
4. ~~Fast path for array elements~~: superseded, integer indices always use `getElement` /
   `setElement` since access follows `ark_interop` (status, 2026-10-16).
5. ~~Cache the JS conversion functions `Object` and `String`~~: superseded, `objectFor` and
   `jsString` are gone since access follows `ark_interop` (status, 2026-10-16).

## Open points

- ~~Exact exception type thrown by `ark_interop` on a JS exception (step 7).~~ Resolved:
  `BusinessException` code 34300002, see step 7 status. To add to the design doc: the JS
  error value and stack are not available through `ark_interop`.
- ~~Whether `requireArkModule` paths resolve as `"entry/ets/..."` in this project layout
  (step 8).~~ Resolved: `"entry/src/main/ets/..."`, see step 8 status. To add to the design
  doc: `requireArkModule` fails off the JS call stack (spawned threads).
- ~~Compound assignment semantics in step 5 are ours; to confirm or move into the design
  doc.~~ Resolved: compound assignment is not supported (see "Compound assignment removed").
  To add to the design doc.