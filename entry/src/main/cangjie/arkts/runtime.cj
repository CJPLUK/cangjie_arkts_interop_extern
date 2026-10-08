package ohos_app_cangjie_entry.arkts

/**
 * The ArkTS foreign runtime: evaluates `Extern<ArkTSRuntime>` trees built by the compiler
 * from dynamic syntax (`e.f`, `e(...)`, `e[i]`, updates) and converts values between Cangjie
 * and ArkTS. Backed by `ohos.ark_interop`.
 *
 * All members are static; the class is never instantiated.
 */
public abstract class ArkTSRuntime <: ForeignRuntime<ArkTSRuntime> {
    public static func eval(tree: Extern<ArkTSRuntime>): Extern<ArkTSRuntime> {
        throw notImplemented("eval")
    }

    public static func toExtern<R>(value: R): Extern<ArkTSRuntime> {
        throw notImplemented("toExtern")
    }

    public static func fromExtern<R>(value: Extern<ArkTSRuntime>): R {
        throw notImplemented("fromExtern")
    }

    static func notImplemented(operation: String): ExternUnsupportedOperation {
        ExternUnsupportedOperation("ArkTSRuntime.${operation} is not implemented yet")
    }
}
