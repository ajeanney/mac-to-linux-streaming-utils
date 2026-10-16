# Mac three screens on Linux

Streams three BetterDisplay virtual Mac displays to three monitors on a Linux laptop. Three Sunshine instances (Mac) feed three Moonlight windows (Linux). Mouse and special keys travel over a custom UDP bridge, not through Moonlight. Personal use, trusted LAN, one Mac and one Linux machine.

Also read, when they exist:
- `AGENTS.local.md`: personal, uncommitted instructions for this machine (gitignored). Follow it.
- `README.md`: human setup guide (install, pairing, permissions, display table).
- `docs/architecture.md`: UDP protocol, lease lifecycle, input rules, gotchas. Read before touching the bridge or session scripts.

## How it runs

```
Linux laptop                                        Mac
mac-three-screens start ─► 3 systemd user units ─► Moonlight x3 ══video═► Sunshine x3 (ports 47989/48189/48389)
                           (left, center, right)                          capture BetterDisplay virtual screens
mac-mouse-bridge.service ──UDP 45991 (M/B/W/K/P/L/J…)──► mac-mouse-bridge (Swift, launchd) ─► CGEvent
                                                         mac-sunshine-three (launchd supervisor)
                                                         mac-sunshine-session (leases, brightness)
```

- Center stream owns keyboard focus and the cursor. Side streams are view-only (Sunshine `mouse = disabled`); the Linux bridge sends all pointer input for all three screens.
- Screens are only connected on the Mac while a stream holds a lease; they power off after the streams stop.
- Audio stays on the Mac (`stream_audio = false`).

## Layout

| Path | Purpose |
| --- | --- |
| `macos/install.sh` | Builds Swift bridge + keyboard helper, renders templates into `~/.config`, restarts launchd jobs |
| `macos/bin/mac-mouse-bridge.swift` | UDP receiver on the Mac; posts mouse/key events, handles wake/heartbeat/release/jitter |
| `macos/bin/mac-sunshine-three` | zsh supervisor (`lockf`, KeepAlive): resolves display IDs from BetterDisplay tags, runs the 3 Sunshine instances |
| `macos/bin/mac-sunshine-session` | Python: lease state, display on/off, internal panel + keyboard backlight save/restore |
| `macos/bin/mac-keyboard-backlight.m` | CoreBrightness helper (private API) |
| `macos/sunshine/{left,center,right}/sunshine.conf.in`, `apps.json` | Sunshine templates (`@HOME@`, `@SIDE@` placeholders) |
| `macos/launchagents/*.plist` | LaunchAgent templates |
| `linux/install.sh` | Symlinks bin + units into `~/.local/bin` and `~/.config/systemd/user`, builds the cursor shim, starts the bridge |
| `linux/bin/mac-three-screens` | `start [stable\|high]`, `restart`, `stop`, `status` for the 3 units |
| `linux/bin/moonlight-mac-display` | One Moonlight window: finds the Mac, wakes it, launches, places and fullscreens the window, heartbeats, jitter |
| `linux/bin/mac-mouse-bridge` | Python: reads X11 raw input / XQueryPointer via XWayland, maps to Mac coordinates, sends UDP |
| `linux/bin/mac-screens-wake` | Python UDP client: `wake`, `heartbeat`, `release`, `jitter` |
| `linux/bin/moonlight-show-cursor.c` | `LD_PRELOAD` shim forcing `SDL_ShowCursor` on so the Linux cursor shows on every stream |
| `linux/systemd/*.service`, `linux/kde/moonlight.kwinrule` | User units; KDE rule that frees Super/Meta for the Mac |
| `linux/environment.example` | Template for `~/.config/mac-three-screens/environment` |
| `tests/check.py`, `tests/check-bridge.py` | Offline regression check; live UDP flow check |

Both platforms run from a checkout at `~/Documents/mac-three-screens`. On Linux everything in `linux/bin` is symlinked, so edits are live. On the Mac, the two session scripts are *copied* to `~/.local/bin` by `macos/install.sh`, and the Swift bridge is compiled there.

## Commands

Offline checks (safe, no hardware needed):
```sh
python3 -I tests/check.py                          # mapping, click/drag, syntax of scripts and templates
swiftc -typecheck macos/bin/mac-mouse-bridge.swift # Mac only
bash -n linux/bin/<script>                         # single script syntax
python3 tests/check-bridge.py MAC_IP               # live; 1,100 heartbeats, sends no input
```

Linux (run on the laptop):
```sh
mac-three-screens start|restart|stop|status        # restart after editing moonlight-mac-display
systemctl --user restart mac-mouse-bridge          # after editing linux/bin/mac-mouse-bridge
systemctl --user daemon-reload                     # after editing linux/systemd/*
tail -n 50 ~/.local/state/mac-three-screens/center.log
journalctl --user -u mac-mouse-bridge -n 50
```

Mac:
```sh
./macos/install.sh [--no-start]     # rebuilds the bridge; WITHOUT --no-start it restarts bridge + Sunshine
launchctl list | grep anthony       # both com.anthony.* jobs should be listed
~/.local/bin/mac-sunshine-session has-active
tail ~/.config/mac-mouse-bridge.log ~/.config/sunshine-three-autostart.log
```

## Configuration

Linux, in `~/.config/mac-three-screens/environment` (systemd `EnvironmentFile`, uncommitted; template `linux/environment.example`):
- `MAC_MOUSE_BRIDGE_ADDRESS`: Mac hostname or wired IP (default `FR-K3KFKV6TFX.local`).
- `MAC_JITTER_SECONDS`: pointer jitter period while streaming (default 60, `0` disables).

Stream resolution, FPS, bitrate and window origins live in `linux/bin/moonlight-mac-display`. Mac display geometry for pointer mapping lives in `MAC_DISPLAYS` in `linux/bin/mac-mouse-bridge`. They must stay consistent with BetterDisplay and the `.conf.in` files (README has the table).

## Rules and gotchas

- Never commit credentials, certificates, pairing state, `Moonlight.conf`, or `.local-backups/`. Never put passwords, keys or IPs of private machines in tracked files.
- Edit the `.conf.in` templates, not `~/.config/sunshine-*/sunshine.conf`; the installer overwrites the live ones.
- Rebuilding `~/.local/bin/mac-mouse-bridge` makes macOS revoke its Accessibility permission. Symptom: the pointer moves but clicks do nothing, and `~/.config/mac-mouse-bridge.log` says it needs Accessibility. Fix: re-add the binary in System Settings → Privacy & Security → Accessibility, then `launchctl kickstart -k gui/$(id -u)/com.anthony.mac-mouse-bridge`.
- Side-stream keyboard/mouse capture must stay off, or they overwrite the global Mac pointer.
- Do not send a pointer sample on button release; Moonlight shifts the pointer and Chromium turns it into a drag. `tests/check.py` guards this.
- Each wake/heartbeat/release must use a fresh UDP socket, and the Mac must close the flow after replying; otherwise the UDP flow table fills and renewals stop.
- Cursor visibility depends on the `LD_PRELOAD` shim (`~/.local/lib/moonlight-show-cursor.so`), not on Moonlight's Ctrl+Alt+Shift+C toggle, which is stateful and unreliable.
- Display geometry, KDE behaviour and encoder load are specific to these machines; verify input changes with a real mouse after `tests/check.py` passes.
- The README still mentions an AppleScript launcher for the bridge; it was removed and launchd now runs the binary directly with `KeepAlive`.

## Permissions

Without asking: read files, run the offline checks, `bash -n` / `swiftc -typecheck`, view logs.
Ask first: `macos/install.sh` without `--no-start` (restarts the bridge and Sunshine and can drop a live stream or lose the Accessibility grant), `mac-three-screens restart|stop` while a stream is in use, deleting files, `git commit` / `git push`, installing packages, changing macOS privacy or KDE settings.
When stuck or when a change can only be verified on real hardware, say what you could not verify instead of guessing.

## Commits

Short imperative subject describing the behaviour change (see `git log`). Keep `README.md`, this file and `docs/architecture.md` in step with the code in the same commit.
