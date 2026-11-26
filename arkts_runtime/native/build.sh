#!/bin/sh
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
DEVECO="${DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}"
NATIVE="${DEVECO_OH_NATIVE_HOME:-$DEVECO/sdk/default/openharmony/native}"
OUT="$1"
MODE="${2:-debug}"
case "$MODE" in
    debug) MODE_FLAGS="" ;;
    release) MODE_FLAGS="-DNDEBUG" ;;
    *) echo "build.sh: unknown build mode '$MODE'" >&2; exit 1 ;;
esac
mkdir -p "$OUT"
"$NATIVE/llvm/bin/clang++" --target=aarch64-linux-ohos --sysroot="$NATIVE/sysroot" \
    -std=c++17 -O2 $MODE_FLAGS -fPIC -shared -Wall -Wextra -Werror \
    "$HERE/backend.cpp" "$HERE/ops.cpp" -lace_napi.z -lhilog_ndk.z -o "$OUT/libarkts_runtime_native.so"

cp "$NATIVE/llvm/lib/aarch64-linux-ohos/libc++_shared.so" "$OUT/libc++_shared.so"
