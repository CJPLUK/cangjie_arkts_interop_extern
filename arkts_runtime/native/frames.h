#ifndef ARKTS_RUNTIME_FRAMES_H
#define ARKTS_RUNTIME_FRAMES_H
#include <cassert>
#include <cstdint>
#include <vector>

struct OpenFrame { uint32_t savedUnits; bool inFlight; };

class FrameStack {
public:
    bool makeRoom() noexcept {
        if (hasRoom()) return true;
        try { frames.reserve(2 * frames.size() + 8); } catch (...) { return false; }
        return true;
    }
    bool hasRoom() const noexcept { return frames.size() < frames.capacity(); }
    bool empty() const noexcept { return frames.empty(); }
    void push(OpenFrame frame) noexcept { assert(hasRoom()); frames.push_back(frame); }
    OpenFrame pop() noexcept {
        assert(!empty());
        OpenFrame frame = frames.back();
        frames.pop_back();
        return frame;
    }

private:
    std::vector<OpenFrame> frames;
};

#endif
