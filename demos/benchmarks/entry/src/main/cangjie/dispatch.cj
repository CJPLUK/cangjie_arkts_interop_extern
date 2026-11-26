package ohos_app_cangjie_entry

import ohos.ark_interop.*
import arkts_runtime.bench.*

func dispatchCasesOf(context: JSContext, _: JSCallInfo): JSValue {
    let names = dispatchCaseNames()
    context.array(Array<JSValue>(names.size) { i => context.string(names[i]).toJSValue() }).toJSValue()
}

func timeDispatchOf(context: JSContext, info: JSCallInfo): JSValue {
    let caseName = info[0].toString()
    let variant = info[1].toString()
    let iterations = Int64(info[2].toNumber())
    let ns = timeDispatch(caseName, variant, iterations)
    context.number(Float64(ns)).toJSValue()
}
