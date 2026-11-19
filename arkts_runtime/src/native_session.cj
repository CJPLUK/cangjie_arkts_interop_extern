package arkts_runtime

import std.collection.HashMap
import std.sync.Mutex
import std.sync.SyncCounter

foreign func ats_rt_ext_bind(env: NativeEnv, callback: CFunc<(Int64, Int32) -> Unit>): CPointer<Unit>
@FastNative
foreign func ats_rt_ext_release_state(state: CPointer<Unit>): Unit
@FastNative
foreign func ats_rt_ext_is_owner(state: CPointer<Unit>): Int32
@FastNative
foreign func ats_rt_ext_alive(state: CPointer<Unit>): Int32
@FastNative
foreign func ats_rt_ext_access_status(state: CPointer<Unit>): Int32
// Nonblocking queue insertion only; callbacks execute later, outside native queue locks.
@FastNative
foreign func ats_rt_ext_post(state: CPointer<Unit>, id: Int64): Int32
@FastNative
foreign func ats_rt_ext_open_scope(state: CPointer<Unit>, scope: CPointer<CPointer<Unit>>, flags: Int32): Int32
@FastNative
foreign func ats_rt_ext_close_scope(state: CPointer<Unit>, scope: CPointer<Unit>): Int32
// Deleting references stays on an ordinary FFI transition: unbounded work.
foreign func ats_rt_ext_drain(state: CPointer<Unit>): Unit
@FastNative
foreign func ats_rt_ext_pin(state: CPointer<Unit>, value: NapiValue, pin: CPointer<CPointer<Unit>>): Int32
@FastNative
foreign func ats_rt_ext_pin_value(state: CPointer<Unit>, pin: CPointer<Unit>, value: CPointer<NapiValue>): Int32
// Only queues deletion (or frees dead-session bookkeeping); never invokes callbacks.
@FastNative
foreign func ats_rt_ext_unpin(pin: CPointer<Unit>): Unit

private let taskMutex = Mutex()
private let nativeTasks = HashMap<Int64, (Bool) -> Unit>()
private var nextNativeTask: Int64 = 0

@C
func ats_rt_ext_executeNativeTask(id: Int64, cancelled: Int32): Unit {
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
    let intern = InternTable()

    init(env: NativeEnv) {
        if (env.isNull()) { throw IllegalArgumentException("ArkTS environment is null") }
        environment = env
        state = unsafe { ats_rt_ext_bind(env, ats_rt_ext_executeNativeTask) }
        if (state.isNull()) { throw ForeignRuntimeException("Cannot initialize ArkTS dispatch queue") }
    }

    ~init() { unsafe { ats_rt_ext_release_state(state) } }

    prop env: NativeEnv {
        get() {
            // One leaf call checks the tombstone and native OS thread together.
            let status = unsafe { ats_rt_ext_access_status(state) }
            if (status == 1) { throw ForeignRuntimeException("ArkTS environment has been destroyed") }
            if (status != 0) { throw ForeignRuntimeException("Thread mismatch") }
            environment
        }
    }
    func isInBindThread(): Bool { unsafe { ats_rt_ext_is_owner(state) != 0 } }
    func checkAlive(): Unit {
        if (unsafe { ats_rt_ext_alive(state) == 0 }) { throw ForeignRuntimeException("ArkTS environment has been destroyed") }
    }

    /** A generic bracket: holds napi_values, so pins are not deleted until it closes. */
    func scopeOpen(): CPointer<Unit> { bracketOpen(AR_SCOPE_IN_FLIGHT) }

    /** `ArkTSRuntime.newScope`'s bracket: holds no napi_value, pins may drain inside it. */
    func userScopeOpen(): CPointer<Unit> { bracketOpen(0) }

    private func bracketOpen(flags: Int32): CPointer<Unit> {
        var scope = CPointer<Unit>()
        var status = unsafe { ats_rt_ext_open_scope(state, inout scope, flags | AR_SCOPE_DRAIN_CHECK) }
        if (status == AR_DRAIN_FIRST) {
            unsafe { ats_rt_ext_drain(state) }
            status = unsafe { ats_rt_ext_open_scope(state, inout scope, flags) }
        }
        if (status != 0) {
            checkAlive()
            throw ForeignRuntimeException("Cannot open ArkTS handle scope: ${status}")
        }
        scope
    }

    func scopeClose(scope: CPointer<Unit>): Unit { unsafe { ats_rt_ext_close_scope(state, scope) } }

    func newScope<R>(operation: () -> R): R {
        let scope = scopeOpen()
        try { operation() } finally { scopeClose(scope) }
    }

    func run<R>(operation: () -> R): R {
        if (isInBindThread()) { return newScope(operation) }
        runPosted(operation)
    }

    func runPosted<R>(operation: () -> R): R {
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
        let status = unsafe { ats_rt_ext_post(state, id) }
        if (status != 0) {
            synchronized(taskMutex) { nativeTasks.remove(id) }
            throw ForeignRuntimeException("Cannot post ArkTS task: ${status}")
        }
    }
}
