package arkts_runtime.tests

import std.runtime.gc

import arkts_runtime.*

@When[bundle == "com.example.testArkTSForeignRuntime"]
func step4Scenarios(): Array<(String, Scenario)> {
    [
        ("step4.retainClassifiesEachKind", retainClassifiesEachKind),
        ("step4.payloadRoundTrip", payloadRoundTrip),
        ("step4.retainedValueOutlivesScope", { js, _ => retainedValueOutlivesScope(js) }),
        ("step4.rejectsForeignPayload", { js, _ => rejectsForeignPayload(js) }),
        ("step4.keepObject", keepObject),
        ("step4.checkKeptObject", checkKeptObject),
        ("step4.dropKeptObject", { _, _ => dropKeptObject() }),
        ("step4.releaseManyHandles", { js, _ => releaseManyHandles(js) })
    ]
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
const FOREIGN_PAYLOAD = "Extern payload was not produced by ArkTSRuntime"

@When[bundle == "com.example.testArkTSForeignRuntime"]
func unwrap(value: Extern<ArkTSRuntime>): NativeJSValue {
    ArkTSRuntime.jsValueOf(value)
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
type PayloadKind = String

@When[bundle == "com.example.testArkTSForeignRuntime"]
func valuesOfEachKind(js: JS, fixtures: Array<NativeJSValue>): Array<(String, NativeJSValue, PayloadKind)> {
    [
        ("undefined", js.undefined().toJSValue(), "Imm"),
        ("null", js.null().toJSValue(), "Imm"),
        ("boolean", js.boolean(true).toJSValue(), "Imm"),
        ("number", js.number(1.5).toJSValue(), "Imm"),
        ("string", js.string("héllo").toJSValue(), "Pin"),
        ("bigint", js.bigint(10).toJSValue(), "Pin"),
        ("symbol", js.symbol(description: "s").toJSValue(), "Pin"),
        ("object", js.object().toJSValue(), "Pin"),
        ("array", js.array([js.number(1.0).toJSValue()]).toJSValue(), "Pin"),
        ("function", js.function({ js, _ => js.undefined().toJSValue() }).toJSValue(), "Pin"),
        ("ArkTS class instance", fixture(fixtures, 0), "Pin"),
        ("external", js.external(ExternalProbe()).toJSValue(), "Pin")
    ]
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
class ExternalProbe {}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func retainClassifiesEachKind(js: JS, fixtures: Array<NativeJSValue>): String {
    let function = js.function({ js, _ => js.undefined().toJSValue() }).toJSValue()
    let receiver = ArkTSRuntime.retain(fixture(fixtures, 0))
    firstFailure([
        firstFailure(valuesOfEachKind(js, fixtures).map({ entry =>
            let (name, value, expectedKind) = entry
            expectEqual(name, ArkTSRuntime.payloadKind(ArkTSRuntime.retain(value)), expectedKind)
        })),
        expectEqual("function with a receiver",
            ArkTSRuntime.payloadKind(ArkTSRuntime.retain(function, receiver: receiver)), "Method"),
        expectEqual("number with a receiver",
            ArkTSRuntime.payloadKind(ArkTSRuntime.retain(js.number(1.0).toJSValue(), receiver: receiver)), "Imm")
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func payloadRoundTrip(js: JS, fixtures: Array<NativeJSValue>): String {
    let function = js.function({ js, _ => js.undefined().toJSValue() }).toJSValue()
    let method = ArkTSRuntime.retain(function, receiver: ArkTSRuntime.retain(fixture(fixtures, 0)))
    firstFailure([
        firstFailure(valuesOfEachKind(js, fixtures).map({ entry =>
            let (name, value, _) = entry
            expectEqual("${name} === after round trip", unwrap(ArkTSRuntime.retain(value)).strictEqual(value), true)
        })),
        expectEqual("method === its function after round trip", unwrap(method).strictEqual(function), true)
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func retainedValueOutlivesScope(js: JS): String {
    let probe = ExternalProbe()
    let (keptObject, keptString, keptExternal, keptBigInt, keptSymbol) = ArkTSRuntime.environment.runtimeFrame {
        let o = js.object()
        o["marker"] = js.string("kept").toJSValue()
        (ArkTSRuntime.retain(o.toJSValue()), ArkTSRuntime.retain(js.string("héllo 🦀").toJSValue()),
            ArkTSRuntime.retain(js.external(probe).toJSValue()),
            ArkTSRuntime.retain(js.bigint(123456789).toJSValue()),
            ArkTSRuntime.retain(js.symbol(description: "kept symbol").toJSValue()))
    }
    for (_ in 0..10000) {
        ArkTSRuntime.environment.runtimeFrame {
            js.object()["junk"] = js.string("junk").toJSValue()
        }
    }
    gc(heavy: true)
    firstFailure([
        expectEqual("object marker", unwrap(keptObject).asObject()["marker"].toString(), "kept"),
        expectEqual("string", unwrap(keptString).toString(), "héllo 🦀"),
        expectEqual("external", refEq(unwrap(keptExternal).asExternal().getData(), probe), true),
        expectEqual("bigint", Int64.fromJS(unwrap(keptBigInt)), 123456789),
        expectEqual("symbol description", js.global.getProperty("String").call(
            [unwrap(keptSymbol)], thisArg: js.undefined()).toString(), "Symbol(kept symbol)")
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func rejectsForeignPayload(js: JS): String {
    let notOurs = Extern<ArkTSRuntime>(42)
    firstFailure([
        expectThrows<ExternConversionException>("Int64 payload", FOREIGN_PAYLOAD,
            { => ArkTSRuntime.evalPayload(42) }),
        expectThrows<ExternConversionException>("bare NativeJSValue payload", FOREIGN_PAYLOAD,
            { => ArkTSRuntime.evalPayload(js.number(1.0).toJSValue()) }),
        expectThrows<ExternConversionException>("Extern(42)", FOREIGN_PAYLOAD,
            { => unwrap(notOurs) }),
        expectThrows<ExternConversionException>("Extern(42) called", FOREIGN_PAYLOAD,
            { => notOurs(1.0) }),
        expectEqual("kind of Extern(42)", ArkTSRuntime.payloadKind(notOurs), "foreign payload")
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
var keptObject: ?Extern<ArkTSRuntime> = None

@When[bundle == "com.example.testArkTSForeignRuntime"]
var keptPrimitives: ?Array<Extern<ArkTSRuntime>> = None

@When[bundle == "com.example.testArkTSForeignRuntime"]
func keepObject(js: JS, fixtures: Array<NativeJSValue>): String {
    keptObject = ArkTSRuntime.retain(fixture(fixtures, 0))
    keptPrimitives = Some([
        ArkTSRuntime.retain(js.string(String(Array<Rune>(4096, repeat: r'é')))),
        ArkTSRuntime.retain(js.bigint(123456789)),
        ArkTSRuntime.retain(js.symbol(description: "survives JS GC"))
    ])
    ""
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func checkKeptObject(js: JS, fixtures: Array<NativeJSValue>): String {
    let kept = keptObject ?? return "step4.keepObject has not run"
    let result = expectEqual("kept === object behind the WeakRef", unwrap(kept).strictEqual(fixture(fixtures, 0)), true)
    unwrap(kept).asObject()["width"] = js.number(7.0).toJSValue()
    let primitives = keptPrimitives.getOrThrow()
    firstFailure([
        result,
        expectEqual("string after JS GC", ArkTSRuntime.fromExtern<String>(primitives[0]),
            String(Array<Rune>(4096, repeat: r'é'))),
        expectEqual("bigint after JS GC", ArkTSRuntime.fromExtern<Int64>(primitives[1]), 123456789),
        expectEqual("symbol after JS GC", js.global.getProperty("String").call(
            [unwrap(primitives[2])], thisArg: js.undefined()).toString(), "Symbol(survives JS GC)")
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func dropKeptObject(): String {
    keptObject = None
    keptPrimitives = None
    gc(heavy: true)
    ""
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func step4OffThreadScenarios(): Array<(String, OffThreadScenario)> {
    [
        ("step4.retainedValueCrossesThreads", retainedValueCrossesThreads),
        ("step4.releaseHandlesFromOtherThread", releaseHandlesFromOtherThread)
    ]
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func retainedValueCrossesThreads(): String {
    let kept = ArkTSRuntime.run {
        let js = ArkTSRuntime.js
        let o = js.object()
        o["marker"] = js.string("crossed").toJSValue()
        ArkTSRuntime.retain(o.toJSValue())
    }
    let marker = ArkTSRuntime.run {
        unwrap(kept).asObject()["marker"].toString()
    }
    expectEqual("marker read in a later run", marker, "crossed")
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func releaseHandlesFromOtherThread(): String {
    for (i in 0..10000) {
        let kept = ArkTSRuntime.run {
            ArkTSRuntime.retain(ArkTSRuntime.js.object().toJSValue())
        }
        if (ArkTSRuntime.payloadKind(kept) != "Pin") {
            return "object ${i} not retained as Pin"
        }
    }
    gc(heavy: true)
    let text = ArkTSRuntime.run {
        ArkTSRuntime.js.string("still working").toJSValue().toString()
    }
    expectEqual("engine after release", text, "still working")
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func releaseManyHandles(js: JS): String {
    for (i in 0..100000) {
        let kept = ArkTSRuntime.environment.runtimeFrame {
            ArkTSRuntime.retain(js.object().toJSValue())
        }
        if (ArkTSRuntime.payloadKind(kept) != "Pin") {
            return "object ${i} not retained as Pin"
        }
    }
    gc(heavy: true)
    ""
}
