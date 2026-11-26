package ohos_app_cangjie_entry

import std.collection.ArrayList
import std.sync.Mutex
import std.time.MonoTime
import ohos.ark_interop.*
import arkts_runtime.ArkTSRuntime

// @report Every measured result is added here, so no variant can skip its work.
var sink: Float64 = 0.0

type TimedLoop = (Int64) -> Unit

class Benchmark {
    Benchmark(
        let name: String,
        let iterations: Int64,
        let prepareArkInterop: (JSContext) -> TimedLoop,
        let prepareArktsRuntime: () -> TimedLoop,
        let offThread: Bool
    ) {}
}

func allBenchmarks(): Array<Benchmark> {
    let groups = [propertyBenchmarks(), callBenchmarks(), arrayBenchmarks(), stringBenchmarks(),
        conversionBenchmarks(), sequenceBenchmarks(), callbackBenchmarks(), handleBenchmarks(),
        threadBenchmarks(), exceptionBenchmarks()]
    let all = ArrayList<Benchmark>()
    for (group in groups) {
        all.add(all: group)
    }
    all.toArray()
}

func find(name: String): Benchmark {
    for (benchmark in allBenchmarks()) {
        if (benchmark.name == name) {
            return benchmark
        }
    }
    throw IllegalArgumentException("unknown benchmark ${name}")
}

func benchmarkNames(context: JSContext, _: JSCallInfo): JSValue {
    let benchmarks = allBenchmarks()
    context.array(Array<JSValue>(benchmarks.size) { i => context.string(benchmarks[i].name).toJSValue() }).toJSValue()
}

func iterationsOf(context: JSContext, info: JSCallInfo): JSValue {
    context.number(Float64(find(info[0].toString()).iterations)).toJSValue()
}

func runBenchmark(context: JSContext, info: JSCallInfo): JSValue {
    let name = info[0].toString()
    let variant = info[1].toString()
    let done = info[2].asFunction()
    try {
        let benchmark = find(name)
        let loop = if (variant == "arkInterop") {
            benchmark.prepareArkInterop(context)
        } else {
            benchmark.prepareArktsRuntime()
        }
        if (benchmark.offThread) {
            spawn {
                let (ns, error) = try {
                    (elapsedNanoseconds { => loop(benchmark.iterations) }, "")
                } catch (e: Exception) {
                    (-1, e.toString())
                }
                context.postJSTask {
                    context.newScope { report(context, done, ns, error) }
                }
            }
        } else if (variant == "arkInterop") {
            let ns = context.newScope { elapsedNanoseconds { => loop(benchmark.iterations) } }
            report(context, done, ns, "")
        } else {
            report(context, done, elapsedNanoseconds { => loop(benchmark.iterations) }, "")
        }
    } catch (e: Exception) {
        report(context, done, -1, e.toString())
    }
    context.undefined().toJSValue()
}

func elapsedNanoseconds(body: () -> Unit): Int64 {
    let start = MonoTime.now()
    body()
    (MonoTime.now() - start).toNanoseconds()
}

func report(context: JSContext, done: JSFunction, ns: Int64, error: String): Unit {
    done.call([context.number(Float64(ns)).toJSValue(), context.string(error).toJSValue()])
}

// @report What an `ark_interop` user writes to run engine code from another thread: post it and wait.
func onJSThread<T>(context: JSContext, operation: () -> T): T {
    let result = Box(None<T>)
    let mutex = Mutex()
    let finished = synchronized(mutex) { mutex.condition() }
    context.postJSTask {
        let value = operation()
        synchronized(mutex) {
            result.value = Some(value)
            finished.notify()
        }
    }
    synchronized(mutex) {
        finished.waitUntil({ => result.value.isSome() })
        result.value.getOrThrow()
    }
}

func interopBench(context: JSContext): JSObject {
    context.global.getProperty("Bench").asObject()
}

func interopTarget(context: JSContext): JSObject {
    interopBench(context).getProperty("target").asObject()
}

func runtimeBench(): Extern<ArkTSRuntime> {
    ArkTSRuntime.global().Bench
}

func runtimeTarget(): Extern<ArkTSRuntime> {
    ArkTSRuntime.global().Bench.target
}
