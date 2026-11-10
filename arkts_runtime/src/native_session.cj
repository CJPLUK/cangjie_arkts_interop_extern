package arkts_runtime

import std.collection.HashMap
import std.sync.Mutex
import std.sync.SyncCounter

foreign func ar_bind(env: NativeEnv, callback: CFunc<(Int64, Int32) -> Unit>): CPointer<Unit>
@FastNative
foreign func ar_release_state(state: CPointer<Unit>): Unit
@FastNative
foreign func ar_is_owner(state: CPointer<Unit>): Int32
@FastNative
foreign func ar_alive(state: CPointer<Unit>): Int32
@FastNative
foreign func ar_access_status(state: CPointer<Unit>): Int32
// Nonblocking queue insertion only; callbacks execute later, outside native queue locks.
@FastNative
foreign func ar_post(state: CPointer<Unit>, id: Int64): Int32
@FastNative
foreign func ar_open_scope(state: CPointer<Unit>, scope: CPointer<CPointer<Unit>>): Int32
@FastNative
foreign func ar_close_scope(state: CPointer<Unit>, scope: CPointer<Unit>): Int32
@FastNative
foreign func ar_create_reference(state: CPointer<Unit>, value: NapiValue, reference: CPointer<CPointer<Unit>>): Int32
@FastNative
foreign func ar_reference_value(state: CPointer<Unit>, reference: CPointer<Unit>, value: CPointer<NapiValue>): Int32
// Queue draining and compatibility boxing stay on ordinary FFI transitions.
foreign func ar_drain_references(state: CPointer<Unit>): Unit
foreign func ar_create_boxed_reference(state: CPointer<Unit>, value: NapiValue, reference: CPointer<CPointer<Unit>>): Int32
foreign func ar_boxed_reference_value(state: CPointer<Unit>, reference: CPointer<Unit>, value: CPointer<NapiValue>): Int32
// Only queues deletion (or frees dead-session bookkeeping); never invokes callbacks.
@FastNative
foreign func ar_release_reference(state: CPointer<Unit>, reference: CPointer<Unit>): Unit

private let taskMutex = Mutex()
private let nativeTasks = HashMap<Int64, (Bool) -> Unit>()
private var nextNativeTask: Int64 = 0

@C
func executeNativeTask(id: Int64, cancelled: Int32): Unit {
    let task = synchronized(taskMutex) { nativeTasks.remove(id) }
    if (let Some(callback) <- task) {
        // Tasks must carry their result or failure back to the waiting caller themselves.
        // No Cangjie exception may escape this C callback.
        try { callback(cancelled != 0) } catch (_: Exception) {} catch (_: Error) {}
    }
}

private enum NativeResult<R> {
    | Ok(R)
    | Err(Exception)
    | Failed(Error)
}

/** Owns dispatch and lifecycle bookkeeping for a borrowed environment; used only through ArkTSRuntime. */
class NativeSession {
    private let environment: NativeEnv
    let state: CPointer<Unit>

    init(env: NativeEnv) {
        if (env.isNull()) { throw IllegalArgumentException("ArkTS environment is null") }
        environment = env
        state = unsafe { ar_bind(env, executeNativeTask) }
        if (state.isNull()) { throw ForeignRuntimeException("Cannot initialize ArkTS dispatch queue") }
    }

    ~init() { unsafe { ar_release_state(state) } }

    prop env: NativeEnv {
        get() {
            // One leaf call checks the tombstone and native OS thread together.
            let status = unsafe { ar_access_status(state) }
            if (status == 1) { throw ForeignRuntimeException("ArkTS environment has been destroyed") }
            if (status != 0) { throw ForeignRuntimeException("Thread mismatch") }
            environment
        }
    }
    func isInBindThread(): Bool { unsafe { ar_is_owner(state) != 0 } }
    func checkAlive(): Unit {
        if (unsafe { ar_alive(state) == 0 }) { throw ForeignRuntimeException("ArkTS environment has been destroyed") }
    }

    func newScope<R>(operation: () -> R): R {
        var scope = CPointer<Unit>()
        let status = unsafe { ar_open_scope(state, inout scope) }
        if (status != 0 && status != AR_SCOPE_NEEDS_DRAIN) {
            checkAlive()
            throw ForeignRuntimeException("Cannot open ArkTS handle scope: ${status}")
        }
        try {
            if (status == AR_SCOPE_NEEDS_DRAIN) { unsafe { ar_drain_references(state) } }
            operation()
        } finally { unsafe { ar_close_scope(state, scope) } }
    }

    func run<R>(operation: () -> R): R {
        if (isInBindThread()) { return newScope(operation) }
        let result = Box(None<NativeResult<R>>)
        // One writer, one reader. The counter publishes the result and wakes the
        // caller without a condition-variable mutex handoff/reacquisition.
        let done = SyncCounter(1)
        post { cancelled =>
            let completed = try {
                if (cancelled) { throw ForeignRuntimeException("ArkTS environment has been destroyed") }
                NativeResult.Ok(newScope(operation))
            } catch (e: Exception) {
                NativeResult<R>.Err(e)
            } catch (e: Error) {
                NativeResult<R>.Failed(e)
            }
            result.value = Some(completed)
            done.dec()
        }
        // SyncCounter guarantees that writes before dec() happen-before reads
        // following waitUntilZero(), including cancellation and error results.
        done.waitUntilZero()
        match (result.value.getOrThrow()) {
            case Ok(value) => value
            case Err(error) => throw error
            case Failed(error) => throw error
        }
    }

    func post(operation: (Bool) -> Unit): Unit {
        checkAlive()
        let id = synchronized(taskMutex) {
            nextNativeTask++
            nativeTasks.add(nextNativeTask, operation)
            nextNativeTask
        }
        let status = unsafe { ar_post(state, id) }
        if (status != 0) {
            synchronized(taskMutex) { nativeTasks.remove(id) }
            throw ForeignRuntimeException("Cannot post ArkTS task: ${status}")
        }
    }
}
