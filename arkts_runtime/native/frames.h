#ifndef ARKTS_RUNTIME_FRAMES_H
#define ARKTS_RUNTIME_FRAMES_H
#include <cassert>
#include <cstdint>
#include <vector>

// A runtime or user frame that is open: the host budget's units to restore when it closes, and
// whether it counts as in flight.
struct OpenFrame { uint32_t units; bool inFlight; };

// The stack of open runtime and user frames. Growing it is split from recording a frame: room is
// made before the frame's handle scope opens, where failing is harmless, so recording the frame
// once the scope is open never allocates or throws.
class FrameStack {
public:
    // Room for one more frame. False, with nothing changed, when growing fails.
    bool makeRoom() noexcept {
        if (hasRoom()) return true;
        try { frames.reserve(2 * frames.size() + 8); } catch (...) { return false; }
        return true;
    }
    bool hasRoom() const noexcept { return frames.size() < frames.capacity(); }
    bool empty() const noexcept { return frames.empty(); }
    // Requires room (makeRoom): it never allocates.
    void push(OpenFrame frame) noexcept { assert(hasRoom()); frames.push_back(frame); }
    // Requires a frame open.
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
