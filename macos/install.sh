#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:-}
if [[ -n "$mode" && "$mode" != --no-start ]]; then
  echo "usage: $0 [--no-start]" >&2
  exit 2
fi
backup="$root/.local-backups/$(date +%Y%m%d-%H%M%S)-macos"
mkdir -p "$HOME/.local/bin" "$HOME/.config" "$HOME/Library/LaunchAgents"

link_file() {
  local source=$1 target=$2
  if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then return; fi
  if [[ -e "$target" || -L "$target" ]]; then
    mkdir -p "$backup"
    mv "$target" "$backup/$(basename "$target")"
  fi
  ln -s "$source" "$target"
}

install_script() {
  local source=$1 target=$2
  if [[ -f "$target" && ! -L "$target" ]] && cmp -s "$source" "$target"; then return; fi
  if [[ -e "$target" || -L "$target" ]]; then
    mkdir -p "$backup"
    mv "$target" "$backup/$(basename "$target")"
  fi
  cp "$source" "$target"
  chmod 755 "$target"
}

# launchd cannot reliably open scripts through the Documents symlinks.
install_script "$root/macos/bin/mac-sunshine-three" "$HOME/.local/bin/mac-sunshine-three"
install_script "$root/macos/bin/mac-sunshine-session" "$HOME/.local/bin/mac-sunshine-session"
link_file "$root/macos/bin/mac-mouse-bridge.swift" "$HOME/.local/bin/mac-mouse-bridge.swift"

# Keep the executable at its existing path for macOS input permissions.
if [[ "$mode" != --no-start || ! -x "$HOME/.local/bin/mac-mouse-bridge" ]]; then
  swiftc "$root/macos/bin/mac-mouse-bridge.swift" -o "$HOME/.local/bin/mac-mouse-bridge.new"
  mv "$HOME/.local/bin/mac-mouse-bridge.new" "$HOME/.local/bin/mac-mouse-bridge"
fi
osacompile -o "$HOME/.local/bin/mac-mouse-bridge-launch.scpt" \
  "$root/macos/bin/mac-mouse-bridge-launch.applescript" >/dev/null

python3 - "$root" "$backup" <<'PY'
from pathlib import Path
import re, shutil, sys
root, backup = map(Path, sys.argv[1:])
home = Path.home()

def write_config(source, target):
    text = source.read_text().replace('@HOME@', str(home))
    if target.exists():
        original = target.read_text()
        if target.name == 'sunshine.conf':
            display = re.search(r'^output_name = (.*)$', original, re.MULTILINE)
            if display:
                text = re.sub(r'^output_name = .*$', lambda _: display[0], text, flags=re.MULTILINE)
        if original == text:
            return
        archive = backup / target.relative_to(home)
        archive.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(target, archive)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text)

for side in ('left', 'center', 'right'):
    folder = home / '.config' / f'sunshine-{side}'
    write_config(root / f'macos/sunshine/{side}/sunshine.conf.in', folder / 'sunshine.conf')
    app_template = (root / 'macos/sunshine/apps.json').read_text()
    app_template = app_template.replace('@HOME@', str(home)).replace('@SIDE@', side)
    apps_target = folder / 'apps.json'
    if apps_target.exists() and apps_target.read_text() != app_template:
        archive = backup / apps_target.relative_to(home)
        archive.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(apps_target, archive)
    apps_target.parent.mkdir(parents=True, exist_ok=True)
    apps_target.write_text(app_template)
for source in (root / 'macos/launchagents').glob('*.plist'):
    write_config(source, home / 'Library/LaunchAgents' / source.name)
# Only the level to put back when a stream ends is configurable: macOS cannot
# report the current keyboard backlight level, so the user owns this value.
backlight = home / '.config' / 'sunshine-three-keyboard-backlight'
if not backlight.exists():
    backlight.write_text('1.0\n')
PY

if [[ "$mode" != --no-start ]]; then
  for label in com.anthony.mac-mouse-bridge com.anthony.sunshine-three; do
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  done
  pkill -x mac-mouse-bridge 2>/dev/null || true
  pkill -f "^/Applications/Sunshine.app/Contents/MacOS/Sunshine $HOME/.config/sunshine-(left|center|right)/sunshine.conf$" 2>/dev/null || true
  rmdir "$HOME/.config/sunshine-three.lock" 2>/dev/null || true
  for label in com.anthony.mac-mouse-bridge com.anthony.sunshine-three; do
    # bootout returns before the label is gone, so checking too early used to
    # pick kickstart on a job that was still being removed and leave nothing
    # running. Wait for it to disappear, then load it again.
    for _ in {1..20}; do
      launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1 || break
      sleep 0.5
    done
    launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$label.plist"
  done
  sleep 2
  for label in com.anthony.mac-mouse-bridge com.anthony.sunshine-three; do
    if ! launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
      launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$label.plist"
    fi
  done
fi
echo "Installed Mac source links and configuration from $root"
