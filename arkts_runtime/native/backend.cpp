#include "state.h"
#include <napi/native_api.h>
#include <atomic>
#include <mutex>
#include <thread>
#include <vector>
#include <memory>
#include <new>
#include <unordered_set>
#include <string>
#include <cstring>

int32_t statePost(State *s, int64_t id) try {
    std::lock_guard<std::mutex> lock(s->postMutex);
    if (!s->alive.load()) return napi_closing;
    auto item = std::make_unique<int64_t>(id);
    auto status = napi_call_threadsafe_function(s->dispatcher, item.get(), napi_tsfn_nonblocking);
    if (status == napi_ok) item.release();
    return status;
} catch (...) { return napi_generic_failure; }

namespace {
void retain(State *s) { s->owners.fetch_add(1); }
void release(State *s) { if (s->owners.fetch_sub(1) == 1) delete s; }
void finalized(napi_env, void *data, void *) { release(static_cast<State *>(data)); }
bool isOwner(State *s) { return stateIsOwner(s); }
int32_t post(State *s, int64_t id) { return statePost(s, id); }

void dispatch(napi_env env, napi_value, void *context, void *data) {
    auto *s = static_cast<State *>(context);
    std::unique_ptr<int64_t> id(static_cast<int64_t *>(data));
    int64_t task = id ? *id : kTaskWake;
    if (task == kTaskTurnEnd) { s->budget.turnEnded(); return; }
    if (!env || !s->alive.load()) {
        if (task > 0) s->callback(task, 1);
        return;
    }
    if (s->opDepth == 0) s->pins.drain(s);
    if (task > 0) s->callback(task, 0);
}

void cleanup(void *data) {
    auto *s = static_cast<State *>(data);
    std::lock_guard<std::mutex> lock(s->postMutex);
    s->alive.store(false);
    s->pins.cleanup(s);
    napi_release_threadsafe_function(s->dispatcher, napi_tsfn_abort);
}
}  // namespace

AtsRtExtPin *PinTable::create(State *s, napi_value value, napi_status *status) {
    auto *pin = new (std::nothrow) AtsRtExtPin{s, nullptr, nullptr, nullptr};
    if (!pin) { *status = napi_generic_failure; return nullptr; }
    *status = napi_create_strong_reference(s->env, value, &pin->strong);
    if (*status == napi_ok && read == PinRead::Alias) *status = napi_get_strong_reference_value(s->env, pin->strong, &pin->alias);
    if (*status != napi_ok) {
        if (pin->strong) napi_delete_strong_reference(s->env, pin->strong);
        delete pin;
        return nullptr;
    }
    retain(s);
    s->pinsCreated.fetch_add(1, std::memory_order_relaxed);
    return pin;
}

napi_status PinTable::value(State *s, const AtsRtExtPin *pin, napi_value *result) const {
    if (pin->alias) { *result = pin->alias; return napi_ok; }
    return napi_get_strong_reference_value(s->env, pin->strong, result);
}

bool PinTable::push(AtsRtExtPin *pin) {
    // Counted before it is published, so a drain that takes it never sees `pending` below zero.
    pending.fetch_add(1, std::memory_order_relaxed);
    AtsRtExtPin *head = deaths.load(std::memory_order_acquire);
    do {
        if (head == tombstone()) {
            pending.fetch_sub(1, std::memory_order_relaxed);
            State *s = pin->state;
            delete pin;
            release(s);
            return false;
        }
        pin->nextDead = head;
    } while (!deaths.compare_exchange_weak(head, pin, std::memory_order_acq_rel, std::memory_order_acquire));
    return head == nullptr && !wakeQueued.exchange(true);
}

void PinTable::drain(State *s, const AtsRtExtPin *const *keep, size_t keepCount) {
    wakeQueued.store(false);
    AtsRtExtPin *head = deaths.exchange(nullptr, std::memory_order_acq_rel);
    if (head == tombstone()) { deaths.store(tombstone()); return; }
    while (head) {
        AtsRtExtPin *next = head->nextDead;
        bool kept = false;
        for (size_t i = 0; i < keepCount; ++i) kept = kept || keep[i] == head;
        if (kept) {
            pending.fetch_sub(1, std::memory_order_relaxed);
            if (push(head)) post(s, 0);
        } else {
            napi_delete_strong_reference(s->env, head->strong);
            delete head;
            pending.fetch_sub(1, std::memory_order_relaxed);
            s->pinsDeleted.fetch_add(1, std::memory_order_relaxed);
            release(s);
        }
        head = next;
    }
}

void PinTable::cleanup(State *s) {
    AtsRtExtPin *head = deaths.exchange(tombstone(), std::memory_order_acq_rel);
    while (head && head != tombstone()) {
        AtsRtExtPin *next = head->nextDead;
        napi_delete_strong_reference(s->env, head->strong);
        delete head;
        release(s);
        head = next;
    }
}

void PinTable::probe(State *s) {
    napi_handle_scope scope;
    if (napi_open_handle_scope(s->env, &scope) != napi_ok) return;
    napi_value object, a = nullptr, b = nullptr;
    napi_strong_ref ref = nullptr;
    if (napi_create_object(s->env, &object) == napi_ok &&
        napi_create_strong_reference(s->env, object, &ref) == napi_ok &&
        napi_get_strong_reference_value(s->env, ref, &a) == napi_ok &&
        napi_get_strong_reference_value(s->env, ref, &b) == napi_ok && a && a == b) {
        read = PinRead::Alias;
    }
    if (ref) napi_delete_strong_reference(s->env, ref);
    napi_close_handle_scope(s->env, scope);
}

extern "C" void *ats_rt_ext_bind(void *raw, ats_rt_ext_task_callback callback) try {
    if (!raw || !callback) return nullptr;
    auto s = std::make_unique<State>();
    s->env = static_cast<napi_env>(raw); s->owner = std::this_thread::get_id(); s->callback = callback;
    napi_value name;
    if (napi_create_string_utf8(s->env, "ArkTSRuntime", NAPI_AUTO_LENGTH, &name) != napi_ok) return nullptr;
    if (napi_create_threadsafe_function(s->env, nullptr, nullptr, name, 0, 1, s.get(),
        finalized, s.get(), dispatch, &s->dispatcher) != napi_ok) return nullptr;
    retain(s.get());
    if (napi_add_env_cleanup_hook(s->env, cleanup, s.get()) != napi_ok) {
        auto *failed = s.release();
        napi_release_threadsafe_function(failed->dispatcher, napi_tsfn_abort);
        release(failed); return nullptr;
    }
    if (napi_unref_threadsafe_function(s->env, s->dispatcher) != napi_ok) {
        napi_remove_env_cleanup_hook(s->env, cleanup, s.get());
        auto *failed = s.release();
        napi_release_threadsafe_function(failed->dispatcher, napi_tsfn_abort);
        release(failed); return nullptr;
    }
    s->pins.probe(s.get());
    return s.release();
} catch (...) { return nullptr; }
extern "C" int32_t ats_rt_ext_is_owner(void *raw) {
    auto *s = static_cast<State *>(raw); return s && isOwner(s);
}
extern "C" int32_t ats_rt_ext_alive(void *raw) {
    auto *s = static_cast<State *>(raw); return s && s->alive.load();
}
// Leaf: no allocation, locks, N-API calls or callbacks. Safe for @FastNative.
extern "C" int32_t ats_rt_ext_access_status(void *raw) {
    if (!ats_rt_ext_alive(raw)) return 1;
    return ats_rt_ext_is_owner(raw) ? 0 : 2;
}
extern "C" int32_t ats_rt_ext_post(void *raw, int64_t id) {
    auto *s = static_cast<State *>(raw);
    if (!s) return napi_closing;
    return post(s, id);
}
extern "C" int32_t ats_rt_ext_open_scope(void *raw, void **scope, int32_t flags) try {
    auto *s = static_cast<State *>(raw);
    if (ats_rt_ext_access_status(raw) != 0) return napi_generic_failure;
    bool inFlight = flags & ATS_RT_EXT_SCOPE_IN_FLIGHT;
    if ((flags & ATS_RT_EXT_SCOPE_DRAIN_CHECK) && s->opDepth == 0 && s->pins.hasDeaths()) return ATS_RT_EXT_DRAIN_FIRST;
    // Grown before the scope opens, so the push below cannot fail with the scope open.
    if (s->brackets.size() == s->brackets.capacity()) s->brackets.reserve(2 * s->brackets.size() + 8);
    auto status = napi_open_handle_scope(s->env, reinterpret_cast<napi_handle_scope *>(scope));
    if (status == napi_ok) {
        if (inFlight) ++s->opDepth;
        s->brackets.push_back({s->budget.enter(), inFlight});
    }
    return status;
} catch (...) { return napi_generic_failure; }
// Ordinary FFI: deletes any number of references.
extern "C" void ats_rt_ext_drain(void *raw) {
    auto *s = static_cast<State *>(raw);
    if (ats_rt_ext_access_status(raw) == 0 && s->opDepth == 0) s->pins.drain(s);
}
extern "C" int32_t ats_rt_ext_close_scope(void *raw, void *scope) {
    auto *s = static_cast<State *>(raw);
    if (ats_rt_ext_access_status(raw) != 0) return napi_generic_failure;
    auto bracket = s->brackets.back();
    s->brackets.pop_back();
    if (bracket.inFlight) --s->opDepth;
    s->budget.exit(bracket.units);
    return napi_close_handle_scope(s->env, static_cast<napi_handle_scope>(scope));
}
extern "C" int32_t ats_rt_ext_pin(void *raw, void *value, void **pin) {
    auto *s = static_cast<State *>(raw);
    if (ats_rt_ext_access_status(raw) != 0) return napi_generic_failure;
    napi_status status;
    *pin = s->pins.create(s, static_cast<napi_value>(value), &status);
    return status;
}
extern "C" int32_t ats_rt_ext_pin_value(void *raw, void *pin, void **value) {
    auto *s = static_cast<State *>(raw);
    if (!pin || ats_rt_ext_access_status(raw) != 0) return napi_generic_failure;
    return s->pins.value(s, static_cast<AtsRtExtPin *>(pin), reinterpret_cast<napi_value *>(value));
}
extern "C" void ats_rt_ext_unpin(void *raw) {
    auto *pin = static_cast<AtsRtExtPin *>(raw);
    if (!pin) return;
    State *s = pin->state;
    if (s->pins.push(pin)) post(s, 0);
}
extern "C" int32_t ats_rt_ext_pin_read_mode(void *raw) {
    return static_cast<State *>(raw)->pins.read == PinRead::Alias ? 1 : 0;
}

extern "C" void ats_rt_ext_release_state(void *raw) { if (raw) release(static_cast<State *>(raw)); }

namespace {
using FunctionCallback = void *(*)(int64_t, size_t, void **);
using FunctionFinalizer = void (*)(int64_t);
struct FunctionData { State *state; int64_t id; FunctionCallback call; FunctionFinalizer drop; };
napi_value invoke(napi_env env, napi_callback_info info) try {
    napi_value stack[8];
    size_t count = 8; void *data = nullptr;
    if (napi_get_cb_info(env, info, &count, stack, nullptr, &data) != napi_ok) return nullptr;
    auto *f = static_cast<FunctionData *>(data);
    // The engine closes this callback's scope on return: whatever ops leak in here dies with it.
    ats_rt_ext::HostBudget::Frame frame(f->state->budget);
    if (count <= 8) return static_cast<napi_value>(f->call(f->id, count, reinterpret_cast<void **>(stack)));
    std::vector<napi_value> args(count);
    if (napi_get_cb_info(env, info, &count, args.data(), nullptr, nullptr) != napi_ok) return nullptr;
    return static_cast<napi_value>(f->call(f->id, count, reinterpret_cast<void **>(args.data())));
} catch (...) { napi_throw_error(env, nullptr, "Native callback allocation failed"); return nullptr; }
void dropFunction(napi_env, void *data, void *) {
    std::unique_ptr<FunctionData> f(static_cast<FunctionData *>(data));
    f->drop(f->id);
}
}
extern "C" int32_t ats_rt_ext_create_function(void *raw, int64_t id, FunctionCallback call,
    FunctionFinalizer drop, void **result) try {
    auto *s = static_cast<State *>(raw);
    if (!ats_rt_ext_alive(raw) || !ats_rt_ext_is_owner(raw)) return napi_generic_failure;
    auto f = std::make_unique<FunctionData>(FunctionData{s, id, call, drop});
    napi_value function;
    auto status = napi_create_function(s->env, nullptr, 0, invoke, f.get(), &function);
    if (status != napi_ok) return status;
    status = napi_add_finalizer(s->env, function, f.get(), dropFunction, nullptr, nullptr);
    if (status != napi_ok) return status;
    f.release(); *result = function; return napi_ok;
} catch (...) { return napi_generic_failure; }
namespace {
struct ExternalData { int64_t id; FunctionFinalizer drop; };
std::mutex externalMutex;
std::unordered_set<ExternalData *> externalData;
void dropExternal(napi_env, void *data, void *) {
    std::unique_ptr<ExternalData> external(static_cast<ExternalData *>(data));
    { std::lock_guard<std::mutex> lock(externalMutex); externalData.erase(external.get()); }
    external->drop(external->id);
}
}
extern "C" int32_t ats_rt_ext_create_external(void *raw, int64_t id, FunctionFinalizer drop, void **result) try {
    auto *s = static_cast<State *>(raw);
    if (!ats_rt_ext_alive(raw) || !ats_rt_ext_is_owner(raw)) return napi_generic_failure;
    auto data = std::make_unique<ExternalData>(ExternalData{id, drop});
    auto status = napi_create_external(s->env, data.get(), dropExternal, nullptr, reinterpret_cast<napi_value *>(result));
    if (status == napi_ok) {
        std::lock_guard<std::mutex> lock(externalMutex);
        externalData.insert(data.release());
    }
    return status;
} catch (...) { return napi_generic_failure; }
extern "C" int32_t ats_rt_ext_external_id(void *raw, void *value, int64_t *id) {
    auto *s = static_cast<State *>(raw);
    if (!ats_rt_ext_alive(raw) || !ats_rt_ext_is_owner(raw)) return napi_generic_failure;
    void *data = nullptr;
    auto status = napi_get_value_external(s->env, static_cast<napi_value>(value), &data);
    if (status == napi_ok) {
        std::lock_guard<std::mutex> lock(externalMutex);
        auto *external = static_cast<ExternalData *>(data);
        if (!externalData.count(external)) return napi_invalid_arg;
        *id = external->id;
    }
    return status;
}
extern "C" int32_t ats_rt_ext_bigint_create(void *raw, int32_t negative, const uint8_t *bytes,
    size_t length, void **result) try {
    auto *s = static_cast<State *>(raw);
    if (!ats_rt_ext_alive(raw) || !ats_rt_ext_is_owner(raw)) return napi_generic_failure;
    std::vector<uint64_t> words((length + 7) / 8, 0);
    for (size_t i = 0; i < length; ++i) words[i / 8] |= uint64_t(bytes[length - 1 - i]) << ((i % 8) * 8);
    if (words.empty()) words.push_back(0);
    return napi_create_bigint_words(s->env, negative, words.size(), words.data(), reinterpret_cast<napi_value *>(result));
} catch (...) { return napi_generic_failure; }
extern "C" int32_t ats_rt_ext_bigint_size(void *raw, void *value, size_t *length) {
    auto *s = static_cast<State *>(raw);
    if (!ats_rt_ext_alive(raw) || !ats_rt_ext_is_owner(raw)) return napi_generic_failure;
    size_t words = 0;
    auto status = napi_get_value_bigint_words(s->env, static_cast<napi_value>(value), nullptr, &words, nullptr);
    if (status == napi_ok) *length = words * 8;
    return status;
}
extern "C" int32_t ats_rt_ext_bigint_read(void *raw, void *value, int32_t *negative,
    uint8_t *bytes, size_t length) try {
    auto *s = static_cast<State *>(raw);
    if (!ats_rt_ext_alive(raw) || !ats_rt_ext_is_owner(raw)) return napi_generic_failure;
    size_t count = length / 8;
    std::vector<uint64_t> words(count);
    auto status = napi_get_value_bigint_words(s->env, static_cast<napi_value>(value), negative, &count, words.data());
    if (status != napi_ok || count * 8 > length) return status == napi_ok ? napi_invalid_arg : status;
    for (size_t i = 0; i < length; ++i) bytes[length - 1 - i] = uint8_t(words[i / 8] >> ((i % 8) * 8));
    return napi_ok;
} catch (...) { return napi_generic_failure; }

// This is one array conversion, not batching independent Extern operations.
// Keep normal FFI: setting an element can invoke an inherited JS setter.
extern "C" int32_t ats_rt_ext_create_array(void *raw, size_t count, const int32_t *kinds,
    void *const *values, const double *numbers, void **result) {
    auto env = static_cast<napi_env>(raw);
    if (!env || !result || count > UINT32_MAX || (count && (!kinds || !values || !numbers))) return napi_invalid_arg;
    napi_value array;
    auto status = napi_create_array_with_length(env, count, &array);
    if (status != napi_ok) return status;
    for (size_t i = 0; i < count; ++i) {
        napi_value value = static_cast<napi_value>(values[i]);
        switch (kinds[i]) {
            case napi_undefined: status = napi_get_undefined(env, &value); break;
            case napi_null: status = napi_get_null(env, &value); break;
            case napi_boolean: status = napi_get_boolean(env, numbers[i] != 0, &value); break;
            case napi_number: status = napi_create_double(env, numbers[i], &value); break;
            default: break;
        }
        if (status != napi_ok) return status;
        status = napi_set_element(env, array, static_cast<uint32_t>(i), value);
        if (status != napi_ok) return status;
        bool pending = false;
        status = napi_is_exception_pending(env, &pending);
        if (status != napi_ok || pending) return pending ? napi_pending_exception : status;
    }
    *result = array;
    return napi_ok;
}

extern "C" int32_t ats_rt_ext_get_array_element(void *raw, void *value, int64_t index, uint32_t *length, void **result) {
    auto env = static_cast<napi_env>(raw);
    auto array = static_cast<napi_value>(value);
    bool isArray = false;
    auto status = napi_is_array(env, array, &isArray);
    if (status != napi_ok) return status;
    if (!isArray) return napi_array_expected;
    status = napi_get_array_length(env, array, length);
    if (status != napi_ok) return status;
    if (index < 0 || static_cast<uint64_t>(index) >= *length) return -1;
    return napi_get_element(env, array, static_cast<uint32_t>(index), reinterpret_cast<napi_value *>(result));
}

extern "C" int32_t ats_rt_ext_create_number_array(void *raw, const double *numbers, size_t count, void **result) {
    auto env = static_cast<napi_env>(raw);
    if (!env || !result || count > UINT32_MAX || (count && !numbers)) return napi_invalid_arg;
    napi_value array;
    auto status = napi_create_array_with_length(env, count, &array);
    if (status != napi_ok) return status;
    for (size_t i = 0; i < count; ++i) {
        napi_value value;
        status = napi_create_double(env, numbers[i], &value);
        if (status != napi_ok) return status;
        status = napi_set_element(env, array, static_cast<uint32_t>(i), value);
        if (status != napi_ok) return status;
        bool pending = false;
        status = napi_is_exception_pending(env, &pending);
        if (status != napi_ok || pending) return pending ? napi_pending_exception : status;
    }
    *result = array;
    return napi_ok;
}
extern "C" int32_t ats_rt_ext_read_number_array(void *raw, void *value, double *numbers, size_t count,
    uint32_t *index, uint32_t *length, void **bad_value) {
    auto env = static_cast<napi_env>(raw);
    auto array = static_cast<napi_value>(value);
    if (!env || !index || !length || !bad_value || count > UINT32_MAX || (count && !numbers)) return napi_invalid_arg;
    for (size_t i = 0; i < count; ++i) {
        *index = static_cast<uint32_t>(i);
        // Preserve the generic reader's bounds check if an earlier getter shrinks the array.
        auto status = napi_get_array_length(env, array, length);
        if (status != napi_ok) return status;
        if (i >= *length) return -1;
        napi_value element;
        status = napi_get_element(env, array, *index, &element);
        if (status != napi_ok) return status;
        bool pending = false;
        status = napi_is_exception_pending(env, &pending);
        if (status != napi_ok || pending) return pending ? napi_pending_exception : status;
        status = napi_get_value_double(env, element, &numbers[i]);
        if (status != napi_ok) { *bad_value = element; return status; }
    }
    return napi_ok;
}

// Fast FFI reads only the UTF-16 length field. Copying and long-string sizing
// remain on normal FFI transitions. Three bytes per code unit bounds UTF-8.
extern "C" int32_t ats_rt_ext_short_string_capacity(void *raw, void *value, size_t *capacity) {
    auto env = static_cast<napi_env>(raw);
    size_t units;
    auto status = napi_get_value_string_utf16(env, static_cast<napi_value>(value), nullptr, 0, &units);
    if (status == napi_ok) *capacity = units <= 128 ? units * 3 + 1 : 0;
    return status;
}

// Bounded, callback-free copying only. Long strings never enter the fast FFI path.
extern "C" int32_t ats_rt_ext_copy_short_string(void *raw, void *value, uint8_t *bytes, size_t capacity, size_t *size) {
    auto env = static_cast<napi_env>(raw);
    size_t units;
    auto status = napi_get_value_string_utf16(env, static_cast<napi_value>(value), nullptr, 0, &units);
    if (status != napi_ok) return status;
    if (units > 128 || capacity < units * 3 + 1) return napi_invalid_arg;
    return napi_get_value_string_utf8(env, static_cast<napi_value>(value), reinterpret_cast<char *>(bytes), capacity, size);
}

// One ordinary FFI transition includes key materialization and the JS property operation.
// Explicit-length fallback preserves embedded NULs in Cangjie property names.
extern "C" int32_t ats_rt_ext_get_property_utf8(void *raw, void *object, const uint8_t *bytes, size_t length, void **result) try {
    auto env = static_cast<napi_env>(raw);
    auto target = static_cast<napi_value>(object);
    if (length && std::memchr(bytes, 0, length)) {
        napi_value key;
        auto status = napi_create_string_utf8(env, reinterpret_cast<const char *>(bytes), length, &key);
        if (status != napi_ok) return status;
        return napi_get_property(env, target, key, reinterpret_cast<napi_value *>(result));
    }
    std::string key;
    if (length) key.assign(reinterpret_cast<const char *>(bytes), length);
    return napi_get_named_property(env, target, key.c_str(), reinterpret_cast<napi_value *>(result));
} catch (...) { return napi_generic_failure; }
extern "C" int32_t ats_rt_ext_set_property_utf8(void *raw, void *object, const uint8_t *bytes, size_t length, void *value) try {
    auto env = static_cast<napi_env>(raw);
    auto target = static_cast<napi_value>(object);
    auto element = static_cast<napi_value>(value);
    if (length && std::memchr(bytes, 0, length)) {
        napi_value key;
        auto status = napi_create_string_utf8(env, reinterpret_cast<const char *>(bytes), length, &key);
        if (status != napi_ok) return status;
        return napi_set_property(env, target, key, element);
    }
    std::string key;
    if (length) key.assign(reinterpret_cast<const char *>(bytes), length);
    return napi_set_named_property(env, target, key.c_str(), element);
} catch (...) { return napi_generic_failure; }
extern "C" int32_t ats_rt_ext_get_number_property(void *raw, void *object, double index, void **result) {
    auto env = static_cast<napi_env>(raw);
    napi_value key;
    auto status = napi_create_double(env, index, &key);
    if (status != napi_ok) return status;
    return napi_get_property(env, static_cast<napi_value>(object), key, reinterpret_cast<napi_value *>(result));
}

// Fixed-size public N-API type/payload reads, with one fast FFI transition.
extern "C" ats_rt_ext_value_info ats_rt_ext_decode_value(void *raw, void *value) {
    auto env = static_cast<napi_env>(raw);
    auto local = static_cast<napi_value>(value);
    ats_rt_ext_value_info result{0.0, -1, napi_ok};
    napi_valuetype kind;
    result.status = napi_typeof(env, local, &kind);
    if (result.status != napi_ok) return result;
    result.kind = kind;
    if (kind == napi_number) result.status = napi_get_value_double(env, local, &result.scalar);
    else if (kind == napi_boolean) {
        bool boolean;
        result.status = napi_get_value_bool(env, local, &boolean);
        if (result.status == napi_ok) result.scalar = boolean ? 1.0 : 0.0;
    }
    return result;
}

extern "C" int32_t ats_rt_ext_is_array(void *raw, void *value) {
    bool result = false;
    if (napi_is_array(static_cast<napi_env>(raw), static_cast<napi_value>(value), &result) != napi_ok) return 0;
    return result ? 1 : 0;
}

extern "C" int32_t ats_rt_ext_element_read(void *raw, void *value, int64_t index, uint32_t *length, void **result,
                                    ats_rt_ext_value_info *info) {
    auto env = static_cast<napi_env>(raw);
    auto array = static_cast<napi_value>(value);
    auto status = napi_get_array_length(env, array, length);
    if (status != napi_ok) return status;
    if (index < 0 || static_cast<uint64_t>(index) >= *length) return -1;
    status = napi_get_element(env, array, static_cast<uint32_t>(index), reinterpret_cast<napi_value *>(result));
    if (status != napi_ok) return status;
    bool pending = false;
    napi_is_exception_pending(env, &pending);
    if (pending) return napi_pending_exception;
    auto element = static_cast<napi_value>(*result);
    info->status = napi_ok;
    if (napi_get_value_double(env, element, &info->scalar) == napi_ok) {
        info->kind = napi_number;
        return napi_ok;
    }
    napi_valuetype kind;
    status = napi_typeof(env, element, &kind);
    if (status != napi_ok) return status;
    info->kind = kind;
    info->scalar = 0.0;
    if (kind == napi_boolean) {
        bool boolean = false;
        status = napi_get_value_bool(env, element, &boolean);
        info->scalar = boolean ? 1.0 : 0.0;
        return status;
    }
    return napi_ok;
}

extern "C" int32_t ats_rt_ext_element_write_f64(void *raw, void *value, uint32_t index, double number) {
    auto env = static_cast<napi_env>(raw);
    napi_value element;
    auto status = napi_create_double(env, number, &element);
    if (status != napi_ok) return status;
    status = napi_set_element(env, static_cast<napi_value>(value), index, element);
    if (status != napi_ok) return status;
    bool pending = false;
    napi_is_exception_pending(env, &pending);
    if (pending) return napi_pending_exception;
    return napi_ok;
}

extern "C" int32_t ats_rt_ext_element_write(void *raw, void *value, uint32_t index, void *element) {
    auto env = static_cast<napi_env>(raw);
    auto status = napi_set_element(env, static_cast<napi_value>(value), index, static_cast<napi_value>(element));
    if (status != napi_ok) return status;
    bool pending = false;
    napi_is_exception_pending(env, &pending);
    if (pending) return napi_pending_exception;
    return napi_ok;
}

extern "C" void ats_rt_ext_stats(void *raw, ats_rt_ext_stats_t *out) {
    auto *s = static_cast<State *>(raw);
    *out = ats_rt_ext_stats_t{s->opsLeaked, s->opsScoped, s->pinsCreated.load(), s->pinsDeleted.load(),
        s->budget.units, s->budget.depth, s->pins.read == PinRead::Alias ? 1u : 0u, s->pins.pending.load()};
}

extern "C" void ats_rt_ext_text_take(void *raw, uint8_t *dst, size_t length) {
    auto *s = static_cast<State *>(raw);
    if (length) std::memcpy(dst, s->text.data(), length);
}
