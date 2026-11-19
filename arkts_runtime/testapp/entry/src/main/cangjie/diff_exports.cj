package ohos_app_cangjie_entry

import ohos.ark_interop.*
import ohos_app_cangjie_entry.diff_interop.runProgram as runInterop
import ohos_app_cangjie_entry.diff_extern.runProgram as runExtern

func registerDiffExports(context: JSContext, exports: JSObject): Unit {
    exports["runDiffProgram"] = context.function(runDiffProgram).toJSValue()
    exports["runDiffProgramOffThread"] = context.function(runDiffProgramOffThread).toJSValue()
}

/** `runDiffProgram(variant: 'interop' | 'extern', name: string, world: Object): string`, the transcript. */
func runDiffProgram(context: JSContext, info: JSCallInfo): JSValue {
    let variant = info[0].toString()
    let name = info[1].toString()
    let transcript = match (variant) {
        case "interop" => context.newScope { runInterop(context, name, info[2]) }
        case "extern" =>
            context.global["__diffWorld"] = info[2]
            let result = runExtern(name, false)
            context.global["__diffWorld"] = context.undefined().toJSValue()
            result
        case _ => "unknown variant=${variant}"
    }
    context.string(transcript).toJSValue()
}

/** `runDiffProgramOffThread(name: string, world: Object): Promise<string>`, the Extern transcript, run on a spawned thread. */
func runDiffProgramOffThread(context: JSContext, info: JSCallInfo): JSValue {
    let name = info[0].toString()
    context.global["__diffWorld"] = info[1]
    let promise = context.promiseCapability()
    spawn {
        let transcript = runExtern(name, true)
        context.postJSTask {
            context.newScope {
                context.global["__diffWorld"] = context.undefined().toJSValue()
                promise.resolve(context.string(transcript).toJSValue())
            }
        }
    }
    promise.toJSValue()
}
