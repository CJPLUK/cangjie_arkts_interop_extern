#!/usr/bin/env python3
"""Isolated, interleaved backend comparison; does not change the library or its dependencies."""
from pathlib import Path
import subprocess,tempfile,tarfile,io,shutil,re,argparse
parser=argparse.ArgumentParser(description="Compare old and current backends in one isolated app, alternating warmed samples. Reuses the benchmark app identity.")
parser.add_argument('--baseline',default='cbdc32f',help='Git ref with the old JSContext backend')
parser.add_argument('--all',action='store_true',help='Run on every connected device')
parser.add_argument('--prepare-only',action='store_true',help='Generate the fixture without building or installing it')
args=parser.parse_args()
baseline=args.baseline
root=Path(__file__).resolve().parents[2]
p=Path(tempfile.mkdtemp(prefix='arkts-paired-',dir='/tmp'))
with tarfile.open(fileobj=io.BytesIO(subprocess.check_output(['git','archive','HEAD'],cwd=root))) as archive:
 archive.extractall(p,filter='data')
for name in ['arkts_runtime/src','arkts_runtime/native','demos/benchmarks/entry/src','demos/benchmarks/oh_modules','demos/benchmarks/entry/oh_modules']:
 dst=p/name
 if dst.exists():shutil.rmtree(dst)
 shutil.copytree(root/name,dst,symlinks=True)
for name in ['arkts_runtime/cjpm.toml','demos/benchmarks/entry/cjpm.toml','demos/benchmarks/entry/hvigorfile.ts','demos/benchmarks/run.sh','demos/benchmarks/build-profile.json5','demos/benchmarks/oh-package-lock.json5','demos/benchmarks/local.properties']:
 shutil.copy2(root/name,p/name)
legacy=p/'arkts_runtime_legacy';(legacy/'src').mkdir(parents=True)
config=subprocess.check_output(['git','show',baseline+':arkts_runtime/cjpm.toml'],cwd=root,text=True).replace('name = "arkts_runtime"','name = "arkts_runtime_legacy"')
(legacy/'cjpm.toml').write_text(config)
files=subprocess.check_output(['git','ls-tree','-r','--name-only',baseline,'arkts_runtime/src'],cwd=root,text=True).splitlines()
for name in files:
 if Path(name).parent.as_posix()!='arkts_runtime/src' or not name.endswith('.cj'):continue
 s=subprocess.check_output(['git','show',baseline+':'+name],cwd=root,text=True).replace('package arkts_runtime','package arkts_runtime_legacy')
 (legacy/'src'/Path(name).name).write_text(s)
entry=p/'demos/benchmarks/entry';f=entry/'cjpm.toml';s=f.read_text().replace('[dependencies]','[dependencies]\n  arkts_runtime_legacy = { path = "../../../arkts_runtime_legacy" }');f.write_text(s)
cj=entry/'src/main/cangjie'
names={}
for f in cj.glob('b*.cj'):
 for n in re.findall(r'^func (\w+)\(',f.read_text(),re.M):names[n]=n+'Legacy'
names.update({'runtimeTarget':'legacyRuntimeTarget','runtimeBench':'legacyRuntimeBench'})
for f in list(cj.glob('b*.cj')):
 s=f.read_text().replace('ArkTSRuntime','LegacyRuntime').replace('import arkts_runtime.LegacyRuntime','import arkts_runtime_legacy.ArkTSRuntime as LegacyRuntime')
 for old,new in names.items():s=re.sub(r'\b'+old+r'\b',new,s)
 (cj/('legacy_'+f.name)).write_text(s)
f=cj/'harness.cj';s=f.read_text().replace('import arkts_runtime.ArkTSRuntime','import arkts_runtime.ArkTSRuntime\nimport arkts_runtime_legacy.ArkTSRuntime as LegacyRuntime')
a=s.index('func allBenchmarks()');b=s.index('\nfunc find(',a);groups=re.sub(r'\ballBenchmarks\b','allLegacyBenchmarks',s[a:b])
for old,new in names.items():groups=re.sub(r'\b'+old+r'\b',new,groups)
s+='\n'+groups+'''
func findLegacy(name: String): Benchmark {
    for (benchmark in allLegacyBenchmarks()) {
        if (benchmark.name == name) { return benchmark }
    }
    throw IllegalArgumentException("unknown legacy benchmark ${name}")
}
func legacyRuntimeBench(): Extern<LegacyRuntime> { LegacyRuntime.global().Bench }
func legacyRuntimeTarget(): Extern<LegacyRuntime> { LegacyRuntime.global().Bench.target }
'''
s=s.replace('let benchmark = find(name)','let benchmark = if (variant == "arktsRuntimeLegacy") { findLegacy(name) } else { find(name) }');f.write_text(s)
f=cj/'index.cj';s=f.read_text().replace('import arkts_runtime.ArkTSRuntime','import arkts_runtime.ArkTSRuntime\nimport arkts_runtime_legacy.ArkTSRuntime as LegacyRuntime').replace('    exports["benchmarkNames"]','    if (!LegacyRuntime.isBound()) { LegacyRuntime.bind(context) }\n    exports["benchmarkNames"]',1);f.write_text(s)
f=entry/'src/main/ets/pages/Index.ets';s=f.read_text().replace("const VARIANTS = ['arkInterop', 'arktsRuntime'];","const VARIANTS = ['arkInterop', 'arktsRuntimeLegacy', 'arktsRuntime'];")
a=s.index('        for (const variant of VARIANTS)');b=s.index("        const heap =",a)
s=s[:a]+'''        const sampleSets: number[][] = [[], [], []];
        for (let i = 0; i < RUNS; i++) {
          for (let v = 0; v < VARIANTS.length; v++) {
            const index = i % 2 === 0 ? v : VARIANTS.length - 1 - v;
            const variant = VARIANTS[index];
            await measure(name, variant);
            sampleSets[index].push(await measure(name, variant));
            await sleep(PAUSE_MS);
          }
        }
        for (let v = 0; v < VARIANTS.length; v++) {
          const runs = sampleSets[v];
          hilog.info(DOMAIN, TAG, 'SAMPLES|%{public}s', `${name}|${VARIANTS[v]}|${n}|${runs.join(',')}`);
          perOp.push(median(runs) / n);
        }
'''+s[b:]
s=s.replace('arktsRuntime: perOp[1]','arktsRuntime: perOp[2]').replace('heapGrowthKB(name, VARIANTS[1])','heapGrowthKB(name, VARIANTS[2])');f.write_text(s)
print(p,flush=True)
if not args.prepare_only:
    subprocess.run(['sh',str(p/'demos/benchmarks/run.sh')]+(['--all'] if args.all else []),cwd=p,check=True)
    print('Paired samples: '+str(p/'demos/benchmarks/results'),flush=True)
    print('Restore the standard app with demos/benchmarks/run.sh'+(' --all' if args.all else ''),flush=True)
