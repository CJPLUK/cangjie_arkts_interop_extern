#ifndef ARKTS_RUNTIME_STATE_H
#define ARKTS_RUNTIME_STATE_H
#include "backend.h"
#include "budget.h"
#include "pins.h"
#include <napi/native_api.h>
#include <atomic>
#include <cstdint>
#include <mutex>
#include <thread>
#include <vector>

constexpr int64_t kTaskWake = 0;
constexpr int64_t kTaskTurnEnd = -1;

struct State {
    napi_env env;
    napi_threadsafe_function dispatcher{};
    std::thread::id owner;
    ats_rt_ext_task_callback callback;
    std::atomic<bool> alive{true};
    std::atomic<unsigned> owners{1};
    // `postMutex` serializes every TSFN post against cleanup, so a finalizer's wake can never call
    // a TSFN that cleanup already aborted.
    std::mutex postMutex;
    PinTable pins;
    ats_rt_ext::HostBudget budget;
    struct Bracket { uint32_t units; bool inFlight; };
    std::vector<Bracket> brackets;
    uint32_t opDepth = 0;
    uint64_t opsLeaked = 0, opsScoped = 0;
    std::vector<char16_t> text16;
    std::vector<uint8_t> text;
    std::atomic<uint64_t> pinsCreated{0}, pinsDeleted{0};
};

inline bool stateIsOwner(const State *s) { return s->owner == std::this_thread::get_id(); }
int32_t statePost(State *s, int64_t id);

#endif
