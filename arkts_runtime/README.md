# arkts_runtime

`ArkTSRuntime`, the runtime behind `Extern<ArkTSRuntime>`: Cangjie code reads and writes
ArkTS values with ordinary syntax (`blob.width = 3.0`, `api.createRectangle()`).

```cangjie
import arkts_runtime.ArkTSRuntime

let api: Extern<ArkTSRuntime> = ArkTSRuntime.requireArkModule("entry/src/main/ets/Rectangle")
let blob = api.createRectangle()
blob.width = 3.0
let width = ArkTSRuntime.fromExtern<Float64>(blob.width)
blob.width = width + 2.0
let area: Float64 = ArkTSRuntime.fromExtern<Float64>(blob.area())
```

Compound assignment (`blob.width += 2.0`, `e[i] &&= v`, ...) is not supported: it throws
`ExternCompoundAssignmentException`.

## Requirements

- The Cangjie SDK in `~/.cangjie-sdk/6.1/cangjie`: its `cjc` has `Extern<T>` and
  `ForeignRuntime<T>` in `std.core`. The app must be built with it (`DEVECO_CANGJIE_PATH`).
- The app ships the matching Cangjie libraries (below).

## Using it in an app

1. `entry/cjpm.toml`: depend on the library by path, and remove
   `[profile.build.combined]` (it merges the library's packages into one and makes a cycle):

   ```toml
   [dependencies]
     arkts_runtime = { path = "../../arkts_runtime" }
   ```

2. Bind the runtime when ArkTS loads the app's Cangjie library:

   ```cangjie
   let EXPORT_MODULE = JSModule.registerModule {
       runtime, exports =>
       if (!ArkTSRuntime.isBound()) {
           ArkTSRuntime.bind(runtime)
       }
       // exports ...
   }
   ```

3. `entry/hvigorfile.ts`: copy `dependencies_libs/base` (and `dependencies_libs/ui` for a
   Cangjie UI) from the repository root into `entry/libs` on every build (hvigor does not
   package a symlinked folder). See `demos/hello/entry/hvigorfile.ts`.

## Shipped libraries

The app must load exactly one Cangjie runtime and one `std-core`: with two, runtime type
checks disagree or the app crashes at start.

Why not use the phone's own libraries: the library is compiled with the Cangjie 6.1 SDK, whose
`std-core` defines `Extern<T>` and `ForeignRuntime<T>`. The phone's `std-core`
(`/system/lib64/platformsdk/cjsdk`) is an older build without them (no `Extern` or
`ForeignRuntime` symbols), so the app must ship the SDK runtime and `std-core`. A Cangjie
library loaded from the system folder resolves its own dependencies there and brings the
system `std-core` next to ours. So every Cangjie library the app uses is shipped too (copied
from the phone, they run on our `std-core`): the launcher looks in the app's
`libs/arm64/runtime` and `libs/arm64/ohos` before the system folder.

The libraries are in `dependencies_libs/` at the repository root:

- `base/arm64-v8a`: the SDK runtime and std libraries, plus `ark_interop`, `hilog`, `labels`
  and `business_exception` copied from the phone. Every app needs it.
- `ui/arm64-v8a`: the Cangjie UI libraries (`kit.ArkUI`, `ohos.arkui.*`, ...) copied from the
  phone (system 6.1). Only apps with a Cangjie UI need it; without it they load the system
  runtime and `std-core` next to ours and crash.

## Loading ArkTS modules

- Specifiers are `<module>/src/main/ets/<path>` without extension. A file nothing imports must
  be listed in `arkOptions.runtimeOnly.sources` of `entry/build-profile.json5`.
- `requireArkModule` works only while ArkTS is calling into Cangjie. It fails during
  `registerModule`, from Cangjie UI events and from spawned threads. Load modules in a Cangjie
  function the ArkTS page calls once (`init()` in the demos) and keep the result.

## Cangjie UI

A pure CangjieUI app (Cangjie ability) cannot load ArkTS code. Use a mixed app: an ArkTS
ability and page that embeds the Cangjie view with `CJHybridComponent` (ohpm
`@cangjie/cjhybridcomponent`); the view is a `@HybridComponentEntry @Component` class. See
`demos/hello` and `demos/rectangle`.

## Cangjie functions in ArkTS

`ArkTSRuntime.function { args => ... }` makes an ArkTS function. It runs on the JS thread; an
exception thrown in it reaches ArkTS as an `Error` with the exception's text.

## Tests

`arkts_runtime.tests` holds the device scenarios, run by `testapp/` through `./devicetest.sh`.
They are compiled only when testapp builds the library. `cjpm.toml` passes the app's bundle
name as `--cfg` key `bundle`, and every top-level declaration in `src/tests` carries
`@When[bundle == "com.example.testArkTSForeignRuntime"]`, testapp's bundle name. Other apps get an empty
package. New declarations in `src/tests` need the same annotation. `testapp/` and
`devicetest.sh` are not part of the library build (`src-dir` is `./src`).
