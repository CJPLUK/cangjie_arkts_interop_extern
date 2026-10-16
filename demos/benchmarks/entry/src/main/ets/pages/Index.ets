import { hidebug, hilog } from '@kit.PerformanceAnalysisKit';
import { benchmarkNames, iterations, runBenchmark } from 'libohos_app_cangjie_entry.so';
import '../Bench';

// run.sh collects the lines logged with this tag.
const DOMAIN = 0x0b01;
const TAG = 'ArkTSBench';
const RUNS = 5;
// Pause between runs: with setTimeout(0) the main thread's event queue starves and the system
// watchdog kills the app (THREAD_BLOCK_6S).
const PAUSE_MS = 20;
const VARIANTS = ['arkInterop', 'arktsRuntime'];

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

/** Dumping a heap snapshot runs a full collection; queued handle releases run in between. */
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

  aboutToAppear(): void {
    setTimeout(() => this.runAll(), 500);
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
            runs.push(await measure(name, variant));
            await sleep(PAUSE_MS);
          }
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
      Text('benchmark | N | ark_interop ns/op | arkts_runtime ns/op | ratio | heap KB').fontSize(11)
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
