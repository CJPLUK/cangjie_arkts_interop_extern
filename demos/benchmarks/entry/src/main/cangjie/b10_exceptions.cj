package ohos_app_cangjie_entry

import ohos.ark_interop.*
import ohos.business_exception.BusinessException
import arkts_runtime.ArkTSRuntime

/** ArkTS `thrower()` throws an `Error`; each operation calls it and catches the exception in Cangjie. */
func exceptionBenchmarks(): Array<Benchmark> {
    [
        Benchmark("exception.throwCatch", 2000,
            { context: JSContext =>
                let thrower = interopBench(context).getProperty("thrower").asFunction()
                { n: Int64 =>
                    for (_ in 0..n) {
                        try {
                            thrower.call()
                        } catch (_: BusinessException) {
                            sink += 1.0
                        }
                    }
                }
            },
            { =>
                let bench = runtimeBench()
                { n: Int64 =>
                    for (_ in 0..n) {
                        try {
                            bench.thrower()
                        } catch (_: ForeignRuntimeException) {
                            sink += 1.0
                        }
                    }
                }
            }, false)
    ]
}
