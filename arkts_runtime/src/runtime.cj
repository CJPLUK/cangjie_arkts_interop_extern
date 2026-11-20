package arkts_runtime

import std.collection.ArrayList
import std.math.numeric.BigInt
import std.sync.Mutex

/** `ArkTSNativeException.code` of `ark_interop`'s "The accessing index is out of range". */
const INDEX_OUT_OF_RANGE_CODE: Int32 = 34300001

/** `ArkTSNativeException.code` of `ark_interop`'s "The ArkTS data types do not match". */
const TYPE_MISMATCH_CODE: Int32 = 34300005

/** What an `Extern<ArkTSRuntime>` made by the runtime holds as its payload. */
private enum ArkTSHandle {
    | Imm(NativeJSValue)      // undefined / null / boolean / number
    | Text(String)
    | Ref(Pinned) // string / bigint / symbol / object (arrays too) / function / external
    | Method(Pinned, ArkTSHandle) // a function read as a member or element, with its receiver
}

private enum OpArg {
    | Scalar(Int32, Float64)
    | Pin(Pinned)
    | Text(String)
    | Generic
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
        if (context.session.isInBindThread()) {
            let scope = context.session.scopeOpen()
            try { return operation() } finally { context.session.scopeClose(scope) }
        }
        context.session.runPosted(operation)
    }

    static func arrayOwnerOf(e: Extern<ArkTSRuntime>): ?Pinned {
        match (Extern<ArkTSRuntime>.getPayload(e) as ArkTSHandle) {
            case Some(Ref(owner)) => if (owner.isArray()) { Some(owner) } else { None }
            case _ => None
        }
    }

    /**
     * Runs `body` inside a fresh ArkTS handle scope that closes when `body` returns or throws.
     * Wrap code that runs where no ArkTS caller closes a scope for you, such as Cangjie UI event
     * handlers and `postJSTask` bodies: there, every ArkTS value created would otherwise stay
     * alive until the environment is destroyed, as with `ark_interop` without `newScope`.
     * `Extern` values created inside stay valid after it returns. Off the bind thread it only
     * runs `body`.
     */
    public static func newScope<T>(body: () -> T): T {
        let session = context.session
        if (!session.isInBindThread()) { return body() }
        let scope = session.userScopeOpen()
        try { body() } finally { session.scopeClose(scope) }
    }

    /** `e.f`. A function keeps `e` as the `this` of a later `functionCall`. */
    public static func memberAccess(e: Extern<ArkTSRuntime>, field: String): Extern<ArkTSRuntime> {
        if (let Some(receiver) <- (Extern<ArkTSRuntime>.getPayload(e) as ArkTSHandle)) {
            if (let Some(target) <- objectPinOf(receiver)) {
                let session = context.session
                let hint = session.intern.hint(target.cell, field)
                var out = NativeOpResult()
                let status = unsafe {
                    let key = acquireArrayRawData(field.rawData())
                    try { ats_rt_ext_get_named(session.state, target.cell, key.pointer, UIntNative(key.array.size), cellOf(hint), inout out) }
                    finally { releaseArrayRawData(key) }
                }
                if (status == 0) { return Extern<ArkTSRuntime>(handleOfRead(session, out, receiver, target, field, hint)) }
                if (status != AR_NOT_OWNER) {
                    try { opFailed(session, status) } catch (x: ArkTSNativeException) { throw memberError(x) }
                }
                return memberAccessSlow(e, field)
            }
        }
        if (context.session.isInBindThread()) {
            let scope = context.session.scopeOpen()
            try { return ArkTSRuntime.retain(readMember(ArkTSRuntime.jsValueOf(e), field), receiver: e) } finally { context.session.scopeClose(scope) }
        }
        memberAccessSlow(e, field)
    }

    static func memberAccessSlow(e: Extern<ArkTSRuntime>, field: String): Extern<ArkTSRuntime> {
        run { ArkTSRuntime.retain(readMember(ArkTSRuntime.jsValueOf(e), field), receiver: e) }
    }

    /** `e[arg]`. A function keeps `e` as the `this` of a later `functionCall`. */
    public static func indexedAccess(e: Extern<ArkTSRuntime>, arg: Any): Extern<ArkTSRuntime> {
        if (let Some(receiver) <- (Extern<ArkTSRuntime>.getPayload(e) as ArkTSHandle)) {
            if (let Some(target) <- objectPinOf(receiver)) {
                let session = context.session
                var out = NativeOpResult()
                let status = match (arg) {
                    case position: Int64 where target.isArrayHere() => unsafe { ats_rt_ext_element_get(session.state, target.cell, position, inout out) }
                    case name: String => unsafe {
                        let key = acquireArrayRawData(name.rawData())
                        try { ats_rt_ext_get_named(session.state, target.cell, key.pointer, UIntNative(key.array.size), CPointer<Unit>(), inout out) }
                        finally { releaseArrayRawData(key) }
                    }
                    case _ => AR_GENERIC
                }
                if (status == 0) { return Extern<ArkTSRuntime>(handleOfResult(session, out, receiver)) }
                if (status == AR_NOT_OWNER) { return indexedAccessSlow(e, arg) }
                if (status == NAPI_PENDING_EXCEPTION || status == AR_DEAD) {
                    try { opFailed(session, status) } catch (x: ArkTSNativeException) { throw indexError(x) }
                }
            }
        }
        if (context.session.isInBindThread()) {
            match (arg) {
                case position: Int64 =>
                    let scope = context.session.scopeOpen()
                    try {
                        if (let Some(owner) <- arrayOwnerOf(e)) {
                            return try { ArkTSRuntime.retain(owner.elementRead(position), receiver: e) }
                                   catch (x: ArkTSNativeException) { throw indexError(x) }
                        }
                    } finally { context.session.scopeClose(scope) }
                case _ => ()
            }
            let scope = context.session.scopeOpen()
            try { return ArkTSRuntime.retain(readIndex(ArkTSRuntime.jsValueOf(e), arg), receiver: e) } finally { context.session.scopeClose(scope) }
        }
        indexedAccessSlow(e, arg)
    }

    static func indexedAccessSlow(e: Extern<ArkTSRuntime>, arg: Any): Extern<ArkTSRuntime> {
        run { ArkTSRuntime.retain(readIndex(ArkTSRuntime.jsValueOf(e), arg), receiver: e) }
    }

    /** `e.f = value`. */
    public static func memberUpdate(e: Extern<ArkTSRuntime>, field: String, value: Any): Unit {
        if (let Some(receiver) <- (Extern<ArkTSRuntime>.getPayload(e) as ArkTSHandle)) {
            if (let Some(target) <- objectPinOf(receiver)) {
                let arg = opArgOf(value)
                if (!isGeneric(arg)) {
                    let session = context.session
                    let status = unsafe {
                        let key = acquireArrayRawData(field.rawData())
                        try {
                            match (arg) {
                                case Text(text) =>
                                    let bytes = acquireArrayRawData(text.rawData())
                                    try {
                                        var native = textArg(bytes.pointer, bytes.array.size)
                                        ats_rt_ext_set_named(session.state, target.cell, key.pointer, UIntNative(key.array.size), inout native)
                                    } finally { releaseArrayRawData(bytes) }
                                case _ =>
                                    var native = plainArg(arg)
                                    ats_rt_ext_set_named(session.state, target.cell, key.pointer, UIntNative(key.array.size), inout native)
                            }
                        } finally { releaseArrayRawData(key) }
                    }
                    if (status == 0) { return }
                    if (status != AR_NOT_OWNER) {
                        try { opFailed(session, status) } catch (x: ArkTSNativeException) { throw memberError(x) }
                    }
                    return memberUpdateSlow(e, field, value)
                }
            }
        }
        if (context.session.isInBindThread()) {
            let scope = context.session.scopeOpen()
            try { return writeMember(ArkTSRuntime.jsValueOf(e), field, ArkTSRuntime.toJSValue(value)) } finally { context.session.scopeClose(scope) }
        }
        memberUpdateSlow(e, field, value)
    }

    static func memberUpdateSlow(e: Extern<ArkTSRuntime>, field: String, value: Any): Unit {
        run { writeMember(ArkTSRuntime.jsValueOf(e), field, ArkTSRuntime.toJSValue(value)) }
    }

    /** `e[field] = value`. */
    public static func indexedUpdate(e: Extern<ArkTSRuntime>, field: Any, value: Any): Unit {
        if (let Some(receiver) <- (Extern<ArkTSRuntime>.getPayload(e) as ArkTSHandle)) {
            if (let Some(target) <- objectPinOf(receiver)) {
                let arg = opArgOf(value)
                let status = if (isGeneric(arg)) { AR_GENERIC } else { indexedUpdateFused(target, field, arg) }
                if (status == 0) { return }
                if (status == AR_NOT_OWNER) { return indexedUpdateSlow(e, field, value) }
                if (status == NAPI_PENDING_EXCEPTION || status == AR_DEAD) {
                    try { opFailed(context.session, status) } catch (x: ArkTSNativeException) { throw indexError(x) }
                }
            }
        }
        if (context.session.isInBindThread()) {
            match (field) {
                case position: Int64 where position >= 0 && position < Int64(UInt32.Max) =>
                    let scope = context.session.scopeOpen()
                    try {
                        if (let Some(owner) <- arrayOwnerOf(e)) {
                            return try { owner.elementWrite(UInt32(position), ArkTSRuntime.toJSValue(value)) }
                                   catch (x: ArkTSNativeException) { throw indexError(x) }
                        }
                    } finally { context.session.scopeClose(scope) }
                case _ => ()
            }
            let scope = context.session.scopeOpen()
            try { return writeIndex(ArkTSRuntime.jsValueOf(e), field, value) } finally { context.session.scopeClose(scope) }
        }
        indexedUpdateSlow(e, field, value)
    }

    private static func indexedUpdateFused(target: Pinned, field: Any, arg: OpArg): Int32 {
        let state = context.session.state
        match (field) {
            case position: Int64 where position >= 0 && position < Int64(UInt32.Max) && target.isArrayHere() => unsafe {
                match (arg) {
                    case Text(text) =>
                        let bytes = acquireArrayRawData(text.rawData())
                        try {
                            var native = textArg(bytes.pointer, bytes.array.size)
                            ats_rt_ext_element_set(state, target.cell, UInt32(position), inout native)
                        } finally { releaseArrayRawData(bytes) }
                    case _ =>
                        var native = plainArg(arg)
                        ats_rt_ext_element_set(state, target.cell, UInt32(position), inout native)
                }
            }
            case name: String => unsafe {
                let key = acquireArrayRawData(name.rawData())
                try {
                    match (arg) {
                        case Text(text) =>
                            let bytes = acquireArrayRawData(text.rawData())
                            try {
                                var native = textArg(bytes.pointer, bytes.array.size)
                                ats_rt_ext_set_named(state, target.cell, key.pointer, UIntNative(key.array.size), inout native)
                            } finally { releaseArrayRawData(bytes) }
                        case _ =>
                            var native = plainArg(arg)
                            ats_rt_ext_set_named(state, target.cell, key.pointer, UIntNative(key.array.size), inout native)
                    }
                } finally { releaseArrayRawData(key) }
            }
            case _ => AR_GENERIC
        }
    }

    static func indexedUpdateSlow(e: Extern<ArkTSRuntime>, field: Any, value: Any): Unit {
        run { writeIndex(ArkTSRuntime.jsValueOf(e), field, value) }
    }

    /**
     * `e(args)`. `this` is the receiver a member or element read kept, `undefined` for any
     * other function.
     */
    public static func functionCall(e: Extern<ArkTSRuntime>, args: Array<Any>): Extern<ArkTSRuntime> {
        if (let Some(callee) <- (Extern<ArkTSRuntime>.getPayload(e) as ArkTSHandle)) {
            let fused: ?Extern<ArkTSRuntime> = match (callee) {
                case Method(p, receiver) where p.kind == JSType.FUNCTION => match (receiverArgOf(receiver)) {
                    case Some(receiverArg) => callFused(p, receiverArg, e, args)
                    case None => None
                }
                case Ref(p) where p.kind == JSType.FUNCTION => callFused(p, scalarArg(JSType.UNDEFINED, 0.0), e, args)
                case _ => None
            }
            if (let Some(result) <- fused) { return result }
        }
        if (context.session.isInBindThread()) {
            let scope = context.session.scopeOpen()
            try {
            let (function, receiver) = ArkTSRuntime.calleeOf(e)
            return ArkTSRuntime.retain(invoke(function, args, receiver ?? undefinedValue))
        } finally { context.session.scopeClose(scope) }
        }
        functionCallSlow(e, args)
    }

    private static let noTexts = ArrayList<CPointerHandle<UInt8>>()

    private static func callFused(function: Pinned, receiverArg: NativeArg, e: Extern<ArkTSRuntime>,
        args: Array<Any>): ?Extern<ArkTSRuntime> {
        let natives = Array<NativeArg>(args.size, repeat: NativeArg())
        var textCount = 0
        for (i in 0..args.size) {
            match (callArgOf(args[i])) {
                case Some(native) =>
                    natives[i] = native
                    if (native.tag == AR_ARG_UTF8) { textCount++ }
                case None => return None
            }
        }
        let session = context.session
        var result = NativeOpResult()
        var receiver = receiverArg
        let texts = if (textCount == 0) { noTexts } else { ArrayList<CPointerHandle<UInt8>>(textCount) }
        try {
            for (i in 0..args.size where natives[i].tag == AR_ARG_UTF8) {
                let bytes = unsafe { acquireArrayRawData(textOfArg(args[i]).rawData()) }
                texts.add(bytes)
                natives[i] = textArg(bytes.pointer, bytes.array.size)
            }
            let status = unsafe {
                let buffer = acquireArrayRawData(natives)
                try { ats_rt_ext_call(session.state, function.cell, inout receiver, buffer.pointer, UIntNative(natives.size), inout result) }
                finally { releaseArrayRawData(buffer) }
            }
            if (status == 0) { return Extern<ArkTSRuntime>(handleOfResult(session, result, None)) }
            if (status != AR_NOT_OWNER) { opFailed(session, status) }
            functionCallSlow(e, args)
        } finally {
            for (bytes in texts) { unsafe { releaseArrayRawData(bytes) } }
        }
    }

    private static func callArgOf(value: Any): ?NativeArg {
        if (let Some((kind, x)) <- immediateOfAny(value)) { return scalarArg(kind, x) }
        match (value) {
            case _: String => textArg(CPointer<UInt8>(), 0)
            case _: Option<String> => textArg(CPointer<UInt8>(), 0)
            case external: Extern<ArkTSRuntime> => match (Extern<ArkTSRuntime>.getPayload(external) as ArkTSHandle) {
                case Some(Text(_)) => textArg(CPointer<UInt8>(), 0)
                case Some(handle) => receiverArgOf(handle)
                case None => None
            }
            case _ => None
        }
    }

    private static func textOfArg(value: Any): String {
        match (value) {
            case text: String => text
            case option: Option<String> => option.getOrThrow()
            case external: Extern<ArkTSRuntime> => match (Extern<ArkTSRuntime>.getPayload(external) as ArkTSHandle) {
                case Some(Text(text)) => text
                case _ => throw IllegalStateException("call argument is not text")
            }
            case _ => throw IllegalStateException("call argument is not text")
        }
    }

    private static func receiverArgOf(handle: ArkTSHandle): ?NativeArg {
        match (handle) {
            case Imm(v) => scalarArg(v.kind, if (v.kind == JSType.BOOLEAN) { if (v.boolean) { 1.0 } else { 0.0 } } else { v.number })
            case Text(_) => None
            case Ref(p) => pinArg(p)
            case Method(p, _) => pinArg(p)
        }
    }

    private static func argOfHandle(handle: ArkTSHandle): OpArg {
        match (handle) {
            case Imm(v) => Scalar(v.kind, if (v.kind == JSType.BOOLEAN) { if (v.boolean) { 1.0 } else { 0.0 } } else { v.number })
            case Text(s) => OpArg.Text(s)
            case Ref(p) => Pin(p)
            case Method(p, _) => Pin(p)
        }
    }

    private static func scalarArg(kind: Int32, x: Float64): NativeArg {
        var native = NativeArg()
        native.kind = kind
        native.scalar = x
        native
    }

    private static func pinArg(p: Pinned): NativeArg {
        var native = NativeArg()
        native.tag = AR_ARG_PIN
        native.ptr = p.cell
        native
    }

    static func functionCallSlow(e: Extern<ArkTSRuntime>, args: Array<Any>): Extern<ArkTSRuntime> {
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
        let boxed: Any = value
        match (boxed) {
            case external: Extern<ArkTSRuntime> => return external
            case _ => ()
        }
        if (let Some((kind, x)) <- immediateOfAny(boxed)) {
            context.session.checkAlive()
            return Extern<ArkTSRuntime>(Imm(NativeJSValue(context.session, NapiValue(), kind, number: x,
                boolean: kind == JSType.BOOLEAN && x != 0.0)))
        }
        if (context.session.isInBindThread()) {
            let scope = context.session.scopeOpen()
            try {
                return ArkTSRuntime.retain(ArkTSRuntime.toJSValue(boxed))
            } finally { context.session.scopeClose(scope) }
        }
        toExternSlow(boxed)
    }

    static func toExternSlow(value: Any): Extern<ArkTSRuntime> {
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
        if (let Some(Text(text)) <- (Extern<ArkTSRuntime>.getPayload(value) as ArkTSHandle)) {
            match (probeOf<R>(probeString, probeComparableString, probeInt64)) {
                case Hit =>
                    context.session.checkAlive()
                    return asR<R>(text)
                case _ => ()
            }
            match (probeOf<R>(probeOptionString, probeOptionInt64, probeSentinel)) {
                case Hit =>
                    context.session.checkAlive()
                    return asR<R>(Some(text))
                case _ => ()
            }
        }
        if (let Some(immediate) <- ArkTSRuntime.immediateOf(value)) {
            if (context.isInBindThread()) {
                return ArkTSRuntime.fromJSValue<R>(immediate)
            }
            if (isCopiedScalarReader<R>()) {
                context.session.checkAlive()
                return ArkTSRuntime.fromJSValue<R>(immediate)
            }
        }
        let boxed: Any = value
        match (probeOf<R>(boxed, probeSentinel, probeSentinel)) {
            case Hit => return asR<R>(boxed)
            case _ => ()
        }
        if (context.session.isInBindThread()) {
            let scope = context.session.scopeOpen()
            try {
                return ArkTSRuntime.fromJSValue<R>(ArkTSRuntime.jsValueOf(value))
            } finally { context.session.scopeClose(scope) }
        }
        fromExternSlow<R>(value)
    }

    static func fromExternSlow<R>(value: Extern<ArkTSRuntime>): R {
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
            case t == JSType.STRING => Ref(Pinned(value))
            case t == JSType.OBJECT => Ref(Pinned(value))
            case t == JSType.FUNCTION => match (receiver) {
                case Some(target) => Method(Pinned(value), handleOf(target))
                case None => Ref(Pinned(value))
            }
            case t == JSType.SYMBOL => Ref(Pinned(value))
            case t == JSType.BIGINT => Ref(Pinned(value))
            case t == JSType.EXTERNAL => Ref(Pinned(value))
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
            case Text(s) => nativeString(context.session, s)
            case Ref(owner) => owner.toJSValue()
            case Method(function, _) => function.toJSValue()
        }
    }

    private static func objectPinOf(handle: ArkTSHandle): ?Pinned {
        let pin = match (handle) {
            case Ref(p) => p
            case Method(p, _) => p
            case _ => return None
        }
        if (pin.kind == JSType.OBJECT || pin.kind == JSType.FUNCTION) { pin } else { None }
    }

    private static func immediateOfAny(value: Any): ?(Int32, Float64) {
        match (value) {
            case number: Float64 => (JSType.NUMBER, number)
            case boolean: Bool => (JSType.BOOLEAN, if (boolean) { 1.0 } else { 0.0 })
            case option: Option<Float64> => match (option) {
                case Some(number) => (JSType.NUMBER, number)
                case None => (JSType.UNDEFINED, 0.0)
            }
            case option: Option<Bool> => match (option) {
                case Some(boolean) => (JSType.BOOLEAN, if (boolean) { 1.0 } else { 0.0 })
                case None => (JSType.UNDEFINED, 0.0)
            }
            case option: Option<String> where option.isNone() => (JSType.UNDEFINED, 0.0)
            case _ => None
        }
    }

    private static func opArgOf(value: Any): OpArg {
        if (let Some((kind, x)) <- immediateOfAny(value)) { return Scalar(kind, x) }
        match (value) {
            case text: String => Text(text)
            case option: Option<String> => Text(option.getOrThrow())
            case external: Extern<ArkTSRuntime> => match (Extern<ArkTSRuntime>.getPayload(external) as ArkTSHandle) {
                case Some(handle) => argOfHandle(handle)
                case None => Generic
            }
            case _ => Generic
        }
    }

    private static func isGeneric(arg: OpArg): Bool {
        match (arg) {
            case Generic => true
            case _ => false
        }
    }

    private static func plainArg(arg: OpArg): NativeArg {
        match (arg) {
            case Scalar(kind, x) => scalarArg(kind, x)
            case Pin(p) => pinArg(p)
            case _ => throw IllegalStateException("text or generic value passed as a plain argument")
        }
    }

    private static func textArg(bytes: CPointer<UInt8>, count: Int64): NativeArg {
        var native = NativeArg()
        native.tag = AR_ARG_UTF8
        native.ptr = CPointer<Unit>(bytes)
        native.length = UIntNative(count)
        native
    }

    static func nativeStats(): NativeStats {
        var out = NativeStats()
        unsafe { ats_rt_ext_stats(context.session.state, inout out) }
        out
    }

    private static func cellOf(pin: ?Pinned): CPointer<Unit> {
        match (pin) {
            case Some(p) => p.cell
            case None => CPointer<Unit>()
        }
    }

    private static func handleOfRead(session: NativeSession, out: NativeOpResult, receiver: ArkTSHandle, target: Pinned,
        field: String, hint: ?Pinned): ArkTSHandle {
        if (out.kind > JSType.NUMBER && (out.flags & AR_RESULT_HIT) != 0) {
            if (let Some(p) <- hint) {
                return if (p.kind == JSType.FUNCTION) { Method(p, receiver) } else { Ref(p) }
            }
        }
        let handle = handleOfResult(session, out, receiver)
        match (handle) {
            case Ref(p) => session.intern.remember(target.cell, field, p)
            case Method(p, _) => session.intern.remember(target.cell, field, p)
            case _ => ()
        }
        handle
    }

    private static func handleOfResult(session: NativeSession, out: NativeOpResult, receiver: ?ArkTSHandle): ArkTSHandle {
        if ((out.flags & AR_RESULT_TEXT) != 0) {
            let bytes = Array<UInt8>(Int64(out.textLength), repeat: 0)
            unsafe {
                let buffer = acquireArrayRawData(bytes)
                try { ats_rt_ext_text_take(session.state, buffer.pointer, out.textLength) } finally { releaseArrayRawData(buffer) }
                return Text(String.withRawData(bytes))
            }
        }
        if (out.kind <= JSType.NUMBER) {
            return Imm(NativeJSValue(session, NapiValue(), out.kind, number: out.scalar, boolean: out.kind == JSType.BOOLEAN && out.scalar != 0.0))
        }
        let pinned = Pinned(session, out.pin, out.kind)
        match {
            case out.kind == JSType.FUNCTION => match (receiver) {
                case Some(r) => Method(pinned, r)
                case None => Ref(pinned)
            }
            case out.kind <= JSType.BIGINT => Ref(pinned)
            case _ => throw ExternConversionException("Unknown ArkTS value type ${out.kind}")
        }
    }

    private static func opFailed(session: NativeSession, status: Int32): Nothing {
        if (status == AR_DEAD) { session.checkAlive() }
        session.newScope { nativeCheck(session, status, checkPending: true) }
        throw ForeignRuntimeException("N-API operation failed: ${status}")
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

    static func handleKind(value: Extern<ArkTSRuntime>): String {
        match (Extern<ArkTSRuntime>.getPayload(value) as ArkTSHandle) {
            case Some(Imm(_)) => "Imm"
            case Some(Text(_)) => "Text"
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
            case number: Float64 => context.number(number)
            case external: Extern<ArkTSRuntime> => jsValueOf(external)
            case boolean: Bool => context.boolean(boolean)
            case text: String => text.toJS()
            case integer: Int64 => integer.toJS()
            case option: Option<Float64> => match (option) { case Some(n) => context.number(n) case None => undefinedValue }
            case option: Option<String> => match (option) { case Some(s) => s.toJS() case None => undefinedValue }
            case option: Option<Bool> => match (option) { case Some(b) => context.boolean(b) case None => undefinedValue }
            case convertible: ToJS => convertible.toJS()
            case _ => throw ExternConversionException("Unsupported conversion to ArkTS")
        }
    }

    /** Reads `value` as a Cangjie `R`; `Extern<ArkTSRuntime>` is the identity. Bind thread only. */
    static func fromJSValue<R>(value: NativeJSValue): R { probedFromJSValue<R>(value) }

    static func fromJSValueSlow<R>(value: NativeJSValue): R {
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
