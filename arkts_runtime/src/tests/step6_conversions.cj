package arkts_runtime.tests

import std.math.numeric.BigInt
import ohos.ark_interop.*
import arkts_runtime.*

func step6Scenarios(): Array<(String, Scenario)> {
    [
        ("step6.toExternTypes", { _, f => toExternTypes(f) }),
        ("step6.fromExternTypes", { _, f => fromExternTypes(f) }),
        ("step6.roundTrip", { _, _ => roundTrips() }),
        ("step6.largeValues", { _, f => largeValues(f) }),
        ("step6.externInputs", { _, f => externInputs(f) }),
        ("step6.conversionFailures", { _, f => conversionFailures(f) }),
        ("step6.implicitConversion", { _, f => implicitConversion(f) })
    ]
}

func step6OffThreadScenarios(): Array<(String, OffThreadScenario)> {
    [("step6.conversionsFromOtherThread", conversionsFromOtherThread)]
}

func from<T>(e: E): T {
    ArkTSRuntime.fromExtern<T>(e)
}

func to<T>(value: T): E {
    ArkTSRuntime.toExtern(value)
}

/**
 * fixtures: sink object, Rectangle. Stores one converted value per mapping row in the sink;
 * ArkTS checks the `typeof` and value of each.
 */
func toExternTypes(fixtures: Array<JSValue>): String {
    let sink = ext(fixtures, 0)
    let rect = ext(fixtures, 1)
    let rows: Array<(String, E)> = [
        ("unit", to(())),
        ("bool", to(true)),
        ("int8Min", to(Int8.Min)),
        ("int8Max", to(Int8.Max)),
        ("int16", to(Int16.Min)),
        ("int32", to(Int32.Max)),
        ("uint8", to(UInt8.Max)),
        ("uint16", to(UInt16.Max)),
        ("uint32Max", to(UInt32.Max)),
        ("int64Min", to(Int64.Min)),
        ("int64Max", to(Int64.Max)),
        ("uint64Max", to(UInt64.Max)),
        ("float16", to(Float16(0.1))),
        ("float32", to(Float32(1.1))),
        ("float64", to(0.1)),
        ("nan", to(Float64.NaN)),
        ("inf", to(Float64.Inf)),
        ("negInf", to(-Float64.Inf)),
        ("negZero", to(-0.0)),
        ("bigint", to(BigInt("123456789012345678901234567890"))),
        ("emptyString", to("")),
        ("text", to("héllo 日本 😀")),
        ("some", to(Some(Int32(7)))),
        ("none", to(None<Int32>)),
        ("emptyArray", to(Array<Int32>())),
        ("nested", to([[Int32(1)], [Int32(2), Int32(3)]])),
        ("int64Array", to([1, 2])),
        ("optionArray", to([Some(1.5), None<Float64>])),
        ("mixed", to([to("a"), rect, to(1.5), to(())]))
    ]
    for ((name, value) in rows) {
        sink[name] = value
    }
    ""
}

/** fixtures: Values. Each field read as its Cangjie type. */
func fromExternTypes(fixtures: Array<JSValue>): String {
    let v = ext(fixtures, 0)
    let negZero = from<Float64>(v.negZero)
    let mixed = from<Array<E>>(v.mixed)
    firstFailure([
        expectEqual("Bool", from<Bool>(v.bool), true),
        expectEqual("Int8.Min", from<Int8>(v.int8Min), Int8.Min),
        expectEqual("Int8.Max", from<Int8>(v.int8Max), Int8.Max),
        expectEqual("Int16", from<Int16>(v.int8Min), -128),
        expectEqual("Int32", from<Int32>(v.int8Max), 127),
        expectEqual("UInt8", from<UInt8>(v.int8Max), 127),
        expectEqual("UInt16", from<UInt16>(v.int8Max), 127),
        expectEqual("UInt32.Max", from<UInt32>(v.uint32Max), UInt32.Max),
        expectEqual("Int64.Min", from<Int64>(v.int64Min), Int64.Min),
        expectEqual("Int64.Max", from<Int64>(v.int64Max), Int64.Max),
        expectEqual("UInt64.Max", from<UInt64>(v.uint64Max), UInt64.Max),
        expectEqual("BigInt", from<BigInt>(v.big), BigInt("123456789012345678901234567890")),
        expectEqual("Float64", from<Float64>(v.float), 0.1),
        expectEqual("Float32", from<Float32>(v.float), Float32(0.1)),
        expectEqual("Float16", from<Float16>(v.float), Float16(0.1)),
        expectEqual("Float16 precision", Float64(from<Float16>(v.float)), 0.0999755859375),
        expectEqual("NaN", from<Float64>(v.nan).isNaN(), true),
        expectEqual("Infinity", from<Float64>(v.inf), Float64.Inf),
        expectEqual("-Infinity", from<Float64>(v.negInf), -Float64.Inf),
        expectEqual("-0", negZero == 0.0 && 1.0 / negZero < 0.0, true),
        expectEqual("empty string", from<String>(v.empty), ""),
        expectEqual("non-ASCII string", from<String>(v.text), "héllo 日本 😀"),
        expectEqual("Unit", from<Unit>(v.obj) == (), true),
        expectEqual("Option from undefined", from<?Float64>(v.undef), None),
        expectEqual("Option from null", from<?Float64>(v.nul), None),
        expectEqual("Option from number", from<?Float64>(v.float), Some(0.1)),
        expectEqual("nested array", from<Array<Array<Float64>>>(v.nested), [[1.0, 2.0], [], [3.0]]),
        expectEqual("array of options", from<Array<?Float64>>(v.optional), [Some(1.0), None, Some(3.0)]),
        expectEqual("Array<Extern> size", mixed.size, 4),
        expectEqual("Array<Extern>[0]", from<String>(mixed[0]), "a"),
        expectEqual("Array<Extern>[3] is null", unwrap(mixed[3]).isNull(), true),
        expectEqual("Extern identity", unwrap(from<E>(v.obj)).strictEqual(unwrap(v.obj)), true)
    ])
}

func roundTrip<T>(value: T): String where T <: Equatable<T> & ToString {
    expectEqual("round trip of ${value}", from<T>(to(value)), value)
}

func roundTrips(): String {
    let negZero = from<Float64>(to(-0.0))
    firstFailure([
        roundTrip(true),
        roundTrip(Int8.Min),
        roundTrip(Int8.Max),
        roundTrip(Int16.Min),
        roundTrip(Int32.Max),
        roundTrip(UInt8.Max),
        roundTrip(UInt16.Max),
        roundTrip(UInt32.Max),
        roundTrip(Int64.Min),
        roundTrip(Int64.Max),
        roundTrip(UInt64.Min),
        roundTrip(UInt64.Max),
        roundTrip(Float16(0.1)),
        roundTrip(Float32(1.1)),
        roundTrip(0.1),
        roundTrip(Float64.Inf),
        roundTrip(BigInt("-123456789012345678901234567890")),
        roundTrip(""),
        roundTrip("héllo 日本 😀"),
        roundTrip(Some(5)),
        roundTrip(None<Int64>),
        roundTrip([[1, 2], [3]]),
        roundTrip(Array<String>()),
        expectEqual("round trip of NaN", from<Float64>(to(Float64.NaN)).isNaN(), true),
        expectEqual("round trip of -0", 1.0 / negZero < 0.0, true),
        expectEqual("round trip of ()", from<Unit>(to(())) == (), true)
    ])
}

/** fixtures: sink. A 1 MB string and a 100 000-element array; ArkTS checks the stored ones. */
func largeValues(fixtures: Array<JSValue>): String {
    let sink = ext(fixtures, 0)
    let text = String(Array<Rune>(1 << 20, repeat: r'é'))
    let numbers = Array<Int32>(100000) { i => Int32(i) }
    sink.longString = text
    sink.bigArray = to(numbers)
    let externs = from<Array<E>>(sink.bigArray)
    firstFailure([
        expectEqual("long string", from<String>(sink.longString) == text, true),
        expectEqual("big array", from<Array<Int32>>(sink.bigArray) == numbers, true),
        expectEqual("Array<Extern> size", externs.size, 100000),
        expectEqual("Array<Extern> last", from<Int32>(externs[99999]), 99999)
    ])
}

/** fixtures: Target. An unevaluated tree is evaluated by `toExtern` and `fromExtern`. */
func externInputs(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    let tree = member(member(member(e, "a"), "b"), "c")
    firstFailure([
        expectEqual("fromExtern of a tree", from<Float64>(tree), 42.0),
        expectEqual("toExtern of a tree", from<Float64>(to(tree)), 42.0),
        expectEqual("toExtern of a tree is a payload", ArkTSRuntime.handleKind(to(tree)), "Imm"),
        expectEqual("tree inside an array", from<Array<Float64>>(to([tree, member(e, "num")])), [42.0, 1.5])
    ])
}

/** fixtures: Values. */
func conversionFailures(fixtures: Array<JSValue>): String {
    let v = ext(fixtures, 0)
    func fails(what: String, fragment: String, block: () -> Any): String {
        expectThrows<ExternConversionException>(what, fragment, block)
    }
    firstFailure([
        fails("toExtern(Rune)", "Unsupported conversion to ArkTS", { => to(r'a') }),
        fails("toExtern([Rune])", "Unsupported conversion to ArkTS", { => to([r'a']) }),
        fails("toExtern(Some(Rune))", "Unsupported conversion to ArkTS", { => to(Some(r'a')) }),
        fails("fromExtern<Rune>", "Unsupported conversion from ArkTS", { => from<Rune>(v.text) }),
        fails("string as Float64", "Cannot convert ArkTS string to Float64", { => from<Float64>(v.five) }),
        fails("object as Bool", "Cannot convert ArkTS object to Bool", { => from<Bool>(v.obj) }),
        fails("undefined as String", "Cannot convert ArkTS undefined to String", { => from<String>(v.undef) }),
        fails("number as Int64", "Cannot convert ArkTS number to Int64", { => from<Int64>(v.float) }),
        fails("bigint as Int32", "Cannot convert ArkTS bigint to Int32", { => from<Int32>(v.int64Max) }),
        fails("300 as Int8", "ArkTS number does not fit Int8", { => from<Int8>(v.n300) }),
        fails("-128 as UInt8", "ArkTS number does not fit UInt8", { => from<UInt8>(v.int8Min) }),
        fails("0.1 as Int32", "ArkTS number does not fit Int32", { => from<Int32>(v.float) }),
        fails("NaN as Int32", "ArkTS number does not fit Int32", { => from<Int32>(v.nan) }),
        fails("UInt64.Max as Int64", "ArkTS bigint does not fit Int64", { => from<Int64>(v.uint64Max) }),
        fails("Int64.Min as UInt64", "ArkTS bigint does not fit UInt64", { => from<UInt64>(v.int64Min) }),
        fails("object as Array", "Cannot convert ArkTS object to Array", { => from<Array<Float64>>(v.obj) }),
        fails("mixed as Array<Float64>", "Cannot convert ArkTS string to Float64",
            { => from<Array<Float64>>(v.mixed) }),
        fails("foreign payload", "Extern payload was not produced by ArkTSRuntime", { => from<Int64>(payload()) })
    ])
}

/**
 * fixtures: sink. Through the compiler: a Cangjie value where an `Extern` is expected becomes
 * `toExtern`. ArkTS checks implicit === 42n and implicitArray is [1n, "a"].
 */
func implicitConversion(fixtures: Array<JSValue>): String {
    let sink = ext(fixtures, 0)
    let v: E = 42
    let items: Array<E> = [1, "a"]
    sink.implicit = v
    sink.implicitArray = items
    expectEqual("Int64 literal", from<Int64>(v), 42)
}

/** `toExtern` and `fromExtern` from a spawned thread. */
func conversionsFromOtherThread(): String {
    let numbers = to([1.5, 2.5])
    firstFailure([
        expectEqual("array", from<Array<Float64>>(numbers), [1.5, 2.5]),
        expectEqual("Int64.Max", from<Int64>(to(Int64.Max)), Int64.Max),
        expectEqual("Unit", from<Unit>(numbers) == (), true)
    ])
}
