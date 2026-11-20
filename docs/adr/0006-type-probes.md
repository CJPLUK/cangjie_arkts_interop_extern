# ADR-0006: Find the target type of fromExtern<R> by probing

Status: accepted

## Context

`fromExtern<R>` and the generic readers must decide, for a type parameter `R` known only at run time, which conversion applies. Asking the type system directly (`match (None<R>) { case _: Option<T> }`, `x as R`, `TypeTag<R>()`) builds type information at run time. That cost 150-350 ns per conversion on the device: more than the rest of a fused op.

No benchmark in the repo reproduces that measurement.

## Decision

Readers find `R` by probing (`src/dispatch.cj`). `match (probe) { case _: R }` holds when the probe's type is `R` or one of `R`'s supertypes, and it checks against type information the generic function already receives. The probes are preallocated values of each scalar type and of `Option<Float64 | String | Bool>`.

A hit is exact unless `R` is an interface. Two further probes tell the cases apart:

- **The type's rival scalar also matches:** then `R` is an interface both share, such as `Any`, `ToString` or `Hashable`.
- **Its `ProbeComparable` matches:** then `R` is `Equatable<T>` or `Comparable<T>`. `ProbeComparable<T>` is a marker type that is never compared.

Both cases fall back to the reflective conversion, which rejects interfaces as ark_interop does.

An interface the user attached to the type alone (`extend Float64 <: Shape`) receives the value as that type.

## Consequences

- Scalar and option conversions cost a few type checks against preallocated probes.
- The rival and sentinel scheme is subtle, and its justification rests on an unrecorded measurement. See issue #7: benchmark it against `as R`, and collapse it if the difference is gone.
