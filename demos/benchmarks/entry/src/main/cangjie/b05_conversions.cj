package ohos_app_cangjie_entry

import ohos.ark_interop.*
import arkts_runtime.ArkTSRuntime

/** Each operation writes a Cangjie value to `target.slot` and reads it back as the same type. */
func conversionBenchmarks(): Array<Benchmark> {
    let numbers = Array<Float64>(1000) { i => Float64(i) }
    let nested = Array<Array<Float64>>(10) { i => Array<Float64>(100) { j => Float64(i * 100 + j) } }
    [
        Benchmark("convert.bool", 20000,
            { context: JSContext =>
                let t = interopTarget(context)
                { n: Int64 =>
                    for (_ in 0..n) {
                        t.setProperty("slot", context.boolean(true).toJSValue())
                        if (t.getProperty("slot").toBoolean()) { sink += 1.0 }
                    }
                }
            },
            { =>
                let t = runtimeTarget()
                { n: Int64 =>
                    for (_ in 0..n) {
                        t.slot = true
                        if (ArkTSRuntime.fromExtern<Bool>(t.slot)) { sink += 1.0 }
                    }
                }
            }, false),
        Benchmark("convert.string", 15000,
            { context: JSContext =>
                let t = interopTarget(context)
                { n: Int64 =>
                    for (_ in 0..n) {
                        t.setProperty("slot", context.string("abcdefghij").toJSValue())
                        sink += Float64(t.getProperty("slot").toString().size)
                    }
                }
            },
            { =>
                let t = runtimeTarget()
                { n: Int64 =>
                    for (_ in 0..n) {
                        t.slot = "abcdefghij"
                        sink += Float64(ArkTSRuntime.fromExtern<String>(t.slot).size)
                    }
                }
            }, false),
        Benchmark("convert.arrayFloat64", 100,
            { context: JSContext =>
                let t = interopTarget(context)
                { n: Int64 =>
                    for (_ in 0..n) {
                        let elements = Array<JSValue>(numbers.size) { i => context.number(numbers[i]).toJSValue() }
                        t.setProperty("slot", context.array(elements).toJSValue())
                        let back = t.getProperty("slot").asArray()
                        for (i in 0..back.size) { sink += back[i].toNumber() }
                    }
                }
            },
            { =>
                let t = runtimeTarget()
                { n: Int64 =>
                    for (_ in 0..n) {
                        t.slot = numbers
                        let back = ArkTSRuntime.fromExtern<Array<Float64>>(t.slot)
                        for (x in back) { sink += x }
                    }
                }
            }, false),
        Benchmark("convert.nestedArray", 100,
            { context: JSContext =>
                let t = interopTarget(context)
                { n: Int64 =>
                    for (_ in 0..n) {
                        let rows = Array<JSValue>(nested.size) { i =>
                            let row = nested[i]
                            context.array(Array<JSValue>(row.size) { j => context.number(row[j]).toJSValue() }).toJSValue()
                        }
                        t.setProperty("slot", context.array(rows).toJSValue())
                        let back = t.getProperty("slot").asArray()
                        for (i in 0..back.size) {
                            let row = back[i].asArray()
                            for (j in 0..row.size) { sink += row[j].toNumber() }
                        }
                    }
                }
            },
            { =>
                let t = runtimeTarget()
                { n: Int64 =>
                    for (_ in 0..n) {
                        t.slot = nested
                        for (row in ArkTSRuntime.fromExtern<Array<Array<Float64>>>(t.slot)) {
                            for (x in row) { sink += x }
                        }
                    }
                }
            }, false),
        Benchmark("convert.optionSome", 20000,
            { context: JSContext =>
                let t = interopTarget(context)
                { n: Int64 =>
                    for (_ in 0..n) {
                        t.setProperty("slot", context.number(1.5).toJSValue())
                        let v = t.getProperty("slot")
                        let back: ?Float64 = if (v.isUndefined() || v.isNull()) { None } else { v.toNumber() }
                        sink += back ?? 0.0
                    }
                }
            },
            { =>
                let t = runtimeTarget()
                { n: Int64 =>
                    for (_ in 0..n) {
                        t.slot = Some(1.5)
                        sink += ArkTSRuntime.fromExtern<?Float64>(t.slot) ?? 0.0
                    }
                }
            }, false),
        Benchmark("convert.optionNone", 20000,
            { context: JSContext =>
                let t = interopTarget(context)
                { n: Int64 =>
                    for (_ in 0..n) {
                        t.setProperty("slot", context.undefined().toJSValue())
                        let v = t.getProperty("slot")
                        let back: ?Float64 = if (v.isUndefined() || v.isNull()) { None } else { v.toNumber() }
                        sink += back ?? 1.0
                    }
                }
            },
            { =>
                let t = runtimeTarget()
                { n: Int64 =>
                    for (_ in 0..n) {
                        t.slot = None<Float64>
                        sink += ArkTSRuntime.fromExtern<?Float64>(t.slot) ?? 1.0
                    }
                }
            }, false)
    ]
}
