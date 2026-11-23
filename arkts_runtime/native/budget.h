#ifndef ARKTS_RUNTIME_BUDGET_H
#define ARKTS_RUNTIME_BUDGET_H
#include <cstdint>

namespace ats_rt_ext {

constexpr uint32_t kCapacity = 1u << 19;

constexpr uint32_t kUnitLocal = 1;
constexpr uint32_t kUnitFreshHeap = 64;
inline uint32_t unitsForCreatedText(uint64_t bytes) { return 1 + static_cast<uint32_t>(bytes / 512); }

enum class Placement : uint8_t { Spill, Scoped };

struct HostBudget {
    uint32_t units = 0;
    uint32_t framesOpen = 0;
    bool markerPending = false;

    Placement admit(uint32_t worst) const { return units + worst <= kCapacity ? Placement::Spill : Placement::Scoped; }
    void charge(uint32_t spilled) { units += spilled; }
    // Outside every frame (the outer scope, whose caller the runtime cannot see) a turn marker
    // resets `units`: a TSFN task posted on the first spill there, which runs once the JS stack has
    // unwound. Scope rule: the outer scope closes by then (ark_interop exports and JS-called
    // functions do; Cangjie UI handlers and postJSTask bodies must use ArkTSRuntime.newScope).
    // Calls `post` (returning whether it posted) if a marker is wanted; returns whether one was posted.
    template <class Post>
    bool postMarkerIfWanted(Post &&post) {
        if (framesOpen != 0 || units == 0 || markerPending || !post()) return false;
        markerPending = true;
        return true;
    }
    void turnEnded() { markerPending = false; if (framesOpen == 0) units = 0; }

    uint32_t enter() { ++framesOpen; return units; }
    void exit(uint32_t saved) { --framesOpen; units = saved; }

    struct Frame {
        HostBudget &budget;
        uint32_t saved;
        explicit Frame(HostBudget &b) : budget(b), saved(b.enter()) {}
        ~Frame() { budget.exit(saved); }
        Frame(const Frame &) = delete;
        Frame &operator=(const Frame &) = delete;
    };
};

}
#endif
