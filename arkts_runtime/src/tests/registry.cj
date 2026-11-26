package arkts_runtime.tests

import std.collection.*
import arkts_runtime.*

@When[bundle == "com.example.testArkTSForeignRuntime"]
public type FailureMessage = String

@When[bundle == "com.example.testArkTSForeignRuntime"]
type Scenario = (JS, Array<NativeJSValue>) -> FailureMessage

@When[bundle == "com.example.testArkTSForeignRuntime"]
func allScenarios(): Array<(String, Scenario)> {
    concat([step0Scenarios(), step1Scenarios(), step2Scenarios(), step3Scenarios(), step4Scenarios(), step5Scenarios(),
        step6Scenarios(), step7Scenarios(), step8Scenarios(), step9Scenarios(), step10Scenarios(), step12Scenarios()])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func concat<T>(groups: Array<Array<T>>): Array<T> {
    let all = ArrayList<T>()
    for (group in groups) {
        all.add(all: group)
    }
    all.toArray()
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
public type OffThreadScenario = () -> FailureMessage

@When[bundle == "com.example.testArkTSForeignRuntime"]
func allOffThreadScenarios(): Array<(String, OffThreadScenario)> {
    concat([step3OffThreadScenarios(), step4OffThreadScenarios(), step5OffThreadScenarios(), step6OffThreadScenarios(), step7OffThreadScenarios(),
        step8OffThreadScenarios(), step9OffThreadScenarios(), step10OffThreadScenarios(), step12OffThreadScenarios()])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
public func scenarioNames(): Array<String> {
    let names = ArrayList<String>(allScenarios().map({ entry => entry[0] }))
    names.add(all: allOffThreadScenarios().map({ entry => entry[0] }))
    names.toArray()
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func runScenario(js: JS, name: String, fixtures: Array<NativeJSValue>): FailureMessage {
    for ((scenarioName, scenario) in concat([allScenarios(), lifetimeScenarios()])) {
        if (scenarioName == name) {
            return try {
                scenario(js, fixtures)
            } catch (e: Exception) {
                "unexpected exception ${e}"
            }
        }
    }
    "unknown scenario '${name}'"
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
public func runOffThreadScenario(name: String): FailureMessage {
    for ((scenarioName, scenario) in allOffThreadScenarios()) {
        if (scenarioName == name) {
            return try {
                scenario()
            } catch (e: Exception) {
                "unexpected exception ${e}"
            }
        }
    }
    "unknown scenario '${name}'"
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func expectEqual<T>(what: String, actual: T, expected: T): String where T <: Equatable<T> & ToString {
    if (actual == expected) { "" } else { "${what}: expected ${expected}, got ${actual}" }
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func expectThrows<E>(what: String, fragment: String, block: () -> Any): String where E <: Exception {
    try {
        let result = block()
        "${what}: expected an exception, returned ${(result as ToString)?.toString() ?? "a value"}"
    } catch (e: Exception) {
        match (e) {
            case _: E where e.toString().contains(fragment) => ""
            case _: E => "${what}: expected '${fragment}' in '${e}'"
            case _ => "${what}: wrong exception '${e}'"
        }
    }
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func firstFailure(results: Array<String>): String {
    for (r in results) {
        if (!r.isEmpty()) { return r }
    }
    ""
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func fixture(fixtures: Array<NativeJSValue>, index: Int64): NativeJSValue {
    if (index >= fixtures.size) {
        throw IllegalArgumentException("scenario expects fixture #${index}, got ${fixtures.size} fixtures")
    }
    fixtures[index]
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
public func runNativeScenario(env: CPointer<Unit>, name: String): FailureMessage {
    let js = ArkTSRuntime.js
    if (ArkTSRuntime.environment.env.toUIntNative() != env.toUIntNative()) {
        return "Runtime is bound to a different host environment"
    }
    let fixtures = js.global.getProperty("__arkts_test_fixtures")
    runScenario(js, name, Array<NativeJSValue>(fixtures.size) { i => fixtures[i] })
}
