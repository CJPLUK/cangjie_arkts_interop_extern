package arkts_runtime

import std.math.numeric.BigInt



/** Local N-API value; immediate payloads are copied so they can outlive scopes. */
struct NativeJSValue <: ToString {
    /** Owning environment and thread dispatcher; keeps the native session alive. */
    let session: NativeSession
    /** Scope-local N-API handle for heap values. Immediates use copied payloads instead. */
    let local: NapiValue
    /** Cached JS type, using the JSType constants. */
    let kind: Int32
    /** Copied numeric payload, meaningful only when kind is JSType.NUMBER. */
    let number: Float64
    /** Copied boolean payload, meaningful only when kind is JSType.BOOLEAN. */
    let boolean: Bool

    init(session: NativeSession, value: NapiValue) {
        this.session = session
        local = value
        let decoded = unsafe { ar_decode_value(session.env, value) }
        nativeCheck(session, decoded.status)
        kind = decoded.kind
        number = decoded.scalar
        boolean = decoded.kind == 2 && decoded.scalar != 0.0
    }

    // Factories and retained references already know their type. Immediate values
    // carry copied payloads, never a handle from a scope which may have closed.
    init(session: NativeSession, value: NapiValue, kind: Int32, number!: Float64 = 0.0, boolean!: Bool = false) {
        this.session = session; local = value; this.kind = kind
        this.number = number; this.boolean = boolean
    }

    prop raw: NapiValue {
        get() {
            // Heap handles are consumed only by checked N-API entry points.
            if (kind > 3) { return local }
            let env = session.env
            var result = local
            match (kind) {
                case 0 => nativeCheck(session, unsafe { napi_get_undefined(env, inout result) })
                case 1 => nativeCheck(session, unsafe { napi_get_null(env, inout result) })
                case 2 => nativeCheck(session, unsafe { napi_get_boolean(env, boolean, inout result) })
                case 3 => nativeCheck(session, unsafe { napi_create_double(env, number, inout result) })
                case _ => ()
            }
            result
        }
    }
    func toJSValue(): NativeJSValue { this }
    func typeof(): Int32 { kind }
    func isUndefined(): Bool { kind == 0 }
    func isNull(): Bool { kind == 1 }
    func isBoolean(): Bool { kind == 2 }
    func isNumber(): Bool { kind == 3 }
    func isString(): Bool { kind == 4 }
    func isFunction(): Bool { kind == 7 }
    func isBigInt(): Bool { kind == 9 }
    func isArray(): Bool {
        var result = false
        nativeCheck(session, unsafe { napi_is_array(session.env, raw, inout result) })
        result
    }
    func toNumber(): Float64 {
        if (!isNumber()) { throw ExternConversionException("Expected number") }
        number
    }
    func toBoolean(): Bool {
        if (!isBoolean()) { throw ExternConversionException("Expected boolean") }
        boolean
    }
    public func toString(): String {
        if (!isString()) { throw ArkTSNativeException(34300005, "The ArkTS data types do not match, expect: string, given: ${typeName()}.") }
        let env = session.env
        var size: UIntNative = 0
        var capacity: UIntNative = 0
        nativeCheck(session, unsafe { ar_short_string_capacity(env, raw, inout capacity) })
        let short = capacity != 0
        if (!short) {
            nativeCheck(session, unsafe { napi_get_value_string_utf8(env, raw, CPointer<UInt8>(), 0, inout size) })
            capacity = size + 1
        }
        let bytes = Array<UInt8>(Int64(capacity), repeat: 0)
        unsafe {
            let buffer = acquireArrayRawData(bytes)
            try {
                let status = if (short) {
                    ar_copy_short_string(env, raw, buffer.pointer, capacity, inout size)
                } else {
                    napi_get_value_string_utf8(env, raw, buffer.pointer, capacity, inout size)
                }
                nativeCheck(session, status)
                String.withRawData(bytes.slice(0, Int64(size)))
            } finally { releaseArrayRawData(buffer) }
        }
    }
    func typeName(): String {
        match (kind) {
            case 0 => "undefined"
            case 1 => "null"
            case 2 => "boolean"
            case 3 => "number"
            case 4 => "string"
            case 5 => "symbol"
            case 6 => "object"
            case 7 => "function"
            case 8 => "external"
            case 9 => "bigint"
            case _ => "unknown"
        }
    }
    func expectObject(): Unit {
        if (kind != 6 && kind != 7) {
            throw ArkTSNativeException(34300005, "The ArkTS data types do not match, expect: object, given: ${typeName()}.")
        }
    }
    func asObject(): NativeJSValue { expectObject(); this }
    func asArray(): NativeJSValue {
        if (!isArray()) { throw ArkTSNativeException(34300005, "The ArkTS data types do not match, expect: array, given: ${typeName()}.") }
        this
    }
    func asFunction(): NativeJSValue { this }
    func asString(): NativeJSValue { this }
    func asSymbol(): NativeJSValue { this }
    func asExternal(): NativeJSValue { this }
    func getData(): Object {
        var id: Int64 = 0
        nativeCheck(session, unsafe { ar_external_id(session.state, raw, inout id) })
        nativeExternalData(id)
    }
    func toBigInt(): BigInt {
        if (!isBigInt()) { throw ExternConversionException("Expected bigint") }
        var size: UIntNative = 0
        nativeCheck(session, unsafe { ar_bigint_size(session.state, raw, inout size) })
        if (size == 0) { return BigInt(0) }
        let bytes = Array<UInt8>(Int64(size), repeat: 0)
        var negative: Int32 = 0
        unsafe {
            let buffer = acquireArrayRawData(bytes)
            try { nativeCheck(session, ar_bigint_read(session.state, raw, inout negative, buffer.pointer, size)) }
            finally { releaseArrayRawData(buffer) }
        }
        let value = BigInt(true, bytes)
        if (negative != 0) { -value } else { value }
    }
    func getProperty(key: String): NativeJSValue {
        expectObject()
        var result = NapiValue()
        unsafe {
            let buffer = acquireArrayRawData(key.rawData())
            try {
                nativeCheck(session, ar_get_property_utf8(session.env, raw, buffer.pointer,
                    UIntNative(buffer.array.size), inout result), checkPending: true)
            } finally { releaseArrayRawData(buffer) }
        }
        NativeJSValue(session, result)
    }
    func setProperty(key: String, value: NativeJSValue): Unit {
        expectObject()
        unsafe {
            let buffer = acquireArrayRawData(key.rawData())
            try {
                nativeCheck(session, ar_set_property_utf8(session.env, raw, buffer.pointer,
                    UIntNative(buffer.array.size), value.raw), checkPending: true)
            } finally { releaseArrayRawData(buffer) }
        }
    }
    func hasProperty(key: String): Bool {
        expectObject()
        var result = false
        nativeCheck(session, unsafe { napi_has_property(session.env, raw, nativeString(session, key).raw, inout result) }, checkPending: true)
        result
    }
    func keys(): Array<String> {
        expectObject()
        // Some target N-API implementations ignore enumerable filters in
        // napi_get_all_property_names. Use the engine own-enumerable operation.
        let context = ArkTSRuntime.context
        let object = context.global.getProperty("Object")
        let keys = object.getProperty("keys").call([this], thisArg: object)
        Array<String>(keys.size) { i => keys.getElement(UInt32(i)).toString() }
    }
    func defineOwnProperty(key: String, value: NativeJSValue,
        isWritable!: Bool = true, isEnumerable!: Bool = true, isConfigurable!: Bool = true): Bool {
        expectObject()
        let context = ArkTSRuntime.context
        let descriptor = context.object()
        descriptor.setProperty("value", value)
        descriptor.setProperty("writable", context.boolean(isWritable))
        descriptor.setProperty("enumerable", context.boolean(isEnumerable))
        descriptor.setProperty("configurable", context.boolean(isConfigurable))
        let object = context.global.getProperty("Object")
        object.getProperty("defineProperty").call([this, context.string(key), descriptor], thisArg: object)
        true
    }
    operator func [](key: String): NativeJSValue { getProperty(key) }
    operator func [](key: String, value!: NativeJSValue): Unit { setProperty(key, value) }
    operator func [](index: Int64): NativeJSValue { getElement(index) }
    operator func [](index: Int64, value!: NativeJSValue): Unit { setElement(index, value) }
    func getElement(index: Int64): NativeJSValue {
        var length: UInt32 = 0
        var result = NapiValue()
        // Keep type/bounds semantics, but cross the ordinary FFI boundary once.
        let status = unsafe { ar_get_array_element(session.env, raw, index, inout length, inout result) }
        if (status == AR_INDEX_OUT_OF_RANGE) {
            throw ArkTSNativeException(34300001, "The accessing index is out of range, allowed: [0, ${length}), given: ${index}")
        }
        if (status == NAPI_ARRAY_EXPECTED) {
            throw ArkTSNativeException(34300005, "The ArkTS data types do not match, expect: array, given: ${typeName()}.")
        }
        nativeCheck(session, status, checkPending: true)
        NativeJSValue(session, result)
    }
    func setElement(index: Int64, value: NativeJSValue): Unit {
        asArray()
        if (index < 0) { throw ArkTSNativeException(34300001, "The accessing index is out of range, allowed: [0, ${size}), given: ${index}") }
        if (index > Int64(UInt32.Max)) { throw OverflowException() }
        setElement(UInt32(index), value)
        if (index == Int64(UInt32.Max)) {
            var length = NapiValue()
            nativeCheck(session, unsafe { napi_create_double(session.env, 0.0, inout length) })
            setProperty("length", NativeJSValue(session, length))
        }
    }
    func strictEqual(other: NativeJSValue): Bool {
        var result = false
        nativeCheck(session, unsafe { napi_strict_equals(session.env, raw, other.raw, inout result) })
        result
    }
    func getProperty(key: NativeJSValue): NativeJSValue {
        expectObject()
        var result = NapiValue()
        let status = if (key.kind == 3) {
            unsafe { ar_get_number_property(session.env, raw, key.number, inout result) }
        } else {
            unsafe { napi_get_property(session.env, raw, key.raw, inout result) }
        }
        nativeCheck(session, status, checkPending: true)
        NativeJSValue(session, result)
    }
    func setProperty(key: NativeJSValue, value: NativeJSValue): Unit {
        expectObject()
        nativeCheck(session, unsafe { napi_set_property(session.env, raw, key.raw, value.raw) }, checkPending: true)
    }
    func getElement(index: UInt32): NativeJSValue {
        var result = NapiValue()
        nativeCheck(session, unsafe { napi_get_element(session.env, raw, index, inout result) }, checkPending: true)
        NativeJSValue(session, result)
    }
    func setElement(index: UInt32, value: NativeJSValue): Unit {
        nativeCheck(session, unsafe { napi_set_element(session.env, raw, index, value.raw) }, checkPending: true)
    }
    prop size: Int64 {
        get() {
            var result: UInt32 = 0
            nativeCheck(session, unsafe { napi_get_array_length(session.env, raw, inout result) })
            Int64(result)
        }
    }
    func toNumberArray(): Array<Float64> {
        let numbers = Array<Float64>(size, repeat: 0.0)
        var index: UInt32 = 0
        var length: UInt32 = 0
        var badValue = NapiValue()
        let status = unsafe {
            let buffer = acquireArrayRawData(numbers)
            try {
                ar_read_number_array(session.env, raw, buffer.pointer, UIntNative(numbers.size),
                    inout index, inout length, inout badValue)
            } finally { releaseArrayRawData(buffer) }
        }
        if (status == AR_INDEX_OUT_OF_RANGE) {
            throw ArkTSNativeException(34300001, "The accessing index is out of range, allowed: [0, ${length}), given: ${index}")
        }
        if (status == NAPI_NUMBER_EXPECTED) {
            // Reuse the generic reader's exact conversion error for the first bad element.
            Float64.fromJS(NativeJSValue(session, badValue))
        }
        nativeCheck(session, status, checkPending: true)
        numbers
    }
    func call(args: Array<NativeJSValue>, thisArg!: NativeJSValue): NativeJSValue {
        let values = args.map({ v => v.raw })
        var result = NapiValue()
        unsafe {
            let buffer = acquireArrayRawData(values)
            try { nativeCheck(session, napi_call_function(session.env, thisArg.raw, raw,
                UIntNative(values.size), buffer.pointer, inout result), checkPending: true) }
            finally { releaseArrayRawData(buffer) }
        }
        NativeJSValue(session, result)
    }
}

/** Every heap value is rooted through an owned reference; disposal is queued on the JS thread. */
class NativeReference {
    let session: NativeSession
    private let reference: CPointer<Unit>
    private let kind: Int32
    init(value: NativeJSValue) {
        session = value.session
        kind = value.kind
        var result = CPointer<Unit>()
        let raw = value.raw
        var status = unsafe { ar_create_reference(session.state, raw, inout result) }
        if (status == NAPI_INVALID_ARG && kind != 6 && kind != 7) {
            status = unsafe { ar_create_boxed_reference(session.state, raw, inout result) }
        }
        nativeCheck(session, status)
        reference = result
    }
    ~init() { unsafe { ar_release_reference(session.state, reference) } }
    func toJSValue(): NativeJSValue {
        var result = NapiValue()
        var status = unsafe { ar_reference_value(session.state, reference, inout result) }
        if (status == AR_BOXED_REFERENCE) {
            status = unsafe { ar_boxed_reference_value(session.state, reference, inout result) }
        }
        nativeCheck(session, status)
        NativeJSValue(session, result, kind)
    }
}

func nativeString(session: NativeSession, value: String): NativeJSValue {
    var result = NapiValue()
    unsafe {
        let buffer = acquireArrayRawData(value.rawData())
        try { nativeCheck(session, napi_create_string_utf8(session.env, buffer.pointer, UIntNative(buffer.array.size), inout result)) }
        finally { releaseArrayRawData(buffer) }
    }
    NativeJSValue(session, result, 4)
}

func nativeCheck(session: NativeSession, status: Int32, checkPending!: Bool = false): Unit {
    if (status == 0 && !checkPending) { return }
    let env = session.env
    var pending = false
    unsafe { napi_is_exception_pending(env, inout pending) }
    if (status == 0 && !pending) { return }
    if (pending || status == NAPI_PENDING_EXCEPTION) {
        var error = NapiValue()
        unsafe { napi_get_and_clear_last_exception(env, inout error) }
        if (error.isNull()) { throw ArkTSNativeException(34300002, "ArkTS exception (message unavailable)") }
        var message = NapiValue()
        let converted = unsafe { napi_coerce_to_string(env, error, inout message) }
        if (converted == 0) {
            let text = NativeJSValue(session, message).toString()
            var kind: Int32 = -1
            unsafe { napi_typeof(env, error, inout kind) }
            let formatted = if (kind == 4) { "message: ${text}" } else {
                // Preserve the existing error name/message spelling in the runtime contract.
                text.replace(": ", "\n")
            }
            var stack = NapiValue()
            var detail = formatted
            if (kind == 6 || kind == 7) {
                unsafe {
                    let key = LibC.mallocCString("stack")
                    let status = try { napi_get_named_property(env, error, key, inout stack) }
                                 finally { LibC.free(key) }
                    var stackPending = false
                    napi_is_exception_pending(env, inout stackPending)
                    if (status == 0 && !stackPending) {
                        var stackKind: Int32 = -1
                        if (napi_typeof(env, stack, inout stackKind) == 0 && stackKind == 4) {
                            detail += "\n" + NativeJSValue(session, stack).toString()
                        }
                    } else {
                        // A custom stack getter must not replace the original exception.
                        var ignored = NapiValue()
                        napi_get_and_clear_last_exception(env, inout ignored)
                    }
                }
            }
            throw ArkTSNativeException(34300002, detail)
        }
        unsafe { napi_get_and_clear_last_exception(env, inout error) }
        throw ForeignRuntimeException("ArkTS exception (message unavailable)")
    }
    throw ForeignRuntimeException("N-API operation failed: ${status}")
}
