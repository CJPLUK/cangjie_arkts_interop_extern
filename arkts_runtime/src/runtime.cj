package arkts_runtime

import std.collection.ArrayList
import std.math.numeric.BigInt
import std.sync.{AtomicOptionReference, Mutex}

const INDEX_OUT_OF_RANGE_CODE: Int32 = 34300001

const TYPE_MISMATCH_CODE: Int32 = 34300005

private enum ArkTSPayload {
    | Imm(NativeJSValue)
    | Text(String)
    | Pin(Pinned)
    | Method(Pinned, ArkTSPayload)
}

private enum OpArg {
    | Plain(PlainArg)
    | Text(String)
}

private enum PlainArg {
    | Scalar(JSTypeCode, Float64)
    | Pin(Pinned)
}

private struct LentArg {
    LentArg(let native: NativeArg, let bytes: ?CPointerHandle<UInt8>) {}

    unsafe func release(): Unit {
        if (let Some(held) <- bytes) { releaseArrayRawData(held) }
    }
}

private struct HeldTexts {
    var bytes: ?ArrayList<CPointerHandle<UInt8>> = None

    mut func hold(lent: LentArg, capacity: Int64): NativeArg {
        if (let Some(handle) <- lent.bytes) {
            match (bytes) {
                case Some(list) => list.add(handle)
                case None =>
                    let list = ArrayList<CPointerHandle<UInt8>>(capacity)
                    list.add(handle)
                    bytes = list
            }
        }
        lent.native
    }

    unsafe func releaseAll(): Unit {
        if (let Some(list) <- bytes) {
            for (handle in list) { releaseArrayRawData(handle) }
        }
    }
}

private enum ArkTSIndex {
    | Element(Int64)
    | Key(NativeJSValue)
}

public abstract class ArkTSRuntime <: ForeignRuntime<ArkTSRuntime> {
    private static let bindMutex = Mutex()
    private static let js_ = AtomicOptionReference<JS>()

    public static func bind(env: CPointer<Unit>): Unit {
        synchronized(bindMutex) {
            if (js_.load().isSome()) {
                throw ArkTSContextAlreadyBoundException(
                    "ArkTS runtime is already associated with a host ArkTS environment")
            }
            js_.store(JS(Environment(env)))
        }
    }

    public static func isBound(): Bool {
        js_.load().isSome()
    }

    static prop js: JS {
        get() {
            match (js_.load()) {
                case Some(js) => js
                case None => throw ArkTSContextNotBoundException(
                    "ArkTS runtime is not associated with a host ArkTS environment")
            }
        }
    }

    static prop environment: Environment {
        get() { js.environment }
    }

    private static var undefined_: ?(NativeJSValue, Extern<ArkTSRuntime>) = None

    private static func undefinedPair(): (NativeJSValue, Extern<ArkTSRuntime>) {
        match (undefined_) {
            case Some(pair) => pair
            case None =>
                let value = js.undefined().toJSValue()
                let pair = (value, ArkTSRuntime.retain(value))
                undefined_ = Some(pair)
                pair
        }
    }

    static prop undefinedValue: NativeJSValue {
        get() { undefinedPair()[0] }
    }

    static prop undefinedExtern: Extern<ArkTSRuntime> {
        get() { undefinedPair()[1] }
    }

    static func run<R>(operation: () -> R): R {
        if (environment.isOnOwnerThread()) {
            return environment.runtimeFrame(operation)
        }
        environment.runPosted(operation)
    }

    static func arrayOwnerOf(e: Extern<ArkTSRuntime>): ?Pinned {
        match (Extern<ArkTSRuntime>.getPayload(e) as ArkTSPayload) {
            case Some(Pin(owner)) => if (owner.isArray()) { Some(owner) } else { None }
            case _ => None
        }
    }

    public static func newScope<T>(body: () -> T): T {
        let environment = ArkTSRuntime.environment
        if (!environment.isOnOwnerThread()) { return body() }
        environment.userFrame(body)
    }

    public static func memberAccess(e: Extern<ArkTSRuntime>, field: String): Extern<ArkTSRuntime> {
        if (let Some(receiver) <- (Extern<ArkTSRuntime>.getPayload(e) as ArkTSPayload)) {
            if (let Some(target) <- objectPinOf(receiver)) {
                let environment = ArkTSRuntime.environment
                let pinCache = match (environment.pinCacheIfOwnerThread()) {
                    case Some(cache) => cache
                    case None => return memberAccessSlow(e, field)
                }
                let hint = pinCache.hint(target.cell, field)
                var out = NativeOpResult()
                let status = unsafe {
                    let key = acquireArrayRawData(field.rawData())
                    try { ats_rt_ext_get_named(environment.state, target.cell, key.pointer, UIntNative(key.array.size), cellOf(hint), inout out) }
                    finally { releaseArrayRawData(key) }
                }
                if (status == 0) { return Extern<ArkTSRuntime>(payloadOfRead(environment, pinCache, out, receiver, target, field, hint)) }
                try { opFailed(environment, status) } catch (x: ArkTSNativeException) { throw memberError(x) }
            }
        }
        memberAccessSlow(e, field)
    }

    static func memberAccessSlow(e: Extern<ArkTSRuntime>, field: String): Extern<ArkTSRuntime> {
        run { ArkTSRuntime.retain(readMember(ArkTSRuntime.jsValueOf(e), field), receiver: e) }
    }

    public static func indexedAccess(e: Extern<ArkTSRuntime>, arg: Any): Extern<ArkTSRuntime> {
        if (let Some(receiver) <- (Extern<ArkTSRuntime>.getPayload(e) as ArkTSPayload)) {
            if (let Some(target) <- objectPinOf(receiver)) {
                let environment = ArkTSRuntime.environment
                var out = NativeOpResult()
                let status: ?Int32 = match (arg) {
                    case position: Int64 => unsafe { ats_rt_ext_element_get(environment.state, target.cell, position, inout out) }
                    case name: String => unsafe {
                        let key = acquireArrayRawData(name.rawData())
                        try { ats_rt_ext_get_named(environment.state, target.cell, key.pointer, UIntNative(key.array.size), NativePin(), inout out) }
                        finally { releaseArrayRawData(key) }
                    }
                    case _ => None
                }
                if (let Some(status) <- status) {
                    if (status == 0) { return Extern<ArkTSRuntime>(payloadOfResult(environment, out, receiver)) }
                    if (status == AR_NOT_OWNER) { return indexedAccessSlow(e, arg) }
                    indexedOpFailed(status)
                }
            }
        }
        if (environment.isOnOwnerThread()) {
            match (arg) {
                case position: Int64 =>
                    let read: ?Extern<ArkTSRuntime> = environment.runtimeFrame {
                        match (arrayOwnerOf(e)) {
                            case Some(owner) =>
                                try { Some(ArkTSRuntime.retain(owner.elementRead(position), receiver: e)) }
                                catch (x: ArkTSNativeException) { throw indexError(x) }
                            case None => None
                        }
                    }
                    if (let Some(result) <- read) { return result }
                case _ => ()
            }
        }
        indexedAccessSlow(e, arg)
    }

    static func indexedAccessSlow(e: Extern<ArkTSRuntime>, arg: Any): Extern<ArkTSRuntime> {
        run { ArkTSRuntime.retain(readIndex(ArkTSRuntime.jsValueOf(e), arg), receiver: e) }
    }

    public static func memberUpdate(e: Extern<ArkTSRuntime>, field: String, value: Any): Unit {
        if (let Some(receiver) <- (Extern<ArkTSRuntime>.getPayload(e) as ArkTSPayload)) {
            if (let Some(target) <- objectPinOf(receiver)) {
                if (let Some(arg) <- opArgOf(value)) {
                    let environment = ArkTSRuntime.environment
                    let status = unsafe {
                        let key = acquireArrayRawData(field.rawData())
                        try {
                            let lent = lend(arg)
                            try {
                                var native = lent.native
                                ats_rt_ext_set_named(environment.state, target.cell, key.pointer, UIntNative(key.array.size), inout native)
                            } finally { lent.release() }
                        } finally { releaseArrayRawData(key) }
                    }
                    if (status == 0) { return }
                    if (status != AR_NOT_OWNER) {
                        try { opFailed(environment, status) } catch (x: ArkTSNativeException) { throw memberError(x) }
                    }
                    return memberUpdateSlow(e, field, value)
                }
            }
        }
        memberUpdateSlow(e, field, value)
    }

    static func memberUpdateSlow(e: Extern<ArkTSRuntime>, field: String, value: Any): Unit {
        run { writeMember(ArkTSRuntime.jsValueOf(e), field, ArkTSRuntime.toJSValue(value)) }
    }

    public static func indexedUpdate(e: Extern<ArkTSRuntime>, field: Any, value: Any): Unit {
        if (let Some(receiver) <- (Extern<ArkTSRuntime>.getPayload(e) as ArkTSPayload)) {
            if (let Some(target) <- objectPinOf(receiver)) {
                let status: ?Int32 = match (opArgOf(value)) {
                    case Some(arg) => indexedUpdateFused(target, field, arg)
                    case None => None
                }
                if (let Some(status) <- status) {
                    if (status == 0) { return }
                    if (status == AR_NOT_OWNER) { return indexedUpdateSlow(e, field, value) }
                    indexedOpFailed(status)
                }
            }
        }
        if (environment.isOnOwnerThread()) {
            match (field) {
                case position: Int64 where position >= 0 && position < Int64(UInt32.Max) =>
                    let written = environment.runtimeFrame {
                        match (arrayOwnerOf(e)) {
                            case Some(owner) =>
                                try { owner.elementWrite(UInt32(position), ArkTSRuntime.toJSValue(value)) }
                                catch (x: ArkTSNativeException) { throw indexError(x) }
                                true
                            case None => false
                        }
                    }
                    if (written) { return }
                case _ => ()
            }
        }
        indexedUpdateSlow(e, field, value)
    }

    private static func indexedUpdateFused(target: Pinned, field: Any, arg: OpArg): ?Int32 {
        let state = environment.state
        match (field) {
            case position: Int64 where position >= 0 && position < Int64(UInt32.Max) => unsafe {
                let lent = lend(arg)
                try {
                    var native = lent.native
                    ats_rt_ext_element_set(state, target.cell, UInt32(position), inout native)
                } finally { lent.release() }
            }
            case name: String => unsafe {
                let key = acquireArrayRawData(name.rawData())
                try {
                    let lent = lend(arg)
                    try {
                        var native = lent.native
                        ats_rt_ext_set_named(state, target.cell, key.pointer, UIntNative(key.array.size), inout native)
                    } finally { lent.release() }
                } finally { releaseArrayRawData(key) }
            }
            case _ => None
        }
    }

    static func indexedUpdateSlow(e: Extern<ArkTSRuntime>, field: Any, value: Any): Unit {
        run { writeIndex(ArkTSRuntime.jsValueOf(e), field, value) }
    }

    public static func functionCall(e: Extern<ArkTSRuntime>, args: Array<Any>): Extern<ArkTSRuntime> {
        if (let Some(callee) <- (Extern<ArkTSRuntime>.getPayload(e) as ArkTSPayload)) {
            let fused: ?Extern<ArkTSRuntime> = match (callee) {
                case Method(p, receiver) where p.kind == JSType.FUNCTION => callFused(p, opArgOfPayload(receiver), e, args)
                case Pin(p) where p.kind == JSType.FUNCTION => callFused(p, Plain(Scalar(JSType.UNDEFINED, 0.0)), e, args)
                case _ => None
            }
            if (let Some(result) <- fused) { return result }
        }
        functionCallSlow(e, args)
    }

    private static func callFused(function: Pinned, receiver: OpArg, e: Extern<ArkTSRuntime>,
        args: Array<Any>): ?Extern<ArkTSRuntime> {
        let natives = Array<NativeArg>(args.size + 1, repeat: NativeArg())
        var texts = HeldTexts()
        try {
            for (i in 0..natives.size) {
                let arg = if (i == 0) { receiver } else {
                    match (opArgOf(args[i - 1])) {
                        case Some(arg) => arg
                        case None => return None
                    }
                }
                natives[i] = texts.hold(unsafe { lend(arg) }, natives.size - i)
            }
            let environment = ArkTSRuntime.environment
            var result = NativeOpResult()
            let status = unsafe {
                let buffer = acquireArrayRawData(natives)
                try { ats_rt_ext_call(environment.state, function.cell, buffer.pointer, buffer.pointer + 1, UIntNative(args.size), inout result) }
                finally { releaseArrayRawData(buffer) }
            }
            if (status == 0) { return Extern<ArkTSRuntime>(payloadOfResult(environment, result, None)) }
            if (status != AR_NOT_OWNER) { opFailed(environment, status) }
            functionCallSlow(e, args)
        } finally {
            unsafe { texts.releaseAll() }
        }
    }

    private static func opArgOfPayload(payload: ArkTSPayload): OpArg {
        match (payload) {
            case Imm(v) => Plain(Scalar(v.kind, v.scalar))
            case Text(s) => OpArg.Text(s)
            case Pin(p) => Plain(PlainArg.Pin(p))
            case Method(p, _) => Plain(PlainArg.Pin(p))
        }
    }

    private static func nativeArgOf(arg: PlainArg): NativeArg {
        var native = NativeArg()
        match (arg) {
            case Scalar(kind, x) =>
                native.kind = kind
                native.scalar = x
            case Pin(p) =>
                native.tag = AR_ARG_PIN
                native.pinOrUtf8 = p.cell
        }
        native
    }

    static func functionCallSlow(e: Extern<ArkTSRuntime>, args: Array<Any>): Extern<ArkTSRuntime> {
        run {
            let (function, receiver) = ArkTSRuntime.calleeOf(e)
            ArkTSRuntime.retain(invoke(function, args, receiver ?? undefinedValue))
        }
    }

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

    private static func writeIndex(target: NativeJSValue, index: Any, value: Any): Unit {
        writeResolvedIndex(target, toIndex(index), ArkTSRuntime.toJSValue(value))
    }

    private static func writeResolvedIndex(target: NativeJSValue, index: ArkTSIndex, value: NativeJSValue): Unit {
        try {
            match (index) {
                case Element(position) => target.setElement(position, value)
                case Key(key) => target.setProperty(key, value)
            }
        } catch (e: ArkTSNativeException) {
            throw indexError(e)
        }
    }

    private static func toIndex(index: Any): ArkTSIndex {
        match (index) {
            case position: Int64 => Element(position)
            case name: String => Key(js.string(name))
            case number: Float64 => Key(js.number(number))
            case name: Utf16String => Key(js.string(name))
            case external: Extern<ArkTSRuntime> =>
                let value = ArkTSRuntime.jsValueOf(external)
                let t = value.typeof()
                match {
                    case t == JSType.NUMBER => Key(js.number(value.toNumber()))
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

    public static func toExtern<R>(value: R): Extern<ArkTSRuntime> {
        let boxed: Any = value
        match (boxed) {
            case external: Extern<ArkTSRuntime> => return external
            case _ => ()
        }
        if (let Some((kind, x)) <- immediateOfAny(boxed)) {
            environment.checkAlive()
            return Extern<ArkTSRuntime>(Imm(NativeJSValue(environment, NapiValue(), kind, number: x,
                boolean: kind == JSType.BOOLEAN && x != 0.0)))
        }
        toExternSlow(boxed)
    }

    static func toExternSlow(value: Any): Extern<ArkTSRuntime> {
        run { ArkTSRuntime.retain(ArkTSRuntime.toJSValue(value)) }
    }

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

    public static func fromExtern<R>(value: Extern<ArkTSRuntime>): R {
        if (let Some(Text(text)) <- (Extern<ArkTSRuntime>.getPayload(value) as ArkTSPayload)) {
            match (probeOf<R>(probeString, probeComparableString, probeInt64)) {
                case Hit =>
                    environment.checkAlive()
                    return asR<R>(text)
                case _ => ()
            }
            match (probeOf<R>(probeOptionString, probeOptionInt64, probeSentinel)) {
                case Hit =>
                    environment.checkAlive()
                    return asR<R>(Some(text))
                case _ => ()
            }
        }
        if (let Some(immediate) <- ArkTSRuntime.immediateOf(value)) {
            if (environment.isOnOwnerThread()) {
                return ArkTSRuntime.fromJSValue<R>(immediate)
            }
            if (isCopiedScalarReader<R>()) {
                environment.checkAlive()
                return ArkTSRuntime.fromJSValue<R>(immediate)
            }
        }
        let boxed: Any = value
        match (probeOf<R>(boxed, probeSentinel, probeSentinel)) {
            case Hit => return asR<R>(boxed)
            case _ => ()
        }
        fromExternSlow<R>(value)
    }

    static func fromExternSlow<R>(value: Extern<ArkTSRuntime>): R {
        run { ArkTSRuntime.fromJSValue<R>(ArkTSRuntime.jsValueOf(value)) }
    }

    static func retain(value: NativeJSValue, receiver!: ?Extern<ArkTSRuntime> = None): Extern<ArkTSRuntime> {
        let t = value.typeof()
        let payload = match {
            case t == JSType.NUMBER || t == JSType.UNDEFINED || t == JSType.NULL || t == JSType.BOOLEAN => Imm(value)
            case t == JSType.STRING => ArkTSPayload.Pin(Pinned(value))
            case t == JSType.OBJECT => ArkTSPayload.Pin(Pinned(value))
            case t == JSType.FUNCTION => match (receiver) {
                case Some(target) => Method(Pinned(value), payloadOf(target))
                case None => ArkTSPayload.Pin(Pinned(value))
            }
            case t == JSType.SYMBOL => ArkTSPayload.Pin(Pinned(value))
            case t == JSType.BIGINT => ArkTSPayload.Pin(Pinned(value))
            case t == JSType.EXTERNAL => ArkTSPayload.Pin(Pinned(value))
            case _ => throw ExternConversionException("Unknown ArkTS value type ${t.toString()}")
        }
        Extern<ArkTSRuntime>(payload)
    }

    static func jsValueOf(value: Extern<ArkTSRuntime>): NativeJSValue {
        evalPayload(Extern<ArkTSRuntime>.getPayload(value))
    }

    static func evalPayload(payload: Any): NativeJSValue {
        match (payload as ArkTSPayload) {
            case Some(h) => valueOfPayload(h)
            case None => throw foreignPayload()
        }
    }

    static func calleeOf(callee: Extern<ArkTSRuntime>): (NativeJSValue, ?NativeJSValue) {
        match (Extern<ArkTSRuntime>.getPayload(callee) as ArkTSPayload) {
            case Some(Method(function, receiver)) => (function.toJSValue(), valueOfPayload(receiver))
            case Some(h) => (valueOfPayload(h), None)
            case None => throw foreignPayload()
        }
    }

    private static func valueOfPayload(payload: ArkTSPayload): NativeJSValue {
        match (payload) {
            case Imm(value) => value
            case Text(s) => nativeString(environment, s)
            case Pin(owner) => owner.toJSValue()
            case Method(function, _) => function.toJSValue()
        }
    }

    private static func objectPinOf(payload: ArkTSPayload): ?Pinned {
        let pin = match (payload) {
            case Pin(p) => p
            case Method(p, _) => p
            case _ => return None
        }
        if (pin.kind == JSType.OBJECT || pin.kind == JSType.FUNCTION) { pin } else { None }
    }

    private static func scalarOf(boolean: Bool): Float64 { if (boolean) { 1.0 } else { 0.0 } }

    private static func immediateOfAny(value: Any): ?(JSTypeCode, Float64) {
        match (value) {
            case number: Float64 => (JSType.NUMBER, number)
            case boolean: Bool => (JSType.BOOLEAN, scalarOf(boolean))
            case option: Option<Float64> => match (option) {
                case Some(number) => (JSType.NUMBER, number)
                case None => (JSType.UNDEFINED, 0.0)
            }
            case option: Option<Bool> => match (option) {
                case Some(boolean) => (JSType.BOOLEAN, scalarOf(boolean))
                case None => (JSType.UNDEFINED, 0.0)
            }
            case option: Option<String> where option.isNone() => (JSType.UNDEFINED, 0.0)
            case _ => None
        }
    }

    private static func textOf(value: Any): ?String {
        match (value) {
            case text: String => text
            case option: Option<String> => option
            case _ => None
        }
    }

    private static func opArgOf(value: Any): ?OpArg {
        if (let Some(text) <- textOf(value)) { return Text(text) }
        if (let Some((kind, x)) <- immediateOfAny(value)) { return Plain(Scalar(kind, x)) }
        match (value) {
            case external: Extern<ArkTSRuntime> => match (Extern<ArkTSRuntime>.getPayload(external) as ArkTSPayload) {
                case Some(payload) => opArgOfPayload(payload)
                case None => None
            }
            case _ => None
        }
    }

    private static unsafe func lend(arg: OpArg): LentArg {
        match (arg) {
            case Plain(plain) => LentArg(nativeArgOf(plain), None)
            case Text(text) =>
                let bytes = acquireArrayRawData(text.rawData())
                var native = NativeArg()
                native.tag = AR_ARG_UTF8
                native.pinOrUtf8 = CPointer<Unit>(bytes.pointer)
                native.utf8Length = UIntNative(bytes.array.size)
                LentArg(native, bytes)
        }
    }

    private static func indexedOpFailed(status: Int32): Unit {
        if (status == NAPI_PENDING_EXCEPTION || status == AR_DEAD) {
            try { opFailed(environment, status) } catch (x: ArkTSNativeException) { throw indexError(x) }
        }
    }

    static func nativeStats(): NativeStats {
        var out = NativeStats()
        unsafe { ats_rt_ext_stats(environment.state, inout out) }
        out
    }

    static func nativePost(id: Int64): Int32 {
        unsafe { ats_rt_ext_post(environment.state, id) }
    }

    private static func cellOf(pin: ?Pinned): NativePin {
        match (pin) {
            case Some(p) => p.cell
            case None => NativePin()
        }
    }

    private static func payloadOfRead(environment: Environment, pinCache: PinCache, out: NativeOpResult,
        receiver: ArkTSPayload, target: Pinned, field: String, hint: ?Pinned): ArkTSPayload {
        if (out.kind > JSType.NUMBER && (out.flags & AR_RESULT_HIT) != 0) {
            if (let Some(p) <- hint) {
                return if (p.kind == JSType.FUNCTION) { Method(p, receiver) } else { ArkTSPayload.Pin(p) }
            }
        }
        let payload = payloadOfResult(environment, out, receiver)
        match (payload) {
            case Pin(p) => pinCache.remember(target.cell, field, p)
            case Method(p, _) => pinCache.remember(target.cell, field, p)
            case _ => ()
        }
        payload
    }

    private static func payloadOfResult(environment: Environment, out: NativeOpResult, receiver: ?ArkTSPayload): ArkTSPayload {
        if ((out.flags & AR_RESULT_TEXT) != 0) {
            let bytes = Array<UInt8>(Int64(out.textUtf8Length), repeat: 0)
            unsafe {
                let buffer = acquireArrayRawData(bytes)
                try { ats_rt_ext_text_take(environment.state, buffer.pointer, out.textUtf8Length) } finally { releaseArrayRawData(buffer) }
                return Text(String.withRawData(bytes))
            }
        }
        if (out.kind <= JSType.NUMBER) {
            return Imm(NativeJSValue(environment, NapiValue(), out.kind, number: out.scalar, boolean: out.kind == JSType.BOOLEAN && out.scalar != 0.0))
        }
        let pinned = Pinned.adopt(environment, out.pin, out.kind)
        match {
            case out.kind == JSType.FUNCTION => match (receiver) {
                case Some(r) => Method(pinned, r)
                case None => ArkTSPayload.Pin(pinned)
            }
            case out.kind <= JSType.BIGINT => ArkTSPayload.Pin(pinned)
            case _ => throw ExternConversionException("Unknown ArkTS value type ${out.kind}")
        }
    }

    private static func opFailed(environment: Environment, status: Int32): Nothing {
        if (status == AR_DEAD) { environment.checkAlive() }
        environment.runtimeFrame { nativeCheck(environment, status, checkPending: true) }
        throw ForeignRuntimeException("N-API operation failed: ${status}")
    }

    private static func payloadOf(value: Extern<ArkTSRuntime>): ArkTSPayload {
        match (Extern<ArkTSRuntime>.getPayload(value) as ArkTSPayload) {
            case Some(payload) => payload
            case None => throw foreignPayload()
        }
    }

    private static func foreignPayload(): ExternConversionException {
        ExternConversionException("Extern payload was not produced by ArkTSRuntime")
    }

    static func immediateOf(value: Extern<ArkTSRuntime>): ?NativeJSValue {
        match (Extern<ArkTSRuntime>.getPayload(value) as ArkTSPayload) {
            case Some(Imm(immediate)) => immediate
            case _ => None
        }
    }

    static func samePin(a: Extern<ArkTSRuntime>, b: Extern<ArkTSRuntime>): Bool {
        match ((Extern<ArkTSRuntime>.getPayload(a) as ArkTSPayload, Extern<ArkTSRuntime>.getPayload(b) as ArkTSPayload)) {
            case (Some(Pin(p)), Some(Pin(q))) => refEq(p, q)
            case (Some(Method(p, _)), Some(Method(q, _))) => refEq(p, q)
            case _ => false
        }
    }

    static func payloadKind(value: Extern<ArkTSRuntime>): String {
        match (Extern<ArkTSRuntime>.getPayload(value) as ArkTSPayload) {
            case Some(Imm(_)) => "Imm"
            case Some(Text(_)) => "Text"
            case Some(Pin(_)) => "Pin"
            case Some(Method(_, _)) => "Method"
            case None => "foreign payload"
        }
    }

    static func toJSValue(value: Any): NativeJSValue {
        match (value) {
            case number: Float64 => js.number(number)
            case external: Extern<ArkTSRuntime> => jsValueOf(external)
            case boolean: Bool => js.boolean(boolean)
            case text: String => text.toJS()
            case integer: Int64 => integer.toJS()
            case option: Option<Float64> => match (option) { case Some(n) => js.number(n) case None => undefinedValue }
            case option: Option<String> => match (option) { case Some(s) => s.toJS() case None => undefinedValue }
            case option: Option<Bool> => match (option) { case Some(b) => js.boolean(b) case None => undefinedValue }
            case convertible: ToJS => convertible.toJS()
            case _ => throw ExternConversionException("Unsupported conversion to ArkTS")
        }
    }

    static func fromJSValue<R>(value: NativeJSValue): R { probedFromJSValue<R>(value) }

    static func fromJSValueReflective<R>(value: NativeJSValue): R {
        match (TypeTag<R>() as JSReader) {
            case Some(reader) => (reader.read(value) as R).getOrThrow()
            case None => match (None<R>) {
                case _: Option<Extern<ArkTSRuntime>> => (retain(value) as R).getOrThrow()
                case _ => throw ExternConversionException("Unsupported conversion from ArkTS")
            }
        }
    }

    public static func undefined(): Extern<ArkTSRuntime> {
        run { undefinedExtern }
    }

    public static func null(): Extern<ArkTSRuntime> {
        run { retain(js.null().toJSValue()) }
    }

    public static func object(): Extern<ArkTSRuntime> {
        run { retain(js.object().toJSValue()) }
    }

    public static func global(): Extern<ArkTSRuntime> {
        run { retain(js.global.toJSValue()) }
    }

    public static func symbol(description!: String = ""): Extern<ArkTSRuntime> {
        run { retain(js.symbol(description: description).toJSValue()) }
    }

    public static func strictEqual(lhs: Extern<ArkTSRuntime>, rhs: Extern<ArkTSRuntime>): Bool {
        run { jsValueOf(lhs).strictEqual(jsValueOf(rhs)) }
    }

    public static func isNull(value: Extern<ArkTSRuntime>): Bool {
        run { jsValueOf(value).isNull() }
    }

    public static func isUndefined(value: Extern<ArkTSRuntime>): Bool {
        run { jsValueOf(value).isUndefined() }
    }

    public static func objectHasProperty(value: Extern<ArkTSRuntime>, key: String): Bool {
        run { objectOf(jsValueOf(value)).hasProperty(key) }
    }

    public static func objectKeys(value: Extern<ArkTSRuntime>): Array<String> {
        run { objectOf(jsValueOf(value)).keys() }
    }

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

    public static func requireArkModule(specifier: String): Extern<ArkTSRuntime> {
        run { retain(js.requireArkModule(specifier)) }
    }

    public static func requireSystemNativeModule(moduleName: String, prefix: ?String): Extern<ArkTSRuntime> {
        run { retain(js.requireSystemNativeModule(moduleName, prefix: prefix)) }
    }

    public static func function(body: (Array<Extern<ArkTSRuntime>>) -> Extern<ArkTSRuntime>): Extern<ArkTSRuntime> {
        run {
            let function = js.function { _, callInfo =>
                let arguments = Array<Extern<ArkTSRuntime>>(callInfo.size) { i => retain(callInfo[i]) }
                toJSValue(body(arguments))
            }
            retain(function.toJSValue())
        }
    }

    private static func objectOf(value: NativeJSValue): NativeJSValue {
        try {
            value.asObject()
        } catch (e: ArkTSNativeException) {
            throw memberError(e)
        }
    }
}
