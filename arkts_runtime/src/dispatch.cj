package arkts_runtime

import std.math.numeric.BigInt

let probeFloat64: Any = 0.0
let probeBool: Any = false
let probeString: Any = ""
let probeInt64: Any = Int64(0)
let probeInt32: Any = Int32(0)
let probeInt16: Any = Int16(0)
let probeInt8: Any = Int8(0)
let probeUInt64: Any = UInt64(0)
let probeUInt32: Any = UInt32(0)
let probeUInt16: Any = UInt16(0)
let probeUInt8: Any = UInt8(0)
let probeFloat32: Any = Float32(0)
let probeFloat16: Any = Float16(0)
let probeBigInt: Any = BigInt(0)
let probeUnit: Any = ()
let probeOptionBool: Any = None<Bool>
let probeOptionFloat32: Any = None<Float32>
let probeOptionFloat64: Any = None<Float64>
let probeOptionInt64: Any = None<Int64>
let probeOptionString: Any = None<String>

let probeComparableFloat64: Any = ProbeComparable<Float64>()
let probeComparableBool: Any = ProbeComparable<Bool>()
let probeComparableString: Any = ProbeComparable<String>()
let probeComparableInt64: Any = ProbeComparable<Int64>()
let probeComparableInt32: Any = ProbeComparable<Int32>()
let probeComparableInt16: Any = ProbeComparable<Int16>()
let probeComparableInt8: Any = ProbeComparable<Int8>()
let probeComparableUInt64: Any = ProbeComparable<UInt64>()
let probeComparableUInt32: Any = ProbeComparable<UInt32>()
let probeComparableUInt16: Any = ProbeComparable<UInt16>()
let probeComparableUInt8: Any = ProbeComparable<UInt8>()
let probeComparableFloat32: Any = ProbeComparable<Float32>()
let probeComparableFloat16: Any = ProbeComparable<Float16>()
let probeComparableBigInt: Any = ProbeComparable<BigInt>()
let probeComparableUnit: Any = ProbeComparable<Unit>()

class ProbeSentinel {}
let probeSentinel: Any = ProbeSentinel()

class ProbeComparable<T> <: Comparable<T> {
    public func compare(_: T): Ordering { Ordering.EQ }
    public operator func ==(_: T): Bool { false }
    public operator func !=(_: T): Bool { false }
    public operator func <(_: T): Bool { false }
    public operator func >(_: T): Bool { false }
    public operator func <=(_: T): Bool { false }
    public operator func >=(_: T): Bool { false }
}

enum Probe { | Miss | Hit | Shared }

func probeOf<R>(probe: Any, rival: Any, sentinel: Any): Probe {
    match (probe) {
        case _: R => ()
        case _ => return Miss
    }
    match (rival) {
        case _: R => return Shared
        case _ => ()
    }
    match (sentinel) {
        case _: R => Shared
        case _ => Hit
    }
}

func asR<R>(value: Any): R {
    match (value) {
        case r: R => r
        case _ => throw IllegalStateException("probe hit without a matching value")
    }
}

func probedFromJSValue<R>(value: NativeJSValue): R {
    match (probeOf<R>(probeFloat64, probeComparableFloat64, probeFloat32)) {
        case Hit => return asR<R>(Float64.fromJS(value))
        case Shared => return ArkTSRuntime.fromJSValueSlow<R>(value)
        case Miss => ()
    }
    match (probeOf<R>(probeBool, probeComparableBool, probeInt64)) {
        case Hit => return asR<R>(Bool.fromJS(value))
        case Shared => return ArkTSRuntime.fromJSValueSlow<R>(value)
        case Miss => ()
    }
    match (probeOf<R>(probeString, probeComparableString, probeInt64)) {
        case Hit => return asR<R>(String.fromJS(value))
        case Shared => return ArkTSRuntime.fromJSValueSlow<R>(value)
        case Miss => ()
    }
    match (probeOf<R>(probeInt64, probeComparableInt64, probeInt32)) {
        case Hit => return asR<R>(Int64.fromJS(value))
        case Shared => return ArkTSRuntime.fromJSValueSlow<R>(value)
        case Miss => ()
    }
    match (probeOf<R>(probeInt32, probeComparableInt32, probeInt64)) {
        case Hit => return asR<R>(Int32.fromJS(value))
        case Shared => return ArkTSRuntime.fromJSValueSlow<R>(value)
        case Miss => ()
    }
    match (probeOf<R>(probeInt16, probeComparableInt16, probeInt64)) {
        case Hit => return asR<R>(Int16.fromJS(value))
        case Shared => return ArkTSRuntime.fromJSValueSlow<R>(value)
        case Miss => ()
    }
    match (probeOf<R>(probeInt8, probeComparableInt8, probeInt64)) {
        case Hit => return asR<R>(Int8.fromJS(value))
        case Shared => return ArkTSRuntime.fromJSValueSlow<R>(value)
        case Miss => ()
    }
    match (probeOf<R>(probeUInt64, probeComparableUInt64, probeUInt32)) {
        case Hit => return asR<R>(UInt64.fromJS(value))
        case Shared => return ArkTSRuntime.fromJSValueSlow<R>(value)
        case Miss => ()
    }
    match (probeOf<R>(probeUInt32, probeComparableUInt32, probeUInt64)) {
        case Hit => return asR<R>(UInt32.fromJS(value))
        case Shared => return ArkTSRuntime.fromJSValueSlow<R>(value)
        case Miss => ()
    }
    match (probeOf<R>(probeUInt16, probeComparableUInt16, probeUInt64)) {
        case Hit => return asR<R>(UInt16.fromJS(value))
        case Shared => return ArkTSRuntime.fromJSValueSlow<R>(value)
        case Miss => ()
    }
    match (probeOf<R>(probeUInt8, probeComparableUInt8, probeUInt64)) {
        case Hit => return asR<R>(UInt8.fromJS(value))
        case Shared => return ArkTSRuntime.fromJSValueSlow<R>(value)
        case Miss => ()
    }
    match (probeOf<R>(probeFloat32, probeComparableFloat32, probeFloat64)) {
        case Hit => return asR<R>(Float32.fromJS(value))
        case Shared => return ArkTSRuntime.fromJSValueSlow<R>(value)
        case Miss => ()
    }
    match (probeOf<R>(probeFloat16, probeComparableFloat16, probeFloat64)) {
        case Hit => return asR<R>(Float16.fromJS(value))
        case Shared => return ArkTSRuntime.fromJSValueSlow<R>(value)
        case Miss => ()
    }
    match (probeOf<R>(probeBigInt, probeComparableBigInt, probeInt64)) {
        case Hit => return asR<R>(BigInt.fromJS(value))
        case Shared => return ArkTSRuntime.fromJSValueSlow<R>(value)
        case Miss => ()
    }
    match (probeOf<R>(probeUnit, probeComparableUnit, probeBool)) {
        case Hit => return asR<R>(Unit.fromJS(value))
        case Shared => return ArkTSRuntime.fromJSValueSlow<R>(value)
        case Miss => ()
    }
    match (probeOf<R>(probeOptionFloat64, probeOptionFloat32, probeSentinel)) {
        case Hit => return asR<R>(if (value.isUndefined() || value.isNull()) { None<Float64> } else { Some(Float64.fromJS(value)) })
        case Shared => return ArkTSRuntime.fromJSValueSlow<R>(value)
        case Miss => ()
    }
    match (probeOf<R>(probeOptionString, probeOptionInt64, probeSentinel)) {
        case Hit => return asR<R>(if (value.isUndefined() || value.isNull()) { None<String> } else { Some(String.fromJS(value)) })
        case Shared => return ArkTSRuntime.fromJSValueSlow<R>(value)
        case Miss => ()
    }
    match (probeOf<R>(probeOptionBool, probeOptionInt64, probeSentinel)) {
        case Hit => return asR<R>(if (value.isUndefined() || value.isNull()) { None<Bool> } else { Some(Bool.fromJS(value)) })
        case Shared => return ArkTSRuntime.fromJSValueSlow<R>(value)
        case Miss => ()
    }
    ArkTSRuntime.fromJSValueSlow<R>(value)
}
