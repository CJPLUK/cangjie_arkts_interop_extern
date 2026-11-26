#!/bin/sh
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
DEVECO="${DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}"
CANGJIE_SDK="${CANGJIE_SDK:-$HOME/.cangjie-sdk/6.1/cangjie}"
SYSROOT_INCLUDE="$DEVECO/sdk/default/openharmony/native/sysroot/usr/include"
TEST_BUNDLE=com.example.testArkTSForeignRuntime
BENCH_BUNDLE=com.example.arkts.benchmarks
WORK="$ROOT/.hostcheck"

SDK_CANGJIE_HOME="$CANGJIE_SDK/build-tools"
mkdir -p "$WORK"
cd "$ROOT"

sdk_cjc_ignoring_host_cangjie_home() {
    CANGJIE_HOME="$SDK_CANGJIE_HOME" "$SDK_CANGJIE_HOME/bin/cjc" "$@"
}

run_logged_or_show_log() {
    log="$1"
    shift
    if ! "$@" > "$log" 2>&1; then
        cat "$log"
        exit 1
    fi
}

cjc_package() {
    package_dir="$1" bundle="$2"
    echo "== cjc $package_dir (bundle=$bundle)"
    run_logged_or_show_log "$WORK/cjc.log" sdk_cjc_ignoring_host_cangjie_home --package "$package_dir" \
        --output-type=staticlib --cfg="bundle=$bundle" --import-path "$WORK" --output-dir "$WORK" \
        -o "lib$(basename "$package_dir").a"
}
every_top_level_declaration_is_gated_to_bundle() {
    package_dir="$1" bundle="$2"
    echo "== every top-level declaration in $package_dir has @When[bundle == \"$bundle\"]"
    awk -v gate="@When[bundle == \"$bundle\"]" '
        /^(public |private |internal |protected |open |abstract |sealed |unsafe |foreign )*(func|type|const|let|var|class|struct|enum|interface|extend|main)[ <(]/ {
            if (previous != gate) { print FILENAME ":" FNR ": not gated: " $0; ungated = 1 }
        }
        $0 != "" { previous = $0 }
        END { exit ungated }
    ' "$package_dir"/*.cj
}
every_top_level_declaration_is_gated_to_bundle src/tests "$TEST_BUNDLE"
every_top_level_declaration_is_gated_to_bundle src/bench "$BENCH_BUNDLE"

for bundle in shipped "$TEST_BUNDLE" "$BENCH_BUNDLE"; do
    cjc_package src "$bundle"
    cjc_package src/tests "$bundle"
    cjc_package src/bench "$bundle"
done

for source in native/ops.cpp native/backend.cpp; do
    for mode in "" -DNDEBUG; do
        echo "== c++ -fsyntax-only $mode $source"
        c++ -std=c++17 -fsyntax-only -Wall -Wextra -Werror $mode -idirafter "$SYSROOT_INCLUDE" -Inative "$source"
    done
done

echo "== budget_test"
c++ -std=c++17 -O2 native/budget_test.cpp -o "$WORK/budget_test"
run_logged_or_show_log "$WORK/budget_test.log" "$WORK/budget_test"
tail -1 "$WORK/budget_test.log"
