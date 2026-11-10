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
typedef void (*ar_task_callback)(int64_t id, int32_t cancelled);

/**
 * Borrow a live env on its JS thread. Capture that thread and install dispatch
 * and cleanup hooks. Return an owned state handle, or NULL on initialization
 * failure. callback must remain callable until dispatcher teardown completes.
 */
void *ar_bind(void *env, ar_task_callback callback);

/** Drop the binding's state ownership share from any thread. Does not destroy env. */
void ar_release_state(void *state);

/** Return 1 if this is the captured native thread, otherwise 0. Does not test liveness. */
int32_t ar_is_owner(void *state);

/** Return 1 while env is alive, otherwise 0. May be queried from any thread. */
int32_t ar_alive(void *state);

/** Return 0 for live owner-thread access, 1 for dead/NULL state, or 2 for wrong thread. */
int32_t ar_access_status(void *state);

/**
 * Create an array from count parallel entries. kinds uses napi_valuetype codes.
 * Undefined/null need no payload. numbers supplies numbers and boolean 0/nonzero.
 * Other kinds use local handles from values. Arrays may be NULL when count is 0.
 * count must fit uint32_t. Insertion may invoke inherited setters and reenter JS.
 */
int32_t ar_create_array(void *env, size_t count, const int32_t *kinds,
    void *const *values, const double *numbers, void **result);

/**
 * Check array type and current length, then read index. Accessors may run JS.
 * Return -1 for a negative/out-of-range index; length then holds the current size.
 * Return napi_array_expected for a non-array. result is valid only on success.
 */
int32_t ar_get_array_element(void *env, void *value, int64_t index, uint32_t *length, void **result);

/**
 * Create an array from count doubles; count must fit uint32_t. Inherited setters
 * may reenter JS. Callers needing snapshot semantics must copy numbers first.
 */
int32_t ar_create_number_array(void *env, const double *numbers, size_t count, void **result);

/**
 * Read count array elements into a buffer of at least count doubles.
 * Recheck length before each read, preserving bounds when a getter shrinks value.
 * On -1, index and length identify the bounds failure. On napi_number_expected,
 * bad_value is the offending local handle and index identifies its position.
 * Accessors may reenter JS. The buffer may contain a prefix when the call fails.
 */
int32_t ar_read_number_array(void *env, void *value, double *numbers, size_t count,
    uint32_t *index, uint32_t *length, void **bad_value);

/**
 * Read string-length metadata without copying. For at most 128 UTF-16 units,
 * capacity is units * 3 + 1, including the UTF-8 terminator. Otherwise it is 0.
 * A zero capacity is a successful long-string result, not an error.
 */
int32_t ar_short_string_capacity(void *env, void *value, size_t *capacity);

/**
 * Copy a string of at most 128 UTF-16 units into bytes and append a terminator.
 * capacity must be at least units * 3 + 1. size excludes the terminator.
 * Reject longer strings or insufficient capacity with napi_invalid_arg.
 * Work is bounded and does not invoke JS callbacks.
 */
int32_t ar_copy_short_string(void *env, void *value, uint8_t *bytes, size_t capacity, size_t *size);

/**
 * Read a property using length UTF-8 bytes; no input terminator is required.
 * Embedded NULs use an explicit-length JS key. Getters/proxies may execute JS.
 */
int32_t ar_get_property_utf8(void *env, void *object, const uint8_t *bytes, size_t length, void **result);

/**
 * Write a property using length UTF-8 bytes; preserve embedded NULs in the key.
 * No input terminator is required. Setters/proxies may execute JS.
 */
int32_t ar_set_property_utf8(void *env, void *object, const uint8_t *bytes, size_t length, void *value);

/** Create a JS number key and read its property. Uses property semantics, not array bounds. */
int32_t ar_get_number_property(void *env, void *object, double index, void **result);

/** Decoded public N-API metadata. Keep this layout aligned with Cangjie's NativeValueInfo. */
typedef struct {
    /** Number payload, boolean 0/1, or 0 for other kinds. Valid when status is 0. */
    double scalar;
    /** napi_valuetype code. Valid when status is 0. */
    int32_t kind;
    /** N-API status from type/payload decoding. */
    int32_t status;
} ar_value_info;

/** Read type and primitive payload together. Returns no retained handle and invokes no JS. */
ar_value_info ar_decode_value(void *env, void *value);

/**
 * Queue an ID from any thread without executing its callback synchronously.
 * ID 0 only wakes reference draining; it does not invoke ar_task_callback.
 * Return napi_closing for dead/NULL state. Accepted nonzero IDs are dispatched
 * normally or receive cancellation during teardown.
 */
int32_t ar_post(void *state, int64_t id);

/**
 * Open a scope on the live owner thread. Return 0, or -2 when the scope opened
 * successfully and references need draining. Both require ar_close_scope.
 * Drain through ar_drain_references; this entry does not drain on its fast path.
 */
int32_t ar_open_scope(void *state, void **scope);

/** Delete queued N-API references on the live owner thread. May perform unbounded work. */
void ar_drain_references(void *state);

/** Close a scope opened by ar_open_scope. Requires the same live owner thread. */
int32_t ar_close_scope(void *state, void *scope);

/**
 * Create a direct strong reference on the live owner thread. On success the
 * caller owns reference and must release it once with ar_release_reference.
 * Some implementations reject primitive values; the caller can try boxing.
 */
int32_t ar_create_reference(void *state, void *value, void **reference);

/**
 * Resolve a direct reference to a local handle on the live owner thread.
 * Return -3 for a boxed reference; value is then unset. Use the boxed helper.
 */
int32_t ar_reference_value(void *state, void *reference, void **value);

/**
 * Retain value in a private array's own data slot and strongly reference the box.
 * Requires the live owner thread. Success transfers one reference to the caller.
 * This compatibility path allocates a JS object; use ordinary FFI.
 */
int32_t ar_create_boxed_reference(void *state, void *value, void **reference);

/** Resolve a boxed reference's slot 0 on the live owner thread. Use ordinary FFI. */
int32_t ar_boxed_reference_value(void *state, void *reference, void **value);

/**
 * Consume an owned reference exactly once, from any thread. Queue N-API deletion
 * while alive; after teardown free only native bookkeeping. Never invoke JS or
 * delete a N-API reference on the calling finalizer thread.
 */
void ar_release_reference(void *state, void *reference);

/**
 * Invoke a registered function on its JS thread. argv contains argc borrowed
 * local handles. Return a local N-API value. No receiver argument is supplied.
 * The callback must contain its language exceptions before returning to C.
 */
typedef void *(*ar_function_callback)(int64_t id, size_t argc, void **argv);

/** Remove the managed root for id when its JS function/external is finalized. Must not throw. */
typedef void (*ar_function_finalizer)(int64_t id);

/**
 * Create a JS function carrying id and callback adapters on the live owner thread.
 * On success, JS finalization invokes drop(id). The caller must root its closure
 * before creation and undo that root on failure. Keep both callbacks callable.
 */
int32_t ar_create_function(void *state, int64_t id, ar_function_callback call,
    ar_function_finalizer drop, void **result);

/**
 * Create a JS external carrying a managed-object ID on the live owner thread.
 * Finalization invokes drop(id). The caller owns ID-root registration and failure
 * rollback; C++ stores no pointer to the managed object itself.
 */
int32_t ar_create_external(void *state, int64_t id, ar_function_finalizer drop, void **result);

/**
 * Read an ID from an external created by this bridge, on the live owner thread.
 * Reject unrecognized external data with napi_invalid_arg before dereferencing it.
 */
int32_t ar_external_id(void *state, void *value, int64_t *id);

/**
 * Create a bigint from length big-endian magnitude bytes. negative is 0 or 1.
 * An empty magnitude is zero. Requires the live owner thread; returns a local value.
 */
int32_t ar_bigint_create(void *state, int32_t negative, const uint8_t *bytes, size_t length, void **result);

/**
 * Return the bigint magnitude buffer size on the live owner thread.
 * length is the N-API word count times 8, so it may include leading zero padding.
 */
int32_t ar_bigint_size(void *state, void *value, size_t *length);

/**
 * Copy a bigint into length big-endian magnitude bytes; negative receives 0 or 1.
 * Use the size from ar_bigint_size, in multiples of 8. Requires the live owner
 * thread. A too-small word buffer is rejected with napi_invalid_arg on detection.
 */
int32_t ar_bigint_read(void *state, void *value, int32_t *negative, uint8_t *bytes, size_t length);
#ifdef __cplusplus
}
#endif
#endif
