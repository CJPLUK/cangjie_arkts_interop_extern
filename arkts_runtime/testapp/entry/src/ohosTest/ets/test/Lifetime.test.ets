import { describe, it, expect } from '@ohos/hypium';
import { runArkTSTest } from 'libohos_app_cangjie_entry.so';
import { Target } from './fixtures';

export default function lifetimeTest() {
  describe('Lifetime', () => {
    it('pinReadAlias', 0, () => {
      expect(runArkTSTest('lifetime.pinReadAlias')).assertEqual('');
    });
    it('fusedOpsSpill', 0, () => {
      expect(runArkTSTest('lifetime.fusedOpsSpill', new Target())).assertEqual('');
    });
    it('newScopeRestoresBudget', 0, () => {
      expect(runArkTSTest('lifetime.newScopeRestoresBudget', new Target())).assertEqual('');
    });
    it('repeatedReadReusesPin', 0, () => {
      expect(runArkTSTest('lifetime.repeatedReadReusesPin', new Target())).assertEqual('');
    });
    it('textCopies', 0, () => {
      expect(runArkTSTest('lifetime.textCopies', new Target())).assertEqual('');
    });
    it('optionImmediates', 0, () => {
      expect(runArkTSTest('lifetime.optionImmediates', new Target())).assertEqual('');
    });
    it('userInterfaceOnScalar', 0, () => {
      expect(runArkTSTest('lifetime.userInterfaceOnScalar', new Target())).assertEqual('');
    });
    it('budgetFillsThenResets', 0, async () => {
      expect(runArkTSTest('lifetime.budgetFillsThenScoped', new Target())).assertEqual('');
      await new Promise<void>((resolve) => setTimeout(resolve, 20));
      expect(runArkTSTest('lifetime.budgetIsEmpty')).assertEqual('');
    });
  });
}
