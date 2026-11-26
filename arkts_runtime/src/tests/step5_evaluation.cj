package arkts_runtime.tests

import std.math.numeric.BigInt

import arkts_runtime.*

@When[bundle == "com.example.testArkTSForeignRuntime"]
func step5Scenarios(): Array<(String, Scenario)> {
    [
        ("step5.memberRead", { _, f => memberRead(f) }),
        ("step5.primitiveReceivers", { _, f => primitiveReceivers(f) }),
        ("step5.memberUpdate", { _, f => memberUpdate(f) }),
        ("step5.memberOfUndefinedOrNull", { _, f => memberOfUndefinedOrNull(f) }),
        ("step5.methodCallThis", { _, f => methodCallThis(f) }),
        ("step5.extractedMethodKeepsThis", { _, f => extractedMethodKeepsThis(f) }),
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
        ("step5.longChainLoop", { _, f => longChainLoop(f) })
    ]
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func step5OffThreadScenarios(): Array<(String, OffThreadScenario)> {
    [("step5.operationsFromOtherThread", operationsFromOtherThread)]
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
type E = Extern<ArkTSRuntime>

@When[bundle == "com.example.testArkTSForeignRuntime"]
func ext(fixtures: Array<NativeJSValue>, index: Int64): E {
    ArkTSRuntime.retain(fixture(fixtures, index))
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func number(e: E): Float64 { unwrap(e).toNumber() }

@When[bundle == "com.example.testArkTSForeignRuntime"]
func text(e: E): String { unwrap(e).toString() }

@When[bundle == "com.example.testArkTSForeignRuntime"]
func memberRead(fixtures: Array<NativeJSValue>): String {
    let target = ext(fixtures, 0)
    firstFailure([
        expectEqual("target.num", number(target.num), 1.5),
        expectEqual("target.str", text(target.str), "héllo"),
        expectEqual("target.a.b.c", number(target.a.b.c), 42.0),
        expectEqual("target.missing is undefined", unwrap(target.missing).isUndefined(), true)
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func primitiveReceivers(fixtures: Array<NativeJSValue>): String {
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

@When[bundle == "com.example.testArkTSForeignRuntime"]
func memberUpdate(fixtures: Array<NativeJSValue>): String {
    let target = ext(fixtures, 0)
    target.num = 7.0
    target.a.b.c = 99.0
    target.str = "set"
    firstFailure([
        expectEqual("target.num", number(target.num), 7.0),
        expectEqual("target.a.b.c", number(target.a.b.c), 99.0),
        expectEqual("target.str", text(target.str), "set")
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func memberOfUndefinedOrNull(fixtures: Array<NativeJSValue>): String {
    let target = ext(fixtures, 0)
    let notObject = "The ArkTS data types do not match, expect: object, given: "
    firstFailure([
        expectThrows<ExternMemberAccessException>("target.nothing.x", notObject + "undefined", { => target.nothing.x }),
        expectThrows<ExternMemberAccessException>("target.nul.x", notObject + "null", { => target.nul.x }),
        expectThrows<ExternMemberAccessException>("target.nothing.x = 1", notObject + "undefined",
            { => target.nothing.x = 1.0 }),
        expectThrows<ExternMemberAccessException>("target.nul.m()", notObject + "null", { => target.nul.m() })
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func methodCallThis(fixtures: Array<NativeJSValue>): String {
    let target = ext(fixtures, 0)
    let callLog = ext(fixtures, 1)
    let result = target.record(1.0, 2.0)
    firstFailure([
        expectEqual("return value", number(result), 2.0),
        expectEqual("this === target", unwrap(callLog.self).strictEqual(fixture(fixtures, 0)), true)
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func extractedMethodKeepsThis(fixtures: Array<NativeJSValue>): String {
    let target = ext(fixtures, 0)
    let callLog = ext(fixtures, 1)
    let recordNotReadFromReceiver = ArkTSRuntime.retain(fixture(fixtures, 0).getProperty("record"))
    recordNotReadFromReceiver(1.0)
    let notReadFromReceiverGetsUndefinedThis = unwrap(callLog.self).isUndefined()
    let recordReadIntoVariable = target.record
    recordReadIntoVariable(1.0)
    firstFailure([
        expectEqual("calls", number(callLog.calls), 2.0),
        expectEqual("function not read from a receiver: this is undefined", notReadFromReceiverGetsUndefinedThis, true),
        expectEqual("method read into a variable: this === target",
            unwrap(callLog.self).strictEqual(fixture(fixtures, 0)), true)
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func indexCallThis(js: JS, fixtures: Array<NativeJSValue>): String {
    let target = ext(fixtures, 0)
    let callLog = ext(fixtures, 1)
    target["record"](1.0)
    let byNameThisIsTarget = unwrap(callLog.self).strictEqual(fixture(fixtures, 0))
    let recordStoredInArray = js.array([fixture(fixtures, 0).getProperty("record")])
    fixture(fixtures, 0).asObject()["list"] = recordStoredInArray.toJSValue()
    target.list[0](1.0)
    firstFailure([
        expectEqual("target[\"record\"](): this === target", byNameThisIsTarget, true),
        expectEqual("target.list[0](), a method stored in an array: this === the array, not target",
            unwrap(callLog.self).strictEqual(unwrap(target.list)), true)
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func receiverEvaluatedOnce(fixtures: Array<NativeJSValue>): String {
    let holder = ext(fixtures, 0)
    expectEqual("return value", number(holder.target.record(1.0)), 1.0)
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func argumentTypes(fixtures: Array<NativeJSValue>): String {
    let target = ext(fixtures, 0)
    let rect = ext(fixtures, 2)
    let count = target.record(1, 2.5, true, "s", BigInt(3), Int32(4), rect)
    let arrayOf = ArkTSRuntime.memberAccess(ArkTSRuntime.memberAccess(ArkTSRuntime.global(), "Array"), "of")
    let passed = firstFailure([0, 1, 8, 9, 20].map { n =>
        let received = from<Array<Float64>>(ArkTSRuntime.functionCall(arrayOf, Array<Any>(n) { i => Float64(i) }))
        expectEqual("Array.of with ${n} arguments", received, Array<Float64>(n) { i => Float64(i) })
    })
    firstFailure([
        expectEqual("argument count", number(count), 7.0),
        passed,
        expectThrows<ExternConversionException>("Rune argument", "Unsupported conversion to ArkTS",
            { => target.record(r'a') })
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func callNonFunction(fixtures: Array<NativeJSValue>): String {
    let target = ext(fixtures, 0)
    let v = target.num
    firstFailure([
        expectThrows<ExternFunctionAccessException>("target.str()", "ArkTS value is not a function",
            { => target.str(1.0) }),
        expectThrows<ExternFunctionAccessException>("target.missing()", "ArkTS value is not a function",
            { => target.missing() }),
        expectThrows<ExternFunctionAccessException>("target.items[0]()", "ArkTS value is not a function",
            { => target.items[0]() }),
        expectThrows<ExternFunctionAccessException>("v()", "ArkTS value is not a function", { => v() })
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func indexReadWrite(js: JS, fixtures: Array<NativeJSValue>): String {
    let target = ext(fixtures, 0)
    let symbol = ArkTSRuntime.retain(js.symbol(description: "k").toJSValue())
    let readChecks = [
        expectEqual("target.items[1] (Int64)", number(target.items[1]), 20.0),
        expectEqual("target.items[0.0] (Float64 key)", number(target.items[0.0]), 10.0),
        expectEqual("target[\"num\"] (String)", number(target["num"]), 1.5),
        expectEqual("target[Utf16String(\"num\")]", number(target[Utf16String("num")]), 1.5),
        expectEqual("target[target.keyName] (Extern string)", number(target[target.keyName]), 1.5),
        expectEqual("target.items[target.one] (Extern number key)", number(target.items[target.one]), 20.0)
    ]
    target.items[2] = 99.0
    target.items[1.0] = 77.0
    target.items[target.zero] = 55.0
    target["str"] = "via string"
    target[target.keyName] = 4.0
    target[target.half] = "fraction"
    target[0.25] = "quarter"
    target[symbol] = 8.0
    let surrogate = Utf16String([0xD800u16])
    target[surrogate] = "surrogate"
    firstFailure([
        firstFailure(readChecks),
        expectEqual("raw UTF-16 key", text(target[surrogate]), "surrogate"),
        expectEqual("target[target.half] (Extern fractional number)", text(target[target.half]), "fraction"),
        expectEqual("property \"1.5\"", fixture(fixtures, 0).getProperty("1.5").toString(), "fraction"),
        expectEqual("property \"0.25\" (Float64 key)", fixture(fixtures, 0).getProperty("0.25").toString(), "quarter"),
        expectEqual("target[symbol] (Extern symbol)", number(target[symbol]), 8.0),
        expectThrows<ExternIndexedAccessException>("target[0] on an object (not an array)",
            "expect: array, given: object", { => target[0] = "zero" }),
        expectThrows<ExternIndexedAccessException>("target.items[-1]", "out of range", { => target.items[-1] = 5.0 })
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func indexBoundaries(js: JS, fixtures: Array<NativeJSValue>): String {
    let a = ext(fixtures, 0)
    func num(n: Float64): E { ArkTSRuntime.retain(js.number(n).toJSValue()) }
    let reads = [
        expectEqual("fixture", from<Array<Float64>>(a), [10.0, 20.0, 30.0]),
        expectThrows<ExternIndexedAccessException>("a[3] (Int64 reads need a position in 0..length-1)",
            "allowed: [0, 3), given: 3", { => a[3] }),
        expectThrows<ExternIndexedAccessException>("a[-1]", "given: -1", { => a[-1] }),
        expectEqual("a[Extern 5] (a key, not a position: undefined past the end)",
            ArkTSRuntime.isUndefined(a[num(5.0)]), true)
    ]
    let prototype = js.global.getProperty("Array").getProperty("prototype")
    let reflect = js.global.getProperty("Reflect")
    prototype.setProperty("5", js.number(7.0).toJSValue())
    let inherited = try {
        expectThrows<ExternIndexedAccessException>("a[5] with Array.prototype[5] set", "allowed: [0, 3), given: 5",
            { => a[5] })
    } finally {
        reflect.getProperty("deleteProperty").call([prototype, js.string("5").toJSValue()], thisArg: reflect)
    }
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
        expectEqual("a[3] = 1 (a write at length grows the array)", outcome({ => a[3] = 1.0 }), "ok, length 4"),
        expectEqual("a[6] = 2 (a write past length grows the array, with holes)", outcome({ => a[6] = 2.0 }),
            "ok, length 7"),
        expectEqual("a[-1] = 2", outcome({ => a[-1] = 2.0 }),
            "throws The accessing index is out of range, allowed: [0, 7), given: -1"),
        expectEqual("a[4294967295] = 7 (succeeds but empties the array)", outcome({ => a[4294967295] = 7.0 }),
            "ok, length 0")
    ]
    firstFailure([
        firstFailure(reads),
        inherited,
        afterWrite,
        firstFailure(writes)
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func nonArrayIndexing(fixtures: Array<NativeJSValue>): String {
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

@When[bundle == "com.example.testArkTSForeignRuntime"]
func unsupportedIndex(fixtures: Array<NativeJSValue>): String {
    let target = ext(fixtures, 0)
    firstFailure([
        expectThrows<ExternIndexedAccessException>("target.items[Int32(0)]", "Unsupported ArkTS index type",
            { => target.items[Int32(0)] }),
        expectThrows<ExternIndexedAccessException>("target.items[UInt8(0)]", "Unsupported ArkTS index type",
            { => target.items[UInt8(0)] }),
        expectThrows<ExternIndexedAccessException>("target[target.flag] (Extern boolean)",
            "Unsupported ArkTS index type", { => target[target.flag] }),
        expectThrows<ExternIndexedAccessException>("target.nothing[0]", "expect: array, given: undefined",
            { => target.nothing[0] }),
        expectThrows<ExternIndexedAccessException>("target.nul[0] = 1", "expect: array, given: null",
            { => target.nul[0] = 1.0 }),
        expectThrows<ExternIndexedAccessException>("target.nothing[\"k\"]", "expect: object, given: undefined",
            { => target.nothing["k"] })
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func indexWriteOrder(fixtures: Array<NativeJSValue>): String {
    let orderLog = ext(fixtures, 0)
    orderLog.target[orderLog.index] = orderLog.value
    ""
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func numberKeys(js: JS, fixtures: Array<NativeJSValue>): String {
    let e = ext(fixtures, 0)
    func num(n: Float64): E { ArkTSRuntime.retain(js.number(n).toJSValue()) }
    e[num(1e21)] = "huge"
    e[num(0.25)] = "quarter"
    e[num(-0.0)] = "zero"
    firstFailure([
        expectEqual("Extern 1e21 is named as JS String(1e21)", fixture(fixtures, 0).getProperty("1e+21").toString(),
            "huge"),
        expectEqual("Extern 0.25 is named as JS String(0.25)", fixture(fixtures, 0).getProperty("0.25").toString(),
            "quarter"),
        expectEqual("Extern 0.25 is not named as Cangjie formats it",
            fixture(fixtures, 0).getProperty("${0.25}").isUndefined(), true),
        expectEqual("Extern -0 is named as JS String(-0)", fixture(fixtures, 0).getProperty("0").toString(), "zero")
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func compoundAssignmentUnsupported(fixtures: Array<NativeJSValue>): String {
    let e = ext(fixtures, 0)
    let readsMemberOfPrimitive = "The ArkTS data types do not match, expect: object, given: "
    firstFailure([
        expectThrows<ExternMemberAccessException>("e.num += 1 reads the member + of e.num",
            readsMemberOfPrimitive + "number", { => e.num += 1.0 }),
        expectThrows<ExternMemberAccessException>("e.items[0] += 1 reads the member + of e.items[0]",
            readsMemberOfPrimitive + "number", { => e.items[0] += 1.0 }),
        expectThrows<ExternMemberAccessException>("e.flag &&= \"yes\" reads the member && of e.flag",
            readsMemberOfPrimitive + "bool", { => e.flag &&= "yes" }),
        expectEqual("e.num unchanged: the read throws before the write", number(e.num), 1.5),
        expectEqual("e.items[0] unchanged: the read throws before the write", number(e.items[0]), 10.0)
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func variableCompoundIsMethodCall(fixtures: Array<NativeJSValue>): String {
    let e = ext(fixtures, 0)
    var x = e.num
    try {
        x += 1
        "x += 1: expected an exception"
    } catch (ex: ExternMemberAccessException) {
        expectEqual("x += 1 is x = x.+(1), which reads the member + of a number", ex.message,
            "The ArkTS data types do not match, expect: object, given: number.")
    }
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func longChainLoop(fixtures: Array<NativeJSValue>): String {
    let e = ext(fixtures, 0)
    for (i in 0..100000) {
        let c = e.a.b.c
        if (i % 10000 == 0 && number(c) != 42.0) {
            return "iteration ${i}: e.a.b.c is ${number(c)}"
        }
    }
    ""
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func operationsFromOtherThread(): String {
    let o = ArkTSRuntime.run { ArkTSRuntime.retain(ArkTSRuntime.js.object().toJSValue()) }
    o.x = 1.5
    o.items = [1.0, 2.0]
    o.items[1] = 2.5
    let (x, item) = ArkTSRuntime.run { (number(o.x), number(o.items[1])) }
    firstFailure([
        expectEqual("o.x", x, 1.5),
        expectEqual("o.items[1]", item, 2.5),
        expectThrows<ExternMemberAccessException>("o.x += 1", "expect: object, given: number",
            { => o.x += 1.0 })
    ])
}
