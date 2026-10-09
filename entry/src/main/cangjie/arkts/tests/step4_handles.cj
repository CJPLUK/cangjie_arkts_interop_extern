package ohos_app_cangjie_entry.arkts.tests

import std.runtime.gc
import ohos.ark_interop.*
import ohos_app_cangjie_entry.arkts.*

func step4Scenarios(): Array<(String, Scenario)> {
    [
        ("step4.retainClassifiesEachKind", retainClassifiesEachKind),
        ("step4.payloadRoundTrip", payloadRoundTrip),
        ("step4.retainedValueOutlivesScope", { context, _ => retainedValueOutlivesScope(context) }),
        ("step4.rejectsForeignPayload", { context, _ => rejectsForeignPayload(context) }),
        ("step4.keepObject", keepObject),
        ("step4.checkKeptObject", checkKeptObject),
        ("step4.dropKeptObject", { _, _ => dropKeptObject() }),
        ("step4.releaseManyHandles", { context, _ => releaseManyHandles(context) })
    ]
}

const FOREIGN_PAYLOAD = "Extern payload was not produced by ArkTSRuntime"

/** The JSValue held by an evaluated Extern, valid in the current scope. */
func unwrap(value: Extern<ArkTSRuntime>): JSValue {
    match (value) {
        case ExternPayload(handle) => ArkTSRuntime.evalPayload(handle)
        case _ => throw IllegalArgumentException("not an evaluated Extern")
    }
}

/**
 * One value of every JS kind, with the handle variant `retain` must pick. fixtures[0] is a
 * Rectangle created by ArkTS.
 */
func valuesOfEachKind(context: JSContext, fixtures: Array<JSValue>): Array<(String, JSValue, String)> {
    [
        ("undefined", context.undefined().toJSValue(), "Imm"),
        ("null", context.null().toJSValue(), "Imm"),
        ("boolean", context.boolean(true).toJSValue(), "Imm"),
        ("number", context.number(1.5).toJSValue(), "Imm"),
        ("string", context.string("héllo").toJSValue(), "Ref"),
        ("bigint", context.bigint(10).toJSValue(), "Ref"),
        ("symbol", context.symbol(description: "s").toJSValue(), "Ref"),
        ("object", context.object().toJSValue(), "Ref"),
        ("array", context.array([context.number(1.0).toJSValue()]).toJSValue(), "Ref"),
        ("function", context.function({ ctx, _ => ctx.undefined().toJSValue() }).toJSValue(), "Ref"),
        ("ArkTS class instance", fixture(fixtures, 0), "Ref")
    ]
}

func retainClassifiesEachKind(context: JSContext, fixtures: Array<JSValue>): String {
    firstFailure(valuesOfEachKind(context, fixtures).map({ entry =>
        let (name, value, kind) = entry
        expectEqual(name, ArkTSRuntime.handleKind(ArkTSRuntime.retain(value)), kind)
    }))
}

/** `evalPayload(retain(v))` is `v` itself (JS `===`). */
func payloadRoundTrip(context: JSContext, fixtures: Array<JSValue>): String {
    firstFailure(valuesOfEachKind(context, fixtures).map({ entry =>
        let (name, value, _) = entry
        expectEqual("${name} === after round trip", unwrap(ArkTSRuntime.retain(value)).strictEqual(value), true)
    }))
}

/** Values retained inside a scope stay usable after it closes and many others come and go. */
func retainedValueOutlivesScope(context: JSContext): String {
    let (keptObject, keptString) = context.newScope {
        let o = context.object()
        o["marker"] = context.string("kept").toJSValue()
        (ArkTSRuntime.retain(o.toJSValue()), ArkTSRuntime.retain(context.string("héllo 🦀").toJSValue()))
    }
    for (_ in 0..10000) {
        context.newScope {
            context.object()["junk"] = context.string("junk").toJSValue()
        }
    }
    gc(heavy: true)
    firstFailure([
        expectEqual("object marker", unwrap(keptObject).asObject()["marker"].toString(), "kept"),
        expectEqual("string", unwrap(keptString).toString(), "héllo 🦀")
    ])
}

/** Payloads not made by `retain` are rejected, including a bare JSValue. */
func rejectsForeignPayload(context: JSContext): String {
    let notOurs = Extern<ArkTSRuntime>.ExternPayload(42)
    firstFailure([
        expectThrows<ExternConversionException>("Int64 payload", FOREIGN_PAYLOAD,
            { => ArkTSRuntime.evalPayload(42) }),
        expectThrows<ExternConversionException>("bare JSValue payload", FOREIGN_PAYLOAD,
            { => ArkTSRuntime.evalPayload(context.number(1.0).toJSValue()) }),
        expectThrows<ExternConversionException>("ExternPayload(42)", FOREIGN_PAYLOAD,
            { => unwrap(notOurs) }),
        expectEqual("kind of ExternPayload(42)", ArkTSRuntime.handleKind(notOurs), "foreign payload"),
        expectEqual("kind of an unevaluated node",
            ArkTSRuntime.handleKind(Extern<ArkTSRuntime>.ExternMemberAccess(notOurs, "f")), "not a payload")
    ])
}

/**
 * The only strong reference to an ArkTS object between `step4.keepObject` and
 * `step4.dropKeptObject`; ArkTS holds just a `WeakRef`. Only touched on the JS thread.
 */
var keptObject: ?Extern<ArkTSRuntime> = None
/** fixtures[0] is a Rectangle that ArkTS will stop referring to. */
func keepObject(_: JSContext, fixtures: Array<JSValue>): String {
    keptObject = ArkTSRuntime.retain(fixture(fixtures, 0))
    ""
}

/**
 * fixtures[0] is the Rectangle read back from the `WeakRef` after collections: the kept
 * Extern must be that very object. Sets its width to 7 so ArkTS can check the effect.
 */
func checkKeptObject(context: JSContext, fixtures: Array<JSValue>): String {
    let kept = keptObject ?? return "step4.keepObject has not run"
    let result = expectEqual("kept === object behind the WeakRef", unwrap(kept).strictEqual(fixture(fixtures, 0)), true)
    unwrap(kept).asObject()["width"] = context.number(7.0).toJSValue()
    result
}

/** Drops the kept Extern and runs the Cangjie GC, so its global handle gets released. */
func dropKeptObject(): String {
    keptObject = None
    gc(heavy: true)
    ""
}

func step4OffThreadScenarios(): Array<(String, OffThreadScenario)> {
    [
        ("step4.retainedValueCrossesThreads", retainedValueCrossesThreads),
        ("step4.releaseHandlesFromOtherThread", releaseHandlesFromOtherThread)
    ]
}

/** A value retained in one `run` is held by a spawned thread and used in a later `run`. */
func retainedValueCrossesThreads(): String {
    let kept = ArkTSRuntime.run {
        let context = ArkTSRuntime.context
        let o = context.object()
        o["marker"] = context.string("crossed").toJSValue()
        ArkTSRuntime.retain(o.toJSValue())
    }
    let marker = ArkTSRuntime.run {
        unwrap(kept).asObject()["marker"].toString()
    }
    expectEqual("marker read in a later run", marker, "crossed")
}

/**
 * 10 000 handles retained on the JS thread are dropped on a spawned thread, so their
 * finalizers do not run on the JS thread; the engine keeps working afterwards.
 */
func releaseHandlesFromOtherThread(): String {
    for (i in 0..10000) {
        let kept = ArkTSRuntime.run {
            ArkTSRuntime.retain(ArkTSRuntime.context.object().toJSValue())
        }
        if (ArkTSRuntime.handleKind(kept) != "Ref") {
            return "object ${i} not retained as Ref"
        }
    }
    gc(heavy: true)
    let text = ArkTSRuntime.run {
        ArkTSRuntime.context.string("still working").toJSValue().toString()
    }
    expectEqual("engine after release", text, "still working")
}

/** Retains and drops 100 000 objects, each created in its own scope, then runs the Cangjie GC. */
func releaseManyHandles(context: JSContext): String {
    for (i in 0..100000) {
        let kept = context.newScope {
            ArkTSRuntime.retain(context.object().toJSValue())
        }
        if (ArkTSRuntime.handleKind(kept) != "Ref") {
            return "object ${i} not retained as Ref"
        }
    }
    gc(heavy: true)
    ""
}
