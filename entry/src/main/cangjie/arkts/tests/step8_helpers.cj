package ohos_app_cangjie_entry.arkts.tests

import std.collection.*
import ohos.ark_interop.*
import ohos.business_exception.BusinessException
import ohos_app_cangjie_entry.arkts.*

func step8Scenarios(): Array<(String, Scenario)> {
    [
        ("step8.undefinedAndNull", { c, f => undefinedAndNull(c, f) }),
        ("step8.objectIsFresh", { _, f => objectIsFresh(f) }),
        ("step8.globalIsGlobalThis", { _, f => globalIsGlobalThis(f) }),
        ("step8.symbols", { _, f => symbols(f) }),
        ("step8.strictEqualTable", { _, f => strictEqualTable(f) }),
        ("step8.objectProperties", { _, f => objectProperties(f) }),
        ("step8.defineOwnProperty", { _, f => defineOwnProperty(f) }),
        ("step8.requireArkModule", { _, _ => requireArkModule() }),
        ("step8.requireSystemNativeModule", { _, _ => requireSystemNativeModule() })
    ]
}

func step8OffThreadScenarios(): Array<(String, OffThreadScenario)> {
    [("step8.helpersFromOtherThread", helpersFromOtherThread)]
}

const TEST_MODULE = "entry/src/main/ets/arkts/TestModule"

func foreignPayloadFails(what: String, block: () -> Any): String {
    expectThrows<ExternConversionException>(what, "Extern payload was not produced by ArkTSRuntime", block)
}

/**
 * fixtures: sink, Rectangle. Stores undefined() and null(); ArkTS checks them. isUndefined /
 * isNull are true only for their own kind.
 */
func undefinedAndNull(context: JSContext, fixtures: Array<JSValue>): String {
    let sink = ext(fixtures, 0)
    sink.u = ArkTSRuntime.undefined()
    sink.n = ArkTSRuntime.null()
    let kinds: Array<(String, E)> = [
        ("undefined", ArkTSRuntime.undefined()),
        ("null", ArkTSRuntime.null()),
        ("false", to(false)),
        ("0", to(0.0)),
        ("\"\"", to("")),
        ("NaN", to(Float64.NaN)),
        ("0n", to(0)),
        ("object", ArkTSRuntime.object()),
        ("array", to(Array<Int32>())),
        ("function", ArkTSRuntime.retain(context.global.getProperty("String"))),
        ("symbol", ArkTSRuntime.symbol()),
        ("class instance", ext(fixtures, 1))
    ]
    let table = kinds.map({ row =>
        let (name, value) = row
        firstFailure([
            expectEqual("isUndefined(${name})", ArkTSRuntime.isUndefined(value), name == "undefined"),
            expectEqual("isNull(${name})", ArkTSRuntime.isNull(value), name == "null")
        ])
    })
    firstFailure([
        firstFailure(table),
        expectEqual("isUndefined of a tree", ArkTSRuntime.isUndefined(member(sink, "u")), true),
        foreignPayloadFails("isUndefined(foreign payload)", { => ArkTSRuntime.isUndefined(payload()) }),
        foreignPayloadFails("isNull(foreign payload)", { => ArkTSRuntime.isNull(payload()) })
    ])
}

/** fixtures: sink. ArkTS checks o1 and o2 are distinct empty objects. */
func objectIsFresh(fixtures: Array<JSValue>): String {
    let sink = ext(fixtures, 0)
    let o1 = ArkTSRuntime.object()
    let o2 = ArkTSRuntime.object()
    sink.o1 = o1
    sink.o2 = o2
    firstFailure([
        expectEqual("o1 === o2", ArkTSRuntime.strictEqual(o1, o2), false),
        expectEqual("keys", ArkTSRuntime.objectKeys(o1).size, 0)
    ])
}

/** fixtures: globalThis. */
func globalIsGlobalThis(fixtures: Array<JSValue>): String {
    let g = ArkTSRuntime.global()
    firstFailure([
        expectEqual("global() === globalThis", ArkTSRuntime.strictEqual(g, ext(fixtures, 0)), true),
        expectEqual("global().JSON.stringify(1.5)", from<String>(g.JSON.stringify(1.5)), "1.5")
    ])
}

/** fixtures: sink. ArkTS checks s1.description === "d", s1 !== s2, and the default description. */
func symbols(fixtures: Array<JSValue>): String {
    let sink = ext(fixtures, 0)
    let s1 = ArkTSRuntime.symbol(description: "d")
    let s2 = ArkTSRuntime.symbol(description: "d")
    sink.s1 = s1
    sink.s2 = s2
    sink.plain = ArkTSRuntime.symbol()
    firstFailure([
        expectEqual("s1 === s2", ArkTSRuntime.strictEqual(s1, s2), false),
        expectEqual("s1 === s1", ArkTSRuntime.strictEqual(s1, s1), true),
        expectEqual("s1.description", from<String>(s1.description), "d")
    ])
}

/**
 * fixtures: pairs (array of [a, b]), expected (ArkTS `a === b` for each pair), Rectangle.
 * Then pairs made in Cangjie, and trees as operands.
 */
func strictEqualTable(fixtures: Array<JSValue>): String {
    let pairs = from<Array<Array<E>>>(ext(fixtures, 0))
    let expected = from<Array<Bool>>(ext(fixtures, 1))
    let rect = ext(fixtures, 2)
    let fromArkTS = Array<String>(pairs.size) { i =>
        expectEqual("pair ${i}", ArkTSRuntime.strictEqual(pairs[i][0], pairs[i][1]), expected[i])
    }
    firstFailure([
        firstFailure(fromArkTS),
        expectEqual("\"a\" === \"a\" (Cangjie strings)", ArkTSRuntime.strictEqual(to("a"), to("a")), true),
        expectEqual("1n === 1n (Int64)", ArkTSRuntime.strictEqual(to(1), to(1)), true),
        expectEqual("1n === 1 (Int64, Float64)", ArkTSRuntime.strictEqual(to(1), to(1.0)), false),
        expectEqual("rect.width === rect.width (trees)",
            ArkTSRuntime.strictEqual(member(rect, "width"), member(rect, "width")), true),
        foreignPayloadFails("strictEqual(foreign payload)", { => ArkTSRuntime.strictEqual(rect, payload()) })
    ])
}

/** fixtures: Rectangle, [1, 2]. `objectHasProperty` follows JS `in`; `objectKeys` is `Object.keys`. */
func objectProperties(fixtures: Array<JSValue>): String {
    let rect = ext(fixtures, 0)
    let items = ext(fixtures, 1)
    let o = ArkTSRuntime.object()
    o.visible = 1.0
    ArkTSRuntime.objectDefineOwnProperty(o, "hidden", 2.0, isEnumerable: false)
    o[ArkTSRuntime.symbol()] = 3.0
    func notObject(what: String, block: () -> Any): String {
        expectThrows<ExternConversionException>(what, "ArkTS value is not an object", block)
    }
    firstFailure([
        expectEqual("has own 'width'", ArkTSRuntime.objectHasProperty(rect, "width"), true),
        expectEqual("has inherited 'area'", ArkTSRuntime.objectHasProperty(rect, "area"), true),
        expectEqual("has inherited 'toString'", ArkTSRuntime.objectHasProperty(rect, "toString"), true),
        expectEqual("has 'missing'", ArkTSRuntime.objectHasProperty(rect, "missing"), false),
        expectEqual("has non-enumerable 'hidden'", ArkTSRuntime.objectHasProperty(o, "hidden"), true),
        expectEqual("keys of Rectangle", ArkTSRuntime.objectKeys(rect), ["width", "height"]),
        expectEqual("keys skip non-enumerable and symbols", ArkTSRuntime.objectKeys(o), ["visible"]),
        expectEqual("keys of an array", ArkTSRuntime.objectKeys(items), ["0", "1"]),
        expectEqual("has '1' on an array", ArkTSRuntime.objectHasProperty(items, "1"), true),
        expectEqual("keys of a tree (globalThis.JSON)",
            ArkTSRuntime.objectKeys(member(ArkTSRuntime.global(), "JSON")).size, 0),
        notObject("objectHasProperty(1.5)", { => ArkTSRuntime.objectHasProperty(to(1.5), "x") }),
        notObject("objectKeys(\"s\")", { => ArkTSRuntime.objectKeys(to("s")) }),
        notObject("objectKeys(undefined)", { => ArkTSRuntime.objectKeys(ArkTSRuntime.undefined()) }),
        notObject("objectDefineOwnProperty(null)", { => ArkTSRuntime.objectDefineOwnProperty(ArkTSRuntime.null(), "x", 1.0) })
    ])
}

/**
 * fixtures: sink, frozen object. Defines one property per flag combination (named by its
 * flags, e.g. "wEc" = writable, not enumerable, configurable); ArkTS checks each descriptor.
 */
func defineOwnProperty(fixtures: Array<JSValue>): String {
    let sink = ext(fixtures, 0)
    let frozen = ext(fixtures, 1)
    let results = ArrayList<String>()
    for (w in [true, false]) {
        for (e in [true, false]) {
            for (c in [true, false]) {
                let name = (if (w) { "W" } else { "w" }) + (if (e) { "E" } else { "e" }) + (if (c) { "C" } else { "c" })
                let ok = ArkTSRuntime.objectDefineOwnProperty(sink, name, name, isWritable: w, isEnumerable: e,
                    isConfigurable: c)
                results.add(expectEqual("define ${name}", ok, true))
            }
        }
    }
    firstFailure([
        firstFailure(results.toArray()),
        expectThrows<ForeignRuntimeException>("define on a frozen object", "Cannot define property",
            { => ArkTSRuntime.objectDefineOwnProperty(frozen, "x", 1.0) }),
        expectThrows<ForeignRuntimeException>("redefine read-only non-configurable", "Cannot define property",
            { => ArkTSRuntime.objectDefineOwnProperty(sink, "wec", 1.0) }),
        expectEqual("redefine configurable", ArkTSRuntime.objectDefineOwnProperty(sink, "WEC", "again"), true)
    ])
}

func requireArkModule(): String {
    let m = ArkTSRuntime.requireArkModule(TEST_MODULE)
    let hilog = ArkTSRuntime.requireArkModule("@ohos.hilog")
    let missing = try {
        ArkTSRuntime.requireArkModule("entry/src/main/ets/arkts/Missing")
        "missing module: expected an exception"
    } catch (e: BusinessException) {
        expectEqual("missing module: code", e.code, 34300006)
    }
    firstFailure([
        expectEqual("m.add(1, 2)", from<Float64>(m.add(1.0, 2.0)), 3.0),
        expectEqual("m.moduleName", from<String>(m.moduleName), "TestModule"),
        expectEqual("@ohos.hilog has info()", ArkTSRuntime.objectHasProperty(hilog, "info"), true),
        missing
    ])
}

func requireSystemNativeModule(): String {
    let hilog = ArkTSRuntime.requireSystemNativeModule("hilog", None)
    firstFailure([
        expectEqual("hilog.info is a function", unwrap(hilog.info).isFunction(), true),
        expectEqual("missing module is undefined",
            ArkTSRuntime.isUndefined(ArkTSRuntime.requireSystemNativeModule("doesNotExist", None)), true)
    ])
}

/**
 * Every helper from a spawned thread. `requireArkModule` is the exception: without ArkTS code on
 * the stack the engine cannot resolve the specifier (known limitation).
 */
func helpersFromOtherThread(): String {
    let o = ArkTSRuntime.object()
    let s = ArkTSRuntime.symbol(description: "t")
    let defined = ArkTSRuntime.objectDefineOwnProperty(o, "k", 1.5)
    let hilog = ArkTSRuntime.requireSystemNativeModule("hilog", None)
    firstFailure([
        expectThrows<ForeignRuntimeException>("requireArkModule", "Unable to get recordName",
            { => ArkTSRuntime.requireArkModule(TEST_MODULE) }),
        expectEqual("isUndefined(undefined())", ArkTSRuntime.isUndefined(ArkTSRuntime.undefined()), true),
        expectEqual("isNull(null())", ArkTSRuntime.isNull(ArkTSRuntime.null()), true),
        expectEqual("global().JSON", ArkTSRuntime.isUndefined(ArkTSRuntime.global().JSON), false),
        expectEqual("symbol description", from<String>(s.description), "t"),
        expectEqual("strictEqual", ArkTSRuntime.strictEqual(o, o), true),
        expectEqual("defineOwnProperty", defined, true),
        expectEqual("objectHasProperty", ArkTSRuntime.objectHasProperty(o, "k"), true),
        expectEqual("objectKeys", ArkTSRuntime.objectKeys(o), ["k"]),
        expectEqual("requireSystemNativeModule", ArkTSRuntime.isUndefined(hilog), false)
    ])
}
