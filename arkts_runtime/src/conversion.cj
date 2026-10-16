package arkts_runtime

import std.math.trunc
import std.math.numeric.BigInt
import ohos.ark_interop.*

/**
 * Cangjie types with an ArkTS mapping. `Extern<ArkTSRuntime>` cannot be extended, so it is
 * handled apart in `toJSValue` / `fromJSValue`; `Array` and `Option` convert their elements
 * through those, so unsupported element types fail only when an element is converted.
 */
interface ToJS {
    func toJS(): JSValue
}

interface FromJS<T> {
    static func fromJS(value: JSValue): T
}

/** Reaches `FromJS<T>` from code where `T` is unconstrained (`fromExtern<R>`). */
interface JSReader {
    func read(value: JSValue): Any
}

class TypeTag<T> {}

extend<T> TypeTag<T> <: JSReader where T <: FromJS<T> {
    public func read(value: JSValue): Any {
        T.fromJS(value)
    }
}

extend ArkTSRuntime {
    /**
     * Converts an assigned value, call argument or index leaf to a `JSValue`. An `Extern` is
     * reduced with `evalTree`, so it may be unevaluated. Bind thread only.
     */
    static func toJSValue(value: Any): JSValue {
        match (value) {
            case external: Extern<ArkTSRuntime> => evalTree(external)
            case convertible: ToJS => convertible.toJS()
            case _ => throw ExternConversionException("Unsupported conversion to ArkTS")
        }
    }

    /** Reads `value` as a Cangjie `R`; `Extern<ArkTSRuntime>` is the identity. Bind thread only. */
    static func fromJSValue<R>(value: JSValue): R {
        // Concrete types skip the `TypeTag` allocation and the interface cast; only `Array<T>` and
        // `Option<T>` need them, to reach the element type's `fromJS`.
        match (None<R>) {
            case _: Option<Float64> => return (Float64.fromJS(value) as R).getOrThrow()
            case _: Option<Bool> => return (Bool.fromJS(value) as R).getOrThrow()
            case _: Option<String> => return (String.fromJS(value) as R).getOrThrow()
            case _: Option<Int64> => return (Int64.fromJS(value) as R).getOrThrow()
            case _: Option<Int32> => return (Int32.fromJS(value) as R).getOrThrow()
            case _: Option<Int16> => return (Int16.fromJS(value) as R).getOrThrow()
            case _: Option<Int8> => return (Int8.fromJS(value) as R).getOrThrow()
            case _: Option<UInt64> => return (UInt64.fromJS(value) as R).getOrThrow()
            case _: Option<UInt32> => return (UInt32.fromJS(value) as R).getOrThrow()
            case _: Option<UInt16> => return (UInt16.fromJS(value) as R).getOrThrow()
            case _: Option<UInt8> => return (UInt8.fromJS(value) as R).getOrThrow()
            case _: Option<Float32> => return (Float32.fromJS(value) as R).getOrThrow()
            case _: Option<Float16> => return (Float16.fromJS(value) as R).getOrThrow()
            case _: Option<BigInt> => return (BigInt.fromJS(value) as R).getOrThrow()
            case _: Option<Unit> => return (Unit.fromJS(value) as R).getOrThrow()
            case _ => ()
        }
        match (TypeTag<R>() as JSReader) {
            case Some(reader) => (reader.read(value) as R).getOrThrow()
            case None => match (None<R>) {
                case _: Option<Extern<ArkTSRuntime>> => (retain(value) as R).getOrThrow()
                case _ => throw ExternConversionException("Unsupported conversion from ArkTS")
            }
        }
    }
}

private func jsNumber(n: Float64): JSValue {
    ArkTSRuntime.context.number(n).toJSValue()
}

private func jsBigInt(n: BigInt): JSValue {
    ArkTSRuntime.context.bigint(n).toJSValue()
}

private func mismatch(value: JSValue, target: String): ExternConversionException {
    ExternConversionException("Cannot convert ArkTS ${jsTypeName(value)} to ${target}")
}

private func jsTypeName(value: JSValue): String {
    if (value.isUndefined()) { "undefined" } else if (value.isNull()) { "null" } else if (value.isBoolean()) {
        "boolean"
    } else if (value.isNumber()) { "number" } else if (value.isBigInt()) { "bigint" } else if (value.isString()) {
        "string"
    } else if (value.isSymbol()) { "symbol" } else if (value.isFunction()) { "function" } else if (value.isArray()) {
        "array"
    } else { "object" }
}

private func readNumber(value: JSValue, target: String): Float64 {
    if (!value.isNumber()) { throw mismatch(value, target) }
    value.toNumber()
}

/** A JS number that is an integer in `min..=max`. */
private func readInteger(value: JSValue, target: String, min: Float64, max: Float64): Float64 {
    let n = readNumber(value, target)
    if (n.isNaN() || n < min || n > max || n != trunc(n)) {
        throw ExternConversionException("ArkTS number does not fit ${target}")
    }
    n
}

/** A JS bigint in `min..=max`. */
private func readBigInt(value: JSValue, target: String, min: BigInt, max: BigInt): BigInt {
    if (!value.isBigInt()) { throw mismatch(value, target) }
    let n = value.toBigInt()
    if (n < min || n > max) {
        throw ExternConversionException("ArkTS bigint does not fit ${target}")
    }
    n
}

extend Unit <: ToJS & FromJS<Unit> {
    public func toJS(): JSValue { ArkTSRuntime.context.undefined().toJSValue() }
    public static func fromJS(_: JSValue): Unit {}
}

extend Bool <: ToJS & FromJS<Bool> {
    public func toJS(): JSValue { ArkTSRuntime.context.boolean(this).toJSValue() }
    public static func fromJS(value: JSValue): Bool {
        if (!value.isBoolean()) { throw mismatch(value, "Bool") }
        value.toBoolean()
    }
}

extend Int8 <: ToJS & FromJS<Int8> {
    public func toJS(): JSValue { jsNumber(Float64(this)) }
    public static func fromJS(value: JSValue): Int8 {
        Int8(readInteger(value, "Int8", Float64(Int8.Min), Float64(Int8.Max)))
    }
}

extend Int16 <: ToJS & FromJS<Int16> {
    public func toJS(): JSValue { jsNumber(Float64(this)) }
    public static func fromJS(value: JSValue): Int16 {
        Int16(readInteger(value, "Int16", Float64(Int16.Min), Float64(Int16.Max)))
    }
}

extend Int32 <: ToJS & FromJS<Int32> {
    public func toJS(): JSValue { jsNumber(Float64(this)) }
    public static func fromJS(value: JSValue): Int32 {
        Int32(readInteger(value, "Int32", Float64(Int32.Min), Float64(Int32.Max)))
    }
}

extend Int64 <: ToJS & FromJS<Int64> {
    public func toJS(): JSValue { ArkTSRuntime.context.bigint(this).toJSValue() }
    public static func fromJS(value: JSValue): Int64 {
        readBigInt(value, "Int64", BigInt(Int64.Min), BigInt(Int64.Max)).toInt64()
    }
}

extend UInt8 <: ToJS & FromJS<UInt8> {
    public func toJS(): JSValue { jsNumber(Float64(this)) }
    public static func fromJS(value: JSValue): UInt8 {
        UInt8(readInteger(value, "UInt8", 0.0, Float64(UInt8.Max)))
    }
}

extend UInt16 <: ToJS & FromJS<UInt16> {
    public func toJS(): JSValue { jsNumber(Float64(this)) }
    public static func fromJS(value: JSValue): UInt16 {
        UInt16(readInteger(value, "UInt16", 0.0, Float64(UInt16.Max)))
    }
}

extend UInt32 <: ToJS & FromJS<UInt32> {
    public func toJS(): JSValue { jsNumber(Float64(this)) }
    public static func fromJS(value: JSValue): UInt32 {
        UInt32(readInteger(value, "UInt32", 0.0, Float64(UInt32.Max)))
    }
}

extend UInt64 <: ToJS & FromJS<UInt64> {
    public func toJS(): JSValue { jsBigInt(BigInt(this)) }
    public static func fromJS(value: JSValue): UInt64 {
        readBigInt(value, "UInt64", BigInt(0), BigInt(UInt64.Max)).toUInt64()
    }
}

extend Float16 <: ToJS & FromJS<Float16> {
    public func toJS(): JSValue { jsNumber(Float64(this)) }
    public static func fromJS(value: JSValue): Float16 { Float16(readNumber(value, "Float16")) }
}

extend Float32 <: ToJS & FromJS<Float32> {
    public func toJS(): JSValue { jsNumber(Float64(this)) }
    public static func fromJS(value: JSValue): Float32 { Float32(readNumber(value, "Float32")) }
}

extend Float64 <: ToJS & FromJS<Float64> {
    public func toJS(): JSValue { jsNumber(this) }
    public static func fromJS(value: JSValue): Float64 { readNumber(value, "Float64") }
}

extend BigInt <: ToJS & FromJS<BigInt> {
    public func toJS(): JSValue { jsBigInt(this) }
    public static func fromJS(value: JSValue): BigInt {
        if (!value.isBigInt()) { throw mismatch(value, "BigInt") }
        value.toBigInt()
    }
}

extend String <: ToJS & FromJS<String> {
    public func toJS(): JSValue { ArkTSRuntime.context.string(this).toJSValue() }
    public static func fromJS(value: JSValue): String {
        if (!value.isString()) { throw mismatch(value, "String") }
        value.toString()
    }
}

/** `Some(x)` is `x`, `None` is `undefined`; `undefined` and `null` read as `None`. */
extend<T> Option<T> <: ToJS & FromJS<Option<T>> {
    public func toJS(): JSValue {
        match (this) {
            case Some(x) => ArkTSRuntime.toJSValue(x)
            case None => ArkTSRuntime.context.undefined().toJSValue()
        }
    }

    public static func fromJS(value: JSValue): Option<T> {
        if (value.isUndefined() || value.isNull()) {
            return None
        }
        Some(ArkTSRuntime.fromJSValue<T>(value))
    }
}

extend<T> Array<T> <: ToJS & FromJS<Array<T>> {
    public func toJS(): JSValue {
        let elements = Array<JSValue>(this.size) { i => ArkTSRuntime.toJSValue(this[i]) }
        ArkTSRuntime.context.array(elements).toJSValue()
    }

    public static func fromJS(value: JSValue): Array<T> {
        if (!value.isArray()) { throw mismatch(value, "Array") }
        let array = value.asArray()
        Array<T>(array.size) { i => ArkTSRuntime.fromJSValue<T>(array[i]) }
    }
}
