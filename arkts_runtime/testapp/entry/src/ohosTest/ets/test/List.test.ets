import abilityTest from './Ability.test';
import arkTSRuntimeTest from './ArkTSRuntime.test';
import lifetimeTest from './Lifetime.test';
import diffTest from './Diff.test';

export default function testsuite() {
  abilityTest();
  arkTSRuntimeTest();
  lifetimeTest();
  diffTest();
}
