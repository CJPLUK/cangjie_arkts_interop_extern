package arkts_runtime.tests


import arkts_runtime.*

@When[bundle == "com.example.testArkTSForeignRuntime"]
func step7Scenarios(): Array<(String, Scenario)> {
    [
        ("step7.nativeJSException", { _, f => nativeJSException(f) }),
        ("step7.jsThrowsBecomeForeignRuntimeException", { _, f => jsThrowsBecomeForeignRuntimeException(f) }),
        ("step7.ownExceptionsNotWrapped", { _, f => ownExceptionsNotWrapped(f) }),
        ("step7.usableAfterJSException", { _, f => usableAfterJSException(f) })
    ]
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func step7OffThreadScenarios(): Array<(String, OffThreadScenario)> {
    [("step7.jsExceptionFromOtherThread", jsExceptionFromOtherThread)]
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func nativeJSException(fixtures: Array<NativeJSValue>): String {
    let thrower = fixture(fixtures, 0)
    func raw(what: String, fragment: String, block: () -> NativeJSValue): String {
        expectThrows<ForeignRuntimeException>(what, fragment, { => block() })
    }
    func callRaw(method: String): NativeJSValue {
        thrower.asObject()[method].asFunction().call(thisArg: thrower)
    }
    firstFailure([
        raw("new Error", "Error\nboom", { => callRaw("boom") }),
        raw("throw string", "message: boom string", { => callRaw("throwString") }),
        raw("TypeError", "TypeError\nmissing is not callable", { => callRaw("typeError") }),
        raw("getter", "boom getter", { => thrower.asObject()["failingGetter"] })
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func jsThrowsBecomeForeignRuntimeException(fixtures: Array<NativeJSValue>): String {
    let thrower = ext(fixtures, 0)
    func fails(what: String, fragment: String, block: () -> Any): String {
        expectThrows<ForeignRuntimeException>(what, fragment, block)
    }
    firstFailure([
        fails("thrower.boom()", "boom", { => thrower.boom() }),
        fails("thrower.throwString()", "boom string", { => thrower.throwString() }),
        fails("thrower.typeError()", "missing is not callable", { => thrower.typeError() }),
        fails("thrower.failingGetter", "boom getter", { => thrower.failingGetter })
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func ownExceptionsNotWrapped(fixtures: Array<NativeJSValue>): String {
    let target = ext(fixtures, 0)
    let mismatch = try {
        ArkTSRuntime.run { unwrap(target.num).toString() }
        "toString of a number: expected an exception"
    } catch (ex: ArkTSNativeException) {
        expectEqual("toString of a number: code", ex.code, 34300005)
    }
    firstFailure([
        expectThrows<ExternIndexedAccessException>("target[UInt8(1)]", "Unsupported ArkTS index type",
            { => target[UInt8(1)] }),
        expectThrows<ExternMemberAccessException>("target.nothing.x", "expect: object, given: undefined",
            { => target.nothing.x }),
        expectThrows<ExternFunctionAccessException>("target.num()", "ArkTS value is not a function",
            { => target.num() }),
        expectThrows<ExternConversionException>("Bool from a number", "Cannot convert ArkTS number to Bool",
            { => from<Bool>(target.num) }),
        mismatch
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func usableAfterJSException(fixtures: Array<NativeJSValue>): String {
    let thrower = ext(fixtures, 0)
    let first = expectThrows<ForeignRuntimeException>("first call", "boom", { => thrower.boom() })
    let second = expectThrows<ForeignRuntimeException>("second call", "boom", { => thrower.boom() })
    firstFailure([
        first,
        second,
        expectEqual("thrower.calls", from<Float64>(thrower.calls), 2.0),
        expectEqual("toExtern", from<String>(to("still works")), "still works")
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func jsExceptionFromOtherThread(): String {
    let json = ArkTSRuntime.run { ArkTSRuntime.retain(ArkTSRuntime.js.global.getProperty("JSON")) }
    firstFailure([
        expectThrows<ForeignRuntimeException>("JSON.parse(\"{\")", "SyntaxError", { => json.parse("{") }),
        expectEqual("JSON.parse(\"1\") afterwards", from<Float64>(json.parse("1")), 1.0)
    ])
}
