package ohos_app_cangjie_entry.arkts.tests

import ohos.ark_interop.*
import ohos.business_exception.BusinessException
import ohos_app_cangjie_entry.arkts.*

func step7Scenarios(): Array<(String, Scenario)> {
    [
        ("step7.arkInteropJSException", { _, f => arkInteropJSException(f) }),
        ("step7.jsThrowsBecomeForeignRuntimeException", { _, f => jsThrowsBecomeForeignRuntimeException(f) }),
        ("step7.ownExceptionsNotWrapped", { _, f => ownExceptionsNotWrapped(f) }),
        ("step7.usableAfterJSException", { _, f => usableAfterJSException(f) })
    ]
}

func step7OffThreadScenarios(): Array<(String, OffThreadScenario)> {
    [("step7.jsExceptionFromOtherThread", jsExceptionFromOtherThread)]
}

/**
 * fixtures: Thrower. Pins what `ark_interop` itself throws for a JS throw, called directly
 * (without `run`): a `BusinessException` with code 34300002 whose message contains the JS text.
 */
func arkInteropJSException(fixtures: Array<JSValue>): String {
    let thrower = fixture(fixtures, 0)
    func raw(what: String, fragment: String, block: () -> JSValue): String {
        try {
            block()
            "${what}: expected an exception"
        } catch (e: BusinessException) {
            firstFailure([
                expectEqual("${what}: code", e.code, 34300002),
                expectEqual("${what}: message contains '${fragment}' ('${e.message}')", e.message.contains(fragment), true)
            ])
        }
    }
    func callRaw(method: String): JSValue {
        thrower.asObject()[method].asFunction().call(thisArg: thrower)
    }
    firstFailure([
        raw("new Error", "Error\nboom", { => callRaw("boom") }),
        raw("throw string", "message: boom string", { => callRaw("throwString") }),
        raw("TypeError", "TypeError\nmissing is not callable", { => callRaw("typeError") }),
        raw("getter", "boom getter", { => thrower.asObject()["failingGetter"] })
    ])
}

/** fixtures: Thrower. Every public entry point turns a JS throw into a ForeignRuntimeException. */
func jsThrowsBecomeForeignRuntimeException(fixtures: Array<JSValue>): String {
    let t = ext(fixtures, 0)
    func fails(what: String, fragment: String, block: () -> Any): String {
        expectThrows<ForeignRuntimeException>(what, fragment, block)
    }
    firstFailure([
        fails("t.boom()", "boom", { => t.boom() }),
        fails("t.throwString()", "boom string", { => t.throwString() }),
        fails("t.typeError()", "missing is not callable", { => t.typeError() }),
        fails("t.failingGetter", "boom getter", { => t.failingGetter }),
        fails("fromExtern of a throwing tree", "boom getter", { => from<Float64>(member(t, "failingGetter")) }),
        fails("toExtern of a throwing tree", "boom getter", { => to(member(t, "failingGetter")) })
    ])
}

/**
 * fixtures: Target. Our exceptions, and `ark_interop` errors that are not JS throws (type
 * mismatch, 34300005), keep their type.
 */
func ownExceptionsNotWrapped(fixtures: Array<JSValue>): String {
    let e = ext(fixtures, 0)
    let mismatch = try {
        ArkTSRuntime.run { unwrap(e.num).toString() }
        "toString of a number: expected an exception"
    } catch (ex: BusinessException) {
        expectEqual("toString of a number: code", ex.code, 34300005)
    }
    firstFailure([
        expectThrows<ExternIndexedAccessException>("e[1.5]", "Unsupported ArkTS index type", { => e[1.5] }),
        expectThrows<ExternMemberAccessException>("e.nothing.x", "Cannot read property 'x' of undefined",
            { => e.nothing.x }),
        expectThrows<ExternFunctionAccessException>("e.num()", "ArkTS 'num' is not a function", { => e.num() }),
        expectThrows<ExternConversionException>("Bool from a number", "Cannot convert ArkTS number to Bool",
            { => from<Bool>(e.num) }),
        mismatch
    ])
}

/** fixtures: Thrower. ArkTS checks calls == 2: the second call after a JS exception ran too. */
func usableAfterJSException(fixtures: Array<JSValue>): String {
    let t = ext(fixtures, 0)
    let first = expectThrows<ForeignRuntimeException>("first call", "boom", { => t.boom() })
    let second = expectThrows<ForeignRuntimeException>("second call", "boom", { => t.boom() })
    firstFailure([
        first,
        second,
        expectEqual("t.calls", from<Float64>(t.calls), 2.0),
        expectEqual("toExtern", from<String>(to("still works")), "still works")
    ])
}

/** `JSON.parse("{")` from a spawned thread: the SyntaxError is rethrown on this thread. */
func jsExceptionFromOtherThread(): String {
    let json = ArkTSRuntime.run { ArkTSRuntime.retain(ArkTSRuntime.context.global.getProperty("JSON")) }
    firstFailure([
        expectThrows<ForeignRuntimeException>("JSON.parse(\"{\")", "SyntaxError", { => json.parse("{") }),
        expectEqual("JSON.parse(\"1\") afterwards", from<Float64>(json.parse("1")), 1.0)
    ])
}
