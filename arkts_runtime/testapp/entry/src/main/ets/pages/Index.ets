import { testCJ, runArkTSTest, runArkTSTestOffThread } from 'libohos_app_cangjie_entry.so';
import { Rectangle } from '../arkts/TestModule';

// Smoke check for the ArkTS runtime without the test runner: runs the step 9 scenarios (the
// design example and the mixed scenario using every feature) and shows one line per scenario.
@Entry
@Component
struct Index {
  @State message: string = 'Hello World';
  @State report: string = '';
  @State running: boolean = false;

  build() {
    Column({ space: 16 }) {
      Text(this.message)
        .fontSize(40)
        .fontWeight(FontWeight.Bold)
        .onClick(() => {
          this.message = testCJ('Cangjie');
        })
      Button(this.running ? 'Running…' : 'Run ArkTS runtime smoke tests')
        .enabled(!this.running)
        .onClick(() => {
          this.runSmokeTests();
        })
      Text(this.report)
        .fontSize(14)
        .fontFamily('monospace')
        .width('90%')
    }
    .height('100%')
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  async runSmokeTests(): Promise<void> {
    this.running = true;
    this.report = '';
    const lines: string[] = [];
    lines.push(this.check('step9.designExample', () => {
      const sink: Record<string, Object | null | undefined> = {};
      const failure = runArkTSTest('step9.designExample', sink);
      if (failure !== '') {
        return failure;
      }
      const rect = sink['rect'] as Rectangle;
      return rect.width === 5 && rect.area() === 25 ? '' : `ArkTS sees width ${rect.width}, area ${rect.area()}`;
    }));
    lines.push(this.check('step9.mixedScenario (1000x)', () => runArkTSTest('step9.mixedScenario')));
    this.report = lines.join('\n');

    const start = Date.now();
    const failure = await runArkTSTestOffThread('step9.mixedScenarioOffThread');
    lines.push(this.line('step9.mixedScenarioOffThread (100x)', failure, Date.now() - start));
    const failed = lines.filter((l: string) => l.startsWith('FAIL')).length;
    lines.push(failed === 0 ? `ALL PASS (${lines.length})` : `${failed} FAILED`);
    this.report = lines.join('\n');
    this.running = false;
  }

  check(name: string, body: () => string): string {
    const start = Date.now();
    let failure: string;
    try {
      failure = body();
    } catch (e) {
      failure = `ArkTS exception: ${e}`;
    }
    return this.line(name, failure, Date.now() - start);
  }

  line(name: string, failure: string, ms: number): string {
    return failure === '' ? `PASS ${name} (${ms} ms)` : `FAIL ${name}: ${failure}`;
  }
}
