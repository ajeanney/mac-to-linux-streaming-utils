#!/usr/bin/env python3
"""Run without a desktop: python3 tests/check.py."""
import importlib.machinery
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
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
    if source.is_file() and source.name not in {'mac-mouse-bridge', 'mac-screens-wake'}:
        subprocess.run(['bash', '-n', str(source)], check=True)
for source in (root / 'macos/install.sh', root / 'linux/install.sh'):
    subprocess.run(['bash', '-n', str(source)], check=True)
if shutil.which('zsh'):
    subprocess.run(['zsh', '-n', str(root / 'macos/bin/mac-sunshine-three')], check=True)
for source in (root / 'macos/launchagents').glob('*.plist'):
    plistlib.loads(source.read_bytes())
for side in ('left', 'center', 'right'):
    apps = json.loads((root / 'macos/sunshine/apps.json').read_text().replace('@SIDE@', side))
    hook = apps['apps'][0]['prep-cmd'][0]
    assert hook['do'].endswith(f'acquire {side}')
    # Sunshine never runs `undo` for Desktop, so the lease must expire on its own.
    assert 'undo' not in hook
for source in (root / 'macos/bin/mac-sunshine-session', root / 'linux/bin/mac-screens-wake'):
    compile(source.read_text(), str(source), 'exec')

# Both call sites pass mode and host, so a strict argv length check silently
# rejected every real invocation.
wake_argv = re.findall(r"sys\.argv\[(\d+)\] if len\(sys\.argv\) > (\d+)",
                       (root / 'linux/bin/mac-screens-wake').read_text())
assert wake_argv == [('1', '1'), ('2', '2'), ('3', '3')], wake_argv

session_loader = importlib.machinery.SourceFileLoader('sunshine_session', str(root / 'macos/bin/mac-sunshine-session'))
session_spec = importlib.util.spec_from_loader(session_loader.name, session_loader)
session = importlib.util.module_from_spec(session_spec)
session_loader.exec_module(session)
with tempfile.TemporaryDirectory() as temp_dir:
    # Never drive the real BetterDisplay or the real keyboard backlight.
    patch.object(session.subprocess, 'run',
                 return_value=SimpleNamespace(returncode=0, stdout='')).start()
    session.CONFIG = Path(temp_dir)
    session.STATE = session.CONFIG / 'sessions.json'
    session.LOCK = session.CONFIG / 'sessions.lock'
    session.INTERNAL_BRIGHTNESS = session.CONFIG / 'internal-brightness'
    session.KEYBOARD_BACKLIGHT = session.CONFIG / 'keyboard-backlight'
    session.IDLE = session.CONFIG / 'idle'
    real_restore = session.restore
    session.prepare = lambda: None
    session.connected = lambda *_: True
    session.is_connected = lambda *_: True
    restored = []
    session.restore = lambda: restored.append(True)
    session.command = lambda *args, **kwargs: SimpleNamespace(returncode=0, stdout='{"displayID":"0"}')
    assert session.display_id(5) is None
    session.command = lambda *args, **kwargs: SimpleNamespace(returncode=0, stdout='{"displayID":"10"}')
    assert session.display_id(5) == '10'
    assert session.main(['acquire', 'left']) == 0
    assert session.main(['acquire', 'center']) == 0
    assert not restored
    assert session.main(['heartbeat']) == 0
    assert set(session.read_leases()) == {'left', 'center'}
    # has-active reports success while a lease is live; the supervisor relies
    # on that polarity to decide when the screens may power down.
    assert session.main(['has-active']) == 0
    # A stream that stopped refreshing lets its lease run out; once all are
    # stale the Mac powers the virtual screens back down.
    session.write_leases({'left': session.time.time() - 1, 'center': session.time.time() - 1})
    assert session.main(['has-active']) == 1
    assert session.main(['expire']) == 0 and restored == [True]
    assert session.read_leases() == {}
    # A wake request holds the screens up while Sunshine restarts around the
    # new capture IDs, and a stream that ends drops its lease right away
    # instead of waiting out the timeout.
    assert session.main(['prepare']) == 0
    assert set(session.read_leases()) == {'wake'}
    assert session.main(['has-active']) == 0
    # The first stream to connect takes over the hold, so stopping later does
    # not have to wait for the wake lease to age out.
    assert session.main(['acquire', 'left']) == 0
    assert set(session.read_leases()) == {'left'}
    # A late wake request from a retrying client must not re-add the start-up
    # hold once a stream owns the screens.
    assert session.main(['prepare']) == 0
    assert set(session.read_leases()) == {'left'}
    # A wake refreshed seconds ago keeps the screens up while a client is
    # still connecting...
    session.write_leases({'left': session.time.time() + 60, 'wake': session.time.time() + 55})
    assert session.main(['release', 'left']) == 0
    assert set(session.read_leases()) == {'wake'}
    # ...but with nobody waking the Mac any more, releasing the last stream
    # powers the screens down immediately.
    session.write_leases({'wake': session.time.time() + 20})
    assert session.main(['release', 'left']) == 0
    assert session.read_leases() == {}
    assert restored == [True, True]
    # Streaming blanks the built-in panel, which macOS will not let us
    # disconnect, and puts the saved brightness back when it ends.
    calls = []

    def fake_command(*args, **kwargs):
        calls.append(args)
        return SimpleNamespace(returncode=0, stdout='0.7' if '-brightness' in args else '{"displayID":"10"}')

    session.command = fake_command
    session.INTERNAL_BRIGHTNESS.unlink(missing_ok=True)
    session.dim_internal()
    assert session.INTERNAL_BRIGHTNESS.read_text().strip() == '0.7'
    assert ('set', '-tagID=2', '-brightness=0') in calls
    session.undim_internal()
    assert not session.INTERNAL_BRIGHTNESS.exists()
    assert ('set', '-tagID=2', '-brightness=0.7') in calls
    # A sleeping panel reports 0. Restoring "nothing" left the screen dark
    # after a session, so a dark reading has to fall back to a usable level.
    session.command = lambda *args, **kwargs: SimpleNamespace(returncode=0, stdout='0')
    session.dim_internal()
    assert session.INTERNAL_BRIGHTNESS.read_text().strip() == str(session.DARK_PANEL_BRIGHTNESS)
    session.command = fake_command
    session.INTERNAL_BRIGHTNESS.unlink(missing_ok=True)
    # Streaming turns the built-in keyboard backlight off; macOS cannot report
    # the level, so the level to put back comes from the config file.
    session.KEYBOARD_BACKLIGHT.write_text('0.5\n')
    sent = []
    session.bridge = lambda message, timeout=3: sent.append(message) or True
    session.keyboard_backlight_off()
    session.restore_keyboard_backlight()
    assert sent == ['X down 16', 'X up 8'], sent
    # The supervisor expires every few seconds while the Mac sits idle, so
    # putting everything back has to happen once and then stay put.
    session.restore = real_restore
    sent.clear()
    session.restore()
    assert session.IDLE.exists() and sent == ['X up 8']
    session.restore()
    assert sent == ['X up 8']
    session.power_on()
    assert not session.IDLE.exists()
for side in ('left', 'right'):
    config = (root / f'macos/sunshine/{side}/sunshine.conf.in').read_text()
    assert 'keyboard = disabled' in config and 'mouse = disabled' in config
assert 'keyboard = enabled' in (root / 'macos/sunshine/center/sunshine.conf.in').read_text()
print('OK: pointer mapping, click/drag regression, scripts, service templates and Sunshine input settings')
