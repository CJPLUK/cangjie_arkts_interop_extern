# Splitting `State` into owner-thread and shared structs

The runtime keeps one `State` per bound environment, holding both the fields only the owner thread may touch (the host budget, the open frames, the in-flight count, the op counters, the text buffers) and the few that other threads touch (`alive`, `owners`, `postMutex`, the pin table's atomics). We decided not to split it into two structs, with the owner-only half reachable only after an owner check.

## Why this is out of scope

The split looks like a type-level guarantee, but the fields don't divide cleanly in two. There is a third kind: fields written once at bind and read from any thread afterwards (`env`, `owner`, `callback`, `dispatcher`, the pin read mode). And several owner-thread paths reach owner fields without going through the op entry check at all: the task dispatcher, the callback trampoline's engine frame, the stats hook, and taking the copied text. Each of those would need either an unchecked accessor, which gives back the guarantee the split was for, or a new check on a path that is already on the owner thread by construction.

So the change is a large diff across `backend.cpp`, `ops.cpp` and `state.h` for a small invariant gain. Mistakes it would prevent are already caught, probabilistically, by the differential suite's thread program, and ADR-0007 documents which fields belong to which thread.

The cheap, real part of the original suggestion (rejecting runtime-reserved task ids at the post boundary, and naming the task kinds) was kept, in #3.

## Prior requests

- #3: "Split State by thread, and give runtime tasks their own type" (the `State` split half)
