package arkts_runtime.tests

import std.sync.AtomicInt64
import ohos.ark_interop.*
import arkts_runtime.*

@When[bundle == "com.example.testArkTSForeignRuntime"]
func step10Scenarios(): Array<(String, Scenario)> {
    [
        ("step10.functionCalls", { _, f => functionCalls(f) }),
        ("step10.functionThrows", { _, f => functionThrows(f) })
    ]
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func step10OffThreadScenarios(): Array<(String, OffThreadScenario)> {
    [("step10.functionFromOtherThread", functionFromOtherThread)]
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
class Counter {
    var count = 0.0
}

/**
 * fixtures: sink. Stores Cangjie functions on the sink; ArkTS calls them (directly, through
 * `Array.prototype.map` and from a timer) and checks the results.
 */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func functionCalls(fixtures: Array<JSValue>): String {
    let sink = ext(fixtures, 0)
    sink.concat = ArkTSRuntime.function { args => to(from<String>(args[0]) + "|" + from<String>(args[1])) }
    sink.count = ArkTSRuntime.function { args => to(Float64(args.size)) }
    sink.width = ArkTSRuntime.function { args => args[0].width }
    sink.double = ArkTSRuntime.function { args => to(from<Float64>(args[0]) * 2.0) }
    sink.nothing = ArkTSRuntime.function { _ => ArkTSRuntime.undefined() }
    let counter = Counter()
    sink.next = ArkTSRuntime.function { _ =>
        counter.count += 1.0
        to(counter.count)
    }
    sink.later = ArkTSRuntime.function { args =>
        sink.laterArgument = args[0]
        ArkTSRuntime.undefined()
    }
    let f = ArkTSRuntime.function { args => to(from<Float64>(args[0]) + 1.0) }
    firstFailure([
        expectEqual("kind", from<String>(ArkTSRuntime.global().Object.prototype.toString.call(f)), "[object Function]"),
        expectEqual("called from Cangjie", from<Float64>(f(to(41.0))), 42.0)
    ])
}

/** fixtures: sink. `fails` throws a Cangjie exception; ArkTS records what it sees. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func functionThrows(fixtures: Array<JSValue>): String {
    let sink = ext(fixtures, 0)
    sink.fails = ArkTSRuntime.function { _ => throw IllegalStateException("cangjie boom") }
    ""
}

/**
 * A function created from a spawned thread and called from it: the body runs on the JS thread
 * (not the calling one) and the result comes back.
 */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func functionFromOtherThread(): String {
    let callers = AtomicInt64(0)
    let thisThread = Thread.currentThread.id
    let f = ArkTSRuntime.function { args =>
        if (Thread.currentThread.id != thisThread) { callers.fetchAdd(1) }
        to(from<Float64>(args[0]) * 3.0)
    }
    let result: Float64 = from<Float64>(f(to(2.0)))
    firstFailure([
        expectEqual("result", result, 6.0),
        expectEqual("body ran on another thread", callers.load(), 1)
    ])
}
