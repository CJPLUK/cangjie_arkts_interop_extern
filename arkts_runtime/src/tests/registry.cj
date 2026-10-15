package arkts_runtime.tests

import std.collection.*
import ohos.ark_interop.*

// Every top-level declaration in this package carries the `@When` below, so the package is
// empty unless the library is built by testapp (bundle com.example.testArkTSForeignRuntime).

/**
 * A device test scenario. Receives the ArkTS fixtures passed after the scenario name and
 * returns "" on success or a failure message.
 */
@When[bundle == "com.example.testArkTSForeignRuntime"]
public type Scenario = (JSContext, Array<JSValue>) -> String

@When[bundle == "com.example.testArkTSForeignRuntime"]
func allScenarios(): Array<(String, Scenario)> {
    concat([step0Scenarios(), step1Scenarios(), step2Scenarios(), step3Scenarios(), step4Scenarios(), step5Scenarios(),
        step6Scenarios(), step7Scenarios(), step8Scenarios(), step9Scenarios(), step10Scenarios()])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func concat<T>(groups: Array<Array<T>>): Array<T> {
    let all = ArrayList<T>()
    for (group in groups) {
        all.add(all: group)
    }
    all.toArray()
}

/**
 * A device test scenario whose body runs on a spawned Cangjie thread, so the JS thread stays
 * free to serve `run`. Returns "" on success or a failure message.
 */
@When[bundle == "com.example.testArkTSForeignRuntime"]
public type OffThreadScenario = () -> String

@When[bundle == "com.example.testArkTSForeignRuntime"]
func allOffThreadScenarios(): Array<(String, OffThreadScenario)> {
    concat([step3OffThreadScenarios(), step4OffThreadScenarios(), step5OffThreadScenarios(), step6OffThreadScenarios(), step7OffThreadScenarios(),
        step8OffThreadScenarios(), step9OffThreadScenarios(), step10OffThreadScenarios()])
}

/** Names of all scenarios: those run on the JS thread first, then the off-thread ones. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
public func scenarioNames(): Array<String> {
    let names = ArrayList<String>(allScenarios().map({ entry => entry[0] }))
    names.add(all: allOffThreadScenarios().map({ entry => entry[0] }))
    names.toArray()
}

/** Runs the scenario called `name`. Exceptions become failure messages. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
public func runScenario(context: JSContext, name: String, fixtures: Array<JSValue>): String {
    for ((scenarioName, scenario) in allScenarios()) {
        if (scenarioName == name) {
            return try {
                scenario(context, fixtures)
            } catch (e: Exception) {
                "unexpected exception ${e}"
            }
        }
    }
    "unknown scenario '${name}'"
}

/**
 * Runs the off-thread scenario called `name` on the calling thread, which must not be the JS
 * thread. Exceptions become failure messages.
 */
@When[bundle == "com.example.testArkTSForeignRuntime"]
public func runOffThreadScenario(name: String): String {
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

/** Returns "" when `actual == expected`, otherwise a message naming `what`. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func expectEqual<T>(what: String, actual: T, expected: T): String where T <: Equatable<T> & ToString {
    if (actual == expected) { "" } else { "${what}: expected ${expected}, got ${actual}" }
}

/**
 * Returns "" when `block` throws an `E` whose `toString()` contains `fragment`, otherwise a
 * message naming `what` and what happened instead.
 */
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

/** Returns the first failure message, or "" if all checks passed. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func firstFailure(results: Array<String>): String {
    for (r in results) {
        if (!r.isEmpty()) { return r }
    }
    ""
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func fixture(fixtures: Array<JSValue>, index: Int64): JSValue {
    if (index >= fixtures.size) {
        throw IllegalArgumentException("scenario expects fixture #${index}, got ${fixtures.size} fixtures")
    }
    fixtures[index]
}
