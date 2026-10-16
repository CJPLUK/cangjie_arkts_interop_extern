#!/bin/sh
# Benchmarks: builds the app (release), installs it, starts it, waits for the end and writes
# results/<device>-<date>.csv and .html from the lines the app logs (hilog tag ArkTSBench).
#
#   ./run.sh                          # first connected device
#   DEVICE=127.0.0.1:5555 ./run.sh
#   ./run.sh --all                    # every connected device, one after the other
#
# Only writes files under results/ and .devicetest/; never runs git.
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
DEVECO="${DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}"
CANGJIE_SDK="${CANGJIE_SDK:-$HOME/.cangjie-sdk/6.1/cangjie}"
HDC="$DEVECO/sdk/default/openharmony/toolchains/hdc"
BUNDLE=com.example.arkts.benchmarks
BUILD_MODE=release
WORK="$HERE/.devicetest"
RESULTS="$HERE/results"
TIMEOUT=300

ALL=false
if [ "$1" = "--all" ]; then
    ALL=true
fi

# Same environment as devicetest.sh (hvigor's Cangjie support outside the IDE).
mkdir -p "$WORK/node_modules/@ohos" "$RESULTS"
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
    echo "no device connected"
    exit 1
fi

cd "$HERE"
echo "== build ($BUILD_MODE)"
if ! "$DEVECO/tools/hvigor/bin/hvigorw" --mode module -p module=entry@default -p product=default \
        -p buildMode=$BUILD_MODE -p requiredDeviceType=phone assembleHap --no-daemon > "$WORK/build.log" 2>&1; then
    tail -40 "$WORK/build.log"
    exit 1
fi
HAP=entry/build/default/outputs/default/entry-default-signed.hap

CODE="$WORK/code"

# Copies the code of every benchmark from the sources into HTML fragments in $CODE: <name>.html
# (the group's description and the two variants) and shared.html (fixtures and helpers). Each
# variant is the second and third argument of Benchmark("name", N, { ... }, { ... }, offThread).
write_code() {
    rm -rf "$CODE"
    mkdir -p "$CODE"
    awk -v dir="$CODE" '
        function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); return s }
        function ticks(s,    open) {
            while (index(s, "`") > 0) { sub(/`/, open ? "</code>" : "<code>", s); open = !open }
            return s
        }
        function dedent(l, n) { while (n > 0 && substr(l, 1, 1) == " ") { l = substr(l, 2); n-- } return l }
        function finish(line, s, i,    file) {
            block[nblock++] = buf (s > 0 ? substr(line, s, i - s + 1) : dedent(substr(line, 1, i), ind))
            cap = 0; buf = ""
            if (nblock < 2) return
            file = dir "/" name ".html"
            if (doc != "") print "<p>" ticks(esc(doc)) "</p>" > file
            print "<div class=\"variants\"><div><h3>ark_interop</h3><pre>" esc(block[0]) "</pre></div>" > file
            print "<div><h3>arkts_runtime</h3><pre>" esc(block[1]) "</pre></div></div>" > file
            close(file)
            name = ""
        }
        function scan(line, from,    i, c, s) {
            s = 0
            for (i = from; i <= length(line); i++) {
                c = substr(line, i, 1)
                if (instr) { if (c == "\"") instr = 0; continue }
                if (c == "\"") { instr = 1; continue }
                if (c == "{") {
                    if (!cap) { cap = 1; ind = i - 1; s = i; depth = 0 }
                    depth++
                } else if (c == "}" && cap && --depth == 0) {
                    finish(line, s, i)
                    if (name == "") return
                    s = 0
                }
            }
            if (cap) buf = buf (s > 0 ? substr(line, s) : dedent(line, ind)) "\n"
        }
        FNR == 1 { doc = ""; indoc = 0; ingroup = 0; insetup = 0; name = ""; cap = 0; instr = 0
                   file = FILENAME; sub(/.*\//, "", file) }
        !ingroup && /^\/\*\*/ { indoc = 1; doc = "" }
        indoc { line = $0; sub(/^ *\/?\*+\/? ?/, "", line); sub(/ *\*\/ *$/, "", line)
                if (line != "") doc = doc (doc == "" ? "" : " ") line
                if ($0 ~ /\*\//) indoc = 0
                next }
        /^func [A-Za-z]+Benchmarks\(\)/ { ingroup = 1; insetup = 1; setup = ""; next }
        insetup && /^    \[/ { insetup = 0
                               if (setup != "") shared = shared "<h3>" file ": values shared by its benchmarks</h3><pre>" esc(setup) "</pre>\n"
                               next }
        insetup { setup = setup substr($0, 5) "\n"; next }
        name != "" { scan($0, 1); next }
        match($0, /Benchmark\("[^"]+"/) { name = substr($0, RSTART + 11, RLENGTH - 12); nblock = 0
                                          scan($0, RSTART + RLENGTH) }
        END { printf "%s", shared > (dir "/groups.html") }
    ' "$HERE"/entry/src/main/cangjie/b*.cj
    {
        echo "<h3>Bench.ets: the ArkTS fixtures</h3><pre>"
        sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "$HERE/entry/src/main/ets/Bench.ets"
        echo "</pre>"
        cat "$CODE/groups.html"
        echo "<h3>harness.cj: helpers used by the benchmarks</h3><pre>"
        awk '
            /^\/\*\*/ { pending = "" ; incomment = 1 }
            incomment { pending = pending $0 "\n"; if ($0 ~ /\*\//) incomment = 0; next }
            /^var sink/ { printf "%s%s\n\n", pending, $0 }
            /^func (onJSThread|interopBench|interopTarget|runtimeBench|runtimeTarget)[<(]/ { infunc = 1; printf "%s", pending }
            infunc { print; if ($0 ~ /^}/) { infunc = 0; print "" } }
            !/^\/\*\*/ && !infunc { pending = "" }
        ' "$HERE/entry/src/main/cangjie/harness.cj" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
        echo "</pre>"
    } > "$CODE/shared.html"
}

# Writes the .csv and .html for one device from the RESULT lines in $1.
write_results() {
    lines="$1" device="$2" stamp="$3" base="$4"
    {
        echo "date,device,build,benchmark,iterations,ark_interop_ns_per_op,arkts_runtime_ns_per_op,ratio,ark_interop_heap_kb,arkts_runtime_heap_kb"
        while IFS='|' read -r name n interop runtime ratio heap1 heap2; do
            echo "$stamp,$device,$BUILD_MODE,$name,$n,$interop,$runtime,$ratio,$heap1,$heap2"
        done < "$lines"
    } > "$base.csv"
    {
        cat <<EOF
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>arkts_runtime benchmarks: $device $stamp</title>
<style>
body { font-family: -apple-system, sans-serif; margin: 2em; }
table { border-collapse: collapse; }
th, td { border: 1px solid #ccc; padding: 4px 10px; }
td.num { text-align: right; font-variant-numeric: tabular-nums; }
th { background: #f2f2f2; }
td.name { cursor: pointer; color: #0645ad; }
td.name:hover { text-decoration: underline; }
tr.code > td { background: #fafafa; }
.variants { display: grid; grid-template-columns: 1fr 1fr; gap: 1em; }
h3 { margin: 0.8em 0 0.3em; font-size: 1em; }
pre { margin: 0; padding: 8px; background: #fff; border: 1px solid #ddd; overflow-x: auto; font-size: 12px; }
</style></head><body>
<h1>arkts_runtime against ark_interop</h1>
<p>Date: $stamp<br>Device: $device<br>Build: $BUILD_MODE<br>
Median of 5 runs, nanoseconds per operation. Ratio = arkts_runtime / ark_interop.</p>
<p>Click a benchmark to see its code. In each variant the outer block is the setup (not timed)
and the inner <code>{ n: Int64 =&gt; ... }</code> block is the timed run, with n = N.
The fixtures and helpers it uses are <a href="#shared">below the table</a>.</p>
<table>
<tr><th>Benchmark</th><th>N</th><th>ark_interop ns/op</th><th>arkts_runtime ns/op</th><th>Ratio</th><th>ark_interop heap KB</th><th>arkts_runtime heap KB</th></tr>
EOF
        while IFS='|' read -r name n interop runtime ratio heap1 heap2; do
            echo "<tr><td class=\"name\">$name</td><td class=\"num\">$n</td><td class=\"num\">$interop</td><td class=\"num\">$runtime</td><td class=\"num\">$ratio</td><td class=\"num\">$heap1</td><td class=\"num\">$heap2</td></tr>"
            echo "<tr class=\"code\" hidden><td colspan=\"7\">"
            cat "$CODE/$name.html" 2>/dev/null || echo "<p>Code not found in the sources.</p>"
            echo "</td></tr>"
        done < "$lines"
        echo "</table>"
        echo "<h2 id=\"shared\">Fixtures and helpers</h2>"
        cat "$CODE/shared.html"
        cat <<'EOF'
<script>
document.querySelectorAll('td.name').forEach(function (cell) {
  cell.addEventListener('click', function () {
    var row = cell.parentElement.nextElementSibling;
    row.hidden = !row.hidden;
  });
});
</script>
</body></html>
EOF
    } > "$base.html"
}

write_code
FAILED=0
for device in $DEVICES; do
    echo "== device $device"
    "$HDC" -t "$device" uninstall "$BUNDLE" > /dev/null || true
    out="$("$HDC" -t "$device" install -r "$HAP")"
    case "$out" in
        *"install bundle successfully"*) ;;
        *) echo "$out"; FAILED=1; continue ;;
    esac
    # The screen must be on when the app starts (it then keeps it on itself) and the per-process
    # log quota must be off: the Cangjie GC logs enough to make hilog drop the app's own lines.
    "$HDC" -t "$device" shell "power-shell wakeup" > /dev/null
    "$HDC" -t "$device" shell "hilog -Q pidoff; hilog -Q domainoff; hilog -r" > /dev/null

    log="$WORK/hilog-$(echo "$device" | tr -c 'A-Za-z0-9\n' '_').txt"
    : > "$log"
    "$HDC" -t "$device" shell hilog -T ArkTSBench > "$log" 2>/dev/null &
    reader=$!
    sleep 1
    "$HDC" -t "$device" shell aa start -a EntryAbility -b "$BUNDLE" > /dev/null

    waited=0
    while :; do
        sleep 5
        waited=$((waited + 5))
        if grep -q 'DONE' "$log"; then
            break
        fi
        if [ $waited -ge $TIMEOUT ]; then
            echo "timed out after ${TIMEOUT}s"
            FAILED=1
            break
        fi
    done
    kill $reader 2>/dev/null || true
    wait $reader 2>/dev/null || true
    "$HDC" -t "$device" shell "hilog -Q pidon; hilog -Q domainon" > /dev/null
    echo "== finished in ${waited}s"
    grep 'ERROR|' "$log" | sed 's/.*ERROR|/  ERROR /' || true

    model="$("$HDC" -t "$device" shell param get const.product.model | tr -d '\r' | sed 's/[[:space:]]*$//' | tr -c 'A-Za-z0-9\n-' '_')"
    stamp="$(date +%Y-%m-%d-%H%M)"
    lines="$WORK/results.txt"
    # Some devices log every line twice.
    sed -n 's/.*RESULT|//p' "$log" | tr -d '\r' | awk '!seen[$0]++' > "$lines"
    base="$RESULTS/$model-$stamp"
    write_results "$lines" "$model" "$stamp" "$base"
    echo "== $(wc -l < "$lines" | tr -d ' ') results: $base.csv, $base.html"
    column -t -s '|' "$lines" | sed 's/^/  /'
done
exit $FAILED
