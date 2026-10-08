package ohos_app_cangjie_entry

import ohos.ark_interop.JSModule
import ohos.ark_interop.JSContext
import ohos.ark_interop.JSCallInfo
import ohos.ark_interop.JSValue
import ohos_app_cangjie_entry.arkts.tests.*

func testCJ(runtime: JSContext, callInfo: JSCallInfo): JSValue {
    let result = "Hello ${callInfo[0].toString()}"
    runtime.string(result).toJSValue()
}

/** runArkTSTest(name, ...fixtures): "" on success, otherwise a failure message. */
func runArkTSTest(runtime: JSContext, callInfo: JSCallInfo): JSValue {
    let name = callInfo[0].toString()
    let fixtures = Array<JSValue>(callInfo.count - 1) { i => callInfo[i + 1] }
    runtime.string(runScenario(runtime, name, fixtures)).toJSValue()
}

/** listArkTSTests(): names of all device scenarios. */
func listArkTSTests(runtime: JSContext, _: JSCallInfo): JSValue {
    let names = scenarioNames()
    runtime.array(Array<JSValue>(names.size) { i => runtime.string(names[i]).toJSValue() }).toJSValue()
}

let EXPORT_MODULE = JSModule.registerModule {
    runtime, exports =>
    exports["testCJ"] = runtime.function(testCJ).toJSValue()
    exports["runArkTSTest"] = runtime.function(runArkTSTest).toJSValue()
    exports["listArkTSTests"] = runtime.function(listArkTSTests).toJSValue()
}
