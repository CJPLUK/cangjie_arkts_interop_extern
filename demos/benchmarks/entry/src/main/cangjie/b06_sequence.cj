package ohos_app_cangjie_entry

import ohos.ark_interop.*
import arkts_runtime.ArkTSRuntime

/** Consecutive statements: one operation is the whole sequence of writes. */
func sequenceBenchmarks(): Array<Benchmark> {
    [
        Benchmark("sequence.twoWrites", 25000,
            { context: JSContext =>
                let t = interopTarget(context)
                { n: Int64 =>
                    for (_ in 0..n) {
                        t.setProperty("x", context.number(1.0).toJSValue())
                        t.setProperty("y", context.number(2.0).toJSValue())
                    }
                }
            },
            { =>
                let t = runtimeTarget()
                { n: Int64 =>
                    for (_ in 0..n) {
                        t.x = 1.0
                        t.y = 2.0
                    }
                }
            }, false),
        Benchmark("sequence.threeWrites", 15000,
            { context: JSContext =>
                let t = interopTarget(context)
                { n: Int64 =>
                    for (_ in 0..n) {
                        t.setProperty("x", context.number(1.0).toJSValue())
                        t.setProperty("y", context.number(2.0).toJSValue())
                        t.setProperty("z", context.number(3.0).toJSValue())
                    }
                }
            },
            { =>
                let t = runtimeTarget()
                { n: Int64 =>
                    for (_ in 0..n) {
                        t.x = 1.0
                        t.y = 2.0
                        t.z = 3.0
                    }
                }
            }, false)
    ]
}
