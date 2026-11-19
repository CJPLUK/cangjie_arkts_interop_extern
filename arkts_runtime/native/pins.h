// Pins: persistent strong references owned by Cangjie `Pinned` objects, and their release.
#ifndef ARKTS_RUNTIME3_PINS_H
#define ARKTS_RUNTIME3_PINS_H
#include <napi/native_api.h>
#include <atomic>
#include <cstdint>
#include <cstddef>
#include <initializer_list>

struct State;

/** How a pin's value is read; probed once at bind. */
enum class PinRead : uint8_t {
    Alias,  // napi_get_strong_reference_value returns the reference's own global slot: read once
            // at creation, valid until the reference is deleted, in any scope, with no engine call.
    Fetch,  // anything else: every read is napi_get_strong_reference_value (a local per read).
};

struct AtsRtExtPin {
    State *state;          // one counted share of State, released after the reference is deleted
    napi_strong_ref strong;
    napi_value alias;      // PinRead::Alias only, else nullptr. Never a scope-local handle.
    AtsRtExtPin *nextDead;      // written only by the single ats_rt_ext_unpin of this pin
};

/**
 * Release protocol:
 *  - ExactlyOnce: one Cangjie Pinned per AtsRtExtPin, so ats_rt_ext_unpin runs once per pin. The push is a
 *    Treiber push: finalizer threads never block each other or the JS thread.
 *  - JsThreadDelete: references are deleted only on the owner thread, in drain().
 *  - NoDeleteInFlight: drain() runs only while no op or generic bracket is in flight
 *    (opDepth == 0), and keeps the pins the starting op was handed. An alias handed to an op
 *    therefore stays valid until the op returns, even if its Pinned was finalized meanwhile
 *    (Cangjie has no reachability fence).
 *  - Tombstone: cleanup() swaps `deaths` to kTombstone; a later push frees bookkeeping only.
 *  - Liveness: the push that finds the list empty posts one wake unless one is queued.
 */
struct PinTable {
    static AtsRtExtPin *tombstone() { return reinterpret_cast<AtsRtExtPin *>(uintptr_t(1)); }
    static constexpr uint32_t kDrainBatch = 256;

    std::atomic<AtsRtExtPin *> deaths{nullptr};
    std::atomic<uint32_t> pending{0};
    std::atomic<bool> wakeQueued{false};
    PinRead read = PinRead::Fetch;

    /** Owner thread. nullptr on failure, with the napi status in *status. */
    AtsRtExtPin *create(State *s, napi_value value, napi_status *status);
    /** Owner thread. A napi_value valid until the pin is deleted (Alias) or the scope closes (Fetch). */
    napi_status value(State *s, const AtsRtExtPin *pin, napi_value *result) const;
    /** Owner thread: finalized pins are waiting for drain(). */
    bool hasDeaths() const {
        AtsRtExtPin *head = deaths.load(std::memory_order_acquire);
        return head != nullptr && head != tombstone();
    }
    /** Any thread. Returns true when the caller must post a wake. */
    bool push(AtsRtExtPin *pin);
    /** Owner thread, opDepth == 0. Deletes queued pins except `keep`, which are queued again. */
    void drain(State *s, const AtsRtExtPin *const *keep, size_t keepCount);
    void drain(State *s, std::initializer_list<const AtsRtExtPin *> keep = {}) { drain(s, keep.begin(), keep.size()); }
    /** Env cleanup hook, owner thread: drain everything, then tombstone. */
    void cleanup(State *s);
    /** At bind, inside a scope: two reads of a fresh strong reference give the same napi_value
     *  iff the engine hands out the reference's global slot. */
    void probe(State *s);
};

#endif
