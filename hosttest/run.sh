#!/bin/sh
# Host (macOS) tests: compiler contract and pure runtime logic. No ArkTS VM.
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
SDK="${CANGJIE_SDK:-$HOME/.cangjie-sdk/6.1/cangjie}"
CJC="$SDK/build-tools/bin/cjc"
OUT="$HERE/build"

mkdir -p "$OUT"
rm -f "$OUT/hosttest"
"$CJC" --test "$HERE"/*.cj -o "$OUT/hosttest" \
    --link-options="-syslibroot $(xcrun --show-sdk-path)" 2>&1 | grep -v "ld64.lld: warning" || true
test -x "$OUT/hosttest"

DYLD_LIBRARY_PATH="$SDK/build-tools/runtime/lib/darwin_aarch64_cjnative" "$OUT/hosttest" "$@"
