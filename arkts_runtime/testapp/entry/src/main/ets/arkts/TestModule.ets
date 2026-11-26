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

export function createRectangle(): Rectangle {
  return new Rectangle(0, 5);
}
