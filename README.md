# ArkTS Foreign Runtime for Cangjie

This repository contains `arkts_runtime`, a Cangjie library that implements
`ForeignRuntime<ArkTSRuntime>`. With it, Cangjie code on HarmonyOS uses ArkTS values through
`Extern<ArkTSRuntime>` with ordinary syntax:

```cangjie
let api: Extern<ArkTSRuntime> = ArkTSRuntime.requireArkModule("entry/src/main/ets/Rectangle")
let blob = api.createRectangle()
blob.width = 3.0
let width = ArkTSRuntime.fromExtern<Float64>(blob.width)
blob.width = width + 2.0
let area: Float64 = ArkTSRuntime.fromExtern<Float64>(blob.area())
```

The library is the product. Everything else in the repository exists to test it or to show
it in use. The design it implements is `docs/arkts_runtime_design.md` in
`cangjie_interop_architecture`.

## Structure

```
arkts_runtime/      the library: Cangjie sources, shipped Cangjie libraries, README
testapp/            test app (DevEco project): runs the device test suite and a smoke page
demos/hello         demo app: Cangjie UI calling an ArkTS function with a Cangjie callback
demos/rectangle     demo app: the design's example, with a Cangjie UI
hosttest/           host tests (macOS, no ArkTS VM): compiler contract
devicetest.sh       builds testapp and runs the device suite on connected devices
demo.sh             builds, installs and starts one demo app
plan.md             implementation plan, status and findings of every step
```

### arkts_runtime/

```
cjpm.toml           static library "arkts_runtime"
README.md           how an app uses the library (setup, shipped libraries, limitations)
src/                package arkts_runtime: runtime, handles, conversions, helpers
src/tests/          package arkts_runtime.tests: device test scenarios, one file per step
libs/               Cangjie runtime and std libraries every app using the library must ship
libs-ui/            additional Cangjie UI libraries, for apps with a Cangjie UI only
```

Apps depend on it by path in their `entry/cjpm.toml` and copy `libs` (and `libs-ui`) into
their `entry/libs` from `entry/hvigorfile.ts`. See `arkts_runtime/README.md`.

### Tests and demos

- `testapp/` binds the runtime and exports the scenarios of `arkts_runtime.tests` to ArkTS.
  Its hypium suite (`entry/src/ohosTest`) calls each scenario and checks the results from the
  ArkTS side as well. Its main page runs the step 9 end-to-end scenarios at the press of a
  button.
- `demos/` are separate apps that use only the library's public API, each with its own
  bundle name. They are mixed apps: a minimal ArkTS ability and page that embed a Cangjie view
  (`CJHybridComponent`).
- `hosttest/` checks what the compiler generates for dynamic `Extern` syntax.

## Requirements

- DevEco Studio in `/Applications/DevEco-Studio.app`.
- The Cangjie SDK in `~/.cangjie-sdk/6.1/cangjie`, whose `cjc` has `Extern<T>` and
  `ForeignRuntime<T>` in `std.core`.
- A HarmonyOS phone or emulator connected through `hdc`, for device tests and demos.

## Running

```sh
./hosttest/run.sh                    # host tests
./devicetest.sh                      # device suite on the first connected device
./devicetest.sh --all                # ... on every connected device
DEVICE=127.0.0.1:5555 ./devicetest.sh -s class Step10_Function   # one test class
./demo.sh demos/hello                # build, install and start a demo
```

Build logs and full test runner output go to `.devicetest/`.
