package arkts_runtime.tests

import arkts_runtime.*
import std.sync.*
import std.runtime.gc

@When[bundle == "com.example.testArkTSForeignRuntime"]
let callbackLifetimeMutex = Mutex()

@When[bundle == "com.example.testArkTSForeignRuntime"]
var callbackLifetimeCount: Int64 = 0

@When[bundle == "com.example.testArkTSForeignRuntime"]
var probeEnvironment: ?Environment = None

@When[bundle == "com.example.testArkTSForeignRuntime"]
func step12Scenarios(): Array<(String, Scenario)> {
    [("step12.nativeBinding", { js, _ =>
        let environment = Environment(ArkTSRuntime.environment.env)
        let native = JS(environment)
        probeEnvironment = environment
        let retained = environment.runtimeFrame {
            let object = native.object()
            object.setProperty(native.string("answer"), native.number(42.0))
            Pinned(object)
        }
        environment.runtimeFrame {
            let object = retained.toJSValue()
            let callback = native.function { _, args => native.number(args[0].toNumber() + 1.0) }
            let result = callback.call([native.number(41.0)], thisArg: native.undefined())
            firstFailure([
                expectEqual("bound native thread", environment.isOnOwnerThread(), true),
                expectEqual("retained property", object.getProperty(native.string("answer")).toNumber(), 42.0),
                expectEqual("native callback result", result.toNumber(), 42.0),
                expectEqual("native string round trip", native.string("héllo 🦀").toString(), "héllo 🦀")
            ])
        }
    }),
    ("step12.immediateLifetime", { js, _ =>
        let inputs = [js.undefined(), js.null(), js.boolean(true), js.boolean(false),
            js.number(-0.0), js.number(Float64.NaN), js.number(Float64.Inf), js.number(-Float64.Inf)]
        let copied = ArkTSRuntime.environment.runtimeFrame {
            let array = js.array(inputs)
            Array<NativeJSValue>(inputs.size) { i => array.getElement(UInt32(i)) }
        }
        // Overwrite local handle slots, then materialize both created and read values
        // into a fresh scope. No primitive may depend on the scope that produced it.
        for (_ in 0..100) { ArkTSRuntime.environment.runtimeFrame { js.object() } }
        gc(heavy: true)
        ArkTSRuntime.environment.runtimeFrame {
            let array = js.array(copied)
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
            let offThread = !ArkTSRuntime.environment.isOnOwnerThread()
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
    ("step12.stringBoundaries", { js, _ =>
        let samples = ["", String.fromUtf8([UInt8(97), UInt8(0), UInt8(98)]),
            String(Array<Rune>(64, repeat: r'a')), String(Array<Rune>(65, repeat: r'a')),
            String(Array<Rune>(64, repeat: r'é')), String(Array<Rune>(65, repeat: r'é')),
            String(Array<Rune>(64, repeat: r'漢')), String(Array<Rune>(65, repeat: r'漢')),
            String(Array<Rune>(32, repeat: r'😀')), String(Array<Rune>(33, repeat: r'😀')),
            String(Array<Rune>(128, repeat: r'a')), String(Array<Rune>(129, repeat: r'a')),
            String(Array<Rune>(128, repeat: r'漢')), String(Array<Rune>(129, repeat: r'漢')),
            String(Array<Rune>(64, repeat: r'😀')), String(Array<Rune>(65, repeat: r'😀'))]
        let textResult = firstFailure(samples.map { text =>
            expectEqual("string boundary ${text.size}", js.string(text).toString(), text)
        })
        let stringClass = js.global.getProperty("String")
        let lone = stringClass.getProperty("fromCharCode").call(
            [js.number(97.0), js.number(55296.0), js.number(98.0)], thisArg: stringClass)
        let loneLong = stringClass.getProperty("prototype").getProperty("repeat").call([js.number(50.0)], thisArg: lone)
        let loneBytes = lone.toString().toArray()
        let loneResult = firstFailure([
            expectEqual("lone surrogate keeps the engine's bytes, short", loneBytes, [97u8, 237, 160, 128, 98]),
            expectEqual("lone surrogate, long", loneLong.toString().toArray(),
                Array<UInt8>(loneBytes.size * 50) { i => loneBytes[i % loneBytes.size] })
        ])
        let object = js.object()
        let names = ["", String.fromUtf8([UInt8(97), UInt8(0), UInt8(98)]), "é漢😀"]
        firstFailure([textResult, loneResult, firstFailure(names.map { name =>
            object.setProperty(name, js.string(name))
            expectEqual("explicit-length property key", object.getProperty(name).toString(), name)
        })])
    }),
    ("step12.numberArrayRead", { js, fixtures =>
        let values = numberArrayWithGetter(js) { _ =>
            fixture(fixtures, 0).call([], thisArg: js.undefined())
            js.number(1.0)
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
    ("step12.numberArrayThrows", { js, _ =>
        let values = numberArrayWithGetter(js) { _ => throw Exception("numeric getter failed") }
        let array = ArkTSRuntime.retain(values)
        expectThrows<ForeignRuntimeException>("numeric array getter throw", "numeric getter failed",
            { => ArkTSRuntime.fromExtern<Array<Float64>>(array) })
    }),
    ("step12.numberArrayShrinks", { js, _ =>
        let values = numberArrayWithGetter(js) { array =>
            array.setProperty("length", js.number(1.0))
            js.number(1.0)
        }
        let array = ArkTSRuntime.retain(values)
        let shrinking = js.array([js.number(0.0), js.number(2.0), js.number(3.0)])
        let descriptor = js.object()
        descriptor.setProperty("configurable", js.boolean(true))
        descriptor.setProperty("get", js.function { _, _ =>
            shrinking.setProperty("length", js.number(1.0))
            js.undefined()
        })
        let object = js.global.getProperty("Object")
        object.getProperty("defineProperty").call([shrinking, js.string("2"), descriptor], thisArg: object)
        let element = ArkTSRuntime.indexedAccess(ArkTSRuntime.retain(shrinking), 2)
        firstFailure([
            expectThrows<ArkTSNativeException>("numeric array getter shrink", "allowed: [0, 1), given: 1",
                { => ArkTSRuntime.fromExtern<Array<Float64>>(array) }),
            expectEqual("element getter that shrinks the array reads undefined", ArkTSRuntime.isUndefined(element), true)
        ])
    }),
    ("step12.numberArraySnapshot", { js, _ =>
        let numbers = Array<Float64>(2000) { i => Float64(i) }
        let prototype = js.global.getProperty("Array").getProperty("prototype")
        if (prototype.hasProperty("1024")) { return "Array.prototype[1024] already exists" }
        let descriptor = js.object()
        descriptor.setProperty("configurable", js.boolean(true))
        descriptor.setProperty("set", js.function { _, _ =>
            numbers[1025] = -1.0
            gc(heavy: true)
            js.undefined()
        })
        let object = js.global.getProperty("Object")
        object.getProperty("defineProperty").call([prototype, js.string("1024"), descriptor], thisArg: object)
        try {
            let converted = ArkTSRuntime.toExtern(numbers)
            firstFailure([
                expectEqual("setter executed", numbers[1025], -1.0),
                expectEqual("conversion snapshots before setters", ArkTSRuntime.fromExtern<Float64>(converted[1025]), 1025.0)
            ])
        } finally {
            let reflect = js.global.getProperty("Reflect")
            reflect.getProperty("deleteProperty").call([prototype, js.string("1024")], thisArg: reflect)
        }
    }),
    ("step12.callbackLifetimeCreate", { js, fixtures =>
        let token = CallbackLifetimeToken()
        let callback = js.function { js, args => js.number(args[0].toNumber() + Float64(token.next())) }
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
        let environment = probeEnvironment.getOrThrow()
        let mutex = Mutex()
        let done: Condition
        synchronized(mutex) { done = mutex.condition() }
        let completed = Box(false)
        let result = Box("callback did not run")
        environment.post { cancelled =>
            let report = if (cancelled) { "native task cancelled" } else {
                environment.runtimeFrame { expectEqual("native callback thread", environment.isOnOwnerThread(), true) }
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
func numberArrayWithGetter(js: JS, body: (NativeJSValue) -> NativeJSValue): NativeJSValue {
    let array = js.array([js.number(0.0), js.number(2.0), js.number(3.0)])
    let descriptor = js.object()
    descriptor.setProperty("get", js.function { _, _ => body(array) })
    let object = js.global.getProperty("Object")
    object.getProperty("defineProperty").call([array, js.string("0"), descriptor], thisArg: object)
    array
}
