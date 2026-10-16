package ohos_app_cangjie_entry

import ohos.ark_interop.*
import arkts_runtime.ArkTSRuntime

/** A string's length with `ark_interop`: there is no `length` on a string value, so read the text. */
func stringBenchmarks(): Array<Benchmark> {
    [
        Benchmark("string.length", 15000,
            { context: JSContext =>
                let t = interopTarget(context)
                { n: Int64 => for (_ in 0..n) { sink += Float64(t.getProperty("str").toString().size) } }
            },
            { =>
                let t = runtimeTarget()
                { n: Int64 => for (_ in 0..n) { sink += Float64(ArkTSRuntime.fromExtern<String>(t.str).size) } }
            }, false),
        Benchmark("string.readShort", 20000,
            { context: JSContext =>
                let t = interopTarget(context)
                { n: Int64 => for (_ in 0..n) { sink += Float64(t.getProperty("short").toString().size) } }
            },
            { =>
                let t = runtimeTarget()
                { n: Int64 => for (_ in 0..n) { sink += Float64(ArkTSRuntime.fromExtern<String>(t.short).size) } }
            }, false),
        Benchmark("string.readLong", 10000,
            { context: JSContext =>
                let t = interopTarget(context)
                { n: Int64 => for (_ in 0..n) { sink += Float64(t.getProperty("long").toString().size) } }
            },
            { =>
                let t = runtimeTarget()
                { n: Int64 => for (_ in 0..n) { sink += Float64(ArkTSRuntime.fromExtern<String>(t.long).size) } }
            }, false)
    ]
}
