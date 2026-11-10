package arkts_runtime

import std.collection.HashMap
import std.sync.Mutex
import std.math.numeric.BigInt

private let functionMutex = Mutex()
private let nativeFunctions = HashMap<Int64, (NativeContext, (NativeContext, Array<NativeJSValue>) -> NativeJSValue)>()
private var nextFunctionId: Int64 = 0
private let nativeExternals = HashMap<Int64, Object>()
private var nextExternalId: Int64 = 0

@C
func nativeExternalDrop(id: Int64): Unit { synchronized(functionMutex) { nativeExternals.remove(id) } }

func nativeExternalData(id: Int64): Object { synchronized(functionMutex) { nativeExternals.get(id).getOrThrow() } }

@C
func nativeFunctionDrop(id: Int64): Unit {
    synchronized(functionMutex) { nativeFunctions.remove(id) }
}

@C
func nativeFunctionCall(id: Int64, count: UIntNative, values: CPointer<NapiValue>): NapiValue {
    let entry = synchronized(functionMutex) { nativeFunctions.get(id) }
    if (let Some((context, body)) <- entry) {
        try {
            let args = Array<NativeJSValue>(Int64(count)) { i => NativeJSValue(context.session, unsafe { values.read(i) }) }
            return body(context, args).raw
        } catch (e: Exception) {
            context.throwError(e.toString())
        } catch (e: Error) {
            context.throwError(e.toString())
        }
    }
    NapiValue()
}

class NativeContext {
    let session: NativeSession
    init(env: NativeEnv) {
        session = NativeSession(env)
    }
    func getNapiEnv(): NativeEnv { session.env }
    func isInBindThread(): Bool { session.isInBindThread() }
    func newScope<R>(operation: () -> R): R { session.newScope(operation) }
    func undefined(): NativeJSValue { NativeJSValue(session, NapiValue(), 0) }
    func null(): NativeJSValue { NativeJSValue(session, NapiValue(), 1) }
    func boolean(b: Bool): NativeJSValue { NativeJSValue(session, NapiValue(), 2, boolean: b) }
    func number(n: Float64): NativeJSValue { NativeJSValue(session, NapiValue(), 3, number: n) }
    func string(text: String): NativeJSValue { nativeString(session, text) }
    func string(value: Utf16String): NativeJSValue {
        if (let Some(units) <- value.units) {
            var result = NapiValue()
            unsafe {
                // Some target implementations inspect the terminator even with an explicit length.
                let terminated = Array<UInt16>(units.size + 1, repeat: 0)
                for (i in 0..units.size) { terminated[i] = units[i] }
                let buffer = acquireArrayRawData(terminated)
                try { nativeCheck(session, napi_create_string_utf16(session.env, buffer.pointer, UIntNative(units.size), inout result)) }
                finally { releaseArrayRawData(buffer) }
            }
            return NativeJSValue(session, result, 4)
        }
        string(value.text)
    }
    func object(): NativeJSValue {
        var value = NapiValue()
        nativeCheck(session, unsafe { napi_create_object(session.env, inout value) })
        NativeJSValue(session, value, 6)
    }
    prop global: NativeJSValue {
        get() {
            var value = NapiValue()
            nativeCheck(session, unsafe { napi_get_global(session.env, inout value) })
            NativeJSValue(session, value, 6)
        }
    }
    func array(elements: Array<NativeJSValue>): NativeJSValue {
        // Marshal copied immediate payloads and current-scope heap handles once.
        // N-API materialization and insertion stay on the native side of the loop.
        let kinds = elements.map { v => v.kind }
        let locals = elements.map { v => v.local }
        let numbers = elements.map { v =>
            if (v.kind == 2) { if (v.boolean) { 1.0 } else { 0.0 } } else { v.number }
        }
        var value = NapiValue()
        unsafe {
            let types = acquireArrayRawData(kinds)
            let handles = acquireArrayRawData(locals)
            let payloads = acquireArrayRawData(numbers)
            try {
                nativeCheck(session, ar_create_array(session.env, UIntNative(elements.size), types.pointer,
                    handles.pointer, payloads.pointer, inout value), checkPending: true)
            } finally {
                releaseArrayRawData(payloads)
                releaseArrayRawData(handles)
                releaseArrayRawData(types)
            }
        }
        NativeJSValue(session, value, 6)
    }
    func numberArray(numbers: Array<Float64>): NativeJSValue {
        // Match generic conversion: snapshot every input before JS setters can reenter.
        let copied = numbers.clone()
        var value = NapiValue()
        unsafe {
            let buffer = acquireArrayRawData(copied)
            try {
                nativeCheck(session, ar_create_number_array(session.env, buffer.pointer,
                    UIntNative(numbers.size), inout value), checkPending: true)
            } finally { releaseArrayRawData(buffer) }
        }
        NativeJSValue(session, value, 6)
    }
    func bigint(n: Int64): NativeJSValue {
        var value = NapiValue()
        nativeCheck(session, unsafe { napi_create_bigint_int64(session.env, n, inout value) })
        NativeJSValue(session, value, 9)
    }
    func bigint(n: UInt64): NativeJSValue {
        var value = NapiValue()
        nativeCheck(session, unsafe { napi_create_bigint_uint64(session.env, n, inout value) })
        NativeJSValue(session, value, 9)
    }
    func bigint(n: BigInt): NativeJSValue {
        let digits = (if (n.sign < 0) { -n } else { n }).toBytes()
        var result = NapiValue()
        unsafe {
            let bytes = acquireArrayRawData(digits)
            try { nativeCheck(session, ar_bigint_create(session.state, if (n.sign < 0) { 1 } else { 0 },
                bytes.pointer, UIntNative(digits.size), inout result)) }
            finally { releaseArrayRawData(bytes) }
        }
        NativeJSValue(session, result, 9)
    }
    func symbol(description!: String = ""): NativeJSValue {
        var value = NapiValue()
        nativeCheck(session, unsafe { napi_create_symbol(session.env, string(description).raw, inout value) })
        NativeJSValue(session, value, 5)
    }
    func function(body: (NativeContext, Array<NativeJSValue>) -> NativeJSValue): NativeJSValue {
        let id = synchronized(functionMutex) {
            nextFunctionId++
            nativeFunctions.add(nextFunctionId, (this, body))
            nextFunctionId
        }
        var value = NapiValue()
        let status = unsafe { ar_create_function(session.state, id, nativeFunctionCall, nativeFunctionDrop, inout value) }
        if (status != 0) { unsafe { nativeFunctionDrop(id) }; nativeCheck(session, status) }
        NativeJSValue(session, value, 7)
    }
    func requireArkModule(path: String): NativeJSValue {
        var value = NapiValue()
        try {
            unsafe {
                let name = LibC.mallocCString(path)
                try { nativeCheck(session, napi_load_module(session.env, name, inout value), checkPending: true) }
                finally { LibC.free(name) }
            }
        } catch (e: ArkTSNativeException) {
            if (e.message.contains("cannot find record") || e.message.contains("Cannot find module")) {
                throw ArkTSNativeException(34300006, "Fail to load module '${path}' which doesn't exist.")
            }
            throw e
        }
        NativeJSValue(session, value)
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
        let status = unsafe { ar_create_external(session.state, id, nativeExternalDrop, inout result) }
        if (status != 0) { unsafe { nativeExternalDrop(id) }; nativeCheck(session, status) }
        NativeJSValue(session, result)
    }
    func throwError(message: String): Unit {
        unsafe {
            let msg = LibC.mallocCString(message)
            try { napi_throw_error(session.env, CString(CPointer<UInt8>()), msg) }
            finally { LibC.free(msg) }
        }
    }
}

abstract class JSType {
    static const UNDEFINED: Int32 = 0
    static const NULL: Int32 = 1
    static const BOOLEAN: Int32 = 2
    static const NUMBER: Int32 = 3
    static const STRING: Int32 = 4
    static const SYMBOL: Int32 = 5
    static const OBJECT: Int32 = 6
    static const FUNCTION: Int32 = 7
    static const EXTERNAL: Int32 = 8
    static const BIGINT: Int32 = 9
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
