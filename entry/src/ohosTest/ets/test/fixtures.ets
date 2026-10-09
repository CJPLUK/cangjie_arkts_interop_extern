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

// Last call of `Target.record`: its `this` and the `typeof` of each argument.
export class CallLog {
  self: Object | undefined = undefined;
  argTypes: string[] = [];
  calls: number = 0;
}

export const callLog: CallLog = new CallLog();

export class Leaf {
  c: number = 42;
}

export class Branch {
  b: Leaf = new Leaf();
}

// Fields of every kind for member, index and compound-assignment scenarios.
export class Target {
  num: number = 1.5;
  str: string = 'héllo';
  big: bigint = 10n;
  flag: boolean = true;
  zero: number = 0;
  nothing: Object | undefined = undefined;
  nul: Object | null = null;
  a: Branch = new Branch();
  items: number[] = [10, 20, 30];
  keyName: string = 'num';
  one: number = 1;
  half: number = 1.5;
  list: Object[] = [];

  record(...args: Object[]): number {
    callLog.self = this;
    callLog.argTypes = args.map((arg: Object) => typeof arg);
    callLog.calls++;
    return args.length;
  }
}

// Getters that log their reads, to check evaluation order.
export class OrderLog {
  order: string[] = [];
  private store: number[] = [0, 0];

  get target(): number[] {
    this.order.push('target');
    return this.store;
  }

  get index(): number {
    this.order.push('index');
    return 1;
  }

  get value(): number {
    this.order.push('value');
    return 5;
  }

  get stored(): number[] {
    return this.store;
  }
}

export class Thrower {
  boom(): void {
    throw new Error('boom');
  }
}
