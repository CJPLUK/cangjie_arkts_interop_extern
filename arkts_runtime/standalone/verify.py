"""Verify the independent app UI and its packaged native dependencies."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

hdc, device = sys.argv[1:]
app = Path(os.environ['ARKTS_STANDALONE_APP'])
libs = app / 'entry/libs/arm64-v8a'
assert not any('ark_interop' in path.name for path in libs.rglob('*.so'))
readelf = Path(os.environ['DEVECO_HOME']) / 'sdk/default/openharmony/native/llvm/bin/llvm-readelf'
for path in libs.rglob('*.so'):
    dynamic = subprocess.check_output([str(readelf), '-d', str(path)], text=True)
    assert 'ark_interop' not in dynamic, str(path)


def shell(*args):
    return subprocess.check_output([hdc, '-t', device, 'shell', *args], text=True)


def texts(node):
    result = []
    value = node.get('attributes', {}).get('text')
    if value:
        result.append(value)
    for child in node.get('children', []):
        result.extend(texts(child))
    return result


for _ in range(15):
    time.sleep(1)
    path = shell('uitest', 'dumpLayout').strip().split('saved to:')[-1]
    layout = json.loads(shell('cat', path))
    visible = texts(layout)
    if 'Standalone native backend: 0' in visible and 'Worker teardown: passed' in visible:
        print('PASS independent binding, callbacks, worker teardown, pending-task cancellation and late reference release')
        print('PASS no ark_interop native dependencies or packaged libraries')
        break
else:
    raise RuntimeError(f'Independent consumer validation failed: {visible}')
