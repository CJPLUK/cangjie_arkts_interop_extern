package arkts_runtime

import std.math.numeric.BigInt
import std.sync.Mutex

/** `ArkTSNativeException.code` of an exception thrown by JS code ("Outside error occurred"). */
const JS_EXCEPTION_CODE: Int32 = 34300002

/** `ArkTSNativeException.code` of `ark_interop`'s "The accessing index is out of range". */
const INDEX_OUT_OF_RANGE_CODE: Int32 = 34300001

/** `ArkTSNativeException.code` of `ark_interop`'s "The ArkTS data types do not match". */
const TYPE_MISMATCH_CODE: Int32 = 34300005

/** What an `Extern<ArkTSRuntime>` made by the runtime holds as its payload. */
private enum ArkTSHandle {
    | Imm(NativeJSValue)      // undefined / null / boolean / number
    | Ref(NativeReference) // string / bigint / symbol / object (arrays too) / function / external
    | Method(NativeReference, ArkTSHandle) // a function read as a member or element, with its receiver
}

/** How an index is accessed: an array element, or a property key. */
private enum ArkTSIndex {
    | Element(Int64)
    | Key(NativeJSValue)
}

/**
 * The ArkTS foreign runtime: runs the operations the compiler generates for dynamic syntax on
 * `Extern<ArkTSRuntime>` (`e.f`, `e(...)`, `e[i]`, updates), one `run` each, and converts values
 * between Cangjie and ArkTS. Backed directly by the host N-API C interface.
 *
 * All members are static; the class is never instantiated.
 */
public abstract class ArkTSRuntime <: ForeignRuntime<ArkTSRuntime> {
    private static let contextMutex = Mutex()
    private static var context_: ?NativeContext = None

    /**
     * Associates the runtime with the JS engine instance `env`. Only the first call
     * succeeds; every later call throws `ArkTSContextAlreadyBoundException`, even with the
     * same context.
     */
    public static func bind(env: CPointer<Unit>): Unit {
        synchronized(contextMutex) {
            match (context_) {
                case None => context_ = Some(NativeContext(env))
                case Some(_) => throw ArkTSContextAlreadyBoundException(
                    "ArkTS runtime is already associated with a host ArkTS environment")
            }
        }
    }

    public static func isBound(): Bool {
        context_.isSome()
    }

    /** The bound context; throws `ArkTSContextNotBoundException` before `bind`. */
    static prop context: NativeContext {
        get() {
            match (context_) {
                case Some(context) => context
                case None => throw ArkTSContextNotBoundException(
                    "ArkTS runtime is not associated with a host ArkTS environment")
            }
        }
    }

    /** The `undefined` the runtime returns and passes, built on first use. Bind thread only. */
    private static var undefined_: ?(NativeJSValue, Extern<ArkTSRuntime>) = None

    private static func undefinedPair(): (NativeJSValue, Extern<ArkTSRuntime>) {
        match (undefined_) {
            case Some(pair) => pair
            case None =>
                let value = context.undefined().toJSValue()
                let pair = (value, ArkTSRuntime.retain(value))
                undefined_ = Some(pair)
                pair
        }
    }

    /** ArkTS `undefined`, shared by the whole runtime. Bind thread only. */
    static prop undefinedValue: NativeJSValue {
        get() { undefinedPair()[0] }
    }

    /** `undefinedValue` as an `Extern`, shared by the whole runtime. Bind thread only. */
    static prop undefinedExtern: Extern<ArkTSRuntime> {
        get() { undefinedPair()[1] }
    }

    /**
     * Runs `operation` on the bind thread inside a fresh engine scope and returns its result,
     * or rethrows its exception or error on the calling thread. Blocks callers on other threads
     * until the JS thread has run it, so the JS thread must never wait for a thread that is
     * inside `run`. Public entry points call it exactly once; internal recursion never does.
     */
    static func run<R>(operation: () -> R): R {
        context.session.run { translatingJSExceptions(operation) }
    }

    /**
     * A JS throw reaches Cangjie as an `ArkTSNativeException` with code 34300002, whose message
     * holds the JS message and stack ("Outside error occurred, ArkTS exception, ..."); the JS
     * exception is cleared before translating it to `ForeignRuntimeException`.
     * Other native backend errors and our own exceptions pass through unchanged.
     */
    private static func translatingJSExceptions<R>(operation: () -> R): R {
        try {
            operation()
        } catch (e: ArkTSNativeException) {
            if (e.code == JS_EXCEPTION_CODE) {
                throw ForeignRuntimeException(e.message)
            }
            throw e
        }
    }

    /** `e.f`. A function keeps `e` as the `this` of a later `functionCall`. */
    public static func memberAccess(e: Extern<ArkTSRuntime>, field: String): Extern<ArkTSRuntime> {
        run { ArkTSRuntime.retain(readMember(ArkTSRuntime.jsValueOf(e), field), receiver: e) }
    }

    /** `e[arg]`. A function keeps `e` as the `this` of a later `functionCall`. */
    public static func indexedAccess(e: Extern<ArkTSRuntime>, arg: Any): Extern<ArkTSRuntime> {
        run { ArkTSRuntime.retain(readIndex(ArkTSRuntime.jsValueOf(e), arg), receiver: e) }
    }

    /** `e.f = value`. */
    public static func memberUpdate(e: Extern<ArkTSRuntime>, field: String, value: Any): Unit {
        run { writeMember(ArkTSRuntime.jsValueOf(e), field, ArkTSRuntime.toJSValue(value)) }
    }

    /** `e[field] = value`. */
    public static func indexedUpdate(e: Extern<ArkTSRuntime>, field: Any, value: Any): Unit {
        run { writeIndex(ArkTSRuntime.jsValueOf(e), field, value) }
    }

    /**
     * `e(args)`. `this` is the receiver a member or element read kept, `undefined` for any
     * other function.
     */
    public static func functionCall(e: Extern<ArkTSRuntime>, args: Array<Any>): Extern<ArkTSRuntime> {
        run {
            let (function, receiver) = ArkTSRuntime.calleeOf(e)
            ArkTSRuntime.retain(invoke(function, args, receiver ?? undefinedValue))
        }
    }

    /*
     * Member and index access behave as in `ark_interop`: `getProperty` / `setProperty` work only
     * on objects, integer indices use `getElement` / `setElement`. Its "types do not match" and
     * "index out of range" errors become the `Extern` exceptions, with its message.
     */

    private static func readMember(receiver: NativeJSValue, field: String): NativeJSValue {
        try {
            receiver.getProperty(field)
        } catch (e: ArkTSNativeException) {
            throw memberError(e)
        }
    }

    private static func writeMember(receiver: NativeJSValue, field: String, value: NativeJSValue): Unit {
        try {
            receiver.setProperty(field, value)
        } catch (e: ArkTSNativeException) {
            throw memberError(e)
        }
    }

    static func memberError(e: ArkTSNativeException): Exception {
        if (e.code == TYPE_MISMATCH_CODE) {
            return ExternMemberAccessException(e.message)
        }
        e
    }

    private static func indexError(e: ArkTSNativeException): Exception {
        if (e.code == TYPE_MISMATCH_CODE || e.code == INDEX_OUT_OF_RANGE_CODE) {
            return ExternIndexedAccessException(e.message)
        }
        e
    }

    private static func readIndex(target: NativeJSValue, index: Any): NativeJSValue {
        let resolved = toIndex(index)
        try {
            match (resolved) {
                case Element(position) => target.getElement(position)
                case Key(key) => target.getProperty(key)
            }
        } catch (e: ArkTSNativeException) {
            throw indexError(e)
        }
    }

    /** Resolves the index before converting the value: target, index, value order. */
    private static func writeIndex(target: NativeJSValue, index: Any, value: Any): Unit {
        let resolved = toIndex(index)
        let converted = ArkTSRuntime.toJSValue(value)
        try {
            match (resolved) {
                case Element(position) => target.setElement(position, converted)
                case Key(key) => target.setProperty(key, converted)
            }
        } catch (e: ArkTSNativeException) {
            throw indexError(e)
        }
    }

    /**
     * The Cangjie types `ark_interop` accepts: `Int64` is an element position; `String`,
     * `Utf16String` and `Float64` are property keys. An `Extern` holding a number, a string or a
     * symbol is a property key, the number as a `Float64`.
     */
    private static func toIndex(index: Any): ArkTSIndex {
        match (index) {
            case position: Int64 => Element(position)
            case name: String => Key(context.string(name))
            case number: Float64 => Key(context.number(number))
            case name: Utf16String => Key(context.string(name))
            case external: Extern<ArkTSRuntime> =>
                let value = ArkTSRuntime.jsValueOf(external)
                let t = value.typeof()
                match {
                    case t == JSType.NUMBER => Key(context.number(value.toNumber()))
                    case t == JSType.STRING => Key(value.asString())
                    case t == JSType.SYMBOL => Key(value.asSymbol())
                    case _ => throw ExternIndexedAccessException("Unsupported ArkTS index type")
                }
            case _ => throw ExternIndexedAccessException("Unsupported ArkTS index type")
        }
    }

    private static func invoke(function: NativeJSValue, arguments: Array<Any>, thisArg: NativeJSValue): NativeJSValue {
        if (!function.isFunction()) {
            throw ExternFunctionAccessException("ArkTS value is not a function")
        }
        let converted = Array<NativeJSValue>(arguments.size) { i => ArkTSRuntime.toJSValue(arguments[i]) }
        function.asFunction().call(converted, thisArg: thisArg)
    }

    /**
     * Converts a Cangjie value to ArkTS (type mapping in `conversion.cj`). An `Extern` is
     * returned as is.
     */
    public static func toExtern<R>(value: R): Extern<ArkTSRuntime> {
        if (let Some(external) <- (value as Extern<ArkTSRuntime>)) {
            return external
        }
        run { ArkTSRuntime.retain(ArkTSRuntime.toJSValue(value)) }
    }

    /** These readers touch only copied payloads for immediate JS values, including type errors. */
    private static func isCopiedScalarReader<R>(): Bool {
        match (None<R>) {
            case _: Option<Float64> => true
            case _: Option<Float32> => true
            case _: Option<Float16> => true
            case _: Option<Bool> => true
            case _: Option<Int8> => true
            case _: Option<Int16> => true
            case _: Option<Int32> => true
            case _: Option<Int64> => true
            case _: Option<UInt8> => true
            case _: Option<UInt16> => true
            case _: Option<UInt32> => true
            case _: Option<UInt64> => true
            case _: Option<String> => true
            case _: Option<BigInt> => true
            case _: Option<Unit> => true
            case _ => false
        }
    }

    /**
     * Reads `value` as `R`; wrong JS types throw `ExternConversionException`. A number, boolean,
     * `undefined` or `null` is an immediate: scalar readers can use its copied payload on
     * any thread without `run`. Off-thread reads still reject a destroyed environment.
     * Readers requiring VM operations retain dispatch. Read as an `Extern`, `value` is
     * returned as is.
     */
    public static func fromExtern<R>(value: Extern<ArkTSRuntime>): R {
        if (let Some(immediate) <- ArkTSRuntime.immediateOf(value)) {
            if (context.isInBindThread()) {
                return ArkTSRuntime.fromJSValue<R>(immediate)
            }
            if (isCopiedScalarReader<R>()) {
                context.session.checkAlive()
                return ArkTSRuntime.fromJSValue<R>(immediate)
            }
        }
        match (None<R>) {
            case _: Option<Extern<ArkTSRuntime>> => return (value as R).getOrThrow()
            case _ => ()
        }
        run { ArkTSRuntime.fromJSValue<R>(ArkTSRuntime.jsValueOf(value)) }
    }

    /**
     * Wraps a `NativeJSValue` produced by the engine as an `Extern`. Heap values become engine-global
     * handles, so the result outlives the current scope. A function read from `receiver` keeps
     * it, as the `this` of a later `functionCall`. Bind thread only.
     */
    static func retain(value: NativeJSValue, receiver!: ?Extern<ArkTSRuntime> = None): Extern<ArkTSRuntime> {
        // `JSType` constants are not patterns, hence `match` without a selector.
        let t = value.typeof()
        let handle = match {
            case t == JSType.NUMBER || t == JSType.UNDEFINED || t == JSType.NULL || t == JSType.BOOLEAN => Imm(value)
            case t == JSType.STRING => Ref(NativeReference(value))
            case t == JSType.OBJECT => Ref(NativeReference(value))
            case t == JSType.FUNCTION => match (receiver) {
                case Some(target) => Method(NativeReference(value), handleOf(target))
                case None => Ref(NativeReference(value))
            }
            case t == JSType.SYMBOL => Ref(NativeReference(value))
            case t == JSType.BIGINT => Ref(NativeReference(value))
            case t == JSType.EXTERNAL => Ref(NativeReference(value))
            case _ => throw ExternConversionException("Unknown ArkTS value type ${t.toString()}")
        }
        Extern<ArkTSRuntime>(handle)
    }

    /**
     * The `NativeJSValue` held by an `Extern` made by `retain`, valid in the current scope; a method
     * gives its function. Throws `ExternConversionException` for any other payload. Bind thread only.
     */
    static func jsValueOf(value: Extern<ArkTSRuntime>): NativeJSValue {
        evalPayload(Extern<ArkTSRuntime>.getPayload(value))
    }

    /** `jsValueOf` for a payload. */
    static func evalPayload(handle: Any): NativeJSValue {
        match (handle as ArkTSHandle) {
            case Some(h) => valueOfHandle(h)
            case None => throw foreignPayload()
        }
    }

    /** The function and, for a method, its receiver. Bind thread only. */
    static func calleeOf(callee: Extern<ArkTSRuntime>): (NativeJSValue, ?NativeJSValue) {
        match (Extern<ArkTSRuntime>.getPayload(callee) as ArkTSHandle) {
            case Some(Method(function, receiver)) => (function.toJSValue(), valueOfHandle(receiver))
            case Some(h) => (valueOfHandle(h), None)
            case None => throw foreignPayload()
        }
    }

    private static func valueOfHandle(handle: ArkTSHandle): NativeJSValue {
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

    /** The `NativeJSValue` of a payload holding an immediate, `None` for anything else. */
    static func immediateOf(value: Extern<ArkTSRuntime>): ?NativeJSValue {
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

    /**
     * Converts an assigned value, call argument or array element to a `NativeJSValue`. An `Extern`
     * gives the value it holds (a method its function). Bind thread only.
     */
    static func toJSValue(value: Any): NativeJSValue {
        match (value) {
            case external: Extern<ArkTSRuntime> => jsValueOf(external)
            case convertible: ToJS => convertible.toJS()
            case _ => throw ExternConversionException("Unsupported conversion to ArkTS")
        }
    }

    /** Reads `value` as a Cangjie `R`; `Extern<ArkTSRuntime>` is the identity. Bind thread only. */
    static func fromJSValue<R>(value: NativeJSValue): R {
        // Concrete types skip the `TypeTag` allocation and the interface cast; only `Array<T>` and
        // `Option<T>` need them, to reach the element type's `fromJS`.
        match (None<R>) {
            case _: Option<Float64> => return (Float64.fromJS(value) as R).getOrThrow()
            case _: Option<Bool> => return (Bool.fromJS(value) as R).getOrThrow()
            case _: Option<String> => return (String.fromJS(value) as R).getOrThrow()
            case _: Option<Int64> => return (Int64.fromJS(value) as R).getOrThrow()
            case _: Option<Int32> => return (Int32.fromJS(value) as R).getOrThrow()
            case _: Option<Int16> => return (Int16.fromJS(value) as R).getOrThrow()
            case _: Option<Int8> => return (Int8.fromJS(value) as R).getOrThrow()
            case _: Option<UInt64> => return (UInt64.fromJS(value) as R).getOrThrow()
            case _: Option<UInt32> => return (UInt32.fromJS(value) as R).getOrThrow()
            case _: Option<UInt16> => return (UInt16.fromJS(value) as R).getOrThrow()
            case _: Option<UInt8> => return (UInt8.fromJS(value) as R).getOrThrow()
            case _: Option<Float32> => return (Float32.fromJS(value) as R).getOrThrow()
            case _: Option<Float16> => return (Float16.fromJS(value) as R).getOrThrow()
            case _: Option<BigInt> => return (BigInt.fromJS(value) as R).getOrThrow()
            case _: Option<Unit> => return (Unit.fromJS(value) as R).getOrThrow()
            case _ => ()
        }
        match (TypeTag<R>() as JSReader) {
            case Some(reader) => (reader.read(value) as R).getOrThrow()
            case None => match (None<R>) {
                case _: Option<Extern<ArkTSRuntime>> => (retain(value) as R).getOrThrow()
                case _ => throw ExternConversionException("Unsupported conversion from ArkTS")
            }
        }
    }

    // ArkTS-specific entry points. Each runs in one `run`.
    public static func undefined(): Extern<ArkTSRuntime> {
        run { undefinedExtern }
    }

    public static func null(): Extern<ArkTSRuntime> {
        run { retain(context.null().toJSValue()) }
    }

    /** A fresh empty object. */
    public static func object(): Extern<ArkTSRuntime> {
        run { retain(context.object().toJSValue()) }
    }

    /** `globalThis`. */
    public static func global(): Extern<ArkTSRuntime> {
        run { retain(context.global.toJSValue()) }
    }

    /** A new symbol; two calls never give the same symbol. */
    public static func symbol(description!: String = ""): Extern<ArkTSRuntime> {
        run { retain(context.symbol(description: description).toJSValue()) }
    }

    /** JS `lhs === rhs`. */
    public static func strictEqual(lhs: Extern<ArkTSRuntime>, rhs: Extern<ArkTSRuntime>): Bool {
        run { jsValueOf(lhs).strictEqual(jsValueOf(rhs)) }
    }

    public static func isNull(value: Extern<ArkTSRuntime>): Bool {
        run { jsValueOf(value).isNull() }
    }

    public static func isUndefined(value: Extern<ArkTSRuntime>): Bool {
        run { jsValueOf(value).isUndefined() }
    }

    /** JS `key in value`: own or inherited. Throws `ExternMemberAccessException` for non-objects. */
    public static func objectHasProperty(value: Extern<ArkTSRuntime>, key: String): Bool {
        run { objectOf(jsValueOf(value)).hasProperty(key) }
    }

    /** JS `Object.keys(value)`: own enumerable string keys. */
    public static func objectKeys(value: Extern<ArkTSRuntime>): Array<String> {
        run { objectOf(jsValueOf(value)).keys() }
    }

    /**
     * Defines (or redefines) an own data property. As with JS `Object.defineProperty`, a refusal
     * (frozen object, read-only non-configurable property) throws: a `ForeignRuntimeException`
     * with "TypeError Cannot define property".
     */
    public static func objectDefineOwnProperty(
        value: Extern<ArkTSRuntime>,
        key: String,
        propertyValue: Any,
        isWritable!: Bool = true,
        isEnumerable!: Bool = true,
        isConfigurable!: Bool = true
    ): Bool {
        run {
            let target = objectOf(jsValueOf(value))
            target.defineOwnProperty(key, toJSValue(propertyValue), isWritable: isWritable,
                isEnumerable: isEnumerable, isConfigurable: isConfigurable)
        }
    }

    /**
     * Loads an ArkTS module, e.g. `"entry/src/main/ets/Utils"` (no extension; the file must be
     * listed in `arkOptions.runtimeOnly.sources`), `"@ohos.hilog"` or `"libfoo.so"`. Works only
     * while ArkTS code is on the stack: from a spawned thread (the call then runs in a posted
     * JS task) it throws `ForeignRuntimeException` ("Unable to get recordName ..."). A missing
     * module throws `ArkTSNativeException` 34300006 from the native backend.
     */
    public static func requireArkModule(specifier: String): Extern<ArkTSRuntime> {
        run { retain(context.requireArkModule(specifier)) }
    }

    /** Loads a system NAPI module, e.g. `"hilog"`; `undefined` when it cannot be loaded. */
    public static func requireSystemNativeModule(moduleName: String, prefix: ?String): Extern<ArkTSRuntime> {
        run { retain(context.requireSystemNativeModule(moduleName, prefix: prefix)) }
    }

    /**
     * An ArkTS function that runs `body` when called (on the JS thread), with the arguments as
     * `Extern` values; the result is converted like any value passed to ArkTS. `this` is not
     * passed. An exception thrown by `body` reaches ArkTS as an `Error` whose message is the
     * exception's text.
     */
    public static func function(body: (Array<Extern<ArkTSRuntime>>) -> Extern<ArkTSRuntime>): Extern<ArkTSRuntime> {
        run {
            let function = context.function { _, callInfo =>
                let arguments = Array<Extern<ArkTSRuntime>>(callInfo.size) { i => retain(callInfo[i]) }
                toJSValue(body(arguments))
            }
            retain(function.toJSValue())
        }
    }

    /** As member access, a non-object throws `ExternMemberAccessException` with `ark_interop`'s message. */
    private static func objectOf(value: NativeJSValue): NativeJSValue {
        try {
            value.asObject()
        } catch (e: ArkTSNativeException) {
            throw memberError(e)
        }
    }
}
