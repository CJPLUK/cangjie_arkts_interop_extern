package arkts_runtime

// Declarations use the public N-API ABI. Environment and value pointers are opaque;
// neither the Ark VM layout nor ohos.ark_interop types appear in this boundary.
const NAPI_ARRAY_EXPECTED: Int32 = 8
const NAPI_NUMBER_EXPECTED: Int32 = 6
const NAPI_PENDING_EXCEPTION: Int32 = 10
const AR_INDEX_OUT_OF_RANGE: Int32 = -1
const AR_SCOPE_NEEDS_DRAIN: Int32 = -2
const AR_BOXED_REFERENCE: Int32 = -3
const NAPI_INVALID_ARG: Int32 = 1

type NativeEnv = CPointer<Unit>
type NapiValue = CPointer<Unit>

// FastNative is limited to callback-free type/payload/singleton operations.
@FastNative
foreign func napi_get_undefined(env: NativeEnv, result: CPointer<NapiValue>): Int32
@FastNative
foreign func napi_get_null(env: NativeEnv, result: CPointer<NapiValue>): Int32
@FastNative
foreign func napi_get_boolean(env: NativeEnv, value: Bool, result: CPointer<NapiValue>): Int32
@FastNative
foreign func napi_create_double(env: NativeEnv, value: Float64, result: CPointer<NapiValue>): Int32
@FastNative
foreign func napi_get_value_double(env: NativeEnv, value: NapiValue, result: CPointer<Float64>): Int32
@FastNative
foreign func napi_get_value_bool(env: NativeEnv, value: NapiValue, result: CPointer<Bool>): Int32
@FastNative
foreign func napi_typeof(env: NativeEnv, value: NapiValue, result: CPointer<Int32>): Int32
foreign func napi_create_object(env: NativeEnv, result: CPointer<NapiValue>): Int32
foreign func napi_get_global(env: NativeEnv, result: CPointer<NapiValue>): Int32
foreign func napi_create_array_with_length(env: NativeEnv, length: UIntNative, result: CPointer<NapiValue>): Int32
foreign func napi_get_array_length(env: NativeEnv, value: NapiValue, result: CPointer<UInt32>): Int32
@FastNative
foreign func napi_is_array(env: NativeEnv, value: NapiValue, result: CPointer<Bool>): Int32
foreign func napi_get_element(env: NativeEnv, value: NapiValue, index: UInt32, result: CPointer<NapiValue>): Int32
foreign func napi_set_element(env: NativeEnv, value: NapiValue, index: UInt32, element: NapiValue): Int32
foreign func napi_get_property(env: NativeEnv, value: NapiValue, key: NapiValue, result: CPointer<NapiValue>): Int32
foreign func napi_set_property(env: NativeEnv, value: NapiValue, key: NapiValue, element: NapiValue): Int32
foreign func napi_has_property(env: NativeEnv, value: NapiValue, key: NapiValue, result: CPointer<Bool>): Int32
foreign func napi_strict_equals(env: NativeEnv, lhs: NapiValue, rhs: NapiValue, result: CPointer<Bool>): Int32
foreign func napi_call_function(env: NativeEnv, receiver: NapiValue, function: NapiValue,
    count: UIntNative, args: CPointer<NapiValue>, result: CPointer<NapiValue>): Int32
@FastNative
foreign func napi_is_exception_pending(env: NativeEnv, result: CPointer<Bool>): Int32
foreign func napi_get_and_clear_last_exception(env: NativeEnv, result: CPointer<NapiValue>): Int32
foreign func napi_create_bigint_int64(env: NativeEnv, value: Int64, result: CPointer<NapiValue>): Int32
foreign func napi_create_bigint_uint64(env: NativeEnv, value: UInt64, result: CPointer<NapiValue>): Int32
foreign func napi_get_value_bigint_int64(env: NativeEnv, value: NapiValue, result: CPointer<Int64>, lossless: CPointer<Bool>): Int32
foreign func napi_get_value_bigint_uint64(env: NativeEnv, value: NapiValue, result: CPointer<UInt64>, lossless: CPointer<Bool>): Int32
foreign func napi_create_string_utf8(env: NativeEnv, bytes: CPointer<UInt8>, length: UIntNative, result: CPointer<NapiValue>): Int32
foreign func napi_get_value_string_utf8(env: NativeEnv, value: NapiValue, bytes: CPointer<UInt8>, capacity: UIntNative, length: CPointer<UIntNative>): Int32
foreign func napi_coerce_to_string(env: NativeEnv, value: NapiValue, result: CPointer<NapiValue>): Int32
foreign func napi_create_symbol(env: NativeEnv, description: NapiValue, result: CPointer<NapiValue>): Int32
foreign func napi_load_module(env: NativeEnv, path: CString, result: CPointer<NapiValue>): Int32
foreign func napi_throw_error(env: NativeEnv, code: CString, message: CString): Int32
foreign func ar_create_function(state: CPointer<Unit>, id: Int64,
    call: CFunc<(Int64, UIntNative, CPointer<NapiValue>) -> NapiValue>,
    drop: CFunc<(Int64) -> Unit>, result: CPointer<NapiValue>): Int32
foreign func ar_create_external(state: CPointer<Unit>, id: Int64, drop: CFunc<(Int64)->Unit>, result: CPointer<NapiValue>): Int32
foreign func ar_external_id(state: CPointer<Unit>, value: NapiValue, id: CPointer<Int64>): Int32
foreign func ar_bigint_create(state: CPointer<Unit>, negative: Int32, bytes: CPointer<UInt8>, count: UIntNative, result: CPointer<NapiValue>): Int32
foreign func ar_bigint_size(state: CPointer<Unit>, value: NapiValue, count: CPointer<UIntNative>): Int32
foreign func ar_bigint_read(state: CPointer<Unit>, value: NapiValue, negative: CPointer<Int32>, bytes: CPointer<UInt8>, count: UIntNative): Int32
foreign func napi_create_string_utf16(env: NativeEnv, units: CPointer<UInt16>, count: UIntNative, result: CPointer<NapiValue>): Int32
foreign func napi_get_named_property(env: NativeEnv, value: NapiValue, name: CString, result: CPointer<NapiValue>): Int32

// May execute inherited setters; deliberately uses the normal FFI transition.
foreign func ar_create_array(env: NativeEnv, count: UIntNative, kinds: CPointer<Int32>,
    values: CPointer<NapiValue>, numbers: CPointer<Float64>, result: CPointer<NapiValue>): Int32

// Includes the integer-index type/bounds checks; property getters may reenter JS.
foreign func ar_get_array_element(env: NativeEnv, value: NapiValue, index: Int64,
    length: CPointer<UInt32>, result: CPointer<NapiValue>): Int32

// Numeric array conversion stays on ordinary FFI: indexed accessors can call JS/Cangjie.
foreign func ar_create_number_array(env: NativeEnv, numbers: CPointer<Float64>, count: UIntNative,
    result: CPointer<NapiValue>): Int32
foreign func ar_read_number_array(env: NativeEnv, value: NapiValue, numbers: CPointer<Float64>, count: UIntNative,
    index: CPointer<UInt32>, length: CPointer<UInt32>, badValue: CPointer<NapiValue>): Int32

// Reads only string length metadata, never copies/allocates an unbounded string.
@FastNative
foreign func ar_short_string_capacity(env: NativeEnv, value: NapiValue, capacity: CPointer<UIntNative>): Int32

// Copies at most 128 UTF-16 code units; no JS execution or unbounded work.
@FastNative
foreign func ar_copy_short_string(env: NativeEnv, value: NapiValue, bytes: CPointer<UInt8>,
    capacity: UIntNative, size: CPointer<UIntNative>): Int32

// Named/numeric keys are created inside the ordinary FFI property operation.
foreign func ar_get_property_utf8(env: NativeEnv, object: NapiValue, bytes: CPointer<UInt8>,
    length: UIntNative, result: CPointer<NapiValue>): Int32
foreign func ar_set_property_utf8(env: NativeEnv, object: NapiValue, bytes: CPointer<UInt8>,
    length: UIntNative, value: NapiValue): Int32
foreign func ar_get_number_property(env: NativeEnv, object: NapiValue, index: Float64,
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
@FastNative
foreign func ar_decode_value(env: NativeEnv, value: NapiValue): NativeValueInfo
