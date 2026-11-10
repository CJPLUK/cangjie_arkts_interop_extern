# Independent native consumer

Run from the repository root:

```sh
DEVICE=0123456789ABCDEF sh arkts_runtime/standalone/run.sh
DEVICE=127.0.0.1:5555 sh arkts_runtime/standalone/run.sh
```

The script builds the library without any OHOS Cangjie package import path, then links a
minimal Cangjie shared library and a regular N-API addon. The addon initializes Cangjie with
`InitCJRuntime`, loads the consumer with `LoadCJLibraryWithInit`, and calls its C exports via
`FindCJSymbol`. It does not use `JSModule`, `JSContext`, the platform Cangjie-module loader,
or the process-global `ARKTS_SetCJModuleCallback` table.

The generated app reuses `demos/benchmarks`' local signing configuration and bundle identity.
It is generated in `.app/`; compiler artifacts and logs go to `.build/`. Both are ignored.
After validation, run `demos/benchmarks/run.sh` to reinstall the normal benchmark app. The
normal benchmarks and interactive demos retain their existing registration adapters and the
libraries those adapters or Cangjie UI need.

The app tests the unbound state, rejection of a null environment, successful binding,
property updates, UTF-8 conversion and JS-to-Cangjie callbacks. A Worker creates a separate
backend session and a retained value, queues a task, and is terminated while the task is
pending. The main thread verifies cancellation, release of a caller waiting on dispatch, rejection of further posts and retained-value
access, and release after teardown. `verify.py` also checks the generated native dependencies
and packaged filenames for interop libraries. It fails unless both UI results report success.

A regular N-API application's linker namespace differs from the platform Cangjie loader's
namespace. This fixture ships one flat copy of the SDK runtime and standard libraries and
fetches the selected device's `libc++.so` to satisfy the SDK runtime's native dependency.
The core bridge separately uses the NDK `libc++_shared.so`. All interfaces between these
components are C-compatible; no C++ standard-library objects cross that boundary.

`Cangjie.h` is the public runtime C API header from the local Cangjie runtime source snapshot
`fdbd5408` (`cangjie_sdk_deveco/cangjie_runtime/runtime/src/Cangjie.h`). Its copyright notice
is preserved; `LICENSE-Cangjie` contains the source project's license and runtime exception.
The header and bootstrap have been checked with the installed 6.1 SDK; validate their ABI again
when changing the SDK/runtime version. The direct compiler build currently emits a benign
library-version warning for its default `0.0.1` metadata; the functional and lifecycle checks
must still pass.
