#ifndef ARKTS_RUNTIME_STATE_H
#define ARKTS_RUNTIME_STATE_H
#include "backend.h"
#include "budget.h"
#include "frames.h"
#include "pins.h"
#include <napi/native_api.h>
#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

constexpr ats_rt_ext_task_id kTaskWake = 0;
constexpr ats_rt_ext_task_id kTaskTurnEnd = -1;
constexpr ats_rt_ext_task_id kFirstUserTask = 1;
inline bool isUserTask(ats_rt_ext_task_id id) { return id >= kFirstUserTask; }

class TaskQueue {
public:
    napi_status create(napi_env env, napi_value name, void *context, napi_finalize finalize,
        napi_threadsafe_function_call_js call) {
        return napi_create_threadsafe_function(env, nullptr, nullptr, name, 0, 1, context, finalize, context, call, &tsfn);
    }
    napi_status unref(napi_env env) { return napi_unref_threadsafe_function(env, tsfn); }

    int32_t post(int64_t id) noexcept try {
        std::lock_guard<std::mutex> lock(mutex);
        if (aborted) return napi_closing;
        auto item = std::make_unique<int64_t>(id);
        auto status = napi_call_threadsafe_function(tsfn, item.get(), napi_tsfn_nonblocking);
        if (status == napi_ok) item.release();
        return status;
    } catch (...) { return napi_generic_failure; }

    template <class Teardown>
    void abortAfter(Teardown teardown) {
        std::lock_guard<std::mutex> lock(mutex);
        teardown();
        aborted = true;
        napi_release_threadsafe_function(tsfn, napi_tsfn_abort);
    }
    void abort() { abortAfter([] {}); }

private:
    std::mutex mutex;
    napi_threadsafe_function tsfn{};
    bool aborted = false;
};

struct State {
    napi_env env;
    TaskQueue tasks;
    std::thread::id owner;
    ats_rt_ext_task_callback callback;
    std::atomic<bool> alive{true};
    std::atomic<unsigned> owners{1};
    Pins pins;
    ats_rt_ext::HostBudget budget;
    FrameStack openFrames;
    uint32_t inFlightCount = 0;
    uint64_t opsSpilled = 0, opsScoped = 0;
    std::vector<char16_t> text16;
    std::vector<uint8_t> text;
    std::atomic<uint64_t> pinsCreated{0}, pinsDeleted{0};
};

inline bool stateIsOwner(const State *s) { return s->owner == std::this_thread::get_id(); }
inline int32_t statePost(State *s, int64_t id) { return s->tasks.post(id); }

#endif
