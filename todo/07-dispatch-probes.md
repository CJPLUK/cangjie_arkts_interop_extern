# Benchmark the fromExtern<R> probes against `as R`, then keep or collapse them

## Where

`arkts_runtime/src/dispatch.cj`: `probeOf` (57), `probedFromJSValue` (79 and on), `ProbeComparable`. See ADR-0006.

## Problem

The rival and sentinel scheme is the subtlest code in the runtime. Its justification, that `as R` and `TypeTag<R>()` cost 150-350 ns on the device, is not reproduced by any benchmark in the repo.

## Suggested reshape

- Add a device benchmark of `fromExtern<R>` for each scalar `R`, comparing the probes with a plain `as R` (next to `demos/benchmarks/entry/src/main/cangjie/b05_conversions.cj`).
- If the gap is gone, reduce `probedFromJSValue` to `as R` plus the slow path.
- If it holds, replace the repeated match blocks with one table of (type, probe, rival, sentinel, reader).

## Done when

ADR-0006 records the measured numbers and the decision.
