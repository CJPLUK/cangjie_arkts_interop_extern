package ohos_app_cangjie_entry.arkts.tests

import std.collection.*
import std.sync.*
import ohos.ark_interop.*
import ohos_app_cangjie_entry.arkts.*

// The runtime is bound when the module is registered, before any test runs, and binding is
// permanent: the unbound state cannot be observed here.
func step2Scenarios(): Array<(String, Scenario)> {
    [
        ("step2.runtimeIsBound", { _, _ => runtimeIsBound() }),
        ("step2.runtimeBoundToCallerContext", runtimeBoundToCallerContext),
        ("step2.runtimeRebindThrows", runtimeRebindThrows),
        ("step2.concurrentRebindAllThrow", concurrentRebindAllThrow)
    ]
}

const ALREADY_BOUND = "ArkTS runtime is already associated with a host JSContext"

/** index.cj binds the runtime when the module is registered. */
func runtimeIsBound(): String {
    expectEqual("ArkTSRuntime.isBound()", ArkTSRuntime.isBound(), true)
}

/** The bound context is the engine this test is running in. */
func runtimeBoundToCallerContext(context: JSContext, _: Array<JSValue>): String {
    let bound = ArkTSRuntime.context
    firstFailure([
        expectEqual("same global object", bound.global.toJSValue().strictEqual(context.global.toJSValue()), true),
        expectEqual("on bind thread", bound.isInBindThread(), true)
    ])
}

func runtimeRebindThrows(context: JSContext, _: Array<JSValue>): String {
    let before = ArkTSRuntime.context
    firstFailure([
        expectThrows<ArkTSContextAlreadyBoundException>("bind again", ALREADY_BOUND,
            { => ArkTSRuntime.bind(context) }),
        expectEqual("still bound", ArkTSRuntime.isBound(), true),
        expectEqual("context unchanged", refEq(ArkTSRuntime.context, before), true)
    ])
}

/** 8 threads released together try to rebind; every one throws and the context is unchanged. */
func concurrentRebindAllThrow(context: JSContext, _: Array<JSValue>): String {
    let threads = 8
    let before = ArkTSRuntime.context
    for (round in 0..50) {
        let barrier = Barrier(threads)
        let futures = ArrayList<Future<Bool>>()
        for (_ in 0..threads) {
            futures.add(spawn {
                barrier.wait()
                try {
                    ArkTSRuntime.bind(context)
                    false
                } catch (_: ArkTSContextAlreadyBoundException) {
                    true
                }
            })
        }
        for (f in futures) {
            if (!f.get()) {
                return "round ${round}: a rebind succeeded"
            }
        }
        if (!refEq(ArkTSRuntime.context, before)) {
            return "round ${round}: context changed"
        }
    }
    ""
}
