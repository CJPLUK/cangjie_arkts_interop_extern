package arkts_runtime

const NAPI_ARRAY_EXPECTED: Int32 = 8
const NAPI_NUMBER_EXPECTED: Int32 = 6
const NAPI_PENDING_EXCEPTION: Int32 = 10
const AR_INDEX_OUT_OF_RANGE: Int32 = -1
const AR_DRAIN_FIRST: Int32 = -2
const AR_SCOPE_DRAIN_CHECK: Int32 = 1
const AR_SCOPE_IN_FLIGHT: Int32 = 2
const AR_NOT_OWNER: Int32 = -4
const AR_DEAD: Int32 = -5
const NAPI_INVALID_ARG: Int32 = 1
const AR_ACCESS_OK: Int32 = 0
const AR_ACCESS_DEAD: Int32 = 1

type NapiEnv = CPointer<Unit>
type NapiValue = CPointer<Unit>
type NativeState = CPointer<Unit>
type NativePin = CPointer<Unit>
type NapiHandleScope = CPointer<Unit>

@FastNative
foreign func napi_get_undefined(env: NapiEnv, result: CPointer<NapiValue>): Int32
@FastNative
foreign func napi_get_null(env: NapiEnv, result: CPointer<NapiValue>): Int32
@FastNative
foreign func napi_get_boolean(env: NapiEnv, value: Bool, result: CPointer<NapiValue>): Int32
@FastNative
foreign func napi_create_double(env: NapiEnv, value: Float64, result: CPointer<NapiValue>): Int32
@FastNative
foreign func napi_get_value_double(env: NapiEnv, value: NapiValue, result: CPointer<Float64>): Int32
@FastNative
foreign func napi_get_value_bool(env: NapiEnv, value: NapiValue, result: CPointer<Bool>): Int32
@FastNative
foreign func napi_typeof(env: NapiEnv, value: NapiValue, result: CPointer<Int32>): Int32
@FastNative
foreign func napi_create_object(env: NapiEnv, result: CPointer<NapiValue>): Int32
@FastNative
foreign func napi_get_global(env: NapiEnv, result: CPointer<NapiValue>): Int32
@FastNative
foreign func napi_create_array_with_length(env: NapiEnv, length: UIntNative, result: CPointer<NapiValue>): Int32
@FastNative
foreign func napi_get_array_length(env: NapiEnv, value: NapiValue, result: CPointer<UInt32>): Int32
@FastNative
foreign func napi_is_array(env: NapiEnv, value: NapiValue, result: CPointer<Bool>): Int32
foreign func napi_get_element(env: NapiEnv, value: NapiValue, index: UInt32, result: CPointer<NapiValue>): Int32
foreign func napi_set_element(env: NapiEnv, value: NapiValue, index: UInt32, element: NapiValue): Int32
foreign func napi_get_property(env: NapiEnv, value: NapiValue, key: NapiValue, result: CPointer<NapiValue>): Int32
foreign func napi_set_property(env: NapiEnv, value: NapiValue, key: NapiValue, element: NapiValue): Int32
foreign func napi_has_property(env: NapiEnv, value: NapiValue, key: NapiValue, result: CPointer<Bool>): Int32
@FastNative
foreign func napi_strict_equals(env: NapiEnv, lhs: NapiValue, rhs: NapiValue, result: CPointer<Bool>): Int32
foreign func napi_call_function(env: NapiEnv, receiver: NapiValue, function: NapiValue,
    count: UIntNative, args: CPointer<NapiValue>, result: CPointer<NapiValue>): Int32
@FastNative
foreign func napi_is_exception_pending(env: NapiEnv, result: CPointer<Bool>): Int32
@FastNative
foreign func napi_get_and_clear_last_exception(env: NapiEnv, result: CPointer<NapiValue>): Int32
@FastNative
foreign func napi_create_bigint_int64(env: NapiEnv, value: Int64, result: CPointer<NapiValue>): Int32
@FastNative
foreign func napi_create_bigint_uint64(env: NapiEnv, value: UInt64, result: CPointer<NapiValue>): Int32
@FastNative
foreign func napi_get_value_bigint_int64(env: NapiEnv, value: NapiValue, result: CPointer<Int64>, lossless: CPointer<Bool>): Int32
@FastNative
foreign func napi_get_value_bigint_uint64(env: NapiEnv, value: NapiValue, result: CPointer<UInt64>, lossless: CPointer<Bool>): Int32
@FastNative
foreign func napi_create_string_utf8(env: NapiEnv, bytes: CPointer<UInt8>, length: UIntNative, result: CPointer<NapiValue>): Int32
@FastNative
foreign func napi_get_value_string_utf8(env: NapiEnv, value: NapiValue, bytes: CPointer<UInt8>, capacity: UIntNative, length: CPointer<UIntNative>): Int32
foreign func napi_coerce_to_string(env: NapiEnv, value: NapiValue, result: CPointer<NapiValue>): Int32
@FastNative
foreign func napi_create_symbol(env: NapiEnv, description: NapiValue, result: CPointer<NapiValue>): Int32
foreign func napi_load_module(env: NapiEnv, path: CString, result: CPointer<NapiValue>): Int32
foreign func napi_throw_error(env: NapiEnv, code: CString, message: CString): Int32
foreign func ats_rt_ext_create_function(state: NativeState, id: Int64,
    call: CFunc<(Int64, UIntNative, CPointer<NapiValue>) -> NapiValue>,
    drop: CFunc<(Int64) -> Unit>, result: CPointer<NapiValue>): Int32
foreign func ats_rt_ext_create_external(state: NativeState, id: Int64, drop: CFunc<(Int64)->Unit>, result: CPointer<NapiValue>): Int32
@FastNative
foreign func ats_rt_ext_external_id(state: NativeState, value: NapiValue, id: CPointer<Int64>): Int32
@FastNative
foreign func ats_rt_ext_bigint_create(state: NativeState, negative: Int32, bigEndianMagnitude: CPointer<UInt8>, magnitudeLength: UIntNative, result: CPointer<NapiValue>): Int32
@FastNative
foreign func ats_rt_ext_bigint_size(state: NativeState, value: NapiValue, magnitudeLength: CPointer<UIntNative>): Int32
@FastNative
foreign func ats_rt_ext_bigint_read(state: NativeState, value: NapiValue, negative: CPointer<Int32>, bigEndianMagnitude: CPointer<UInt8>, magnitudeLength: UIntNative): Int32
@FastNative
foreign func napi_create_string_utf16(env: NapiEnv, units: CPointer<UInt16>, count: UIntNative, result: CPointer<NapiValue>): Int32
foreign func napi_get_named_property(env: NapiEnv, value: NapiValue, name: CString, result: CPointer<NapiValue>): Int32

foreign func ats_rt_ext_create_array(env: NapiEnv, count: UIntNative, kinds: CPointer<Int32>,
    values: CPointer<NapiValue>, numbers: CPointer<Float64>, result: CPointer<NapiValue>): Int32

foreign func ats_rt_ext_get_array_element(env: NapiEnv, value: NapiValue, index: Int64,
    length: CPointer<UInt32>, result: CPointer<NapiValue>): Int32

foreign func ats_rt_ext_create_number_array(env: NapiEnv, numbers: CPointer<Float64>, count: UIntNative,
    result: CPointer<NapiValue>): Int32
foreign func ats_rt_ext_read_number_array(env: NapiEnv, value: NapiValue, numbers: CPointer<Float64>, count: UIntNative,
    index: CPointer<UInt32>, length: CPointer<UInt32>, badValue: CPointer<NapiValue>): Int32

@FastNative
foreign func ats_rt_ext_short_string_capacity(env: NapiEnv, value: NapiValue, capacity: CPointer<UIntNative>): Int32

@FastNative
foreign func ats_rt_ext_copy_short_string(env: NapiEnv, value: NapiValue, bytes: CPointer<UInt8>,
    capacity: UIntNative, size: CPointer<UIntNative>): Int32

foreign func ats_rt_ext_get_property_utf8(env: NapiEnv, object: NapiValue, keyUtf8: CPointer<UInt8>,
    keyLength: UIntNative, result: CPointer<NapiValue>): Int32
foreign func ats_rt_ext_set_property_utf8(env: NapiEnv, object: NapiValue, keyUtf8: CPointer<UInt8>,
    keyLength: UIntNative, value: NapiValue): Int32
foreign func ats_rt_ext_get_number_property(env: NapiEnv, object: NapiValue, numberKey: Float64,
    result: CPointer<NapiValue>): Int32

@C
struct NativeValueInfo {
    let scalar: Float64
    let kind: Int32
    let status: Int32
    init(scalar: Float64, kind: Int32, status: Int32) {
        this.scalar = scalar; this.kind = kind; this.status = status
    }
}
@C
struct NativeOpResult {
    var scalar: Float64 = 0.0
    var pin: NativePin = NativePin()
    var kind: Int32 = 0
    var flags: Int32 = 0
    var textUtf8Length: UIntNative = 0
}
const AR_RESULT_TEXT: Int32 = 2
@FastNative
foreign func ats_rt_ext_text_take(state: NativeState, dst: CPointer<UInt8>, length: UIntNative): Unit
@C
struct NativeArg {
    var scalar: Float64 = 0.0
    var pinOrUtf8: CPointer<Unit> = CPointer<Unit>()
    var utf8Length: UIntNative = 0
    var tag: Int32 = 0
    var kind: Int32 = 0
}
@C
struct NativeStats {
    var opsSpilled: UInt64 = 0
    var opsScoped: UInt64 = 0
    var pinsCreated: UInt64 = 0
    var pinsDeleted: UInt64 = 0
    var budgetUnits: UInt32 = 0
    var budgetFramesOpen: UInt32 = 0
    var pinReadAlias: UInt32 = 0
    var budgetCapacity: UInt32 = 0
}
foreign func ats_rt_ext_stats(state: NativeState, out: CPointer<NativeStats>): Unit
foreign func ats_rt_ext_element_get(state: NativeState, target: NativePin, index: Int64, out: CPointer<NativeOpResult>): Int32
foreign func ats_rt_ext_element_set(state: NativeState, target: NativePin, index: UInt32, value: CPointer<NativeArg>): Int32
foreign func ats_rt_ext_call(state: NativeState, function: NativePin, thisArg: CPointer<NativeArg>, args: CPointer<NativeArg>,
    argc: UIntNative, out: CPointer<NativeOpResult>): Int32
foreign func ats_rt_ext_set_named(state: NativeState, target: NativePin, key: CPointer<UInt8>,
    length: UIntNative, value: CPointer<NativeArg>): Int32
foreign func ats_rt_ext_get_named(state: NativeState, target: NativePin, key: CPointer<UInt8>,
    length: UIntNative, hint: NativePin, out: CPointer<NativeOpResult>): Int32
const AR_ARG_PIN: Int32 = 1
const AR_ARG_UTF8: Int32 = 2
const AR_RESULT_HIT: Int32 = 1

@FastNative
foreign func ats_rt_ext_decode_value(env: NapiEnv, value: NapiValue): NativeValueInfo

@FastNative
foreign func ats_rt_ext_pin_is_array(state: NativeState, pin: NativePin): Int32
foreign func ats_rt_ext_element_read(env: NapiEnv, array: NapiValue, index: Int64, length: CPointer<UInt32>,
    result: CPointer<NapiValue>, info: CPointer<NativeValueInfo>): Int32
foreign func ats_rt_ext_element_write_f64(env: NapiEnv, array: NapiValue, index: UInt32, value: Float64): Int32
foreign func ats_rt_ext_element_write(env: NapiEnv, array: NapiValue, index: UInt32, value: NapiValue): Int32

private unsafe func fieldAt<T, F>(value: T, byteOffset: Int64): F where T <: CType, F <: CType {
    let copy = LibC.malloc<T>()
    if (copy.isNull()) { throw ForeignRuntimeException("Cannot check native struct layouts") }
    copy.write(value)
    let field = CPointer<F>(CPointer<UInt8>(copy) + byteOffset).read()
    LibC.free(copy)
    field
}

func nativeLayoutMismatch(): ?String {
    let info = NativeValueInfo(1.5, 7, 9)
    let infoMatches = sizeOf<NativeValueInfo>() == 16 && unsafe {
        fieldAt<NativeValueInfo, Float64>(info, 0) == 1.5 && fieldAt<NativeValueInfo, Int32>(info, 8) == 7 &&
            fieldAt<NativeValueInfo, Int32>(info, 12) == 9
    }
    if (!infoMatches) { return Some("NativeValueInfo") }
    var result = NativeOpResult()
    result.scalar = 1.5
    result.kind = 7
    result.flags = 9
    result.textUtf8Length = 11
    let resultMatches = sizeOf<NativeOpResult>() == 32 && unsafe {
        fieldAt<NativeOpResult, Float64>(result, 0) == 1.5 && fieldAt<NativeOpResult, UIntNative>(result, 8) == 0 &&
            fieldAt<NativeOpResult, Int32>(result, 16) == 7 && fieldAt<NativeOpResult, Int32>(result, 20) == 9 &&
            fieldAt<NativeOpResult, UIntNative>(result, 24) == 11
    }
    if (!resultMatches) { return Some("NativeOpResult") }
    var arg = NativeArg()
    arg.scalar = 1.5
    arg.utf8Length = 11
    arg.tag = 7
    arg.kind = 9
    let argMatches = sizeOf<NativeArg>() == 32 && unsafe {
        fieldAt<NativeArg, Float64>(arg, 0) == 1.5 && fieldAt<NativeArg, UIntNative>(arg, 8) == 0 &&
            fieldAt<NativeArg, UIntNative>(arg, 16) == 11 && fieldAt<NativeArg, Int32>(arg, 24) == 7 &&
            fieldAt<NativeArg, Int32>(arg, 28) == 9
    }
    if (!argMatches) { return Some("NativeArg") }
    var stats = NativeStats()
    stats.opsSpilled = 1
    stats.opsScoped = 2
    stats.pinsCreated = 3
    stats.pinsDeleted = 4
    stats.budgetUnits = 5
    stats.budgetFramesOpen = 6
    stats.pinReadAlias = 7
    stats.budgetCapacity = 8
    let statsMatches = sizeOf<NativeStats>() == 48 && unsafe {
        fieldAt<NativeStats, UInt64>(stats, 0) == 1 && fieldAt<NativeStats, UInt64>(stats, 8) == 2 &&
            fieldAt<NativeStats, UInt64>(stats, 16) == 3 && fieldAt<NativeStats, UInt64>(stats, 24) == 4 &&
            fieldAt<NativeStats, UInt32>(stats, 32) == 5 && fieldAt<NativeStats, UInt32>(stats, 36) == 6 &&
            fieldAt<NativeStats, UInt32>(stats, 40) == 7 && fieldAt<NativeStats, UInt32>(stats, 44) == 8
    }
    if (!statsMatches) { return Some("NativeStats") }
    None
}
