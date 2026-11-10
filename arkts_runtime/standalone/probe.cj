package arkts_runtime.native_probe
import arkts_runtime.*
import std.runtime.gc
import std.sync.Mutex
import std.sync.AtomicBool

@C
public func arktsStandaloneProbe(env: CPointer<Unit>): Int32 {
    try {
        if (ArkTSRuntime.isBound()) { return 10 }
        try { ArkTSRuntime.undefined(); return 11 } catch (_: ArkTSContextNotBoundException) {}
        try { ArkTSRuntime.bind(CPointer<Unit>()); return 12 } catch (_: IllegalArgumentException) {}
        if (ArkTSRuntime.isBound()) { return 13 }
        ArkTSRuntime.bind(env)
        let object = ArkTSRuntime.object()
        object.answer = 41.0
        let callback = ArkTSRuntime.function { args =>
            ArkTSRuntime.toExtern(ArkTSRuntime.fromExtern<Float64>(args[0]) + 1.0)
        }
        object.increment = callback
        if (ArkTSRuntime.fromExtern<Float64>(object.increment(object.answer)) != 42.0) { return 1 }
        if (ArkTSRuntime.fromExtern<String>(ArkTSRuntime.toExtern("héllo 🦀")) != "héllo 🦀") { return 2 }
        0
    } catch (_: Exception) { 3 }
}

let workerProbeMutex = Mutex()

var workerSession: ?NativeSession = None
var workerReference: ?NativeReference = None
let workerCancelled = AtomicBool(false)
let workerWaitingReleased = AtomicBool(false)

@C
public func arktsStandaloneWorkerBind(env: CPointer<Unit>): Int32 {
    try {
        let context = NativeContext(env)
        synchronized(workerProbeMutex) {
            workerSession = context.session
            workerReference = context.newScope { NativeReference(context.object()) }
            context.session.post { cancelled => if (cancelled) { workerCancelled.store(true) } }
            spawn {
                try { context.session.run { context.object() } }
                catch (_: ForeignRuntimeException) { workerWaitingReleased.store(true) }
            }
        }
        0
    } catch (_: Exception) { 1 }
}

@C
public func arktsStandaloneWorkerAfterShutdown(): Int32 {
    let sessionToCheck = synchronized(workerProbeMutex) { workerSession }
    if (let Some(session) <- sessionToCheck) {
        try { session.checkAlive(); return 1 } catch (_: ForeignRuntimeException) {}
        try { session.post { _ => () }; return 2 } catch (_: ForeignRuntimeException) {}
        if (let Some(reference) <- workerReference) {
            try { reference.toJSValue(); return 3 } catch (_: ForeignRuntimeException) {}
        }
        if (!workerCancelled.load()) { return 5 }
        if (!workerWaitingReleased.load()) { return 6 }
        synchronized(workerProbeMutex) { workerReference = None }
        gc(heavy: true)
        return 0
    }
    4
}
