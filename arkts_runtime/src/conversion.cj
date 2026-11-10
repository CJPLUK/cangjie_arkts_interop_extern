package arkts_runtime

import std.math.trunc
import std.math.numeric.BigInt


/**
 * Cangjie types with an ArkTS mapping. `Extern<ArkTSRuntime>` cannot be extended, so it is
 * handled apart in `toJSValue` / `fromJSValue`; `Array` and `Option` convert their elements
 * through those, so unsupported element types fail only when an element is converted.
 */
interface ToJS {
    func toJS(): NativeJSValue
}

interface FromJS<T> {
    static func fromJS(value: NativeJSValue): T
}

/** Reaches `FromJS<T>` from code where `T` is unconstrained (`fromExtern<R>`). */
interface JSReader {
    func read(value: NativeJSValue): Any
}

class TypeTag<T> {}

extend<T> TypeTag<T> <: JSReader where T <: FromJS<T> {
    public func read(value: NativeJSValue): Any {
        T.fromJS(value)
    }
}

private func jsNumber(n: Float64): NativeJSValue {
    ArkTSRuntime.context.number(n).toJSValue()
}

private func jsBigInt(n: BigInt): NativeJSValue {
    ArkTSRuntime.context.bigint(n).toJSValue()
}

private func mismatch(value: NativeJSValue, target: String): ExternConversionException {
    ExternConversionException("Cannot convert ArkTS ${jsTypeName(value)} to ${target}")
}

private func jsTypeName(value: NativeJSValue): String {
    let t = value.typeof()
    match {
        case t == JSType.OBJECT && value.isArray() => "array"
        case t == JSType.OBJECT => "object"
        case t == JSType.UNDEFINED => "undefined"
        case t == JSType.NULL => "null"
        case t == JSType.BOOLEAN => "boolean"
        case t == JSType.NUMBER => "number"
        case t == JSType.BIGINT => "bigint"
        case t == JSType.STRING => "string"
        case t == JSType.SYMBOL => "symbol"
        case t == JSType.FUNCTION => "function"
        case t == JSType.EXTERNAL => "external"
        case _ => t.toString()
    }
}

private func readNumber(value: NativeJSValue, target: String): Float64 {
    if (!value.isNumber()) { throw mismatch(value, target) }
    value.toNumber()
}

/** A JS number that is an integer in `min..=max`. */
private func readInteger(value: NativeJSValue, target: String, min: Float64, max: Float64): Float64 {
    let n = readNumber(value, target)
    if (n.isNaN() || n < min || n > max || n != trunc(n)) {
        throw ExternConversionException("ArkTS number does not fit ${target}")
    }
    n
}

/** A JS bigint in `min..=max`. */
private func readBigInt(value: NativeJSValue, target: String, min: BigInt, max: BigInt): BigInt {
    if (!value.isBigInt()) { throw mismatch(value, target) }
    let n = value.toBigInt()
    if (n < min || n > max) {
        throw ExternConversionException("ArkTS bigint does not fit ${target}")
    }
    n
}

extend Unit <: ToJS & FromJS<Unit> {
    public func toJS(): NativeJSValue { ArkTSRuntime.undefinedValue }
    public static func fromJS(_: NativeJSValue): Unit {}
}

extend Bool <: ToJS & FromJS<Bool> {
    public func toJS(): NativeJSValue { ArkTSRuntime.context.boolean(this).toJSValue() }
    public static func fromJS(value: NativeJSValue): Bool {
        if (!value.isBoolean()) { throw mismatch(value, "Bool") }
        value.toBoolean()
    }
}

extend Int8 <: ToJS & FromJS<Int8> {
    public func toJS(): NativeJSValue { jsNumber(Float64(this)) }
    public static func fromJS(value: NativeJSValue): Int8 {
        Int8(readInteger(value, "Int8", Float64(Int8.Min), Float64(Int8.Max)))
    }
}

extend Int16 <: ToJS & FromJS<Int16> {
    public func toJS(): NativeJSValue { jsNumber(Float64(this)) }
    public static func fromJS(value: NativeJSValue): Int16 {
        Int16(readInteger(value, "Int16", Float64(Int16.Min), Float64(Int16.Max)))
    }
}

extend Int32 <: ToJS & FromJS<Int32> {
    public func toJS(): NativeJSValue { jsNumber(Float64(this)) }
    public static func fromJS(value: NativeJSValue): Int32 {
        Int32(readInteger(value, "Int32", Float64(Int32.Min), Float64(Int32.Max)))
    }
}

extend Int64 <: ToJS & FromJS<Int64> {
    public func toJS(): NativeJSValue { ArkTSRuntime.context.bigint(this).toJSValue() }
    public static func fromJS(value: NativeJSValue): Int64 {
        readBigInt(value, "Int64", BigInt(Int64.Min), BigInt(Int64.Max)).toInt64()
    }
}

extend UInt8 <: ToJS & FromJS<UInt8> {
    public func toJS(): NativeJSValue { jsNumber(Float64(this)) }
    public static func fromJS(value: NativeJSValue): UInt8 {
        UInt8(readInteger(value, "UInt8", 0.0, Float64(UInt8.Max)))
    }
}

extend UInt16 <: ToJS & FromJS<UInt16> {
    public func toJS(): NativeJSValue { jsNumber(Float64(this)) }
    public static func fromJS(value: NativeJSValue): UInt16 {
        UInt16(readInteger(value, "UInt16", 0.0, Float64(UInt16.Max)))
    }
}

extend UInt32 <: ToJS & FromJS<UInt32> {
    public func toJS(): NativeJSValue { jsNumber(Float64(this)) }
    public static func fromJS(value: NativeJSValue): UInt32 {
        UInt32(readInteger(value, "UInt32", 0.0, Float64(UInt32.Max)))
    }
}

extend UInt64 <: ToJS & FromJS<UInt64> {
    public func toJS(): NativeJSValue { jsBigInt(BigInt(this)) }
    public static func fromJS(value: NativeJSValue): UInt64 {
        readBigInt(value, "UInt64", BigInt(0), BigInt(UInt64.Max)).toUInt64()
    }
}

extend Float16 <: ToJS & FromJS<Float16> {
    public func toJS(): NativeJSValue { jsNumber(Float64(this)) }
    public static func fromJS(value: NativeJSValue): Float16 { Float16(readNumber(value, "Float16")) }
}

extend Float32 <: ToJS & FromJS<Float32> {
    public func toJS(): NativeJSValue { jsNumber(Float64(this)) }
    public static func fromJS(value: NativeJSValue): Float32 { Float32(readNumber(value, "Float32")) }
}

extend Float64 <: ToJS & FromJS<Float64> {
    public func toJS(): NativeJSValue { jsNumber(this) }
    public static func fromJS(value: NativeJSValue): Float64 { readNumber(value, "Float64") }
}

extend BigInt <: ToJS & FromJS<BigInt> {
    public func toJS(): NativeJSValue { jsBigInt(this) }
    public static func fromJS(value: NativeJSValue): BigInt {
        if (!value.isBigInt()) { throw mismatch(value, "BigInt") }
        value.toBigInt()
    }
}

extend String <: ToJS & FromJS<String> {
    public func toJS(): NativeJSValue { ArkTSRuntime.context.string(this).toJSValue() }
    public static func fromJS(value: NativeJSValue): String {
        if (!value.isString()) { throw mismatch(value, "String") }
        value.toString()
    }
}

/** `Some(x)` is `x`, `None` is `undefined`; `undefined` and `null` read as `None`. */
extend<T> Option<T> <: ToJS & FromJS<Option<T>> {
    public func toJS(): NativeJSValue {
        match (this) {
            case Some(x) => ArkTSRuntime.toJSValue(x)
            case None => ArkTSRuntime.undefinedValue
        }
    }

    public static func fromJS(value: NativeJSValue): Option<T> {
        let t = value.typeof()
        match {
            case t == JSType.UNDEFINED || t == JSType.NULL => None
            case _ => Some(ArkTSRuntime.fromJSValue<T>(value))
        }
    }
}

extend<T> Array<T> <: ToJS & FromJS<Array<T>> {
    public func toJS(): NativeJSValue {
        if (let Some(numbers) <- (this as Array<Float64>)) {
            return ArkTSRuntime.context.numberArray(numbers)
        }
        let elements = Array<NativeJSValue>(this.size) { i => ArkTSRuntime.toJSValue(this[i]) }
        ArkTSRuntime.context.array(elements).toJSValue()
    }

    public static func fromJS(value: NativeJSValue): Array<T> {
        if (!value.isArray()) { throw mismatch(value, "Array") }
        match (None<T>) {
            case _: Option<Float64> => return (value.toNumberArray() as Array<T>).getOrThrow()
            case _ => ()
        }
        let array = value.asArray()
        Array<T>(array.size) { i => ArkTSRuntime.fromJSValue<T>(array[i]) }
    }
}
