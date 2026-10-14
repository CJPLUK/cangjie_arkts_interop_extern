// Loaded by the step 8 device tests with `ArkTSRuntime.requireArkModule`; nothing imports it,
// so it is listed in `arkOptions.runtimeOnly.sources` in entry/build-profile.json5.

export const moduleName: string = 'TestModule';

export function add(a: number, b: number): number {
  return a + b;
}
