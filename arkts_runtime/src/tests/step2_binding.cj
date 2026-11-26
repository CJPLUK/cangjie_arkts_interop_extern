package arkts_runtime.tests

import std.sync.*

import arkts_runtime.*

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

@When[bundle == "com.example.testArkTSForeignRuntime"]
func runtimeIsBound(): String {
    expectEqual("ArkTSRuntime.isBound()", ArkTSRuntime.isBound(), true)
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func runtimeBoundToCallerContext(js: JS, _: Array<NativeJSValue>): String {
    let bound = ArkTSRuntime.js
    firstFailure([
        expectEqual("same global object", bound.global.toJSValue().strictEqual(js.global.toJSValue()), true),
        expectEqual("on owner thread", ArkTSRuntime.environment.isOnOwnerThread(), true)
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func runtimeRebindThrows(js: JS, _: Array<NativeJSValue>): String {
    let before = ArkTSRuntime.js
    firstFailure([
        expectThrows<ArkTSContextAlreadyBoundException>("bind again", ALREADY_BOUND,
            { => ArkTSRuntime.bind(ArkTSRuntime.environment.env) }),
        expectEqual("still bound", ArkTSRuntime.isBound(), true),
        expectEqual("binding unchanged", refEq(ArkTSRuntime.js, before), true)
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func concurrentRebindAllThrow(js: JS, _: Array<NativeJSValue>): String {
    let env = ArkTSRuntime.environment.env
    let threads = 8
    let before = ArkTSRuntime.js
    for (round in 0..50) {
        let outcomes = outcomesWithoutFutureGetBecauseOfSdkCompletionRace(threads) {
            try {
                ArkTSRuntime.bind(env)
                "a rebind succeeded"
            } catch (_: ArkTSContextAlreadyBoundException) {
                ""
            }
        }
        for (outcome in outcomes) {
            if (!outcome.isEmpty()) { return "round ${round}: ${outcome}" }
        }
        if (!refEq(ArkTSRuntime.js, before)) {
            return "round ${round}: binding changed"
        }
    }
    ""
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func outcomesWithoutFutureGetBecauseOfSdkCompletionRace(threads: Int64, worker: () -> String): Array<String> {
    let barrier = Barrier(threads)
    let completed = SyncCounter(threads)
    let outcomes = Array<String>(threads, repeat: "worker did not complete")
    for (index in 0..threads) {
        spawn {
            try {
                barrier.wait()
                outcomes[index] = worker()
            } catch (e: Exception) {
                outcomes[index] = "unexpected exception ${e}"
            } catch (e: Error) {
                outcomes[index] = "unexpected error ${e}"
            } finally { completed.dec() }
        }
    }
    completed.waitUntilZero()
    outcomes
}
