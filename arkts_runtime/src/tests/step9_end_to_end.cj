package arkts_runtime.tests

import std.math.numeric.BigInt
import ohos.ark_interop.*
import arkts_runtime.*

// The step 9 scenarios need no test-package fixtures beyond a plain sink object, so the smoke
// page in Index.ets runs them too.
@When[bundle == "com.example.testArkTSForeignRuntime"]
func step9Scenarios(): Array<(String, Scenario)> {
    [
        ("step9.designExample", { _, f => designExample(f) }),
        ("step9.mixedScenario", { _, _ => mixedScenario(1000) })
    ]
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func step9OffThreadScenarios(): Array<(String, OffThreadScenario)> {
    [("step9.mixedScenarioOffThread", { => mixedScenario(100) })]
}

/**
 * fixtures: sink. The example of the design's section 1, except the explicit `fromExtern` (until
 * the forced cast parses) and `blob.width += 2.0` (compound assignment is not supported). Stores
 * the rectangle as sink.rect; the caller checks from ArkTS that width == 5 and area() == 25.
 */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func designExample(fixtures: Array<JSValue>): String {
    let sink = ext(fixtures, 0)

    let api: Extern<ArkTSRuntime> = ArkTSRuntime.requireArkModule(TEST_MODULE)
    let blob = api.createRectangle()
    blob.width = 3.0
    blob.width = ArkTSRuntime.fromExtern<Float64>(blob.width) + 2.0
    let a: Float64 = ArkTSRuntime.fromExtern<Float64>(blob.area())

    sink.rect = blob
    firstFailure([
        expectEqual("area", a, 25.0),
        expectEqual("width", from<Float64>(blob.width), 5.0)
    ])
}

/** Runs `mixedOnce` `iterations` times; stops at the first failure. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func mixedScenario(iterations: Int64): String {
    for (i in 0..iterations) {
        let failure = mixedOnce(i)
        if (!failure.isEmpty()) {
            return "iteration ${i}: ${failure}"
        }
    }
    ""
}

/** Every runtime feature once, on objects made from JS built-ins (so it also runs off-thread). */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func mixedOnce(i: Int64): String {
    let g = ArkTSRuntime.global()

    // Member updates (every leaf type), nested members.
    let o = ArkTSRuntime.object()
    o.name = "item${i}!"
    o.count = 0.25
    o.nested = ArkTSRuntime.object()
    o.nested.value = Int32(8)
    o.bits = 22.0
    o.big = i + 1
    o.flag = true

    // Arrays and indexing with Int64, Float64, String, Extern number and Extern symbol keys.
    o.items = [1.0, 2.0, 3.0]
    o.items[0] = 10.0
    o.items[1.0] = 7.0
    o.idx = 2.0
    let third = from<Float64>(o.items[o.idx])
    let pushed = from<Float64>(o.items.push(4.0))
    o["dyn"] = "by string"
    let key = ArkTSRuntime.symbol(description: "k")
    o[key] = true

    // Calls: free call (this = undefined), built-ins, construction through Reflect.
    let max = g.Math.max
    let m = g.Reflect.construct(g.Map, to(Array<E>()))
    m.set("a", Int32(1))

    // Helpers.
    let hiddenDefined = ArkTSRuntime.objectDefineOwnProperty(o, "hidden", "h", isEnumerable: false)
    let hilog = ArkTSRuntime.requireSystemNativeModule("hilog", None)
    let back = from<E>(o.nested)

    firstFailure([
        expectEqual("o.name", from<String>(o.name), "item${i}!"),
        expectEqual("o.nested.value", from<Int32>(o.nested.value), 8),
        expectEqual("o.count", from<Float64>(o.count), 0.25),
        expectEqual("o.bits", from<Float64>(o.bits), 22.0),
        expectEqual("o.big", from<Int64>(o.big), i + 1),
        expectEqual("o.flag", from<Bool>(o.flag), true),
        expectEqual("o.items", from<Array<Float64>>(o.items), [10.0, 7.0, 3.0, 4.0]),
        expectEqual("o.items[o.idx]", third, 3.0),
        expectEqual("push", pushed, 4.0),
        expectEqual("JSON.stringify", from<String>(g.JSON.stringify(o.items)), "[10,7,3,4]"),
        expectEqual("o[\"dyn\"]", from<String>(o["dyn"]), "by string"),
        expectEqual("o[symbol]", from<Bool>(o[key]), true),
        expectEqual("free call max", from<Float64>(max(1.0, 9.0, 3.0)), 9.0),
        expectEqual("Map.get", from<Int32>(m.get("a")), 1),
        expectEqual("Map.size", from<Float64>(m.size), 1.0),
        expectEqual("defineOwnProperty", hiddenDefined, true),
        expectEqual("objectKeys", ArkTSRuntime.objectKeys(o),
            ["name", "count", "nested", "bits", "big", "flag", "items", "idx", "dyn"]),
        expectEqual("has hidden", ArkTSRuntime.objectHasProperty(o, "hidden"), true),
        expectEqual("has toString", ArkTSRuntime.objectHasProperty(o, "toString"), true),
        expectEqual("has missing", ArkTSRuntime.objectHasProperty(o, "missing"), false),
        expectEqual("Extern identity", ArkTSRuntime.strictEqual(back, o.nested), true),
        expectEqual("fresh objects differ", ArkTSRuntime.strictEqual(ArkTSRuntime.object(), ArkTSRuntime.object()), false),
        expectEqual("isUndefined", ArkTSRuntime.isUndefined(o.missing), true),
        expectEqual("isNull", ArkTSRuntime.isNull(ArkTSRuntime.null()), true),
        expectEqual("isUndefined(undefined())", ArkTSRuntime.isUndefined(ArkTSRuntime.undefined()), true),
        expectEqual("hilog.info", ArkTSRuntime.objectHasProperty(hilog, "info"), true),

        // Conversions.
        expectEqual("options", from<Array<?Float64>>(to([Some(1.5), None<Float64>])), [Some(1.5), None]),
        expectEqual("nested arrays", from<Array<Array<Int64>>>(to([[1, 2], [Int64.Max]])), [[1, 2], [Int64.Max]]),
        expectEqual("UInt64.Max", from<UInt64>(to(UInt64.Max)), UInt64.Max),
        expectEqual("Int8.Min", from<Int8>(to(Int8.Min)), Int8.Min),
        expectEqual("Float16", from<Float16>(to(Float16(0.5))), Float16(0.5)),
        expectEqual("BigInt", from<BigInt>(to(BigInt("-123456789012345678901234567890"))),
            BigInt("-123456789012345678901234567890")),
        expectEqual("String", from<String>(to("héllo 😀")), "héllo 😀"),
        expectEqual("Unit", from<Unit>(to(())) == (), true),

        // Exceptions.
        expectThrows<ForeignRuntimeException>("JSON.parse", "SyntaxError", { => g.JSON.parse("{") }),
        expectThrows<ExternMemberAccessException>("o.missing.x", "expect: object, given: undefined",
            { => o.missing.x }),
        expectThrows<ExternFunctionAccessException>("o.count()", "ArkTS 'count' is not a function",
            { => o.count() }),
        expectThrows<ExternConversionException>("Bool from a number", "Cannot convert ArkTS number to Bool",
            { => from<Bool>(o.count) })
    ])
}
