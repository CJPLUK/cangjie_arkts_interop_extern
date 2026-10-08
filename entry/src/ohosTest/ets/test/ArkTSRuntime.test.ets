import { describe, it, expect } from '@ohos/hypium';
import { runArkTSTest, listArkTSTests } from 'libohos_app_cangjie_entry.so';
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
        'step2.concurrentRebindAllThrow'
      ]));
    });

    it('unknownScenarioIsReported', 0, () => {
      expect(runArkTSTest('step0.doesNotExist')).assertEqual("unknown scenario 'step0.doesNotExist'");
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
}
