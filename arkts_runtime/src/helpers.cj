package arkts_runtime

import ohos.ark_interop.*
import ohos.business_exception.BusinessException

/**
 * ArkTS-specific entry points used directly by applications, outside the compiler contract.
 * Each runs in one `run`; `Extern` operands may be unevaluated trees.
 */
extend ArkTSRuntime {
    public static func undefined(): Extern<ArkTSRuntime> {
        run { undefinedExtern }
    }

    public static func null(): Extern<ArkTSRuntime> {
        run { retain(context.null().toJSValue()) }
    }

    /** A fresh empty object. */
    public static func object(): Extern<ArkTSRuntime> {
        run { retain(context.object().toJSValue()) }
    }

    /** `globalThis`. */
    public static func global(): Extern<ArkTSRuntime> {
        run { retain(context.global.toJSValue()) }
    }

    /** A new symbol; two calls never give the same symbol. */
    public static func symbol(description!: String = ""): Extern<ArkTSRuntime> {
        run { retain(context.symbol(description: description).toJSValue()) }
    }

    /** JS `lhs === rhs`. */
    public static func strictEqual(lhs: Extern<ArkTSRuntime>, rhs: Extern<ArkTSRuntime>): Bool {
        run { evalTree(lhs).strictEqual(evalTree(rhs)) }
    }

    public static func isNull(value: Extern<ArkTSRuntime>): Bool {
        run { evalTree(value).isNull() }
    }

    public static func isUndefined(value: Extern<ArkTSRuntime>): Bool {
        run { evalTree(value).isUndefined() }
    }

    /** JS `key in value`: own or inherited. Throws `ExternMemberAccessException` for non-objects. */
    public static func objectHasProperty(value: Extern<ArkTSRuntime>, key: String): Bool {
        run { objectOf(evalTree(value)).hasProperty(key) }
    }

    /** JS `Object.keys(value)`: own enumerable string keys. */
    public static func objectKeys(value: Extern<ArkTSRuntime>): Array<String> {
        run { objectOf(evalTree(value)).keys() }
    }

    /**
     * Defines (or redefines) an own data property. As with JS `Object.defineProperty`, a refusal
     * (frozen object, read-only non-configurable property) throws: a `ForeignRuntimeException`
     * with "TypeError Cannot define property".
     */
    public static func objectDefineOwnProperty(
        value: Extern<ArkTSRuntime>,
        key: String,
        propertyValue: Any,
        isWritable!: Bool = true,
        isEnumerable!: Bool = true,
        isConfigurable!: Bool = true
    ): Bool {
        run {
            let target = objectOf(evalTree(value))
            target.defineOwnProperty(key, toJSValue(propertyValue), isWritable: isWritable,
                isEnumerable: isEnumerable, isConfigurable: isConfigurable)
        }
    }

    /**
     * Loads an ArkTS module, e.g. `"entry/src/main/ets/Utils"` (no extension; the file must be
     * listed in `arkOptions.runtimeOnly.sources`), `"@ohos.hilog"` or `"libfoo.so"`. Works only
     * while ArkTS code is on the stack: from a spawned thread (the call then runs in a posted
     * JS task) it throws `ForeignRuntimeException` ("Unable to get recordName ..."). A missing
     * module throws `BusinessException` 34300006 from `ark_interop`.
     */
    public static func requireArkModule(specifier: String): Extern<ArkTSRuntime> {
        run { retain(context.requireArkModule(specifier)) }
    }

    /** Loads a system NAPI module, e.g. `"hilog"`; `undefined` when it cannot be loaded. */
    public static func requireSystemNativeModule(moduleName: String, prefix: ?String): Extern<ArkTSRuntime> {
        run { retain(context.requireSystemNativeModule(moduleName, prefix: prefix)) }
    }

    /**
     * An ArkTS function that runs `body` when called (on the JS thread), with the arguments as
     * `Extern` values; the result is converted like any value passed to ArkTS. `this` is not
     * passed. An exception thrown by `body` reaches ArkTS as an `Error` whose message is the
     * exception's text (`ark_interop` does this).
     */
    public static func function(body: (Array<Extern<ArkTSRuntime>>) -> Extern<ArkTSRuntime>): Extern<ArkTSRuntime> {
        run {
            let function = context.function { _, callInfo =>
                let arguments = Array<Extern<ArkTSRuntime>>(callInfo.count) { i => retain(callInfo[i]) }
                toJSValue(body(arguments))
            }
            retain(function.toJSValue())
        }
    }

    /** As member access, a non-object throws `ExternMemberAccessException` with `ark_interop`'s message. */
    private static func objectOf(value: JSValue): JSObject {
        try {
            value.asObject()
        } catch (e: BusinessException) {
            throw memberError(e)
        }
    }
}
