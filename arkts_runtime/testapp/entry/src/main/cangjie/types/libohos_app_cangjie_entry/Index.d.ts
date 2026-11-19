export declare function testCJ(s: string): string

export declare function runArkTSTest(name: string, ...fixtures: Object[]): string

export declare function runArkTSTestOffThread(name: string): Promise<string>

export declare function listArkTSTests(): string[]

export declare function runDiffProgram(variant: string, name: string, world: Object): string

export declare function runDiffProgramOffThread(name: string, world: Object): Promise<string>
