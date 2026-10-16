package arkts_runtime

import std.sync.Mutex
import std.sync.Condition
import ohos.ark_interop.JSContext
import ohos.ark_interop.JSValue
import ohos.ark_interop.JSKeyable
import ohos.ark_interop.Utf16String
import ohos.business_exception.BusinessException

/** `BusinessException.code` of an exception thrown by JS code ("Outside error occurred"). */
const JS_EXCEPTION_CODE: Int32 = 34300002

/** `BusinessException.code` of `ark_interop`'s "The accessing index is out of range". */
const INDEX_OUT_OF_RANGE_CODE: Int32 = 34300001

/** `BusinessException.code` of `ark_interop`'s "The ArkTS data types do not match". */
const TYPE_MISMATCH_CODE: Int32 = 34300005

/** Outcome of an operation run on the JS thread, carried back to the waiting thread. */
private enum ArkTSResult<R> {
    | Ok(R)
    | Err(Exception)
    | Failed(Error)
}

/** How an index is accessed: an array element, or a property key. */
private enum ArkTSIndex {
    | Element(Int64)
    | Key(JSKeyable)
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
     * or rethrows its exception or error on the calling thread. Blocks callers on other threads
     * until the JS thread has run it, so the JS thread must never wait for a thread that is
     * inside `run`. Public entry points call it exactly once; internal recursion never does.
     */
    static func run<R>(operation: () -> R): R {
        if (context.isInBindThread()) {
            // (a) already on JS thread: run immediately
            return context.newScope {
                translatingJSExceptions(operation)
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
                        translatingJSExceptions(operation)
                    }
                    ArkTSResult.Ok(res)
                } catch (e: Exception) {
                    ArkTSResult.Err(e)
                } catch (e: Error) {
                    ArkTSResult.Failed(e)
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
                case Failed(error) => throw error
            }
        }
    }

    /**
     * A JS throw reaches Cangjie as a `BusinessException` with code 34300002, whose message
     * holds the JS message and stack ("Outside error occurred, ArkTS exception, ..."); the JS
     * value itself is not available. It becomes a `ForeignRuntimeException` with that message.
     * Other `ark_interop` errors and our own exceptions pass through unchanged.
     */
    private static func translatingJSExceptions<R>(operation: () -> R): R {
        try {
            operation()
        } catch (e: BusinessException) {
            if (e.code == JS_EXCEPTION_CODE) {
                throw ForeignRuntimeException(e.message)
            }
            throw e
        }
    }

    /**
     * Evaluates a tree built by the compiler: one `run`, one engine scope, and only the final
     * result is retained. Payloads are already evaluated; derived constructors go through
     * `Extern.evalDerived`.
     */
    public static func eval(tree: Extern<ArkTSRuntime>): Extern<ArkTSRuntime> {
        match (tree) {
            case ExternPayload(_) => tree
            case ExternMemberAccess(target, field) =>
                run { ArkTSRuntime.retain(readMember(evalTree(target), field)) }
            case ExternIndexedAccess(target, index) =>
                run { ArkTSRuntime.retain(readIndex(evalTree(target), index)) }
            case ExternMemberUpdate(target, field, value) =>
                run { ArkTSRuntime.retain(evalMemberUpdate(target, field, value)) }
            case ExternIndexedUpdate(target, index, value) =>
                run { ArkTSRuntime.retain(evalIndexedUpdate(target, index, value)) }
            case ExternFunctionCall(callee, arguments) =>
                run { ArkTSRuntime.retain(call(callee, arguments)) }
            case ExternCompoundAssignment(_, _, _) => evalCompoundAssignment()
            case _ => Extern<ArkTSRuntime>.evalDerived(tree)
        }
    }

    /** The same operations as `eval`, recursively, without `run` or `retain`. Bind thread only. */
    static func evalTree(tree: Extern<ArkTSRuntime>): JSValue {
        match (tree) {
            case ExternPayload(handle) => ArkTSRuntime.evalPayload(handle)
            case ExternMemberAccess(target, field) =>
                readMember(evalTree(target), field)
            case ExternIndexedAccess(target, index) =>
                readIndex(evalTree(target), index)
            case ExternMemberUpdate(target, field, value) =>
                evalMemberUpdate(target, field, value)
            case ExternIndexedUpdate(target, index, value) =>
                evalIndexedUpdate(target, index, value)
            case ExternFunctionCall(callee, arguments) =>
                call(callee, arguments)
            case ExternCompoundAssignment(_, _, _) => evalCompoundAssignment()
            case _ =>
                evalTree(Extern<ArkTSRuntime>.evalDerived(tree))
        }
    }

    /*
     * Member and index access behave as in `ark_interop`: `getProperty` / `setProperty` work only
     * on objects, integer indices use `getElement` / `setElement`. Its "types do not match" and
     * "index out of range" errors become the `Extern` exceptions, with its message.
     */

    private static func readMember(receiver: JSValue, field: String): JSValue {
        try {
            receiver.getProperty(field)
        } catch (e: BusinessException) {
            throw memberError(e)
        }
    }

    private static func writeMember(receiver: JSValue, field: String, value: JSValue): Unit {
        try {
            receiver.setProperty(field, value)
        } catch (e: BusinessException) {
            throw memberError(e)
        }
    }

    private static func evalMemberUpdate(target: Extern<ArkTSRuntime>, field: String, value: Any): JSValue {
        let receiver = evalTree(target)
        writeMember(receiver, field, ArkTSRuntime.toJSValue(value))
        context.undefined().toJSValue()
    }

    private static func memberError(e: BusinessException): Exception {
        if (e.code == TYPE_MISMATCH_CODE) {
            return ExternMemberAccessException(e.message)
        }
        e
    }

    private static func indexError(e: BusinessException): Exception {
        if (e.code == TYPE_MISMATCH_CODE || e.code == INDEX_OUT_OF_RANGE_CODE) {
            return ExternIndexedAccessException(e.message)
        }
        e
    }

    private static func evalIndexedUpdate(target: Extern<ArkTSRuntime>, index: Any, value: Any): JSValue {
        let receiver = evalTree(target)
        writeIndex(receiver, index, value)
        context.undefined().toJSValue()
    }

    private static func readIndex(target: JSValue, index: Any): JSValue {
        let resolved = toIndex(index)
        try {
            match (resolved) {
                case Element(position) => target.getElement(position)
                case Key(key) => target.getProperty(key)
            }
        } catch (e: BusinessException) {
            throw indexError(e)
        }
    }

    /** Resolves the index before converting the value: target, index, value order. */
    private static func writeIndex(target: JSValue, index: Any, value: Any): Unit {
        let resolved = toIndex(index)
        let converted = ArkTSRuntime.toJSValue(value)
        try {
            match (resolved) {
                case Element(position) => target.setElement(position, converted)
                case Key(key) => target.setProperty(key, converted)
            }
        } catch (e: BusinessException) {
            throw indexError(e)
        }
    }

    /**
     * The Cangjie types `ark_interop` accepts: `Int64` is an element position; `String`,
     * `Utf16String` and `Float64` are property keys. An `Extern` (possibly unevaluated) holding
     * a number, a string or a symbol is a property key, the number as a `Float64`.
     */
    private static func toIndex(index: Any): ArkTSIndex {
        match (index) {
            case position: Int64 => Element(position)
            case name: String => Key(name)
            case number: Float64 => Key(number)
            case name: Utf16String => Key(name)
            case external: Extern<ArkTSRuntime> =>
                let value = evalTree(external)
                if (value.isNumber()) { return Key(value.toNumber()) }
                if (value.isString()) { return Key(value.asString()) }
                if (value.isSymbol()) { return Key(value.asSymbol()) }
                throw ExternIndexedAccessException("Unsupported ArkTS index type")
            case _ => throw ExternIndexedAccessException("Unsupported ArkTS index type")
        }
    }

    /** `this` is the target of a member or index callee, `undefined` otherwise; evaluated once. */
    private static func call(callee: Extern<ArkTSRuntime>, arguments: Array<Any>): JSValue {
        match (callee) {
            case ExternMemberAccess(receiver, field) =>
                let target = evalTree(receiver)
                invoke(readMember(target, field), arguments, target, "'${field}'")
            case ExternIndexedAccess(receiver, index) =>
                let target = evalTree(receiver)
                invoke(readIndex(target, index), arguments, target, "indexed value")
            case _ =>
                invoke(evalTree(callee), arguments, context.undefined().toJSValue(), "value")
        }
    }

    private static func invoke(function: JSValue, arguments: Array<Any>, thisArg: JSValue, what: String): JSValue {
        if (!function.isFunction()) {
            throw ExternFunctionAccessException("ArkTS ${what} is not a function")
        }
        let converted = Array<JSValue>(arguments.size) { i => ArkTSRuntime.toJSValue(arguments[i]) }
        function.asFunction().call(converted, thisArg: thisArg)
    }

    /** ArkTS does not support compound assignment (`e.f += 1`, `e[i] &&= v`, ...). */
    private static func evalCompoundAssignment(): Nothing {
        throw ExternCompoundAssignmentException("Compound assignment not supported in ArkTS foreign runtime!")
    }

    /**
     * Converts a Cangjie value to ArkTS (type mapping in `conversion.cj`). An `Extern` is
     * evaluated with `eval`, so an evaluated one is returned as is.
     */
    public static func toExtern<R>(value: R): Extern<ArkTSRuntime> {
        if (let Some(external) <- (value as Extern<ArkTSRuntime>)) {
            return eval(external)
        }
        run { ArkTSRuntime.retain(ArkTSRuntime.toJSValue(value)) }
    }

    /**
     * Evaluates `value` and reads it as `R`; wrong JS types throw `ExternConversionException`.
     * The compiler passes dynamic expressions already evaluated, so a number, boolean,
     * `undefined` or `null` arrives as an immediate: on the bind thread it is read without
     * `run`, since reading it creates no engine handle and runs no JS code. Read as an `Extern`,
     * `value` goes through `eval`, so an evaluated one is returned as is.
     */
    public static func fromExtern<R>(value: Extern<ArkTSRuntime>): R {
        if (let Some(immediate) <- ArkTSRuntime.immediateOf(value)) {
            if (context.isInBindThread()) {
                return ArkTSRuntime.fromJSValue<R>(immediate)
            }
        }
        match (None<R>) {
            case _: Option<Extern<ArkTSRuntime>> => return (eval(value) as R).getOrThrow()
            case _ => ()
        }
        run { ArkTSRuntime.fromJSValue<R>(evalTree(value)) }
    }
}
