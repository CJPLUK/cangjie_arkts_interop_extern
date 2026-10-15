import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import * as fs from 'fs';
import * as path from 'path';

// Apps using arkts_runtime ship its Cangjie libraries (exactly one std-core per app). hvigor
// does not package a symlinked libs folder, so it is copied on every build.
const libs = path.resolve(__dirname, 'libs');
fs.rmSync(libs, { recursive: true, force: true });
fs.cpSync(path.resolve(__dirname, '../../libs'), libs, { recursive: true });

export default {
  system: hapTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: []       /* Custom plugin to extend the functionality of Hvigor. */
}
