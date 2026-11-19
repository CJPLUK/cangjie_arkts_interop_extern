// HostBudget: decides where a fused op's engine locals live. Pure: no N-API, threads or
// allocation. Owned by State and touched only on the owner thread; host-tested by budget_test.cpp.
//
// An op either LEAKS its locals into whatever scope is on top (the caller's), or runs SCOPED
// (opens and closes its own scope inside the op). Leaked locals are never read after the op
// returns; they only occupy slots, and root their values, until the caller's scope closes.
// `units` over-approximates the leaked locals that may still be alive:
//   - a known frame (callback trampoline, TSFN task, generic bracket, ArkTSRuntime.newScope)
//     restores `units` on exit: everything leaked above its scope died when that scope closed;
//   - at depth 0 (a caller the runtime cannot see) a turn marker resets `units`: a TSFN task
//     posted on the first depth-0 leak, which runs once the JS stack has unwound. Contract: the
//     caller's scope closes by then (ark_interop exports and JS-called functions do; Cangjie UI
//     handlers and postJSTask bodies must use ArkTSRuntime.newScope).
//
// Invariant Bound: units <= kCapacity + the largest `worst` ever admitted.
// Invariant Sound: units >= weight of leaked locals not yet reclaimed, given the contract.
#ifndef ARKTS_RUNTIME3_BUDGET_H
#define ARKTS_RUNTIME3_BUDGET_H
#include <cstdint>

namespace ats_rt_ext {

/** 2^19 units: at most 4 MiB of handle slots. */
constexpr uint32_t kCapacity = 1u << 19;

/** A leaked local roots its value until the caller's scope closes, so a fresh heap result (which
 *  can root an arbitrary graph) weighs 64: at most 8K of them per turn or frame. */
constexpr uint32_t kUnitLocal = 1;
constexpr uint32_t kUnitFreshHeap = 64;
inline uint32_t unitsForCreatedText(uint64_t bytes) { return 1 + static_cast<uint32_t>(bytes / 512); }

enum class Placement : uint8_t { Leak, Scoped };

struct HostBudget {
    uint32_t units = 0;
    uint32_t depth = 0;          // known frames open
    bool markerPending = false;  // a turn marker is queued

    /** Before the op creates any local. `worst` bounds the units it may leak. */
    Placement admit(uint32_t worst) const { return units + worst <= kCapacity ? Placement::Leak : Placement::Scoped; }
    /** After a leaking op, the units it leaked (at most its `worst`). */
    void charge(uint32_t leaked) { units += leaked; }
    /** True once per turn at depth 0: the caller posts the marker, then calls markerPosted(). */
    bool wantsMarker() const { return depth == 0 && units > 0 && !markerPending; }
    void markerPosted() { markerPending = true; }
    /** In the marker task: event loop, empty JS stack. */
    void turnEnded() { markerPending = false; if (depth == 0) units = 0; }

    /** A known frame opens: returns what its exit restores. */
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

}  // namespace ats_rt_ext
#endif
