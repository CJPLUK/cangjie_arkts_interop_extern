export declare function benchmarkNames(): string[];
export declare function iterations(name: string): number;
export declare function runBenchmark(name: string, variant: string, done: (ns: number, error: string) => void): void;
