package ohos_app_cangjie_entry.arkts

import std.math.numeric.BigInt
import ohos.ark_interop.*

extend ArkTSRuntime {
    /**
     * Converts an assigned value, call argument or index leaf to a `JSValue`. An `Extern` is
     * reduced with `evalTree`, so it may be unevaluated. Bind thread only.
     */
    static func toJSValue(value: Any): JSValue {
        match (value) {
            case external: Extern<ArkTSRuntime> => evalTree(external)
            case boolean: Bool => context.boolean(boolean).toJSValue()
            case number: Int32 => context.number(number).toJSValue()
            case number: Float64 => context.number(number).toJSValue()
            case number: Int64 => context.bigint(number).toJSValue()
            case number: BigInt => context.bigint(number).toJSValue()
            case text: String => context.string(text).toJSValue()
            case _ => throw ExternConversionException("Unsupported conversion to ArkTS")
        }
    }
}
