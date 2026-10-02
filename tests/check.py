#!/usr/bin/env python3
"""Run without a desktop: python3 tests/check.py."""
import importlib.machinery
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
from types import SimpleNamespace
from unittest.mock import patch

root = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader('bridge', str(root / 'linux/bin/mac-mouse-bridge'))
spec = importlib.util.spec_from_loader(loader.name, loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)

bridge.WINDOWS.update({
    'Mac-Left-Portrait': (0, 0, 1200, 2133, 1),
    'Mac-Center-Ultrawide': (1200, 309, 3440, 1440, 2),
    'Mac-Right-Landscape': (4640, 451, 1920, 1080, 3),
})
assert bridge.map_pointer((1200, 309)) == (0, 0)
assert bridge.map_pointer((4640, 451)) == (3440, 153)
assert bridge.map_pointer((600, 1066)) == (-540, 776)
assert bridge.map_pointer(None) is None
assert bridge.map_pointer((9000, 9000)) is None

# A focus-induced cursor jump on release must not become a drag. Real
# RawMotion during a held button must still send a position update.
press = 'EVENT type 15 (RawButtonPress)\n detail: 1\n\n'
release = 'EVENT type 16 (RawButtonRelease)\n detail: 1\n\n'
motion = 'EVENT type 17 (RawMotion)\n\n'

class Finished(Exception):
    pass

for events, expected_moves in ((press + release, 1), (press + motion + release, 2)):
    messages, moves, resets = [], [], []
    pointer = SimpleNamespace(last_mask=0, get=lambda: (4700, 550))
    process = SimpleNamespace(stdout=io.StringIO(events))
    with patch.object(bridge, 'POINTER', pointer), \
         patch.object(bridge, 'send', messages.append), \
         patch.object(bridge, 'send_current', lambda: moves.append(True)), \
         patch.object(bridge, 'reset_side_input', resets.append), \
         patch.object(bridge.subprocess, 'Popen', return_value=process), \
         patch.object(bridge.time, 'sleep', side_effect=Finished):
        try:
            bridge.input_reader()
        except Finished:
            pass
    assert len(moves) == expected_moves, (events, moves)
    assert [m for m in messages if m.startswith('B ')] == ['B 1 1', 'B 1 0']
    assert resets == ['Mac-Right-Landscape']

for source in (root / 'linux/bin').iterdir():
    if source.is_file() and source.name != 'mac-mouse-bridge':
        subprocess.run(['bash', '-n', str(source)], check=True)
for source in (root / 'macos/install.sh', root / 'linux/install.sh'):
    subprocess.run(['bash', '-n', str(source)], check=True)
if shutil.which('zsh'):
    subprocess.run(['zsh', '-n', str(root / 'macos/bin/mac-sunshine-three')], check=True)
for source in (root / 'macos/launchagents').glob('*.plist'):
    plistlib.loads(source.read_bytes())
json.loads((root / 'macos/sunshine/apps.json').read_text())
for side in ('left', 'right'):
    config = (root / f'macos/sunshine/{side}/sunshine.conf.in').read_text()
    assert 'keyboard = disabled' in config and 'mouse = disabled' in config
assert 'keyboard = enabled' in (root / 'macos/sunshine/center/sunshine.conf.in').read_text()
print('OK: pointer mapping, click/drag regression, scripts, service templates and Sunshine input settings')
