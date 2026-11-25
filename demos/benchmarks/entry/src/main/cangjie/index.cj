package ohos_app_cangjie_entry

import ohos.ark_interop.JSModule
import arkts_runtime.ArkTSRuntime

let EXPORT_MODULE = JSModule.registerModule {
    context, exports =>
    if (!ArkTSRuntime.isBound()) {
        ArkTSRuntime.bind(context.getNapiEnv())
    }
    exports["benchmarkNames"] = context.function(benchmarkNames).toJSValue()
    exports["iterations"] = context.function(iterationsOf).toJSValue()
    exports["runBenchmark"] = context.function(runBenchmark).toJSValue()
    exports["dispatchCases"] = context.function(dispatchCasesOf).toJSValue()
    exports["timeDispatch"] = context.function(timeDispatchOf).toJSValue()
}
