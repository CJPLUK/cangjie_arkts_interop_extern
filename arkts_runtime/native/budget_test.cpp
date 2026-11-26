#include "budget.h"
#include "frames.h"
#include <cstdio>
#include <cstdlib>
#include <optional>
#include <random>
#include <vector>

namespace {

struct CaseState {
    const char *name = "";
    std::optional<uint64_t> seed;
    int failures = 0;
} runningCase;

constexpr int kPrintedFailuresPerCase = 5;
void fail(const char *what, std::optional<uint64_t> step) {
    if (runningCase.failures++ >= kPrintedFailuresPerCase) return;
    std::printf("FAIL [%s", runningCase.name);
    if (runningCase.seed) std::printf(", seed %llu", (unsigned long long)*runningCase.seed);
    std::printf("] %s", what);
    if (step) std::printf(" at step %llu", (unsigned long long)*step);
    std::printf("\n");
}
void check(bool ok, const char *what, std::optional<uint64_t> step = std::nullopt) { if (!ok) fail(what, step); }

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
        check(spilled <= worst, "an op spills at most its worst case");
        if (budget.admit(worst) == ats_rt_ext::Placement::Scoped) { ++opsScoped; return; }
        ++opsSpilled;
        scopes.back().spilled += spilled;
        budget.charge(spilled);
        budget.postMarkerIfWanted([&] { ++markersThisTurn; return true; });
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

enum class ScopeRule { Kept, Broken };

struct Outcome { bool sound; uint64_t turns, resets, scoped; };

Outcome run(uint64_t seed, uint64_t steps, ScopeRule rule, uint32_t turnEndOdds = 1) {
    runningCase.seed = seed;
    const bool ruleKept = rule == ScopeRule::Kept;
    std::mt19937_64 rng(seed);
    World w;
    const uint32_t kWorst = 4 + ats_rt_ext::kUnitFreshHeap;
    bool sound = true;
    uint64_t turns = 0, resets = 0;
    for (uint64_t step = 0; step < steps; ++step) {
        uint32_t r = rng() % 100;
        if (!w.inTurn && w.scopes.size() == 1) {
            if (ruleKept || r < 50) { w.turnStart(); ++turns; }
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
        if (ruleKept) check(w.budget.units >= w.live(), "Sound", step);
        check(w.budget.units <= ats_rt_ext::kCapacity, "Bound", step);
        check(w.budget.framesOpen == w.frames(), "framesOpen == open frames", step);
    }
    std::printf("  seed %llu: %llu turns, %llu marker resets, %llu spilled ops, %llu scoped ops, sound %s\n",
        (unsigned long long)seed, (unsigned long long)turns, (unsigned long long)resets,
        (unsigned long long)w.opsSpilled, (unsigned long long)w.opsScoped, sound ? "yes" : "no");
    return {sound, turns, resets, w.opsScoped};
}

void randomWalks() {
    for (uint64_t seed = 1; seed <= 8; ++seed) {
        Outcome o = run(seed, 3000000, ScopeRule::Kept);
        check(o.turns > 1000 && o.resets > 100, "walk exercises turns and marker resets");
    }
}

void longTurns() {
    for (uint64_t seed = 11; seed <= 12; ++seed) {
        Outcome o = run(seed, 3000000, ScopeRule::Kept, 20000);
        check(o.scoped > 1000 && o.resets > 0, "long turns reach the cap and still reset");
    }
}

void frameRestore() {
    ats_rt_ext::HostBudget b;
    b.charge(10);
    { ats_rt_ext::HostBudget::Frame f(b); b.charge(500); check(b.framesOpen == 1, "frames open inside a frame"); }
    check(b.units == 10 && b.framesOpen == 0, "frame restores units");
}

void scopedOnceFull() {
    ats_rt_ext::HostBudget b;
    b.units = ats_rt_ext::kCapacity - 3;
    check(b.admit(3) == ats_rt_ext::Placement::Spill, "admit up to capacity spills");
    check(b.admit(4) == ats_rt_ext::Placement::Scoped, "admit past capacity is scoped");
}

void markerPosting() {
    ats_rt_ext::HostBudget b;
    int posts = 0;
    bool succeeds = true;
    auto post = [&] { ++posts; return succeeds; };

    check(!b.postMarkerIfWanted(post) && posts == 0, "no marker while nothing is spilled");
    b.charge(5);
    {
        ats_rt_ext::HostBudget::Frame f(b);
        b.charge(5);
        check(!b.postMarkerIfWanted(post) && posts == 0, "no marker inside a frame");
    }
    succeeds = false;
    check(!b.postMarkerIfWanted(post) && posts == 1, "a failed post reports no marker");
    succeeds = true;
    check(b.postMarkerIfWanted(post) && posts == 2, "the next spill retries the post");
    check(!b.postMarkerIfWanted(post) && posts == 2, "one marker pending at a time");
    b.turnEnded();
    check(b.units == 0, "the marker empties the budget");
    b.charge(1);
    check(b.postMarkerIfWanted(post) && posts == 3, "a later turn posts its own marker");
}

void frameStack() {
    FrameStack frames;
    static_assert(noexcept(frames.push({0, false})), "recording a frame cannot throw");
    static_assert(noexcept(frames.makeRoom()), "making room reports failure instead of throwing");
    check(frames.empty(), "a new stack is empty");
    for (uint32_t i = 0; i < 100; ++i) {
        check(frames.makeRoom() && frames.hasRoom(), "making room leaves room for one frame");
        check(frames.makeRoom() && frames.hasRoom(), "making room again, with room, still succeeds");
        frames.push({i, i % 2 == 1});
    }
    bool lifo = true;
    for (uint32_t i = 100; i-- > 0;) {
        OpenFrame f = frames.pop();
        lifo = lifo && f.savedUnits == i && f.inFlight == (i % 2 == 1);
    }
    check(lifo, "frames pop last-in, first-out");
    check(frames.empty() && frames.hasRoom(), "popping leaves room");
}

void negativeControl() {
    check(!run(99, 3000000, ScopeRule::Broken).sound, "Sound fails once the scope rule is broken");
}

struct Case { const char *name; void (*body)(); };

const Case kCases[] = {
    {"random walks", randomWalks},
    {"long turns", longTurns},
    {"frame restore", frameRestore},
    {"scoped once full", scopedOnceFull},
    {"marker posting", markerPosting},
    {"frame stack", frameStack},
    {"negative control", negativeControl},
};

}

int main() {
    int failedCases = 0;
    for (const Case &c : kCases) {
        runningCase = CaseState{c.name};
        std::printf("== %s\n", c.name);
        c.body();
        if (runningCase.failures) {
            ++failedCases;
            std::printf("  %s FAILED: %d failed checks\n", c.name, runningCase.failures);
        }
    }
    if (failedCases) std::printf("FAILED: %d of %zu cases\n", failedCases, sizeof kCases / sizeof kCases[0]);
    else std::printf("all budget cases passed\n");
    return failedCases ? 1 : 0;
}
