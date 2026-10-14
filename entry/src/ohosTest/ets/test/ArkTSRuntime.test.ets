import { describe, it, expect } from '@ohos/hypium';
import { runArkTSTest, runArkTSTestOffThread, listArkTSTests } from 'libohos_app_cangjie_entry.so';
import { hidebug, hilog } from '@kit.PerformanceAnalysisKit';
import { Rectangle, Target, CallLog, callLog, CountingHolder, OrderLog, Values, Thrower } from './fixtures';
import { globalObject, frozenObject, describeProperty } from './jsHelpers';

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
        'step1.dynamicSyntaxReachesEval',
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
        'step5.memberRead',
        'step5.primitiveReceivers',
        'step5.memberUpdate',
        'step5.memberOfUndefinedOrNull',
        'step5.methodCallThis',
        'step5.freeCallThisUndefined',
        'step5.indexCallThis',
        'step5.receiverEvaluatedOnce',
        'step5.argumentTypes',
        'step5.callNonFunction',
        'step5.indexReadWrite',
        'step5.indexBoundaries',
        'step5.nonArrayIndexing',
        'step5.unsupportedIndex',
        'step5.indexWriteOrder',
        'step5.compoundAssignmentOrder',
        'step5.compoundOperators',
        'step5.stringConversions',
        'step5.compoundThroughSyntax',
        'step5.logicalAssignment',
        'step5.compoundReceiverOnce',
        'step5.compoundErrors',
        'step5.variableCompoundIsMethodCall',
        'step5.evalPayloadUnchanged',
        'step5.derivedConstructor',
        'step5.longChainLoop',
        'step6.toExternTypes',
        'step6.fromExternTypes',
        'step6.roundTrip',
        'step6.largeValues',
        'step6.externInputs',
        'step6.conversionFailures',
        'step6.implicitConversion',
        'step7.arkInteropJSException',
        'step7.jsThrowsBecomeForeignRuntimeException',
        'step7.ownExceptionsNotWrapped',
        'step7.usableAfterJSException',
        'step8.undefinedAndNull',
        'step8.objectIsFresh',
        'step8.globalIsGlobalThis',
        'step8.symbols',
        'step8.strictEqualTable',
        'step8.objectProperties',
        'step8.defineOwnProperty',
        'step8.requireArkModule',
        'step8.requireSystemNativeModule',
        'step9.designExample',
        'step9.mixedScenario',
        'step3.runOffThreadReturnsValue',
        'step3.runOffThreadUsesEngine',
        'step3.runOffThreadRethrows',
        'step3.runOffThreadNested',
        'step3.runFromManyThreads',
        'step4.retainedValueCrossesThreads',
        'step4.releaseHandlesFromOtherThread',
        'step5.evalFromOtherThread',
        'step6.conversionsFromOtherThread',
        'step7.jsExceptionFromOtherThread',
        'step8.helpersFromOtherThread',
        'step9.mixedScenarioOffThread'
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

    it('dynamicSyntaxReachesEval', 0, () => {
      expect(runArkTSTest('step1.dynamicSyntaxReachesEval')).assertEqual('');
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

  describe('Step5_Evaluation', () => {
    it('memberRead', 0, () => {
      expect(runArkTSTest('step5.memberRead', new Target())).assertEqual('');
    });

    it('primitiveReceivers', 0, () => {
      const t = new Target();
      expect(runArkTSTest('step5.primitiveReceivers', t)).assertEqual('');
      expect(t.str).assertEqual('héllo');
    });

    it('memberUpdate', 0, () => {
      const t = new Target();
      expect(runArkTSTest('step5.memberUpdate', t)).assertEqual('');
      expect(t.num).assertEqual(7);
      expect(t.a.b.c).assertEqual(99);
      expect(t.str).assertEqual('set');
    });

    it('memberOfUndefinedOrNull', 0, () => {
      expect(runArkTSTest('step5.memberOfUndefinedOrNull', new Target())).assertEqual('');
    });

    it('methodCallThis', 0, () => {
      const t = new Target();
      resetCallLog();
      expect(runArkTSTest('step5.methodCallThis', t, callLog)).assertEqual('');
      expect(callLog.self === t).assertTrue();
      expect(callLog.calls).assertEqual(1);
    });

    it('freeCallThisUndefined', 0, () => {
      resetCallLog();
      expect(runArkTSTest('step5.freeCallThisUndefined', new Target(), callLog)).assertEqual('');
      expect(callLog.self === undefined).assertTrue();
    });

    it('indexCallThis', 0, () => {
      const t = new Target();
      resetCallLog();
      expect(runArkTSTest('step5.indexCallThis', t, callLog)).assertEqual('');
      expect(callLog.self === t.list).assertTrue();
      expect(callLog.calls).assertEqual(2);
    });

    it('receiverEvaluatedOnce', 0, () => {
      const holder = new CountingHolder(new Target());
      expect(runArkTSTest('step5.receiverEvaluatedOnce', holder)).assertEqual('');
      expect(holder.reads).assertEqual(1);
    });

    it('argumentTypes', 0, () => {
      resetCallLog();
      expect(runArkTSTest('step5.argumentTypes', new Target(), callLog, new Rectangle(1, 2))).assertEqual('');
      expect(JSON.stringify(callLog.argTypes)).assertEqual(
        JSON.stringify(['bigint', 'number', 'boolean', 'string', 'bigint', 'number', 'object']));
    });

    it('callNonFunction', 0, () => {
      expect(runArkTSTest('step5.callNonFunction', new Target())).assertEqual('');
    });

    it('indexReadWrite', 0, () => {
      const t = new Target();
      expect(runArkTSTest('step5.indexReadWrite', t)).assertEqual('');
      expect(JSON.stringify(t.items)).assertEqual(JSON.stringify([55, 77, 99]));
      expect(t.str).assertEqual('via string');
      expect(t.num).assertEqual(4);
    });

    it('indexBoundaries', 0, () => {
      const items: number[] = [10, 20, 30];
      expect(runArkTSTest('step5.indexBoundaries', items)).assertEqual('');
      expect(items.length).assertEqual(4294967295);
      expect(items[-1]).assertEqual(5);
      expect(items[4294967295]).assertEqual(7);
      expect(items[4294967294]).assertEqual(9);
      expect(items[0]).assertEqual(10);
    });

    it('nonArrayIndexing', 0, () => {
      const m = new Map<number, string>([[0, 'zero']]);
      const u8 = new Uint8Array([1, 2, 3, 4]);
      expect(runArkTSTest('step5.nonArrayIndexing', m, u8)).assertEqual('');
      expect(m.size).assertEqual(1);
      expect(m.get(0)).assertEqual('zero');
      expect(JSON.stringify(Array.from(u8))).assertEqual(JSON.stringify([1, 44, 3, 4]));
    });

    it('unsupportedIndex', 0, () => {
      expect(runArkTSTest('step5.unsupportedIndex', new Target())).assertEqual('');
    });

    it('indexWriteOrder', 0, () => {
      const log = new OrderLog();
      expect(runArkTSTest('step5.indexWriteOrder', log)).assertEqual('');
      expect(JSON.stringify(log.order)).assertEqual(JSON.stringify(['target', 'index', 'value']));
      expect(log.stored[1]).assertEqual(5);
    });

    it('compoundAssignmentOrder', 0, () => {
      const log = new OrderLog();
      expect(runArkTSTest('step5.compoundAssignmentOrder', log)).assertEqual('');
      expect(JSON.stringify(log.order)).assertEqual(JSON.stringify(['target', 'index', 'value']));
      expect(log.stored[1]).assertEqual(5);
    });

    it('compoundOperators', 0, () => {
      const t = new Target();
      expect(runArkTSTest('step5.compoundOperators', t)).assertEqual('');
      expect(t.big).assertEqual(225n);
      expect(t.str).assertEqual('a1.52');
    });

    it('stringConversions', 0, () => {
      expect(runArkTSTest('step5.stringConversions', new Target())).assertEqual('');
    });

    it('compoundThroughSyntax', 0, () => {
      const t = new Target();
      expect(runArkTSTest('step5.compoundThroughSyntax', t)).assertEqual('');
      expect(t.num).assertEqual(2.5);
      expect(t.items[0]).assertEqual(11);
    });

    it('logicalAssignment', 0, () => {
      const t = new Target();
      const log = new OrderLog();
      expect(runArkTSTest('step5.logicalAssignment', t, log)).assertEqual('');
      expect(t.flag as Object).assertEqual('yes');
      expect(t.zero).assertEqual(5);
      expect(t.num).assertEqual(1.5);
      expect(JSON.stringify(log.order)).assertEqual(JSON.stringify(['value']));
    });

    it('compoundReceiverOnce', 0, () => {
      const t = new Target();
      const holder = new CountingHolder(t);
      expect(runArkTSTest('step5.compoundReceiverOnce', holder)).assertEqual('');
      expect(holder.reads).assertEqual(1);
      expect(t.num).assertEqual(2.5);
    });

    it('compoundErrors', 0, () => {
      expect(runArkTSTest('step5.compoundErrors', new Target())).assertEqual('');
    });

    it('variableCompoundIsMethodCall', 0, () => {
      expect(runArkTSTest('step5.variableCompoundIsMethodCall', new Target())).assertEqual('');
    });

    it('evalPayloadUnchanged', 0, () => {
      expect(runArkTSTest('step5.evalPayloadUnchanged', new Rectangle(1, 2))).assertEqual('');
    });

    it('derivedConstructor', 0, () => {
      const t = new Target();
      expect(runArkTSTest('step5.derivedConstructor', t)).assertEqual('');
      expect(t.num).assertEqual(2);
      expect(t.zero).assertEqual(3);
    });

    it('longChainLoop', 0, () => {
      expect(runArkTSTest('step5.longChainLoop', new Target())).assertEqual('');
    });

    it('evalFromOtherThread', 0, async (done: Function) => {
      expect(await runArkTSTestOffThread('step5.evalFromOtherThread')).assertEqual('');
      done();
    });
  });

  describe('Step6_Conversions', () => {
    // [field, typeof, String(value)] for each value stored by step6.toExternTypes.
    it('toExternTypes', 0, () => {
      const sink: Record<string, Object | null | undefined> = {};
      const rect = new Rectangle(1, 2);
      expect(runArkTSTest('step6.toExternTypes', sink, rect)).assertEqual('');
      const rows: string[][] = [
        ['unit', 'undefined', 'undefined'],
        ['bool', 'boolean', 'true'],
        ['int8Min', 'number', '-128'],
        ['int8Max', 'number', '127'],
        ['int16', 'number', '-32768'],
        ['int32', 'number', '2147483647'],
        ['uint8', 'number', '255'],
        ['uint16', 'number', '65535'],
        ['uint32Max', 'number', '4294967295'],
        ['int64Min', 'bigint', '-9223372036854775808'],
        ['int64Max', 'bigint', '9223372036854775807'],
        ['uint64Max', 'bigint', '18446744073709551615'],
        ['float16', 'number', '0.0999755859375'],
        ['float32', 'number', '1.100000023841858'],
        ['float64', 'number', '0.1'],
        ['nan', 'number', 'NaN'],
        ['inf', 'number', 'Infinity'],
        ['negInf', 'number', '-Infinity'],
        ['negZero', 'number', '0'],
        ['bigint', 'bigint', '123456789012345678901234567890'],
        ['emptyString', 'string', ''],
        ['text', 'string', 'héllo 日本 😀'],
        ['some', 'number', '7'],
        ['none', 'undefined', 'undefined'],
        ['emptyArray', 'object', ''],
        ['int64Array', 'object', '1,2']
      ];
      for (const row of rows) {
        expect(`${row[0]}: ${typeof sink[row[0]]} ${String(sink[row[0]])}`).assertEqual(`${row[0]}: ${row[1]} ${row[2]}`);
      }
      expect(Object.keys(sink).includes('unit')).assertTrue();
      expect(1 / (sink['negZero'] as number)).assertEqual(-Infinity);
      expect(Array.isArray(sink['emptyArray'])).assertTrue();
      expect(typeof (sink['int64Array'] as bigint[])[0]).assertEqual('bigint');
      expect(JSON.stringify(sink['nested'])).assertEqual('[[1],[2,3]]');
      const options = sink['optionArray'] as (number | undefined)[];
      expect(options.length).assertEqual(2);
      expect(options[0]).assertEqual(1.5);
      expect(options[1] === undefined).assertTrue();
      const mixed = sink['mixed'] as Object[];
      expect(mixed.length).assertEqual(4);
      expect(mixed[0] as string).assertEqual('a');
      expect(mixed[1] === rect).assertTrue();
      expect(mixed[2] as number).assertEqual(1.5);
      expect(mixed[3] === undefined).assertTrue();
    });

    it('fromExternTypes', 0, () => {
      expect(runArkTSTest('step6.fromExternTypes', new Values())).assertEqual('');
    });

    it('roundTrip', 0, () => {
      expect(runArkTSTest('step6.roundTrip')).assertEqual('');
    });

    it('largeValues', 0, () => {
      const sink: Record<string, Object | null | undefined> = {};
      expect(runArkTSTest('step6.largeValues', sink)).assertEqual('');
      const text = sink['longString'] as string;
      expect(text.length).assertEqual(1 << 20);
      expect(text.charAt(12345)).assertEqual('é');
      const numbers = sink['bigArray'] as number[];
      expect(numbers.length).assertEqual(100000);
      expect(numbers[99999]).assertEqual(99999);
    });

    it('externInputs', 0, () => {
      expect(runArkTSTest('step6.externInputs', new Target())).assertEqual('');
    });

    it('conversionFailures', 0, () => {
      expect(runArkTSTest('step6.conversionFailures', new Values())).assertEqual('');
    });

    it('implicitConversion', 0, () => {
      const sink: Record<string, Object | null | undefined> = {};
      expect(runArkTSTest('step6.implicitConversion', sink)).assertEqual('');
      expect(typeof sink['implicit']).assertEqual('bigint');
      expect(sink['implicit'] === 42n).assertTrue();
      const items = sink['implicitArray'] as Object[];
      expect(items.length).assertEqual(2);
      expect(items[0] === 1n).assertTrue();
      expect(items[1] as string).assertEqual('a');
    });

    it('conversionsFromOtherThread', 0, async (done: Function) => {
      expect(await runArkTSTestOffThread('step6.conversionsFromOtherThread')).assertEqual('');
      done();
    });
  });

  describe('Step7_VMExceptions', () => {
    it('arkInteropJSException', 0, () => {
      expect(runArkTSTest('step7.arkInteropJSException', new Thrower())).assertEqual('');
    });

    it('jsThrowsBecomeForeignRuntimeException', 0, () => {
      expect(runArkTSTest('step7.jsThrowsBecomeForeignRuntimeException', new Thrower())).assertEqual('');
    });

    it('ownExceptionsNotWrapped', 0, () => {
      expect(runArkTSTest('step7.ownExceptionsNotWrapped', new Target())).assertEqual('');
    });

    it('usableAfterJSException', 0, () => {
      const t = new Thrower();
      expect(runArkTSTest('step7.usableAfterJSException', t)).assertEqual('');
      expect(t.calls).assertEqual(2);
    });

    it('jsExceptionFromOtherThread', 0, async (done: Function) => {
      expect(await runArkTSTestOffThread('step7.jsExceptionFromOtherThread')).assertEqual('');
      done();
    });
  });

  describe('Step8_Helpers', () => {
    it('undefinedAndNull', 0, () => {
      const sink: Record<string, Object | null | undefined> = {};
      expect(runArkTSTest('step8.undefinedAndNull', sink, new Rectangle(1, 2))).assertEqual('');
      expect(Object.keys(sink).includes('u')).assertTrue();
      expect(sink['u'] === undefined).assertTrue();
      expect(sink['n'] === null).assertTrue();
    });

    it('objectIsFresh', 0, () => {
      const sink: Record<string, Object | null | undefined> = {};
      expect(runArkTSTest('step8.objectIsFresh', sink)).assertEqual('');
      expect(typeof sink['o1']).assertEqual('object');
      expect(Object.keys(sink['o1'] as Object).length).assertEqual(0);
      expect(sink['o1'] !== sink['o2']).assertTrue();
    });

    it('globalIsGlobalThis', 0, () => {
      expect(runArkTSTest('step8.globalIsGlobalThis', globalObject())).assertEqual('');
    });

    it('symbols', 0, () => {
      const sink: Record<string, Object | null | undefined> = {};
      expect(runArkTSTest('step8.symbols', sink)).assertEqual('');
      expect(typeof sink['s1']).assertEqual('symbol');
      expect(String(sink['s1'])).assertEqual('Symbol(d)');
      expect(sink['s1'] !== sink['s2']).assertTrue();
      expect(String(sink['plain'])).assertEqual('Symbol()');
    });

    it('strictEqualTable', 0, () => {
      const rect = new Rectangle(1, 2);
      const pairs: (Object | null | undefined)[][] = [
        [rect, rect], [rect, new Rectangle(1, 2)], [1.5, 1.5], [NaN, NaN], [0, -0], ['ab', 'a'.concat('b')],
        [1n, 1n], [1, 1n], [1, '1'], [undefined, null], [null, null], [undefined, undefined], [true, true]
      ];
      const expected = pairs.map((p: (Object | null | undefined)[]) => p[0] === p[1]);
      expect(runArkTSTest('step8.strictEqualTable', pairs, expected, rect)).assertEqual('');
    });

    it('objectProperties', 0, () => {
      expect(runArkTSTest('step8.objectProperties', new Rectangle(1, 2), [1, 2])).assertEqual('');
    });

    it('defineOwnProperty', 0, () => {
      const sink: Record<string, Object | null | undefined> = {};
      expect(runArkTSTest('step8.defineOwnProperty', sink, frozenObject())).assertEqual('');
      for (const name of ['WEC', 'WEc', 'WeC', 'Wec', 'wEC', 'wEc', 'weC', 'wec']) {
        const value = name == 'WEC' ? 'again' : name;
        expect(describeProperty(sink, name)).assertEqual(`${value} ${name}`);
      }
    });

    it('requireArkModule', 0, () => {
      expect(runArkTSTest('step8.requireArkModule')).assertEqual('');
    });

    it('requireSystemNativeModule', 0, () => {
      expect(runArkTSTest('step8.requireSystemNativeModule')).assertEqual('');
    });

    it('helpersFromOtherThread', 0, async (done: Function) => {
      expect(await runArkTSTestOffThread('step8.helpersFromOtherThread')).assertEqual('');
      done();
    });
  });

  // The same scenarios run from the smoke page in entry/src/main/ets/pages/Index.ets.
  describe('Step9_EndToEnd', () => {
    it('designExample', 0, () => {
      const sink: Record<string, Object | null | undefined> = {};
      expect(runArkTSTest('step9.designExample', sink)).assertEqual('');
      const rect = sink['rect'] as Rectangle;
      expect(rect.width).assertEqual(5);
      expect(rect.area()).assertEqual(25);
    });

    it('mixedScenario', 0, () => {
      const start = Date.now();
      expect(runArkTSTest('step9.mixedScenario')).assertEqual('');
      hilog.info(0, 'ArkTSRuntimeTest', 'mixedScenario: 1000 iterations in %{public}d ms', Date.now() - start);
    });

    it('mixedScenarioOffThread', 0, async (done: Function) => {
      const start = Date.now();
      expect(await runArkTSTestOffThread('step9.mixedScenarioOffThread')).assertEqual('');
      hilog.info(0, 'ArkTSRuntimeTest', 'mixedScenarioOffThread: 100 iterations in %{public}d ms', Date.now() - start);
      done();
    });
  });
}

function resetCallLog(): void {
  callLog.self = undefined;
  callLog.argTypes = [];
  callLog.calls = 0;
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
