#include "budget.h"
#include <cstdio>
#include <cstdlib>
#include <random>
#include <vector>

namespace {

struct Scope { uint64_t spilled; bool frame; uint32_t saved; };

struct World {
    ats_rt_ext::HostBudget budget;
    std::vector<Scope> scopes{{0, false, 0}};
    bool inTurn = false;
    uint32_t markersThisTurn = 0;
    uint64_t opsScoped = 0, opsSpilled = 0;

    uint64_t live() const { uint64_t sum = 0; for (auto &s : scopes) sum += s.spilled; return sum; }
    uint32_t frames() const { uint32_t n = 0; for (auto &s : scopes) n += s.frame; return n; }

    void op(uint32_t worst, uint32_t spilled) {
        if (budget.admit(worst) == ats_rt_ext::Placement::Scoped) { ++opsScoped; return; }
        ++opsSpilled;
        scopes.back().spilled += spilled;
        budget.charge(spilled);
        if (budget.wantsMarker()) { budget.markerPosted(); ++markersThisTurn; }
    }
    void frameOpen() { scopes.push_back({0, true, budget.enter()}); }
    void frameClose() { budget.exit(scopes.back().saved); scopes.pop_back(); }
    void foreignOpen() { scopes.push_back({0, false, 0}); }
    void foreignClose() { scopes.pop_back(); }
    void turnStart() { scopes.push_back({0, false, 0}); inTurn = true; markersThisTurn = 0; }
    void turnEnd() {
        scopes.pop_back();
        inTurn = false;
        if (budget.markerPending) budget.turnEnded();
    }
};

int failures = 0;
void check(bool ok, const char *what, uint64_t step) {
    if (!ok && failures++ < 5) std::printf("FAIL %s at step %llu\n", what, (unsigned long long)step);
}

struct Outcome { bool sound; uint64_t turns, resets, scoped; };

Outcome run(uint64_t seed, uint64_t steps, bool scopeRuleKept, bool expectSound, uint32_t turnEndOdds = 1) {
    std::mt19937_64 rng(seed);
    World w;
    const uint32_t kWorst = 4 + ats_rt_ext::kUnitFreshHeap;
    bool sound = true;
    uint64_t turns = 0, resets = 0;
    for (uint64_t step = 0; step < steps; ++step) {
        uint32_t r = rng() % 100;
        if (!w.inTurn && w.scopes.size() == 1) {
            if (scopeRuleKept || r < 50) { w.turnStart(); ++turns; }
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
        check(w.budget.framesOpen == w.frames(), "framesOpen == open frames", step);
    }
    std::printf("seed %llu: %llu turns, %llu marker resets, %llu spilled ops, %llu scoped ops, sound %s\n",
        (unsigned long long)seed, (unsigned long long)turns, (unsigned long long)resets,
        (unsigned long long)w.opsSpilled, (unsigned long long)w.opsScoped, sound ? "yes" : "no");
    return {sound, turns, resets, w.opsScoped};
}

}

int main() {
    for (uint64_t seed = 1; seed <= 8; ++seed) {
        Outcome o = run(seed, 3000000, true, true);
        check(o.turns > 1000 && o.resets > 100, "walk exercises turns and marker resets", seed);
    }
    for (uint64_t seed = 11; seed <= 12; ++seed) {
        Outcome o = run(seed, 3000000, true, true, 20000);
        check(o.scoped > 1000 && o.resets > 0, "long turns reach the cap and still reset", seed);
    }
    if (run(99, 3000000, false, false).sound) { std::printf("FAIL negative control stayed sound\n"); ++failures; }
    ats_rt_ext::HostBudget b;
    b.charge(10);
    { ats_rt_ext::HostBudget::Frame f(b); b.charge(500); check(b.framesOpen == 1, "frames open inside a frame", 0); }
    check(b.units == 10 && b.framesOpen == 0, "frame restores units", 0);
    b.units = ats_rt_ext::kCapacity - 3;
    check(b.admit(4) == ats_rt_ext::Placement::Scoped && b.admit(3) == ats_rt_ext::Placement::Spill, "admit at capacity", 0);
    std::printf(failures ? "FAILED (%d)\n" : "all budget checks passed\n", failures);
    return failures ? 1 : 0;
}
