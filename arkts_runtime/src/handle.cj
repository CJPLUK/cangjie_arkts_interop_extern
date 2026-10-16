package arkts_runtime

import ohos.ark_interop.*

/** What an evaluated `Extern<ArkTSRuntime>` holds inside its `ExternPayload`. */
private enum ArkTSHandle {
    | Imm(JSValue)      // undefined / null / boolean / number
    | Ref(JSHeapObject) // string / bigint / symbol / object (arrays too) / function / external
}

extend ArkTSRuntime {
    /**
     * Wraps a `JSValue` produced by the engine as an evaluated `Extern`. Heap values become
     * engine-global handles, so the result outlives the current scope. Bind thread only.
     */
    static func retain(value: JSValue): Extern<ArkTSRuntime> {
        // `JSType` constants are not patterns, hence `match` without a selector.
        let t = value.typeof()
        let handle = match {
            case t == JSType.NUMBER || t == JSType.UNDEFINED || t == JSType.NULL || t == JSType.BOOLEAN => Imm(value)
            case t == JSType.STRING => Ref(value.asString())
            case t == JSType.OBJECT => Ref(value.asObject())
            case t == JSType.FUNCTION => Ref(value.asFunction())
            case t == JSType.SYMBOL => Ref(value.asSymbol())
            case t == JSType.BIGINT => Ref(value.asBigInt())
            case t == JSType.EXTERNAL => Ref(value.asExternal())
            case _ => throw ExternConversionException("Unknown ArkTS value type ${t.toString()}")
        }
        Extern<ArkTSRuntime>.ExternPayload(handle)
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

    /** The `JSValue` of a payload holding an immediate, `None` for anything else. */
    static func immediateOf(value: Extern<ArkTSRuntime>): ?JSValue {
        match (value) {
            case ExternPayload(handle) => match (handle as ArkTSHandle) {
                case Some(Imm(immediate)) => immediate
                case _ => None
            }
            case _ => None
        }
    }

    /** Test hook: whether `a` and `b` are `Ref` payloads holding the same engine handle. */
    static func sameHandle(a: Extern<ArkTSRuntime>, b: Extern<ArkTSRuntime>): Bool {
        match ((a, b)) {
            case (ExternPayload(x), ExternPayload(y)) => match ((x as ArkTSHandle, y as ArkTSHandle)) {
                case (Some(Ref(p)), Some(Ref(q))) => refEq(p, q)
                case _ => false
            }
            case _ => false
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
