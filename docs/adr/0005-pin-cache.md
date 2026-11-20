# ADR-0005: Reuse the pin of a repeated member read (pin cache)

Status: accepted

## Context

Code such as `obj.config.theme.color` inside a loop reads the same objects again and again. Under ADR-0003, each heap result is a new strong reference, later deleted on the owner thread. Most of those references would duplicate one that is already live.

## Decision

The pin cache (`PinCache`, `src/native_values.cj`) is a 256-slot, direct-mapped cache. A slot is chosen by hashing (receiver pin, key) and holds the last heap result read from that pair.

1. Before a member read, `memberAccess` looks the pair up (`hint`) and passes the cached pin to the fused op.
2. The op returns the hint (`ATS_RT_EXT_RESULT_HIT`, no new pin) only when the value read is strictly equal to the hinted value. Otherwise it returns a new pin, which then replaces the slot (`remember`).

The table is a hint, never a source of truth. A stale or colliding slot costs a miss, never a wrong value.

The pin cache is used only on the owner thread. `memberAccess` checks the thread first; off the owner thread it goes straight to the posted generic path, with no `hint` and no fused attempt, which could only return `ATS_RT_EXT_NOT_OWNER`. `remember` runs only after a successful op, so also only on the owner thread.

The slots are plain fields with no synchronisation. An off-thread `hint` would race the owner thread's `remember`: the Cangjie spec makes that undefined behaviour, and in practice a slot's `String` key could be read half-written and then compared past the end of its buffer (issue #15). Off-thread reads lose nothing by skipping the cache, since the op never used the hint there. The extra thread check is one more native call per member read: about 12 ns, or 2.6% on `property.readNumber` and 2.8 to 3.7% on `property.readChain` (paired runs on a phone).

## Consequences

- Repeated reads of an unchanged object graph create no references.
- The table holds at most 256 extra pins alive.
- Off-thread member reads never reuse a pin.
