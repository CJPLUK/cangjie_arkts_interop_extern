import std.collection.*

/**
 * A foreign runtime that evaluates nothing. It records every tree passed to `eval` and
 * `fromExtern`, and every value passed to `toExtern`, as strings in `log`.
 *
 * Payloads are strings naming the value, e.g. `ExternPayload("e")` renders as `e`. `eval`
 * returns a fresh payload `r1`, `r2`, ... so later trees show which result they consumed.
 */
public class RecordingRuntime <: ForeignRuntime<RecordingRuntime> {
    public static let log = ArrayList<String>()
    private static var results = 0

    public static func reset(): Unit {
        log.clear()
        results = 0
    }

    public static func named(name: String): Extern<RecordingRuntime> {
        Extern<RecordingRuntime>.ExternPayload(name)
    }

    public static func eval(tree: Extern<RecordingRuntime>): Extern<RecordingRuntime> {
        log.add("eval ${render(tree)}")
        results++
        named("r${results}")
    }

    public static func toExtern<R>(value: R): Extern<RecordingRuntime> {
        log.add("toExtern ${renderLeaf(value)}")
        named("t(${renderLeaf(value)})")
    }

    public static func fromExtern<R>(value: Extern<RecordingRuntime>): R {
        log.add("fromExtern ${render(value)}")
        match (None<R>) {
            case _: Option<Float64> => (0.0 as R).getOrThrow()
            case _: Option<Int64> => (0 as R).getOrThrow()
            case _: Option<String> => ("" as R).getOrThrow()
            case _ => throw ExternConversionException("RecordingRuntime: unsupported target")
        }
    }

    public static func render(tree: Extern<RecordingRuntime>): String {
        match (tree) {
            case ExternPayload(p) => (p as String) ?? "<payload>"
            case ExternMemberAccess(t, f) => "Member(${render(t)}, ${f})"
            case ExternIndexedAccess(t, i) => "Index(${render(t)}, ${renderLeaf(i)})"
            case ExternMemberUpdate(t, f, v) => "MemberUpdate(${render(t)}, ${f}, ${renderLeaf(v)})"
            case ExternIndexedUpdate(t, i, v) =>
                "IndexUpdate(${render(t)}, ${renderLeaf(i)}, ${renderLeaf(v)})"
            case ExternFunctionCall(t, args) =>
                "Call(${render(t)}, [${joinLeaves(args)}])"
            case ExternCompoundAssignment(t, op, v) => "Compound(${render(t)}, ${op}, ${renderLeaf(v)})"
            case _ => "<derived>"
        }
    }

    /** Renders an operand with its runtime type, e.g. `1:Int64`, or a nested tree. */
    public static func renderLeaf(value: Any): String {
        match (value) {
            case e: Extern<RecordingRuntime> => render(e)
            case v: Int64 => "${v}:Int64"
            case v: Int32 => "${v}:Int32"
            case v: Float64 => "${v}:Float64"
            case v: Bool => "${v}:Bool"
            case v: String => "\"${v}\":String"
            case _: Unit => "():Unit"
            case v: Array<Int64> => "[${joinLeaves(v)}]:Array<Int64>"
            case _ => "<other>"
        }
    }

    private static func joinLeaves<T>(values: Array<T>): String {
        var out = ""
        for (i in 0..values.size) {
            if (i > 0) { out += ", " }
            out += renderLeaf(values[i])
        }
        out
    }
}
