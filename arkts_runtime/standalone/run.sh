#!/bin/sh
# Independent native consumer. Reuses the signed benchmark app identity for this check;
# run demos/benchmarks/run.sh afterwards to restore the benchmark application.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SDK="${CANGJIE_SDK:-$HOME/.cangjie-sdk/6.1/cangjie}"
DEVECO="${DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}"
NATIVE="$DEVECO/sdk/default/openharmony/native"
HDC="$DEVECO/sdk/default/openharmony/toolchains/hdc"
DEVICE="${DEVICE:-$("$HDC" list targets | head -1)}"
export ARKTS_STANDALONE_BUILD="$HERE/.build"
export ARKTS_STANDALONE_APP="$HERE/.app"
OUT="$ARKTS_STANDALONE_BUILD"
mkdir -p "$OUT/native"
sh "$ROOT/arkts_runtime/native/build.sh" "$OUT/native"
"$SDK/build-tools/bin/cjc" -p "$ROOT/arkts_runtime/src" --target aarch64-linux-ohos --output-type staticlib --output-dir "$OUT" -o libarkts_runtime.a
"$SDK/build-tools/bin/cjc" "$HERE/probe.cj" --target aarch64-linux-ohos --output-type dylib --dy-std --output-dir "$OUT" --import-path "$OUT" -L "$OUT" -larkts_runtime -L "$OUT/native" -larkts_runtime_native -L "$NATIVE/sysroot/usr/lib/aarch64-linux-ohos" -lace_napi.z -B "$NATIVE/llvm/bin" --sysroot "$NATIVE/sysroot" -o libarkts_smoke_cj.so
"$NATIVE/llvm/bin/clang++" --target=aarch64-linux-ohos --sysroot="$NATIVE/sysroot" -std=c++17 -fPIC -shared "$HERE/module.cpp" -L "$ROOT/dependencies_libs/base/arm64-v8a/runtime" -lcangjie-runtime -lace_napi.z -o "$OUT/libarkts_standalone.so"
"$HDC" -t "$DEVICE" file recv /system/lib64/libc++.so "$OUT/libc++.so"
python3 "$HERE/prepare.py"
# Include the bridge built above even when the test app has never been built.
cp "$OUT/native/"*.so "$ARKTS_STANDALONE_APP/entry/libs/arm64-v8a/"
export NODE_PATH="$ROOT/.devicetest/node_modules"
export DEVECO_SDK_HOME="$DEVECO/sdk"
export JAVA_HOME="$DEVECO/jbr/Contents/Home"
export PATH="$JAVA_HOME/bin:$DEVECO/tools/node/bin:$PATH"
cd "$ARKTS_STANDALONE_APP"
"$DEVECO/tools/hvigor/bin/hvigorw" --mode module -p module=entry@default -p product=default -p requiredDeviceType=phone assembleHap --no-daemon > "$OUT/build.log" 2>&1
"$HDC" -t "$DEVICE" uninstall com.example.arkts.benchmarks > /dev/null || true
"$HDC" -t "$DEVICE" install -r entry/build/default/outputs/default/entry-default-signed.hap
"$HDC" -t "$DEVICE" shell power-shell wakeup > /dev/null
"$HDC" -t "$DEVICE" shell aa start -a EntryAbility -b com.example.arkts.benchmarks
export DEVECO_HOME="$DEVECO"
python3 "$HERE/verify.py" "$HDC" "$DEVICE"
