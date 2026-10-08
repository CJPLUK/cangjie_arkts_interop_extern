package ohos_app_cangjie_entry.arkts.tests

import ohos.ark_interop.*

func step0Scenarios(): Array<(String, Scenario)> {
    [
        ("step0.trivial", { _, _ => "" }),
        ("step0.readFixture", readFixture),
        ("step0.writeFixture", writeFixture),
        ("step0.reportsFailure", { _, _ => expectEqual("deliberate", 1, 2) }),
        ("step0.reportsException", { _, _ => throw IllegalStateException("deliberate") }),
        ("step0.expectThrowsHelper", { _, _ => expectThrowsHelper() })
    ]
}

/** `expectThrows` must accept the right exception and report every other outcome. */
func expectThrowsHelper(): String {
    firstFailure([
        expectEqual("matching exception",
            expectThrows<IllegalStateException>("x", "boom", { => throw IllegalStateException("boom") }), ""),
        expectEqual("no exception",
            expectThrows<IllegalStateException>("x", "boom", { => 42 }), "x: expected an exception, returned 42"),
        expectEqual("wrong type",
            expectThrows<IllegalStateException>("x", "boom", { => throw IllegalArgumentException("boom") }),
            "x: wrong exception 'IllegalArgumentException: boom'"),
        expectEqual("wrong message",
            expectThrows<IllegalStateException>("x", "boom", { => throw IllegalStateException("bang") }),
            "x: expected 'boom' in 'IllegalStateException: bang'")
    ])
}

/** fixtures[0] is a Rectangle(3, 4); reads it with plain ark_interop. */
func readFixture(_: JSContext, fixtures: Array<JSValue>): String {
    let rect = fixture(fixtures, 0).asObject()
    firstFailure([
        expectEqual("width", rect["width"].toNumber(), 3.0),
        expectEqual("height", rect["height"].toNumber(), 4.0)
    ])
}

/** fixtures[0] is a Rectangle; sets width = 5 with plain ark_interop. ArkTS checks the effect. */
func writeFixture(context: JSContext, fixtures: Array<JSValue>): String {
    fixture(fixtures, 0).asObject()["width"] = context.number(5.0).toJSValue()
    ""
}
