package ohos_app_cangjie_entry.arkts

import ohos.ark_interop.JSContext

/**
 * The ArkTS foreign runtime: evaluates `Extern<ArkTSRuntime>` trees built by the compiler
 * from dynamic syntax (`e.f`, `e(...)`, `e[i]`, updates) and converts values between Cangjie
 * and ArkTS. Backed by `ohos.ark_interop`.
 *
 * All members are static; the class is never instantiated.
 */
public abstract class ArkTSRuntime <: ForeignRuntime<ArkTSRuntime> {
    private static let contextCell = ContextCell<JSContext>()

    /**
     * Associates the runtime with the JS engine instance `newContext`. Only the first call
     * succeeds; every later call throws `ArkTSContextAlreadyBoundException`, even with the
     * same context.
     */
    public static func bind(newContext: JSContext): Unit {
        contextCell.bind(newContext)
    }

    public static func isBound(): Bool {
        contextCell.isBound()
    }

    /** The bound context; throws `ArkTSContextNotBoundException` before `bind`. */
    static prop context: JSContext {
        get() {
            contextCell.get()
        }
    }

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
