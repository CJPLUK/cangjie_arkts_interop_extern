package ohos_app_cangjie_entry

import ohos.ark_interop.*
import arkts_runtime.ArkTSRuntime

/**
 * Each operation keeps an ArkTS object (`target.a`) in a Cangjie value and drops it. The page
 * also measures the ArkTS heap after full collections around one run of each variant.
 */
func handleBenchmarks(): Array<Benchmark> {
    [
        Benchmark("handles.createAndDrop", 20000,
            { context: JSContext =>
                let t = interopTarget(context)
                { n: Int64 =>
                    for (_ in 0..n) {
                        let a = t.getProperty("a").asObject()
                        if (a.hasProperty("b")) { sink += 1.0 }
                    }
                }
            },
            { =>
                let t = runtimeTarget()
                { n: Int64 =>
                    for (_ in 0..n) {
                        let a = ArkTSRuntime.eval(t.a)
                        if (ArkTSRuntime.objectHasProperty(a, "b")) { sink += 1.0 }
                    }
                }
            }, false)
    ]
}
