# Mac three screens on Linux

The working configuration for streaming three BetterDisplay virtual Mac displays to three monitors attached to a Linux PC. The repository contains both platforms' source files, service definitions, and non-secret configuration. It was collected from the working setup on 2 October 2026.

Video uses three independent Sunshine instances and three Moonlight windows. Keyboard input goes through the center stream. A Python bridge on Linux maps the desktop pointer to macOS coordinates and sends mouse events over UDP to a Swift bridge on the Mac. Audio stays on the Mac, including its USB headset.

## Repository layout

```text
macos/
  install.sh                          Build/install the Mac side
  bin/
    mac-sunshine-three                BetterDisplay/Sunshine supervisor
    mac-mouse-bridge.swift            Native mouse event receiver
    mac-mouse-bridge-launch.applescript  Launch receiver through Terminal
  launchagents/                      Login startup templates
  sunshine/
    apps.json                        Desktop application definition
    left/sunshine.conf.in             Portrait host settings
    center/sunshine.conf.in           Ultrawide host settings
    right/sunshine.conf.in            Landscape host settings
linux/
  install.sh                         Link the Linux side and start its bridge
  bin/
    mac-three-screens                Start/stop/restart all three streams
    moonlight-mac-display             Launch/place one Moonlight window
    mac-mouse-bridge                  Pointer and special-key sender
  systemd/                           User service definitions
  kde/moonlight.kwinrule              KDE shortcut exception for Moonlight
  environment.example                Optional wired host override
tests/check.py                       Desktop-independent regression check
.local-backups/                      Local installation/legacy backups; ignored
```

Keep this checkout in a permanent location, such as `~/Documents/mac-three-screens`. Linux scripts and user units are symlinks into it; the two Mac session scripts are copied into `~/.local/bin` so launchd can run them outside Documents. If you move the checkout, run the platform installer again to refresh installed files.

## Current display layout

These are the actual working settings, rather than the original proposed settings. `stable` and `high` currently use the same values; the center is streaming at **120 FPS**, and both side displays are at **60 FPS**.

| Screen | BetterDisplay tag | Mac logical size | Mac origin | Mac HiDPI backing size | Moonlight size | FPS | Bitrate | Linux window origin |
| --- | ---: | --- | --- | --- | --- | ---: | ---: | --- |
| Left portrait | 5 | 1080 × 1920 | −1080, −184 | 2160 × 3840 | 1200 × 2133 | 60 | 60 Mbps | 0, 0 |
| Center ultrawide | 6 | 3440 × 1440 | 0, 0 | 6880 × 2880 | 3440 × 1440 | 120 | 60 Mbps | 1200, 309 |
| Right landscape | 3 | 1920 × 1080 | 3440, 153 | 3840 × 2160 | 1920 × 1080 | 60 | 20 Mbps | 4640, 451 |

The center virtual display is the Mac's main display. The built-in display remains available but is outside the three streamed regions. Portrait stream coordinates are scaled to the portrait Mac desktop by the bridge.

The tag IDs belong to this BetterDisplay installation. macOS capture IDs change after reconnects or reboots; the supervisor resolves them from the tags and updates Sunshine automatically. A new BetterDisplay installation needs its own tag IDs.

## Dependencies

The captured working versions are macOS 27.0, BetterDisplay 5.0.6, Sunshine 2026.922.203725, and Moonlight Qt 6.1.0 on Arch Linux with KDE Plasma/KWin 6.7.5 and Wayland/XWayland. Other versions are not verified by this snapshot.

On the Mac, install [BetterDisplay](https://github.com/waydabber/BetterDisplay) and [Sunshine](https://github.com/LizardByte/Sunshine/releases) in `/Applications`. Install Apple's command line tools for `swiftc`, and make Python 3 available:

```sh
xcode-select --install
```

On Linux, install Moonlight Qt, Python 3, `xdotool`, `xinput`, XWayland, `libX11`, Avahi tools, and `iproute2`. `nmap` is used as a fallback for wired host discovery. For the current Arch system:

```sh
sudo pacman -S moonlight-qt python xdotool xorg-xinput xorg-xwayland libx11 avahi iproute2 nmap
```

The live bridge uses X11 raw input and XQueryPointer through XWayland. The launchers explicitly select Qt's `xcb` and SDL's `x11` backends. `wdotool`, `uinput`, and `evemu` were diagnostic tools and are not runtime dependencies.

## Mac setup

1. Open BetterDisplay and create/enable three virtual displays with the sizes, HiDPI backing resolutions, and refresh rates above. Arrange them in macOS Displays to match the Mac origins and make the center virtual display the main display. BetterDisplay must be running at login.
2. Confirm their tag IDs using BetterDisplay's CLI:

   ```sh
   /Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay get -identifiers
   ```

   If the tags differ, update `DISPLAYS` in `macos/bin/mac-sunshine-session` and the three `display_id_for_tag` calls in `macos/bin/mac-sunshine-three`. Also adapt the mirror-recovery display names there if you use different virtual-display names. The current names are `Virtuel 16:9` and `Virtuel 21:9`.
3. From the checkout, install the Mac side:

   ```sh
   cd ~/Documents/mac-three-screens
   ./macos/install.sh
   ```

   This builds the Swift receiver, compiles its AppleScript launcher, renders the Sunshine/LaunchAgent templates for your home directory, and starts the two login jobs. It restarts this setup's Sunshine instances and mouse receiver; reconnect the Linux streams afterward if they were running.
4. In macOS **Privacy & Security**, allow Sunshine screen recording and input permissions, and allow Terminal accessibility/input control. Allow the launcher to automate Terminal when macOS asks. The receiver runs through Terminal because that is the input-permission path used by this working setup. Keep the binary at `~/.local/bin/mac-mouse-bridge`.
5. Open each Sunshine web interface and create its local account if this is a fresh installation:

   | Instance | Stream address | Mac web interface |
   | --- | --- | --- |
   | Left | `MAC_WIRED_IP:47989` | `https://localhost:47990` |
   | Center | `MAC_WIRED_IP:48189` | `https://localhost:48190` |
   | Right | `MAC_WIRED_IP:48389` | `https://localhost:48390` |

   Let each instance generate its own certificates and state. The installer preserves existing identities and pairing files.
6. Add the built-in **French – PC / French-PC** input source to macOS Keyboard settings for the Linux AZERTY ISO keyboard. Switch input sources manually: French-PC for Linux input, French for the Mac keyboard. There is no custom keyboard layout file or automatic layout switching. The bridge handles the Linux `< >` and `²` keys that need special forwarding.
7. Select the Mac speakers or USB headset as the macOS audio output. All Sunshine templates have `stream_audio = false`; Moonlight audio is not part of this setup.

The supervisor refreshes Sunshine's capture IDs whenever the virtual screens connect. The Linux launcher wakes the Mac through the always-on mouse bridge before starting Moonlight, so all three displays can stay disconnected during normal Mac use.

Each stream holds a lease on the Mac while it runs. Sunshine runs a lease's `acquire` when a client connects, and each running Moonlight stream refreshes it every 45 seconds over the mouse bridge. When a stream ends on purpose it also sends a release, so `mac-three-screens stop` powers the screens down within seconds; the first stream to connect clears the wake hold, and a late wake request from a client that retried too long is ignored once a stream owns the screens. If the Mac hears nothing at all (crash, network cut, yanked cable) the lease simply expires after 150 seconds and the supervisor powers the screens down on its own.

A wake request writes a short lease of its own. That is what keeps the supervisor from powering the screens back down while Sunshine is still restarting around the new capture IDs.

The `com.anthony.sunshine-three` LaunchAgent has `KeepAlive`, because a supervisor that dies silently is the difference between "works" and "every stream returns 503". If you ever see 503s, check that the agent is running first: `launchctl list | grep anthony` and `mac-sunshine-session has-active`.

The built-in panel cannot be disconnected on this Mac: BetterDisplay 5.0.6 returns `Failed` for `set -tagID=2 -connected=off` and `-disconnectAllButMain` leaves it connected. Streaming instead blanks it by dropping its brightness to zero and puts the previous brightness back when the session ends. The value is saved in `~/.config/sunshine-three-internal-brightness` for the duration of the session.

The built-in keyboard backlight is switched off for the same reason. `hidutil property --set '{"KeyboardBacklightBrightness":...}'` is accepted by macOS and then ignored, so the bridge posts the same illumination media-key events `Fn+F5`/`Fn+F6` produce: sixteen down steps to go dark, and the level in `~/.config/sunshine-three-keyboard-backlight` mapped onto sixteen up steps to come back (`0` is off, `1` is full, and the installer writes `1.0` if the file is missing). Edit that file to match the level you normally keep. Only the mouse bridge can post those events, which is why this goes through it.

## Linux setup and pairing

1. Put the same repository at `~/Documents/mac-three-screens` on Linux. Run the installer from a terminal inside your KDE session:

   ```sh
   cd ~/Documents/mac-three-screens
   ./linux/install.sh
   ```

   It links the three commands and four systemd user units, creates the log directory, and enables/starts the mouse bridge. It leaves Sunshine/Moonlight pairing files intact. KDE creates a new XWayland authorization file each login; the bridge discovers it rather than pinning an old filename.
2. Import `linux/kde/moonlight.kwinrule` in **System Settings → Window Management → Window Rules**. The rule disables KDE global shortcuts while a Moonlight window has focus, so Super/Meta combinations reach the Mac as Command combinations. The existing Linux laptop already has this rule.
3. In KDE's window mouse actions, set the modifier + left-button action to **Nothing**. The current `~/.config/kwinrc` setting is:

   ```ini
   [MouseBindings]
   CommandAll1=Nothing
   ```

   This permits Command-click selection instead of KDE grabbing the window. It is a desktop-wide mouse binding. The installer does not overwrite your KDE configuration.
4. Pair each isolated Moonlight profile with its corresponding Sunshine instance. Open one GUI at a time from the KDE terminal:

   ```sh
   XDG_CONFIG_HOME="$HOME/.config/moonlight-left" QT_QPA_PLATFORM=xcb SDL_VIDEODRIVER=x11 moonlight
   XDG_CONFIG_HOME="$HOME/.config/moonlight-center" QT_QPA_PLATFORM=xcb SDL_VIDEODRIVER=x11 moonlight
   XDG_CONFIG_HOME="$HOME/.config/moonlight-right" QT_QPA_PLATFORM=xcb SDL_VIDEODRIVER=x11 moonlight
   ```

   Add `MAC_WIRED_IP:47989`, `MAC_WIRED_IP:48189`, and `MAC_WIRED_IP:48389` in the left, center, and right GUIs respectively. Enter each Moonlight PIN in the corresponding Sunshine web interface. Pair all three profiles separately and then close the GUIs.
5. Ensure `~/.local/bin` is on your shell's PATH, then start:

   ```sh
   mac-three-screens start
   ```

The default Bonjour name is `FR-K3KFKV6TFX.local`. For another Mac or a fixed wired address, edit `~/.config/mac-three-screens/environment`:

```ini
MAC_MOUSE_BRIDGE_ADDRESS=192.168.11.27
```

Restart the bridge and streams after changing it:

```sh
systemctl --user restart mac-mouse-bridge
mac-three-screens restart
```

Both bridge and video launchers otherwise look for reachable Sunshine addresses and prefer the faster path when the Mac advertises Wi-Fi and Ethernet addresses. Network discovery can take several seconds. Wired Ethernet is the intended connection.

## Daily use

```sh
mac-three-screens start          # Launch and place all three windows
mac-three-screens status
mac-three-screens restart
mac-three-screens stop
```

The center Moonlight window owns keyboard focus. The mouse bridge sends global Mac pointer events across all three displays. Side streams are viewers: Sunshine rejects both their mouse and keyboard input. The bridge releases side-window capture after clicks and returns keyboard focus to the center.

For normal Mac use, stop the streams on Linux. Within about two and a half minutes the leases expire and the Mac disconnects all three virtual displays. Starting `mac-three-screens` wakes them again before Moonlight connects.

To disable remote mouse input entirely:

```sh
systemctl --user stop mac-mouse-bridge
```

To restore it:

```sh
systemctl --user start mac-mouse-bridge
```

## Editing and updating

Edit files in the checkout. Linux scripts are linked directly; restart the mouse service after changing its Python code, and restart streams after changing the launcher. Run `systemctl --user daemon-reload` after changing Linux service definitions.

Mac Swift source changes need a rebuild with `./macos/install.sh`. Sunshine settings and LaunchAgent templates are rendered by that installer. Edit the `.conf.in` files in the repository rather than relying on live configuration edits to be retained across installation.

Both installers accept `--no-start` to install source links/configuration without restarting services. On the Mac, this mode preserves an existing bridge binary; it builds one only if missing. This was used for the initial reorganization so streaming could continue.

For another desk layout, change `MAC_DISPLAYS` in `linux/bin/mac-mouse-bridge` to the Mac's **logical** display coordinates. Change stream resolution/FPS/bitrate and Linux window origins in `linux/bin/moonlight-mac-display`, and update the corresponding Sunshine FPS target and BetterDisplay settings. Changing only the stream size does not change the mouse coordinate map.

To try 144 FPS on the center, change both center profile entries in the launcher, the center Sunshine FPS target, and the BetterDisplay refresh rate together. The committed snapshot preserves the working 120 FPS settings.

## Checks and troubleshooting

Run the small regression check from either checkout:

```sh
python3 tests/check.py
```

It checks pointer mapping, ordinary click versus genuine drag handling, script/template syntax, and side-stream input isolation. On the Mac you can also type-check the receiver:

```sh
swiftc -typecheck macos/bin/mac-mouse-bridge.swift
```

Linux diagnostics:

```sh
systemctl --user status mac-mouse-bridge
journalctl --user -u mac-mouse-bridge -n 50
tail -n 50 ~/.local/state/mac-three-screens/center.log
```

Mac logs are `~/.config/mac-mouse-bridge.log`, `~/.config/sunshine-three-autostart.log`, and `~/.config/sunshine-{left,center,right}/sunshine.log`.

- **Video connects but mouse clicks fail:** check the Linux bridge service and Terminal's macOS input permission. Check UDP port 45991 and both display coordinate maps.
- **Chromium reload opens its menu:** ordinary clicks must not send a new pointer sample on button release. That creates a synthetic drag when Moonlight shifts the pointer. The regression check protects this fix. Keep side Sunshine keyboard input disabled so local capture shortcuts cannot inject modifiers.
- **Command-click drags a Linux window or Command-V opens KDE clipboard:** check the imported window rule, KDE's modifier mouse binding, and center Moonlight focus.
- **A display reconnects incorrectly:** check BetterDisplay tags and arrangement, then Sunshine logs. Restart the Linux streams once the hosts are listening again.
- **No Mac audio:** check macOS output selection and that `stream_audio = false` remains in each host config.

## Files deliberately kept outside Git

Runtime state remains in the normal OS locations:

- Mac: `~/.config/sunshine-{left,center,right}/` contains credentials, certificates, pairing state, rendered configs, and logs. `~/.local/bin/mac-mouse-bridge` and `mac-mouse-bridge-launch.scpt` are generated artifacts; `~/Library/LaunchAgents` contains rendered startup files.
- Linux: `~/.config/moonlight-{left,center,right}/` contains each client identity and paired hosts. `~/.local/state/mac-three-screens/` contains stream logs. KDE settings and `~/.config/mac-three-screens/environment` are local settings.
- `.local-backups/` contains the pre-migration scripts and installer backups on each computer. It is ignored by Git.

Do not copy Sunshine credentials/certificates or whole Moonlight profiles into the repository. A fresh installation pairs again; restoring a machine's existing pairing state is a separate private backup operation. The receiver is an unauthenticated, unencrypted UDP input service intended for this trusted LAN, and it sends input while the bridge is running.

The repository is initialized locally with a baseline commit. It has no remote. Add a private remote of your choice to keep the Mac and Linux checkouts synchronized, then pull/reinstall on each platform when needed. Publishing a repository does not copy the ignored runtime identities.

## Upstream references

- [Sunshine configuration](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html): instance paths, ports, capture selection, and input/audio switches.
- [Moonlight setup and capture shortcuts](https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide): pairing and the capture, pointer lock, and local cursor toggles used by the launchers.
- [BetterDisplay CLI](https://github.com/waydabber/BetterDisplay/wiki/Integration-features,-CLI): installation-specific tag IDs and display identifiers.

This is a captured three-instance setup with a custom mouse bridge. Display geometry, KDE input behavior, and concurrent encoding capacity are specific to these machines; changes should be verified with a real mouse after the automated check.
