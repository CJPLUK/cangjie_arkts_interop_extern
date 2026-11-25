package ohos_app_cangjie_entry

import ohos.ark_interop.*
import arkts_runtime.bench.*

/** `dispatchCases(): string[]`: the dispatch benchmark's cases (issue #7), in table order. */
func dispatchCasesOf(context: JSContext, _: JSCallInfo): JSValue {
    let names = dispatchCaseNames()
    context.array(Array<JSValue>(names.size) { i => context.string(names[i]).toJSValue() }).toJSValue()
}

/**
 * `timeDispatch(name: string, variant: 'probes' | 'reflective', iterations: number): number`:
 * one timed run, in nanoseconds, of reading case `name`'s value `iterations` times.
 */
func timeDispatchOf(context: JSContext, info: JSCallInfo): JSValue {
    let ns = timeDispatch(info[0].toString(), info[1].toString(), Int64(info[2].toNumber()))
    context.number(Float64(ns)).toJSValue()
}
