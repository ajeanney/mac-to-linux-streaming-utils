#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:-}
if [[ -n "$mode" && "$mode" != --no-start ]]; then
  echo "usage: $0 [--no-start]" >&2
  exit 2
fi
backup="$root/.local-backups/$(date +%Y%m%d-%H%M%S)-linux"
mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user" \
  "$HOME/.config/mac-three-screens" "$HOME/.local/state/mac-three-screens"

link_file() {
  local source=$1 target=$2
  if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then return; fi
  if [[ -e "$target" || -L "$target" ]]; then
    mkdir -p "$backup"
    mv "$target" "$backup/$(basename "$target")"
  fi
  ln -s "$source" "$target"
}

for source in "$root"/linux/bin/*; do
  if [[ -f "$source" && "$source" != *.c ]]; then link_file "$source" "$HOME/.local/bin/$(basename "$source")"; fi
done
for source in "$root"/linux/systemd/*.service; do
  link_file "$source" "$HOME/.config/systemd/user/$(basename "$source")"
done
mkdir -p "$HOME/.local/lib"
cc -shared -fPIC -O2 "$root/linux/bin/moonlight-show-cursor.c" -o "$HOME/.local/lib/moonlight-show-cursor.so" -ldl
config="$HOME/.config/mac-three-screens/config"
legacy="$HOME/.config/mac-three-screens/environment"
if [[ ! -e "$config" ]]; then
  if [[ -e "$legacy" ]] && grep -q '^MAC_MOUSE_BRIDGE_ADDRESS=' "$legacy"; then
    # Older installs kept just the Mac address here.
    sed -e 's/^MAC_MOUSE_BRIDGE_ADDRESS=/MAC_HOST=/' "$legacy" > "$config"
  else
    cp "$root/config.example" "$config"
  fi
  echo "Created $config; set MAC_HOST and your screens in it (see examples/)." >&2
fi
for unit in left center right; do
  rm -f "$HOME/.config/systemd/user/mac-three-screens-$unit.service"
done
"$HOME/.local/bin/mac-three-screens-config" check linux

if [[ "$mode" != --no-start ]]; then
  for variable in DISPLAY XAUTHORITY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS; do
    if [[ -n "${!variable:-}" ]]; then systemctl --user import-environment "$variable"; fi
  done
  systemctl --user daemon-reload
  systemctl --user enable mac-mouse-bridge.service
  systemctl --user restart mac-mouse-bridge.service
fi
echo "Installed Linux source links from $root"
echo "Start the screens with: mac-three-screens start"
