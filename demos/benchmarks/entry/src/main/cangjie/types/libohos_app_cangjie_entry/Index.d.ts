export declare function benchmarkNames(): string[];
export declare function iterations(name: string): number;
export declare function runBenchmark(name: string, variant: string, done: (ns: number, error: string) => void): void;
export declare function dispatchCases(): string[];
export declare function timeDispatch(name: string, variant: string, iterations: number): number;
