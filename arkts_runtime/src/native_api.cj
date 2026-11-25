package arkts_runtime

// Declarations use the public N-API ABI. Environment and value pointers are opaque;
// neither the Ark VM layout nor ohos.ark_interop types appear in this boundary.
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

type NapiEnv = CPointer<Unit>
type NapiValue = CPointer<Unit>

// FastNative is limited to callback-free type/payload/singleton operations.
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
foreign func ats_rt_ext_create_function(state: CPointer<Unit>, id: Int64,
    call: CFunc<(Int64, UIntNative, CPointer<NapiValue>) -> NapiValue>,
    drop: CFunc<(Int64) -> Unit>, result: CPointer<NapiValue>): Int32
foreign func ats_rt_ext_create_external(state: CPointer<Unit>, id: Int64, drop: CFunc<(Int64)->Unit>, result: CPointer<NapiValue>): Int32
@FastNative
foreign func ats_rt_ext_external_id(state: CPointer<Unit>, value: NapiValue, id: CPointer<Int64>): Int32
@FastNative
foreign func ats_rt_ext_bigint_create(state: CPointer<Unit>, negative: Int32, bytes: CPointer<UInt8>, count: UIntNative, result: CPointer<NapiValue>): Int32
@FastNative
foreign func ats_rt_ext_bigint_size(state: CPointer<Unit>, value: NapiValue, count: CPointer<UIntNative>): Int32
@FastNative
foreign func ats_rt_ext_bigint_read(state: CPointer<Unit>, value: NapiValue, negative: CPointer<Int32>, bytes: CPointer<UInt8>, count: UIntNative): Int32
@FastNative
foreign func napi_create_string_utf16(env: NapiEnv, units: CPointer<UInt16>, count: UIntNative, result: CPointer<NapiValue>): Int32
foreign func napi_get_named_property(env: NapiEnv, value: NapiValue, name: CString, result: CPointer<NapiValue>): Int32

// May execute inherited setters; deliberately uses the normal FFI transition.
foreign func ats_rt_ext_create_array(env: NapiEnv, count: UIntNative, kinds: CPointer<Int32>,
    values: CPointer<NapiValue>, numbers: CPointer<Float64>, result: CPointer<NapiValue>): Int32

// Includes the integer-index type/bounds checks; property getters may reenter JS.
foreign func ats_rt_ext_get_array_element(env: NapiEnv, value: NapiValue, index: Int64,
    length: CPointer<UInt32>, result: CPointer<NapiValue>): Int32

// Numeric array conversion stays on ordinary FFI: indexed accessors can call JS/Cangjie.
foreign func ats_rt_ext_create_number_array(env: NapiEnv, numbers: CPointer<Float64>, count: UIntNative,
    result: CPointer<NapiValue>): Int32
foreign func ats_rt_ext_read_number_array(env: NapiEnv, value: NapiValue, numbers: CPointer<Float64>, count: UIntNative,
    index: CPointer<UInt32>, length: CPointer<UInt32>, badValue: CPointer<NapiValue>): Int32

// Reads only string length metadata, never copies/allocates an unbounded string.
@FastNative
foreign func ats_rt_ext_short_string_capacity(env: NapiEnv, value: NapiValue, capacity: CPointer<UIntNative>): Int32

// Copies at most 128 UTF-16 code units; no JS execution or unbounded work.
@FastNative
foreign func ats_rt_ext_copy_short_string(env: NapiEnv, value: NapiValue, bytes: CPointer<UInt8>,
    capacity: UIntNative, size: CPointer<UIntNative>): Int32

// Named/numeric keys are created inside the ordinary FFI property operation.
foreign func ats_rt_ext_get_property_utf8(env: NapiEnv, object: NapiValue, bytes: CPointer<UInt8>,
    length: UIntNative, result: CPointer<NapiValue>): Int32
foreign func ats_rt_ext_set_property_utf8(env: NapiEnv, object: NapiValue, bytes: CPointer<UInt8>,
    length: UIntNative, value: NapiValue): Int32
foreign func ats_rt_ext_get_number_property(env: NapiEnv, object: NapiValue, index: Float64,
    result: CPointer<NapiValue>): Int32

// Our own C-compatible result, independent of the VM's opaque value representation.
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
    var pin: CPointer<Unit> = CPointer<Unit>()
    var kind: Int32 = 0
    var flags: Int32 = 0
    var textLength: UIntNative = 0
}
const AR_RESULT_TEXT: Int32 = 2
@FastNative
foreign func ats_rt_ext_text_take(state: CPointer<Unit>, dst: CPointer<UInt8>, length: UIntNative): Unit
@C
struct NativeArg {
    var scalar: Float64 = 0.0
    var ptr: CPointer<Unit> = CPointer<Unit>()
    var length: UIntNative = 0
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
foreign func ats_rt_ext_stats(state: CPointer<Unit>, out: CPointer<NativeStats>): Unit
foreign func ats_rt_ext_element_get(state: CPointer<Unit>, target: CPointer<Unit>, index: Int64, out: CPointer<NativeOpResult>): Int32
foreign func ats_rt_ext_element_set(state: CPointer<Unit>, target: CPointer<Unit>, index: UInt32, value: CPointer<NativeArg>): Int32
foreign func ats_rt_ext_call(state: CPointer<Unit>, function: CPointer<Unit>, thisArg: CPointer<NativeArg>, args: CPointer<NativeArg>,
    argc: UIntNative, out: CPointer<NativeOpResult>): Int32
foreign func ats_rt_ext_set_named(state: CPointer<Unit>, target: CPointer<Unit>, key: CPointer<UInt8>,
    length: UIntNative, value: CPointer<NativeArg>): Int32
foreign func ats_rt_ext_get_named(state: CPointer<Unit>, target: CPointer<Unit>, key: CPointer<UInt8>,
    length: UIntNative, hint: CPointer<Unit>, out: CPointer<NativeOpResult>): Int32
const AR_ARG_PIN: Int32 = 1
const AR_ARG_UTF8: Int32 = 2
const AR_RESULT_HIT: Int32 = 1

@FastNative
foreign func ats_rt_ext_decode_value(env: NapiEnv, value: NapiValue): NativeValueInfo

@FastNative
foreign func ats_rt_ext_pin_is_array(state: CPointer<Unit>, pin: CPointer<Unit>): Int32
foreign func ats_rt_ext_element_read(env: NapiEnv, array: NapiValue, index: Int64, length: CPointer<UInt32>,
    result: CPointer<NapiValue>, info: CPointer<NativeValueInfo>): Int32
foreign func ats_rt_ext_element_write_f64(env: NapiEnv, array: NapiValue, index: UInt32, value: Float64): Int32
foreign func ats_rt_ext_element_write(env: NapiEnv, array: NapiValue, index: UInt32, value: NapiValue): Int32
