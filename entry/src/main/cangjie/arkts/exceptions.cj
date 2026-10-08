package ohos_app_cangjie_entry.arkts

/** Thrown when the runtime is used before `ArkTSRuntime.bind` installed a `JSContext`. */
public class ArkTSContextNotBoundException <: Exception {
    public init() {
        super()
    }

    public init(message: String) {
        super(message)
    }

    protected override func getClassName(): String {
        "ArkTSContextNotBoundException"
    }
}

/** Thrown by every call to `ArkTSRuntime.bind` after the first successful one. */
public class ArkTSContextAlreadyBoundException <: Exception {
    public init() {
        super()
    }

    public init(message: String) {
        super(message)
    }

    protected override func getClassName(): String {
        "ArkTSContextAlreadyBoundException"
    }
}
