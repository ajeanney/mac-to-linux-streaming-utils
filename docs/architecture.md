# Architecture details

Deeper reference for `AGENTS.md`. Setup steps and the display table are in `README.md`.

## Control protocol (UDP 45991, Mac bridge)

Plain ASCII datagrams, space-separated. Handler: `handle()` in `macos/bin/mac-mouse-bridge.swift`. Sender: `linux/bin/mac-mouse-bridge` (input) and `linux/bin/mac-screens-wake` (session).

| Cmd | Args | Meaning | Reply |
| --- | --- | --- | --- |
| `M` | `x y` | Move pointer to absolute Mac logical coordinates | none |
| `B` | `button down` | Button press/release (1 left, 2 middle, 3 right) | none |
| `W` | `vertical horizontal` | Scroll | none |
| `S` / `D` / `V` | `down` | Shift / Command / Control held | none |
| `R` / `Q` / `C` | | Release Shift / Command / all modifiers | none |
| `I` / `T` | `down shift` | Special ISO (`< >`) and `²` keys | none |
| `J` | | Pointer jitter: +1 px then back after 50 ms; skipped while a button is held | none |
| `P` | | Prepare: bring virtual screens up (up to 180 s, off the input queue) | `READY` / `ERROR` |
| `K` | | Heartbeat: refresh the stream lease | `READY` |
| `L` | `role` | Release a lease (a screen name, or `all`) | `READY` |

Input messages are fire-and-forget. Session messages (`P`, `K`, `L`) are retried by the client until a reply or timeout, from a fresh socket each time.

## Lease lifecycle

1. `moonlight-mac-display` calls `mac-screens-wake wake` (`P`). The Mac writes a short wake lease and the supervisor connects the displays.
2. Sunshine's `apps.json` `prep-cmd` runs `mac-sunshine-session acquire <name>` when a client connects (records the lease only).
3. While Moonlight runs, a loop sends `K` every 45 s. Leases last 150 s (`LEASE_SECONDS`).
4. On exit, the launcher sends `L <name>`. If the Linux side vanishes, the lease expires and the supervisor powers the screens down.
5. State lives in a small JSON file written atomically by `mac-sunshine-session`; the supervisor uses `lockf` on `~/.config/sunshine-three-supervisor.lock`.

While a session is active the built-in panel is blanked (brightness 0, saved to `~/.config/sunshine-three-internal-brightness`) and the keyboard backlight and auto-brightness are saved, switched off, and restored afterwards (`mac-keyboard-backlight`).

## Linux pointer bridge

`linux/bin/mac-mouse-bridge` runs as a user service. It reads X11 raw input and `XQueryPointer` through XWayland (Qt `xcb`, SDL `x11`), finds which Moonlight window is under the pointer (`refresh_windows`), maps the position into that screen's Mac rectangle (`map_pointer`, `MAC_DISPLAYS`, built from the config's `MAC_*` keys) and sends `M`/`B`/`W`. It pauses forwarding while the primary window is minimized, releases held buttons/modifiers, and follows the host recorded in `~/.local/state/mac-three-screens/host`.

## Moonlight window handling

`moonlight-mac-display <name>` ranks Mac addresses by ping (mDNS, last working IP, subnet sweep as last resort), wakes the Mac, starts `moonlight stream` with the profile's resolution/FPS/bitrate, then with `xdotool` moves the window to its origin, fullscreens it, disables the pointer-region lock (Ctrl+Alt+Shift+L), turns capture off on non-primary windows (Ctrl+Alt+Shift+Z), and rechecks fullscreen for about 10 s while the decoder initialises. `mac-three-screens start` finally activates the primary window. The primary screen also runs the jitter loop.

## Input-permission model

Moving the cursor (`CGWarpMouseCursorPosition`) works without permission, so a missing Accessibility grant looks like "moves but no clicks". Posting clicks and keys needs `~/.local/bin/mac-mouse-bridge` listed under Accessibility. The binary is rebuilt by `macos/install.sh`, which invalidates the grant.
