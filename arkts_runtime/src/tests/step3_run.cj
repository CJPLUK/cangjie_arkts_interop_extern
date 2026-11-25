package arkts_runtime.tests

import std.collection.*
import std.sync.*

import arkts_runtime.*

@When[bundle == "com.example.testArkTSForeignRuntime"]
func step3Scenarios(): Array<(String, Scenario)> {
    [
        ("step3.runOnJSThreadReturnsValue", { _, _ => runReturnsValue() }),
        ("step3.runOnJSThreadUsesEngine", { _, _ => runUsesEngine() }),
        ("step3.runOnJSThreadPropagatesException", { _, _ => runPropagatesException() }),
        ("step3.runOnJSThreadNested", { _, _ => runNested() }),
        ("step3.postRejectsReservedIds", { _, _ => postRejectsReservedIds() })
    ]
}

// Each of these also runs on the owner thread above; here the caller is a spawned thread.
@When[bundle == "com.example.testArkTSForeignRuntime"]
func step3OffThreadScenarios(): Array<(String, OffThreadScenario)> {
    [
        ("step3.runOffThreadReturnsValue", runReturnsValue),
        ("step3.runOffThreadUsesEngine", runUsesEngine),
        ("step3.runOffThreadRethrows", runPropagatesException),
        ("step3.runOffThreadRethrowsError", runOffThreadRethrowsError),
        ("step3.runOffThreadNested", runNested),
        ("step3.runFromManyThreads", runFromManyThreads)
    ]
}

/** The value comes back, and the operation itself ran on the owner thread. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func runReturnsValue(): String {
    let callerOnOwnerThread = ArkTSRuntime.context.isOnOwnerThread()
    let (insideOnOwnerThread, value) = ArkTSRuntime.run {
        (ArkTSRuntime.context.isOnOwnerThread(), 42)
    }
    firstFailure([
        expectEqual("value", value, 42),
        expectEqual("inside run on owner thread", insideOnOwnerThread, true),
        expectEqual("after run, caller on owner thread", ArkTSRuntime.context.isOnOwnerThread(),
            callerOnOwnerThread)
    ])
}

/** Engine calls inside the operation work; they throw "Thread mismatch" off the owner thread. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func runUsesEngine(): String {
    let text = ArkTSRuntime.run {
        let context = ArkTSRuntime.context
        let s = context.string("héllo 🦀").toJSValue()
        let n = context.number(2.5).toJSValue()
        "${s.toString()} ${n.toNumber()}"
    }
    expectEqual("values built and read in the engine", text, "héllo 🦀 2.500000")
}

/** The exact exception object thrown by the operation reaches the caller. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func runPropagatesException(): String {
    let thrown = IllegalStateException("thrown inside run")
    try {
        ArkTSRuntime.run<Unit> {
            throw thrown
        }
        "expected an exception, run returned normally"
    } catch (e: IllegalStateException) {
        firstFailure([
            expectEqual("same exception object", refEq(e, thrown), true),
            expectEqual("message", e.message, "thrown inside run")
        ])
    } catch (e: Exception) {
        "wrong exception '${e}'"
    }
}

/**
 * A Cangjie `Error` thrown by the operation reaches the caller, and `run` still works after
 * it. The caller waits with a timeout, so a lost error fails instead of hanging.
 */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func runOffThreadRethrowsError(): String {
    let caller = spawn {
        try {
            // Return the array across the dispatch boundary. Reading .size inside
            // the closure lets release optimization remove the allocation entirely.
            let impossible = ArkTSRuntime.run { Array<Int64>(Int64.Max / 16, repeat: 0) }
            "returned ${impossible.size}"
        } catch (e: Error) {
            e.toString()
        }
    }
    let outcome = try {
        caller.get(Duration.second * 10)
    } catch (_: TimeoutException) {
        "no result after 10 s"
    }
    firstFailure([
        expectEqual("error rethrown on the caller", outcome, "OutOfMemoryError"),
        expectEqual("run usable afterwards", ArkTSRuntime.run { 7 }, 7)
    ])
}

/** An operation that calls `run` again completes; the inner call is already on the owner thread. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func runNested(): String {
    let value = ArkTSRuntime.run {
        ArkTSRuntime.run {
            (ArkTSRuntime.context.isOnOwnerThread(), 7)
        }
    }
    firstFailure([
        expectEqual("inner value", value[1], 7),
        expectEqual("inner on owner thread", value[0], true)
    ])
}

/**
 * 16 threads call `run` 100 times each, returning their own id. Every result must match, and
 * operations must never overlap, since they all execute on the single owner thread.
 */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func runFromManyThreads(): String {
    let threads = 16
    let callsPerThread = 100
    let active = AtomicInt64(0)
    let overlaps = AtomicInt64(0)
    let start = Barrier(threads)
    let futures = ArrayList<Future<String>>()
    for (id in 0..threads) {
        futures.add(spawn {
            start.wait()
            for (call in 0..callsPerThread) {
                let (onOwnerThread, result) = ArkTSRuntime.run {
                    if (active.fetchAdd(1) != 0) {
                        overlaps.fetchAdd(1)
                    }
                    let onOwnerThread = ArkTSRuntime.context.isOnOwnerThread()
                    active.fetchSub(1)
                    (onOwnerThread, id)
                }
                if (result != id) {
                    return "thread ${id} call ${call}: got ${result}"
                }
                if (!onOwnerThread) {
                    return "thread ${id} call ${call}: operation not on owner thread"
                }
            }
            ""
        })
    }
    let failures = futures.toArray().map({ f => f.get() })
    firstFailure([
        firstFailure(failures),
        expectEqual("overlapping operations", overlaps.load(), 0)
    ])
}

/**
 * Ids below 1 belong to the runtime (the wake and the turn marker): the post entry point
 * rejects them without queueing anything, and `run` still works afterwards.
 */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func postRejectsReservedIds(): String {
    firstFailure([
        expectEqual("status for id 0", ArkTSRuntime.nativePost(0), NAPI_INVALID_ARG),
        expectEqual("status for id -1", ArkTSRuntime.nativePost(-1), NAPI_INVALID_ARG),
        expectEqual("status for Int64.Min", ArkTSRuntime.nativePost(Int64.Min), NAPI_INVALID_ARG),
        expectEqual("run usable afterwards", ArkTSRuntime.run { 7 }, 7)
    ])
}
