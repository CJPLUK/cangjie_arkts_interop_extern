export function sayHello(onTick: (text: string, n: number) => void): void {
  let n = 5;
  const id = setInterval(() => {
    if (n > 0) {
      onTick('Hello world', n);
    } else {
      clearInterval(id);
      onTick('', -1);
    }
    n--;
  }, 1000);
}

// Read from Cangjie with ArkTSRuntime.global().Hello.
globalThis.Hello = { sayHello };
