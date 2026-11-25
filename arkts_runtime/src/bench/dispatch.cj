package arkts_runtime.bench

import std.math.numeric.BigInt
import std.time.MonoTime
import arkts_runtime.*

// Every top-level declaration in this package carries the `@When` below, so the package is
// empty unless the library is built by the benchmarks app (bundle com.example.arkts.benchmarks).
// It is a subpackage so that it can reach the runtime's internal conversion paths (issue #7,
// ADR-0006): `demos/benchmarks/run.sh --dispatch` runs it.

/** Every converted value is added here, so no loop can skip its work. */
@When[bundle == "com.example.arkts.benchmarks"]
var dispatchSink: Float64 = 0.0

/**
 * Reading one already-read JS value as one `R`, timed through the type probes
 * (`probedFromJSValue`) and through the reflective conversion they stand in for.
 */
@When[bundle == "com.example.arkts.benchmarks"]
class DispatchCase {
    DispatchCase(
        let name: String,
        let value: (JS) -> NativeJSValue,
        let probes: (NativeJSValue, Int64) -> Unit,
        let reflective: (NativeJSValue, Int64) -> Unit
    ) {}
}

/** `R` reaches both paths as a type parameter, as it does through `fromExtern<R>`. */
@When[bundle == "com.example.arkts.benchmarks"]
func dispatchCase<R>(name: String, value: (JS) -> NativeJSValue, consume: (R) -> Float64): DispatchCase {
    DispatchCase(name, value,
        { v, n => for (_ in 0..n) { dispatchSink += consume(probedFromJSValue<R>(v)) } },
        { v, n => for (_ in 0..n) { dispatchSink += consume(ArkTSRuntime.fromJSValueReflective<R>(v)) } })
}

@When[bundle == "com.example.arkts.benchmarks"]
func flag(b: Bool): Float64 { if (b) { 1.0 } else { 0.0 } }

/** The probe table's order is `probedFromJSValue`'s: a later type pays for every earlier miss. */
@When[bundle == "com.example.arkts.benchmarks"]
func dispatchCases(): Array<DispatchCase> {
    [
        dispatchCase<Float64>("Float64", { js => js.number(1.5) }, { r => r }),
        dispatchCase<Bool>("Bool", { js => js.boolean(true) }, { r => flag(r) }),
        dispatchCase<String>("String", { js => js.string("abcdefghij") }, { r => Float64(r.size) }),
        dispatchCase<Int64>("Int64", { js => js.bigint(Int64(7)) }, { r => Float64(r) }),
        dispatchCase<Int32>("Int32", { js => js.number(7.0) }, { r => Float64(r) }),
        dispatchCase<UInt8>("UInt8", { js => js.number(7.0) }, { r => Float64(r) }),
        dispatchCase<Float32>("Float32", { js => js.number(1.5) }, { r => Float64(r) }),
        dispatchCase<BigInt>("BigInt", { js => js.bigint(Int64(123456789)) }, { r => flag(r.sign < 0) }),
        dispatchCase<Unit>("Unit", { js => js.undefined() }, { _ => 1.0 }),
        dispatchCase<Option<Float64>>("Option<Float64>", { js => js.number(1.5) }, { r => r ?? 0.0 }),
        dispatchCase<Option<Float64>>("Option<Float64>.None", { js => js.undefined() }, { r => r ?? 0.0 }),
        dispatchCase<Option<String>>("Option<String>", { js => js.string("abcdefghij") },
            { r => Float64((r ?? "").size) }),
        dispatchCase<Option<Bool>>("Option<Bool>", { js => js.boolean(true) }, { r => flag(r ?? false) })
    ]
}

/** The names `timeDispatch` takes, in table order. */
@When[bundle == "com.example.arkts.benchmarks"]
public func dispatchCaseNames(): Array<String> {
    dispatchCases().map { c => c.name }
}

/**
 * Reads case `name`'s value `iterations` times on the owner thread, through `variant`
 * ("probes" or "reflective"), and returns the elapsed nanoseconds. The value is made before
 * the clock starts.
 */
@When[bundle == "com.example.arkts.benchmarks"]
public func timeDispatch(name: String, variant: String, iterations: Int64): Int64 {
    for (c in dispatchCases()) {
        if (c.name != name) { continue }
        let loop = match (variant) {
            case "probes" => c.probes
            case "reflective" => c.reflective
            case _ => throw IllegalArgumentException("unknown variant ${variant}")
        }
        return ArkTSRuntime.run {
            let value = c.value(ArkTSRuntime.js)
            let start = MonoTime.now()
            loop(value, iterations)
            (MonoTime.now() - start).toNanoseconds()
        }
    }
    throw IllegalArgumentException("unknown dispatch case ${name}")
}
