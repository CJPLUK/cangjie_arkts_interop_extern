package arkts_runtime.tests

import arkts_runtime.*
import std.sync.*
import std.runtime.gc

@When[bundle == "com.example.testArkTSForeignRuntime"]
let callbackLifetimeMutex = Mutex()

@When[bundle == "com.example.testArkTSForeignRuntime"]
var callbackLifetimeCount: Int64 = 0

@When[bundle == "com.example.testArkTSForeignRuntime"]
var probeSession: ?NativeSession = None

@When[bundle == "com.example.testArkTSForeignRuntime"]
func step12Scenarios(): Array<(String, Scenario)> {
    [("step12.nativeBinding", { context, _ =>
        let native = NativeContext(context.getNapiEnv())
        let session = native.session
        probeSession = session
        let retained = session.newScope {
            let object = native.object()
            object.setProperty(native.string("answer"), native.number(42.0))
            NativeReference(object)
        }
        session.newScope {
            let object = retained.toJSValue()
            let callback = native.function { _, args => native.number(args[0].toNumber() + 1.0) }
            let result = callback.call([native.number(41.0)], thisArg: native.undefined())
            firstFailure([
                expectEqual("bound native thread", session.isInBindThread(), true),
                expectEqual("retained property", object.getProperty(native.string("answer")).toNumber(), 42.0),
                expectEqual("native callback result", result.toNumber(), 42.0),
                expectEqual("native string round trip", native.string("héllo 🦀").toString(), "héllo 🦀")
            ])
        }
    }),
    ("step12.immediateLifetime", { context, _ =>
        let inputs = [context.undefined(), context.null(), context.boolean(true), context.boolean(false),
            context.number(-0.0), context.number(Float64.NaN), context.number(Float64.Inf), context.number(-Float64.Inf)]
        let copied = context.newScope {
            let array = context.array(inputs)
            Array<NativeJSValue>(inputs.size) { i => array.getElement(UInt32(i)) }
        }
        // Overwrite local handle slots, then materialize both created and read values
        // into a fresh scope. No primitive may depend on the scope that produced it.
        for (_ in 0..100) { context.newScope { context.object() } }
        gc(heavy: true)
        context.newScope {
            let array = context.array(copied)
            firstFailure([
                expectEqual("undefined after scope", array.getElement(UInt32(0)).isUndefined(), true),
                expectEqual("null after scope", array.getElement(UInt32(1)).isNull(), true),
                expectEqual("true after scope", array.getElement(UInt32(2)).toBoolean(), true),
                expectEqual("false after scope", array.getElement(UInt32(3)).toBoolean(), false),
                expectEqual("negative zero after scope", 1.0 / array.getElement(UInt32(4)).toNumber(), -Float64.Inf),
                expectEqual("NaN after scope", array.getElement(UInt32(5)).toNumber().isNaN(), true),
                expectEqual("infinity after scope", array.getElement(UInt32(6)).toNumber(), Float64.Inf),
                expectEqual("negative infinity after scope", array.getElement(UInt32(7)).toNumber(), -Float64.Inf)
            ])
        }
    }),
    ("step12.scalarFromOtherThread", { _, _ =>
        let number = ArkTSRuntime.toExtern(42.0)
        let boolean = ArkTSRuntime.toExtern(true)
        // Keep the JS event loop blocked here. Pure copied-payload reads must
        // finish without posting a second task to that event loop.
        let reader = spawn {
            let offThread = !ArkTSRuntime.context.isInBindThread()
            (ArkTSRuntime.fromExtern<Float64>(number), ArkTSRuntime.fromExtern<Int32>(number),
                ArkTSRuntime.fromExtern<Bool>(boolean), offThread)
        }
        let result = reader.get(Duration.second * 2)
        firstFailure([
            expectEqual("off-thread copied number", result[0], 42.0),
            expectEqual("off-thread copied integer", result[1], 42),
            expectEqual("off-thread copied boolean", result[2], true),
            expectEqual("reader uses a different native thread", result[3], true)
        ])
    }),
    ("step12.stringBoundaries", { context, _ =>
        let samples = ["", String.fromUtf8([UInt8(97), UInt8(0), UInt8(98)]),
            String(Array<Rune>(64, repeat: r'a')), String(Array<Rune>(65, repeat: r'a')),
            String(Array<Rune>(64, repeat: r'é')), String(Array<Rune>(65, repeat: r'é')),
            String(Array<Rune>(64, repeat: r'漢')), String(Array<Rune>(65, repeat: r'漢')),
            String(Array<Rune>(32, repeat: r'😀')), String(Array<Rune>(33, repeat: r'😀')),
            String(Array<Rune>(128, repeat: r'a')), String(Array<Rune>(129, repeat: r'a')),
            String(Array<Rune>(128, repeat: r'漢')), String(Array<Rune>(129, repeat: r'漢')),
            String(Array<Rune>(64, repeat: r'😀')), String(Array<Rune>(65, repeat: r'😀'))]
        let textResult = firstFailure(samples.map { text =>
            expectEqual("string boundary ${text.size}", context.string(text).toString(), text)
        })
        let object = context.object()
        let names = ["", String.fromUtf8([UInt8(97), UInt8(0), UInt8(98)]), "é漢😀"]
        firstFailure([textResult, firstFailure(names.map { name =>
            object.setProperty(name, context.string(name))
            expectEqual("explicit-length property key", object.getProperty(name).toString(), name)
        })])
    }),
    ("step12.numberArrayRead", { context, fixtures =>
        let values = numberArrayWithGetter(context) { _ =>
            fixture(fixtures, 0).call([], thisArg: context.undefined())
            context.number(1.0)
        }
        let array = ArkTSRuntime.retain(values)
        let numbers = ArkTSRuntime.fromExtern<Array<Float64>>(array)
        let edge = ArkTSRuntime.fromExtern<Array<Float64>>(
            ArkTSRuntime.toExtern([-0.0, Float64.NaN, Float64.Inf, -Float64.Inf]))
        firstFailure([
            expectEqual("accessor numbers", numbers, [1.0, 2.0, 3.0]),
            expectEqual("numeric array negative zero", 1.0 / edge[0], -Float64.Inf),
            expectEqual("numeric array NaN", edge[1].isNaN(), true),
            expectEqual("numeric array infinity", edge[2], Float64.Inf),
            expectEqual("numeric array negative infinity", edge[3], -Float64.Inf)
        ])
    }),
    ("step12.numberArrayThrows", { context, _ =>
        let values = numberArrayWithGetter(context) { _ => throw Exception("numeric getter failed") }
        let array = ArkTSRuntime.retain(values)
        expectThrows<ForeignRuntimeException>("numeric array getter throw", "numeric getter failed",
            { => ArkTSRuntime.fromExtern<Array<Float64>>(array) })
    }),
    ("step12.numberArrayShrinks", { context, _ =>
        let values = numberArrayWithGetter(context) { array =>
            array.setProperty("length", context.number(1.0))
            context.number(1.0)
        }
        let array = ArkTSRuntime.retain(values)
        expectThrows<ArkTSNativeException>("numeric array getter shrink", "allowed: [0, 1), given: 1",
            { => ArkTSRuntime.fromExtern<Array<Float64>>(array) })
    }),
    ("step12.numberArraySnapshot", { context, _ =>
        let numbers = Array<Float64>(2000) { i => Float64(i) }
        let prototype = context.global.getProperty("Array").getProperty("prototype")
        if (prototype.hasProperty("1024")) { return "Array.prototype[1024] already exists" }
        let descriptor = context.object()
        descriptor.setProperty("configurable", context.boolean(true))
        descriptor.setProperty("set", context.function { _, _ =>
            numbers[1025] = -1.0
            gc(heavy: true)
            context.undefined()
        })
        let object = context.global.getProperty("Object")
        object.getProperty("defineProperty").call([prototype, context.string("1024"), descriptor], thisArg: object)
        try {
            let converted = ArkTSRuntime.toExtern(numbers)
            firstFailure([
                expectEqual("setter executed", numbers[1025], -1.0),
                expectEqual("conversion snapshots before setters", ArkTSRuntime.fromExtern<Float64>(converted[1025]), 1025.0)
            ])
        } finally {
            let reflect = context.global.getProperty("Reflect")
            reflect.getProperty("deleteProperty").call([prototype, context.string("1024")], thisArg: reflect)
        }
    }),
    ("step12.callbackLifetimeCreate", { context, fixtures =>
        let token = CallbackLifetimeToken()
        let callback = context.function { ctx, args => ctx.number(args[0].toNumber() + Float64(token.next())) }
        fixture(fixtures, 0).setProperty("callback", callback)
        ""
    }),
    ("step12.callbackLifetimeCount", { _, _ =>
        gc(heavy: true)
        synchronized(callbackLifetimeMutex) { callbackLifetimeCount.toString() }
    })]
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func step12OffThreadScenarios(): Array<(String, OffThreadScenario)> {
    [("step12.nativeDispatch", { =>
        let session = probeSession.getOrThrow()
        let mutex = Mutex()
        let done: Condition
        synchronized(mutex) { done = mutex.condition() }
        let completed = Box(false)
        let result = Box("callback did not run")
        session.post { cancelled =>
            let report = if (cancelled) { "native task cancelled" } else {
                session.newScope { expectEqual("native callback thread", session.isInBindThread(), true) }
            }
            synchronized(mutex) {
                result.value = report
                completed.value = true
                done.notify()
            }
        }
        synchronized(mutex) {
            done.waitUntil({ => completed.value })
            result.value
        }
    })]
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
class CallbackLifetimeToken {
    var value: Int64 = 0
    func next(): Int64 { value++; value }
    ~init() { synchronized(callbackLifetimeMutex) { callbackLifetimeCount++ } }
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func numberArrayWithGetter(context: NativeContext, body: (NativeJSValue) -> NativeJSValue): NativeJSValue {
    let array = context.array([context.number(0.0), context.number(2.0), context.number(3.0)])
    let descriptor = context.object()
    descriptor.setProperty("get", context.function { _, _ => body(array) })
    let object = context.global.getProperty("Object")
    object.getProperty("defineProperty").call([array, context.string("0"), descriptor], thisArg: object)
    array
}
