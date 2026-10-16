package ohos_app_cangjie_entry

import ohos.ark_interop.*
import arkts_runtime.ArkTSRuntime

func callBenchmarks(): Array<Benchmark> {
    [
        Benchmark("call.method0", 20000,
            { context: JSContext =>
                let t = interopTarget(context)
                { n: Int64 => for (_ in 0..n) { sink += t.callMethod("m0", []).toNumber() } }
            },
            { =>
                let t = runtimeTarget()
                { n: Int64 => for (_ in 0..n) { sink += ArkTSRuntime.fromExtern<Float64>(t.m0()) } }
            }, false),
        Benchmark("call.method1", 15000,
            { context: JSContext =>
                let t = interopTarget(context)
                { n: Int64 =>
                    for (_ in 0..n) { sink += t.callMethod("m1", [context.number(1.0).toJSValue()]).toNumber() }
                }
            },
            { =>
                let t = runtimeTarget()
                { n: Int64 => for (_ in 0..n) { sink += ArkTSRuntime.fromExtern<Float64>(t.m1(1.0)) } }
            }, false),
        Benchmark("call.method3", 15000,
            { context: JSContext =>
                let t = interopTarget(context)
                { n: Int64 =>
                    for (_ in 0..n) {
                        let args = [context.number(1.0).toJSValue(), context.number(2.0).toJSValue(),
                            context.number(3.0).toJSValue()]
                        sink += t.callMethod("m3", args).toNumber()
                    }
                }
            },
            { =>
                let t = runtimeTarget()
                { n: Int64 => for (_ in 0..n) { sink += ArkTSRuntime.fromExtern<Float64>(t.m3(1.0, 2.0, 3.0)) } }
            }, false),
        Benchmark("call.function1", 25000,
            { context: JSContext =>
                let f = interopBench(context).getProperty("f1").asFunction()
                { n: Int64 => for (_ in 0..n) { sink += f.call([context.number(1.0).toJSValue()]).toNumber() } }
            },
            { =>
                let f = ArkTSRuntime.eval(runtimeBench().f1)
                { n: Int64 => for (_ in 0..n) { sink += ArkTSRuntime.fromExtern<Float64>(f(1.0)) } }
            }, false)
    ]
}
