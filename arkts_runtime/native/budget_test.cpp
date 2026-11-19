// Host test of HostBudget against a simulated engine scope stack.
//   c++ -std=c++17 -O2 budget_test.cpp -o /tmp/budget_test && /tmp/budget_test
//
// The simulation is the engine's rule, not the budget's: a scope frees everything leaked into it
// when it closes, scopes close LIFO, the root scope never closes. Unseen callers (ark_interop
// exports) open a host scope per turn; known frames are scopes the runtime opens itself; foreign
// code may open and close scopes in between. The turn marker runs only after the turn's host
// scope has closed. After every step: Sound (units >= weight still leaked, root included) and
// Bound (units <= kCapacity + worst).
#include "budget.h"
#include <cstdio>
#include <cstdlib>
#include <random>
#include <vector>

namespace {

struct Scope { uint64_t leaked; bool frame; uint32_t saved; };

struct World {
    ats_rt_ext::HostBudget budget;
    std::vector<Scope> scopes{{0, false, 0}};  // [0] is the root scope
    bool inTurn = false;
    uint32_t markersThisTurn = 0;
    uint64_t opsScoped = 0, opsLeaked = 0;

    // The root scope never closes: what leaks there is never reclaimed and counts forever.
    uint64_t live() const { uint64_t sum = 0; for (auto &s : scopes) sum += s.leaked; return sum; }
    uint32_t frames() const { uint32_t n = 0; for (auto &s : scopes) n += s.frame; return n; }

    void op(uint32_t worst, uint32_t leaked) {
        if (budget.admit(worst) == ats_rt_ext::Placement::Scoped) { ++opsScoped; return; }
        ++opsLeaked;
        scopes.back().leaked += leaked;
        budget.charge(leaked);
        if (budget.wantsMarker()) { budget.markerPosted(); ++markersThisTurn; }
    }
    void frameOpen() { scopes.push_back({0, true, budget.enter()}); }
    void frameClose() { budget.exit(scopes.back().saved); scopes.pop_back(); }
    void foreignOpen() { scopes.push_back({0, false, 0}); }
    void foreignClose() { scopes.pop_back(); }
    void turnStart() { scopes.push_back({0, false, 0}); inTurn = true; markersThisTurn = 0; }
    void turnEnd() {
        scopes.pop_back();  // the host scope
        inTurn = false;
        if (budget.markerPending) budget.turnEnded();
    }
};

int failures = 0;
void check(bool ok, const char *what, uint64_t step) {
    if (!ok && failures++ < 5) std::printf("FAIL %s at step %llu\n", what, (unsigned long long)step);
}

struct Outcome { bool sound; uint64_t turns, resets, scoped; };

// One random walk. contractKept=false also runs ops at depth 0 outside any host scope (a Cangjie
// UI handler without newScope): they leak into the root, and the checker must see Sound fail.
// A turn ends with odds 1/turnEndOdds once only its host scope is open; large odds fill the budget.
Outcome run(uint64_t seed, uint64_t steps, bool contractKept, bool expectSound, uint32_t turnEndOdds = 1) {
    std::mt19937_64 rng(seed);
    World w;
    const uint32_t kWorst = 4 + ats_rt_ext::kUnitFreshHeap;
    bool sound = true;
    uint64_t turns = 0, resets = 0;
    for (uint64_t step = 0; step < steps; ++step) {
        uint32_t r = rng() % 100;
        if (!w.inTurn && w.scopes.size() == 1) {
            if (contractKept || r < 50) { w.turnStart(); ++turns; }
            else w.op(kWorst, 1 + rng() % 3);
        } else if (r < 60) {
            w.op(kWorst, (rng() % 8 == 0) ? ats_rt_ext::kUnitFreshHeap + 2 : 1 + rng() % 4);
        } else if (r < 68 && w.scopes.size() < 32) {
            w.frameOpen();
        } else if (r < 72 && w.scopes.size() < 32) {
            w.foreignOpen();
        } else if (r < 97) {
            bool topIsHost = w.inTurn && w.scopes.size() == 2;
            if (w.scopes.back().frame) w.frameClose();
            else if (!topIsHost && w.scopes.size() > 1) w.foreignClose();
        } else if (w.inTurn && w.scopes.size() == 2 && rng() % turnEndOdds == 0) {
            uint32_t before = w.budget.units;
            w.turnEnd();
            if (before && !w.budget.units) ++resets;
            check(w.markersThisTurn <= 1, "one marker per turn", step);
        }
        if (w.budget.units < w.live()) sound = false;
        if (expectSound) check(w.budget.units >= w.live(), "Sound", step);
        check(w.budget.units <= ats_rt_ext::kCapacity + kWorst, "Bound", step);
        check(w.budget.depth == w.frames(), "depth == open frames", step);
    }
    std::printf("seed %llu: %llu turns, %llu marker resets, %llu leaked ops, %llu scoped ops, sound %s\n",
        (unsigned long long)seed, (unsigned long long)turns, (unsigned long long)resets,
        (unsigned long long)w.opsLeaked, (unsigned long long)w.opsScoped, sound ? "yes" : "no");
    return {sound, turns, resets, w.opsScoped};
}

}  // namespace

int main() {
    for (uint64_t seed = 1; seed <= 8; ++seed) {
        Outcome o = run(seed, 3000000, true, true);
        check(o.turns > 1000 && o.resets > 100, "walk exercises turns and marker resets", seed);
    }
    // Long turns: the budget fills, ops run scoped, Sound still holds.
    for (uint64_t seed = 11; seed <= 12; ++seed) {
        Outcome o = run(seed, 3000000, true, true, 20000);
        check(o.scoped > 1000 && o.resets > 0, "long turns reach the cap and still reset", seed);
    }
    // Negative control: break the contract; Sound must be seen to fail.
    if (run(99, 3000000, false, false).sound) { std::printf("FAIL negative control stayed sound\n"); ++failures; }
    // Frame restore, directly.
    ats_rt_ext::HostBudget b;
    b.charge(10);
    { ats_rt_ext::HostBudget::Frame f(b); b.charge(500); check(b.depth == 1, "frame depth", 0); }
    check(b.units == 10 && b.depth == 0, "frame restores units", 0);
    // Scoped once full.
    b.units = ats_rt_ext::kCapacity - 3;
    check(b.admit(4) == ats_rt_ext::Placement::Scoped && b.admit(3) == ats_rt_ext::Placement::Leak, "admit at capacity", 0);
    std::printf(failures ? "FAILED (%d)\n" : "all budget checks passed\n", failures);
    return failures ? 1 : 0;
}
