import { describe, it, expect } from '@ohos/hypium';
import { runDiffProgram, runDiffProgramOffThread } from 'libohos_app_cangjie_entry.so';
import { programHeavy, programNames, programOffThreadRuns, programReference, programWorld } from './DiffPrograms';

function firstDifference(variant: string, expected: string, actual: string): string {
  if (expected === actual) {
    return '';
  }
  const e = expected.split('\n');
  const a = actual.split('\n');
  for (let i = 0; i < Math.max(e.length, a.length); i++) {
    if (e[i] !== a[i]) {
      return variant + ' line ' + (i + 1) + ': expected ' + (e[i] ?? '<end>') + ', got ' + (a[i] ?? '<end>');
    }
  }
  return variant + ': differs';
}

function dump(tag: string, text: string): void {
  for (const line of text.split('\n')) {
    console.info(tag + ' ' + line);
  }
}

export default function diffTest() {
  describe('Diff_Programs', () => {
    for (const name of programNames()) {
      it(name, 0, async () => {
        const reference = programReference(name);
        const differences: string[] = [];
        const check = (variant: string, actual: string) => {
          const difference = firstDifference(variant, reference, actual);
          if (difference !== '') {
            differences.push(difference);
            dump('DIFF ' + name + ' ' + variant + ' |', actual);
          }
        };
        check('interop', runDiffProgram('interop', name, programWorld(name)));
        check('extern', runDiffProgram('extern', name, programWorld(name)));
        for (let run = 0; !programHeavy(name) && run < programOffThreadRuns(name); run++) {
          check('extern off-thread run ' + run, await runDiffProgramOffThread(name, programWorld(name)));
        }
        if (differences.length > 0) {
          dump('DIFF ' + name + ' reference |', reference);
        }
        expect(differences.join(' || ')).assertEqual('');
      });
    }
  });
}
