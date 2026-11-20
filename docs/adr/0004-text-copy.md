# ADR-0004: Copy short well-formed strings, pin the rest

Status: accepted

## Context

Strings are the most common non-numeric result. A Cangjie `String` is UTF-8, and an ArkTS string is UTF-16. A JS string can hold a lone surrogate, which has no UTF-8 encoding. ark_interop converts every string result eagerly.

## Decision

A string result of at most `kTextCopyMax` (255) UTF-16 units is read in one call into a fixed buffer (`copyText`, `native/ops.cpp`).

- **Well-formed:** if it converts to UTF-8, it is returned as text (`ATS_RT_EXT_RESULT_TEXT`), handed over through `ats_rt_ext_text_take`. On the Cangjie side it becomes the `Text(String)` payload: no engine value and no pin.
- **Longer, or containing a lone surrogate:** it becomes a `Pin` payload, like an object. It converts only when Cangjie asks for a `String`, and the lone-surrogate case stays exact, which round-trips losslessly to JS.

`napi_get_value_string_utf16` truncates silently into the buffer, so the buffer holds one unit more than `kTextCopyMax`. A count above `kTextCopyMax` means the string may have been cut, and it is pinned instead.

## Why 255

Copying long strings on every read was measured at 4x ark_interop's cost on a 10K-unit string read repeatedly. A pin is reused across repeated reads of the same property instead (the pin cache, ADR-0005).

Short strings dominate keys and labels, and copying them avoids creating a reference and later deleting it. No benchmark in the repo sweeps the threshold itself.

## Consequences

- Short strings cost one copy and no reference.
- Long strings cost a reference, and a conversion when used.
- A program cannot observe which representation it got: the differential suite (ADR-0008) compares string results, including lone surrogates, against ark_interop and plain ArkTS.
