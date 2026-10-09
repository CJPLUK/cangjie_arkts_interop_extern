#!/bin/sh
# Host (macOS) tests: compiler contract and pure runtime logic. No ArkTS VM.
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
SDK="${CANGJIE_SDK:-$HOME/.cangjie-sdk/6.1/cangjie}"
CJC="$SDK/build-tools/bin/cjc"
OUT="$HERE/build"
ARKTS="$HERE/../entry/src/main/cangjie/arkts"

mkdir -p "$OUT"
rm -f "$OUT/hosttest" "$OUT"/shared_*.cj
# Pure runtime files (no ohos imports), compiled into the test binary without their package line.
for f in operators.cj; do
    sed '/^package /d' "$ARKTS/$f" > "$OUT/shared_$f"
done
"$CJC" --test "$HERE"/*.cj "$OUT"/shared_*.cj -o "$OUT/hosttest" \
    --link-options="-syslibroot $(xcrun --show-sdk-path)" 2>&1 | grep -v "ld64.lld: warning" || true
test -x "$OUT/hosttest"

DYLD_LIBRARY_PATH="$SDK/build-tools/runtime/lib/darwin_aarch64_cjnative" "$OUT/hosttest" "$@"
