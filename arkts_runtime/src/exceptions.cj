package arkts_runtime

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

public class ArkTSNativeException <: Exception {
    public let code: Int32
    init(code: Int32, message: String) { super(message); this.code = code }
    protected override func getClassName(): String { "ArkTSNativeException" }
}
