class C {
  d: number = 1.25;
}

class B {
  c: C = new C();
}

class A {
  b: B = new B();
}

export class Target {
  num: number = 1.5;
  a: A = new A();
  items: number[] = [];
  str: string = 'x'.repeat(100);
  short: string = 'abcdefghij';
  long: string = 'x'.repeat(10000);
  slot: Object | null | undefined = undefined;
  x: number = 0;
  y: number = 0;
  z: number = 0;

  constructor() {
    for (let i = 0; i < 1000; i++) {
      this.items.push(i * 0.5);
    }
  }

  m0(): number {
    return 1;
  }

  m1(a: number): number {
    return a;
  }

  m3(a: number, b: number, c: number): number {
    return a + b + c;
  }
}

export function f1(a: number): number {
  return a;
}

export function thrower(): void {
  throw new Error('bench');
}

/** Calls `f` `n` times from ArkTS. */
export function callTimes(f: (x: number) => number, n: number): number {
  let sum = 0;
  for (let i = 0; i < n; i++) {
    sum += f(i);
  }
  return sum;
}

// Read from Cangjie with ArkTSRuntime.global().Bench (and context.global in the ark_interop
// variants).
globalThis.Bench = { target: new Target(), f1, thrower, callTimes };
