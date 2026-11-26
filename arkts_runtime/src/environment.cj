package arkts_runtime

import std.collection.HashMap
import std.sync.Mutex
import std.sync.SyncCounter

foreign func ats_rt_ext_bind(env: NapiEnv, callback: CFunc<(Int64, Int32) -> Unit>): NativeState
@FastNative
foreign func ats_rt_ext_release_state(state: NativeState): Unit
@FastNative
foreign func ats_rt_ext_is_owner(state: NativeState): Int32
@FastNative
foreign func ats_rt_ext_alive(state: NativeState): Int32
@FastNative
foreign func ats_rt_ext_access_status(state: NativeState): Int32
@FastNative
foreign func ats_rt_ext_post(state: NativeState, id: Int64): Int32
@FastNative
foreign func ats_rt_ext_open_scope(state: NativeState, scope: CPointer<NapiHandleScope>, flags: Int32): Int32
@FastNative
foreign func ats_rt_ext_close_scope(state: NativeState, scope: NapiHandleScope): Int32
foreign func ats_rt_ext_drain(state: NativeState): Unit
@FastNative
foreign func ats_rt_ext_pin(state: NativeState, value: NapiValue, pin: CPointer<NativePin>): Int32
@FastNative
foreign func ats_rt_ext_pin_value(state: NativeState, pin: NativePin, value: CPointer<NapiValue>): Int32
@FastNative
foreign func ats_rt_ext_unpin(pin: NativePin): Unit

private let taskMutex = Mutex()
private let nativeTasks = HashMap<Int64, (Bool) -> Unit>()
private var nextNativeTask: Int64 = 0

@C
func ats_rt_ext_executeNativeTask(id: Int64, cancelled: Int32): Unit {
    let task = synchronized(taskMutex) { nativeTasks.remove(id) }
    if (let Some(selfReportingTask) <- task) {
        discardEverythingThrownAtCBoundary { selfReportingTask(cancelled != 0) }
    }
}

private func discardEverythingThrownAtCBoundary(body: () -> Unit): Unit {
    try { body() } catch (_: Exception) {} catch (_: Error) {}
}

private enum NativeResult<R> {
    | Ok(R)
    | Err(Exception)
    | Failed(Error)
}

private class PostedOutcome<R> {
    private var outcome: ?NativeResult<R> = None
    private let done = SyncCounter(1)

    func complete(result: NativeResult<R>): Unit {
        outcome = Some(result)
        done.dec()
    }

    func waitForCompletion(): NativeResult<R> {
        done.waitUntilZero()
        outcome.getOrThrow()
    }
}

class Environment {
    private let raw: NapiEnv
    let state: NativeState
    private let pinCache = PinCache()

    init(env: NapiEnv) {
        if (env.isNull()) { throw IllegalArgumentException("ArkTS environment is null") }
        if (let Some(mismatched) <- nativeLayoutMismatch()) {
            throw ForeignRuntimeException("${mismatched} does not match its C struct in native/backend.h")
        }
        raw = env
        state = unsafe { ats_rt_ext_bind(env, ats_rt_ext_executeNativeTask) }
        if (state.isNull()) { throw ForeignRuntimeException("Cannot initialize ArkTS dispatch queue") }
    }

    ~init() { unsafe { ats_rt_ext_release_state(state) } }

    prop env: NapiEnv {
        get() {
            let status = unsafe { ats_rt_ext_access_status(state) }
            if (status == AR_ACCESS_DEAD) { throw ForeignRuntimeException("ArkTS environment has been destroyed") }
            if (status != AR_ACCESS_OK) { throw ForeignRuntimeException("Thread mismatch") }
            raw
        }
    }
    func isOnOwnerThread(): Bool { unsafe { ats_rt_ext_is_owner(state) != 0 } }
    func pinCacheIfOwnerThread(): ?PinCache { if (isOnOwnerThread()) { pinCache } else { None } }
    func checkAlive(): Unit {
        if (unsafe { ats_rt_ext_alive(state) == 0 }) { throw ForeignRuntimeException("ArkTS environment has been destroyed") }
    }

    func runtimeFrame<R>(operation: () -> R): R { inFrame(AR_SCOPE_IN_FLIGHT, operation) }

    func userFrame<R>(operation: () -> R): R { inFrame(0, operation) }

    private func inFrame<R>(flags: Int32, operation: () -> R): R {
        let scope = frameOpen(flags)
        try { operation() } finally { unsafe { ats_rt_ext_close_scope(state, scope) } }
    }

    private func frameOpen(flags: Int32): NapiHandleScope {
        var scope = NapiHandleScope()
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

    func runPosted<R>(operation: () -> R): R {
        let outcome = PostedOutcome<R>()
        post { cancelled =>
            let completed = try {
                if (cancelled) { throw ForeignRuntimeException("ArkTS environment has been destroyed") }
                NativeResult.Ok(runtimeFrame(operation))
            } catch (e: Exception) {
                NativeResult<R>.Err(e)
            } catch (e: Error) {
                NativeResult<R>.Failed(e)
            }
            outcome.complete(completed)
        }
        match (outcome.waitForCompletion()) {
            case Ok(value) => value
            case Err(error) => throw error
            case Failed(error) => throw error
        }
    }

    func post(selfReportingTask: (Bool) -> Unit): Unit {
        checkAlive()
        let id = synchronized(taskMutex) {
            nextNativeTask++
            nativeTasks.add(nextNativeTask, selfReportingTask)
            nextNativeTask
        }
        let status = unsafe { ats_rt_ext_post(state, id) }
        if (status != 0) {
            synchronized(taskMutex) { nativeTasks.remove(id) }
            throw ForeignRuntimeException("Cannot post ArkTS task: ${status}")
        }
    }
}
