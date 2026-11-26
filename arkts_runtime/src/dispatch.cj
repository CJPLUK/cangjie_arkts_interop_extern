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

class ProbeRow {
    ProbeRow(let probe: Any, let rival: Any, let sentinel: Any, let read: (NativeJSValue) -> Any) {}
}

func readOption<T>(value: NativeJSValue, read: (NativeJSValue) -> T): Option<T> {
    if (value.isUndefined() || value.isNull()) { None<T> } else { Some(read(value)) }
}

let probeTable: Array<ProbeRow> = [
    ProbeRow(probeFloat64, probeComparableFloat64, probeFloat32, { v => Float64.fromJS(v) }),
    ProbeRow(probeBool, probeComparableBool, probeInt64, { v => Bool.fromJS(v) }),
    ProbeRow(probeString, probeComparableString, probeInt64, { v => String.fromJS(v) }),
    ProbeRow(probeInt64, probeComparableInt64, probeInt32, { v => Int64.fromJS(v) }),
    ProbeRow(probeInt32, probeComparableInt32, probeInt64, { v => Int32.fromJS(v) }),
    ProbeRow(probeInt16, probeComparableInt16, probeInt64, { v => Int16.fromJS(v) }),
    ProbeRow(probeInt8, probeComparableInt8, probeInt64, { v => Int8.fromJS(v) }),
    ProbeRow(probeUInt64, probeComparableUInt64, probeUInt32, { v => UInt64.fromJS(v) }),
    ProbeRow(probeUInt32, probeComparableUInt32, probeUInt64, { v => UInt32.fromJS(v) }),
    ProbeRow(probeUInt16, probeComparableUInt16, probeUInt64, { v => UInt16.fromJS(v) }),
    ProbeRow(probeUInt8, probeComparableUInt8, probeUInt64, { v => UInt8.fromJS(v) }),
    ProbeRow(probeFloat32, probeComparableFloat32, probeFloat64, { v => Float32.fromJS(v) }),
    ProbeRow(probeFloat16, probeComparableFloat16, probeFloat64, { v => Float16.fromJS(v) }),
    ProbeRow(probeBigInt, probeComparableBigInt, probeInt64, { v => BigInt.fromJS(v) }),
    ProbeRow(probeUnit, probeComparableUnit, probeBool, { v => Unit.fromJS(v) }),
    ProbeRow(probeOptionFloat64, probeOptionFloat32, probeSentinel, { v => readOption(v) { w => Float64.fromJS(w) } }),
    ProbeRow(probeOptionString, probeOptionInt64, probeSentinel, { v => readOption(v) { w => String.fromJS(w) } }),
    ProbeRow(probeOptionBool, probeOptionInt64, probeSentinel, { v => readOption(v) { w => Bool.fromJS(w) } })
]

func probedFromJSValue<R>(value: NativeJSValue): R {
    for (row in probeTable) {
        match (probeOf<R>(row.probe, row.rival, row.sentinel)) {
            case Hit => return asR<R>(row.read(value))
            case Shared => return ArkTSRuntime.fromJSValueReflective<R>(value)
            case Miss => ()
        }
    }
    ArkTSRuntime.fromJSValueReflective<R>(value)
}
