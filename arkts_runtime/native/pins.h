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

struct AtsRtExtPin {
    State *state;
    napi_strong_ref strong;
    napi_value alias;
    AtsRtExtPin *nextDead;
};

struct PinTable {
    static AtsRtExtPin *tombstone() { return reinterpret_cast<AtsRtExtPin *>(uintptr_t(1)); }
    static constexpr uint32_t kDrainBatch = 256;

    std::atomic<AtsRtExtPin *> deaths{nullptr};
    std::atomic<uint32_t> pending{0};
    std::atomic<bool> wakeQueued{false};
    PinRead read = PinRead::Fetch;

    AtsRtExtPin *create(State *s, napi_value value, napi_status *status);
    napi_status value(State *s, const AtsRtExtPin *pin, napi_value *result) const;
    bool hasDeaths() const {
        AtsRtExtPin *head = deaths.load(std::memory_order_acquire);
        return head != nullptr && head != tombstone();
    }
    bool push(AtsRtExtPin *pin);
    // drain() runs only while no op or generic bracket is in flight (opDepth == 0), and keeps the
    // pins the starting op was handed. An alias handed to an op therefore stays valid until the op
    // returns, even if its Pinned was finalized meanwhile (Cangjie has no reachability fence).
    void drain(State *s, const AtsRtExtPin *const *keep, size_t keepCount);
    void drain(State *s, std::initializer_list<const AtsRtExtPin *> keep = {}) { drain(s, keep.begin(), keep.size()); }
    void cleanup(State *s);
    void probe(State *s);
};

#endif
