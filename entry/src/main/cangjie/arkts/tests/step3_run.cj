package ohos_app_cangjie_entry.arkts.tests

import std.collection.*
import std.sync.*
import ohos.ark_interop.*
import ohos_app_cangjie_entry.arkts.*

func step3Scenarios(): Array<(String, Scenario)> {
    [
        ("step3.runOnJSThreadReturnsValue", { _, _ => runReturnsValue() }),
        ("step3.runOnJSThreadUsesEngine", { _, _ => runUsesEngine() }),
        ("step3.runOnJSThreadPropagatesException", { _, _ => runPropagatesException() }),
        ("step3.runOnJSThreadNested", { _, _ => runNested() })
    ]
}

// Each of these also runs on the JS thread above; here the caller is a spawned thread.
func step3OffThreadScenarios(): Array<(String, OffThreadScenario)> {
    [
        ("step3.runOffThreadReturnsValue", runReturnsValue),
        ("step3.runOffThreadUsesEngine", runUsesEngine),
        ("step3.runOffThreadRethrows", runPropagatesException),
        ("step3.runOffThreadNested", runNested),
        ("step3.runFromManyThreads", runFromManyThreads)
    ]
}

/** The value comes back, and the operation itself ran on the bind thread. */
func runReturnsValue(): String {
    let callerOnBindThread = ArkTSRuntime.context.isInBindThread()
    let (insideOnBindThread, value) = ArkTSRuntime.run {
        (ArkTSRuntime.context.isInBindThread(), 42)
    }
    firstFailure([
        expectEqual("value", value, 42),
        expectEqual("inside run on bind thread", insideOnBindThread, true),
        expectEqual("after run, caller on bind thread", ArkTSRuntime.context.isInBindThread(),
            callerOnBindThread)
    ])
}

/** Engine calls inside the operation work; they throw "Thread mismatch" off the JS thread. */
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

/** An operation that calls `run` again completes; the inner call is already on the bind thread. */
func runNested(): String {
    let value = ArkTSRuntime.run {
        ArkTSRuntime.run {
            (ArkTSRuntime.context.isInBindThread(), 7)
        }
    }
    firstFailure([
        expectEqual("inner value", value[1], 7),
        expectEqual("inner on bind thread", value[0], true)
    ])
}

/**
 * 16 threads call `run` 100 times each, returning their own id. Every result must match, and
 * operations must never overlap, since they all execute on the single JS thread.
 */
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
                let (onBindThread, result) = ArkTSRuntime.run {
                    if (active.fetchAdd(1) != 0) {
                        overlaps.fetchAdd(1)
                    }
                    let onBindThread = ArkTSRuntime.context.isInBindThread()
                    active.fetchSub(1)
                    (onBindThread, id)
                }
                if (result != id) {
                    return "thread ${id} call ${call}: got ${result}"
                }
                if (!onBindThread) {
                    return "thread ${id} call ${call}: operation not on bind thread"
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
