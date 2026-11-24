#ifndef ARKTS_RUNTIME_PINS_H
#define ARKTS_RUNTIME_PINS_H
#include <napi/native_api.h>
#include <atomic>
#include <cstdint>
#include <cstddef>
#include <initializer_list>

struct State;

enum class PinRead : uint8_t {
    Alias,  // napi_get_strong_reference_value returns the reference's own global slot: read once
            // at creation, valid until the reference is deleted, in any scope, with no engine call.
    Fetch,
};

// What Pins::push did with a released pin.
enum class PushResult : uint8_t {
    Queued,            // on the death list; the list was not empty, or a wake is already queued
    QueuedWakeNeeded,  // on the death list, which was empty: the caller posts a wake (kTaskWake)
    Freed,             // the environment was torn down: the pin's bookkeeping was freed at once
};

// Whether a pin's value is an array. A value's type never changes, so it is found out once.
enum class IsArray : uint8_t { Unknown, Yes, No };

struct AtsRtExtPin {
    State *state;
    napi_strong_ref strong;
    napi_value alias;
    AtsRtExtPin *nextDead;
    // Owner thread only: read and written after an owner-thread check (ADR-0007), never by Cangjie.
    // `mutable`: filled in by ops that otherwise only read the pin.
    mutable IsArray isArray = IsArray::Unknown;
};

struct Pins {
    static AtsRtExtPin *tombstone() { return reinterpret_cast<AtsRtExtPin *>(uintptr_t(1)); }
    static constexpr uint32_t kDrainBatch = 256;

    std::atomic<AtsRtExtPin *> deaths{nullptr};
    std::atomic<bool> wakeQueued{false};
    PinRead read = PinRead::Fetch;

    AtsRtExtPin *create(State *s, napi_value value, napi_status *status);
    napi_status value(State *s, const AtsRtExtPin *pin, napi_value *result) const;
    bool hasDeaths() const {
        AtsRtExtPin *head = deaths.load(std::memory_order_acquire);
        return head != nullptr && head != tombstone();
    }
    PushResult push(AtsRtExtPin *pin);
    // drain() runs only while no op or runtime frame is in flight (inFlightCount == 0), and keeps the
    // pins the starting op was handed. An alias handed to an op therefore stays valid until the op
    // returns, even if its Pinned was finalized meanwhile (Cangjie has no reachability fence).
    void drain(State *s, const AtsRtExtPin *const *keep, size_t keepCount);
    void drain(State *s, std::initializer_list<const AtsRtExtPin *> keep = {}) { drain(s, keep.begin(), keep.size()); }
    void cleanup(State *s);
    void aliasCheck(State *s);
};

#endif
