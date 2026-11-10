package arkts_runtime.tests

import std.sync.*

import arkts_runtime.*

// The runtime is bound when the module is registered, before any test runs, and binding is
// permanent: the unbound state cannot be observed here.
@When[bundle == "com.example.testArkTSForeignRuntime"]
func step2Scenarios(): Array<(String, Scenario)> {
    [
        ("step2.runtimeIsBound", { _, _ => runtimeIsBound() }),
        ("step2.runtimeBoundToCallerContext", runtimeBoundToCallerContext),
        ("step2.runtimeRebindThrows", runtimeRebindThrows),
        ("step2.concurrentRebindAllThrow", concurrentRebindAllThrow)
    ]
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
const ALREADY_BOUND = "ArkTS runtime is already associated with a host ArkTS environment"

/** index.cj binds the runtime when the module is registered. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func runtimeIsBound(): String {
    expectEqual("ArkTSRuntime.isBound()", ArkTSRuntime.isBound(), true)
}

/** The bound context is the engine this test is running in. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func runtimeBoundToCallerContext(context: NativeContext, _: Array<NativeJSValue>): String {
    let bound = ArkTSRuntime.context
    firstFailure([
        expectEqual("same global object", bound.global.toJSValue().strictEqual(context.global.toJSValue()), true),
        expectEqual("on bind thread", bound.isInBindThread(), true)
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func runtimeRebindThrows(context: NativeContext, _: Array<NativeJSValue>): String {
    let before = ArkTSRuntime.context
    firstFailure([
        expectThrows<ArkTSContextAlreadyBoundException>("bind again", ALREADY_BOUND,
            { => ArkTSRuntime.bind(context.session.env) }),
        expectEqual("still bound", ArkTSRuntime.isBound(), true),
        expectEqual("context unchanged", refEq(ArkTSRuntime.context, before), true)
    ])
}

/** 8 threads released together try to rebind; every one throws and the context is unchanged. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func concurrentRebindAllThrow(context: NativeContext, _: Array<NativeJSValue>): String {
    let env = context.session.env
    let threads = 8
    let before = ArkTSRuntime.context
    for (round in 0..50) {
        let barrier = Barrier(threads)
        let completed = SyncCounter(threads)
        let outcomes = Array<String>(threads, repeat: "worker did not complete")
        // Assert binding outcomes directly. Future.get() can itself report an
        // unexpected internal result under this SDK's concurrent completion race.
        for (index in 0..threads) {
            spawn {
                try {
                    barrier.wait()
                    try {
                        ArkTSRuntime.bind(env)
                        outcomes[index] = "a rebind succeeded"
                    } catch (_: ArkTSContextAlreadyBoundException) {
                        outcomes[index] = ""
                    } catch (e: Exception) {
                        outcomes[index] = "unexpected exception ${e}"
                    }
                } catch (e: Error) {
                    outcomes[index] = "unexpected error ${e}"
                } finally { completed.dec() }
            }
        }
        completed.waitUntilZero()
        for (outcome in outcomes) {
            if (!outcome.isEmpty()) { return "round ${round}: ${outcome}" }
        }
        if (!refEq(ArkTSRuntime.context, before)) {
            return "round ${round}: context changed"
        }
    }
    ""
}
