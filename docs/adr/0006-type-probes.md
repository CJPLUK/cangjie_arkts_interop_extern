# ADR-0006: Find the target type of fromExtern<R> by probing

Status: accepted

## Context

`fromExtern<R>` and the generic readers must decide, for a type parameter `R` known only at run time, which conversion applies. Asking the type system directly (`match (None<R>) { case _: Option<T> }`, `x as R`, `TypeTag<R>()`) builds type information at run time. That cost 150-350 ns per conversion on the device: more than the rest of a fused op.

## Decision

Readers find `R` by probing (`src/dispatch.cj`). `match (probe) { case _: R }` holds when the probe's type is `R` or one of `R`'s supertypes, and it checks against type information the generic function already receives. The probes are preallocated values of each scalar type and of `Option<Float64 | String | Bool>`.

A hit is exact unless `R` is an interface. Two further probes tell the cases apart:

- **The type's rival scalar also matches:** then `R` is an interface both share, such as `Any`, `ToString` or `Hashable`.
- **Its `ProbeComparable` matches:** then `R` is `Equatable<T>` or `Comparable<T>`. `ProbeComparable<T>` is a marker type that is never compared.

Both cases fall back to the reflective conversion, which rejects interfaces as ark_interop does.

An interface the user attached to the type alone (`extend Float64 <: Shape`) receives the value as that type.

## Measurement (issue #7)

`demos/benchmarks/run.sh --dispatch` reads one already-read JS value 200,000 times as `R`, through the probes (`probedFromJSValue<R>`) and through the reflective conversion (`fromJSValueReflective<R>`). `R` reaches both as a type parameter, as it does through `fromExtern<R>`. The two variants alternate within each of 9 runs, and the order flips between runs. The benchmark is `arkts_runtime/src/bench/dispatch.cj`.

The threshold was set before measuring: keep the probes only if they save at least 100 ns per conversion for `Float64`, `String` and `Bool`.

The results below are medians in ns per conversion. They come from a Huawei ALN-AL80 with a release build on 2026-11-25 (`results/dispatch-ALN-AL80-2026-11-25-1354.csv`). A second run differed by at most 15 ns per case.

| `R` | probes | reflective | saving |
|---|---:|---:|---:|
| `Float64` | 50 | 442 | 392 |
| `Bool` | 46 | 349 | 303 |
| `String` | 358 | 687 | 329 |
| `Int64` (from a BigInt) | 520 | 801 | 282 |
| `Int32` | 108 | 369 | 261 |
| `UInt8` | 172 | 375 | 203 |
| `Float32` | 168 | 382 | 214 |
| `BigInt` | 617 | 850 | 233 |
| `Unit` | 187 | 331 | 144 |
| `Option<Float64>` | 220 | 467 | 247 |
| `Option<Float64>`, `undefined` | 217 | 381 | 164 |
| `Option<String>` | 540 | 845 | 305 |
| `Option<Bool>` | 237 | 485 | 248 |

The samples do not overlap. For each of the three deciding types, the slowest probed sample is at least 280 ns faster than the fastest reflective one. A type later in the probe table pays for every earlier miss, yet even the last row, `Option<Bool>`, saves 248 ns. The probes stay.

## Consequences

- Scalar and option conversions cost a few type checks against preallocated probes.
- The rival and sentinel scheme is subtle. The measurement above is what justifies it, and `run.sh --dispatch` repeats it.
