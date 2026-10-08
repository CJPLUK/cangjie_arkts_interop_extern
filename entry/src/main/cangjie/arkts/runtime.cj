package ohos_app_cangjie_entry.arkts

import std.sync.Mutex
import ohos.ark_interop.JSContext

/**
 * The ArkTS foreign runtime: evaluates `Extern<ArkTSRuntime>` trees built by the compiler
 * from dynamic syntax (`e.f`, `e(...)`, `e[i]`, updates) and converts values between Cangjie
 * and ArkTS. Backed by `ohos.ark_interop`.
 *
 * All members are static; the class is never instantiated.
 */
public abstract class ArkTSRuntime <: ForeignRuntime<ArkTSRuntime> {
    private static let contextMutex = Mutex()
    private static var context_: ?JSContext = None

    /**
     * Associates the runtime with the JS engine instance `newContext`. Only the first call
     * succeeds; every later call throws `ArkTSContextAlreadyBoundException`, even with the
     * same context.
     */
    public static func bind(newContext: JSContext): Unit {
        synchronized(contextMutex) {
            match (context_) {
                case None => context_ = Some(newContext)
                case Some(_) => throw ArkTSContextAlreadyBoundException(
                    "ArkTS runtime is already associated with a host JSContext")
            }
        }
    }

    public static func isBound(): Bool {
        context_.isSome()
    }

    /** The bound context; throws `ArkTSContextNotBoundException` before `bind`. */
    static prop context: JSContext {
        get() {
            match (context_) {
                case Some(context) => context
                case None => throw ArkTSContextNotBoundException(
                    "ArkTS runtime is not associated with a host JSContext")
            }
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
