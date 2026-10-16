# Mac to Linux screen streaming

Stream one or more BetterDisplay virtual Mac displays to monitors attached to a Linux PC, with the Linux mouse and keyboard controlling the Mac. The default is a single display; a multi-monitor desk (for example portrait + ultrawide + landscape) is a matter of configuration. The repository contains both platforms' source files, service definitions and non-secret configuration templates.

Video uses one Sunshine instance per screen on the Mac and one Moonlight window per screen on Linux. Keyboard input goes through the primary screen's stream. A Python bridge on Linux maps the desktop pointer to macOS coordinates and sends mouse events over UDP to a Swift bridge on the Mac. Audio stays on the Mac.

## Repository layout

```text
config.example                        Settings template (single display)
examples/three-screens.config         Settings for a three-monitor desk
common/mac-three-screens-config       Settings reader shared by both platforms
macos/
  install.sh                          Build/install the Mac side
  bin/
    mac-sunshine-three                BetterDisplay/Sunshine supervisor
    mac-sunshine-session              Display leases and brightness restore
    mac-keyboard-backlight.m          Native keyboard brightness helper
    mac-mouse-bridge.swift            Native mouse event receiver
  launchagents/                       Login startup templates
  sunshine/
    apps.json                         Desktop application definition
    sunshine.conf.in                  Per-screen Sunshine settings template
linux/
  install.sh                          Link the Linux side and start its bridge
  bin/
    mac-three-screens                 Start/stop/restart all streams
    moonlight-mac-display             Launch/place one Moonlight window
    mac-mouse-bridge                  Pointer and special-key sender
    mac-screens-wake                  Wake/heartbeat/release client
    moonlight-show-cursor.c           Keeps the Linux cursor visible
  systemd/                            User service definitions
  kde/moonlight.kwinrule              KDE shortcut exception for Moonlight
tests/                                Desktop-independent regression checks
```

Keep this checkout in a permanent location, such as `~/Documents/mac-three-screens`. Linux scripts and user units are symlinks into it; the Mac session scripts are copied into `~/.local/bin` so launchd can run them outside Documents. If you move the checkout, run the platform installer again to refresh installed files.

## Configuration

Both machines read `~/.config/mac-three-screens/config`. The installers create it from `config.example` if it is missing. The same file works on both sides; each side uses the keys it needs. Nothing about your machines is stored in the repository.

```ini
MAC_HOST=my-mac.local          # Linux: Bonjour name or wired IP of the Mac (required)
SCREENS=main                   # one stream per name
SCREEN_MAIN_TAG=1              # Mac: BetterDisplay tag of that virtual display (required)
```

With only those three lines you get one 1920 × 1080 @ 60 fps stream at the top-left of the Linux desktop. Every other key is optional:

| Key | Default | Used by | Meaning |
| --- | --- | --- | --- |
| `MAC_HOST` | none (required) | Linux | Mac hostname or IP. Prefer a reserved wired address. |
| `MAC_JITTER_SECONDS` | `60` | Linux | Nudge the Mac pointer 1 px and back this often while streaming; `0` disables. |
| `SCREENS` | `main` | both | Space-separated screen names (lowercase letters, digits, dashes). Order sets the port: the first is 47989, each next one +200. |
| `PRIMARY_SCREEN` | first screen | both | The screen that keeps keyboard focus and receives typing; the others are view-only. |
| `SCREEN_<NAME>_TAG` | none (required) | Mac | BetterDisplay tag of the virtual display. |
| `SCREEN_<NAME>_WIDTH` / `_HEIGHT` | `1920` / `1080` | both | Stream size in pixels. |
| `SCREEN_<NAME>_FPS` / `_BITRATE` | `60` / `20` | both | Frame rate and bitrate (Mbps). |
| `SCREEN_<NAME>_WINDOW_X` / `_WINDOW_Y` | `0` / `0` | Linux | Top-left of the window on the Linux desktop. |
| `SCREEN_<NAME>_MAC_X` / `_MAC_Y` | `0` / `0` | Linux | Top-left of the display in the Mac's logical desktop coordinates (negative for a display left of or above the main one). |
| `SCREEN_<NAME>_MAC_WIDTH` / `_MAC_HEIGHT` | stream size | Linux | The display's logical size, used to map the pointer. Differs from the stream size when the Mac display is HiDPI or the stream is scaled. |
| `INTERNAL_SCREEN_TAG` | unset | Mac | BetterDisplay tag of the built-in panel; blanked while streaming and restored afterwards. |
| `UNMIRROR_FROM` | `Color LCD` | Mac | Display names (comma separated) the primary display is un-mirrored from after the virtual screens were off. |

`<NAME>` is the screen name upper-cased with dashes turned into underscores (`left-2` → `SCREEN_LEFT_2_TAG`). Window titles and Sunshine names are `Mac-<name>`.

`examples/three-screens.config` is a complete three-monitor layout (portrait, ultrawide, landscape) with the Mac arrangement and window origins that go with it; copy it and replace `MAC_HOST` and the tags. After changing the file, run the Mac installer again (it regenerates the Sunshine settings and restarts the supervisor) and `mac-three-screens restart` on Linux.

To get the tags, use BetterDisplay's CLI. Tags belong to your BetterDisplay installation; macOS capture IDs change after reconnects or reboots, and the supervisor resolves them from the tags and updates Sunshine automatically.

```sh
/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay get -identifiers
```

## Dependencies

Developed on macOS 27 with BetterDisplay 5.0.6 and Sunshine 2026.922, and on Arch Linux with KDE Plasma/KWin 6.7 under Wayland/XWayland with Moonlight Qt 6. Other versions are not verified.

On the Mac, install [BetterDisplay](https://github.com/waydabber/BetterDisplay) and [Sunshine](https://github.com/LizardByte/Sunshine/releases) in `/Applications`. Install Apple's command line tools for `swiftc` and `clang`, and make Python 3 available:

```sh
xcode-select --install
```

On Linux, install Moonlight Qt, Python 3, a C compiler, `xdotool`, `xinput`, XWayland, `libX11`, Avahi tools, and `iproute2`. `nmap` is used as a fallback for wired host discovery. On Arch:

```sh
sudo pacman -S moonlight-qt python gcc xdotool xorg-xinput xorg-xwayland libx11 avahi iproute2 nmap
```

The live bridge uses X11 raw input and XQueryPointer through XWayland. The launchers explicitly select Qt's `xcb` and SDL's `x11` backends.

## Mac setup

1. Open BetterDisplay and create/enable one virtual display per screen with the sizes, HiDPI backing resolutions and refresh rates you want. Arrange them in macOS Displays to match the `MAC_X`/`MAC_Y` values you will configure, and make the primary screen's virtual display the main display. BetterDisplay must be running at login.
2. Create the config (see [Configuration](#configuration)) with your tags, either by copying `config.example` to `~/.config/mac-three-screens/config` or by running the installer once, which creates it and stops so you can fill it in.
3. From the checkout, install the Mac side:

   ```sh
   cd ~/Documents/mac-three-screens
   ./macos/install.sh
   ```

   This builds the Swift receiver, renders the Sunshine/LaunchAgent templates for your home directory and screens, and starts the two login jobs. It restarts this setup's Sunshine instances and mouse receiver; reconnect the Linux streams afterward if they were running.
4. In macOS **Privacy & Security**, allow Sunshine screen recording and input permissions, and allow `~/.local/bin/mac-mouse-bridge` accessibility/input control. The receiver runs directly under launchd with `KeepAlive`, so closing Terminal cannot stop it and a crashed receiver restarts automatically. Keep the binary at `~/.local/bin/mac-mouse-bridge`. macOS drops the grant whenever the binary is rebuilt: if the pointer moves but clicks do nothing, remove and re-add it, then restart the job with `launchctl kickstart -k gui/$(id -u)/com.mac-three-screens.mouse-bridge`.
5. Open each Sunshine web interface and create its local account if this is a fresh installation. Screen *n* (counting from 0) streams on port `47989 + 200·n`; its web interface is on the port 1 above that, at `https://localhost:<port>`.

   | Screen (in `SCREENS` order) | Stream address | Mac web interface |
   | --- | --- | --- |
   | 1st | `MAC_HOST:47989` | `https://localhost:47990` |
   | 2nd | `MAC_HOST:48189` | `https://localhost:48190` |
   | 3rd | `MAC_HOST:48389` | `https://localhost:48390` |

   Let each instance generate its own certificates and state. The installer preserves existing identities and pairing files.
6. The bridge forwards two keys specially for a French AZERTY ISO keyboard (the ISO key beside Left Shift and the `²` key). If that is your layout, add the built-in **French – PC / French-PC** input source in macOS Keyboard settings and switch between it (for Linux input) and the Mac's own layout manually. Other layouts may need small changes in `linux/bin/mac-mouse-bridge` and `macos/bin/mac-mouse-bridge.swift`.
7. Select the Mac speakers or a headset as the macOS audio output. All Sunshine configs have `stream_audio = false`; Moonlight audio is not part of this setup.

The supervisor refreshes Sunshine's capture IDs whenever the virtual screens connect. The Linux launcher wakes the Mac through the always-on mouse bridge before starting Moonlight, so the virtual displays can stay disconnected during normal Mac use.

Each stream holds a lease on the Mac while it runs. Sunshine runs a lease's `acquire` when a client connects (this hook only records the lease; display setup is done by the Linux wake request), and each running Moonlight stream refreshes it every 45 seconds over the mouse bridge. When a stream ends on purpose it also sends a release, so `mac-three-screens stop` powers the screens down within seconds; the first stream to connect clears the wake hold, and a late wake request from a client that retried too long is ignored once a stream owns the screens. If the Mac hears nothing at all (crash, network cut, yanked cable) the lease simply expires after 150 seconds and the supervisor powers the screens down on its own.

Leases are renewed by the running Moonlight processes, independently of keyboard or mouse activity. The Mac bridge closes each wake/heartbeat/release UDP flow after replying; otherwise the accumulating client ports can exhaust the UDP flow table, stop renewals, and block subsequent starts. Failed renewals appear in the Linux stream logs.

A wake request writes a short lease of its own. That is what keeps the supervisor from powering the screens back down while Sunshine is still restarting around the new capture IDs.

The supervisor uses macOS `lockf` with `~/.config/sunshine-three-supervisor.lock`; the kernel releases the lock on process exit or reboot, even if the file remains. Failed startup clears its wake lease and restores the Mac; Linux reports a preparation error instead of launching Moonlight against an unresolved host. The last working IP is also tried when mDNS is late.

The `com.mac-three-screens.supervisor` LaunchAgent has `KeepAlive`, because a supervisor that dies silently is the difference between "works" and "every stream returns 503". If you ever see 503s, check that the agent is running first: `launchctl list | grep mac-three-screens` and `mac-sunshine-session has-active`.

On an Apple silicon laptop the built-in panel cannot always be disconnected through BetterDisplay. Setting `INTERNAL_SCREEN_TAG` blanks it by dropping its brightness to zero during streaming and puts the previous brightness back when the session ends; the value is saved in `~/.config/sunshine-three-internal-brightness` for the duration of the session.

The built-in keyboard backlight is switched off through the small native `mac-keyboard-backlight` helper, compiled by the Mac installer. It uses CoreBrightness directly; simulated brightness keys and `hidutil` do not work on current macOS. The session saves the current keyboard brightness and automatic brightness setting, disables automatic brightness while streaming, then restores both on stop. If the keyboard was already dark, `~/.config/sunshine-three-keyboard-backlight` provides the restore level (`0`–`1`, default `1.0`). CoreBrightness is a private macOS interface: the helper reports an error if a future macOS version changes it.

The Linux bridge follows the address selected by the streaming launcher, recorded in `~/.local/state/mac-three-screens/host`, instead of retaining the address guessed at login. Heartbeats and releases also use that same address.

## Linux setup and pairing

1. Put the same repository at `~/Documents/mac-three-screens` on Linux. Run the installer from a terminal inside your KDE session:

   ```sh
   cd ~/Documents/mac-three-screens
   ./linux/install.sh
   ```

   It links the commands and systemd user units, builds the cursor shim, creates the log directory, and enables/starts the mouse bridge. If `~/.config/mac-three-screens/config` does not exist yet it creates it from `config.example` and stops; set `MAC_HOST` (and your screens) and run it again. It leaves Sunshine/Moonlight pairing files intact. KDE creates a new XWayland authorization file each login; the bridge discovers it rather than pinning an old filename.
2. Import `linux/kde/moonlight.kwinrule` in **System Settings → Window Management → Window Rules**. The rule disables KDE global shortcuts while a Moonlight window has focus, so Super/Meta combinations reach the Mac as Command combinations.
3. In KDE's window mouse actions, set the modifier + left-button action to **Nothing**. The `~/.config/kwinrc` setting is:

   ```ini
   [MouseBindings]
   CommandAll1=Nothing
   ```

   This permits Command-click selection instead of KDE grabbing the window. It is a desktop-wide mouse binding. The installer does not overwrite your KDE configuration.
4. Pair each isolated Moonlight profile with its corresponding Sunshine instance. Each screen has its own profile directory, `~/.config/moonlight-<name>`. Open one GUI at a time from the KDE terminal, add `MAC_HOST:<port>` for that screen, and enter the PIN shown by Moonlight in that screen's Sunshine web interface:

   ```sh
   XDG_CONFIG_HOME="$HOME/.config/moonlight-main" QT_QPA_PLATFORM=xcb SDL_VIDEODRIVER=x11 moonlight
   ```

   Pair every screen's profile separately and then close the GUIs.
5. Ensure `~/.local/bin` is on your shell's PATH, then start:

   ```sh
   mac-three-screens start
   ```

Both bridge and video launchers look for reachable Sunshine addresses and prefer the faster path when the Mac advertises Wi-Fi and Ethernet addresses. Network discovery can take several seconds. Wired Ethernet is the intended connection. After changing `MAC_HOST`:

```sh
systemctl --user restart mac-mouse-bridge
mac-three-screens restart
```

## Daily use

```sh
mac-three-screens start          # Launch and place all windows
mac-three-screens status
mac-three-screens restart
mac-three-screens stop
```

The primary screen's Moonlight window owns keyboard focus. The mouse bridge sends global Mac pointer events across all screens. The other streams are viewers: Sunshine rejects both their mouse and keyboard input. The bridge releases their capture after clicks and returns keyboard focus to the primary.

Minimize the primary stream with **Ctrl+Shift+Alt+D** to use the Linux desktop. While it is minimized, the bridge pauses mouse and special-key forwarding on all screens and releases held buttons/modifiers. Side-window clicks cannot restore the primary stream. Restore its window to resume control; minimized side windows never receive mouse input.

`mac-three-screens stop` explicitly releases all display sessions after closing Moonlight, including while minimized. It reports an error if the Mac does not acknowledge a release. Startup rechecks fullscreen during the first ten seconds while Moonlight initializes its video surface.

For normal Mac use, stop the streams on Linux. Within about two and a half minutes the leases expire and the Mac disconnects the virtual displays. Starting `mac-three-screens` wakes them again before Moonlight connects.

To disable remote mouse input entirely, `systemctl --user stop mac-mouse-bridge`; to restore it, `systemctl --user start mac-mouse-bridge`.

## Editing and updating

Edit files in the checkout. Linux scripts are linked directly; restart the mouse service after changing its Python code, and restart streams after changing the launcher. Run `systemctl --user daemon-reload` after changing Linux service definitions.

Mac Swift source changes need a rebuild with `./macos/install.sh`. Sunshine settings and LaunchAgent templates are rendered by that installer. Edit `macos/sunshine/sunshine.conf.in` rather than relying on live configuration edits to be retained across installation.

Both installers accept `--no-start` to install source links/configuration without restarting services. On the Mac, this mode preserves an existing bridge binary; it builds one only if missing.

For another desk layout, edit the config: stream size, FPS, bitrate and window origins are per screen, and the `MAC_*` keys are the **logical** display coordinates the pointer is mapped to. Changing only the stream size does not change the mouse coordinate map. Keep the BetterDisplay refresh rate in step with `FPS`.

## Checks and troubleshooting

Run the small regression check from either checkout:

```sh
python3 tests/check.py
```

It checks pointer mapping, ordinary click versus genuine drag handling, the config reader, script/template syntax, and side-stream input isolation. On the Mac you can also type-check the receiver:

```sh
swiftc -typecheck macos/bin/mac-mouse-bridge.swift
```

To check the control bridge from Linux with a running or idle Mac (no mouse or keyboard events are sent):

```sh
python3 tests/check-bridge.py MAC_IP
```

This opens 1,100 fresh UDP client sockets to catch the old flow accumulation failure.

Linux diagnostics:

```sh
systemctl --user status mac-mouse-bridge
journalctl --user -u mac-mouse-bridge -n 50
tail -n 50 ~/.local/state/mac-three-screens/<name>.log
mac-three-screens-config check linux
```

Mac logs are `~/.config/mac-mouse-bridge.log`, `~/.config/sunshine-three-autostart.log`, and `~/.config/sunshine-<name>/sunshine.log`; `mac-three-screens-config check mac` validates the config.

- **Video connects but mouse clicks fail:** check the Linux bridge service and the mouse bridge's macOS Accessibility permission. Check UDP port 45991 and the `MAC_*` coordinates.
- **The Linux cursor is invisible over a stream:** Moonlight hides it while capturing. The launcher preloads `~/.local/lib/moonlight-show-cursor.so` to keep it visible; re-run `linux/install.sh` if that file is missing.
- **Chromium reload opens its menu:** ordinary clicks must not send a new pointer sample on button release. That creates a synthetic drag when Moonlight shifts the pointer. The regression check protects this fix. Keep non-primary Sunshine keyboard input disabled so local capture shortcuts cannot inject modifiers.
- **Command-click drags a Linux window or Command-V opens KDE clipboard:** check the imported window rule, KDE's modifier mouse binding, and primary Moonlight focus.
- **A display reconnects incorrectly:** check BetterDisplay tags and arrangement, then Sunshine logs. Restart the Linux streams once the hosts are listening again.
- **No Mac audio:** check macOS output selection and that `stream_audio = false` remains in each host config.

## Files deliberately kept outside Git

Runtime state remains in the normal OS locations:

- Mac: `~/.config/sunshine-<name>/` contains credentials, certificates, pairing state, rendered configs, and logs. `~/.local/bin/mac-mouse-bridge` is a generated executable; `~/Library/LaunchAgents` contains rendered startup files.
- Linux: `~/.config/moonlight-<name>/` contains each client identity and paired hosts. `~/.local/state/mac-three-screens/` contains stream logs.
- Both: `~/.config/mac-three-screens/config` is your local settings file. KDE settings are local too.

Do not copy Sunshine credentials/certificates or whole Moonlight profiles into the repository. A fresh installation pairs again. The receiver is an unauthenticated, unencrypted UDP input service intended for a trusted LAN, and it sends input while the bridge is running.

## Upstream references

- [Sunshine configuration](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html): instance paths, ports, capture selection, and input/audio switches.
- [Moonlight setup and capture shortcuts](https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide): pairing and the capture and pointer-lock toggles used by the launchers.
- [BetterDisplay CLI](https://github.com/waydabber/BetterDisplay/wiki/Integration-features,-CLI): tag IDs and display identifiers.

Display geometry, KDE input behavior, and concurrent encoding capacity vary by machine; verify changes with a real mouse after the automated check.
