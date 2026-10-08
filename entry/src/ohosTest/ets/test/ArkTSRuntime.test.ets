import { describe, it, expect } from '@ohos/hypium';
import { runArkTSTest, runArkTSTestOffThread, listArkTSTests } from 'libohos_app_cangjie_entry.so';
import { Rectangle } from './fixtures';

export default function arkTSRuntimeTest() {
  describe('Step0_Infrastructure', () => {
    it('trivialScenarioPasses', 0, () => {
      expect(runArkTSTest('step0.trivial')).assertEqual('');
    });

    it('scenariosAreListed', 0, () => {
      expect(JSON.stringify(listArkTSTests())).assertEqual(JSON.stringify([
        'step0.trivial',
        'step0.readFixture',
        'step0.writeFixture',
        'step0.reportsFailure',
        'step0.reportsException',
        'step0.expectThrowsHelper',
        'step1.notBoundExceptionNames',
        'step1.alreadyBoundExceptionNames',
        'step1.evalStub',
        'step1.dynamicSyntaxReachesEval',
        'step1.toExternStub',
        'step1.implicitConversionReachesToExtern',
        'step1.fromExternStub',
        'step1.extendHelperReachable',
        'step1.internalVisibleToSubpackage',
        'step2.runtimeIsBound',
        'step2.runtimeBoundToCallerContext',
        'step2.runtimeRebindThrows',
        'step2.concurrentRebindAllThrow',
        'step3.runOnJSThreadReturnsValue',
        'step3.runOnJSThreadUsesEngine',
        'step3.runOnJSThreadPropagatesException',
        'step3.runOnJSThreadNested',
        'step3.runOffThreadReturnsValue',
        'step3.runOffThreadUsesEngine',
        'step3.runOffThreadRethrows',
        'step3.runOffThreadNested',
        'step3.runFromManyThreads'
      ]));
    });

    it('unknownScenarioIsReported', 0, () => {
      expect(runArkTSTest('step0.doesNotExist')).assertEqual("unknown scenario 'step0.doesNotExist'");
    });

    it('unknownOffThreadScenarioIsReported', 0, async (done: Function) => {
      expect(await runArkTSTestOffThread('step0.doesNotExist')).assertEqual("unknown scenario 'step0.doesNotExist'");
      done();
    });

    it('failureMessageIsReturned', 0, () => {
      expect(runArkTSTest('step0.reportsFailure')).assertEqual('deliberate: expected 2, got 1');
    });

    it('exceptionBecomesFailureMessage', 0, () => {
      expect(runArkTSTest('step0.reportsException')).assertContain('deliberate');
    });

    it('expectThrowsHelper', 0, () => {
      expect(runArkTSTest('step0.expectThrowsHelper')).assertEqual('');
    });

    it('fixtureReachesCangjie', 0, () => {
      expect(runArkTSTest('step0.readFixture', new Rectangle(3, 4))).assertEqual('');
    });

    it('missingFixtureIsReported', 0, () => {
      expect(runArkTSTest('step0.readFixture')).assertContain('expects fixture #0');
    });

    it('cangjieChangeIsVisibleInArkTS', 0, () => {
      const rect = new Rectangle(3, 4);
      expect(runArkTSTest('step0.writeFixture', rect)).assertEqual('');
      expect(rect.width).assertEqual(5);
      expect(rect.area()).assertEqual(20);
    });
  });

  describe('Step1_Skeleton', () => {
    it('notBoundExceptionNames', 0, () => {
      expect(runArkTSTest('step1.notBoundExceptionNames')).assertEqual('');
    });

    it('alreadyBoundExceptionNames', 0, () => {
      expect(runArkTSTest('step1.alreadyBoundExceptionNames')).assertEqual('');
    });

    it('evalStub', 0, () => {
      expect(runArkTSTest('step1.evalStub')).assertEqual('');
    });

    it('dynamicSyntaxReachesEval', 0, () => {
      expect(runArkTSTest('step1.dynamicSyntaxReachesEval')).assertEqual('');
    });

    it('toExternStub', 0, () => {
      expect(runArkTSTest('step1.toExternStub')).assertEqual('');
    });

    it('implicitConversionReachesToExtern', 0, () => {
      expect(runArkTSTest('step1.implicitConversionReachesToExtern')).assertEqual('');
    });

    it('fromExternStub', 0, () => {
      expect(runArkTSTest('step1.fromExternStub')).assertEqual('');
    });

    it('extendHelperReachable', 0, () => {
      expect(runArkTSTest('step1.extendHelperReachable')).assertEqual('');
    });

    it('internalVisibleToSubpackage', 0, () => {
      expect(runArkTSTest('step1.internalVisibleToSubpackage')).assertEqual('');
    });
  });

  describe('Step2_Binding', () => {
    it('runtimeIsBound', 0, () => {
      expect(runArkTSTest('step2.runtimeIsBound')).assertEqual('');
    });

    it('runtimeBoundToCallerContext', 0, () => {
      expect(runArkTSTest('step2.runtimeBoundToCallerContext')).assertEqual('');
    });

    it('runtimeRebindThrows', 0, () => {
      expect(runArkTSTest('step2.runtimeRebindThrows')).assertEqual('');
    });

    it('concurrentRebindAllThrow', 0, () => {
      expect(runArkTSTest('step2.concurrentRebindAllThrow')).assertEqual('');
    });
  });

  // The off-thread scenarios run on a spawned Cangjie thread and resolve a promise; the JS
  // thread must stay free meanwhile, because `run` posts the operations to it.
  describe('Step3_Run', () => {
    it('runOnJSThreadReturnsValue', 0, () => {
      expect(runArkTSTest('step3.runOnJSThreadReturnsValue')).assertEqual('');
    });

    it('runOnJSThreadUsesEngine', 0, () => {
      expect(runArkTSTest('step3.runOnJSThreadUsesEngine')).assertEqual('');
    });

    it('runOnJSThreadPropagatesException', 0, () => {
      expect(runArkTSTest('step3.runOnJSThreadPropagatesException')).assertEqual('');
    });

    it('runOnJSThreadNested', 0, () => {
      expect(runArkTSTest('step3.runOnJSThreadNested')).assertEqual('');
    });

    it('runOffThreadReturnsValue', 0, async (done: Function) => {
      expect(await runArkTSTestOffThread('step3.runOffThreadReturnsValue')).assertEqual('');
      done();
    });

    it('runOffThreadUsesEngine', 0, async (done: Function) => {
      expect(await runArkTSTestOffThread('step3.runOffThreadUsesEngine')).assertEqual('');
      done();
    });

    it('runOffThreadRethrows', 0, async (done: Function) => {
      expect(await runArkTSTestOffThread('step3.runOffThreadRethrows')).assertEqual('');
      done();
    });

    it('runOffThreadNested', 0, async (done: Function) => {
      expect(await runArkTSTestOffThread('step3.runOffThreadNested')).assertEqual('');
      done();
    });

    it('runFromManyThreads', 0, async (done: Function) => {
      expect(await runArkTSTestOffThread('step3.runFromManyThreads')).assertEqual('');
      done();
    });
  });
}
