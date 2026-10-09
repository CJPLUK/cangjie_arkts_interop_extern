package ohos_app_cangjie_entry.arkts

import std.sync.Mutex
import std.sync.Condition
import std.math.trunc
import ohos.ark_interop.JSContext
import ohos.ark_interop.JSValue
import ohos.ark_interop.JSKeyable

/** Outcome of an operation run on the JS thread, carried back to the waiting thread. */
private enum ArkTSResult<R> {
    | Ok(R)
    | Err(Exception)
}

/** A resolved index: an array element, or a property key. */
private enum IndexKey {
    | Element(Int64)
    | Property(JSKeyable)
}

/** 2^32 - 1: JS array indices are below it. */
private const MAX_ARRAY_INDEX = 4294967295.0

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
            case ExternCompoundAssignment(target, op, value) =>
                run { ArkTSRuntime.retain(evalCompoundAssignment(target, op, value)) }
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
            case ExternCompoundAssignment(target, op, value) =>
                evalCompoundAssignment(target, op, value)
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

    private static func readKey(target: JSValue, key: IndexKey): JSValue {
        checkIndexTarget(target)
        let lookup = objectFor(target)
        match (key) {
            case Element(position) where lookup.isArray() => lookup.getElement(position)
            case Element(position) => lookup.getProperty("${position}")
            case Property(name) => lookup.getProperty(name)
        }
    }

    private static func writeKey(target: JSValue, key: IndexKey, value: JSValue): Unit {
        checkIndexTarget(target)
        if (isPrimitive(target)) {
            throw ExternIndexedAccessException("Cannot index-assign a primitive ${typeName(target)}")
        }
        match (key) {
            case Element(position) where target.isArray() => target.setElement(position, value)
            case Element(position) => target.setProperty("${position}", value)
            case Property(name) => target.setProperty(name, value)
        }
    }

    private static func checkIndexTarget(target: JSValue): Unit {
        if (target.isUndefined() || target.isNull()) {
            throw ExternIndexedAccessException(
                "Cannot index ${if (target.isNull()) { "null" } else { "undefined" }}")
        }
    }

    /**
     * Integers and `String`s from Cangjie, or an `Extern` (possibly unevaluated) holding a string,
     * a symbol or a number. `JSKeyable` has no number key, so array indices become elements (read
     * with `getElement` on arrays, which is all it accepts) and other numbers property names (their
     * JS string form), as in JS.
     */
    private static func toIndexKey(index: Any): IndexKey {
        match (index) {
            case position: Int64 => integerKey(position)
            case position: Int32 => integerKey(Int64(position))
            case name: String => Property(name)
            case external: Extern<ArkTSRuntime> =>
                let value = evalTree(external)
                if (value.isString()) { return Property(value.asString()) }
                if (value.isSymbol()) { return Property(value.asSymbol()) }
                if (value.isNumber()) {
                    let n = value.toNumber()
                    if (n >= 0.0 && n < MAX_ARRAY_INDEX && n == trunc(n)) {
                        return Element(Int64(n))
                    }
                    return Property(jsString(value))
                }
                throw ExternIndexedAccessException("Unsupported ArkTS index type")
            case _ => throw ExternIndexedAccessException("Unsupported ArkTS index type")
        }
    }

    private static func integerKey(position: Int64): IndexKey {
        if (position >= 0 && Float64(position) < MAX_ARRAY_INDEX) { Element(position) } else { Property("${position}") }
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

    /**
     * `target op= value` with JS semantics: the receiver and key are evaluated once, the current
     * value is read, combined with `value` and written back; returns the new value. `&&=` and
     * `||=` short-circuit like JS: when they do, `value` is not evaluated and nothing is written.
     */
    private static func evalCompoundAssignment(target: Extern<ArkTSRuntime>, op: String, value: Any): JSValue {
        match (target) {
            case ExternMemberAccess(receiverTree, field) =>
                let receiver = evalTree(receiverTree)
                let current = readMember(receiver, field)
                match (combine(current, op, value)) {
                    case Some(result) =>
                        writeMember(receiver, field, result)
                        result
                    case None => current
                }
            case ExternIndexedAccess(receiverTree, index) =>
                let receiver = evalTree(receiverTree)
                let key = toIndexKey(index)
                let current = readKey(receiver, key)
                match (combine(current, op, value)) {
                    case Some(result) =>
                        writeKey(receiver, key, result)
                        result
                    case None => current
                }
            case _ => throw ExternCompoundAssignmentException(
                "ArkTS compound assignment needs a member or index target")
        }
    }

    /** The value to store, or `None` when `&&=` / `||=` short-circuits. */
    private static func combine(current: JSValue, op: String, value: Any): ?JSValue {
        match (op) {
            case "&&" => if (isTruthy(operand(current))) { Some(ArkTSRuntime.toJSValue(value)) } else { None }
            case "||" => if (isTruthy(operand(current))) { None } else { Some(ArkTSRuntime.toJSValue(value)) }
            case _ =>
                let right = ArkTSRuntime.toJSValue(value)
                if (op == "+" && (current.isString() || right.isString())) {
                    return Some(context.string(stringForm(current) + stringForm(right)).toJSValue())
                }
                match (applyOperator(op, operand(current), operand(right))) {
                    case Number(n) => Some(context.number(n).toJSValue())
                    case Big(n) => Some(context.bigint(n).toJSValue())
                    case _ => throw ExternCompoundAssignmentException("Unexpected result of '${op}='")
                }
        }
    }

    private static func operand(value: JSValue): JSOperand {
        if (value.isNumber()) { return Number(value.toNumber()) }
        if (value.isBigInt()) { return Big(value.toBigInt()) }
        if (value.isBoolean()) { return Boolean(value.toBoolean()) }
        if (value.isString()) { return Text(value.toString()) }
        if (value.isUndefined()) { return Undefined }
        if (value.isNull()) { return Null }
        Reference
    }

    /** JS ToString of a primitive, from the engine (number formatting differs from Cangjie). */
    private static func stringForm(value: JSValue): String {
        if (value.isString() || value.isNumber() || value.isBoolean() || value.isBigInt() || value.isUndefined() ||
            value.isNull()) {
            return jsString(value)
        }
        throw ExternCompoundAssignmentException("Unsupported operand for '+='")
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
