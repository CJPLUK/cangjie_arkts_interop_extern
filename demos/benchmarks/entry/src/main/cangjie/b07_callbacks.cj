package ohos_app_cangjie_entry

import ohos.ark_interop.*
import arkts_runtime.ArkTSRuntime

/** ArkTS `callTimes(f, n)` calls the Cangjie function `f` `n` times; one operation is one call of `f`. */
func callbackBenchmarks(): Array<Benchmark> {
    [
        Benchmark("callback.arkTSCallsCangjie", 30000,
            { context: JSContext =>
                let callTimes = interopBench(context).getProperty("callTimes").asFunction()
                let f = context.function { c, info => c.number(info[0].toNumber() + 1.0).toJSValue() }
                { n: Int64 =>
                    sink += callTimes.call([f.toJSValue(), context.number(Float64(n)).toJSValue()]).toNumber()
                }
            },
            { =>
                let bench = runtimeBench()
                let f = ArkTSRuntime.function { args =>
                    ArkTSRuntime.toExtern(ArkTSRuntime.fromExtern<Float64>(args[0]) + 1.0)
                }
                { n: Int64 => sink += ArkTSRuntime.fromExtern<Float64>(bench.callTimes(f, Float64(n))) }
            }, false)
    ]
}
