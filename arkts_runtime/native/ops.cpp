#include "state.h"
#include <cstring>
#include <string>
#include <vector>

namespace {

constexpr uint32_t kWorstGetNamed = 3 + ats_rt_ext::kUnitFreshHeap;

uint32_t worstArg(const ats_rt_ext_arg &arg) {
    return arg.tag == ATS_RT_EXT_ARG_UTF8 ? ats_rt_ext::unitsForCreatedText(arg.length) : ats_rt_ext::kUnitLocal;
}

struct OpPlacement {
    State *s;
    ats_rt_ext::Placement placement;
    napi_handle_scope scope = nullptr;
    uint32_t units = 0;

    OpPlacement(State *state, uint32_t worst) : s(state), placement(state->budget.admit(worst)) {
        if (placement == ats_rt_ext::Placement::Scoped && napi_open_handle_scope(s->env, &scope) != napi_ok) scope = nullptr;
    }
    bool ok() const { return placement == ats_rt_ext::Placement::Leak || scope; }
    ~OpPlacement() {
        if (placement == ats_rt_ext::Placement::Scoped) {
            ++s->opsScoped;
            if (scope) napi_close_handle_scope(s->env, scope);
            return;
        }
        ++s->opsLeaked;
        s->budget.charge(units);
        if (s->budget.wantsMarker() && statePost(s, kTaskTurnEnd) == napi_ok) s->budget.markerPosted();
    }
    OpPlacement(const OpPlacement &) = delete;
    OpPlacement &operator=(const OpPlacement &) = delete;
};

int32_t opEnter(State *s, const AtsRtExtPin *const *keep, size_t keepCount) {
    if (!s->alive.load(std::memory_order_relaxed)) return ATS_RT_EXT_DEAD;
    if (!stateIsOwner(s)) return ATS_RT_EXT_NOT_OWNER;
    if (s->opDepth == 0 && s->pins.hasDeaths()) s->pins.drain(s, keep, keepCount);
    return napi_ok;
}
int32_t opEnter(State *s, std::initializer_list<const AtsRtExtPin *> keep) { return opEnter(s, keep.begin(), keep.size()); }

const AtsRtExtPin *pinOf(const ats_rt_ext_arg &arg) {
    return arg.tag == ATS_RT_EXT_ARG_PIN ? static_cast<const AtsRtExtPin *>(arg.ptr) : nullptr;
}

napi_status argValue(State *s, const ats_rt_ext_arg &arg, napi_value *result, uint32_t *units) {
    switch (arg.tag) {
        case ATS_RT_EXT_ARG_PIN:
            if (s->pins.read == PinRead::Fetch) *units += ats_rt_ext::kUnitLocal;
            return s->pins.value(s, pinOf(arg), result);
        case ATS_RT_EXT_ARG_UTF8:
            *units += ats_rt_ext::unitsForCreatedText(arg.length);
            return napi_create_string_utf8(s->env, static_cast<const char *>(arg.ptr), arg.length, result);
        default:
            *units += ats_rt_ext::kUnitLocal;
            switch (arg.kind) {
                case napi_undefined: return napi_get_undefined(s->env, result);
                case napi_null: return napi_get_null(s->env, result);
                case napi_boolean: return napi_get_boolean(s->env, arg.scalar != 0.0, result);
                default: return napi_create_double(s->env, arg.scalar, result);
            }
    }
}

/** A thrown getter, setter or callee leaves a pending exception, sometimes with napi_ok. */
int32_t pendingOr(napi_env env, napi_status status) {
    bool pending = false;
    napi_is_exception_pending(env, &pending);
    return pending ? napi_pending_exception : status;
}

constexpr size_t kTextCopyMax = 255;

bool utf8Of(const char16_t *units, size_t count, std::vector<uint8_t> &out) {
    out.resize(count * 3);
    uint8_t *p = out.data();
    for (size_t i = 0; i < count; ++i) {
        uint32_t c = units[i];
        if (c >= 0xD800 && c <= 0xDFFF) {
            if (c > 0xDBFF || i + 1 == count || units[i + 1] < 0xDC00 || units[i + 1] > 0xDFFF) return false;
            c = 0x10000 + ((c - 0xD800) << 10) + (units[++i] - 0xDC00);
            *p++ = uint8_t(0xF0 | (c >> 18));
            *p++ = uint8_t(0x80 | ((c >> 12) & 0x3F));
            *p++ = uint8_t(0x80 | ((c >> 6) & 0x3F));
            *p++ = uint8_t(0x80 | (c & 0x3F));
        } else if (c >= 0x800) {
            *p++ = uint8_t(0xE0 | (c >> 12));
            *p++ = uint8_t(0x80 | ((c >> 6) & 0x3F));
            *p++ = uint8_t(0x80 | (c & 0x3F));
        } else if (c >= 0x80) {
            *p++ = uint8_t(0xC0 | (c >> 6));
            *p++ = uint8_t(0x80 | (c & 0x3F));
        } else {
            *p++ = uint8_t(c);
        }
    }
    out.resize(p - out.data());
    return true;
}

bool copyText(State *s, napi_value value, size_t *bytes) try {
    auto &units = s->text16;
    if (units.size() < kTextCopyMax + 2) units.resize(kTextCopyMax + 2);
    size_t count = 0;
    if (napi_get_value_string_utf16(s->env, value, units.data(), units.size(), &count) != napi_ok) return false;
    if (count > kTextCopyMax) return false;  // possibly truncated: too long to copy
    if (!utf8Of(units.data(), count, s->text)) return false;
    *bytes = s->text.size();
    return true;
} catch (...) { return false; }

int32_t decodeResult(State *s, napi_value local, ats_rt_ext_op_result *out, uint32_t *units, const AtsRtExtPin *hint = nullptr) {
    out->pin = nullptr;
    if (napi_get_value_double(s->env, local, &out->scalar) == napi_ok) {
        out->kind = napi_number;
        return napi_ok;
    }
    napi_valuetype kind;
    auto status = napi_typeof(s->env, local, &kind);
    if (status != napi_ok) return status;
    out->kind = kind;
    out->scalar = 0.0;
    switch (kind) {
        case napi_undefined:
        case napi_null:
            return napi_ok;
        case napi_number:
            return napi_get_value_double(s->env, local, &out->scalar);
        case napi_boolean: {
            bool boolean = false;
            status = napi_get_value_bool(s->env, local, &boolean);
            out->scalar = boolean ? 1.0 : 0.0;
            return status;
        }
        case napi_string:
            out->flags = 0;
            if (copyText(s, local, &out->text_length)) {
                out->flags = ATS_RT_EXT_RESULT_TEXT;
                return napi_ok;
            }
            [[fallthrough]];
        default: {
            out->flags = 0;
            if (hint) {
                napi_value cached;
                bool same = false;
                if (s->pins.value(s, hint, &cached) == napi_ok && napi_strict_equals(s->env, local, cached, &same) == napi_ok && same) {
                    if (s->pins.read == PinRead::Fetch) *units += ats_rt_ext::kUnitLocal;
                    out->pin = const_cast<AtsRtExtPin *>(hint);
                    out->flags = ATS_RT_EXT_RESULT_HIT;
                    return napi_ok;
                }
            }
            napi_status pinned;
            out->pin = s->pins.create(s, local, &pinned);
            *units += ats_rt_ext::kUnitFreshHeap - ats_rt_ext::kUnitLocal;
            return pinned;
        }
    }
}

/**
 * Runs named(const char *key) with a NUL-terminated copy of the key, or keyed(napi_value key) when
 * the key has an embedded NUL, which the named N-API calls would cut short.
 */
template <class Named, class Keyed>
napi_status byKey(napi_env env, const uint8_t *bytes, size_t length, Named named, Keyed keyed) try {
    if (length && std::memchr(bytes, 0, length)) {
        napi_value key;
        auto status = napi_create_string_utf8(env, reinterpret_cast<const char *>(bytes), length, &key);
        if (status != napi_ok) return status;
        return keyed(key);
    }
    char small[64];
    if (length < sizeof(small)) {
        std::memcpy(small, bytes, length);
        small[length] = 0;
        return named(small);
    }
    std::string key(reinterpret_cast<const char *>(bytes), length);
    return named(key.c_str());
} catch (...) { return napi_generic_failure; }

}

extern "C" int32_t ats_rt_ext_get_named(void *raw, void *targetPin, const uint8_t *key, size_t keyLength, void *hintPin,
                                 ats_rt_ext_op_result *out) {
    auto *s = static_cast<State *>(raw);
    auto *target = static_cast<const AtsRtExtPin *>(targetPin);
    auto *hint = static_cast<const AtsRtExtPin *>(hintPin);
    if (auto entered = opEnter(s, {target, hint})) return entered;
    OpPlacement place(s, kWorstGetNamed);
    if (!place.ok()) return napi_generic_failure;
    napi_value receiver, result;
    auto status = s->pins.value(s, target, &receiver);
    if (status != napi_ok) return status;
    if (s->pins.read == PinRead::Fetch) place.units += ats_rt_ext::kUnitLocal;
    ++s->opDepth;
    auto env = s->env;
    status = byKey(env, key, keyLength,
        [&](const char *name) { return napi_get_named_property(env, receiver, name, &result); },
        [&](napi_value k) { return napi_get_property(env, receiver, k, &result); });
    --s->opDepth;
    place.units += 2 * ats_rt_ext::kUnitLocal;
    if (auto thrown = pendingOr(s->env, status)) return thrown;
    return decodeResult(s, result, out, &place.units, hint);
}

extern "C" int32_t ats_rt_ext_set_named(void *raw, void *targetPin, const uint8_t *key, size_t keyLength, const ats_rt_ext_arg *value) {
    auto *s = static_cast<State *>(raw);
    auto *target = static_cast<const AtsRtExtPin *>(targetPin);
    if (auto entered = opEnter(s, {target, pinOf(*value)})) return entered;
    OpPlacement place(s, 2 + worstArg(*value));
    if (!place.ok()) return napi_generic_failure;
    napi_value receiver, element;
    auto status = s->pins.value(s, target, &receiver);
    if (status != napi_ok) return status;
    if (s->pins.read == PinRead::Fetch) place.units += ats_rt_ext::kUnitLocal;
    status = argValue(s, *value, &element, &place.units);
    if (status != napi_ok) return status;
    auto env = s->env;
    ++s->opDepth;
    status = byKey(env, key, keyLength,
        [&](const char *name) { return napi_set_named_property(env, receiver, name, element); },
        [&](napi_value k) { return napi_set_property(env, receiver, k, element); });
    --s->opDepth;
    place.units += ats_rt_ext::kUnitLocal;
    return pendingOr(env, status);
}

namespace {
napi_status arrayValue(State *s, const AtsRtExtPin *pin, napi_value *array, uint32_t *units) {
    auto status = s->pins.value(s, pin, array);
    if (status == napi_ok && s->pins.read == PinRead::Fetch) *units += ats_rt_ext::kUnitLocal;
    return status;
}
}

extern "C" int32_t ats_rt_ext_element_get(void *raw, void *targetPin, int64_t index, ats_rt_ext_op_result *out) {
    auto *s = static_cast<State *>(raw);
    auto *target = static_cast<const AtsRtExtPin *>(targetPin);
    if (auto entered = opEnter(s, {target})) return entered;
    OpPlacement place(s, 2 + ats_rt_ext::kUnitFreshHeap);
    if (!place.ok()) return napi_generic_failure;
    napi_value array, result;
    auto status = arrayValue(s, target, &array, &place.units);
    if (status != napi_ok) return status;
    uint32_t length = 0;
    status = napi_get_array_length(s->env, array, &length);
    if (status != napi_ok) return status;
    if (index < 0 || static_cast<uint64_t>(index) >= length) return ATS_RT_EXT_INDEX_OUT_OF_RANGE;
    ++s->opDepth;
    status = napi_get_element(s->env, array, static_cast<uint32_t>(index), &result);
    --s->opDepth;
    place.units += ats_rt_ext::kUnitLocal;
    if (auto thrown = pendingOr(s->env, status)) return thrown;
    return decodeResult(s, result, out, &place.units);
}

extern "C" int32_t ats_rt_ext_element_set(void *raw, void *targetPin, uint32_t index, const ats_rt_ext_arg *value) {
    auto *s = static_cast<State *>(raw);
    auto *target = static_cast<const AtsRtExtPin *>(targetPin);
    if (auto entered = opEnter(s, {target, pinOf(*value)})) return entered;
    OpPlacement place(s, 1 + worstArg(*value));
    if (!place.ok()) return napi_generic_failure;
    napi_value array, element;
    auto status = arrayValue(s, target, &array, &place.units);
    if (status != napi_ok) return status;
    status = argValue(s, *value, &element, &place.units);
    if (status != napi_ok) return status;
    ++s->opDepth;
    status = napi_set_element(s->env, array, index, element);
    --s->opDepth;
    return pendingOr(s->env, status);
}

extern "C" int32_t ats_rt_ext_call(void *raw, void *functionPin, const ats_rt_ext_arg *thisArg, const ats_rt_ext_arg *args, size_t argc,
                            ats_rt_ext_op_result *out) try {
    auto *s = static_cast<State *>(raw);
    auto *function = static_cast<const AtsRtExtPin *>(functionPin);
    constexpr size_t kInline = 8;
    const AtsRtExtPin *keepInline[kInline + 2];
    napi_value valuesInline[kInline];
    std::vector<const AtsRtExtPin *> keepHeap;
    std::vector<napi_value> valuesHeap;
    const AtsRtExtPin **keep = keepInline;
    napi_value *values = valuesInline;
    if (argc > kInline) {
        keepHeap.resize(argc + 2);
        valuesHeap.resize(argc);
        keep = keepHeap.data();
        values = valuesHeap.data();
    }
    keep[0] = function;
    keep[1] = pinOf(*thisArg);
    uint32_t worst = 2 + worstArg(*thisArg) + ats_rt_ext::kUnitFreshHeap;
    for (size_t i = 0; i < argc; ++i) {
        keep[i + 2] = pinOf(args[i]);
        worst += worstArg(args[i]);
    }
    if (auto entered = opEnter(s, keep, argc + 2)) return entered;
    OpPlacement place(s, worst);
    if (!place.ok()) return napi_generic_failure;
    napi_value callee, receiver, result;
    auto status = s->pins.value(s, function, &callee);
    if (status != napi_ok) return status;
    if (s->pins.read == PinRead::Fetch) place.units += ats_rt_ext::kUnitLocal;
    status = argValue(s, *thisArg, &receiver, &place.units);
    if (status != napi_ok) return status;
    for (size_t i = 0; i < argc; ++i) {
        status = argValue(s, args[i], &values[i], &place.units);
        if (status != napi_ok) return status;
    }
    ++s->opDepth;
    status = napi_call_function(s->env, receiver, callee, argc, values, &result);
    --s->opDepth;
    place.units += ats_rt_ext::kUnitLocal;
    if (auto thrown = pendingOr(s->env, status)) return thrown;
    return decodeResult(s, result, out, &place.units);
} catch (...) { return napi_generic_failure; }
