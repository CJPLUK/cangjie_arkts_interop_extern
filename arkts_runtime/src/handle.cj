package arkts_runtime

import ohos.ark_interop.*

/** What an `Extern<ArkTSRuntime>` made by the runtime holds as its payload. */
private enum ArkTSHandle {
    | Imm(JSValue)      // undefined / null / boolean / number
    | Ref(JSHeapObject) // string / bigint / symbol / object (arrays too) / function / external
    | Method(JSFunction, ArkTSHandle) // a function read as a member or element, with its receiver
}

extend ArkTSRuntime {
    /**
     * Wraps a `JSValue` produced by the engine as an `Extern`. Heap values become engine-global
     * handles, so the result outlives the current scope. A function read from `receiver` keeps
     * it, as the `this` of a later `functionCall`. Bind thread only.
     */
    static func retain(value: JSValue, receiver!: ?Extern<ArkTSRuntime> = None): Extern<ArkTSRuntime> {
        // `JSType` constants are not patterns, hence `match` without a selector.
        let t = value.typeof()
        let handle = match {
            case t == JSType.NUMBER || t == JSType.UNDEFINED || t == JSType.NULL || t == JSType.BOOLEAN => Imm(value)
            case t == JSType.STRING => Ref(value.asString())
            case t == JSType.OBJECT => Ref(value.asObject())
            case t == JSType.FUNCTION => match (receiver) {
                case Some(target) => Method(value.asFunction(), handleOf(target))
                case None => Ref(value.asFunction())
            }
            case t == JSType.SYMBOL => Ref(value.asSymbol())
            case t == JSType.BIGINT => Ref(value.asBigInt())
            case t == JSType.EXTERNAL => Ref(value.asExternal())
            case _ => throw ExternConversionException("Unknown ArkTS value type ${t.toString()}")
        }
        Extern<ArkTSRuntime>(handle)
    }

    /**
     * The `JSValue` held by an `Extern` made by `retain`, valid in the current scope; a method
     * gives its function. Throws `ExternConversionException` for any other payload. Bind thread only.
     */
    static func jsValueOf(value: Extern<ArkTSRuntime>): JSValue {
        evalPayload(Extern<ArkTSRuntime>.getPayload(value))
    }

    /** `jsValueOf` for a payload. */
    static func evalPayload(handle: Any): JSValue {
        match (handle as ArkTSHandle) {
            case Some(h) => valueOfHandle(h)
            case None => throw foreignPayload()
        }
    }

    /** The function and, for a method, its receiver. Bind thread only. */
    static func calleeOf(callee: Extern<ArkTSRuntime>): (JSValue, ?JSValue) {
        match (Extern<ArkTSRuntime>.getPayload(callee) as ArkTSHandle) {
            case Some(Method(function, receiver)) => (function.toJSValue(), valueOfHandle(receiver))
            case Some(h) => (valueOfHandle(h), None)
            case None => throw foreignPayload()
        }
    }

    private static func valueOfHandle(handle: ArkTSHandle): JSValue {
        match (handle) {
            case Imm(value) => value
            case Ref(owner) => owner.toJSValue()
            case Method(function, _) => function.toJSValue()
        }
    }

    private static func handleOf(value: Extern<ArkTSRuntime>): ArkTSHandle {
        match (Extern<ArkTSRuntime>.getPayload(value) as ArkTSHandle) {
            case Some(handle) => handle
            case None => throw foreignPayload()
        }
    }

    private static func foreignPayload(): ExternConversionException {
        ExternConversionException("Extern payload was not produced by ArkTSRuntime")
    }

    /** The `JSValue` of a payload holding an immediate, `None` for anything else. */
    static func immediateOf(value: Extern<ArkTSRuntime>): ?JSValue {
        match (Extern<ArkTSRuntime>.getPayload(value) as ArkTSHandle) {
            case Some(Imm(immediate)) => immediate
            case _ => None
        }
    }

    /** Test hook: whether `a` and `b` hold the same engine handle (a method's function). */
    static func sameHandle(a: Extern<ArkTSRuntime>, b: Extern<ArkTSRuntime>): Bool {
        match ((Extern<ArkTSRuntime>.getPayload(a) as ArkTSHandle, Extern<ArkTSRuntime>.getPayload(b) as ArkTSHandle)) {
            case (Some(Ref(p)), Some(Ref(q))) => refEq(p, q)
            case (Some(Method(p, _)), Some(Method(q, _))) => refEq(p, q)
            case _ => false
        }
    }

    /** Test hook: "Imm", "Ref" or "Method" for a payload made by `retain`, otherwise "foreign payload". */
    static func handleKind(value: Extern<ArkTSRuntime>): String {
        match (Extern<ArkTSRuntime>.getPayload(value) as ArkTSHandle) {
            case Some(Imm(_)) => "Imm"
            case Some(Ref(_)) => "Ref"
            case Some(Method(_, _)) => "Method"
            case None => "foreign payload"
        }
    }
}
