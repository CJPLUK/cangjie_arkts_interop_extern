// Plain TypeScript for checks that ArkTS does not allow (globalThis, property descriptors,
// Object.freeze on a literal).

export function globalObject(): object {
  return globalThis;
}

export function frozenObject(): object {
  return Object.freeze({});
}

// "<value> W|w E|e C|c" (upper case = flag set), or "none".
export function describeProperty(o: object, key: string): string {
  const d = Object.getOwnPropertyDescriptor(o, key);
  if (d === undefined) {
    return 'none';
  }
  return `${String(d.value)} ${d.writable ? 'W' : 'w'}${d.enumerable ? 'E' : 'e'}${d.configurable ? 'C' : 'c'}`;
}
