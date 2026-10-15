package ohos_app_cangjie_entry

import kit.ArkUI.Text
import kit.ArkUI.Button
import kit.ArkUI.Column
import kit.ArkUI.CustomView
import kit.ArkUI.LocalStorage
import kit.ArkUI.ObservedProperty
import kit.ArkUI.SubscriberManager
import kit.ArkUI.ViewStackProcessor
import kit.ArkUI.CJPageEntry
import kit.ArkUI.HybridComponentBase
import kit.ArkUI.FontWeight
import kit.ArkUI.FlexAlign
import kit.ArkUI.LengthProp
import ohos.arkui.state_macro_manage.State
import ohos.arkui.state_macro_manage.Component
import ohos.arkui.state_macro_manage.HybridComponentEntry
import ohos.ark_interop.JSModule
import ohos.ark_interop.JSContext
import ohos.ark_interop.JSCallInfo
import ohos.ark_interop.JSValue
import arkts_runtime.ArkTSRuntime

var api: ?Extern<ArkTSRuntime> = None

/**
 * init(): called once by the ArkTS page. `requireArkModule` only works while ArkTS is calling
 * into Cangjie (not while the module registers, nor from a Cangjie UI event).
 */
func initRectangle(runtime: JSContext, _: JSCallInfo): JSValue {
    api = ArkTSRuntime.requireArkModule("entry/src/main/ets/Rectangle")
    runtime.undefined().toJSValue()
}

let EXPORT_MODULE = JSModule.registerModule {
    runtime, exports =>
    if (!ArkTSRuntime.isBound()) {
        ArkTSRuntime.bind(runtime)
    }
    exports["init"] = runtime.function(initRectangle).toJSValue()
}

@HybridComponentEntry
@Component
class RectangleView {
    @State
    var result: String = ""
    @State
    var arkTSView: String = ""

    /** The design's section 1 example. */
    func runExample(): Unit {
        let api = api.getOrThrow()
        let blob = api.createRectangle()
        blob.width = 3.0
        blob.width = ArkTSRuntime.fromExtern<Float64>(blob.width) + 2.0
        let width: Float64 = ArkTSRuntime.fromExtern<Float64>(blob.width)
        let area: Float64 = ArkTSRuntime.fromExtern<Float64>(blob.area())
        result = "width ${Int64(width)}, area ${Int64(area)}"
        arkTSView = "ArkTS: ${ArkTSRuntime.fromExtern<String>(api.describe(blob))}"
    }

    public func build() {
        Column {
            Text(result).fontSize(40).fontWeight(FontWeight.Bold)
            Text(arkTSView).fontSize(30)
            Button("Run example").margin(top: 20.vp).onClick({ _ => runExample() })
        }.width(100.percent).height(100.percent).justifyContent(FlexAlign.Center)
    }
}
