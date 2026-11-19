// State: one per bound environment, shared by backend.cpp (session, pins, functions) and ops.cpp.
#ifndef ARKTS_RUNTIME3_STATE_H
#define ARKTS_RUNTIME3_STATE_H
#include "backend.h"
#include "budget.h"
#include "pins.h"
#include <napi/native_api.h>
#include <atomic>
#include <cstdint>
#include <mutex>
#include <thread>
#include <vector>

/** TSFN task ids below 1 are the runtime's own: a wake to drain pins, or the turn marker. */
constexpr int64_t kTaskWake = 0;
constexpr int64_t kTaskTurnEnd = -1;

/**
 * One per bound environment. Off the owner thread only `alive`, `owners`, `postMutex` and the
 * atomics of `pins` are touched. `postMutex` serializes every TSFN post against cleanup, so a
 * finalizer's wake can never call a TSFN that cleanup already aborted.
 */
struct State {
    napi_env env;
    napi_threadsafe_function dispatcher{};
    std::thread::id owner;
    ats_rt_ext_task_callback callback;
    std::atomic<bool> alive{true};
    std::atomic<unsigned> owners{1};
    std::mutex postMutex;
    PinTable pins;
    ats_rt_ext::HostBudget budget;          // owner thread
    struct Bracket { uint32_t units; bool inFlight; };
    std::vector<Bracket> brackets;   // owner thread: each open ats_rt_ext_open_scope, innermost last
    uint32_t opDepth = 0;            // owner thread: fused ops and generic brackets in flight
    uint64_t opsLeaked = 0, opsScoped = 0;          // owner thread
    std::vector<char16_t> text16;    // owner thread: a string result's UTF-16 units, while copied
    std::vector<uint8_t> text;       // owner thread: the last string result as UTF-8, for ats_rt_ext_text_take
    std::atomic<uint64_t> pinsCreated{0}, pinsDeleted{0};
};

inline bool stateIsOwner(const State *s) { return s->owner == std::this_thread::get_id(); }
/** Post task `id` to the owner thread; napi_closing once cleanup ran. Any thread. */
int32_t statePost(State *s, int64_t id);

#endif
