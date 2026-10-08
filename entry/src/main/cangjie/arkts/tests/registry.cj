package ohos_app_cangjie_entry.arkts.tests

import std.collection.*
import ohos.ark_interop.*

/**
 * A device test scenario. Receives the ArkTS fixtures passed after the scenario name and
 * returns "" on success or a failure message.
 */
public type Scenario = (JSContext, Array<JSValue>) -> String

func allScenarios(): Array<(String, Scenario)> {
    concat([step0Scenarios(), step1Scenarios(), step2Scenarios()])
}

func concat(groups: Array<Array<(String, Scenario)>>): Array<(String, Scenario)> {
    let all = ArrayList<(String, Scenario)>()
    for (group in groups) {
        all.add(all: group)
    }
    all.toArray()
}

public func scenarioNames(): Array<String> {
    allScenarios().map({ entry => entry[0] })
}

/** Runs the scenario called `name`. Exceptions become failure messages. */
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

/** Returns "" when `actual == expected`, otherwise a message naming `what`. */
func expectEqual<T>(what: String, actual: T, expected: T): String where T <: Equatable<T> & ToString {
    if (actual == expected) { "" } else { "${what}: expected ${expected}, got ${actual}" }
}

/**
 * Returns "" when `block` throws an `E` whose `toString()` contains `fragment`, otherwise a
 * message naming `what` and what happened instead.
 */
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
func firstFailure(results: Array<String>): String {
    for (r in results) {
        if (!r.isEmpty()) { return r }
    }
    ""
}

func fixture(fixtures: Array<JSValue>, index: Int64): JSValue {
    if (index >= fixtures.size) {
        throw IllegalArgumentException("scenario expects fixture #${index}, got ${fixtures.size} fixtures")
    }
    fixtures[index]
}
