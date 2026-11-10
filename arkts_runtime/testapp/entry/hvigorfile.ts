import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import * as fs from 'fs';
import * as path from 'path';
import { execFileSync } from 'child_process';

// Apps using arkts_runtime ship the Cangjie libraries in dependencies_libs/base (exactly one
// std-core per app). hvigor does not package a symlinked libs folder, so it is copied on every
// build.
const libs = path.resolve(__dirname, 'libs');
fs.rmSync(libs, { recursive: true, force: true });
fs.cpSync(path.resolve(__dirname, '../../../dependencies_libs/base'), libs, { recursive: true });

const nativeLibs = path.join(libs, 'arm64-v8a');
execFileSync('/bin/sh', [path.resolve(__dirname, '../../native/build.sh'), nativeLibs]);
process.env.ARKTS_RUNTIME_NATIVE_LIB = nativeLibs;

export default {
  system: hapTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: []       /* Custom plugin to extend the functionality of Hvigor. */
}
