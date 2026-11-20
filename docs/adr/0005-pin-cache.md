# ADR-0005: Reuse the pin of a repeated member read (pin cache)

Status: accepted, with an open issue

## Context

Code such as `obj.config.theme.color` inside a loop reads the same objects again and again. Under ADR-0003, each heap result is a new strong reference, later deleted on the owner thread. Most of those references would duplicate one that is already live.

## Decision

The pin cache (`PinCache`, `src/native_values.cj`) is a 256-slot, direct-mapped cache. A slot is chosen by hashing (receiver pin, key) and holds the last heap result read from that pair.

1. Before a member read, `memberAccess` looks the pair up (`hint`) and passes the cached pin to the fused op.
2. The op returns the hint (`ATS_RT_EXT_RESULT_HIT`, no new pin) only when the value read is strictly equal to the hinted value. Otherwise it returns a new pin, which then replaces the slot (`remember`).

The table is a hint, never a source of truth. A stale or colliding slot costs a miss, never a wrong value.

`remember` runs only on the owner thread, after a successful op. `hint` runs before the op, possibly on another thread. Off the owner thread the op returns `ATS_RT_EXT_NOT_OWNER` without using the hint.

## Open issue

The off-thread `hint` read is a data race with the owner thread's `remember` on the same slot. The value read is discarded, but the read itself is unsynchronised, and the three slot fields can be seen half-written: in particular a torn `String` key, which is then compared.

The fix is to look the hint up only on the owner thread. This puts a thread check on the hottest operation, so it needs a benchmark run and the device suite before it lands.

## Consequences

- Repeated reads of an unchanged object graph create no references.
- The table holds at most 256 extra pins alive.
