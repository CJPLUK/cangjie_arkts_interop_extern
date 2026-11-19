package ohos_app_cangjie_entry.difflog

import std.collection.ArrayList
import std.convert.Formattable
import std.math.{abs, trunc}

/** A differential program's output: one `label=value` line per observation, formatted like DiffPrograms.ts. */
public class Transcript {
    private let lines = ArrayList<String>()

    public func num(label: String, x: Float64): Unit { lines.add("${label}=${fmtNum(x)}") }
    public func str(label: String, s: String): Unit { lines.add("${label}=${fmtStr(s)}") }
    public func bool(label: String, b: Bool): Unit { lines.add("${label}=${b}") }
    public func text(label: String, t: String): Unit { lines.add("${label}=${t}") }
    public func append(other: Transcript): Unit { lines.add(all: other.lines) }
    public func render(): String { String.join(lines.toArray(), delimiter: "\n") }
}

public func fmtNum(x: Float64): String {
    if (x.isNaN()) { return "NaN" }
    if (x.isInf()) { return if (x > 0.0) { "Inf" } else { "-Inf" } }
    if (x == 0.0 && x.toBits() != 0) { return "-0" }
    if (abs(x) <= 9007199254740992.0 && x == trunc(x)) { return Int64(x).toString() }
    "f" + x.toBits().format("016x")
}

public func fmtStr(s: String): String {
    let out = StringBuilder("\"")
    for (r in s.runes()) {
        let cp = UInt32(r)
        if (cp >= 0x20 && cp <= 0x7E && r != r'"' && r != r'\\') {
            out.append(r)
        } else {
            out.append("\\u{${cp.format("x")}}")
        }
    }
    out.append("\"")
    out.toString()
}
