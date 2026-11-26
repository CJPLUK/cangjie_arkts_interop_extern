package arkts_runtime.tests

import arkts_runtime.*



@When[bundle == "com.example.testArkTSForeignRuntime"]
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

@When[bundle == "com.example.testArkTSForeignRuntime"]
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

@When[bundle == "com.example.testArkTSForeignRuntime"]
func readFixture(_: JS, fixtures: Array<NativeJSValue>): String {
    let rect = fixture(fixtures, 0).asObject()
    firstFailure([
        expectEqual("width", rect["width"].toNumber(), 3.0),
        expectEqual("height", rect["height"].toNumber(), 4.0)
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func writeFixture(js: JS, fixtures: Array<NativeJSValue>): String {
    fixture(fixtures, 0).asObject()["width"] = js.number(5.0).toJSValue()
    ""
}
