# Mac to Linux screen streaming

Streams one or more BetterDisplay virtual Mac displays to monitors on a Linux PC (default: one screen; a multi-monitor desk is configuration). One Sunshine instance per screen (Mac) feeds one Moonlight window per screen (Linux). Mouse and special keys travel over a custom UDP bridge, not through Moonlight. Trusted LAN, one Mac and one Linux machine. The repository is generic: nothing about a particular user's machines may live in tracked files; everything machine-specific is in `~/.config/mac-three-screens/config`.

Also read, when they exist:
- `AGENTS.local.md`: personal, uncommitted instructions for this machine (gitignored). Follow it.
- `README.md`: human setup guide (install, pairing, permissions, display table).
- `docs/architecture.md`: UDP protocol, lease lifecycle, input rules, gotchas. Read before touching the bridge or session scripts.

## How it runs

```
Linux laptop                                        Mac
mac-three-screens start ─► systemd units          ─► Moonlight xN ══video═► Sunshine xN (47989, +200 per screen)
                           mac-three-screens@<name>                       capture BetterDisplay virtual screens
mac-mouse-bridge.service ──UDP 45991 (M/B/W/K/P/L/J…)──► mac-mouse-bridge (Swift, launchd) ─► CGEvent
                                                         mac-sunshine-three (launchd supervisor)
                                                         mac-sunshine-session (leases, brightness)
```

- The primary screen (`PRIMARY_SCREEN`, default the first) owns keyboard focus and the cursor. The others are view-only (Sunshine `mouse = disabled`); the Linux bridge sends all pointer input for every screen.
- Screens are only connected on the Mac while a stream holds a lease; they power off after the streams stop.
- Audio stays on the Mac (`stream_audio = false`).

## Layout

| Path | Purpose |
| --- | --- |
| `macos/install.sh` | Builds Swift bridge + keyboard helper, renders templates into `~/.config`, restarts launchd jobs |
| `macos/bin/mac-mouse-bridge.swift` | UDP receiver on the Mac; posts mouse/key events, handles wake/heartbeat/release/jitter |
| `macos/bin/mac-sunshine-three` | zsh supervisor (`lockf`, KeepAlive): resolves display IDs from BetterDisplay tags, runs one Sunshine instance per screen |
| `macos/bin/mac-sunshine-session` | Python: lease state, display on/off, internal panel + keyboard backlight save/restore |
| `macos/bin/mac-keyboard-backlight.m` | CoreBrightness helper (private API) |
| `macos/sunshine/sunshine.conf.in`, `apps.json` | Sunshine templates rendered once per screen (`@HOME@`, `@NAME@`, `@TITLE@`, `@PORT@`, `@FPS@`, `@KEYBOARD@`) |
| `macos/launchagents/*.plist` | LaunchAgent templates |
| `linux/install.sh` | Symlinks bin + units into `~/.local/bin` and `~/.config/systemd/user`, builds the cursor shim, starts the bridge |
| `linux/bin/mac-three-screens` | `start`, `restart`, `stop`, `status` for the configured screens' units |
| `linux/bin/moonlight-mac-display` | One Moonlight window: finds the Mac, wakes it, launches, places and fullscreens the window, heartbeats, jitter |
| `linux/bin/mac-mouse-bridge` | Python: reads X11 raw input / XQueryPointer via XWayland, maps to Mac coordinates, sends UDP |
| `linux/bin/mac-screens-wake` | Python UDP client: `wake`, `heartbeat`, `release`, `jitter` |
| `linux/bin/moonlight-show-cursor.c` | `LD_PRELOAD` shim forcing `SDL_ShowCursor` on so the Linux cursor shows on every stream |
| `linux/systemd/*.service`, `linux/kde/moonlight.kwinrule` | User units (`mac-three-screens@.service` is a template, instance = screen name); KDE rule that frees Super/Meta for the Mac |
| `common/mac-three-screens-config` | Reads the config. Python module and CLI (`names`, `primary`, `get`, `screen NAME`, `check linux\|mac`); symlinked into `linux/bin` and `macos/bin` so the scripts next to it can import it |
| `config.example`, `examples/three-screens.config` | Settings templates: single display, and a three-monitor desk (also the fixture for `tests/check.py`) |
| `tests/check.py`, `tests/check-bridge.py` | Offline regression check (also fails if private names such as a hostname leak into tracked files); live UDP flow check |

Both platforms run from a checkout at `~/Documents/mac-three-screens`. On Linux everything in `linux/bin` is symlinked, so edits are live. On the Mac, the session scripts and the config tool are *copied* to `~/.local/bin` by `macos/install.sh`, and the Swift bridge is compiled there.

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
tail -n 50 ~/.local/state/mac-three-screens/<name>.log
journalctl --user -u mac-mouse-bridge -n 50
```

Mac:
```sh
./macos/install.sh [--no-start]     # rebuilds the bridge; WITHOUT --no-start it restarts bridge + Sunshine
launchctl list | grep mac-three-screens   # mouse-bridge and supervisor jobs should be listed
~/.local/bin/mac-sunshine-session has-active
tail ~/.config/mac-mouse-bridge.log ~/.config/sunshine-three-autostart.log
```

## Configuration

One file on each machine, `~/.config/mac-three-screens/config` (KEY=value lines; template `config.example`, three-monitor example `examples/three-screens.config`). The same file works on both; each side reads what it needs. Read it only through `common/mac-three-screens-config` (module or CLI), never re-parse it in a script.

- Global: `MAC_HOST` (required on Linux), `MAC_JITTER_SECONDS` (default 60, `0` off), `SCREENS` (default `main`; order sets Sunshine ports 47989 + 200·index), `PRIMARY_SCREEN`, `INTERNAL_SCREEN_TAG`, `UNMIRROR_FROM`.
- Per screen `SCREEN_<NAME>_*`: `TAG` (required on the Mac), `WIDTH`, `HEIGHT`, `FPS`, `BITRATE` (Mbps), `WINDOW_X/Y`, `MAC_X/Y`, `MAC_WIDTH/HEIGHT`. Defaults live in `screens()` in the config tool; the README has the full table.
- Window title and Sunshine name are `Mac-<name>`; Moonlight profile `~/.config/moonlight-<name>`; Sunshine dir `~/.config/sunshine-<name>`.
- Add a setting by adding its default in `screens()` (or a `get` call) and documenting it in `config.example` and the README table, never by hard-coding a value in a script. Config changes take effect after `macos/install.sh` (Mac) and `mac-three-screens restart` (Linux).

## Rules and gotchas

- Never commit credentials, certificates, pairing state, `Moonlight.conf`, or `.local-backups/`. Never put passwords, keys, hostnames or IPs of private machines in tracked files.
- Edit the `.conf.in` templates, not `~/.config/sunshine-*/sunshine.conf`; the installer overwrites the live ones.
- Rebuilding `~/.local/bin/mac-mouse-bridge` makes macOS revoke its Accessibility permission. Symptom: the pointer moves but clicks do nothing, and `~/.config/mac-mouse-bridge.log` says it needs Accessibility. Fix: re-add the binary in System Settings → Privacy & Security → Accessibility, then `launchctl kickstart -k gui/$(id -u)/com.mac-three-screens.mouse-bridge`.
- Side-stream keyboard/mouse capture must stay off, or they overwrite the global Mac pointer.
- Do not send a pointer sample on button release; Moonlight shifts the pointer and Chromium turns it into a drag. `tests/check.py` guards this.
- Each wake/heartbeat/release must use a fresh UDP socket, and the Mac must close the flow after replying; otherwise the UDP flow table fills and renewals stop.
- `check linux` / `check mac` must pass before anything starts; the launchers exit 2 with a message otherwise.
- Cursor visibility depends on the `LD_PRELOAD` shim (`~/.local/lib/moonlight-show-cursor.so`), not on Moonlight's Ctrl+Alt+Shift+C toggle, which is stateful and unreliable.
- Display geometry, KDE behaviour and encoder load are specific to these machines; verify input changes with a real mouse after `tests/check.py` passes.
- launchd runs `~/.local/bin/mac-mouse-bridge` directly with `KeepAlive` (labels `com.mac-three-screens.mouse-bridge` and `.supervisor`); there is no AppleScript launcher any more.

## Permissions

Without asking: read files, run the offline checks, `bash -n` / `swiftc -typecheck`, view logs.
Ask first: `macos/install.sh` without `--no-start` (restarts the bridge and Sunshine and can drop a live stream or lose the Accessibility grant), `mac-three-screens restart|stop` while a stream is in use, deleting files, `git commit` / `git push`, installing packages, changing macOS privacy or KDE settings.
When stuck or when a change can only be verified on real hardware, say what you could not verify instead of guessing.

## Commits

Short imperative subject describing the behaviour change (see `git log`). Keep `README.md`, this file and `docs/architecture.md` in step with the code in the same commit.
