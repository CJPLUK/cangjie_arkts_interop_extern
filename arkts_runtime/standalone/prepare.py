from pathlib import Path
import shutil
import os
root=Path(__file__).resolve().parents[2]
src=root/'demos/benchmarks'; out=Path(os.environ['ARKTS_STANDALONE_APP'])
out.mkdir(exist_ok=True)
for name in ['AppScope','hvigor']:
 shutil.copytree(src/name,out/name,dirs_exist_ok=True)
for name in ['build-profile.json5','hvigorfile.ts','oh-package.json5','oh-package-lock.json5','local.properties','code-linter.json5']:
 if (src/name).exists(): shutil.copy2(src/name,out/name)
if not (out/'oh_modules').exists(): (out/'oh_modules').symlink_to(src/'oh_modules',target_is_directory=True)
entry=out/'entry'; entry.mkdir(exist_ok=True)
for name in ['build-profile.json5','oh-package.json5','oh-package-lock.json5','obfuscation-rules.txt']:
 if (src/'entry'/name).exists(): shutil.copy2(src/'entry'/name,entry/name)
shutil.copytree(src/'entry/src/main',entry/'src/main',dirs_exist_ok=True,ignore=shutil.ignore_patterns('cangjie'))
shutil.copytree(src/'entry/src/main/cangjie/types',entry/'src/main/cangjie/types',dirs_exist_ok=True)
(entry/'src/main/cangjie/types/libohos_app_cangjie_entry/Index.d.ts').write_text('export const result: number;\nexport function workerBind(): number;\nexport function workerAfterShutdown(): number;\n')
# The temporary app uses the existing signed benchmark identity and has no Cangjie build plugin.
p=entry/'build-profile.json5'; s=p.read_text();a=s.index('    "cangjieOptions"');b=s.index('    "nativeLib"',a);s=s[:a]+s[b:];s=s.replace('  \"buildOption\": {', '  \"buildOption\": {\n    \"sourceOption\": {\"workers\": [\"./src/main/ets/workers/NativeWorker.ets\"]},', 1);p.write_text(s)
(entry/'hvigorfile.ts').write_text("import { hapTasks } from '@ohos/hvigor-ohos-plugin';\nexport default { system: hapTasks, plugins: [] };\n")
(entry/'src/main/ets/workers').mkdir(exist_ok=True)
(entry/'src/main/ets/workers/NativeWorker.ets').write_text("""import { worker, MessageEvents, ErrorEvent } from '@kit.ArkTS';
import { workerBind } from 'libohos_app_cangjie_entry.so';
worker.workerPort.onmessage = (): void => {
  worker.workerPort.postMessage(-100);
  worker.workerPort.postMessage(workerBind());
  const started = Date.now();
  while (Date.now() - started < 1000) { /* keep the queued native task pending until termination */ }
};
""")
(entry/'src/main/ets/pages/Index.ets').write_text("""import { result, workerAfterShutdown } from 'libohos_app_cangjie_entry.so';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { worker, MessageEvents, ErrorEvent } from '@kit.ArkTS';
@Entry
@Component
struct Index {
  @State workerStatus: string = 'pending';
  private thread: worker.ThreadWorker | undefined = undefined;
  aboutToAppear(): void {
    hilog.info(0x0b01, 'ArkTSStandalone', 'result=%{public}d', result);
    try {
    const thread = new worker.ThreadWorker('entry/ets/workers/NativeWorker.ets');
    this.thread = thread;
    thread.onerror = (event: ErrorEvent): void => { this.workerStatus = event.message; };
    thread.onmessage = (event: MessageEvents): void => {
      if (event.data === -100) { this.workerStatus = 'worker started'; return; }
      if (event.data !== 0) { this.workerStatus = 'bind failed'; return; }
      thread.terminate();
      let attempts = 0;
      const timer = setInterval(() => {
        const after = workerAfterShutdown();
        attempts++;
        if (after === 0 || attempts >= 100) {
          clearInterval(timer);
          this.workerStatus = after === 0 ? 'passed' : `failed: ${after}`;
          hilog.info(0x0b01, 'ArkTSStandalone', 'worker teardown: %{public}s', this.workerStatus);
        }
      }, 50);
    };
    thread.postMessage(0);
    } catch (error) { this.workerStatus = String(error); }
  }
  build() {
    Column() {
      Text(`Standalone native backend: ${result}`)
      Text(`Worker teardown: ${this.workerStatus}`)
    }.width('100%').height('100%')
  }
}
""")
libs=entry/'libs/arm64-v8a';libs.mkdir(parents=True,exist_ok=True)
base=root/'dependencies_libs/base/arm64-v8a'
for folder in ['runtime','ohos']:
 for p in (base/folder).glob('*.so'):
  if p.name.startswith('libcangjie-') or p.name in ['libboundscheck.so','libpcre2-8.so']: shutil.copy2(p,libs/p.name)
for name in ['libarkts_runtime_native.so','libc++_shared.so']:
 shutil.copy2(Path(os.environ['ARKTS_STANDALONE_BUILD'])/'native'/name,libs/name)
shutil.copy2(Path(os.environ['ARKTS_STANDALONE_BUILD'])/'libarkts_smoke_cj.so',libs/'libarkts_smoke_cj.so')
shutil.copy2(Path(os.environ['ARKTS_STANDALONE_BUILD'])/'libarkts_standalone.so',libs/'libohos_app_cangjie_entry.so')
# Reuse the resolver cache but point its local native declaration at this temporary app.
(entry/'oh_modules').mkdir(exist_ok=True)
link=entry/'oh_modules/libohos_app_cangjie_entry.so'
if not link.exists(): link.symlink_to(entry/'src/main/cangjie/types/libohos_app_cangjie_entry',target_is_directory=True)
shutil.copy2(Path(os.environ['ARKTS_STANDALONE_BUILD'])/'libc++.so', libs/'libc++.so')
print(out)
