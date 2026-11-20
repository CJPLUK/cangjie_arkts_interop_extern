#!/bin/sh
# Host checks: what can be verified without a device, in about a minute.
#
#   ./hostcheck.sh
#
# 1. Type-checks the Cangjie package with the SDK compiler, twice: as shipped, and with the
#    step tests (they are compiled in only for the test app's bundle, see @When[bundle == ...]).
# 2. Syntax-checks the native sources against the SDK's N-API headers.
# 3. Builds and runs native/budget_test.cpp (ADR-0002).
#
# Exits non-zero on the first failure. The device suite is ./devicetest.sh.
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
DEVECO="${DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}"
CANGJIE_SDK="${CANGJIE_SDK:-$HOME/.cangjie-sdk/6.1/cangjie}"
SYSROOT_INCLUDE="$DEVECO/sdk/default/openharmony/native/sysroot/usr/include"
TEST_BUNDLE=com.example.testArkTSForeignRuntime
WORK="$ROOT/.hostcheck"

# The SDK's cjc reads its standard library from CANGJIE_HOME; a host Cangjie install's value breaks it.
export CANGJIE_HOME="$CANGJIE_SDK/build-tools"
mkdir -p "$WORK"
cd "$ROOT"

for bundle in shipped "$TEST_BUNDLE"; do
    echo "== cjc (bundle=$bundle)"
    if ! "$CANGJIE_HOME/bin/cjc" --package src --output-type=staticlib --cfg="bundle=$bundle" \
            -o "$WORK/libarkts_runtime.a" > "$WORK/cjc.log" 2>&1; then
        cat "$WORK/cjc.log"
        exit 1
    fi
done

# -idirafter: the host's libc headers win, and only napi/ and info/ come from the device sysroot.
for source in native/ops.cpp native/backend.cpp; do
    echo "== c++ -fsyntax-only $source"
    c++ -std=c++17 -fsyntax-only -idirafter "$SYSROOT_INCLUDE" -Inative "$source"
done

echo "== budget_test"
c++ -std=c++17 -O2 native/budget_test.cpp -o "$WORK/budget_test"
# No pipe: in sh a pipeline's status is its last command's, which would hide a failure.
if ! "$WORK/budget_test" > "$WORK/budget_test.log" 2>&1; then
    cat "$WORK/budget_test.log"
    exit 1
fi
tail -1 "$WORK/budget_test.log"
