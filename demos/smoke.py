#!/usr/bin/env python3
"""Exercise an installed demo: python3 demos/smoke.py <device> hello|rectangle."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('device')
parser.add_argument('demo', choices=['hello', 'rectangle'])
args = parser.parse_args()
hdc = Path(os.environ.get('DEVECO_HOME', '/Applications/DevEco-Studio.app/Contents')) / 'sdk/default/openharmony/toolchains/hdc'


def run(*command):
    return subprocess.check_output([str(hdc), '-t', args.device, *command], text=True)


def layout():
    path = run('shell', 'uitest', 'dumpLayout').strip().split('saved to:')[-1]
    root = json.loads(run('shell', 'cat', path))
    nodes = []

    def walk(node):
        attributes = node.get('attributes', {})
        if attributes.get('text'):
            nodes.append(attributes)
        for child in node.get('children', []):
            walk(child)

    walk(root)
    return nodes


run('shell', 'power-shell', 'wakeup')
run('shell', 'aa', 'start', '-a', 'EntryAbility', '-b', f'com.example.arkts.{args.demo}')
label = 'Say hello' if args.demo == 'hello' else 'Run example'
button = None
for _ in range(15):
    time.sleep(0.5)
    button = next((node for node in layout() if node.get('text') == label and node.get('enabled') == 'true'), None)
    if button:
        break
assert button, f'{args.demo}: enabled button did not appear'
x1, y1, x2, y2 = map(int, re.findall(r'\d+', button['bounds']))
run('shell', 'uitest', 'uiInput', 'click', str((x1 + x2) // 2), str((y1 + y2) // 2))
time.sleep(1.5)
visible = layout()
texts = [node['text'] for node in visible]
if args.demo == 'hello':
    assert 'Hello world' in texts and any(str(n) in texts for n in range(1, 6)), texts
    assert any(node['text'] == label and node.get('enabled') == 'false' for node in visible), visible
    time.sleep(5)
    visible = layout()
    assert 'Hello world' not in [node['text'] for node in visible], visible
    assert any(node['text'] == label and node.get('enabled') == 'true' for node in visible), visible
else:
    assert 'width 5, area 25' in texts and 'ArkTS: 5 x 5 = 25' in texts, texts
print(f'PASS {args.device} {args.demo}: visible behavior verified')
