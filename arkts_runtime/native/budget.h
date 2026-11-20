#ifndef ARKTS_RUNTIME_BUDGET_H
#define ARKTS_RUNTIME_BUDGET_H
#include <cstdint>

namespace ats_rt_ext {

constexpr uint32_t kCapacity = 1u << 19;

constexpr uint32_t kUnitLocal = 1;
constexpr uint32_t kUnitFreshHeap = 64;
inline uint32_t unitsForCreatedText(uint64_t bytes) { return 1 + static_cast<uint32_t>(bytes / 512); }

enum class Placement : uint8_t { Leak, Scoped };

struct HostBudget {
    uint32_t units = 0;
    uint32_t depth = 0;
    bool markerPending = false;

    Placement admit(uint32_t worst) const { return units + worst <= kCapacity ? Placement::Leak : Placement::Scoped; }
    void charge(uint32_t leaked) { units += leaked; }
    // At depth 0 (a caller the runtime cannot see) a turn marker resets `units`: a TSFN task
    // posted on the first depth-0 leak, which runs once the JS stack has unwound. Contract: the
    // caller's scope closes by then (ark_interop exports and JS-called functions do; Cangjie UI
    // handlers and postJSTask bodies must use ArkTSRuntime.newScope).
    bool wantsMarker() const { return depth == 0 && units > 0 && !markerPending; }
    void markerPosted() { markerPending = true; }
    void turnEnded() { markerPending = false; if (depth == 0) units = 0; }

    uint32_t enter() { ++depth; return units; }
    void exit(uint32_t saved) { --depth; units = saved; }

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
