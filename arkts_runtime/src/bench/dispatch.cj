package arkts_runtime.bench

import std.math.numeric.BigInt
import std.time.MonoTime
import arkts_runtime.*

@When[bundle == "com.example.arkts.benchmarks"]
public type Nanoseconds = Int64

@When[bundle == "com.example.arkts.benchmarks"]
var dispatchSink: Float64 = 0.0

@When[bundle == "com.example.arkts.benchmarks"]
class DispatchCase {
    DispatchCase(
        let name: String,
        let makeValue: (JS) -> NativeJSValue,
        let typeProbes: (NativeJSValue, Int64) -> Unit,
        let reflective: (NativeJSValue, Int64) -> Unit
    ) {}
}

@When[bundle == "com.example.arkts.benchmarks"]
func dispatchCase<R>(name: String, makeValue: (JS) -> NativeJSValue, consume: (R) -> Float64): DispatchCase {
    DispatchCase(name, makeValue,
        { v, n => for (_ in 0..n) { dispatchSink += consume(probedFromJSValue<R>(v)) } },
        { v, n => for (_ in 0..n) { dispatchSink += consume(ArkTSRuntime.fromJSValueReflective<R>(v)) } })
}

@When[bundle == "com.example.arkts.benchmarks"]
func asNumber(b: Bool): Float64 { if (b) { 1.0 } else { 0.0 } }

@When[bundle == "com.example.arkts.benchmarks"]
func dispatchCases(): Array<DispatchCase> {
    [
        dispatchCase<Float64>("Float64", { js => js.number(1.5) }, { r => r }),
        dispatchCase<Bool>("Bool", { js => js.boolean(true) }, { r => asNumber(r) }),
        dispatchCase<String>("String", { js => js.string("abcdefghij") }, { r => Float64(r.size) }),
        dispatchCase<Int64>("Int64", { js => js.bigint(Int64(7)) }, { r => Float64(r) }),
        dispatchCase<Int32>("Int32", { js => js.number(7.0) }, { r => Float64(r) }),
        dispatchCase<Int16>("Int16", { js => js.number(7.0) }, { r => Float64(r) }),
        dispatchCase<Int8>("Int8", { js => js.number(7.0) }, { r => Float64(r) }),
        dispatchCase<UInt64>("UInt64", { js => js.bigint(UInt64(7)) }, { r => Float64(r) }),
        dispatchCase<UInt32>("UInt32", { js => js.number(7.0) }, { r => Float64(r) }),
        dispatchCase<UInt16>("UInt16", { js => js.number(7.0) }, { r => Float64(r) }),
        dispatchCase<UInt8>("UInt8", { js => js.number(7.0) }, { r => Float64(r) }),
        dispatchCase<Float32>("Float32", { js => js.number(1.5) }, { r => Float64(r) }),
        dispatchCase<Float16>("Float16", { js => js.number(1.5) }, { r => Float64(r) }),
        dispatchCase<BigInt>("BigInt", { js => js.bigint(Int64(123456789)) }, { r => asNumber(r.sign < 0) }),
        dispatchCase<Unit>("Unit", { js => js.undefined() }, { _ => 1.0 }),
        dispatchCase<Option<Float64>>("Option<Float64>", { js => js.number(1.5) }, { r => r ?? 0.0 }),
        dispatchCase<Option<Float64>>("Option<Float64>.None", { js => js.undefined() }, { r => r ?? 0.0 }),
        dispatchCase<Option<String>>("Option<String>", { js => js.string("abcdefghij") },
            { r => Float64((r ?? "").size) }),
        dispatchCase<Option<Bool>>("Option<Bool>", { js => js.boolean(true) }, { r => asNumber(r ?? false) }),
        dispatchCase<Option<Int32>>("Option<Int32>.missesEveryRow", { js => js.number(7.0) },
            { r => Float64(r ?? 0) })
    ]
}

@When[bundle == "com.example.arkts.benchmarks"]
public func dispatchCaseNames(): Array<String> {
    dispatchCases().map { c => c.name }
}

@When[bundle == "com.example.arkts.benchmarks"]
public func timeDispatch(caseName: String, variant: String, iterations: Int64): Nanoseconds {
    for (c in dispatchCases()) {
        if (c.name != caseName) { continue }
        let loop = match (variant) {
            case "probes" => c.typeProbes
            case "reflective" => c.reflective
            case _ => throw IllegalArgumentException("unknown variant ${variant}")
        }
        return ArkTSRuntime.run {
            let value = c.makeValue(ArkTSRuntime.js)
            let start = MonoTime.now()
            loop(value, iterations)
            (MonoTime.now() - start).toNanoseconds()
        }
    }
    throw IllegalArgumentException("unknown dispatch case ${caseName}")
}
