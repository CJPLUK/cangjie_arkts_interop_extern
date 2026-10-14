// Loaded with `ArkTSRuntime.requireArkModule` by the step 8 and step 9 device tests and by the
// smoke page. Nothing imports it at build time, so it is listed in
// `arkOptions.runtimeOnly.sources` in entry/build-profile.json5.

export const moduleName: string = 'TestModule';

export function add(a: number, b: number): number {
  return a + b;
}

export class Rectangle {
  width: number;
  height: number;

  constructor(width: number, height: number) {
    this.width = width;
    this.height = height;
  }

  area(): number {
    return this.width * this.height;
  }
}

// The `createRectangle` of the design's section 1 example (height 5).
export function createRectangle(): Rectangle {
  return new Rectangle(0, 5);
}
