
export class Log {
  lines: string[] = [];

  num(label: string, x: number): void { this.lines.push(label + '=' + fmtNum(x)); }
  str(label: string, s: string): void { this.lines.push(label + '=' + fmtStr(s)); }
  bool(label: string, b: boolean): void { this.lines.push(label + '=' + (b ? 'true' : 'false')); }
  text(label: string, t: string): void { this.lines.push(label + '=' + t); }
  render(): string { return this.lines.join('\n'); }
}

export function fmtNum(x: number): string {
  if (Number.isNaN(x)) return 'NaN';
  if (x === Infinity) return 'Inf';
  if (x === -Infinity) return '-Inf';
  if (Object.is(x, -0)) return '-0';
  if (Number.isInteger(x) && Math.abs(x) <= 9007199254740992) return BigInt(x).toString();
  const view = new DataView(new ArrayBuffer(8));
  view.setFloat64(0, x);
  return 'f' + view.getBigUint64(0).toString(16).padStart(16, '0');
}

export function fmtStr(s: string): string {
  let out = '"';
  for (const ch of s) {
    const cp = ch.codePointAt(0) as number;
    out += cp >= 0x20 && cp <= 0x7e && ch !== '"' && ch !== '\\' ? ch : '\\u{' + cp.toString(16) + '}';
  }
  return out + '"';
}

/** fromExtern<String> (and ark_interop's toString) of a lone surrogate gives a String that is not valid UTF-8. */
function convertible(s: string): boolean {
  for (const ch of s) {
    const cp = ch.codePointAt(0) as number;
    if (cp >= 0xd800 && cp <= 0xdfff) {
      return false;
    }
  }
  return true;
}

function errorText(e: any): string {
  return e instanceof Error ? e.name + '\n' + e.message : String(e);
}

function attempt(log: Log, label: string, fragment: string, contract: string | undefined, body: () => any): void {
  try {
    body();
    log.text(label, 'ok');
  } catch (e) {
    log.text(label, contract ?? 'js:' + errorText(e).includes(fragment));
  }
}

function typeOf(x: any): string {
  return x === null ? 'null' : Array.isArray(x) ? 'array' : typeof x;
}

class Counter {
  count: number = 0;

  inc(n: number): number {
    this.count += n;
    return this.count;
  }

  get double(): number { return this.count * 2; }

  set value(v: number) { this.count = v * 10; }

  static make(): Counter { return new Counter(); }
}

export interface Program {
  name: string;
  offThreadRuns?: number;
  world: () => any;
  arkts?: (w: any, log: Log) => void;
}

const DOC = '{"name":"root","n":[1,2.5,-0,1e300,null,true,"s"],"o":{"a":{"b":[[],{}]},"emoji":"\u{1F600}","esc":"q\\"t"},"empty":"","neg":-7}';

function walk(w: any, x: any): string {
  const kind: string = w.kind(x);
  if (kind === 'number') return fmtNum(x);
  if (kind === 'string') return fmtStr(x);
  if (kind === 'boolean') return x ? 'true' : 'false';
  if (kind === 'null') return 'null';
  if (kind === 'array') {
    const parts: string[] = [];
    for (let i = 0; i < x.length; i++) parts.push(walk(w, x[i]));
    return '[' + parts.join(',') + ']';
  }
  return '{' + Object.keys(x).map((k: string) => fmtStr(k) + ':' + walk(w, x[k])).join(',') + '}';
}

function copyOf(w: any, x: any): any {
  const kind: string = w.kind(x);
  if (kind === 'array') {
    const out: any[] = [];
    for (let i = 0; i < x.length; i++) out.push(copyOf(w, x[i]));
    return out;
  }
  if (kind === 'object') {
    const out: any = {};
    for (const k of Object.keys(x)) out[k] = copyOf(w, x[k]);
    return out;
  }
  return x;
}

export const PROGRAMS: Program[] = [
  {
    name: 'objectGraph',
    world: () => ({ root: { a: { b: { c: { d: 1 } } }, x: { tag: 'x' } } }),
    arkts: (w: any, log: Log) => {
      const r = w.root;
      log.num('d', r.a.b.c.d);
      r.a.b.c.d = 2.5;
      log.num('d after write', r.a.b.c.d);
      log.bool('a read twice is one object', r.a === r.a);
      const oldB = r.a.b;
      const nb: any = {};
      nb.c = {};
      nb.c.d = 7;
      r.a.b = nb;
      log.num('d via new b', r.a.b.c.d);
      log.bool('b replaced', oldB === r.a.b);
      log.num('old b still readable', oldB.c.d);
      const a = r.a;
      r.a = r.x;
      r.x = a;
      log.str('a.tag after swap', r.a.tag);
      log.num('x.b.c.d after swap', r.x.b.c.d);
      r.self = r;
      log.bool('cycle', r.self.self.self === r);
      r.x = undefined;
      log.bool('x undefined', r.x === undefined);
      log.text('keys', Object.keys(r).join(','));
    }
  },
  {
    name: 'internChurn',
    world: () => {
      const many: any[] = [];
      for (let i = 0; i < 600; i++) many.push({ child: { v: i } });
      return {
        holder: { slot: { id: 0 } },
        many: many,
        rotate(i: number): void { this.holder.slot = { id: i }; },
        mutateMany(): void { for (const m of this.many) m.child = { v: m.child.v * 2 }; }
      };
    },
    arkts: (w: any, log: Log) => {
      let sum = 0;
      let wrongId = 0;
      let sameAsBefore = 0;
      for (let i = 1; i <= 300; i++) {
        const before = w.holder.slot;
        w.rotate(i);
        const after = w.holder.slot;
        if (after.id !== i) wrongId++;
        if (before === after) sameAsBefore++;
        sum += after.id;
      }
      log.num('sum', sum);
      log.num('wrong ids', wrongId);
      log.num('same as before', sameAsBefore);
      let total = 0;
      for (let round = 0; round < 3; round++) {
        for (let k = 0; k < 600; k++) total += w.many[k].child.v;
      }
      log.num('many total', total);
      const first = w.many[0].child;
      w.mutateMany();
      total = 0;
      for (let k = 0; k < 600; k++) total += w.many[k].child.v;
      log.num('many total after JS mutation', total);
      log.bool('replaced child differs', first === w.many[0].child);
      const kept = w.many[0].child;
      for (let k = 0; k < 600; k++) total += w.many[k].child.v;
      log.bool('identity after 600 other receivers', kept === w.many[0].child);
      log.bool('different receivers differ', w.many[1].child === w.many[2].child);
      w.holder.slot = w.many[5].child;
      log.bool('slot set from another read', w.holder.slot === w.many[5].child);
      w.holder.slot = 3;
      log.num('slot as number', w.holder.slot);
      w.holder.slot = w.many[7].child;
      log.num('slot back to object', w.holder.slot.v);
      w.many[7].child.v = -1;
      log.num('write through other path', w.holder.slot.v);
    }
  },
  {
    name: 'numbers',
    world: () => ({
      vals: [0, -0, NaN, Infinity, -Infinity, 2 ** 53, 2 ** 53 + 2, 1.7976931348623157e308, 5e-324, 0.1 + 0.2, -1.5,
        2147483647, 2147483648, -2147483649, 1e21, 123456789.125, 3.4028235677973366e38],
      out: {},
      echo(x: any): any { return x; },
      sum(a: number, b: number): number { return a + b; },
      kind(x: any): string { return typeOf(x); }
    }),
    arkts: (w: any, log: Log) => {
      for (let i = 0; i < w.vals.length; i++) {
        const x: number = w.vals[i];
        log.num('v' + i, x);
        const y = x * 3 + 1;
        w.out.v = y;
        log.num('v' + i + ' written', w.out.v);
        log.num('v' + i + ' echo', w.echo(y));
        log.text('v' + i + ' Int32',
          Number.isInteger(x) && x >= -2147483648 && x <= 2147483647 ? BigInt(x).toString() : 'conversion');
        log.num('v' + i + ' Float32', Math.fround(x));
      }
      w.out.big = BigInt('9007199254740993');
      log.text('Int64 written kind', w.kind(w.out.big));
      log.text('Int64 read', String(w.out.big));
      w.out.min = BigInt('-9223372036854775808');
      log.text('Int64.Min read', String(w.out.min));
      log.text('Int64 from a number', 'conversion');
      w.out.i32 = 2147483647;
      log.text('Int32 written kind', w.kind(w.out.i32));
      log.num('sum', w.sum(0.1, 0.2));
      log.num('sum of extremes', w.sum(w.vals[7], w.vals[7]));
    }
  },
  {
    name: 'strings',
    world: () => ({
      strs: ['', 'a', 'héllo', '\u{1F600}', 'a'.repeat(255), 'a'.repeat(256), 'é'.repeat(255),
        'é'.repeat(256), '中文字符', 'nul\u0000mid', 'x\uD800y', '\uDC00', 'tab\tnl\n',
        '\u{1F600}'.repeat(200), 'q"b\\s'],
      out: {},
      len(s: string): number { return s.length; },
      echo(s: string): string { return s; }
    }),
    arkts: (w: any, log: Log) => {
      for (let i = 0; i < w.strs.length; i++) {
        if (!convertible(w.strs[i])) {
          log.text('s' + i, 'malformed');
          continue;
        }
        const s: string = w.strs[i];
        log.str('s' + i, s);
        log.num('s' + i + ' js length', w.len(w.strs[i]));
        const t = s + '|' + s;
        w.out.s = t;
        log.num('s' + i + ' written length', w.len(w.out.s));
        log.str('s' + i + ' echo', w.echo(t));
        log.bool('s' + i + ' round trip', w.out.s === t);
      }
      log.text('member read on a string', typeof w.strs[1] === 'object' ? 'ok' : 'member');
      w.out['kéy'] = 1;
      w.out[''] = 2;
      log.text('keys', Object.keys(w.out).map(fmtStr).join(','));
      log.num('index by unicode key', w.out['kéy']);
    }
  },
  {
    name: 'arrays',
    world: () => ({
      arr: [1, 'two', true, null, undefined, { k: 1 }, [5, 6]],
      nested: [[1, 2], [3, [4, 5]]],
      nums: [3, 1, 2, 10],
      out: {},
      kind(x: any): string { return typeOf(x); }
    }),
    arkts: (w: any, log: Log) => {
      const a = w.arr;
      log.num('length', a.length);
      for (let i = 0; i < 7; i++) log.text('kind ' + i, w.kind(a[i]));
      log.text('out of bounds', 100 < a.length ? 'ok' : 'index');
      a[10] = 'far';
      log.num('length after far write', a.length);
      log.text('hole', w.kind(a[8]));
      a.length = 3;
      log.num('length after shrink', a.length);
      log.text('element past shrink', 5 < a.length ? 'ok' : 'index');
      log.num('push', a.push(42));
      log.num('indexOf', a.indexOf(42));
      log.str('Float64 index', a[1.0]);
      log.bool('String index', a['2']);
      log.num('nested', w.nested[1][1][0]);
      w.nested[1][1][1] = 50;
      log.num('nested write', w.nested[1][1][1]);
      w.out.floats = [1.5, 2.5];
      log.str('Array<Float64> written', JSON.stringify(w.out.floats));
      w.out.strs = ['x', 'y'];
      log.str('Array<String> written', JSON.stringify(w.out.strs));
      w.out.opts = [1, undefined];
      log.str('Array<?Float64> written', JSON.stringify(w.out.opts));
      w.out.nested = [[1, 2], [3]];
      log.str('Array<Array<Float64>> written', JSON.stringify(w.out.nested));
      const nums: number[] = w.nums.slice();
      log.num('Array<Float64> read sum', nums.reduce((s: number, x: number) => s + x, 0));
      w.nums.sort();
      log.str('default sort', w.nums.join(','));
      w.nums.reverse();
      log.str('reverse', w.nums.join(','));
      log.num('Array.isArray', Array.isArray(w.nums) ? 1 : 0);
    }
  },
  {
    name: 'methodsAndThis',
    world: () => {
      const w: any = {
        c: new Counter(),
        Counter: Counter,
        makeCounter(): () => number {
          let n = 0;
          return () => ++n;
        }
      };
      w.whoAmI = function (this: any): string { return this === undefined ? 'undefined' : this === w ? 'world' : 'other'; };
      return w;
    },
    arkts: (w: any, log: Log) => {
      const c = w.c;
      log.num('inc 2', c.inc(2));
      log.num('inc 3', c.inc(3));
      log.num('getter', c.double);
      c.value = 4;
      log.num('after setter', c.count);
      const inc = c.inc;
      log.num('extracted method keeps this', inc.call(c, 1));
      log.num('static', w.Counter.make().inc(5));
      log.text('method this', w.whoAmI());
      const who = w.whoAmI;
      log.text('extracted function this', who.call(w));
      log.num('index call', c['inc'](1));
      const c2: any = Reflect.construct(w.Counter, []);
      log.num('Reflect.construct', c2.inc(7));
      log.bool('shared prototype method', c.inc === c2.inc);
      log.bool('instances differ', c === c2);
      const next = w.makeCounter();
      next();
      next();
      log.num('closure', next());
      log.text('own keys', Object.keys(c).join(','));
    }
  },
  {
    name: 'callbacks',
    world: () => {
      const range: number[] = [];
      for (let i = 0; i < 5000; i++) range.push(i);
      return {
        nums: [3, 1, 2],
        range: range,
        target: {},
        apply(f: (x: any) => any, x: any): any { return f(x); },
        twice(f: (x: number) => number): number { return f(f(1)); },
        callAndCatch(f: () => void): string {
          try {
            f();
            return 'no throw';
          } catch (e) {
            return 'caught:' + errorText(e).includes('cbBoom');
          }
        },
        reenter(f: (x: number) => number): number { return f(10) + 1; },
        inner(x: number): number { return x * 2; },
        kind(x: any): string { return typeOf(x); }
      };
    },
    arkts: (w: any, log: Log) => {
      log.num('apply', w.apply((x: number) => x * x, 7));
      log.num('twice', w.twice((x: number) => x + 10));
      log.str('map', w.nums.map((x: number) => x * 10).join(','));
      log.str('sort', w.nums.slice().sort((a: number, b: number) => a - b).join(','));
      log.num('reenter', w.reenter((x: number) => w.inner(x) + 5));
      log.str('callback throws', w.callAndCatch(() => { throw new Error('cbBoom'); }));
      log.str('callback returns string', w.apply((s: string) => s + '!', 'hi'));
      log.text('callback returns undefined', w.kind(w.apply((_: number) => undefined, 0)));
      let count = 0;
      w.nums.forEach((_: number) => { count++; });
      log.num('forEach count', count);
      w.apply((o: any) => {
        o.touched = true;
        return o;
      }, w.target);
      log.bool('callback mutated its argument', w.target.touched);
      log.num('reduce over 5000', w.range.reduce((acc: number, x: number) => acc + x, 0));
      let seen = 0;
      const f = (x: number) => {
        seen += x;
        return seen;
      };
      w.apply(f, 1);
      w.apply(f, 2);
      log.num('one function called twice', w.apply(f, 3));
    }
  },
  {
    name: 'exceptions',
    world: () => ({
      n: 1,
      calls: 0,
      boom(): void { throw new Error('E-boom'); },
      throwStr(): void { throw 'E-str'; },
      get bad(): number { throw new TypeError('E-getter'); },
      count(): number { return ++this.calls; }
    }),
    arkts: (w: any, log: Log) => {
      attempt(log, 'Error', 'E-boom', undefined, () => w.boom());
      attempt(log, 'thrown string', 'E-str', undefined, () => w.throwStr());
      attempt(log, 'throwing getter', 'E-getter', undefined, () => w.bad);
      attempt(log, 'JSON.parse', 'SyntaxError', undefined, () => JSON.parse('{'));
      attempt(log, 'member of undefined', '', 'member', () => w.missing.x);
      attempt(log, 'call a number', '', 'function', () => w.n());
      log.text('String from a number', 'conversion');
      log.num('usable after errors', w.count());
      let caught = 0;
      for (let i = 0; i < 100; i++) {
        try {
          w.boom();
        } catch (e) {
          caught++;
        }
      }
      log.num('caught in a loop', caught);
      log.num('calls after loop', w.count());
    }
  },
  {
    name: 'builtins',
    world: () => ({ kind(x: any): string { return typeOf(x); } }),
    arkts: (w: any, log: Log) => {
      const m: any = Reflect.construct(Map, []);
      m.set('a', 1);
      m.set(2, 'two');
      const key = {};
      m.set(key, true);
      log.num('map size', m.size);
      log.num('get a', m.get('a'));
      log.str('get 2', m.get(2));
      log.bool('get object key', m.get(key));
      log.bool('has missing', m.has('zz'));
      m.delete('a');
      log.num('size after delete', m.size);
      log.str('keys', JSON.stringify(Array.from(m.keys())));
      const s: any = Reflect.construct(Set, []);
      s.add(1);
      s.add(1);
      s.add('1');
      log.num('set size', s.size);
      const o: any = {};
      o.name = 'n';
      o.list = [1, 2, 3];
      o.nested = {};
      o.nested.ok = true;
      o.nothing = null;
      log.str('stringify', JSON.stringify(o));
      const p = JSON.parse('{"x":[1,{"y":"z"}],"n":-0.5}');
      log.str('parse y', p.x[1].y);
      log.num('parse n', p.n);
      log.str('Object.keys', Object.keys(p).join(','));
      log.num('Math.max', Math.max(1, 9, 3));
      log.num('Math.hypot', Math.hypot(3, 4));
      log.num('parseInt', parseInt('ff', 16));
      log.str('String(123.5)', String(123.5));
      log.text('toFixed on a number', typeof 3.14159 === 'object' ? 'ok' : 'member');
      log.text('toUpperCase on a string', typeof 'abc' === 'object' ? 'ok' : 'member');
      log.text('kind of a symbol', w.kind(Symbol('s')));
    }
  },
  {
    name: 'longTurn',
    // Too many operations to run through posting.
    offThreadRuns: 0,
    world: () => ({ t: { a: { b: 1.5 } }, fresh(i: number): any { return { id: i }; } }),
    arkts: (w: any, log: Log) => {
      const early = w.t.a;
      let sum = 0;
      for (let i = 0; i < 200000; i++) sum += w.t.a.b;
      log.num('sum', sum);
      const kept: any[] = [];
      for (let i = 0; i < 20000; i++) {
        const o = w.fresh(i);
        if (i % 1000 === 0) kept.push(o);
      }
      log.num('kept', kept.length);
      let ids = 0;
      for (const o of kept) ids += o.id;
      log.num('kept ids', ids);
      log.num('early still readable', early.b);
      w.t.a.b = 2;
      log.num('early sees the write', early.b);
      log.bool('early identity', early === w.t.a);
    }
  },
  {
    name: 'gcChurn',
    // Too many operations to run through posting.
    offThreadRuns: 0,
    world: () => ({ store: [], fresh(i: number): any { return { id: i, payload: [i, i + 1] }; } }),
    arkts: (w: any, log: Log) => {
      const kept: any[] = [];
      for (let round = 0; round < 3; round++) {
        for (let i = 0; i < 20000; i++) {
          const o = w.fresh(round * 20000 + i);
          if (i % 2000 === 0) kept.push(o);
          if (i % 5000 === 1) w.store.push(o);
        }
      }
      let ids = 0;
      let payloads = 0;
      for (const o of kept) {
        ids += o.id;
        payloads += o.payload[1];
      }
      log.num('kept', kept.length);
      log.num('kept ids', ids);
      log.num('kept payloads', payloads);
      log.num('stored', w.store.length);
      let stored = 0;
      for (let i = 0; i < w.store.length; i++) stored += w.store[i].id;
      log.num('stored ids', stored);
    }
  },
  {
    name: 'jsonWalk',
    world: () => ({ doc: JSON.parse(DOC), kind(x: any): string { return typeOf(x); } }),
    arkts: (w: any, log: Log) => {
      log.str('walk', walk(w, w.doc));
      w.copy = copyOf(w, w.doc);
      log.str('copy stringified', JSON.stringify(w.copy));
      log.bool('copy is a new object', w.copy === w.doc);
      w.doc.o.a.b[1].added = 'yes';
      log.str('walk after edit', walk(w, w.doc.o));
    }
  },
  {
    name: 'options',
    world: () => ({
      out: {},
      vals: { undef: undefined, nul: null, two: 2, s: 'str', t: true },
      optArr: [1, null, undefined, 4],
      kind(x: any): string { return typeOf(x); }
    }),
    arkts: (w: any, log: Log) => {
      const opt = (x: any) => (x === undefined || x === null ? 'none' : 'some:' + (typeof x === 'string' ? fmtStr(x) : typeof x === 'boolean' ? String(x) : fmtNum(x)));
      w.out.a = 1.5;
      w.out.b = undefined;
      w.out.c = 's';
      w.out.d = undefined;
      w.out.e = true;
      w.out.f = undefined;
      for (const k of ['a', 'b', 'c', 'd', 'e', 'f']) log.text('written ' + k, w.kind(w.out[k]));
      log.text('?Float64 from undefined', opt(w.vals.undef));
      log.text('?Float64 from null', opt(w.vals.nul));
      log.text('?Float64 from 2', opt(w.vals.two));
      log.text('?String from str', opt(w.vals.s));
      log.text('?Bool from true', opt(w.vals.t));
      log.text('?String from undefined', opt(w.vals.undef));
      log.text('Array<?Float64> read', w.optArr.map(opt).join(','));
      w.out.arr = [1, undefined];
      log.str('Array<?Float64> written', JSON.stringify(w.out.arr));
    }
  },
  {
    name: 'manyThreads',
    offThreadRuns: 5,
    world: () => {
      const slots: any[] = [];
      for (let t = 0; t < THREADS; t++) slots.push({ n: -1, s: '' });
      return {
        slots: slots,
        shared: {
          cfg: { a: { b: 2.5 } },
          bumps: 0,
          add(a: number, b: number): number { return a + b; },
          bump(): void { this.bumps++; }
        },
        fresh(i: number): any { return { id: i }; },
        apply(f: (x: any) => any, x: any): any { return f(x); },
        boom(): void { throw new Error('T-boom'); }
      };
    },
    arkts: (w: any, log: Log) => {
      for (let t = 0; t < THREADS; t++) threadBody(w, t, log);
      log.num('bumps', w.shared.bumps);
    }
  }
];

const THREADS = 8;
const THREAD_ITERATIONS = 200;

function threadBody(w: any, t: number, log: Log): void {
  const own = w.slots[t];
  const kept: any[] = [];
  let acc = 0;
  let caught = 0;
  let badText = 0;
  for (let i = 0; i < THREAD_ITERATIONS; i++) {
    own.n = i;
    acc += own.n;
    acc += w.shared.cfg.a.b;
    acc += w.shared.add(t, i);
    w.shared.bump();
    const o = w.fresh(t * 1000 + i);
    if (i % 50 === 0) kept.push(o);
    if (i % 25 === 0) acc += w.apply((x: number) => x + 1, i);
    if (i % 40 === 0) {
      try {
        w.boom();
      } catch (e) {
        caught++;
      }
    }
    if (i % 20 === 0) {
      const s = 't' + t + '-' + i + '-é';
      own.s = s;
      if (own.s !== s) badText++;
    }
    if (i % 100 === 99) log.num('t' + t + ' acc at ' + i, acc);
  }
  let ids = 0;
  for (const o of kept) ids += o.id;
  log.num('t' + t + ' kept ids', ids);
  log.num('t' + t + ' n', own.n);
  log.str('t' + t + ' s', own.s);
  log.num('t' + t + ' caught', caught);
  log.num('t' + t + ' bad text', badText);
  log.bool('t' + t + ' own identity', own === w.slots[t]);
}

function program(name: string): Program {
  const found = PROGRAMS.find((p: Program) => p.name === name);
  if (found === undefined) {
    throw new Error('unknown program ' + name);
  }
  return found;
}

export function programNames(): string[] { return PROGRAMS.map((p: Program) => p.name); }

export function programWorld(name: string): Object { return program(name).world(); }

export function programOffThreadRuns(name: string): number { return program(name).offThreadRuns ?? 1; }

export function programReference(name: string): string {
  const p = program(name);
  const log = new Log();
  try {
    (p.arkts as (w: any, log: Log) => void)(p.world(), log);
  } catch (e) {
    log.text('uncaught', String(e));
  }
  return log.render();
}
