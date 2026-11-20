package arkts_runtime.tests

import arkts_runtime.*

@When[bundle == "com.example.testArkTSForeignRuntime"]
func lifetimeScenarios(): Array<(String, Scenario)> {
    [
        ("lifetime.pinReadAlias", { _, _ => pinReadAlias() }),
        ("lifetime.fusedOpsSpill", { _, f => fusedOpsSpill(f) }),
        ("lifetime.budgetFillsThenScoped", { _, f => budgetFillsThenScoped(f) }),
        ("lifetime.budgetIsEmpty", { _, _ => budgetIsEmpty() }),
        ("lifetime.newScopeRestoresBudget", { _, f => newScopeRestoresBudget(f) }),
        ("lifetime.repeatedReadReusesPin", { _, f => repeatedReadReusesPin(f) }),
        ("lifetime.textCopies", { _, f => textCopies(f) }),
        ("lifetime.userInterfaceOnScalar", { _, f => userInterfaceOnScalar(f) }),
        ("lifetime.optionImmediates", { _, f => optionImmediates(f) })
    ]
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
let BUDGET_BOUND: UInt32 = (1 << 19) + 128

@When[bundle == "com.example.testArkTSForeignRuntime"]
func pinReadAlias(): String {
    expectEqual("pin read mode", ArkTSRuntime.nativeStats().pinReadAlias, 1)
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func fusedOpsSpill(fixtures: Array<NativeJSValue>): String {
    let e = ext(fixtures, 0)
    let before = ArkTSRuntime.nativeStats()
    let a = e.a
    e.num = 2.0
    let num = e.num
    let after = ArkTSRuntime.nativeStats()
    firstFailure([
        expectEqual("ops spilled", after.opsSpilled - before.opsSpilled, 3),
        expectEqual("ops scoped", after.opsScoped - before.opsScoped, 0),
        expectEqual("pins created (e.a only)", after.pinsCreated - before.pinsCreated, 1),
        expectEqual("units charged", after.budgetUnits > before.budgetUnits, true),
        expectEqual("e.num after write", number(num), 2.0),
        expectEqual("e.a.b.c", number(a.b.c), 42.0)
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func budgetFillsThenScoped(fixtures: Array<NativeJSValue>): String {
    let e = ext(fixtures, 0)
    let keys = ArkTSRuntime.global().Object.keys
    var last = keys(e)
    let before = ArkTSRuntime.nativeStats()
    var maxUnits: UInt32 = 0
    for (_ in 0..10000) {
        last = keys(e)
        maxUnits = max(maxUnits, ArkTSRuntime.nativeStats().budgetUnits)
    }
    let after = ArkTSRuntime.nativeStats()
    firstFailure([
        expectEqual("ops", (after.opsSpilled - before.opsSpilled) + (after.opsScoped - before.opsScoped), 10000),
        expectEqual("some ops ran scoped", after.opsScoped > before.opsScoped, true),
        expectEqual("units within bound (max ${maxUnits})", maxUnits <= BUDGET_BOUND, true),
        expectEqual("last result is an array of keys", number(last.length) > 0.0, true)
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func budgetIsEmpty(): String {
    expectEqual("budget units", ArkTSRuntime.nativeStats().budgetUnits, 0)
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func newScopeRestoresBudget(fixtures: Array<NativeJSValue>): String {
    let e = ext(fixtures, 0)
    let before = ArkTSRuntime.nativeStats()
    let (kept, insideUnits, insideFramesOpen) = ArkTSRuntime.newScope {
        var last = e.a
        for (_ in 0..1000) { last = e.a }
        let inside = ArkTSRuntime.nativeStats()
        (last, inside.budgetUnits, inside.budgetFramesOpen)
    }
    let after = ArkTSRuntime.nativeStats()
    let thrown = try {
        ArkTSRuntime.newScope<Unit> {
            let _ = e.a
            throw IllegalStateException("inside newScope")
        }
        "no exception"
    } catch (x: IllegalStateException) { x.message }
    let afterThrow = ArkTSRuntime.nativeStats()
    firstFailure([
        expectEqual("units charged inside", insideUnits > before.budgetUnits, true),
        expectEqual("frames open inside", insideFramesOpen, before.budgetFramesOpen + 1),
        expectEqual("units after", after.budgetUnits, before.budgetUnits),
        expectEqual("frames open after", after.budgetFramesOpen, before.budgetFramesOpen),
        expectEqual("value made inside, read after", number(kept.b.c), 42.0),
        expectEqual("body's exception", thrown, "inside newScope"),
        expectEqual("frames open after a throw", afterThrow.budgetFramesOpen, before.budgetFramesOpen)
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func repeatedReadReusesPin(fixtures: Array<NativeJSValue>): String {
    let e = ext(fixtures, 0)
    let first = e.a
    let before = ArkTSRuntime.nativeStats()
    let second = e.a
    let afterRepeat = ArkTSRuntime.nativeStats()
    let original = first
    e.a = e.a.b
    let changed = e.a
    let afterChange = ArkTSRuntime.nativeStats()
    e.a = original
    firstFailure([
        expectEqual("pins created by the repeat", afterRepeat.pinsCreated - before.pinsCreated, 0),
        expectEqual("same pin", ArkTSRuntime.samePin(first, second), true),
        expectEqual("pins created after the change", afterChange.pinsCreated - afterRepeat.pinsCreated > 0, true),
        expectEqual("changed value", number(changed.c), 42.0),
        expectEqual("not the old pin", ArkTSRuntime.samePin(changed, first), false)
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func textCopies(fixtures: Array<NativeJSValue>): String {
    let e = ext(fixtures, 0)
    let s = e.str
    let lone = ArkTSRuntime.global().String.fromCharCode(55296.0)
    e.copy = s
    e.lone = lone
    let charCodeAt = ArkTSRuntime.global().String.prototype.charCodeAt.call
    firstFailure([
        expectEqual("kind of a string read", ArkTSRuntime.payloadKind(s), "Text"),
        expectEqual("text", ArkTSRuntime.fromExtern<String>(s), "h\u{e9}llo"),
        expectEqual("written back", ArkTSRuntime.fromExtern<String>(e.copy), "h\u{e9}llo"),
        expectEqual("lone surrogate stays a Pin", ArkTSRuntime.payloadKind(lone), "Pin"),
        expectEqual("lone surrogate round trip", number(charCodeAt(e.lone, 0.0)), 55296.0),
        expectEqual("copied string as an argument", ArkTSRuntime.fromExtern<String>(ArkTSRuntime.global().String(s)), "h\u{e9}llo")
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
interface UserShape { func area(): Float64 }

@When[bundle == "com.example.testArkTSForeignRuntime"]
extend Float64 <: UserShape { public func area(): Float64 { this * this } }

@When[bundle == "com.example.testArkTSForeignRuntime"]
func userInterfaceOnScalar(fixtures: Array<NativeJSValue>): String {
    let e = ext(fixtures, 0)
    let shape = ArkTSRuntime.fromExtern<UserShape>(e.num)
    expectEqual("area of e.num as UserShape", shape.area(), 1.5 * 1.5)
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func optionImmediates(fixtures: Array<NativeJSValue>): String {
    let e = ext(fixtures, 0)
    let shown = { x: Extern<ArkTSRuntime> =>
        e.copy = x
        ArkTSRuntime.fromExtern<String>(ArkTSRuntime.global().String(e.copy))
    }
    firstFailure([
        expectEqual("Some(1.5)", shown(ArkTSRuntime.toExtern(Some(1.5))), "1.5"),
        expectEqual("None<Float64>", shown(ArkTSRuntime.toExtern(None<Float64>)), "undefined"),
        expectEqual("Some(true)", shown(ArkTSRuntime.toExtern(Some(true))), "true"),
        expectEqual("None<Bool>", shown(ArkTSRuntime.toExtern(None<Bool>)), "undefined"),
        expectEqual("None<String>", shown(ArkTSRuntime.toExtern(None<String>)), "undefined"),
        expectEqual("Some(text)", shown(ArkTSRuntime.toExtern(Some("h\u{e9}"))), "h\u{e9}"),
        expectEqual("Some(Int32)", shown(ArkTSRuntime.toExtern(Some(Int32(7)))), "7"),
        expectEqual("read back", ArkTSRuntime.fromExtern<?Float64>(ArkTSRuntime.toExtern(Some(2.5))), Some(2.5)),
        expectEqual("written Some(1.5)", { => e.copy = Some(1.5); ArkTSRuntime.fromExtern<?Float64>(e.copy) }(), Some(1.5)),
        expectEqual("written None<Float64>", { => e.copy = None<Float64>; ArkTSRuntime.fromExtern<String>(ArkTSRuntime.global().String(e.copy)) }(), "undefined"),
        expectEqual("written Some(text)", { => e.copy = Some("h\u{e9}"); ArkTSRuntime.fromExtern<String>(e.copy) }(), "h\u{e9}"),
        expectEqual("written None<String>", { => e.copy = None<String>; ArkTSRuntime.fromExtern<String>(ArkTSRuntime.global().String(e.copy)) }(), "undefined"),
        expectEqual("argument Some(true)", ArkTSRuntime.fromExtern<String>(ArkTSRuntime.global().String(Some(true))), "true"),
        expectEqual("argument Some(text)", ArkTSRuntime.fromExtern<String>(ArkTSRuntime.global().String(Some("h\u{e9}"))), "h\u{e9}"),
        expectEqual("argument None<Bool>", ArkTSRuntime.fromExtern<String>(ArkTSRuntime.global().String(None<Bool>)), "undefined")
    ])
}
