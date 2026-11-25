# ADR-0006: Find the target type of fromExtern<R> by probing

Status: accepted

## Context

`fromExtern<R>` and the generic readers must decide, for a type parameter `R` known only at run time, which conversion applies. Asking the type system directly (`match (None<R>) { case _: Option<T> }`, `x as R`, `TypeTag<R>()`) builds type information at run time. That cost 150-350 ns per conversion on the device: more than the rest of a fused op.

## Decision

Readers find `R` by probing (`src/dispatch.cj`). `match (probe) { case _: R }` holds when the type probe's type is `R` or one of `R`'s supertypes, and it checks against type information the generic function already receives. The type probes are preallocated values of each scalar type and of `Option<Float64 | String | Bool>`.

A hit is exact unless `R` is an interface. Two further type probes tell the cases apart:

- **The type's rival scalar also matches:** then `R` is an interface both share, such as `Any`, `ToString` or `Hashable`.
- **Its `ProbeComparable` matches:** then `R` is `Equatable<T>` or `Comparable<T>`. `ProbeComparable<T>` is a marker type that is never compared.

Both cases fall back to the reflective conversion, which rejects interfaces as ark_interop does.

An interface the user attached to the type alone (`extend Float64 <: Shape`) receives the value as that type.

## Measurement (issue #7)

`demos/benchmarks/run.sh --dispatch` reads one already-read JS value 200,000 times as `R`. It reads through the type probes (`probedFromJSValue<R>`) and through the reflective conversion (`fromJSValueReflective<R>`). `R` reaches both as a type parameter, as it does through `fromExtern<R>`. The two variants alternate within each of 9 runs, and the order flips between runs. The benchmark is `arkts_runtime/src/bench/dispatch.cj`.

The threshold was set before measuring: keep the type probes only if they save at least 100 ns per conversion for `Float64`, `String` and `Bool`.

All runs are on a Huawei ALN-AL80, with a release build, on 2026-11-25. The deciding run, `results/dispatch-ALN-AL80-2026-11-25-1354.csv`, came before the table below existed. In it, the type probes saved 392 ns for `Float64`, 329 ns for `String` and 303 ns for `Bool`.

The table is from the latest run, `-1409.csv`, which covers every type in the table. Values are medians in ns per conversion. The saving is the median of each run's paired difference.

| `R` | type probes | reflective | saving |
|---|---:|---:|---:|
| `Float64` | 54 | 419 | 365 |
| `Bool` | 54 | 331 | 279 |
| `String` | 359 | 692 | 320 |
| `Int64` (from a BigInt) | 533 | 777 | 252 |
| `Int32` | 122 | 356 | 233 |
| `Int16` | 130 | 357 | 227 |
| `Int8` | 140 | 363 | 219 |
| `UInt64` (from a BigInt) | 555 | 764 | 219 |
| `UInt32` | 154 | 348 | 193 |
| `UInt16` | 165 | 360 | 196 |
| `UInt8` | 177 | 356 | 178 |
| `Float32` | 157 | 357 | 199 |
| `Float16` | 172 | 384 | 212 |
| `BigInt` | 629 | 849 | 219 |
| `Unit` | 178 | 338 | 156 |
| `Option<Float64>` | 199 | 470 | 256 |
| `Option<Float64>`, `undefined` | 200 | 374 | 164 |
| `Option<String>` | 580 | 882 | 311 |
| `Option<Bool>` | 259 | 482 | 219 |
| `Option<Int32>`, which misses every row | 758 | 535 | -234 |

Three runs are committed: `-1354`, `-1356` and `-1409`. The reflective path is the same code in all three, and its medians move by up to 42 ns per case between runs, so differences under about 40 ns are noise.

Every type in the table saves at least 144 ns in every run. For the three deciding types, the samples never overlap. In each run, the slowest type-probe sample is at least 237 ns faster than the fastest reflective one.

A type later in the table pays for every earlier miss, about 12 ns per row. Even the last row, `Option<Bool>`, saves over 200 ns. The type probes stay.

Since they stay, the 18 repeated match blocks became one table, `probeTable`, with one row per type: (type probe, rival, sentinel, reader). In the run straight after the change, `-1356`, the type-probe timings moved by -21 to +19 ns per case, which is within the noise.

## Consequences

- Scalar and option conversions cost a few type checks against preallocated type probes.
- A type outside the table pays for all 18 misses, about 230 ns, before the reflective conversion. That covers other options such as `Option<Int32>`, arrays, and user types read through `FromJS`. An array pays it once, not per element.
- Reading a further type directly means adding a row to `probeTable`. Its position matters, because every row before it adds a miss.
- The rival and sentinel scheme is subtle. The measurement above is what justifies it, and `run.sh --dispatch` repeats it.
