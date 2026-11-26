package arkts_runtime

import std.collection.HashMap
import std.sync.Mutex
import std.math.numeric.BigInt

private let functionMutex = Mutex()
private let nativeFunctions = HashMap<Int64, (JS, (JS, Array<NativeJSValue>) -> NativeJSValue)>()
private var nextFunctionId: Int64 = 0
private let nativeExternals = HashMap<Int64, Object>()
private var nextExternalId: Int64 = 0

@C
func ats_rt_ext_nativeExternalDrop(id: Int64): Unit { synchronized(functionMutex) { nativeExternals.remove(id) } }

func nativeExternalData(id: Int64): Object { synchronized(functionMutex) { nativeExternals.get(id).getOrThrow() } }

@C
func ats_rt_ext_nativeFunctionDrop(id: Int64): Unit {
    synchronized(functionMutex) { nativeFunctions.remove(id) }
}

private func nativeFunctionOf(id: Int64): ?(JS, (JS, Array<NativeJSValue>) -> NativeJSValue) {
    synchronized(functionMutex) { nativeFunctions.get(id) }
}

@C
func ats_rt_ext_nativeFunctionCall(id: Int64, count: UIntNative, values: CPointer<NapiValue>): NapiValue {
    if (let Some((js, body)) <- nativeFunctionOf(id)) {
        try {
            let args = Array<NativeJSValue>(Int64(count)) { i => NativeJSValue(js.environment, unsafe { values.read(i) }) }
            return body(js, args).raw
        } catch (e: Exception) {
            js.throwError(e.toString())
        } catch (e: Error) {
            js.throwError(e.toString())
        }
    }
    NapiValue()
}

class JS {
    let environment: Environment
    init(environment: Environment) {
        this.environment = environment
    }
    func undefined(): NativeJSValue { NativeJSValue(environment, NapiValue(), 0) }
    func null(): NativeJSValue { NativeJSValue(environment, NapiValue(), 1) }
    func boolean(b: Bool): NativeJSValue { NativeJSValue(environment, NapiValue(), 2, boolean: b) }
    func number(n: Float64): NativeJSValue { NativeJSValue(environment, NapiValue(), 3, number: n) }
    func string(text: String): NativeJSValue { nativeString(environment, text) }
    func string(value: Utf16String): NativeJSValue {
        if (let Some(units) <- value.units) {
            var result = NapiValue()
            let terminated = terminatedBecauseSomeEnginesReadPastLength(units)
            unsafe {
                let buffer = acquireArrayRawData(terminated)
                try { nativeCheck(environment, napi_create_string_utf16(environment.env, buffer.pointer, UIntNative(units.size), inout result)) }
                finally { releaseArrayRawData(buffer) }
            }
            return NativeJSValue(environment, result, 4)
        }
        string(value.text)
    }
    func object(): NativeJSValue {
        var value = NapiValue()
        nativeCheck(environment, unsafe { napi_create_object(environment.env, inout value) })
        NativeJSValue(environment, value, 6)
    }
    prop global: NativeJSValue {
        get() {
            var value = NapiValue()
            nativeCheck(environment, unsafe { napi_get_global(environment.env, inout value) })
            NativeJSValue(environment, value, 6)
        }
    }
    func array(elements: Array<NativeJSValue>): NativeJSValue {
        let kinds = elements.map { v => v.kind }
        let locals = elements.map { v => v.local }
        let numbers = elements.map { v => v.scalar }
        var value = NapiValue()
        unsafe {
            let types = acquireArrayRawData(kinds)
            let handles = acquireArrayRawData(locals)
            let payloads = acquireArrayRawData(numbers)
            try {
                nativeCheck(environment, ats_rt_ext_create_array(environment.env, UIntNative(elements.size), types.pointer,
                    handles.pointer, payloads.pointer, inout value), checkPending: true)
            } finally {
                releaseArrayRawData(payloads)
                releaseArrayRawData(handles)
                releaseArrayRawData(types)
            }
        }
        NativeJSValue(environment, value, 6)
    }
    func numberArray(numbers: Array<Float64>): NativeJSValue {
        let snapshotBeforeSettersRun = numbers.clone()
        var value = NapiValue()
        unsafe {
            let buffer = acquireArrayRawData(snapshotBeforeSettersRun)
            try {
                nativeCheck(environment, ats_rt_ext_create_number_array(environment.env, buffer.pointer,
                    UIntNative(snapshotBeforeSettersRun.size), inout value), checkPending: true)
            } finally { releaseArrayRawData(buffer) }
        }
        NativeJSValue(environment, value, 6)
    }
    func bigint(n: Int64): NativeJSValue {
        var value = NapiValue()
        nativeCheck(environment, unsafe { napi_create_bigint_int64(environment.env, n, inout value) })
        NativeJSValue(environment, value, 9)
    }
    func bigint(n: UInt64): NativeJSValue {
        var value = NapiValue()
        nativeCheck(environment, unsafe { napi_create_bigint_uint64(environment.env, n, inout value) })
        NativeJSValue(environment, value, 9)
    }
    func bigint(n: BigInt): NativeJSValue {
        let digits = (if (n.sign < 0) { -n } else { n }).toBytes()
        var result = NapiValue()
        unsafe {
            let bytes = acquireArrayRawData(digits)
            try { nativeCheck(environment, ats_rt_ext_bigint_create(environment.state, if (n.sign < 0) { 1 } else { 0 },
                bytes.pointer, UIntNative(digits.size), inout result)) }
            finally { releaseArrayRawData(bytes) }
        }
        NativeJSValue(environment, result, 9)
    }
    func symbol(description!: String = ""): NativeJSValue {
        var value = NapiValue()
        nativeCheck(environment, unsafe { napi_create_symbol(environment.env, string(description).raw, inout value) })
        NativeJSValue(environment, value, 5)
    }
    func function(body: (JS, Array<NativeJSValue>) -> NativeJSValue): NativeJSValue {
        let id = synchronized(functionMutex) {
            nextFunctionId++
            nativeFunctions.add(nextFunctionId, (this, body))
            nextFunctionId
        }
        var value = NapiValue()
        let status = unsafe { ats_rt_ext_create_function(environment.state, id, ats_rt_ext_nativeFunctionCall, ats_rt_ext_nativeFunctionDrop, inout value) }
        if (status != 0) { unsafe { ats_rt_ext_nativeFunctionDrop(id) }; nativeCheck(environment, status) }
        NativeJSValue(environment, value, 7)
    }
    func requireArkModule(path: String): NativeJSValue {
        var value = NapiValue()
        try {
            unsafe {
                let name = LibC.mallocCString(path)
                try { nativeCheck(environment, napi_load_module(environment.env, name, inout value), checkPending: true) }
                finally { LibC.free(name) }
            }
        } catch (e: ForeignRuntimeException) {
            if (e.message.contains("cannot find record") || e.message.contains("Cannot find module")) {
                throw ArkTSNativeException(34300006, "Fail to load module '${path}' which doesn't exist.")
            }
            throw e
        }
        NativeJSValue(environment, value)
    }
    func requireSystemNativeModule(name: String, prefix!: ?String): NativeJSValue {
        let function = global.getProperty(string("requireNapi"))
        function.call([string(name), boolean(false), string(prefix ?? "")], thisArg: global)
    }
    func external(value: Object): NativeJSValue {
        let id = synchronized(functionMutex) {
            nextExternalId++
            nativeExternals.add(nextExternalId, value)
            nextExternalId
        }
        var result = NapiValue()
        let status = unsafe { ats_rt_ext_create_external(environment.state, id, ats_rt_ext_nativeExternalDrop, inout result) }
        if (status != 0) { unsafe { ats_rt_ext_nativeExternalDrop(id) }; nativeCheck(environment, status) }
        NativeJSValue(environment, result)
    }
    func throwError(message: String): Unit {
        unsafe {
            let msg = LibC.mallocCString(message)
            try { napi_throw_error(environment.env, CString(CPointer<UInt8>()), msg) }
            finally { LibC.free(msg) }
        }
    }
}

private func terminatedBecauseSomeEnginesReadPastLength(units: Array<UInt16>): Array<UInt16> {
    let terminated = Array<UInt16>(units.size + 1, repeat: 0)
    for (i in 0..units.size) { terminated[i] = units[i] }
    terminated
}

type JSTypeCode = Int32

abstract class JSType {
    static const UNDEFINED: JSTypeCode = 0
    static const NULL: JSTypeCode = 1
    static const BOOLEAN: JSTypeCode = 2
    static const NUMBER: JSTypeCode = 3
    static const STRING: JSTypeCode = 4
    static const SYMBOL: JSTypeCode = 5
    static const OBJECT: JSTypeCode = 6
    static const FUNCTION: JSTypeCode = 7
    static const EXTERNAL: JSTypeCode = 8
    static const BIGINT: JSTypeCode = 9
}

public class Utf16String {
    let text: String
    let units: ?Array<UInt16>
    public init(text: String) { this.text = text; units = None }
    public init(units: Array<UInt16>) {
        text = ""
        this.units = Some(Array<UInt16>(units.size) { i => units[i] })
    }
}
