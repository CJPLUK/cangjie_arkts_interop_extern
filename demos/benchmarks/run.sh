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

# Render a separate chart for each benchmark, grouped by its name prefix.
write_chart() {
    awk -F, '
        function esc(s) { gsub(/\&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); gsub(/"/, "\\&quot;", s); return s }
        function x(r) { return 60 + (runs == 1 ? 240 : (r - 1) * 480 / (runs - 1)) }
        function y(v) { return 15 + (maxv - v) * 140 / (maxv - minv) }
        FNR == 1 { runs++; next }
        {
            stamp[runs] = $1
            if (!($4 in idx)) {
                idx[$4] = ++nb; names[nb] = $4
                group = $4; sub(/\..*/, "", group)
                groups[nb] = group
                if (!(group in groupidx)) { groupidx[group] = ++ng; groupnames[ng] = group }
            }
            b = idx[$4]
            if ($6 != "" && $6 + 0 > 0) values[b, runs, 1] = $6 + 0
            if ($7 != "" && $7 + 0 > 0) values[b, runs, 2] = $7 + 0
        }
        END {
            for (g = 1; g <= ng; g++) {
                group = groupnames[g]
                printf "<section class=\"chart-group\"><h3>%s</h3><div class=\"chart-grid\">\n", esc(group)
                for (b = 1; b <= nb; b++) {
                    if (groups[b] != group) continue
                    seen = 0; latest = 0; previous = 0
                    for (r = 1; r <= runs; r++) {
                        if ((b, r, 2) in values) { previous = latest; latest = r }
                        for (series = 1; series <= 2; series++) if ((b, r, series) in values) {
                            v = values[b, r, series]
                            if (!seen || v < minv) minv = v
                            if (!seen || v > maxv) maxv = v
                            seen = 1
                        }
                    }
                    if (!seen) continue
                    pad = (maxv - minv) * 0.1
                    if (pad == 0) pad = maxv * 0.1
                    minv = minv - pad; if (minv < 0) minv = 0
                    maxv += pad
                    printf "<article class=\"chart-card\" data-name=\"%s\"><h4>%s</h4>", esc(names[b]), esc(names[b])
                    if (latest) {
                        printf "<p>Latest arkts_runtime: <strong>%.1f ns/op</strong>", values[b, latest, 2]
                        if (previous) printf " (%+.1f%% vs previous result)", 100 * (values[b, latest, 2] / values[b, previous, 2] - 1)
                        else printf " (no previous result)"
                        print "</p>"
                    } else print "<p>No arkts_runtime result</p>"
                    printf "<svg class=\"history\" viewBox=\"0 0 560 195\" role=\"group\" tabindex=\"0\" aria-label=\"%s timing history, nanoseconds per operation. Use left and right arrows to inspect runs.\">", esc(names[b])
                    for (i = 0; i <= 2; i++) {
                        v = minv + (maxv - minv) * i / 2
                        printf "<line class=\"grid\" x1=\"60\" x2=\"540\" y1=\"%.1f\" y2=\"%.1f\"/><text class=\"axis\" x=\"55\" y=\"%.1f\" text-anchor=\"end\">%.1f</text>", y(v), y(v), y(v)+4, v
                    }
                    for (series = 1; series <= 2; series++) {
                        cls = series == 1 ? "interop" : "runtime"
                        prev = 0
                        for (r = 1; r <= runs; r++) {
                            if (!((b, r, series) in values)) { prev = 0; continue }
                            v = values[b, r, series]
                            if (prev) printf "<line class=\"%s line\" x1=\"%.1f\" y1=\"%.1f\" x2=\"%.1f\" y2=\"%.1f\"/>", cls, x(prev), y(values[b, prev, series]), x(r), y(v)
                            prev = r
                        }
                        for (r = 1; r <= runs; r++) if ((b, r, series) in values)
                            printf "<circle class=\"%s point\" cx=\"%.1f\" cy=\"%.1f\" r=\"4\"><title>%s — %s: %.1f ns/op</title></circle>", cls, x(r), y(values[b, r, series]), (cls == "interop" ? "ark_interop" : "arkts_runtime"), esc(stamp[r]), values[b, r, series]
                    }
                    # Full-height hit areas make dense and overlapping points easy to inspect.
                    for (r = 1; r <= runs; r++) {
                        if (!((b, r, 1) in values) && !((b, r, 2) in values)) continue
                        left = r == 1 ? 52 : (x(r-1) + x(r)) / 2
                        right = r == runs ? 548 : (x(r) + x(r+1)) / 2
                        runtime = (b, r, 2) in values ? sprintf("%.1f ns/op", values[b, r, 2]) : "No result"
                        interop = (b, r, 1) in values ? sprintf("%.1f ns/op", values[b, r, 1]) : "No result"
                        printf "<rect class=\"hover-target\" x=\"%.1f\" y=\"8\" width=\"%.1f\" height=\"152\" data-date=\"%s\" data-runtime=\"%s\" data-interop=\"%s\"/>", left, right-left, esc(stamp[r]), runtime, interop
                    }
                    printf "<text class=\"axis\" x=\"60\" y=\"180\">%s</text><text class=\"axis\" x=\"540\" y=\"180\" text-anchor=\"end\">%s</text></svg></article>\n", esc(stamp[1]), esc(stamp[runs])
                }
                print "</div></section>"
            }
        }
    ' "$@"
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
svg.history { width: 100%; font-size: 11px; overflow: visible; }
svg.history .grid { stroke: #ddd; }
svg.history .axis { fill: #555; }
svg.history .line { stroke-width: 2; }
svg.history .interop.line { stroke: #1976a3; }
svg.history .runtime.line { stroke: #bd4b20; }
svg.history .interop.point { fill: #1976a3; }
svg.history .runtime.point { fill: #bd4b20; }
svg.history .hover-target { fill: transparent; pointer-events: all; cursor: crosshair; }
svg.history .hover-target.active { fill: rgba(25, 118, 163, 0.1); }
svg.history:focus-visible { outline: 2px solid #1976a3; outline-offset: 3px; }
.chart-tooltip { position: fixed; z-index: 1000; pointer-events: none; width: max-content; white-space: pre-line; padding: 8px 12px; border-radius: 5px; background: #17212b; color: #fff; font-size: 13px; line-height: 1.5; box-shadow: 0 2px 8px #0003; max-width: calc(100vw - 16px); }
.chart-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 500px), 600px)); gap: 1em; }
.chart-card { border: 1px solid #ddd; border-radius: 6px; padding: 1em; min-width: 0; }
.chart-card h4, .chart-card p { margin: 0 0 0.5em; }
.chart-group { margin: 1.5em 0; }
.legend-runtime { color: #bd4b20; } .legend-interop { color: #1976a3; }
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
        echo "<h2>arkts_runtime across runs</h2>"
        echo '<p>Each chart has its own linear vertical scale in ns/op; lower is faster. Hover over a chart to see both timings and the run date, or focus it and use the arrow keys. Gaps indicate missing results.</p>'
        echo '<p><span class="legend-runtime">● arkts_runtime</span> &nbsp; <span class="legend-interop">● ark_interop</span></p>'
        echo '<label>Search benchmarks: <input id="chart-search" type="search" placeholder="Name or category"></label>'
        write_chart "$RESULTS/$device"-*.csv
        echo "<h2 id=\"shared\">Fixtures and helpers</h2>"
        cat "$CODE/shared.html"
        cat <<'EOF'
<div id="chart-tooltip" class="chart-tooltip" role="tooltip" hidden></div>
<script>
var chartTooltip = document.getElementById('chart-tooltip');
var activeTarget = null;
function hideChartTooltip() {
  chartTooltip.hidden = true;
  if (activeTarget) {
    activeTarget.classList.remove('active');
    activeTarget.ownerSVGElement.removeAttribute('aria-describedby');
    activeTarget = null;
  }
}
function showChartTooltip(target, clientX, clientY) {
  if (activeTarget && activeTarget !== target) {
    activeTarget.classList.remove('active');
    activeTarget.ownerSVGElement.removeAttribute('aria-describedby');
  }
  activeTarget = target;
  target.classList.add('active');
  target.ownerSVGElement.setAttribute('aria-describedby', chartTooltip.id);
  chartTooltip.textContent = target.dataset.date + '\narkts_runtime: ' + target.dataset.runtime +
    '\nark_interop: ' + target.dataset.interop;
  chartTooltip.hidden = false;
  var bounds = chartTooltip.getBoundingClientRect();
  chartTooltip.style.left = Math.max(8, Math.min(clientX + 12, window.innerWidth - bounds.width - 8)) + 'px';
  chartTooltip.style.top = Math.max(8, Math.min(clientY + 12, window.innerHeight - bounds.height - 8)) + 'px';
}
document.querySelectorAll('svg.history').forEach(function (chart) {
  var targets = Array.from(chart.querySelectorAll('.hover-target'));
  var selected = targets.length - 1;
  function inspectSelected() {
    if (!targets.length) return;
    var rect = targets[selected].getBoundingClientRect();
    showChartTooltip(targets[selected], rect.left + rect.width / 2, rect.top);
  }
  chart.addEventListener('pointermove', function (event) {
    if (!event.target.classList.contains('hover-target')) { hideChartTooltip(); return; }
    selected = targets.indexOf(event.target);
    showChartTooltip(event.target, event.clientX, event.clientY);
  });
  chart.addEventListener('pointerleave', hideChartTooltip);
  chart.addEventListener('focus', inspectSelected);
  chart.addEventListener('blur', hideChartTooltip);
  chart.addEventListener('keydown', function (event) {
    if (event.key === 'Escape') { hideChartTooltip(); return; }
    if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
    event.preventDefault();
    if (event.key === 'Home') selected = 0;
    else if (event.key === 'End') selected = targets.length - 1;
    else selected = Math.max(0, Math.min(targets.length - 1, selected + (event.key === 'ArrowLeft' ? -1 : 1)));
    inspectSelected();
  });
});
window.addEventListener('scroll', hideChartTooltip, true);
window.addEventListener('resize', hideChartTooltip);
document.getElementById('chart-search').addEventListener('input', function () {
  hideChartTooltip();
  var query = this.value.toLowerCase().trim();
  document.querySelectorAll('.chart-group').forEach(function (group) {
    var visible = 0;
    group.querySelectorAll('.chart-card').forEach(function (card) {
      card.hidden = !card.dataset.name.toLowerCase().includes(query);
      if (!card.hidden) visible++;
    });
    group.hidden = visible === 0;
  });
});
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
    if grep -q 'ERROR|' "$log"; then
        grep 'ERROR|' "$log" | sed 's/.*ERROR|/  ERROR /'
        FAILED=1
    fi

    model="$("$HDC" -t "$device" shell param get const.product.model | tr -d '\r' | sed 's/[[:space:]]*$//' | tr -c 'A-Za-z0-9\n-' '_')"
    stamp="$(date +%Y-%m-%d-%H%M)"
    lines="$WORK/results.txt"
    # Some devices log every line twice.
    sed -n 's/.*RESULT|//p' "$log" | tr -d '\r' | awk '!seen[$0]++' > "$lines"
    base="$RESULTS/$model-$stamp"
    write_results "$lines" "$model" "$stamp" "$base"
    # Keep complete sample groups alongside the report, outside chart-history CSVs.
    sed -n -e 's/.*SAMPLE|/I|/p' -e 's/.*SAMPLES|/A|/p' "$log" | tr -d '\r' | awk -F'|' '
        BEGIN { OFS="\t"; print "benchmark", "variant", "sample", "iterations", "total_ns" }
        !seen[$0]++ {
            if ($1 == "I") print $2, $3, $4, $5, $6
            else {
                count = split($5, values, ",")
                for (i = 1; i <= count; i++) print $2, $3, i - 1, $4, values[i]
            }
        }
    ' > "$base.samples.tsv"
    echo "== $(wc -l < "$lines" | tr -d ' ') results: $base.csv, $base.html"
    column -t -s '|' "$lines" | sed 's/^/  /'
done
exit $FAILED
