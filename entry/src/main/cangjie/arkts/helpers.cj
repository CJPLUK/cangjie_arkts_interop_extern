package ohos_app_cangjie_entry.arkts

/** ArkTS-specific entry points used directly by applications, outside the compiler contract. */
extend ArkTSRuntime {
    public static func undefined(): Extern<ArkTSRuntime> {
        throw notImplemented("undefined")
    }
}
