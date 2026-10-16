package arkts_runtime.tests

import std.math.numeric.BigInt
import ohos.ark_interop.*
import arkts_runtime.*

// Fixtures are classes from fixtures.ets; ArkTS checks the effects after each scenario.
@When[bundle == "com.example.testArkTSForeignRuntime"]
func step5Scenarios(): Array<(String, Scenario)> {
    [
        ("step5.memberRead", { _, f => memberRead(f) }),
        ("step5.primitiveReceivers", { _, f => primitiveReceivers(f) }),
        ("step5.memberUpdate", { _, f => memberUpdate(f) }),
        ("step5.memberOfUndefinedOrNull", { _, f => memberOfUndefinedOrNull(f) }),
        ("step5.methodCallThis", { _, f => methodCallThis(f) }),
        ("step5.freeCallThisUndefined", { _, f => freeCallThisUndefined(f) }),
        ("step5.indexCallThis", indexCallThis),
        ("step5.receiverEvaluatedOnce", { _, f => receiverEvaluatedOnce(f) }),
        ("step5.argumentTypes", { _, f => argumentTypes(f) }),
        ("step5.callNonFunction", { _, f => callNonFunction(f) }),
        ("step5.indexReadWrite", indexReadWrite),
        ("step5.indexBoundaries", { c, f => indexBoundaries(c, f) }),
        ("step5.nonArrayIndexing", { _, f => nonArrayIndexing(f) }),
        ("step5.unsupportedIndex", { _, f => unsupportedIndex(f) }),
        ("step5.indexWriteOrder", { _, f => indexWriteOrder(f) }),
        ("step5.numberKeys", { c, f => numberKeys(c, f) }),
        ("step5.compoundAssignmentUnsupported", { _, f => compoundAssignmentUnsupported(f) }),
        ("step5.variableCompoundIsMethodCall", { _, f => variableCompoundIsMethodCall(f) }),
        ("step5.evalPayloadUnchanged", { _, f => evalPayloadUnchanged(f) }),
        ("step5.derivedConstructor", { _, f => derivedConstructor(f) }),
        ("step5.longChainLoop", { _, f => longChainLoop(f) })
    ]
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func step5OffThreadScenarios(): Array<(String, OffThreadScenario)> {
    [("step5.evalFromOtherThread", evalFromOtherThread)]
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
type E = Extern<ArkTSRuntime>

/** fixtures[index] as an evaluated Extern. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func ext(fixtures: Array<JSValue>, index: Int64): E {
    ArkTSRuntime.retain(fixture(fixtures, index))
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func number(e: E): Float64 { unwrap(e).toNumber() }

@When[bundle == "com.example.testArkTSForeignRuntime"]
func text(e: E): String { unwrap(e).toString() }

@When[bundle == "com.example.testArkTSForeignRuntime"]
func member(target: E, field: String): E {
    E.ExternMemberAccess(target, field)
}

/** fixtures: Target. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func memberRead(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    firstFailure([
        expectEqual("e.num", number(e.num), 1.5),
        expectEqual("e.str", text(e.str), "héllo"),
        expectEqual("e.a.b.c", number(e.a.b.c), 42.0),
        expectEqual("e.missing is undefined", unwrap(e.missing).isUndefined(), true)
    ])
}

/**
 * fixtures: Target. As in `ark_interop`, members exist only on objects and integer indices only
 * on arrays: on primitives both throw. ArkTS checks str is unchanged.
 */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func primitiveReceivers(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    let notObject = "The ArkTS data types do not match, expect: object, given: "
    firstFailure([
        expectThrows<ExternMemberAccessException>("e.str.length", notObject + "string", { => e.str.length }),
        expectThrows<ExternMemberAccessException>("e.str.toUpperCase()", notObject + "string",
            { => e.str.toUpperCase() }),
        expectThrows<ExternMemberAccessException>("e.num.toFixed(2)", notObject + "number", { => e.num.toFixed(2.0) }),
        expectThrows<ExternMemberAccessException>("e.big.toString()", notObject, { => e.big.toString() }),
        expectThrows<ExternMemberAccessException>("e.str.x = 1", notObject + "string", { => e.str.x = 1.0 }),
        expectThrows<ExternIndexedAccessException>("e.str[1]", "expect: array, given: string", { => e.str[1] }),
        expectThrows<ExternIndexedAccessException>("e.str[0] = \"x\"", "expect: array, given: string",
            { => e.str[0] = "x" })
    ])
}

/** fixtures: Target. ArkTS checks num == 7, a.b.c == 99, str == "set". */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func memberUpdate(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    e.num = 7.0
    e.a.b.c = 99.0
    e.str = "set"
    firstFailure([
        expectEqual("e.num", number(e.num), 7.0),
        expectEqual("e.a.b.c", number(e.a.b.c), 99.0),
        expectEqual("e.str", text(e.str), "set")
    ])
}

/** fixtures: Target. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func memberOfUndefinedOrNull(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    let notObject = "The ArkTS data types do not match, expect: object, given: "
    firstFailure([
        expectThrows<ExternMemberAccessException>("e.nothing.x", notObject + "undefined", { => e.nothing.x }),
        expectThrows<ExternMemberAccessException>("e.nul.x", notObject + "null", { => e.nul.x }),
        expectThrows<ExternMemberAccessException>("e.nothing.x = 1", notObject + "undefined",
            { => e.nothing.x = 1.0 }),
        expectThrows<ExternMemberAccessException>("e.nul.m()", notObject + "null", { => e.nul.m() })
    ])
}

/** fixtures: Target, callLog. ArkTS checks callLog.self === target. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func methodCallThis(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    let log = ext(fixtures, 1)
    let result = e.record(1.0, 2.0)
    firstFailure([
        expectEqual("return value", number(result), 2.0),
        expectEqual("this === target", unwrap(log.self).strictEqual(fixture(fixtures, 0)), true)
    ])
}

/** fixtures: Target, callLog. ArkTS checks callLog.self === undefined. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func freeCallThisUndefined(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    let log = ext(fixtures, 1)
    let f = e.record
    f(1.0)
    firstFailure([
        expectEqual("calls", number(log.calls), 1.0),
        expectEqual("this is undefined", unwrap(log.self).isUndefined(), true)
    ])
}

/**
 * fixtures: Target, callLog. `e["record"]()` has `this` = target; `e.list[0]()`, with the
 * method stored in the array, has `this` = the array. ArkTS checks the second.
 */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func indexCallThis(context: JSContext, fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    let log = ext(fixtures, 1)
    e["record"](1.0)
    let byName = unwrap(log.self).strictEqual(fixture(fixtures, 0))
    fixture(fixtures, 0).asObject()["list"] = context.array([fixture(fixtures, 0).getProperty("record")]).toJSValue()
    e.list[0](1.0)
    firstFailure([
        expectEqual("e[\"record\"](): this === target", byName, true),
        expectEqual("e.list[0](): this === e.list", unwrap(log.self).strictEqual(unwrap(e.list)), true)
    ])
}

/** fixtures: CountingHolder around a Target. ArkTS checks the getter ran once. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func receiverEvaluatedOnce(fixtures: Array<JSValue>): String {
    let h = ext(fixtures, 0)
    expectEqual("return value", number(h.target.record(1.0)), 1.0)
}

/**
 * fixtures: Target, callLog, Rectangle. ArkTS checks the `typeof` of each argument:
 * bigint, number, boolean, string, bigint, number, object.
 */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func argumentTypes(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    let rect = ext(fixtures, 2)
    let count = e.record(1, 2.5, true, "s", BigInt(3), Int32(4), rect)
    firstFailure([
        expectEqual("argument count", number(count), 7.0),
        expectThrows<ExternConversionException>("Rune argument", "Unsupported conversion to ArkTS",
            { => e.record(r'a') })
    ])
}

/** fixtures: Target. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func callNonFunction(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    let v = e.num
    firstFailure([
        expectThrows<ExternFunctionAccessException>("e.str()", "ArkTS 'str' is not a function", { => e.str(1.0) }),
        expectThrows<ExternFunctionAccessException>("e.missing()", "ArkTS 'missing' is not a function",
            { => e.missing() }),
        expectThrows<ExternFunctionAccessException>("e.items[0]()", "ArkTS indexed value is not a function",
            { => e.items[0]() }),
        expectThrows<ExternFunctionAccessException>("v()", "ArkTS value is not a function", { => v() })
    ])
}

/**
 * fixtures: Target. `Int64` is an element position; `String`, `Utf16String`, `Float64` and
 * `Extern` numbers, strings and symbols are property keys, which on an array reach its elements.
 * ArkTS checks items == [55, 77, 99] (length 3), str == "via string", num == 4.
 */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func indexReadWrite(context: JSContext, fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    let symbol = ArkTSRuntime.retain(context.symbol(description: "k").toJSValue())
    let readChecks = [
        expectEqual("e.items[1] (Int64)", number(e.items[1]), 20.0),
        expectEqual("e.items[0.0] (Float64 key)", number(e.items[0.0]), 10.0),
        expectEqual("e[\"num\"] (String)", number(e["num"]), 1.5),
        expectEqual("e[Utf16String(\"num\")]", number(e[Utf16String("num")]), 1.5),
        expectEqual("e[e.keyName] (Extern string)", number(e[e.keyName]), 1.5),
        expectEqual("e.items[e.one] (Extern number key)", number(e.items[e.one]), 20.0)
    ]
    e.items[2] = 99.0
    e.items[1.0] = 77.0
    e.items[e.zero] = 55.0
    e["str"] = "via string"
    e[e.keyName] = 4.0
    e[e.half] = "fraction"
    e[0.25] = "quarter"
    e[symbol] = 8.0
    firstFailure([
        firstFailure(readChecks),
        expectEqual("e[e.half] (Extern fractional number)", text(e[e.half]), "fraction"),
        expectEqual("property \"1.5\"", fixture(fixtures, 0).getProperty("1.5").toString(), "fraction"),
        expectEqual("property \"0.25\" (Float64 key)", fixture(fixtures, 0).getProperty("0.25").toString(), "quarter"),
        expectEqual("e[symbol] (Extern symbol)", number(e[symbol]), 8.0),
        expectThrows<ExternIndexedAccessException>("e[0] on an object (not an array)", "expect: array, given: object",
            { => e[0] = "zero" }),
        expectThrows<ExternIndexedAccessException>("e.items[-1]", "out of range", { => e.items[-1] = 5.0 })
    ])
}

/**
 * fixtures: [10, 20, 30]. `ark_interop`'s rules for `Int64` positions: reads need a position in
 * 0..length-1; writes at or past `length` grow the array (with holes), at -1 throw, and at
 * 4294967295 succeed but empty the array (`length` 0). An `Extern` number is a key, so it reads
 * `undefined` past the end. ArkTS checks items.length == 0.
 */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func indexBoundaries(context: JSContext, fixtures: Array<JSValue>): String {
    let a = ext(fixtures, 0)
    func num(n: Float64): E { ArkTSRuntime.retain(context.number(n).toJSValue()) }
    let reads = [
        expectThrows<ExternIndexedAccessException>("a[3] (just past the end)", "allowed: [0, 3), given: 3",
            { => a[3] }),
        expectThrows<ExternIndexedAccessException>("a[-1]", "given: -1", { => a[-1] }),
        expectEqual("a[Extern 5] (a key: undefined past the end)", ArkTSRuntime.isUndefined(a[num(5.0)]), true)
    ]
    func outcome(write: () -> Unit): String {
        try {
            write()
            "ok, length ${Int64(number(a.length))}"
        } catch (e: ExternIndexedAccessException) {
            "throws ${e.message}"
        }
    }
    a[2] = 99.0
    let afterWrite = expectEqual("a[2] after a write", number(a[2]), 99.0)
    let writes = [
        outcome({ => a[3] = 1.0 }),
        outcome({ => a[6] = 2.0 }),
        outcome({ => a[-1] = 2.0 }),
        outcome({ => a[4294967295] = 7.0 })
    ]
    firstFailure([
        firstFailure(reads),
        afterWrite,
        expectEqual("writes at 3, 6, -1, 4294967295", String.join(writes, delimiter: " | "),
            "ok, length 4 | ok, length 7 | throws The accessing index is out of range, allowed: [0, 7), given: -1 | ok, length 0")
    ])
}

/**
 * fixtures: Map {0 => "zero"}, Uint8Array [1, 2, 3, 4]. As in `ark_interop`, `Int64` indices
 * work only on arrays: on a Map or a typed array they throw and change nothing; members, string
 * keys and `Extern` number keys still work. ArkTS checks the Map has one entry and the bytes are
 * [1, 2, 3, 4].
 */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func nonArrayIndexing(fixtures: Array<JSValue>): String {
    let m = ext(fixtures, 0)
    let u8 = ext(fixtures, 1)
    let notArray = "expect: array, given: object"
    firstFailure([
        expectThrows<ExternIndexedAccessException>("m[0]", notArray, { => m[0] }),
        expectThrows<ExternIndexedAccessException>("u8[1]", notArray, { => u8[1] }),
        expectThrows<ExternIndexedAccessException>("u8[1] = 300", notArray, { => u8[1] = 300.0 }),
        expectEqual("m.get(0)", text(m.get(0.0)), "zero"),
        expectEqual("u8[\"1\"] (string key)", number(u8["1"]), 2.0),
        expectEqual("u8[Extern 1] (number key)", number(u8[ArkTSRuntime.toExtern(1.0)]), 2.0),
        expectEqual("u8.length", number(u8.length), 4.0)
    ])
}

/** fixtures: Target. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func unsupportedIndex(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    firstFailure([
        expectThrows<ExternIndexedAccessException>("e.items[Int32(0)]", "Unsupported ArkTS index type",
            { => e.items[Int32(0)] }),
        expectThrows<ExternIndexedAccessException>("e.items[UInt8(0)]", "Unsupported ArkTS index type",
            { => e.items[UInt8(0)] }),
        expectThrows<ExternIndexedAccessException>("e[e.flag] (Extern boolean)", "Unsupported ArkTS index type",
            { => e[e.flag] }),
        expectThrows<ExternIndexedAccessException>("e.nothing[0]", "expect: array, given: undefined",
            { => e.nothing[0] }),
        expectThrows<ExternIndexedAccessException>("e.nul[0] = 1", "expect: array, given: null",
            { => e.nul[0] = 1.0 }),
        expectThrows<ExternIndexedAccessException>("e.nothing[\"k\"]", "expect: object, given: undefined",
            { => e.nothing["k"] })
    ])
}

/** fixtures: OrderLog. ArkTS checks the getter order target, index, value and stored[1] == 5. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func indexWriteOrder(fixtures: Array<JSValue>): String {
    let l = ext(fixtures, 0)
    l.target[l.index] = l.value
    ""
}

/**
 * fixtures: Target. An `Extern` number is a property key, named by the engine (JS `String(...)`,
 * not Cangjie's "1.500000"), integral or not: -0 is "0".
 */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func numberKeys(context: JSContext, fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    func num(n: Float64): E { ArkTSRuntime.retain(context.number(n).toJSValue()) }
    e[num(1e21)] = "huge"
    e[num(0.25)] = "quarter"
    e[num(-0.0)] = "zero"
    firstFailure([
        expectEqual("key for Extern 1e21", fixture(fixtures, 0).getProperty("1e+21").toString(), "huge"),
        expectEqual("key for Extern 0.25", fixture(fixtures, 0).getProperty("0.25").toString(), "quarter"),
        expectEqual("key for Extern -0", fixture(fixtures, 0).getProperty("0").toString(), "zero")
    ])
}

/** fixtures: Target. Every compound assignment throws without touching the target. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func compoundAssignmentUnsupported(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    let message = "Compound assignment not supported"
    firstFailure([
        expectThrows<ExternCompoundAssignmentException>("e.num += 1", message, { => e.num += 1.0 }),
        expectThrows<ExternCompoundAssignmentException>("e.items[0] += 1", message, { => e.items[0] += 1.0 }),
        expectThrows<ExternCompoundAssignmentException>("e.flag &&= \"yes\"", message,
            { => ArkTSRuntime.eval(E.ExternCompoundAssignment(member(e, "flag"), "&&", "yes")) }),
        expectEqual("e.num unchanged", number(e.num), 1.5),
        expectEqual("e.items[0] unchanged", number(e.items[0]), 10.0)
    ])
}

/**
 * `x += 1` on an Extern variable is desugared by the compiler to `x = x.+(1)`: reading the
 * member `+` of a number fails.
 */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func variableCompoundIsMethodCall(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    var x = e.num
    try {
        x += 1
        "x += 1: expected an exception"
    } catch (ex: ExternMemberAccessException) {
        expectEqual("x += 1", ex.message, "The ArkTS data types do not match, expect: object, given: number.")
    }
}

/** fixtures: Rectangle. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func evalPayloadUnchanged(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    expectEqual("eval(payload) === fixture", unwrap(ArkTSRuntime.eval(e)).strictEqual(fixture(fixtures, 0)), true)
}

/** fixtures: Target. `ExternSequence` is derived: `eval` and `evalTree` hand it to `evalDerived`. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func derivedConstructor(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    let topLevel = ArkTSRuntime.eval(E.ExternSequence(E.ExternMemberUpdate(e, "num", 2.0), member(e, "num")))
    let nested = ArkTSRuntime.eval(member(E.ExternSequence(E.ExternMemberUpdate(e, "zero", 3.0), member(e, "a")), "b"))
    firstFailure([
        expectEqual("top level: second result", number(topLevel), 2.0),
        expectEqual("nested: first ran", number(e.zero), 3.0),
        expectEqual("nested: result is e.a.b", unwrap(nested).strictEqual(unwrap(e.a.b)), true)
    ])
}

/** fixtures: Target. Intermediates stay local to each evaluation's scope. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func longChainLoop(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    for (i in 0..100000) {
        let c = e.a.b.c
        if (i % 10000 == 0 && number(c) != 42.0) {
            return "iteration ${i}: e.a.b.c is ${number(c)}"
        }
    }
    ""
}

/** Every operation dispatched from a spawned thread through the public `eval`. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func evalFromOtherThread(): String {
    let o = ArkTSRuntime.run { ArkTSRuntime.retain(ArkTSRuntime.context.object().toJSValue()) }
    o.x = 1.5
    o.items = [1.0, 2.0]
    o.items[1] = 2.5
    let (x, item) = ArkTSRuntime.run { (number(o.x), number(o.items[1])) }
    firstFailure([
        expectEqual("o.x", x, 1.5),
        expectEqual("o.items[1]", item, 2.5),
        expectThrows<ExternCompoundAssignmentException>("o.x += 1", "Compound assignment not supported",
            { => o.x += 1.0 })
    ])
}
