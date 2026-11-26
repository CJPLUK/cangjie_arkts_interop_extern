package ohos_app_cangjie_entry

import ohos.ark_interop.*
import arkts_runtime.ArkTSRuntime

// @report `property.readNumber` from a spawned thread: every operation is posted to the owner thread,
// @report with `postJSTask` for `ark_interop` and through the runtime's own queue for `arkts_runtime`.
func threadBenchmarks(): Array<Benchmark> {
    [
        Benchmark("thread.readNumber", 250,
            { context: JSContext =>
                let t = interopTarget(context)
                { n: Int64 =>
                    for (_ in 0..n) { sink += onJSThread(context) { => t.getProperty("num").toNumber() } }
                }
            },
            { =>
                let t = runtimeTarget()
                { n: Int64 => for (_ in 0..n) { sink += ArkTSRuntime.fromExtern<Float64>(t.num) } }
            }, true)
    ]
}
