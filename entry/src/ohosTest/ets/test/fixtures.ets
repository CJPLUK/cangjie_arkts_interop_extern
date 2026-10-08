// ArkTS objects passed to Cangjie device scenarios. Cangjie changes them through the runtime
// under test; the tests then check the effect with plain ArkTS code.

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

export class Calculator {
  add(a: number, b: number): number {
    return a + b;
  }

  addBig(a: bigint, b: bigint): bigint {
    return a + b;
  }
}

// Records the `this` and arguments of its last call, to check receivers and argument types.
export class CallRecorder {
  lastThis: Object | undefined = undefined;
  lastArgTypes: string[] = [];
  calls: number = 0;

  record(self: Object | undefined, args: Object[]): void {
    this.lastThis = self;
    this.lastArgTypes = args.map((a: Object) => typeof a);
    this.calls++;
  }
}

// Counts reads of `target`, to check that a receiver is evaluated exactly once.
export class CountingHolder {
  reads: number = 0;
  private value: Object;

  constructor(value: Object) {
    this.value = value;
  }

  get target(): Object {
    this.reads++;
    return this.value;
  }
}

export class Thrower {
  boom(): void {
    throw new Error('boom');
  }
}
