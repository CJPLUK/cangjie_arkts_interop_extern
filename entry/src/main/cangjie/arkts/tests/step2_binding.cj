package ohos_app_cangjie_entry.arkts.tests

import std.collection.*
import std.sync.*
import ohos.ark_interop.*
import ohos_app_cangjie_entry.arkts.*

func step2Scenarios(): Array<(String, Scenario)> {
    [
        ("step2.freshCellIsUnbound", { _, _ => freshCellIsUnbound() }),
        ("step2.firstBindInstalls", { _, _ => firstBindInstalls() }),
        ("step2.rebindSameValueThrows", { _, _ => rebindSameValueThrows() }),
        ("step2.rebindDifferentValueThrows", { _, _ => rebindDifferentValueThrows() }),
        ("step2.concurrentBindExactlyOneWins", { _, _ => concurrentBindExactlyOneWins() }),
        ("step2.concurrentReadersSeeNothingOrWinner", { _, _ => concurrentReadersSeeNothingOrWinner() }),
        ("step2.runtimeIsBound", { _, _ => runtimeIsBound() }),
        ("step2.runtimeBoundToCallerContext", runtimeBoundToCallerContext),
        ("step2.runtimeRebindThrows", runtimeRebindThrows)
    ]
}

/** Stand-in for a JSContext in tests of ContextCell. */
class Token {
    Token(let id: Int64) {}
}

const NOT_BOUND = "ArkTS runtime is not associated with a host JSContext"
const ALREADY_BOUND = "ArkTS runtime is already associated with a host JSContext"

func freshCellIsUnbound(): String {
    let cell = ContextCell<Token>()
    firstFailure([
        expectEqual("isBound", cell.isBound(), false),
        expectThrows<ArkTSContextNotBoundException>("get", NOT_BOUND, { => cell.get() })
    ])
}

func firstBindInstalls(): String {
    let cell = ContextCell<Token>()
    let token = Token(1)
    cell.bind(token)
    firstFailure([
        expectEqual("isBound", cell.isBound(), true),
        expectEqual("same object", refEq(cell.get(), token), true)
    ])
}

func rebindSameValueThrows(): String {
    let cell = ContextCell<Token>()
    let token = Token(1)
    cell.bind(token)
    firstFailure([
        expectThrows<ArkTSContextAlreadyBoundException>("second bind", ALREADY_BOUND, { => cell.bind(token) }),
        expectEqual("still bound", cell.isBound(), true),
        expectEqual("unchanged", refEq(cell.get(), token), true)
    ])
}

func rebindDifferentValueThrows(): String {
    let cell = ContextCell<Token>()
    let first = Token(1)
    cell.bind(first)
    firstFailure([
        expectThrows<ArkTSContextAlreadyBoundException>("second bind", ALREADY_BOUND, { => cell.bind(Token(2)) }),
        expectEqual("unchanged", refEq(cell.get(), first), true)
    ])
}

/** 8 threads released together call bind; repeated to make the race likely. */
func concurrentBindExactlyOneWins(): String {
    let threads = 8
    for (round in 0..200) {
        let cell = ContextCell<Token>()
        let barrier = Barrier(threads)
        let futures = ArrayList<Future<?Token>>()
        for (i in 0..threads) {
            futures.add(spawn {
                let token = Token(i)
                barrier.wait()
                try {
                    cell.bind(token)
                    Some(token)
                } catch (_: ArkTSContextAlreadyBoundException) {
                    None<Token>
                }
            })
        }
        let winners = ArrayList<Token>()
        for (f in futures) {
            if (let Some(token) <- f.get()) {
                winners.add(token)
            }
        }
        if (winners.size != 1) {
            return "round ${round}: ${winners.size} threads bound successfully"
        }
        if (!refEq(cell.get(), winners[0])) {
            return "round ${round}: installed value is not the winner's"
        }
    }
    ""
}

/** While one thread binds, readers see either "not bound" or the bound value, nothing else. */
func concurrentReadersSeeNothingOrWinner(): String {
    let readers = 4
    for (round in 0..100) {
        let cell = ContextCell<Token>()
        let token = Token(round)
        let barrier = Barrier(readers + 1)
        let futures = ArrayList<Future<String>>()
        for (_ in 0..readers) {
            futures.add(spawn {
                barrier.wait()
                for (_ in 0..1000) {
                    try {
                        if (!refEq(cell.get(), token)) {
                            return "read a value that was never bound"
                        }
                    } catch (_: ArkTSContextNotBoundException) {
                        if (cell.isBound() && !refEq(cell.get(), token)) {
                            return "isBound but wrong value"
                        }
                    }
                }
                ""
            })
        }
        barrier.wait()
        cell.bind(token)
        for (f in futures) {
            let failure = f.get()
            if (!failure.isEmpty()) {
                return "round ${round}: ${failure}"
            }
        }
    }
    ""
}

/** index.cj binds the runtime when the module is registered. */
func runtimeIsBound(): String {
    expectEqual("ArkTSRuntime.isBound()", ArkTSRuntime.isBound(), true)
}

/** The bound context is the engine this test is running in. */
func runtimeBoundToCallerContext(context: JSContext, _: Array<JSValue>): String {
    let bound = ArkTSRuntime.context
    firstFailure([
        expectEqual("same global object", bound.global.toJSValue().strictEqual(context.global.toJSValue()), true),
        expectEqual("on bind thread", bound.isInBindThread(), true)
    ])
}

func runtimeRebindThrows(context: JSContext, _: Array<JSValue>): String {
    let before = ArkTSRuntime.context
    firstFailure([
        expectThrows<ArkTSContextAlreadyBoundException>("bind again", ALREADY_BOUND,
            { => ArkTSRuntime.bind(context) }),
        expectEqual("still bound", ArkTSRuntime.isBound(), true),
        expectEqual("context unchanged", refEq(ArkTSRuntime.context, before), true)
    ])
}
