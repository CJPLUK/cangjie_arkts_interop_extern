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

export function describe(rect: Rectangle): string {
  return `${rect.width} x ${rect.height} = ${rect.area()}`;
}
