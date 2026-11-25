import { hidebug, hilog } from '@kit.PerformanceAnalysisKit';
import { benchmarkNames, dispatchCases, iterations, runBenchmark, timeDispatch } from 'libohos_app_cangjie_entry.so';
import '../Bench';

// run.sh collects the lines logged with this tag.
const DOMAIN = 0x0b01;
const TAG = 'ArkTSBench';
const RUNS = 5;
// Pause between runs: with setTimeout(0) the main thread's event queue starves and the system
// watchdog kills the app (THREAD_BLOCK_6S).
const PAUSE_MS = 20;
const VARIANTS = ['arkInterop', 'arktsRuntime'];
// The dispatch benchmark (issue #7): more paired runs, as the gap it looks for is small.
const DISPATCH_RUNS = 9;
const DISPATCH_ITERATIONS = 200000;
const DISPATCH_VARIANTS = ['probes', 'reflective'];

interface Row {
  name: string;
  iterations: number;
  arkInterop: number;
  arktsRuntime: number;
  arkInteropHeapKB: string;
  arktsRuntimeHeapKB: string;
}

function measure(name: string, variant: string): Promise<number> {
  return new Promise<number>((resolve, reject) => {
    runBenchmark(name, variant, (ns: number, error: string) => {
      if (ns < 0) {
        reject(new Error(error));
      } else {
        resolve(ns);
      }
    });
  });
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => setTimeout(resolve, ms));
}

/** Dumping a heap snapshot runs a full collection; queued pin releases run in between. */
async function fullCollection(): Promise<void> {
  for (let i = 0; i < 2; i++) {
    await sleep(100);
    hidebug.dumpJsHeapData('arkts-benchmarks-gc');
  }
  await sleep(100);
}

async function heapGrowthKB(name: string, variant: string): Promise<string> {
  try {
    await fullCollection();
    const before = Number(hidebug.getAppVMObjectUsedSize());
    await measure(name, variant);
    await fullCollection();
    return String(Number(hidebug.getAppVMObjectUsedSize()) - before);
  } catch (e) {
    return 'n/a';
  }
}

function median(values: number[]): number {
  const sorted = values.slice().sort((a: number, b: number) => a - b);
  return sorted[Math.floor(sorted.length / 2)];
}

function format(row: Row): string {
  const ratio = row.arktsRuntime / row.arkInterop;
  return `${row.name}|${row.iterations}|${row.arkInterop.toFixed(1)}|${row.arktsRuntime.toFixed(1)}|` +
    `${ratio.toFixed(2)}|${row.arkInteropHeapKB}|${row.arktsRuntimeHeapKB}`;
}

@Entry
@Component
struct Index {
  @State status: string = 'running';
  @State lines: string[] = [];
  @State header: string = 'benchmark | N | ark_interop ns/op | arkts_runtime ns/op | ratio | heap KB';

  aboutToAppear(): void {
    const suite = AppStorage.get<string>('suite');
    if (suite === 'dispatch') {
      this.header = 'case | N | type probes ns/op | reflective ns/op | saving ns';
    }
    setTimeout(() => suite === 'dispatch' ? this.runDispatch() : this.runAll(), 500);
  }

  /**
   * Times each dispatch case through the type probes and the reflective conversion. The two
   * variants alternate within each run, and their order flips from run to run, so drift in
   * the CPU's speed falls on both. Logs DISPATCH|case|N|probes ns/op|reflective ns/op|saving,
   * each the median over the runs; the saving is the median of each run's paired difference.
   */
  async runDispatch(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'START');
    for (const name of dispatchCases()) {
      this.status = `running ${name}`;
      try {
        const runs: number[][] = [[], []];
        for (let i = 0; i < DISPATCH_RUNS; i++) {
          const order = i % 2 === 0 ? [0, 1] : [1, 0];
          for (const v of order) {
            // Untimed run right before each timed one, as in runAll.
            timeDispatch(name, DISPATCH_VARIANTS[v], DISPATCH_ITERATIONS);
            runs[v].push(timeDispatch(name, DISPATCH_VARIANTS[v], DISPATCH_ITERATIONS));
          }
          await sleep(PAUSE_MS);
        }
        for (let v = 0; v < DISPATCH_VARIANTS.length; v++) {
          hilog.info(DOMAIN, TAG, 'SAMPLES|%{public}s',
            `dispatch.${name}|${DISPATCH_VARIANTS[v]}|${DISPATCH_ITERATIONS}|${runs[v].join(',')}`);
        }
        const probes = median(runs[0]) / DISPATCH_ITERATIONS;
        const reflective = median(runs[1]) / DISPATCH_ITERATIONS;
        const saving = median(runs[1].map((r: number, i: number) => r - runs[0][i])) / DISPATCH_ITERATIONS;
        const line = `${name}|${DISPATCH_ITERATIONS}|${probes.toFixed(1)}|${reflective.toFixed(1)}|` +
          `${saving.toFixed(1)}`;
        hilog.info(DOMAIN, TAG, 'DISPATCH|%{public}s', line);
        this.lines.push(line);
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'ERROR|%{public}s|%{public}s', name, String(e));
        this.lines.push(`${name}: ${String(e)}`);
      }
    }
    this.status = 'done';
    hilog.info(DOMAIN, TAG, 'DONE');
  }

  async runAll(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'START');
    for (const name of benchmarkNames()) {
      this.status = `running ${name}`;
      try {
        const n = iterations(name);
        const perOp: number[] = [];
        for (const variant of VARIANTS) {
          const runs: number[] = [];
          for (let i = 0; i < RUNS; i++) {
            // Untimed run right before each timed one: the CPU slows down during the pause.
            await measure(name, variant);
            const elapsed = await measure(name, variant);
            runs.push(elapsed);
            await sleep(PAUSE_MS);
          }
          hilog.info(DOMAIN, TAG, 'SAMPLES|%{public}s', `${name}|${variant}|${n}|${runs.join(',')}`);
          perOp.push(median(runs) / n);
        }
        const heap = name.startsWith('handles.');
        const row: Row = {
          name: name,
          iterations: n,
          arkInterop: perOp[0],
          arktsRuntime: perOp[1],
          arkInteropHeapKB: heap ? await heapGrowthKB(name, VARIANTS[0]) : '',
          arktsRuntimeHeapKB: heap ? await heapGrowthKB(name, VARIANTS[1]) : ''
        };
        const line = format(row);
        hilog.info(DOMAIN, TAG, 'RESULT|%{public}s', line);
        this.lines.push(line);
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'ERROR|%{public}s|%{public}s', name, String(e));
        this.lines.push(`${name}: ${String(e)}`);
      }
    }
    this.status = 'done';
    hilog.info(DOMAIN, TAG, 'DONE');
  }

  build() {
    Column() {
      Text(this.status).fontSize(18).margin({ bottom: 8 })
      Text(this.header).fontSize(11)
      List() {
        ForEach(this.lines, (line: string) => {
          ListItem() {
            Text(line).fontSize(11)
          }
        })
      }
      .layoutWeight(1)
    }
    .height('100%')
    .width('100%')
    .padding(12)
  }
}
