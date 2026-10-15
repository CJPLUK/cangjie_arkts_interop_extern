package arkts_runtime

import std.sync.Mutex
import std.sync.Condition
import ohos.ark_interop.JSContext
import ohos.ark_interop.JSValue
import ohos.ark_interop.JSKeyable
import ohos.business_exception.BusinessException

/** `BusinessException.code` of an exception thrown by JS code ("Outside error occurred"). */
const JS_EXCEPTION_CODE: Int32 = 34300002

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

    private static func readMember(receiver: JSValue, field: String): JSValue {
        checkReceiver(receiver, "read", field)
        objectFor(receiver).getProperty(field)
    }

    private static func writeMember(receiver: JSValue, field: String, value: JSValue): Unit {
        checkReceiver(receiver, "set", field)
        if (isPrimitive(receiver)) {
            throw ExternMemberAccessException("Cannot set property '${field}' of a primitive ${typeName(receiver)}")
        }
        receiver.setProperty(field, value)
    }

    private static func evalMemberUpdate(target: Extern<ArkTSRuntime>, field: String, value: Any): JSValue {
        let receiver = evalTree(target)
        checkReceiver(receiver, "set", field)
        writeMember(receiver, field, ArkTSRuntime.toJSValue(value))
        context.undefined().toJSValue()
    }

    /** JS throws a TypeError for members of `undefined` and `null`. */
    private static func checkReceiver(receiver: JSValue, verb: String, field: String): Unit {
        if (receiver.isUndefined() || receiver.isNull()) {
            throw ExternMemberAccessException(
                "Cannot ${verb} property '${field}' of ${if (receiver.isNull()) { "null" } else { "undefined" }}")
        }
    }

    /** Strings, numbers, booleans, bigints and symbols; `undefined` and `null` are checked apart. */
    private static func isPrimitive(value: JSValue): Bool {
        value.isString() || value.isNumber() || value.isBoolean() || value.isBigInt() || value.isSymbol()
    }

    private static func typeName(value: JSValue): String {
        if (value.isString()) { "string" } else if (value.isNumber()) { "number" } else if (value.isBoolean()) {
            "boolean"
        } else if (value.isBigInt()) { "bigint" } else { "symbol" }
    }

    /**
     * Where to look up members: JS reads members of a primitive from its wrapper object
     * (`Object(value)`), while `getProperty` only accepts objects. Calls keep the primitive
     * itself as `this`.
     */
    private static func objectFor(value: JSValue): JSValue {
        if (isPrimitive(value)) {
            return context.global.getProperty("Object").asFunction().call([value])
        }
        value
    }

    /** JS `String(value)`; `JSValue.toString` only reads values that already are strings. */
    private static func jsString(value: JSValue): String {
        if (value.isString()) {
            return value.toString()
        }
        context.global.getProperty("String").asFunction().call([value]).toString()
    }

    private static func evalIndexedUpdate(target: Extern<ArkTSRuntime>, index: Any, value: Any): JSValue {
        let receiver = evalTree(target)
        writeIndex(receiver, index, value)
        context.undefined().toJSValue()
    }

    private static func readIndex(target: JSValue, index: Any): JSValue {
        readKey(target, toIndexKey(index))
    }

    /** Resolves the key before converting the value: target, index, value order. */
    private static func writeIndex(target: JSValue, index: Any, value: Any): Unit {
        let key = toIndexKey(index)
        writeKey(target, key, ArkTSRuntime.toJSValue(value))
    }

    private static func readKey(target: JSValue, key: JSKeyable): JSValue {
        checkIndexTarget(target)
        objectFor(target).getProperty(key)
    }

    private static func writeKey(target: JSValue, key: JSKeyable, value: JSValue): Unit {
        checkIndexTarget(target)
        if (isPrimitive(target)) {
            throw ExternIndexedAccessException("Cannot index-assign a primitive ${typeName(target)}")
        }
        target.setProperty(key, value)
    }

    private static func checkIndexTarget(target: JSValue): Unit {
        if (target.isUndefined() || target.isNull()) {
            throw ExternIndexedAccessException(
                "Cannot index ${if (target.isNull()) { "null" } else { "undefined" }}")
        }
    }

    /**
     * Integers and `String`s from Cangjie, or an `Extern` (possibly unevaluated) holding a string,
     * a symbol or a number. Numbers become property names (their JS string form), as JS does
     * for every index. `getElement` / `setElement` are not used: they throw past the end and at
     * negative indices, and `setElement(4294967295)` corrupts the array's `length`.
     */
    private static func toIndexKey(index: Any): JSKeyable {
        match (index) {
            case position: Int64 => "${position}"
            case position: Int32 => "${position}"
            case name: String => name
            case external: Extern<ArkTSRuntime> =>
                let value = evalTree(external)
                if (value.isString()) { return value.asString() }
                if (value.isSymbol()) { return value.asSymbol() }
                if (value.isNumber()) { return jsString(value) }
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

    /** Converts a Cangjie value to ArkTS (type mapping in `conversion.cj`). */
    public static func toExtern<R>(value: R): Extern<ArkTSRuntime> {
        run { ArkTSRuntime.retain(ArkTSRuntime.toJSValue(value)) }
    }

    /** Evaluates `value` and reads it as `R`; wrong JS types throw `ExternConversionException`. */
    public static func fromExtern<R>(value: Extern<ArkTSRuntime>): R {
        run { ArkTSRuntime.fromJSValue<R>(evalTree(value)) }
    }
}
