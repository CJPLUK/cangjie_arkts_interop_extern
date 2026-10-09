#!/bin/sh
# Device tests: builds the entry and ohosTest HAPs, installs them, runs the hypium suite.
#
#   ./devicetest.sh                 # first connected device
#   DEVICE=127.0.0.1:5555 ./devicetest.sh
#   ./devicetest.sh --all           # every connected device, one after the other
#   ./devicetest.sh -s class Step0_Infrastructure   # extra `aa test` arguments
#
# Exits non-zero if the build fails or any test fails on any device.
# Full runner output: .devicetest/last-<device>.log
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
DEVECO="${DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}"
CANGJIE_SDK="${CANGJIE_SDK:-$HOME/.cangjie-sdk/6.1/cangjie}"
HDC="$DEVECO/sdk/default/openharmony/toolchains/hdc"
HVIGORW="$DEVECO/tools/hvigor/bin/hvigorw"
BUNDLE=com.example.externwithenum
WORK="$ROOT/.devicetest"

ALL=false
if [ "$1" = "--all" ]; then
    ALL=true
    shift
fi

# hvigor only enables the Cangjie build support when these are set (the IDE sets them itself).
mkdir -p "$WORK/node_modules/@ohos"
ln -sfn "$CANGJIE_SDK/build-tools/tools/hvigor/cangjie-build-support" "$WORK/node_modules/@ohos/cangjie-build-support"
ln -sfn "$DEVECO/tools/hvigor/hvigor" "$WORK/node_modules/@ohos/hvigor"
ln -sfn "$DEVECO/tools/hvigor/hvigor-ohos-plugin" "$WORK/node_modules/@ohos/hvigor-ohos-plugin"
export NODE_PATH="$WORK/node_modules"
export DEVECO_SDK_HOME="$DEVECO/sdk"
export DEVECO_CANGJIE_PLUGIN_ENABLED=true
export DEVECO_CANGJIE_PATH="$CANGJIE_SDK"
export JAVA_HOME="$DEVECO/jbr/Contents/Home"
export PATH="$JAVA_HOME/bin:$DEVECO/tools/node/bin:$PATH"

CONNECTED="$("$HDC" list targets | grep -v '^\[Empty\]$' || true)"
if $ALL; then
    DEVICES="$CONNECTED"
else
    DEVICES="${DEVICE:-$(echo "$CONNECTED" | head -n 1)}"
fi
if [ -z "$DEVICES" ]; then
    echo "no device connected" >&2
    exit 1
fi

cd "$ROOT"
for target in default ohosTest; do
    echo "== build entry@$target"
    if ! "$HVIGORW" --mode module -p module=entry@$target -p product=default \
            -p requiredDeviceType=phone assembleHap --no-daemon > "$WORK/build-$target.log" 2>&1; then
        tail -40 "$WORK/build-$target.log"
        exit 1
    fi
done

pick_hap() {
    if [ -f "$1-signed.hap" ]; then echo "$1-signed.hap"; else echo "$1-unsigned.hap"; fi
}

# Installs both HAPs on device $1. Returns non-zero on failure.
# Uninstalls first: reinstalling keeps library files that the new build no longer ships, and a
# leftover second copy of a Cangjie std library breaks runtime type checks.
install_on() {
    "$HDC" -t "$1" uninstall "$BUNDLE" > /dev/null || true
    for hap in "$(pick_hap entry/build/default/outputs/default/entry-default)" \
               "$(pick_hap entry/build/default/outputs/ohosTest/entry-ohosTest)"; do
        echo "== install $hap"
        out="$("$HDC" -t "$1" install -r "$hap")"
        case "$out" in
            *"install bundle successfully"*) ;;
            *) echo "$out"; return 1 ;;
        esac
    done
}

# Runs the suite on device $1 (remaining arguments go to `aa test`). Returns non-zero on failure.
run_on() {
    device="$1"
    shift
    log="$WORK/last-$(echo "$device" | tr ':/' '__').log"
    echo "== run tests"
    "$HDC" -t "$device" shell aa test -b "$BUNDLE" -m entry_test \
        -s unittest OpenHarmonyTestRunner -s timeout 30000 "$@" > "$log" 2>&1

    # Per-test lines: hypium reports `test=<name>` then `OHOS_REPORT_STATUS_CODE`
    # (1 start, 0 pass, -1 error, -2 failure) and, for failures, the message in `stream=`.
    awk '
        /OHOS_REPORT_STATUS: class=/ { cls = substr($0, index($0, "=") + 1) }
        /OHOS_REPORT_STATUS: test=/  { test = substr($0, index($0, "=") + 1) }
        /OHOS_REPORT_STATUS: stream=/ { msg = substr($0, index($0, "=") + 1) }
        /OHOS_REPORT_STATUS_CODE: 0/  { print "  PASS " cls "." test; msg = "" }
        /OHOS_REPORT_STATUS_CODE: -1/ { print "  ERROR " cls "." test ": " msg; msg = "" }
        /OHOS_REPORT_STATUS_CODE: -2/ { print "  FAIL " cls "." test ": " msg; msg = "" }
        /OHOS_REPORT_RESULT: stream=/ { print substr($0, index($0, "=") + 1) }
    ' "$log"

    grep -q "OHOS_REPORT_RESULT: stream=Tests run: [0-9]*, Failure: 0, Error: 0" "$log"
}

SUMMARY=""
FAILED=false
for device in $DEVICES; do
    echo "== device $device"
    if install_on "$device" && run_on "$device" "$@"; then
        SUMMARY="$SUMMARY  PASS $device
"
    else
        SUMMARY="$SUMMARY  FAIL $device
"
        FAILED=true
    fi
done

if $ALL; then
    echo "== summary"
    printf "%s" "$SUMMARY"
fi
! $FAILED
