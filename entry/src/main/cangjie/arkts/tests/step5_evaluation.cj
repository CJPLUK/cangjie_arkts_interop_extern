package ohos_app_cangjie_entry.arkts.tests

import std.math.numeric.BigInt
import ohos.ark_interop.*
import ohos_app_cangjie_entry.arkts.*

// Fixtures are classes from fixtures.ets; ArkTS checks the effects after each scenario.
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
        ("step5.unsupportedIndex", { _, f => unsupportedIndex(f) }),
        ("step5.indexWriteOrder", { _, f => indexWriteOrder(f) }),
        ("step5.compoundAssignmentOrder", { _, f => compoundAssignmentOrder(f) }),
        ("step5.compoundOperators", { _, f => compoundOperators(f) }),
        ("step5.compoundThroughSyntax", { _, f => compoundThroughSyntax(f) }),
        ("step5.logicalAssignment", { _, f => logicalAssignment(f) }),
        ("step5.compoundReceiverOnce", { _, f => compoundReceiverOnce(f) }),
        ("step5.compoundErrors", { _, f => compoundErrors(f) }),
        ("step5.variableCompoundIsMethodCall", { _, f => variableCompoundIsMethodCall(f) }),
        ("step5.evalPayloadUnchanged", { _, f => evalPayloadUnchanged(f) }),
        ("step5.derivedConstructor", { _, f => derivedConstructor(f) }),
        ("step5.longChainLoop", { _, f => longChainLoop(f) })
    ]
}

func step5OffThreadScenarios(): Array<(String, OffThreadScenario)> {
    [("step5.evalFromOtherThread", evalFromOtherThread)]
}

type E = Extern<ArkTSRuntime>

/** fixtures[index] as an evaluated Extern. */
func ext(fixtures: Array<JSValue>, index: Int64): E {
    ArkTSRuntime.retain(fixture(fixtures, index))
}

func number(e: E): Float64 { unwrap(e).toNumber() }

func text(e: E): String { unwrap(e).toString() }

func compound(target: E, op: String, value: Any): E {
    ArkTSRuntime.eval(E.ExternCompoundAssignment(target, op, value))
}

func member(target: E, field: String): E {
    E.ExternMemberAccess(target, field)
}

/** fixtures: Target. */
func memberRead(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    firstFailure([
        expectEqual("e.num", number(e.num), 1.5),
        expectEqual("e.str", text(e.str), "héllo"),
        expectEqual("e.a.b.c", number(e.a.b.c), 42.0),
        expectEqual("e.missing is undefined", unwrap(e.missing).isUndefined(), true),
        expectEqual("e.str.length", number(e.str.length), 5.0)
    ])
}

/**
 * fixtures: Target. Members of primitives come from their wrapper object, as in JS; methods get
 * the primitive as `this`. Writing to a primitive fails, as in strict-mode JS.
 */
func primitiveReceivers(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    firstFailure([
        expectEqual("e.str.toUpperCase()", text(e.str.toUpperCase()), "HÉLLO"),
        expectEqual("e.str[1]", text(e.str[1]), "é"),
        expectEqual("e.num.toFixed(2)", text(e.num.toFixed(2.0)), "1.50"),
        expectEqual("e.big.toString()", text(e.big.toString()), "10"),
        expectThrows<ExternMemberAccessException>("e.str.x = 1", "Cannot set property 'x' of a primitive string",
            { => e.str.x = 1.0 }),
        expectThrows<ExternIndexedAccessException>("e.str[0] = \"x\"", "Cannot index-assign a primitive string",
            { => e.str[0] = "x" }),
        expectThrows<ExternMemberAccessException>("e.num.x += 1", "Cannot set property 'x' of a primitive number",
            { => compound(member(member(e, "num"), "x"), "+", 1.0) })
    ])
}

/** fixtures: Target. ArkTS checks num == 7, a.b.c == 99, str == "set". */
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
func memberOfUndefinedOrNull(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    firstFailure([
        expectThrows<ExternMemberAccessException>("e.nothing.x", "Cannot read property 'x' of undefined",
            { => e.nothing.x }),
        expectThrows<ExternMemberAccessException>("e.nul.x", "Cannot read property 'x' of null", { => e.nul.x }),
        expectThrows<ExternMemberAccessException>("e.nothing.x = 1", "Cannot set property 'x' of undefined",
            { => e.nothing.x = 1.0 }),
        expectThrows<ExternMemberAccessException>("e.nul.m()", "Cannot read property 'm' of null",
            { => e.nul.m() })
    ])
}

/** fixtures: Target, callLog. ArkTS checks callLog.self === target. */
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
func receiverEvaluatedOnce(fixtures: Array<JSValue>): String {
    let h = ext(fixtures, 0)
    expectEqual("return value", number(h.target.record(1.0)), 1.0)
}

/**
 * fixtures: Target, callLog, Rectangle. ArkTS checks the `typeof` of each argument:
 * bigint, number, boolean, string, bigint, number, object.
 */
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
 * fixtures: Target. ArkTS checks items == [55, 77, 99] (length 3), str == "via string",
 * num == 4.
 */
func indexReadWrite(context: JSContext, fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    let symbol = ArkTSRuntime.retain(context.symbol(description: "k").toJSValue())
    let readChecks = [
        expectEqual("e.items[1] (Int64)", number(e.items[1]), 20.0),
        expectEqual("e.items[Int32(0)]", number(e.items[Int32(0)]), 10.0),
        expectEqual("e[\"num\"] (String)", number(e["num"]), 1.5),
        expectEqual("e[e.keyName] (Extern string)", number(e[e.keyName]), 1.5),
        expectEqual("e.items[e.one] (Extern integral number)", number(e.items[e.one]), 20.0)
    ]
    e.items[2] = 99.0
    e.items[Int32(1)] = 77.0
    e.items[e.zero] = 55.0
    e["str"] = "via string"
    e[e.keyName] = 4.0
    e[e.half] = "fraction"
    e.items[-1] = 5.0
    e[symbol] = 8.0
    e[0] = "zero"
    firstFailure([
        expectEqual("e[0] on an object (not an array)", text(e[0]), "zero"),
        expectEqual("property \"0\"", fixture(fixtures, 0).getProperty("0").toString(), "zero"),
        firstFailure(readChecks),
        expectEqual("e[e.half] (Extern fractional number)", text(e[e.half]), "fraction"),
        expectEqual("property \"1.5\"", fixture(fixtures, 0).getProperty("1.5").toString(), "fraction"),
        expectEqual("e.items[-1]", number(e.items[-1]), 5.0),
        expectEqual("property \"-1\"", unwrap(e.items).getProperty("-1").toNumber(), 5.0),
        expectEqual("e[symbol] (Extern symbol)", number(e[symbol]), 8.0)
    ])
}

/** fixtures: Target. */
func unsupportedIndex(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    firstFailure([
        expectThrows<ExternIndexedAccessException>("e[1.5] (Float64)", "Unsupported ArkTS index type",
            { => e[1.5] }),
        expectThrows<ExternIndexedAccessException>("e[e.flag] (Extern boolean)", "Unsupported ArkTS index type",
            { => e[e.flag] }),
        expectThrows<ExternIndexedAccessException>("e.nothing[0]", "Cannot index undefined", { => e.nothing[0] }),
        expectThrows<ExternIndexedAccessException>("e.nul[0] = 1", "Cannot index null", { => e.nul[0] = 1.0 })
    ])
}

/** fixtures: OrderLog. ArkTS checks the getter order target, index, value and stored[1] == 5. */
func indexWriteOrder(fixtures: Array<JSValue>): String {
    let l = ext(fixtures, 0)
    l.target[l.index] = l.value
    ""
}

/** fixtures: OrderLog. ArkTS checks the getter order target, index, value and stored[1] == 5. */
func compoundAssignmentOrder(fixtures: Array<JSValue>): String {
    let l = ext(fixtures, 0)
    expectEqual("result", number(compound(E.ExternIndexedAccess(member(l, "target"), member(l, "index")), "+",
        member(l, "value"))), 5.0)
}

/** fixtures: Target. Each row sets e.num, applies `op=` and checks the result and the stored value. */
func compoundOperators(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    let numbers: Array<(String, Float64, Float64, Float64)> = [
        ("+", 1.5, 1.0, 2.5),
        ("-", 5.0, 7.5, -2.5),
        ("*", 3.0, 4.0, 12.0),
        ("/", 1.0, 4.0, 0.25),
        ("%", -5.5, 2.0, -1.5),
        ("**", 2.0, 10.0, 1024.0),
        ("&", 5.0, 3.0, 1.0),
        ("|", 4.0, 1.0, 5.0),
        ("^", 5.0, 1.0, 4.0),
        ("<<", 1.0, 31.0, -2147483648.0),
        (">>", -8.0, 1.0, -4.0)
    ]
    let results = numbers.map({ row =>
        let (op, start, operand, expected) = row
        e.num = start
        let result = compound(member(e, "num"), op, operand)
        firstFailure([
            expectEqual("${start} ${op}= ${operand} result", number(result), expected),
            expectEqual("${start} ${op}= ${operand} stored", number(e.num), expected)
        ])
    })
    e.big = BigInt(10)
    let bigPlus = unwrap(compound(member(e, "big"), "+", 5)).toBigInt()
    let bigPow = unwrap(compound(member(e, "big"), "**", 2)).toBigInt()
    e.str = "a"
    let strNumber = text(compound(member(e, "str"), "+", 1.5))
    let strBigInt = text(compound(member(e, "str"), "+", 2))
    e.num = 1.5
    let numberStr = text(compound(member(e, "num"), "+", "x"))
    let undefinedStr = text(compound(member(e, "nothing"), "+", "s"))
    e.num = 0.1
    let fraction = number(compound(member(e, "num"), "+", 0.2))
    firstFailure([
        firstFailure(results),
        expectEqual("10n += 5 (Int64 is bigint)", bigPlus, BigInt(15)),
        expectEqual("15n **= 2", bigPow, BigInt(225)),
        expectEqual("\"a\" += 1.5", strNumber, "a1.5"),
        expectEqual("\"a1.5\" += 2 (bigint)", strBigInt, "a1.52"),
        expectEqual("1.5 += \"x\"", numberStr, "1.5x"),
        expectEqual("undefined += \"s\"", undefinedStr, "undefineds"),
        expectEqual("0.1 += 0.2", fraction, 0.30000000000000004)
    ])
}

/** fixtures: Target. Through the compiler; ArkTS checks num == 2.5 and items[0] == 11. */
func compoundThroughSyntax(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    e.num += 1.0
    e.items[0] += 1.0
    firstFailure([
        expectEqual("e.num", number(e.num), 2.5),
        expectEqual("e.items[0]", number(e.items[0]), 11.0)
    ])
}

/**
 * fixtures: Target, OrderLog. `&&=` / `||=` assign only when JS would; when they
 * short-circuit, the value (a getter on the OrderLog) is not evaluated. ArkTS checks
 * flag == "yes", zero == 5, num == 1.5 and that the OrderLog was read once.
 */
func logicalAssignment(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    let l = ext(fixtures, 1)
    let yes = text(compound(member(e, "flag"), "&&", "yes"))
    let five = number(compound(member(e, "zero"), "||", member(l, "value")))
    let keptNum = number(compound(member(e, "num"), "||", member(l, "value")))
    e.nothing = 0.0
    let keptZero = number(compound(member(e, "nothing"), "&&", member(l, "value")))
    firstFailure([
        expectEqual("true &&= \"yes\"", yes, "yes"),
        expectEqual("0 ||= 5", five, 5.0),
        expectEqual("1.5 ||= ... keeps 1.5", keptNum, 1.5),
        expectEqual("0 &&= ... keeps 0", keptZero, 0.0)
    ])
}

/** fixtures: CountingHolder around a Target. ArkTS checks reads == 1 and target.num == 2.5. */
func compoundReceiverOnce(fixtures: Array<JSValue>): String {
    let h = ext(fixtures, 0)
    h.target.num += 1.0
    ""
}

/** fixtures: Target. */
func compoundErrors(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    firstFailure([
        expectThrows<ExternCompoundAssignmentException>("bigint += number", "Cannot mix BigInt and other types",
            { => compound(member(e, "big"), "+", 1.0) }),
        expectThrows<ExternCompoundAssignmentException>("object += 1", "Unsupported operand for '+='",
            { => compound(member(e, "a"), "+", 1.0) }),
        expectThrows<ExternCompoundAssignmentException>("string -= 1", "Unsupported operand for '-='",
            { => compound(member(e, "str"), "-", 1.0) }),
        expectThrows<ExternCompoundAssignmentException>("target is a payload", "needs a member or index target",
            { => compound(e, "+", 1.0) }),
        expectThrows<ExternMemberAccessException>("e.nothing.x += 1", "Cannot read property 'x' of undefined",
            { => compound(member(member(e, "nothing"), "x"), "+", 1.0) })
    ])
}

/** `x += 1` on an Extern variable is desugared by the compiler to `x = x.+(1)`. */
func variableCompoundIsMethodCall(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    var x = e.num
    try {
        x += 1
        "x += 1: expected an exception"
    } catch (ex: ExternFunctionAccessException) {
        expectEqual("x += 1", ex.message, "ArkTS '+' is not a function")
    }
}

/** fixtures: Rectangle. */
func evalPayloadUnchanged(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    expectEqual("eval(payload) === fixture", unwrap(ArkTSRuntime.eval(e)).strictEqual(fixture(fixtures, 0)), true)
}

/** fixtures: Target. `ExternSequence` is derived: `eval` and `evalTree` hand it to `evalDerived`. */
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
func evalFromOtherThread(): String {
    let o = ArkTSRuntime.run { ArkTSRuntime.retain(ArkTSRuntime.context.object().toJSValue()) }
    o.x = 1.5
    o.x += 1.0
    o.s = "a"
    o.s += 2.5
    let (x, s) = ArkTSRuntime.run { (number(o.x), text(o.s)) }
    expectEqual("x and s", "${x} ${s}", "2.500000 a2.5")
}
