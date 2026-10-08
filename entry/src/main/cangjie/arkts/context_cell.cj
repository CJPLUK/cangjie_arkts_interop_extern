package ohos_app_cangjie_entry.arkts

import std.sync.*

/**
 * Holds the context a runtime is bound to. The first `bind` installs it, from any thread;
 * every later `bind` throws, so the value never changes once installed.
 *
 * Generic so that tests can exercise it with stand-in values on fresh instances, while
 * `ArkTSRuntime` uses a single process-wide `ContextCell<JSContext>`.
 */
class ContextCell<T> where T <: Object {
    private let cell = AtomicOptionReference<T>()

    func bind(value: T): Unit {
        if (!cell.compareAndSwap(None, value)) {
            throw ArkTSContextAlreadyBoundException("ArkTS runtime is already associated with a host JSContext")
        }
    }

    func isBound(): Bool {
        cell.load().isSome()
    }

    func get(): T {
        match (cell.load()) {
            case Some(value) => value
            case None => throw ArkTSContextNotBoundException("ArkTS runtime is not associated with a host JSContext")
        }
    }
}
