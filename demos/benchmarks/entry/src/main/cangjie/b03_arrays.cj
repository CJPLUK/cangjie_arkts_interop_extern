package ohos_app_cangjie_entry

import ohos.ark_interop.*
import arkts_runtime.ArkTSRuntime

func arrayBenchmarks(): Array<Benchmark> {
    [
        Benchmark("array.readElement", 30000,
            { context: JSContext =>
                let items = interopTarget(context).getProperty("items").asArray()
                { n: Int64 => for (i in 0..n) { sink += items[i % 1000].toNumber() } }
            },
            { =>
                let items = ArkTSRuntime.eval(runtimeTarget().items)
                { n: Int64 => for (i in 0..n) { sink += ArkTSRuntime.fromExtern<Float64>(items[i % 1000]) } }
            }, false),
        Benchmark("array.writeElement", 50000,
            { context: JSContext =>
                let items = interopTarget(context).getProperty("items").asArray()
                { n: Int64 =>
                    for (i in 0..n) { items[i % 1000] = context.number(Float64(i % 1000) * 0.5).toJSValue() }
                }
            },
            { =>
                let items = ArkTSRuntime.eval(runtimeTarget().items)
                { n: Int64 => for (i in 0..n) { items[i % 1000] = Float64(i % 1000) * 0.5 } }
            }, false),
        Benchmark("array.loop1000", 30,
            { context: JSContext =>
                let items = interopTarget(context).getProperty("items").asArray()
                { n: Int64 =>
                    for (_ in 0..n) {
                        for (j in 0..1000) { sink += items[j].toNumber() }
                    }
                }
            },
            { =>
                let items = ArkTSRuntime.eval(runtimeTarget().items)
                { n: Int64 =>
                    for (_ in 0..n) {
                        for (j in 0..1000) { sink += ArkTSRuntime.fromExtern<Float64>(items[j]) }
                    }
                }
            }, false)
    ]
}
