package arkts_runtime.tests


import arkts_runtime.*

@When[bundle == "com.example.testArkTSForeignRuntime"]
func step1Scenarios(): Array<(String, Scenario)> {
    [
        ("step1.notBoundExceptionNames", { _, _ => notBoundExceptionNames() }),
        ("step1.alreadyBoundExceptionNames", { _, _ => alreadyBoundExceptionNames() }),
        ("step1.dynamicSyntaxReachesRuntime", { _, _ => dynamicSyntaxReachesRuntime() }),
        ("step1.extendHelperReachable", { _, _ => extendHelperReachable() }),
        ("step1.directNapiProbe", { context, _ => directNapiProbe(context) }),
        ("step1.internalVisibleToSubpackage", { _, _ => internalVisibleToSubpackage() })
    ]
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func payload(): Extern<ArkTSRuntime> {
    Extern<ArkTSRuntime>(1)
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func notBoundExceptionNames(): String {
    firstFailure([
        expectEqual("with message", ArkTSContextNotBoundException("m").toString(),
            "ArkTSContextNotBoundException: m"),
        expectEqual("without message", ArkTSContextNotBoundException().toString(),
            "ArkTSContextNotBoundException"),
        expectEqual("message", ArkTSContextNotBoundException("m").message, "m")
    ])
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func alreadyBoundExceptionNames(): String {
    firstFailure([
        expectEqual("with message", ArkTSContextAlreadyBoundException("m").toString(),
            "ArkTSContextAlreadyBoundException: m"),
        expectEqual("without message", ArkTSContextAlreadyBoundException().toString(),
            "ArkTSContextAlreadyBoundException"),
        expectEqual("message", ArkTSContextAlreadyBoundException("m").message, "m")
    ])
}

/**
 * `e.f` must be compiled into a call of `ArkTSRuntime.memberAccess` on the device toolchain: on
 * a payload the runtime did not make, only our `evalPayload` throws this.
 */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func dynamicSyntaxReachesRuntime(): String {
    let e = payload()
    expectThrows<ExternConversionException>("e.f", "Extern payload was not produced by ArkTSRuntime", { => e.f })
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
foreign func napi_get_undefined(env: CPointer<Unit>, result: CPointer<CPointer<Unit>>): Int32

@When[bundle == "com.example.testArkTSForeignRuntime"]
foreign func napi_typeof(env: CPointer<Unit>, value: CPointer<Unit>, result: CPointer<Int32>): Int32

@When[bundle == "com.example.testArkTSForeignRuntime"]
func directNapiProbe(context: NativeContext): String {
    let env = context.getNapiEnv()
    if (env.isNull()) { return "getNapiEnv returned null" }
    var value = CPointer<Unit>()
    var kind: Int32 = -1
    let status = unsafe { napi_get_undefined(env, inout value) }
    if (status != 0 || value.isNull()) { return "napi_get_undefined failed: ${status}" }
    let typeStatus = unsafe { napi_typeof(env, value, inout kind) }
    if (typeStatus != 0 || kind != 0) { return "napi_typeof failed: ${typeStatus}, ${kind}" }
    ""
}

@When[bundle == "com.example.testArkTSForeignRuntime"]
func extendHelperReachable(): String {
    expectEqual("isUndefined(undefined())", ArkTSRuntime.isUndefined(ArkTSRuntime.undefined()), true)
}

/** Tests in this subpackage rely on reaching internal members of the runtime package. */
@When[bundle == "com.example.testArkTSForeignRuntime"]
func internalVisibleToSubpackage(): String {
    expectEqual("handleKind", ArkTSRuntime.handleKind(payload()), "foreign payload")
}
