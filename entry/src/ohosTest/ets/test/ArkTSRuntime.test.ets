import { describe, it, expect } from '@ohos/hypium';
import { runArkTSTest, runArkTSTestOffThread, listArkTSTests } from 'libohos_app_cangjie_entry.so';
import { hidebug, hilog } from '@kit.PerformanceAnalysisKit';
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
        'step4.retainClassifiesEachKind',
        'step4.payloadRoundTrip',
        'step4.retainedValueOutlivesScope',
        'step4.rejectsForeignPayload',
        'step4.keepObject',
        'step4.checkKeptObject',
        'step4.dropKeptObject',
        'step4.releaseManyHandles',
        'step3.runOffThreadReturnsValue',
        'step3.runOffThreadUsesEngine',
        'step3.runOffThreadRethrows',
        'step3.runOffThreadNested',
        'step3.runFromManyThreads',
        'step4.retainedValueCrossesThreads',
        'step4.releaseHandlesFromOtherThread'
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

  describe('Step4_Handles', () => {
    it('retainClassifiesEachKind', 0, () => {
      expect(runArkTSTest('step4.retainClassifiesEachKind', new Rectangle(3, 4))).assertEqual('');
    });

    it('payloadRoundTrip', 0, () => {
      expect(runArkTSTest('step4.payloadRoundTrip', new Rectangle(3, 4))).assertEqual('');
    });

    it('retainedValueOutlivesScope', 0, () => {
      expect(runArkTSTest('step4.retainedValueOutlivesScope')).assertEqual('');
    });

    it('rejectsForeignPayload', 0, () => {
      expect(runArkTSTest('step4.rejectsForeignPayload')).assertEqual('');
    });

    // ArkTS keeps only WeakRefs. The control object has no other reference, so once it is gone
    // a collection has certainly run; the retained one must still be there. After Cangjie
    // drops its Extern, the retained object must be collectable too.
    it('retainedObjectSurvivesGCAndIsReleased', 0, async (done: Function) => {
      const refs = keepOneOfTwo();
      const kept = refs[0];
      const control = refs[1];
      const controlGone = await collectUntil(() => control.deref() === undefined);
      expect(controlGone ? 'control collected' : 'control never collected').assertEqual('control collected');
      expect(kept.deref() !== undefined ? 'kept alive' : 'kept collected').assertEqual('kept alive');
      checkKeptObject(kept);

      expect(runArkTSTest('step4.dropKeptObject')).assertEqual('');
      const keptGone = await collectUntil(() => kept.deref() === undefined);
      expect(keptGone ? 'kept collected after drop' : 'kept never collected after drop')
        .assertEqual('kept collected after drop');
      done();
    });

    // Measures the ArkTS heap after full collections. Measured once with the handles deliberately
    // kept: it grew ~37 MB from round 4 to round 10 on both devices; released, at most 1.7 MB.
    // Process memory (PSS) was too noisy for this.
    it('releaseManyHandles', 0, async (done: Function) => {
      const pss: number[] = [];
      const vm: number[] = [];
      for (let round = 0; round < 10; round++) {
        expect(runArkTSTest('step4.releaseManyHandles')).assertEqual('');
        if (round == 3 || round == 9) {
          await collectUntil(() => true);
          pss.push(Number(hidebug.getPss()));
          vm.push(Number(hidebug.getAppVMObjectUsedSize()));
        }
      }
      hilog.info(0, 'ArkTSRuntimeTest', 'releaseManyHandles: after rounds 4 and 10, PSS KB %{public}s, VM objects KB %{public}s',
        pss.join(' '), vm.join(' '));
      expect(vm[1] - vm[0]).assertLess(10 * 1024);
      done();
    });

    it('retainedValueCrossesThreads', 0, async (done: Function) => {
      expect(await runArkTSTestOffThread('step4.retainedValueCrossesThreads')).assertEqual('');
      done();
    });

    it('releaseHandlesFromOtherThread', 0, async (done: Function) => {
      expect(await runArkTSTestOffThread('step4.releaseHandlesFromOtherThread')).assertEqual('');
      done();
    });
  });
}

/** Two fresh Rectangles; Cangjie retains the first. Returns WeakRefs to both. */
function keepOneOfTwo(): WeakRef<Rectangle>[] {
  const kept = new Rectangle(1, 2);
  const control = new Rectangle(3, 4);
  expect(runArkTSTest('step4.keepObject', kept)).assertEqual('');
  return [new WeakRef(kept), new WeakRef(control)];
}

/** A separate function, so the caller's frame holds no strong reference to the object. */
function checkKeptObject(kept: WeakRef<Rectangle>): void {
  const rect = kept.deref() as Rectangle;
  expect(runArkTSTest('step4.checkKeptObject', rect)).assertEqual('');
  expect(rect.width).assertEqual(7);
}

/**
 * Forces full collections, yielding to the event loop in between (queued handle releases run
 * there), until `done()` holds; false after 5 rounds. Allocating garbage only triggers young
 * collections, which never cleared the WeakRefs here; dumping a heap snapshot runs a full one.
 */
async function collectUntil(done: () => boolean): Promise<boolean> {
  for (let round = 0; round < 5; round++) {
    await sleep(100);
    hidebug.dumpJsHeapData('arkts-runtime-test-gc');
    await sleep(100);
    if (done()) {
      return true;
    }
  }
  return false;
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => setTimeout(resolve, ms));
}
