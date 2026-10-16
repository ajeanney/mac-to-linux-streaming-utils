#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:-}
if [[ -n "$mode" && "$mode" != --no-start ]]; then
  echo "usage: $0 [--no-start]" >&2
  exit 2
fi
backup="$root/.local-backups/$(date +%Y%m%d-%H%M%S)-macos"
mkdir -p "$HOME/.local/bin" "$HOME/.config/mac-three-screens" "$HOME/Library/LaunchAgents"

config="$HOME/.config/mac-three-screens/config"
if [[ ! -e "$config" ]]; then
  cp "$root/config.example" "$config"
  echo "Created $config. Set your BetterDisplay tags in it (see examples/), then run this again." >&2
  exit 2
fi
python3 "$root/common/mac-three-screens-config" check mac || exit 2

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
install_script "$root/common/mac-three-screens-config" "$HOME/.local/bin/mac-three-screens-config"
install_script "$root/macos/bin/mac-sunshine-three" "$HOME/.local/bin/mac-sunshine-three"
install_script "$root/macos/bin/mac-sunshine-session" "$HOME/.local/bin/mac-sunshine-session"
link_file "$root/macos/bin/mac-mouse-bridge.swift" "$HOME/.local/bin/mac-mouse-bridge.swift"
clang -framework Foundation "$root/macos/bin/mac-keyboard-backlight.m" -o "$HOME/.local/bin/mac-keyboard-backlight"

# Keep the executable at its existing path for macOS input permissions.
if [[ "$mode" != --no-start || ! -x "$HOME/.local/bin/mac-mouse-bridge" ]]; then
  swiftc "$root/macos/bin/mac-mouse-bridge.swift" -o "$HOME/.local/bin/mac-mouse-bridge.new"
  mv "$HOME/.local/bin/mac-mouse-bridge.new" "$HOME/.local/bin/mac-mouse-bridge"
fi

python3 - "$root" "$backup" <<'PY'
from pathlib import Path
import importlib.machinery, importlib.util, re, shutil, sys
root, backup = map(Path, sys.argv[1:])
home = Path.home()
loader = importlib.machinery.SourceFileLoader('screens_config', str(root / 'common/mac-three-screens-config'))
screens_config = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(screens_config)

def render(text, **values):
    for key, value in {'HOME': home, **values}.items():
        text = text.replace(f'@{key}@', str(value))
    return text

def write_config(source, target, **values):
    text = render(source.read_text(), **values)
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

for screen in screens_config.screens():
    name = screen['name']
    folder = home / '.config' / f'sunshine-{name}'
    write_config(root / 'macos/sunshine/sunshine.conf.in', folder / 'sunshine.conf',
                 NAME=name, TITLE=screen['title'], PORT=screen['port'], FPS=screen['fps'],
                 KEYBOARD='enabled' if screen['primary'] else 'disabled')
    app_template = render((root / 'macos/sunshine/apps.json').read_text(), NAME=name)
    apps_target = folder / 'apps.json'
    if apps_target.exists() and apps_target.read_text() != app_template:
        archive = backup / apps_target.relative_to(home)
        archive.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(apps_target, archive)
    apps_target.parent.mkdir(parents=True, exist_ok=True)
    apps_target.write_text(app_template)
for source in (root / 'macos/launchagents').glob('*.plist'):
    write_config(source, home / 'Library/LaunchAgents' / source.name)
# Fallback restore level when the keyboard was already dark at session start.
backlight = home / '.config' / 'sunshine-three-keyboard-backlight'
if not backlight.exists():
    backlight.write_text('1.0\n')
PY

labels=(com.mac-three-screens.mouse-bridge com.mac-three-screens.supervisor)
if [[ "$mode" != --no-start ]]; then
  # Older installs used com.anthony.* labels; retire them.
  for label in com.anthony.mac-mouse-bridge com.anthony.sunshine-three; do
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/$label.plist"
  done
  for label in "${labels[@]}"; do
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  done
  pkill -x mac-mouse-bridge 2>/dev/null || true
  pkill -f "^/Applications/Sunshine.app/Contents/MacOS/Sunshine $HOME/.config/sunshine-[^/]+/sunshine.conf$" 2>/dev/null || true
  for label in "${labels[@]}"; do
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
  for label in "${labels[@]}"; do
    if ! launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
      launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$label.plist"
    fi
  done
fi
echo "Installed Mac source links and configuration from $root"
