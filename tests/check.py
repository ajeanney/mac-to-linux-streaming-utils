#!/usr/bin/env python3
"""Run without a desktop: python3 tests/check.py."""
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace
from unittest.mock import patch

root = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader('bridge', str(root / 'linux/bin/mac-mouse-bridge'))
spec = importlib.util.spec_from_loader(loader.name, loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)
bridge.POINTER = SimpleNamespace(is_visible=lambda _: True)

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

# Login may discover a stale/unreachable Mac address. Follow the address
# selected by the stream launcher without restarting the input reader.
with tempfile.TemporaryDirectory() as folder:
    home = Path(folder)
    host_file = home / '.local/state/mac-three-screens/host'
    host_file.parent.mkdir(parents=True)
    host_file.write_text('192.168.11.27\n')
    with patch.object(bridge.Path, 'home', return_value=home), \
         patch.object(bridge.subprocess, 'run', return_value=SimpleNamespace(stdout='')):
        bridge.refresh_windows()
        assert bridge.DESTINATION == ('192.168.11.27', bridge.MAC_PORT)
        host_file.write_text('192.168.11.113\n')
        bridge.refresh_windows()
        assert bridge.DESTINATION == ('192.168.11.113', bridge.MAC_PORT)
        host_file.write_text('invalid address\n')
        bridge.refresh_windows()
        assert bridge.DESTINATION == ('192.168.11.113', bridge.MAC_PORT)
bridge.WINDOWS.update({
    'Mac-Center-Ultrawide': (1200, 309, 3440, 1440, 2),
    'Mac-Right-Landscape': (4640, 451, 1920, 1080, 3),
})

# A focus-induced cursor jump on release must not become a drag. Real
# RawMotion during a held button must still send a position update.
press = 'EVENT type 15 (RawButtonPress)\n detail: 1\n\n'
release = 'EVENT type 16 (RawButtonRelease)\n detail: 1\n\n'
motion = 'EVENT type 17 (RawMotion)\n\n'

class Finished(Exception):
    pass

for events, expected_moves in ((press + release, 1), (press + motion + release, 2)):
    messages, moves, resets = [], [], []
    pointer = SimpleNamespace(last_mask=0, get=lambda: (4700, 550), is_visible=lambda _: True)
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

# Minimizing pauses all forwarded input, releases a held drag once, and never
# activates the center from a side click. Restoring resumes without a restart.
visible = {2, 3}
pointer = SimpleNamespace(last_mask=0, get=lambda: (4700, 550),
                          is_visible=lambda window: window in visible)
messages = []
bridge.INPUT_ACTIVE = False
bridge.PRESSED_BUTTONS.clear()
with patch.object(bridge, 'POINTER', pointer), \
     patch.object(bridge, 'send_unchecked', messages.append), \
     patch.object(bridge.subprocess, 'run') as run:
    bridge.send('B 1 1')
    visible.remove(2)
    assert not bridge.input_enabled()
    assert messages.count('B 1 0') == 1
    messages.clear()
    for message in ('M 4000 400', 'B 1 1', 'B 1 0', 'W 80 0', 'D 1', 'I 1 0'):
        bridge.send(message)
    bridge.reset_side_input('Mac-Right-Landscape')
    assert messages == []
    run.assert_not_called()
    visible.add(2)
    bridge.send('M 4000 400')
    bridge.send('B 1 0')  # A press while paused must not become a remote click.
    assert messages == ['M 4000 400']
    bridge.send('B 1 1')
    bridge.send('B 1 0')
    assert messages[-2:] == ['B 1 1', 'B 1 0']
    visible.remove(3)
    assert bridge.map_pointer((4700, 550)) is None
    assert bridge.screen_at((4700, 550)) is None
    bridge.reset_side_input('Mac-Right-Landscape')
    run.assert_not_called()

# Compile the native helper on macOS and exercise its argument boundary
# without ever changing the real keyboard brightness.
if sys.platform == 'darwin':
    with tempfile.TemporaryDirectory() as folder:
        executable = str(Path(folder) / 'keyboard-backlight')
        subprocess.run(['clang', '-framework', 'Foundation',
                        str(root / 'macos/bin/mac-keyboard-backlight.m'), '-o', executable], check=True)
        for arguments in [('invalid', '0'), ('2', '0'), ('nan', '0'), ('0', 'invalid')]:
            result = subprocess.run([executable, *arguments], capture_output=True)
            assert result.returncode == 2, (arguments, result.returncode)

with tempfile.TemporaryDirectory() as folder:
    home = Path(folder)
    commands = home / '.local/bin'
    commands.mkdir(parents=True)
    state = home / '.local/state/mac-three-screens'
    state.mkdir(parents=True)
    (state / 'host').write_text('192.168.11.27\n')
    for name in ('systemctl', 'mac-screens-wake'):
        script = commands / name
        script.write_text('#!/bin/sh\necho "' + name + ' $*" >> "$HOME/calls"\n')
        script.chmod(0o755)
    env = {**os.environ, 'HOME': folder, 'PATH': f'{commands}:' + os.environ['PATH']}
    subprocess.run(['bash', str(root / 'linux/bin/mac-three-screens'), 'stop'], env=env, check=True)
    calls = (home / 'calls').read_text().splitlines()
    assert calls[0].startswith('systemctl --user stop ')
    assert calls[1] == 'mac-screens-wake release 192.168.11.27 all'

    # Simulate the video surface dropping fullscreen after its initial setup.
    launcher = (root / 'linux/bin/moonlight-mac-display').read_text()
    block = launcher.split('    # Moonlight can reset the window state', 1)[1].split('\n    break', 1)[0]
    block = block[block.index('    for _'):]
    for name, body in {
        'sleep': ':',
        'xprop': '''n=$(cat "$HOME/query-count" 2>/dev/null || echo 0)
n=$((n + 1)); echo "$n" > "$HOME/query-count"
case "$n" in 3) exit 1;; 1|4) echo '_NET_WM_STATE(ATOM) =';;
*) echo '_NET_WM_STATE(ATOM) = _NET_WM_STATE_FULLSCREEN';; esac''',
        'xdotool': '''if [ "$1" = search ]; then
n=$(cat "$HOME/query-count" 2>/dev/null || echo 0)
if [ "$n" -ge 2 ]; then echo 456; else echo 123; fi
elif [ "$1" = getwindowname ]; then echo Mac-Center
else echo "$*" >> "$HOME/fullscreen-calls"; fi''',
    }.items():
        script = commands / name
        script.write_text('#!/bin/sh\n' + body + '\n')
        script.chmod(0o755)
    subprocess.run(['bash', '-c', f'child_pid={os.getpid()}; window_id=123; title=Mac-Center; target_x=1200; target_y=309\n' + block], env=env, check=True)
    assert (home / 'fullscreen-calls').read_text().splitlines() == [
        'windowstate --add FULLSCREEN 123', 'windowmove 456 1200 309',
        'windowstate --add FULLSCREEN 456']

for source in (root / 'linux/bin').iterdir():
    if source.is_file() and source.suffix != '.c' and source.name not in {'mac-mouse-bridge', 'mac-screens-wake'}:
        subprocess.run(['bash', '-n', str(source)], check=True)
for source in (root / 'macos/install.sh', root / 'linux/install.sh'):
    subprocess.run(['bash', '-n', str(source)], check=True)
if shutil.which('zsh'):
    subprocess.run(['zsh', '-n', str(root / 'macos/bin/mac-sunshine-three')], check=True)
for source in (root / 'macos/launchagents').glob('*.plist'):
    plistlib.loads(source.read_bytes())
agent = plistlib.loads((root / 'macos/launchagents/com.anthony.mac-mouse-bridge.plist').read_bytes())
assert agent['ProgramArguments'] == ['@HOME@/.local/bin/mac-mouse-bridge']
assert agent['KeepAlive'] is True
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

# Kernel locks do not survive their owner; a stale file is harmless.
if Path('/usr/bin/lockf').exists():
    import fcntl
    with tempfile.TemporaryDirectory() as folder:
        lock = Path(folder) / 'supervisor.lock'
        lock.write_text('left behind by reboot\n')
        command = ['/usr/bin/lockf', '-k', '-s', '-t', '0', str(lock), '/usr/bin/true']
        assert subprocess.run(command).returncode == 0
        with lock.open('r') as handle:
            fcntl.flock(handle, fcntl.LOCK_EX)
            assert subprocess.run(command).returncode != 0
        assert subprocess.run(command).returncode == 0

session_loader = importlib.machinery.SourceFileLoader('sunshine_session', str(root / 'macos/bin/mac-sunshine-session'))
session_spec = importlib.util.spec_from_loader(session_loader.name, session_loader)
session = importlib.util.module_from_spec(session_spec)
session_loader.exec_module(session)
# BetterDisplay rejects redundant setters. Treat an already satisfied state
# as success and still report genuine failures.
for initial, final, expected, sets in [('on', 'on', True, 0), ('off', 'on', True, 1), ('off', 'off', False, 1)]:
    calls = []
    readings = iter([initial, final])
    def connection_command(*args, **kwargs):
        calls.append(args)
        if args[0] == 'get':
            return SimpleNamespace(returncode=0, stdout=next(readings))
        return SimpleNamespace(returncode=1, stdout='Failed.')
    with patch.object(session, 'command', side_effect=connection_command):
        assert session.connected(5, 'on') is expected
    assert sum(call[0] == 'set' for call in calls) == sets

with tempfile.TemporaryDirectory() as temp_dir:
    # Never drive the real BetterDisplay or the real keyboard backlight.
    patch.object(session.subprocess, 'run',
                 return_value=SimpleNamespace(returncode=0, stdout='{"level":0.6,"auto":1}')).start()
    session.CONFIG = Path(temp_dir)
    session.STATE = session.CONFIG / 'sessions.json'
    session.LOCK = session.CONFIG / 'sessions.lock'
    session.INTERNAL_BRIGHTNESS = session.CONFIG / 'internal-brightness'
    session.KEYBOARD_BACKLIGHT = session.CONFIG / 'keyboard-backlight'
    session.KEYBOARD_SAVED = session.CONFIG / 'keyboard-saved.json'
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
    with patch.object(session, 'command', return_value=SimpleNamespace(returncode=0, stdout='{"UUID":"UNKNOWN","displayID":"10"}')):
        assert session.display_id(5) is None
    with patch.object(session, 'power_on', side_effect=AssertionError('acquire must not reconfigure displays')):
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
    # Failed startup drops its wake hold and restores the Mac, but must not
    # tear down screens held by an existing streaming client.
    with patch.object(session, 'prepare', side_effect=RuntimeError('capture unavailable')):
        try:
            session.main(['prepare'])
        except RuntimeError:
            pass
        else:
            raise AssertionError('startup failure was swallowed')
        assert session.read_leases() == {} and restored == [True, True, True]
        session.write_leases({'center': session.time.time() + 60})
        try:
            session.main(['prepare'])
        except RuntimeError:
            pass
        assert set(session.read_leases()) == {'center'}
        assert restored == [True, True, True]
        session.write_leases({})
    # An explicit all-stream stop cancels even a fresh startup hold.
    session.write_leases({'wake': session.time.time() + 59, 'center': session.time.time() + 60})
    before = len(restored)
    assert session.main(['release', 'all']) == 0
    assert session.read_leases() == {} and len(restored) == before + 1
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
    # Save once across repeated acquire hooks and restore brightness plus the
    # ambient sensor setting, rather than faking media keys.
    session.KEYBOARD_SAVED.unlink(missing_ok=True)
    session.KEYBOARD_BACKLIGHT.write_text('0.5\n')
    calls = []
    def fake_backlight(arguments, **kwargs):
        calls.append(arguments)
        return SimpleNamespace(returncode=0, stdout='{"level":0.6,"auto":1}')
    with patch.object(session.subprocess, 'run', side_effect=fake_backlight):
        session.keyboard_backlight_off()
        session.keyboard_backlight_off()
        assert json.loads(session.KEYBOARD_SAVED.read_text()) == {'level': 0.6, 'auto': 1}
        session.restore_keyboard_backlight()
        assert [call[1:] for call in calls] == [[], ['0', '0'], ['0', '0'], ['0.6', '1']]
        assert not session.KEYBOARD_SAVED.exists()
        # If restoring fails, retain the snapshot for a retry.
        session.KEYBOARD_SAVED.write_text('{"level":0.6,"auto":1}')
        with patch.object(session.subprocess, 'run', side_effect=OSError('unavailable')), \
             patch('sys.stderr', io.StringIO()):
            session.restore_keyboard_backlight()
        assert session.KEYBOARD_SAVED.exists()
        session.restore_keyboard_backlight()
        assert not session.KEYBOARD_SAVED.exists()
        session.restore = real_restore
        calls.clear()
        session.IDLE.unlink(missing_ok=True)
        session.restore()
        assert session.IDLE.exists()
        session.restore()
        assert not any(call[0] == str(session.KEYBOARD_HELPER) for call in calls)
        session.power_on()
        assert not session.IDLE.exists()
# The native bridge must give Python valid standard descriptors after nohup.
mac_bridge = (root / 'macos/bin/mac-mouse-bridge.swift').read_text()
assert 'process.standardInput = FileHandle.nullDevice' in mac_bridge
assert 'process.standardOutput = log' in mac_bridge and 'process.standardError = log' in mac_bridge
assert 'heartbeat "$mac_host"' in (root / 'linux/bin/moonlight-mac-display').read_text()
for side in ('left', 'right'):
    config = (root / f'macos/sunshine/{side}/sunshine.conf.in').read_text()
    assert 'keyboard = disabled' in config and 'mouse = disabled' in config
assert 'keyboard = enabled' in (root / 'macos/sunshine/center/sunshine.conf.in').read_text()
print('OK: pointer mapping, click/drag regression, scripts, service templates and Sunshine input settings')
