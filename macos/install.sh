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
link_file "$root/macos/bin/mac-sunshine-three" "$HOME/.local/bin/mac-sunshine-three"
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
    write_config(root / 'macos/sunshine/apps.json', folder / 'apps.json')
for source in (root / 'macos/launchagents').glob('*.plist'):
    write_config(source, home / 'Library/LaunchAgents' / source.name)
PY

if [[ "$mode" != --no-start ]]; then
  for label in com.anthony.mac-mouse-bridge com.anthony.sunshine-three; do
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  done
  pkill -x mac-mouse-bridge 2>/dev/null || true
  pkill -f "^/Applications/Sunshine.app/Contents/MacOS/Sunshine $HOME/.config/sunshine-(left|center|right)/sunshine.conf$" 2>/dev/null || true
  rmdir "$HOME/.config/sunshine-three.lock" 2>/dev/null || true
  for label in com.anthony.mac-mouse-bridge com.anthony.sunshine-three; do
    launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$label.plist"
  done
fi
echo "Installed Mac source links and configuration from $root"
