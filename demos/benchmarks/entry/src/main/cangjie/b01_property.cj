package ohos_app_cangjie_entry

import ohos.ark_interop.*
import arkts_runtime.ArkTSRuntime

func propertyBenchmarks(): Array<Benchmark> {
    [
        Benchmark("property.readNumber", 30000,
            { context: JSContext =>
                let t = interopTarget(context)
                { n: Int64 => for (_ in 0..n) { sink += t.getProperty("num").toNumber() } }
            },
            { =>
                let t = runtimeTarget()
                { n: Int64 => for (_ in 0..n) { sink += ArkTSRuntime.fromExtern<Float64>(t.num) } }
            }, false),
        Benchmark("property.writeNumber", 50000,
            { context: JSContext =>
                let t = interopTarget(context)
                { n: Int64 => for (_ in 0..n) { t.setProperty("num", context.number(1.5).toJSValue()) } }
            },
            { =>
                let t = runtimeTarget()
                { n: Int64 => for (_ in 0..n) { t.num = 1.5 } }
            }, false),
        Benchmark("property.readChain", 15000,
            { context: JSContext =>
                let t = interopTarget(context)
                { n: Int64 =>
                    for (_ in 0..n) {
                        sink += t.getProperty("a").asObject().getProperty("b").asObject().getProperty("c").asObject()
                            .getProperty("d").toNumber()
                    }
                }
            },
            { =>
                let t = runtimeTarget()
                { n: Int64 => for (_ in 0..n) { sink += ArkTSRuntime.fromExtern<Float64>(t.a.b.c.d) } }
            }, false)
    ]
}
