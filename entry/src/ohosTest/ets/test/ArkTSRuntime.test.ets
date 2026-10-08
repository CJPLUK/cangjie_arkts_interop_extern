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
        'step0.reportsException'
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
}
