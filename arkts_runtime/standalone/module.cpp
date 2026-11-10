#include <napi/native_api.h>
#include "Cangjie.h"
#include <mutex>

namespace {
std::once_flag initialized;
int initialResult = -1;
using BindProbe = int32_t (*)(void *);
using AfterProbe = int32_t (*)();
BindProbe workerBind = nullptr;
AfterProbe workerAfter = nullptr;
const char *library = "/data/storage/el1/bundle/libs/arm64/libarkts_smoke_cj.so";
napi_value workerBinding(napi_env env, napi_callback_info) {
    napi_value result;
    napi_create_int32(env, workerBind ? workerBind(env) : -1, &result);
    return result;
}
napi_value afterShutdown(napi_env env, napi_callback_info) {
    napi_value result;
    napi_create_int32(env, workerAfter ? workerAfter() : -1, &result);
    return result;
}
napi_value initialize(napi_env env, napi_value exports) {
    std::call_once(initialized, [env] {
        RuntimeParam config{};
        initialResult = static_cast<int>(InitCJRuntime(&config));
        if (initialResult == 0) initialResult = LoadCJLibraryWithInit(library);
        if (initialResult == 0) {
            auto probe = reinterpret_cast<BindProbe>(FindCJSymbol(library, "arktsStandaloneProbe"));
            workerBind = reinterpret_cast<BindProbe>(FindCJSymbol(library, "arktsStandaloneWorkerBind"));
            workerAfter = reinterpret_cast<AfterProbe>(FindCJSymbol(library, "arktsStandaloneWorkerAfterShutdown"));
            initialResult = probe ? probe(env) : -2;
        }
    });
    napi_value value;
    napi_create_int32(env, initialResult, &value);
    napi_set_named_property(env, exports, "result", value);
    napi_create_function(env, "workerBind", NAPI_AUTO_LENGTH, workerBinding, nullptr, &value);
    napi_set_named_property(env, exports, "workerBind", value);
    napi_create_function(env, "workerAfterShutdown", NAPI_AUTO_LENGTH, afterShutdown, nullptr, &value);
    napi_set_named_property(env, exports, "workerAfterShutdown", value);
    return exports;
}
}
static napi_module module = {1, 0, nullptr, initialize, "ohos_app_cangjie_entry", nullptr, {nullptr}};
extern "C" __attribute__((constructor)) void registerStandalone() { napi_module_register(&module); }
