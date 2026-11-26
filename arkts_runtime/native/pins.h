#ifndef ARKTS_RUNTIME_PINS_H
#define ARKTS_RUNTIME_PINS_H
#include <napi/native_api.h>
#include <atomic>
#include <cassert>
#include <cstdint>
#include <cstddef>
#include <initializer_list>

struct State;
inline bool stateIsOwner(const State *s);

enum class PinRead : uint8_t {
    Alias,
    Fetch,
};

enum class PushResult : uint8_t {
    Queued,
    QueuedWakeNeeded,
    Freed,
};

enum class IsArray : uint8_t { Unknown, Yes, No };

struct AtsRtExtPin {
    explicit AtsRtExtPin(State *s) : state(s) {}

    State *state;
    napi_strong_ref strong = nullptr;
    napi_value alias = nullptr;
    AtsRtExtPin *nextDead = nullptr;

    IsArray isArray() const {
        assert(stateIsOwner(state));
        return isArrayOnOwnerThread;
    }
    void learnIsArray(IsArray known) const {
        assert(stateIsOwner(state));
        isArrayOnOwnerThread = known;
    }

private:
    mutable IsArray isArrayOnOwnerThread = IsArray::Unknown;
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
    void drainUnlessInFlight(State *s, const AtsRtExtPin *const *keepForOp, size_t keepCount);
    void drainUnlessInFlight(State *s, std::initializer_list<const AtsRtExtPin *> keepForOp = {}) {
        drainUnlessInFlight(s, keepForOp.begin(), keepForOp.size());
    }
    void cleanup(State *s);
    void aliasCheck(State *s);
};

#endif
