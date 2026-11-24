#ifndef ARKTS_RUNTIME_BACKEND_H
#define ARKTS_RUNTIME_BACKEND_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/**
 * C ABI for the private N-API bridge. No Ark VM layout is exposed.
 *
 * env and JS value arguments are borrowed N-API handles. Use them only on the
 * environment's owner thread, while it is alive and a handle scope is active.
 * JS value outputs are local handles in that scope, not owned references.
 * Buffers are borrowed for the duration of the call; callers provide their size.
 * State/reference handles must remain owned while used and belong to the same env.
 *
 * Unless documented otherwise, status returns are 0 on success or a napi_status
 * on failure. Outputs are valid on success, except for documented failure details.
 * JS-executing calls can leave an exception pending even with status 0. The caller
 * must check and clear it. Callbacks must not let exceptions cross the C boundary.
 */

/**
 * Run a queued task by ID. cancelled is 0 for work on the owner thread, or 1
 * during teardown. Cancellation handling must not enter the destroyed VM.
 */
typedef void (*ats_rt_ext_task_callback)(int64_t id, int32_t cancelled);

/**
 * Borrow a live env on its owner thread. Capture that thread and install dispatch
 * and cleanup hooks. Return an owned state handle, or NULL on initialization
 * failure. callback must remain callable until dispatcher teardown completes.
 */
void *ats_rt_ext_bind(void *env, ats_rt_ext_task_callback callback);

/** Drop the binding's state ownership share from any thread. Does not destroy env. */
void ats_rt_ext_release_state(void *state);

/** Return 1 if this is the captured native thread, otherwise 0. Does not test liveness. */
int32_t ats_rt_ext_is_owner(void *state);

/** Return 1 while env is alive, otherwise 0. May be queried from any thread. */
int32_t ats_rt_ext_alive(void *state);

/** Return 0 for live owner-thread access, 1 for dead/NULL state, or 2 for wrong thread. */
int32_t ats_rt_ext_access_status(void *state);

/**
 * Create an array from count parallel entries. kinds uses napi_valuetype codes.
 * Undefined/null need no payload. numbers supplies numbers and boolean 0/nonzero.
 * Other kinds use local handles from values. Arrays may be NULL when count is 0.
 * count must fit uint32_t. Insertion may invoke inherited setters and reenter JS.
 */
int32_t ats_rt_ext_create_array(void *env, size_t count, const int32_t *kinds,
    void *const *values, const double *numbers, void **result);

/**
 * Check array type and current length, then read index. Accessors may run JS.
 * Return -1 for a negative/out-of-range index; length then holds the current size.
 * Return napi_array_expected for a non-array. result is valid only on success.
 */
int32_t ats_rt_ext_get_array_element(void *env, void *value, int64_t index, uint32_t *length, void **result);

/**
 * Create an array from count doubles; count must fit uint32_t. Inherited setters
 * may reenter JS. Callers needing snapshot semantics must copy numbers first.
 */
int32_t ats_rt_ext_create_number_array(void *env, const double *numbers, size_t count, void **result);

/**
 * Read count array elements into a buffer of at least count doubles.
 * Recheck length before each read, preserving bounds when a getter shrinks value.
 * On -1, index and length identify the bounds failure. On napi_number_expected,
 * bad_value is the offending local handle and index identifies its position.
 * Accessors may reenter JS. The buffer may contain a prefix when the call fails.
 */
int32_t ats_rt_ext_read_number_array(void *env, void *value, double *numbers, size_t count,
    uint32_t *index, uint32_t *length, void **bad_value);

/**
 * Read string-length metadata without copying. For at most 128 UTF-16 units,
 * capacity is units * 3 + 1, including the UTF-8 terminator. Otherwise it is 0.
 * A zero capacity is a successful long-string result, not an error.
 */
int32_t ats_rt_ext_short_string_capacity(void *env, void *value, size_t *capacity);

/**
 * Copy a string of at most 128 UTF-16 units into bytes and append a terminator.
 * capacity must be at least units * 3 + 1. size excludes the terminator.
 * Reject longer strings or insufficient capacity with napi_invalid_arg.
 * Work is bounded and does not invoke JS callbacks.
 */
int32_t ats_rt_ext_copy_short_string(void *env, void *value, uint8_t *bytes, size_t capacity, size_t *size);

/**
 * Read a property using length UTF-8 bytes; no input terminator is required.
 * Embedded NULs use an explicit-length JS key. Getters/proxies may execute JS.
 */
int32_t ats_rt_ext_get_property_utf8(void *env, void *object, const uint8_t *bytes, size_t length, void **result);

/**
 * Write a property using length UTF-8 bytes; preserve embedded NULs in the key.
 * No input terminator is required. Setters/proxies may execute JS.
 */
int32_t ats_rt_ext_set_property_utf8(void *env, void *object, const uint8_t *bytes, size_t length, void *value);

/** Create a JS number key and read its property. Uses property semantics, not array bounds. */
int32_t ats_rt_ext_get_number_property(void *env, void *object, double index, void **result);

/** Decoded public N-API metadata. Keep this layout aligned with Cangjie's NativeValueInfo. */
typedef struct {
    /** Number payload, boolean 0/1, or 0 for other kinds. Valid when status is 0. */
    double scalar;
    /** napi_valuetype code. Valid when status is 0. */
    int32_t kind;
    /** N-API status from type/payload decoding. */
    int32_t status;
} ats_rt_ext_value_info;

/** Read type and primitive payload together. Returns no retained handle and invokes no JS. */
ats_rt_ext_value_info ats_rt_ext_decode_value(void *env, void *value);

/**
 * Queue an ID from any thread without executing its callback synchronously.
 * ID 0 only wakes reference draining; it does not invoke ats_rt_ext_task_callback.
 * Return napi_closing for dead/NULL state. Accepted nonzero IDs are dispatched
 * normally or receive cancellation during teardown.
 */
int32_t ats_rt_ext_post(void *state, int64_t id);

/** A fused op was called off the owner thread: run it posted. Nothing was done. */
#define ATS_RT_EXT_NOT_OWNER (-4)
/** A fused op was called after environment teardown. Nothing was done. */
#define ATS_RT_EXT_DEAD (-5)
/** A fused op does not apply to its operands (an element op on a non-array): take the generic path. Nothing was done. */
#define ATS_RT_EXT_GENERIC (-6)

/** A fused op's result: a copied scalar (kind 0..3) or a new pin the caller owns. */
typedef struct {
    double scalar;
    void *pin;
    int32_t kind;
    int32_t flags;
    size_t text_length;  /* ATS_RT_EXT_RESULT_TEXT: UTF-8 bytes waiting for ats_rt_ext_text_take */
} ats_rt_ext_op_result;

/** A value a fused op materializes itself: a scalar (kind 0..3), a pin, or UTF-8 text. */
#define ATS_RT_EXT_ARG_SCALAR 0
#define ATS_RT_EXT_ARG_PIN 1
#define ATS_RT_EXT_ARG_UTF8 2
typedef struct {
    double scalar;
    const void *ptr;   /* ATS_RT_EXT_ARG_PIN: the pin; ATS_RT_EXT_ARG_UTF8: the bytes */
    size_t length;     /* ATS_RT_EXT_ARG_UTF8: byte count */
    int32_t tag;
    int32_t kind;      /* ATS_RT_EXT_ARG_SCALAR: undefined 0, null 1, boolean 2, number 3 */
} ats_rt_ext_arg;

/** `target.key = value` for an object or function pin. Status as ats_rt_ext_get_named. */
int32_t ats_rt_ext_set_named(void *state, void *target, const uint8_t *key, size_t key_length, const ats_rt_ext_arg *value);

/**
 * `target[index]` for an array pin. Returns ATS_RT_EXT_INDEX_OUT_OF_RANGE, having run nothing,
 * when index is not an element, and ATS_RT_EXT_GENERIC when target is not an array. Whether it
 * is an array is found out once and kept on the pin.
 */
#define ATS_RT_EXT_INDEX_OUT_OF_RANGE (-1)
int32_t ats_rt_ext_element_get(void *state, void *target, int64_t index, ats_rt_ext_op_result *out);

/** `target[index] = value` for an array pin, index < UINT32_MAX. Statuses as ats_rt_ext_element_get. */
int32_t ats_rt_ext_element_set(void *state, void *target, uint32_t index, const ats_rt_ext_arg *value);

/**
 * 1 when the pin's value is an array, else 0, and 0 off the owner thread or after teardown. The
 * answer is kept on the pin. The first call may create a local: call it inside an open scope.
 */
int32_t ats_rt_ext_pin_is_array(void *state, void *pin);

/** `function.call(this_arg, ...args)` for a function pin. Status as ats_rt_ext_get_named. */
int32_t ats_rt_ext_call(void *state, void *function, const ats_rt_ext_arg *this_arg, const ats_rt_ext_arg *args, size_t argc,
                 ats_rt_ext_op_result *out);

/** Counters for tests; owner thread except the pin counters, which are atomic. */
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
void ats_rt_ext_stats(void *state, ats_rt_ext_stats_t *out);

/** ats_rt_ext_op_result.flags: the result is the hint pin itself; no pin was created. */
#define ATS_RT_EXT_RESULT_HIT 1
/**
 * ats_rt_ext_op_result.flags: a well-formed string of at most 255 UTF-16 units, copied as UTF-8; no pin
 * was created. Take its text_length bytes with ats_rt_ext_text_take before the next op. Strings with a
 * lone surrogate, or longer, are pinned instead.
 */
#define ATS_RT_EXT_RESULT_TEXT 2

/** Copies the last ATS_RT_EXT_RESULT_TEXT bytes to dst. Owner thread, leaf (no N-API). */
void ats_rt_ext_text_take(void *state, uint8_t *dst, size_t length);

/**
 * `target.key` for an object or function pin. On napi_ok, *out holds the result. On
 * napi_pending_exception the engine's exception is pending for the caller to take. `hint`
 * (nullable) is a pin the caller expects the result to be: when strictly equal it is returned
 * with ATS_RT_EXT_RESULT_HIT instead of a new pin.
 */
int32_t ats_rt_ext_get_named(void *state, void *target, const uint8_t *key, size_t key_length, void *hint, ats_rt_ext_op_result *out);

/** ats_rt_ext_open_scope opened nothing: call ats_rt_ext_drain, then open again. */
#define ATS_RT_EXT_DRAIN_FIRST (-2)

#define ATS_RT_EXT_SCOPE_DRAIN_CHECK 1
#define ATS_RT_EXT_SCOPE_IN_FLIGHT 2

/**
 * Open a runtime or user frame on the live owner thread; closing it restores the host budget.
 * With ATS_RT_EXT_SCOPE_IN_FLIGHT it also counts as in flight, so no pin is deleted until it closes.
 * With ATS_RT_EXT_SCOPE_DRAIN_CHECK, returns ATS_RT_EXT_DRAIN_FIRST, having opened nothing, when nothing is in
 * flight and finalized pins are waiting; the open after that drain omits it, as finalizers may
 * keep queueing pins meanwhile.
 */
int32_t ats_rt_ext_open_scope(void *state, void **scope, int32_t flags);

/** Delete finalized pins on the live owner thread, when nothing is in flight. Unbounded work. */
void ats_rt_ext_drain(void *state);

/** Close a scope opened by ats_rt_ext_open_scope (LIFO). Requires the same live owner thread. */
int32_t ats_rt_ext_close_scope(void *state, void *scope);

/**
 * Persist value (any kind) as a strong reference on the live owner thread. On success the caller
 * owns pin and must pass it to ats_rt_ext_unpin exactly once.
 */
int32_t ats_rt_ext_pin(void *state, void *value, void **pin);

/**
 * A napi_value for pin on the live owner thread. In alias mode it is the reference's own global
 * slot, valid in any scope until the pin is deleted; otherwise a local of the current scope.
 */
int32_t ats_rt_ext_pin_value(void *state, void *pin, void **value);

/**
 * Consume an owned pin exactly once, from any thread, without blocking. Queues deletion for the
 * owner thread; after teardown frees only native bookkeeping. Never calls into the VM.
 */
void ats_rt_ext_unpin(void *pin);

/** 1 when pins are read by alias (probed at bind), otherwise 0. */
int32_t ats_rt_ext_pin_read_mode(void *state);

/**
 * Invoke a registered function on its owner thread. argv contains argc borrowed
 * local handles. Return a local N-API value. No receiver argument is supplied.
 * The callback must contain its language exceptions before returning to C.
 */
typedef void *(*ats_rt_ext_function_callback)(int64_t id, size_t argc, void **argv);

/** Remove the managed root for id when its JS function/external is finalized. Must not throw. */
typedef void (*ats_rt_ext_function_finalizer)(int64_t id);

/**
 * Create a JS function carrying id and callback adapters on the live owner thread.
 * On success, JS finalization invokes drop(id). The caller must root its closure
 * before creation and undo that root on failure. Keep both callbacks callable.
 */
int32_t ats_rt_ext_create_function(void *state, int64_t id, ats_rt_ext_function_callback call,
    ats_rt_ext_function_finalizer drop, void **result);

/**
 * Create a JS external carrying a managed-object ID on the live owner thread.
 * Finalization invokes drop(id). The caller owns ID-root registration and failure
 * rollback; C++ stores no pointer to the managed object itself.
 */
int32_t ats_rt_ext_create_external(void *state, int64_t id, ats_rt_ext_function_finalizer drop, void **result);

/**
 * Read an ID from an external created by this bridge, on the live owner thread.
 * Reject unrecognized external data with napi_invalid_arg before dereferencing it.
 */
int32_t ats_rt_ext_external_id(void *state, void *value, int64_t *id);

/**
 * Create a bigint from length big-endian magnitude bytes. negative is 0 or 1.
 * An empty magnitude is zero. Requires the live owner thread; returns a local value.
 */
int32_t ats_rt_ext_bigint_create(void *state, int32_t negative, const uint8_t *bytes, size_t length, void **result);

/**
 * Return the bigint magnitude buffer size on the live owner thread.
 * length is the N-API word count times 8, so it may include leading zero padding.
 */
int32_t ats_rt_ext_bigint_size(void *state, void *value, size_t *length);

/**
 * Copy a bigint into length big-endian magnitude bytes; negative receives 0 or 1.
 * Use the size from ats_rt_ext_bigint_size, in multiples of 8. Requires the live owner
 * thread. A too-small word buffer is rejected with napi_invalid_arg on detection.
 */
int32_t ats_rt_ext_bigint_read(void *state, void *value, int32_t *negative, uint8_t *bytes, size_t length);
#ifdef __cplusplus
}
#endif
#endif
