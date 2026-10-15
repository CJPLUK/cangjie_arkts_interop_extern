export function sayHello(onTick: (text: string, n: number) => void): void {
  onTick('Hello world', 0);
  let n = 0;
  const id = setInterval(() => {
    n++;
    if (n <= 5) {
      onTick('Hello world', n);
    } else {
      clearInterval(id);
      onTick('', -1);
    }
  }, 1000);
}
