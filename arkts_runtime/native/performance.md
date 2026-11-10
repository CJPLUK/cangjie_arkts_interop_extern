# Native backend performance validation

Validated on 2026-11-09 with both backends loaded into the **same process** on each device.
The old backend comes from commit `cbdc32f`, compiled under an isolated package name.
The current kernels are duplicated mechanically with the runtime name changed, so both
backends execute the same operations and iteration counts against the same ArkTS fixtures.
The unchanged `ark_interop` implementation is a third control variant.

Each case uses five timed samples per variant, each preceded by an untimed warm-up.
Variant order alternates forward/reverse on successive samples to reduce order bias.
All 27 case medians match or improve on the old backend on both devices. This is evidence
for these measured cases and targets, not a guarantee about every possible workload.

Ratios are optimized / old; lower is faster.

| Device | Median per-case ratio | Geometric mean ratio | Slowest per-case ratio |
| --- | ---: | ---: | ---: |
| ohos | 0.727 | 0.697 | 0.999 |
| emulator | 0.764 | 0.710 | 0.959 |

`t.a.b.c.d` still performs four independent runtime operations. No expression paths are
fused, and compiler evaluation order is unchanged. The changes reduce work within operations:

- Immutable local value structs and combined C-API type/payload decoding avoid wrapper allocation and repeated crossings.
- Fast scope/reference operations are separated from ordinary-FFI release draining and compatibility boxing; queuing reference disposal stays on fast FFI.
- Named-property operations include key creation, with explicit-length fallback for embedded NUL keys. Numeric property keys are created inside the native read.
- Short-string copying is bounded to 128 UTF-16 code units; long strings retain ordinary FFI and exact-size allocation.
- Numeric arrays use copied/pinned buffers while preserving accessors, changing bounds, exceptions, input snapshots and reentrant GC.
- Copied scalar reads avoid a second JS dispatch. Cross-thread results use a one-shot `SyncCounter` with documented publication ordering instead of a mutex/condition handoff.

Operations that can execute JS retain ordinary FFI and explicit pending-exception checks.
The library and test app use `-O2` with IEEE floating-point behavior, preserving signed zero.
The old backend retains its original build profile; the benchmark-client profile is unchanged.

Validation: 24 host tests; 95 device tests on each target in both debug and release;
independent N-API binding, Worker teardown, cancellation and late reference release on both;
hello and rectangle UI checks on both. The normal benchmark app is restored after comparison.

Release validation also exposed an allocation test that the optimizer could eliminate: the
array now escapes the dispatched closure before its size is inspected, preserving the real
`OutOfMemoryError` check. The concurrent-rebind test still races eight workers for 50 rounds,
but collects explicit outcomes with a completion counter after an intermittent SDK
`Future.get()` internal-result error; its binding assertions are unchanged.

| Benchmark | Phone old ns | Phone optimized ns | Ratio | Emulator old ns | Emulator optimized ns | Ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `array.loop1000` | 1601996.5 | 1358975.7 | 0.848 | 420547.2 | 403168.1 | 0.959 |
| `array.readElement` | 1780.4 | 1496.6 | 0.841 | 392.5 | 367.7 | 0.937 |
| `array.readExternIndex` | 1704.7 | 1362.2 | 0.799 | 478.2 | 427.8 | 0.895 |
| `array.readFloat64Index` | 1611.9 | 1318.4 | 0.818 | 423.1 | 355.7 | 0.841 |
| `array.writeElement` | 1015.7 | 855.8 | 0.843 | 357.2 | 272.7 | 0.764 |
| `call.function1` | 3405.9 | 2502.5 | 0.735 | 1286.6 | 985.7 | 0.766 |
| `call.method0` | 5604.8 | 4049.9 | 0.723 | 1647.2 | 1330.9 | 0.808 |
| `call.method1` | 6282.8 | 4326.9 | 0.689 | 2606.6 | 1426.5 | 0.547 |
| `call.method3` | 6163.6 | 4586.8 | 0.744 | 2117.3 | 1552.8 | 0.733 |
| `callback.arkTSCallsCangjie` | 2487.5 | 1951.1 | 0.784 | 925.1 | 636.7 | 0.688 |
| `convert.arrayFloat64` | 667432.3 | 248651.0 | 0.373 | 235742.1 | 107062.1 | 0.454 |
| `convert.bool` | 3368.7 | 2374.0 | 0.705 | 1108.0 | 838.8 | 0.757 |
| `convert.nestedArray` | 693239.6 | 243744.8 | 0.352 | 219102.5 | 119630.8 | 0.546 |
| `convert.optionNone` | 3516.3 | 2811.4 | 0.800 | 1030.4 | 838.3 | 0.814 |
| `convert.optionSome` | 4083.9 | 3070.6 | 0.752 | 1192.6 | 930.0 | 0.780 |
| `convert.string` | 5886.6 | 4278.5 | 0.727 | 1822.4 | 1441.6 | 0.791 |
| `exception.throwCatch` | 47357.3 | 44272.9 | 0.935 | 20633.1 | 16086.3 | 0.780 |
| `handles.createAndDrop` | 4351.9 | 2664.6 | 0.612 | 1149.8 | 883.2 | 0.768 |
| `property.readChain` | 8087.7 | 6140.6 | 0.759 | 3804.3 | 2064.3 | 0.543 |
| `property.readNumber` | 1964.9 | 1416.0 | 0.721 | 724.0 | 504.7 | 0.697 |
| `property.writeNumber` | 1294.6 | 910.0 | 0.703 | 376.1 | 304.5 | 0.810 |
| `sequence.threeWrites` | 3838.7 | 2758.4 | 0.719 | 1287.9 | 947.3 | 0.736 |
| `sequence.twoWrites` | 2836.5 | 1832.9 | 0.646 | 784.4 | 571.6 | 0.729 |
| `string.length` | 3825.7 | 3821.5 | 0.999 | 1079.5 | 806.0 | 0.747 |
| `string.readLong` | 12052.5 | 4683.1 | 0.389 | 9439.8 | 4039.2 | 0.428 |
| `string.readShort` | 4361.4 | 2824.6 | 0.648 | 1151.0 | 1019.6 | 0.886 |
| `thread.readNumber` | 252520.8 | 166852.1 | 0.661 | 143364.7 | 59794.0 | 0.417 |

Reproduce the isolated comparison:

```sh
python3 demos/benchmarks/compare_backends.py --baseline cbdc32f --all
```

The tool creates a temporary fixture and reuses the benchmark app identity. Run
`demos/benchmarks/run.sh --all` afterwards to restore the standard app. Legacy timings are
in the `arktsRuntimeLegacy` sample rows; normal HTML reports retain the two public series.

Saved paired evidence:

- [Phone samples](../../demos/benchmarks/results/ohos-2026-11-09-1754.samples.tsv).
- [Emulator samples](../../demos/benchmarks/results/emulator-2026-11-09-1754.samples.tsv).
- [Baseline and source hashes](../../demos/benchmarks/results/paired-2026-11-09-1754.json).

Earlier separate-app runs showed substantial clock/scheduler variation, including in the
unchanged control, so they are retained as intermediate history rather than used to hide
or declare individual regressions. The paired measurements above are the final comparison.
