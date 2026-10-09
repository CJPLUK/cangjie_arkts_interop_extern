package ohos_app_cangjie_entry.arkts.tests

import ohos.ark_interop.*
import ohos_app_cangjie_entry.arkts.*

func step1Scenarios(): Array<(String, Scenario)> {
    [
        ("step1.notBoundExceptionNames", { _, _ => notBoundExceptionNames() }),
        ("step1.alreadyBoundExceptionNames", { _, _ => alreadyBoundExceptionNames() }),
        ("step1.dynamicSyntaxReachesEval", { _, _ => dynamicSyntaxReachesEval() }),
        ("step1.toExternStub", { _, _ => toExternStub() }),
        ("step1.implicitConversionReachesToExtern", { _, _ => implicitConversionReachesToExtern() }),
        ("step1.fromExternStub", { _, _ => fromExternStub() }),
        ("step1.extendHelperReachable", { _, _ => extendHelperReachable() }),
        ("step1.internalVisibleToSubpackage", { _, _ => internalVisibleToSubpackage() })
    ]
}

func payload(): Extern<ArkTSRuntime> {
    Extern<ArkTSRuntime>.ExternPayload(1)
}

func notBoundExceptionNames(): String {
    firstFailure([
        expectEqual("with message", ArkTSContextNotBoundException("m").toString(),
            "ArkTSContextNotBoundException: m"),
        expectEqual("without message", ArkTSContextNotBoundException().toString(),
            "ArkTSContextNotBoundException"),
        expectEqual("message", ArkTSContextNotBoundException("m").message, "m")
    ])
}

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
 * `e.f` must be compiled into a call of `ArkTSRuntime.eval` on the device toolchain: on a
 * payload the runtime did not make, only our `evalPayload` throws this.
 */
func dynamicSyntaxReachesEval(): String {
    let e = payload()
    expectThrows<ExternConversionException>("e.f", "Extern payload was not produced by ArkTSRuntime", { => e.f })
}

func toExternStub(): String {
    expectThrows<ExternUnsupportedOperation>("toExtern", "ArkTSRuntime.toExtern",
        { => ArkTSRuntime.toExtern<Int64>(1) })
}

/** An Int64 where an Extern is expected must be compiled into `ArkTSRuntime.toExtern`. */
func implicitConversionReachesToExtern(): String {
    expectThrows<ExternUnsupportedOperation>("let v: Extern = 1", "ArkTSRuntime.toExtern", {
        =>
        let v: Extern<ArkTSRuntime> = 1
        v
    })
}

func fromExternStub(): String {
    expectThrows<ExternUnsupportedOperation>("fromExtern", "ArkTSRuntime.fromExtern",
        { => ArkTSRuntime.fromExtern<Int64>(payload()) })
}

func extendHelperReachable(): String {
    expectThrows<ExternUnsupportedOperation>("undefined()", "ArkTSRuntime.undefined",
        { => ArkTSRuntime.undefined() })
}

/** Tests in this subpackage rely on reaching internal members of the runtime package. */
func internalVisibleToSubpackage(): String {
    expectEqual("notImplemented message", ArkTSRuntime.notImplemented("x").message,
        "ArkTSRuntime.x is not implemented yet")
}
