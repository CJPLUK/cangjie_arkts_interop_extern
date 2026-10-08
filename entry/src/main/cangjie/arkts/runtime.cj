package ohos_app_cangjie_entry.arkts

import std.sync.Mutex
import std.sync.Condition
import ohos.ark_interop.JSContext

/** Outcome of an operation run on the JS thread, carried back to the waiting thread. */
private enum ArkTSResult<R> {
    | Ok(R)
    | Err(Exception)
}

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

    /**
     * Runs `operation` on the bind thread inside a fresh engine scope and returns its result,
     * or rethrows its exception on the calling thread. Blocks callers on other threads until
     * the JS thread has run it, so the JS thread must never wait for a thread that is inside
     * `run`. Public entry points call it exactly once; internal recursion never does.
     */
    static func run<R>(operation: () -> R): R {
        if (context.isInBindThread()) {
            // (a) already on JS thread: run immediately
            return context.newScope {
                operation()
            }
        }

        // (b) other thread: hand the work to the JS thread and block for its result
        let result = Box(None<ArkTSResult<R>>)
        let mutex = Mutex()
        let done: Condition
        synchronized(mutex) {
            done = mutex.condition()
        }

        context.postJSTask {
            let completed: ArkTSResult<R> =
                try {
                    let res = context.newScope {
                        operation()
                    }
                    ArkTSResult.Ok(res)
                } catch (e: Exception) {
                    ArkTSResult.Err(e)
                }
            synchronized(mutex) {
                result.value = Some(completed)
                done.notify()
            }
        }

        synchronized(mutex) {
            done.waitUntil({ => result.value.isSome() })
            match (result.value.getOrThrow()) {
                case Ok(value) => value
                case Err(error) => throw error
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
