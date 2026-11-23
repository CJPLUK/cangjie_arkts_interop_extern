#include "state.h"
#include <hilog/log.h>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace {

/**
 * What each local a fused op creates weighs (ADR-0002). An op charges one of these where it creates
 * the local, through OpPlacement, and declares its worst case as a sum of the same names.
 */
namespace units {
constexpr uint32_t kPinFetch = ats_rt_ext::kUnitLocal;  // a pin's value, read in Fetch mode; none in Alias mode
constexpr uint32_t kScalar = ats_rt_ext::kUnitLocal;    // an argument made from a scalar
constexpr uint32_t kResult = ats_rt_ext::kUnitLocal;    // an engine call's result
// A result that turns out to be a fresh heap value: what it may root beyond its local, so that the
// result weighs kUnitFreshHeap in all.
constexpr uint32_t kFreshHeap = ats_rt_ext::kUnitFreshHeap - kResult;
// Created text: a text argument, or a property key, which the engine creates from the name (or the
// op does, when the key has an embedded NUL).
inline uint32_t text(size_t bytes) { return ats_rt_ext::unitsForCreatedText(bytes); }
inline uint32_t arg(const ats_rt_ext_arg &arg) {
    switch (arg.tag) {
        case ATS_RT_EXT_ARG_PIN: return kPinFetch;
        case ATS_RT_EXT_ARG_UTF8: return text(arg.length);
        default: return kScalar;
    }
}
}

const AtsRtExtPin *pinOf(const ats_rt_ext_arg &arg) {
    return arg.tag == ATS_RT_EXT_ARG_PIN ? static_cast<const AtsRtExtPin *>(arg.ptr) : nullptr;
}

/**
 * Where one fused op's locals live: spilled into the caller's scope, or in a scope of the op's own
 * (HostBudget::admit). Every local the op creates goes through one of the methods below, which
 * charge its units, so none is created uncharged. On exit a spilled op adds the charge to the
 * budget. In debug builds an op whose charge exceeds its declared worst case aborts: the budget's
 * Bound invariant rests on that never happening.
 */
class OpPlacement {
public:
    OpPlacement(State *state, const char *op, uint32_t worst)
        : s(state), op(op), worst(worst), placement(state->budget.admit(worst)) {
        if (placement == ats_rt_ext::Placement::Scoped && napi_open_handle_scope(s->env, &scope) != napi_ok) scope = nullptr;
    }
    bool ok() const { return placement == ats_rt_ext::Placement::Spill || scope; }
    ~OpPlacement() {
#ifndef NDEBUG
        if (charged > worst) {
            OH_LOG_Print(LOG_APP, LOG_FATAL, 0x0000, "arkts_runtime",
                "%{public}s charged %{public}u units, over its declared worst case of %{public}u", op, charged, worst);
            std::abort();
        }
#endif
        if (placement == ats_rt_ext::Placement::Scoped) {
            ++s->opsScoped;
            if (scope) napi_close_handle_scope(s->env, scope);
            return;
        }
        ++s->opsSpilled;
        s->budget.charge(charged);
        s->budget.postMarkerIfWanted([this] { return statePost(s, kTaskTurnEnd) == napi_ok; });
    }
    OpPlacement(const OpPlacement &) = delete;
    OpPlacement &operator=(const OpPlacement &) = delete;

    /** A pin's value: units::kPinFetch in Fetch mode. */
    napi_status pin(const AtsRtExtPin *pin, napi_value *result) {
        if (s->pins.read == PinRead::Fetch) charged += units::kPinFetch;
        return s->pins.value(s, pin, result);
    }

    /** An argument's value: a pin's as pin(), otherwise units::arg(arg). */
    napi_status arg(const ats_rt_ext_arg &arg, napi_value *result) {
        if (arg.tag == ATS_RT_EXT_ARG_PIN) return pin(pinOf(arg), result);
        charged += units::arg(arg);
        switch (arg.tag) {
            case ATS_RT_EXT_ARG_UTF8:
                return napi_create_string_utf8(s->env, static_cast<const char *>(arg.ptr), arg.length, result);
            default:
                switch (arg.kind) {
                    case napi_undefined: return napi_get_undefined(s->env, result);
                    case napi_null: return napi_get_null(s->env, result);
                    case napi_boolean: return napi_get_boolean(s->env, arg.scalar != 0.0, result);
                    default: return napi_create_double(s->env, arg.scalar, result);
                }
        }
    }

    /** Runs an engine call that may run JS (a getter, setter or callee) and creates no local, in flight. */
    template <class Call>
    napi_status inFlight(Call call) {
        ++s->inFlightCount;
        auto status = call();
        --s->inFlightCount;
        return status;
    }

    /** As inFlight, for a call that creates its result: units::kResult. */
    template <class Call>
    napi_status result(Call call) {
        charged += units::kResult;
        return inFlight(call);
    }

    /**
     * Runs named(const char *key) with a NUL-terminated copy of the key, or keyed(napi_value key) when
     * the key has an embedded NUL, which the named N-API calls would cut short. Either way the key is
     * created, by the op or by the engine from the name: units::text(length).
     */
    template <class Named, class Keyed>
    napi_status key(const uint8_t *bytes, size_t length, Named named, Keyed keyed) try {
        charged += units::text(length);
        if (length && std::memchr(bytes, 0, length)) {
            napi_value key;
            auto status = napi_create_string_utf8(s->env, reinterpret_cast<const char *>(bytes), length, &key);
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

    /** Pins a result that is a fresh heap value: units::kFreshHeap on top of its local. */
    AtsRtExtPin *pinFresh(napi_value local, napi_status *status) {
        charged += units::kFreshHeap;
        return s->pins.create(s, local, status);
    }

    State *const s;

private:
    [[maybe_unused]] const char *const op;  // read only by the debug check
    [[maybe_unused]] const uint32_t worst;
    const ats_rt_ext::Placement placement;
    napi_handle_scope scope = nullptr;
    uint32_t charged = 0;
};

int32_t opEnter(State *s, const AtsRtExtPin *const *keep, size_t keepCount) {
    if (!s->alive.load(std::memory_order_relaxed)) return ATS_RT_EXT_DEAD;
    if (!stateIsOwner(s)) return ATS_RT_EXT_NOT_OWNER;
    if (s->inFlightCount == 0 && s->pins.hasDeaths()) s->pins.drain(s, keep, keepCount);
    return napi_ok;
}
int32_t opEnter(State *s, std::initializer_list<const AtsRtExtPin *> keep) { return opEnter(s, keep.begin(), keep.size()); }

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

int32_t decodeResult(OpPlacement &place, napi_value local, ats_rt_ext_op_result *out, const AtsRtExtPin *hint = nullptr) {
    State *s = place.s;
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
                if (place.pin(hint, &cached) == napi_ok && napi_strict_equals(s->env, local, cached, &same) == napi_ok && same) {
                    out->pin = const_cast<AtsRtExtPin *>(hint);
                    out->flags = ATS_RT_EXT_RESULT_HIT;
                    return napi_ok;
                }
            }
            napi_status pinned;
            out->pin = place.pinFresh(local, &pinned);
            return pinned;
        }
    }
}

}

extern "C" int32_t ats_rt_ext_get_named(void *raw, void *targetPin, const uint8_t *key, size_t keyLength, void *hintPin,
                                 ats_rt_ext_op_result *out) {
    auto *s = static_cast<State *>(raw);
    auto *target = static_cast<const AtsRtExtPin *>(targetPin);
    auto *hint = static_cast<const AtsRtExtPin *>(hintPin);
    if (auto entered = opEnter(s, {target, hint})) return entered;
    OpPlacement place(s, "get_named",
        units::kPinFetch /* receiver */ + units::text(keyLength) /* key */ + units::kResult + units::kFreshHeap +
        (hint ? units::kPinFetch /* hint */ : 0));
    if (!place.ok()) return napi_generic_failure;
    napi_value receiver, result;
    auto status = place.pin(target, &receiver);
    if (status != napi_ok) return status;
    auto env = s->env;
    status = place.result([&] {
        return place.key(key, keyLength,
            [&](const char *name) { return napi_get_named_property(env, receiver, name, &result); },
            [&](napi_value k) { return napi_get_property(env, receiver, k, &result); });
    });
    if (auto thrown = pendingOr(env, status)) return thrown;
    return decodeResult(place, result, out, hint);
}

extern "C" int32_t ats_rt_ext_set_named(void *raw, void *targetPin, const uint8_t *key, size_t keyLength, const ats_rt_ext_arg *value) {
    auto *s = static_cast<State *>(raw);
    auto *target = static_cast<const AtsRtExtPin *>(targetPin);
    if (auto entered = opEnter(s, {target, pinOf(*value)})) return entered;
    OpPlacement place(s, "set_named", units::kPinFetch /* receiver */ + units::arg(*value) + units::text(keyLength) /* key */);
    if (!place.ok()) return napi_generic_failure;
    napi_value receiver, element;
    auto status = place.pin(target, &receiver);
    if (status != napi_ok) return status;
    status = place.arg(*value, &element);
    if (status != napi_ok) return status;
    auto env = s->env;
    status = place.inFlight([&] {
        return place.key(key, keyLength,
            [&](const char *name) { return napi_set_named_property(env, receiver, name, element); },
            [&](napi_value k) { return napi_set_property(env, receiver, k, element); });
    });
    return pendingOr(env, status);
}

namespace {
/** Fills pin->isArray from the pin's value. Owner thread only. */
napi_status learnArray(State *s, const AtsRtExtPin *pin, napi_value value) {
    if (pin->isArray != IsArray::Unknown) return napi_ok;
    bool isArray = false;
    auto status = napi_is_array(s->env, value, &isArray);
    if (status == napi_ok) pin->isArray = isArray ? IsArray::Yes : IsArray::No;
    return status;
}

/** The value of an array pin; ATS_RT_EXT_GENERIC if it is not an array. Owner thread only. */
int32_t arrayValue(OpPlacement &place, const AtsRtExtPin *pin, napi_value *array) {
    auto status = place.pin(pin, array);
    if (status != napi_ok) return status;
    status = learnArray(place.s, pin, *array);
    if (status != napi_ok) return status;
    return pin->isArray == IsArray::Yes ? napi_ok : ATS_RT_EXT_GENERIC;
}
}

extern "C" int32_t ats_rt_ext_pin_is_array(void *raw, void *pinRaw) {
    auto *s = static_cast<State *>(raw);
    auto *pin = static_cast<const AtsRtExtPin *>(pinRaw);
    if (!pin || !s->alive.load(std::memory_order_relaxed) || !stateIsOwner(s)) return 0;
    if (pin->isArray == IsArray::Unknown) {
        napi_value value;
        if (s->pins.value(s, pin, &value) != napi_ok || learnArray(s, pin, value) != napi_ok) return 0;
    }
    return pin->isArray == IsArray::Yes ? 1 : 0;
}

extern "C" int32_t ats_rt_ext_element_get(void *raw, void *targetPin, int64_t index, ats_rt_ext_op_result *out) {
    auto *s = static_cast<State *>(raw);
    auto *target = static_cast<const AtsRtExtPin *>(targetPin);
    if (auto entered = opEnter(s, {target})) return entered;
    if (target->isArray == IsArray::No) return ATS_RT_EXT_GENERIC;  // known already: skip the placement
    OpPlacement place(s, "element_get", units::kPinFetch /* array */ + units::kResult + units::kFreshHeap);
    if (!place.ok()) return napi_generic_failure;
    napi_value array, result;
    if (auto status = arrayValue(place, target, &array)) return status;
    uint32_t length = 0;
    auto status = napi_get_array_length(s->env, array, &length);
    if (status != napi_ok) return status;
    if (index < 0 || static_cast<uint64_t>(index) >= length) return ATS_RT_EXT_INDEX_OUT_OF_RANGE;
    status = place.result([&] { return napi_get_element(s->env, array, static_cast<uint32_t>(index), &result); });
    if (auto thrown = pendingOr(s->env, status)) return thrown;
    return decodeResult(place, result, out);
}

extern "C" int32_t ats_rt_ext_element_set(void *raw, void *targetPin, uint32_t index, const ats_rt_ext_arg *value) {
    auto *s = static_cast<State *>(raw);
    auto *target = static_cast<const AtsRtExtPin *>(targetPin);
    if (auto entered = opEnter(s, {target, pinOf(*value)})) return entered;
    if (target->isArray == IsArray::No) return ATS_RT_EXT_GENERIC;  // known already: skip the placement
    OpPlacement place(s, "element_set", units::kPinFetch /* array */ + units::arg(*value));
    if (!place.ok()) return napi_generic_failure;
    napi_value array, element;
    if (auto status = arrayValue(place, target, &array)) return status;
    auto status = place.arg(*value, &element);
    if (status != napi_ok) return status;
    status = place.inFlight([&] { return napi_set_element(s->env, array, index, element); });
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
    uint32_t worst = units::kPinFetch /* callee */ + units::arg(*thisArg) + units::kResult + units::kFreshHeap;
    for (size_t i = 0; i < argc; ++i) {
        keep[i + 2] = pinOf(args[i]);
        worst += units::arg(args[i]);
    }
    if (auto entered = opEnter(s, keep, argc + 2)) return entered;
    OpPlacement place(s, "call", worst);
    if (!place.ok()) return napi_generic_failure;
    napi_value callee, receiver, result;
    auto status = place.pin(function, &callee);
    if (status != napi_ok) return status;
    status = place.arg(*thisArg, &receiver);
    if (status != napi_ok) return status;
    for (size_t i = 0; i < argc; ++i) {
        status = place.arg(args[i], &values[i]);
        if (status != napi_ok) return status;
    }
    status = place.result([&] { return napi_call_function(s->env, receiver, callee, argc, values, &result); });
    if (auto thrown = pendingOr(s->env, status)) return thrown;
    return decodeResult(place, result, out);
} catch (...) { return napi_generic_failure; }
