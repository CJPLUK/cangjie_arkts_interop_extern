import std.collection.*

/**
 * A foreign runtime that evaluates nothing. It records every call the compiler generates
 * (`memberAccess`, `indexedAccess`, `memberUpdate`, `indexedUpdate`, `functionCall`), and every
 * value passed to `toExtern` and `fromExtern`, as strings in `log`.
 *
 * Payloads are strings naming the value, e.g. `Extern<RecordingRuntime>("e")` renders as `e`. Each read or call
 * returns a fresh payload `r1`, `r2`, ... so later calls show which result they consumed.
 */
public class RecordingRuntime <: ForeignRuntime<RecordingRuntime> {
    public static let log = ArrayList<String>()
    private static var results = 0

    public static func reset(): Unit {
        log.clear()
        results = 0
    }

    public static func named(name: String): Extern<RecordingRuntime> {
        Extern<RecordingRuntime>(name)
    }

    private static func result(): Extern<RecordingRuntime> {
        results++
        named("r${results}")
    }

    public static func memberAccess(e: Extern<RecordingRuntime>, field: String): Extern<RecordingRuntime> {
        log.add("memberAccess(${render(e)}, ${field})")
        result()
    }

    public static func indexedAccess(e: Extern<RecordingRuntime>, arg: Any): Extern<RecordingRuntime> {
        log.add("indexedAccess(${render(e)}, ${renderLeaf(arg)})")
        result()
    }

    public static func memberUpdate(e: Extern<RecordingRuntime>, field: String, value: Any): Unit {
        log.add("memberUpdate(${render(e)}, ${field}, ${renderLeaf(value)})")
    }

    public static func indexedUpdate(e: Extern<RecordingRuntime>, field: Any, value: Any): Unit {
        log.add("indexedUpdate(${render(e)}, ${renderLeaf(field)}, ${renderLeaf(value)})")
    }

    public static func functionCall(e: Extern<RecordingRuntime>, args: Array<Any>): Extern<RecordingRuntime> {
        log.add("functionCall(${render(e)}, [${joinLeaves(args)}])")
        result()
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

    public static func render(e: Extern<RecordingRuntime>): String {
        (Extern<RecordingRuntime>.getPayload(e) as String) ?? "<payload>"
    }

    /** Renders an operand with its runtime type, e.g. `1:Int64`, or a payload's name. */
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
