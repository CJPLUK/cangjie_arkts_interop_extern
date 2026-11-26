package arkts_runtime

import std.math.numeric.BigInt

struct NativeJSValue <: ToString {
    let environment: Environment
    let local: NapiValue
    let kind: JSTypeCode
    let number: Float64
    let boolean: Bool

    prop scalar: Float64 {
        get() { if (kind == JSType.BOOLEAN) { if (boolean) { 1.0 } else { 0.0 } } else { number } }
    }

    init(environment: Environment, value: NapiValue) {
        this.environment = environment
        local = value
        let decoded = unsafe { ats_rt_ext_decode_value(environment.env, value) }
        nativeCheck(environment, decoded.status)
        kind = decoded.kind
        number = decoded.scalar
        boolean = decoded.kind == 2 && decoded.scalar != 0.0
    }

    init(environment: Environment, value: NapiValue, kind: JSTypeCode, number!: Float64 = 0.0, boolean!: Bool = false) {
        this.environment = environment; local = value; this.kind = kind
        this.number = number; this.boolean = boolean
    }

    prop raw: NapiValue {
        get() {
            if (kind > 3) { return local }
            let env = environment.env
            var result = local
            match (kind) {
                case 0 => nativeCheck(environment, unsafe { napi_get_undefined(env, inout result) })
                case 1 => nativeCheck(environment, unsafe { napi_get_null(env, inout result) })
                case 2 => nativeCheck(environment, unsafe { napi_get_boolean(env, boolean, inout result) })
                case 3 => nativeCheck(environment, unsafe { napi_create_double(env, number, inout result) })
                case _ => ()
            }
            result
        }
    }
    func toJSValue(): NativeJSValue { this }
    func typeof(): JSTypeCode { kind }
    func isUndefined(): Bool { kind == 0 }
    func isNull(): Bool { kind == 1 }
    func isBoolean(): Bool { kind == 2 }
    func isNumber(): Bool { kind == 3 }
    func isString(): Bool { kind == 4 }
    func isFunction(): Bool { kind == 7 }
    func isBigInt(): Bool { kind == 9 }
    func isArray(): Bool {
        var result = false
        nativeCheck(environment, unsafe { napi_is_array(environment.env, raw, inout result) })
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
        let env = environment.env
        var size: UIntNative = 0
        var capacity: UIntNative = 0
        nativeCheck(environment, unsafe { ats_rt_ext_short_string_capacity(env, raw, inout capacity) })
        let short = capacity != 0
        if (!short) {
            nativeCheck(environment, unsafe { napi_get_value_string_utf8(env, raw, CPointer<UInt8>(), 0, inout size) })
            capacity = size + 1
        }
        let bytes = Array<UInt8>(Int64(capacity), repeat: 0)
        unsafe {
            let buffer = acquireArrayRawData(bytes)
            try {
                let status = if (short) {
                    ats_rt_ext_copy_short_string(env, raw, buffer.pointer, capacity, inout size)
                } else {
                    napi_get_value_string_utf8(env, raw, buffer.pointer, capacity, inout size)
                }
                nativeCheck(environment, status)
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
        nativeCheck(environment, unsafe { ats_rt_ext_external_id(environment.state, raw, inout id) })
        nativeExternalData(id)
    }
    func toBigInt(): BigInt {
        if (!isBigInt()) { throw ExternConversionException("Expected bigint") }
        var size: UIntNative = 0
        nativeCheck(environment, unsafe { ats_rt_ext_bigint_size(environment.state, raw, inout size) })
        if (size == 0) { return BigInt(0) }
        let bytes = Array<UInt8>(Int64(size), repeat: 0)
        var negative: Int32 = 0
        unsafe {
            let buffer = acquireArrayRawData(bytes)
            try { nativeCheck(environment, ats_rt_ext_bigint_read(environment.state, raw, inout negative, buffer.pointer, size)) }
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
                nativeCheck(environment, ats_rt_ext_get_property_utf8(environment.env, raw, buffer.pointer,
                    UIntNative(buffer.array.size), inout result), checkPending: true)
            } finally { releaseArrayRawData(buffer) }
        }
        NativeJSValue(environment, result)
    }
    func setProperty(key: String, value: NativeJSValue): Unit {
        expectObject()
        unsafe {
            let buffer = acquireArrayRawData(key.rawData())
            try {
                nativeCheck(environment, ats_rt_ext_set_property_utf8(environment.env, raw, buffer.pointer,
                    UIntNative(buffer.array.size), value.raw), checkPending: true)
            } finally { releaseArrayRawData(buffer) }
        }
    }
    func hasProperty(key: String): Bool {
        expectObject()
        var result = false
        nativeCheck(environment, unsafe { napi_has_property(environment.env, raw, nativeString(environment, key).raw, inout result) }, checkPending: true)
        result
    }
    func keys(): Array<String> {
        expectObject()
        objectKeysBecauseSomeEnginesIgnoreNapiKeyFilters()
    }
    private func objectKeysBecauseSomeEnginesIgnoreNapiKeyFilters(): Array<String> {
        let js = ArkTSRuntime.js
        let object = js.global.getProperty("Object")
        let keys = object.getProperty("keys").call([this], thisArg: object)
        Array<String>(keys.size) { i => keys.getElement(UInt32(i)).toString() }
    }
    func defineOwnProperty(key: String, value: NativeJSValue,
        isWritable!: Bool = true, isEnumerable!: Bool = true, isConfigurable!: Bool = true): Bool {
        expectObject()
        let js = ArkTSRuntime.js
        let descriptor = js.object()
        descriptor.setProperty("value", value)
        descriptor.setProperty("writable", js.boolean(isWritable))
        descriptor.setProperty("enumerable", js.boolean(isEnumerable))
        descriptor.setProperty("configurable", js.boolean(isConfigurable))
        let object = js.global.getProperty("Object")
        object.getProperty("defineProperty").call([this, js.string(key), descriptor], thisArg: object)
        true
    }
    operator func [](key: String): NativeJSValue { getProperty(key) }
    operator func [](key: String, value!: NativeJSValue): Unit { setProperty(key, value) }
    operator func [](index: Int64): NativeJSValue { getElement(index) }
    operator func [](index: Int64, value!: NativeJSValue): Unit { setElement(index, value) }
    func getElement(index: Int64): NativeJSValue {
        var length: UInt32 = 0
        var result = NapiValue()
        let status = unsafe { ats_rt_ext_get_array_element(environment.env, raw, index, inout length, inout result) }
        if (status == AR_INDEX_OUT_OF_RANGE) {
            throw ArkTSNativeException(34300001, "The accessing index is out of range, allowed: [0, ${length}), given: ${index}")
        }
        if (status == NAPI_ARRAY_EXPECTED) {
            throw ArkTSNativeException(34300005, "The ArkTS data types do not match, expect: array, given: ${typeName()}.")
        }
        nativeCheck(environment, status, checkPending: true)
        NativeJSValue(environment, result)
    }
    func setElement(index: Int64, value: NativeJSValue): Unit {
        asArray()
        if (index < 0) { throw ArkTSNativeException(34300001, "The accessing index is out of range, allowed: [0, ${size}), given: ${index}") }
        if (index > Int64(UInt32.Max)) { throw OverflowException() }
        setElement(UInt32(index), value)
        if (index == Int64(UInt32.Max)) {
            var length = NapiValue()
            nativeCheck(environment, unsafe { napi_create_double(environment.env, 0.0, inout length) })
            setProperty("length", NativeJSValue(environment, length))
        }
    }
    func strictEqual(other: NativeJSValue): Bool {
        var result = false
        nativeCheck(environment, unsafe { napi_strict_equals(environment.env, raw, other.raw, inout result) })
        result
    }
    func getProperty(key: NativeJSValue): NativeJSValue {
        expectObject()
        var result = NapiValue()
        let status = if (key.kind == 3) {
            unsafe { ats_rt_ext_get_number_property(environment.env, raw, key.number, inout result) }
        } else {
            unsafe { napi_get_property(environment.env, raw, key.raw, inout result) }
        }
        nativeCheck(environment, status, checkPending: true)
        NativeJSValue(environment, result)
    }
    func setProperty(key: NativeJSValue, value: NativeJSValue): Unit {
        expectObject()
        nativeCheck(environment, unsafe { napi_set_property(environment.env, raw, key.raw, value.raw) }, checkPending: true)
    }
    func getElement(index: UInt32): NativeJSValue {
        var result = NapiValue()
        nativeCheck(environment, unsafe { napi_get_element(environment.env, raw, index, inout result) }, checkPending: true)
        NativeJSValue(environment, result)
    }
    func setElement(index: UInt32, value: NativeJSValue): Unit {
        nativeCheck(environment, unsafe { napi_set_element(environment.env, raw, index, value.raw) }, checkPending: true)
    }
    prop size: Int64 {
        get() {
            var result: UInt32 = 0
            nativeCheck(environment, unsafe { napi_get_array_length(environment.env, raw, inout result) })
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
                ats_rt_ext_read_number_array(environment.env, raw, buffer.pointer, UIntNative(numbers.size),
                    inout index, inout length, inout badValue)
            } finally { releaseArrayRawData(buffer) }
        }
        if (status == AR_INDEX_OUT_OF_RANGE) {
            throw ArkTSNativeException(34300001, "The accessing index is out of range, allowed: [0, ${length}), given: ${index}")
        }
        if (status == NAPI_NUMBER_EXPECTED) {
            Float64.fromJS(NativeJSValue(environment, badValue))
        }
        nativeCheck(environment, status, checkPending: true)
        numbers
    }
    func call(args: Array<NativeJSValue>, thisArg!: NativeJSValue): NativeJSValue {
        var result = NapiValue()
        let status = if (args.size <= 8) {
            var values = VArray<NapiValue, $8>(repeat: NapiValue())
            for (i in 0..args.size) { values[i] = args[i].raw }
            unsafe { napi_call_function(environment.env, thisArg.raw, raw, UIntNative(args.size), inout values, inout result) }
        } else {
            let values = args.map({ v => v.raw })
            unsafe {
                let buffer = acquireArrayRawData(values)
                try { napi_call_function(environment.env, thisArg.raw, raw, UIntNative(values.size), buffer.pointer, inout result) }
                finally { releaseArrayRawData(buffer) }
            }
        }
        nativeCheck(environment, status, checkPending: true)
        NativeJSValue(environment, result)
    }
}

class PinCache {
    private static let SLOTS = 256
    private let receivers = Array<UIntNative>(SLOTS, repeat: 0)
    private let keys = Array<String>(SLOTS, repeat: "")
    private let values = Array<?Pinned>(SLOTS, repeat: None)

    @OverflowWrapping
    private static func slot(receiver: NativePin, key: String): Int64 {
        let mixed = UInt64(receiver.toUIntNative() >> 4) ^ UInt64(key.hashCode()) * 0x9E3779B97F4A7C15
        Int64((mixed >> 56) & 0xFF)
    }

    func hint(receiver: NativePin, key: String): ?Pinned {
        let i = slot(receiver, key)
        if (receivers[i] == receiver.toUIntNative() && keys[i] == key) { values[i] } else { None }
    }

    func remember(receiver: NativePin, key: String, value: Pinned): Unit {
        let i = slot(receiver, key)
        receivers[i] = receiver.toUIntNative()
        keys[i] = key
        values[i] = value
    }
}

class Pinned {
    let environment: Environment
    let cell: NativePin
    let kind: JSTypeCode
    init(value: NativeJSValue) {
        environment = value.environment
        kind = value.kind
        var result = NativePin()
        nativeCheck(environment, unsafe { ats_rt_ext_pin(environment.state, value.raw, inout result) })
        cell = result
    }
    private init(environment: Environment, cell: NativePin, kind: JSTypeCode) {
        this.environment = environment
        this.cell = cell
        this.kind = kind
    }

    static func adopt(environment: Environment, cell: NativePin, kind: JSTypeCode): Pinned {
        Pinned(environment, cell, kind)
    }
    ~init() { unsafe { ats_rt_ext_unpin(cell) } }

    func isArray(): Bool {
        kind == JSType.OBJECT && unsafe { ats_rt_ext_pin_is_array(environment.state, cell) } == 1
    }

    func elementRead(index: Int64): NativeJSValue {
        var length: UInt32 = 0
        var result = NapiValue()
        var info = NativeValueInfo(0.0, JSType.UNDEFINED, 0)
        let status = unsafe { ats_rt_ext_element_read(environment.env, toJSValue().raw, index, inout length, inout result, inout info) }
        if (status == AR_INDEX_OUT_OF_RANGE) {
            throw ArkTSNativeException(34300001, "The accessing index is out of range, allowed: [0, ${length}), given: ${index}")
        }
        nativeCheck(environment, status)
        NativeJSValue(environment, result, info.kind, number: info.scalar, boolean: info.kind == JSType.BOOLEAN && info.scalar != 0.0)
    }

    func elementWrite(index: UInt32, value: NativeJSValue): Unit {
        let status = if (value.kind == JSType.NUMBER) {
            unsafe { ats_rt_ext_element_write_f64(environment.env, toJSValue().raw, index, value.number) }
        } else {
            unsafe { ats_rt_ext_element_write(environment.env, toJSValue().raw, index, value.raw) }
        }
        nativeCheck(environment, status)
    }

    func toJSValue(): NativeJSValue {
        var result = NapiValue()
        nativeCheck(environment, unsafe { ats_rt_ext_pin_value(environment.state, cell, inout result) })
        NativeJSValue(environment, result, kind)
    }
}

func nativeString(environment: Environment, value: String): NativeJSValue {
    var result = NapiValue()
    unsafe {
        let buffer = acquireArrayRawData(value.rawData())
        try { nativeCheck(environment, napi_create_string_utf8(environment.env, buffer.pointer, UIntNative(buffer.array.size), inout result)) }
        finally { releaseArrayRawData(buffer) }
    }
    NativeJSValue(environment, result, 4)
}

private func stackDiscardingWhatItsGetterThrows(environment: Environment, error: NapiValue): ?String {
    let env = environment.env
    var stack = NapiValue()
    unsafe {
        let key = LibC.mallocCString("stack")
        let status = try { napi_get_named_property(env, error, key, inout stack) }
                     finally { LibC.free(key) }
        var stackPending = false
        napi_is_exception_pending(env, inout stackPending)
        if (status != 0 || stackPending) {
            var discarded = NapiValue()
            napi_get_and_clear_last_exception(env, inout discarded)
            return None
        }
        var stackKind: Int32 = -1
        if (napi_typeof(env, stack, inout stackKind) == 0 && stackKind == 4) {
            return Some(NativeJSValue(environment, stack).toString())
        }
    }
    None
}

func nativeCheck(environment: Environment, status: Int32, checkPending!: Bool = false): Unit {
    if (status == 0 && !checkPending) { return }
    let env = environment.env
    var pending = false
    unsafe { napi_is_exception_pending(env, inout pending) }
    if (status == 0 && !pending) { return }
    if (pending || status == NAPI_PENDING_EXCEPTION) {
        var error = NapiValue()
        unsafe { napi_get_and_clear_last_exception(env, inout error) }
        if (error.isNull()) { throw ForeignRuntimeException("ArkTS exception (message unavailable)") }
        var message = NapiValue()
        let converted = unsafe { napi_coerce_to_string(env, error, inout message) }
        if (converted == 0) {
            let text = NativeJSValue(environment, message).toString()
            var kind: Int32 = -1
            unsafe { napi_typeof(env, error, inout kind) }
            let formatted = if (kind == 4) { "message: ${text}" } else {
                text.replace(": ", "\n")
            }
            var detail = formatted
            if (kind == 6 || kind == 7) {
                if (let Some(stack) <- stackDiscardingWhatItsGetterThrows(environment, error)) { detail += "\n" + stack }
            }
            throw ForeignRuntimeException(detail)
        }
        unsafe { napi_get_and_clear_last_exception(env, inout error) }
        throw ForeignRuntimeException("ArkTS exception (message unavailable)")
    }
    throw ForeignRuntimeException("N-API operation failed: ${status}")
}
