package arkts_runtime

/** Thrown when the runtime is used before `ArkTSRuntime.bind` installed a host environment. */
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

/** Native backend failure; codes preserve the former interop error categories. */
public class ArkTSNativeException <: Exception {
    public let code: Int32
    init(code: Int32, message: String) { super(message); this.code = code }
    protected override func getClassName(): String { "ArkTSNativeException" }
}
