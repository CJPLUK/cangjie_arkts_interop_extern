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
import arkts_runtime.ArkTSRuntime

let EXPORT_MODULE = JSModule.registerModule {
    runtime, _ =>
    if (!ArkTSRuntime.isBound()) {
        ArkTSRuntime.bind(runtime)
    }
}

@HybridComponentEntry
@Component
class HelloView {
    @State
    var text: String = ""
    @State
    var counter: String = ""
    @State
    var running: Bool = false

    func sayHello(): Unit {
        running = true
        ArkTSRuntime.global().Hello.sayHello(ArkTSRuntime.function { args =>
            let n = ArkTSRuntime.fromExtern<Float64>(args[1])
            if (n < 0.0) {
                text = ""
                counter = ""
                running = false
            } else {
                text = ArkTSRuntime.fromExtern<String>(args[0])
                counter = "${Int64(n)}"
            }
            ArkTSRuntime.undefined()
        })
    }

    public func build() {
        Column {
            Text(text).fontSize(40).fontWeight(FontWeight.Bold)
            Text(counter).fontSize(60)
            Button("Say hello").enabled(!running).margin(top: 20.vp).onClick({ _ => sayHello() })
        }.width(100.percent).height(100.percent).justifyContent(FlexAlign.Center)
    }
}
