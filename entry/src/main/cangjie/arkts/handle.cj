package ohos_app_cangjie_entry.arkts

import ohos.ark_interop.*

/** What an evaluated `Extern<ArkTSRuntime>` holds inside its `ExternPayload`. */
private enum ArkTSHandle {
    | Imm(JSValue)      // undefined / null / boolean / number
    | Ref(JSHeapObject) // string / bigint / symbol / object / array / function / ...
}

extend ArkTSRuntime {
    /**
     * Wraps a `JSValue` produced by the engine as an evaluated `Extern`. Heap values become
     * engine-global handles, so the result outlives the current scope. Bind thread only.
     */
    static func retain(value: JSValue): Extern<ArkTSRuntime> {
        if (value.isFunction()) { return Extern<ArkTSRuntime>.ExternPayload(Ref(value.asFunction())) }
        if (value.isArray())    { return Extern<ArkTSRuntime>.ExternPayload(Ref(value.asArray())) }
        if (value.isSymbol())   { return Extern<ArkTSRuntime>.ExternPayload(Ref(value.asSymbol())) }
        if (value.isString())   { return Extern<ArkTSRuntime>.ExternPayload(Ref(value.asString())) }
        if (value.isBigInt())   { return Extern<ArkTSRuntime>.ExternPayload(Ref(value.asBigInt())) }
        if (value.isObject())   { return Extern<ArkTSRuntime>.ExternPayload(Ref(value.asObject())) }
        Extern<ArkTSRuntime>.ExternPayload(Imm(value))     // undefined / null / boolean / number: engine immediates
    }

    /**
     * The `JSValue` held by a payload made by `retain`, valid in the current scope. Throws
     * `ExternConversionException` for any other payload. Bind thread only.
     */
    static func evalPayload(handle: Any): JSValue {
        match (handle as ArkTSHandle) {
            case Some(Imm(value)) => value
            case Some(Ref(owner)) => owner.toJSValue()
            case None => throw ExternConversionException(
                "Extern payload was not produced by ArkTSRuntime")
        }
    }

    /** Test hook: "Imm" or "Ref" for a payload made by `retain`, otherwise a description. */
    static func handleKind(value: Extern<ArkTSRuntime>): String {
        match (value) {
            case ExternPayload(handle) => match (handle as ArkTSHandle) {
                case Some(Imm(_)) => "Imm"
                case Some(Ref(_)) => "Ref"
                case None => "foreign payload"
            }
            case _ => "not a payload"
        }
    }
}
