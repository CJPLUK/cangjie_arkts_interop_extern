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

// Fields of every kind for member and index scenarios.
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

// One field per JS kind and boundary, read by Cangjie with `fromExtern`.
export class Values {
  bool: boolean = true;
  int8Min: number = -128;
  int8Max: number = 127;
  uint32Max: number = 4294967295;
  n300: number = 300;
  int64Min: bigint = -9223372036854775808n;
  int64Max: bigint = 9223372036854775807n;
  uint64Max: bigint = 18446744073709551615n;
  big: bigint = 123456789012345678901234567890n;
  float: number = 0.1;
  nan: number = NaN;
  inf: number = Infinity;
  negInf: number = -Infinity;
  negZero: number = -0;
  empty: string = '';
  text: string = 'héllo 日本 😀';
  five: string = '5';
  undef: Object | undefined = undefined;
  nul: Object | null = null;
  nested: number[][] = [[1, 2], [], [3]];
  optional: (number | undefined)[] = [1, undefined, 3];
  mixed: (string | number | boolean | null)[] = ['a', 1.5, true, null];
  obj: Rectangle = new Rectangle(1, 2);
}

// Each way JS code can throw, for the step 7 scenarios.
export class Thrower {
  missing: Object | undefined = undefined;
  calls: number = 0;

  boom(): void {
    this.calls++;
    throw new Error('boom');
  }

  // ArkTS only allows throwing Errors; the cast is type-only, so a plain string is thrown.
  throwString(): void {
    throw 'boom string' as Object as Error;
  }

  // Calls `undefined`: the engine itself raises a TypeError.
  typeError(): void {
    (this.missing as () => void)();
  }

  get failingGetter(): number {
    throw new Error('boom getter');
  }
}
