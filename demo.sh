#!/bin/sh
# Builds one demo app, installs it and starts it.
#
#   ./demo.sh demos/hello                       # first connected device
#   DEVICE=127.0.0.1:5555 ./demo.sh demos/rectangle
#
# Uninstalls first, as devicetest.sh does (a reinstall keeps library files the new build no
# longer ships). Build log: .devicetest/build-<demo>.log
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$(cd "$1" && pwd)"
NAME="$(basename "$PROJECT")"
DEVECO="${DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}"
CANGJIE_SDK="${CANGJIE_SDK:-$HOME/.cangjie-sdk/6.1/cangjie}"
HDC="$DEVECO/sdk/default/openharmony/toolchains/hdc"
WORK="$ROOT/.devicetest"

# Same environment as devicetest.sh (hvigor's Cangjie support outside the IDE).
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

DEVICE="${DEVICE:-$("$HDC" list targets | head -n 1)}"
BUNDLE="$(sed -n 's/.*"bundleName": *"\([^"]*\)".*/\1/p' "$PROJECT/AppScope/app.json5")"

cd "$PROJECT"
echo "== build $NAME"
if ! "$DEVECO/tools/hvigor/bin/hvigorw" --mode module -p module=entry@default -p product=default \
        -p requiredDeviceType=phone assembleHap --no-daemon > "$WORK/build-$NAME.log" 2>&1; then
    tail -40 "$WORK/build-$NAME.log"
    exit 1
fi

echo "== install $BUNDLE on $DEVICE"
"$HDC" -t "$DEVICE" uninstall "$BUNDLE" > /dev/null || true
out="$("$HDC" -t "$DEVICE" install -r entry/build/default/outputs/default/entry-default-signed.hap)"
case "$out" in
    *"install bundle successfully"*) ;;
    *) echo "$out"; exit 1 ;;
esac
"$HDC" -t "$DEVICE" shell aa start -a EntryAbility -b "$BUNDLE"
