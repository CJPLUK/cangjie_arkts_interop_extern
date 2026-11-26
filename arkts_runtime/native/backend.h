#ifndef ARKTS_RUNTIME_BACKEND_H
#define ARKTS_RUNTIME_BACKEND_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef void *ats_rt_ext_napi_env;
typedef void *ats_rt_ext_napi_value;
typedef void *ats_rt_ext_napi_handle_scope;
typedef void *ats_rt_ext_state;
typedef void *ats_rt_ext_pin_handle;
typedef int32_t ats_rt_ext_status;
typedef int32_t ats_rt_ext_napi_valuetype;
typedef int32_t ats_rt_ext_bool;
typedef int64_t ats_rt_ext_task_id;
typedef int64_t ats_rt_ext_root_id;

#define ATS_RT_EXT_INDEX_OUT_OF_RANGE (-1)

typedef void (*ats_rt_ext_task_callback)(ats_rt_ext_task_id id, ats_rt_ext_bool cancelled);

ats_rt_ext_state ats_rt_ext_bind(ats_rt_ext_napi_env env, ats_rt_ext_task_callback callback);

void ats_rt_ext_release_state(ats_rt_ext_state state);

ats_rt_ext_bool ats_rt_ext_is_owner(ats_rt_ext_state state);

ats_rt_ext_bool ats_rt_ext_alive(ats_rt_ext_state state);

#define ATS_RT_EXT_ACCESS_OK 0
#define ATS_RT_EXT_ACCESS_DEAD 1
#define ATS_RT_EXT_ACCESS_WRONG_THREAD 2
int32_t ats_rt_ext_access_status(ats_rt_ext_state state);

ats_rt_ext_status ats_rt_ext_create_array(ats_rt_ext_napi_env env, size_t count, const ats_rt_ext_napi_valuetype *kinds,
    const ats_rt_ext_napi_value *values, const double *numbers, ats_rt_ext_napi_value *result);

ats_rt_ext_status ats_rt_ext_get_array_element(ats_rt_ext_napi_env env, ats_rt_ext_napi_value value, int64_t index,
    uint32_t *length, ats_rt_ext_napi_value *result);

ats_rt_ext_status ats_rt_ext_create_number_array(ats_rt_ext_napi_env env, const double *numbers, size_t count,
    ats_rt_ext_napi_value *result);

ats_rt_ext_status ats_rt_ext_read_number_array(ats_rt_ext_napi_env env, ats_rt_ext_napi_value value, double *numbers,
    size_t count, uint32_t *index, uint32_t *length, ats_rt_ext_napi_value *bad_value);

ats_rt_ext_status ats_rt_ext_short_string_capacity(ats_rt_ext_napi_env env, ats_rt_ext_napi_value value, size_t *capacity);

ats_rt_ext_status ats_rt_ext_copy_short_string(ats_rt_ext_napi_env env, ats_rt_ext_napi_value value, uint8_t *bytes,
    size_t capacity, size_t *size);

ats_rt_ext_status ats_rt_ext_get_property_utf8(ats_rt_ext_napi_env env, ats_rt_ext_napi_value object,
    const uint8_t *key_utf8, size_t key_length, ats_rt_ext_napi_value *result);

ats_rt_ext_status ats_rt_ext_set_property_utf8(ats_rt_ext_napi_env env, ats_rt_ext_napi_value object,
    const uint8_t *key_utf8, size_t key_length, ats_rt_ext_napi_value value);

ats_rt_ext_status ats_rt_ext_get_number_property(ats_rt_ext_napi_env env, ats_rt_ext_napi_value object, double number_key,
    ats_rt_ext_napi_value *result);

typedef struct {
    double scalar;
    ats_rt_ext_napi_valuetype kind;
    ats_rt_ext_status status;
} ats_rt_ext_value_info;

ats_rt_ext_value_info ats_rt_ext_decode_value(ats_rt_ext_napi_env env, ats_rt_ext_napi_value value);

ats_rt_ext_status ats_rt_ext_post(ats_rt_ext_state state, ats_rt_ext_task_id id);

#define ATS_RT_EXT_NOT_OWNER (-4)
#define ATS_RT_EXT_DEAD (-5)
#define ATS_RT_EXT_GENERIC (-6)

typedef int32_t ats_rt_ext_result_flags;
#define ATS_RT_EXT_RESULT_HIT 1
#define ATS_RT_EXT_RESULT_TEXT 2

typedef struct {
    double scalar;
    ats_rt_ext_pin_handle pin;
    ats_rt_ext_napi_valuetype kind;
    ats_rt_ext_result_flags flags;
    size_t text_utf8_length;
} ats_rt_ext_op_result;

#define ATS_RT_EXT_ARG_SCALAR 0
#define ATS_RT_EXT_ARG_PIN 1
#define ATS_RT_EXT_ARG_UTF8 2
typedef struct {
    double scalar;
    const void *pin_or_utf8;
    size_t utf8_length;
    int32_t tag;
    ats_rt_ext_napi_valuetype kind;
} ats_rt_ext_arg;

ats_rt_ext_status ats_rt_ext_set_named(ats_rt_ext_state state, ats_rt_ext_pin_handle target, const uint8_t *key,
    size_t key_length, const ats_rt_ext_arg *value);

ats_rt_ext_status ats_rt_ext_element_get(ats_rt_ext_state state, ats_rt_ext_pin_handle target, int64_t index,
    ats_rt_ext_op_result *out);

ats_rt_ext_status ats_rt_ext_element_set(ats_rt_ext_state state, ats_rt_ext_pin_handle target, uint32_t index,
    const ats_rt_ext_arg *value);

ats_rt_ext_bool ats_rt_ext_pin_is_array(ats_rt_ext_state state, ats_rt_ext_pin_handle pin);

ats_rt_ext_status ats_rt_ext_call(ats_rt_ext_state state, ats_rt_ext_pin_handle function, const ats_rt_ext_arg *this_arg,
    const ats_rt_ext_arg *args, size_t argc, ats_rt_ext_op_result *out);

typedef struct {
    uint64_t ops_spilled;
    uint64_t ops_scoped;
    uint64_t pins_created;
    uint64_t pins_deleted;
    uint32_t budget_units;
    uint32_t budget_frames_open;
    uint32_t pin_read_alias;
    uint32_t budget_capacity;
} ats_rt_ext_stats_t;
void ats_rt_ext_stats(ats_rt_ext_state state, ats_rt_ext_stats_t *out);

void ats_rt_ext_text_take(ats_rt_ext_state state, uint8_t *dst, size_t length);

ats_rt_ext_status ats_rt_ext_get_named(ats_rt_ext_state state, ats_rt_ext_pin_handle target, const uint8_t *key,
    size_t key_length, ats_rt_ext_pin_handle hint, ats_rt_ext_op_result *out);

#define ATS_RT_EXT_DRAIN_FIRST (-2)

#define ATS_RT_EXT_SCOPE_DRAIN_CHECK 1
#define ATS_RT_EXT_SCOPE_IN_FLIGHT 2

ats_rt_ext_status ats_rt_ext_open_scope(ats_rt_ext_state state, ats_rt_ext_napi_handle_scope *scope, int32_t flags);

void ats_rt_ext_drain(ats_rt_ext_state state);

ats_rt_ext_status ats_rt_ext_close_scope(ats_rt_ext_state state, ats_rt_ext_napi_handle_scope scope);

ats_rt_ext_status ats_rt_ext_pin(ats_rt_ext_state state, ats_rt_ext_napi_value value, ats_rt_ext_pin_handle *pin);

ats_rt_ext_status ats_rt_ext_pin_value(ats_rt_ext_state state, ats_rt_ext_pin_handle pin, ats_rt_ext_napi_value *value);

void ats_rt_ext_unpin(ats_rt_ext_pin_handle pin);

#define ATS_RT_EXT_PIN_READ_FETCH 0
#define ATS_RT_EXT_PIN_READ_ALIAS 1
int32_t ats_rt_ext_pin_read_mode(ats_rt_ext_state state);

typedef ats_rt_ext_napi_value (*ats_rt_ext_function_callback)(ats_rt_ext_root_id id, size_t argc,
    ats_rt_ext_napi_value *argv);

typedef void (*ats_rt_ext_function_finalizer)(ats_rt_ext_root_id id);

ats_rt_ext_status ats_rt_ext_create_function(ats_rt_ext_state state, ats_rt_ext_root_id id,
    ats_rt_ext_function_callback call, ats_rt_ext_function_finalizer drop, ats_rt_ext_napi_value *result);

ats_rt_ext_status ats_rt_ext_create_external(ats_rt_ext_state state, ats_rt_ext_root_id id,
    ats_rt_ext_function_finalizer drop, ats_rt_ext_napi_value *result);

ats_rt_ext_status ats_rt_ext_external_id(ats_rt_ext_state state, ats_rt_ext_napi_value value, ats_rt_ext_root_id *id);

ats_rt_ext_status ats_rt_ext_bigint_create(ats_rt_ext_state state, ats_rt_ext_bool negative,
    const uint8_t *big_endian_magnitude, size_t magnitude_length, ats_rt_ext_napi_value *result);

ats_rt_ext_status ats_rt_ext_bigint_size(ats_rt_ext_state state, ats_rt_ext_napi_value value, size_t *magnitude_length);

ats_rt_ext_status ats_rt_ext_bigint_read(ats_rt_ext_state state, ats_rt_ext_napi_value value, ats_rt_ext_bool *negative,
    uint8_t *big_endian_magnitude, size_t magnitude_length);
#ifdef __cplusplus
}

static_assert(sizeof(void *) == 8 && sizeof(size_t) == 8, "the Cangjie mirrors in native_api.cj assume a 64-bit target");
static_assert(sizeof(ats_rt_ext_value_info) == 16 && offsetof(ats_rt_ext_value_info, scalar) == 0 &&
    offsetof(ats_rt_ext_value_info, kind) == 8 && offsetof(ats_rt_ext_value_info, status) == 12,
    "must match NativeValueInfo in native_api.cj");
static_assert(sizeof(ats_rt_ext_op_result) == 32 && offsetof(ats_rt_ext_op_result, scalar) == 0 &&
    offsetof(ats_rt_ext_op_result, pin) == 8 && offsetof(ats_rt_ext_op_result, kind) == 16 &&
    offsetof(ats_rt_ext_op_result, flags) == 20 && offsetof(ats_rt_ext_op_result, text_utf8_length) == 24,
    "must match NativeOpResult in native_api.cj");
static_assert(sizeof(ats_rt_ext_arg) == 32 && offsetof(ats_rt_ext_arg, scalar) == 0 &&
    offsetof(ats_rt_ext_arg, pin_or_utf8) == 8 && offsetof(ats_rt_ext_arg, utf8_length) == 16 &&
    offsetof(ats_rt_ext_arg, tag) == 24 && offsetof(ats_rt_ext_arg, kind) == 28,
    "must match NativeArg in native_api.cj");
static_assert(sizeof(ats_rt_ext_stats_t) == 48 && offsetof(ats_rt_ext_stats_t, ops_spilled) == 0 &&
    offsetof(ats_rt_ext_stats_t, ops_scoped) == 8 && offsetof(ats_rt_ext_stats_t, pins_created) == 16 &&
    offsetof(ats_rt_ext_stats_t, pins_deleted) == 24 && offsetof(ats_rt_ext_stats_t, budget_units) == 32 &&
    offsetof(ats_rt_ext_stats_t, budget_frames_open) == 36 && offsetof(ats_rt_ext_stats_t, pin_read_alias) == 40 &&
    offsetof(ats_rt_ext_stats_t, budget_capacity) == 44,
    "must match NativeStats in native_api.cj");
#endif
#endif
