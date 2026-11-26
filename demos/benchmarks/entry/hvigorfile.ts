import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import { hvigor } from '@ohos/hvigor';
import * as fs from 'fs';
import * as path from 'path';
import { execFileSync } from 'child_process';

function copyCangjieLibsBecauseHvigorSkipsSymlinkedLibs(libs: string, folders: string[]): void {
  fs.rmSync(libs, { recursive: true, force: true });
  for (const folder of folders) {
    fs.cpSync(path.resolve(__dirname, '../../../dependencies_libs', folder), libs, { recursive: true });
  }
}

const libs = path.resolve(__dirname, 'libs');
copyCangjieLibsBecauseHvigorSkipsSymlinkedLibs(libs, ['base']);

const nativeLibs = path.join(libs, 'arm64-v8a');
const nativeBuildMode = hvigor.getParameter().getExtParam('buildMode') ?? 'debug';
execFileSync('/bin/sh', [path.resolve(__dirname, '../../../arkts_runtime/native/build.sh'), nativeLibs,
  nativeBuildMode]);
process.env.ARKTS_RUNTIME_NATIVE_LIB = nativeLibs;

export default {
  system: hapTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: []       /* Custom plugin to extend the functionality of Hvigor. */
}
